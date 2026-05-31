import Foundation
import MLX

#if os(iOS)
  import os
#endif

/// Pre-flight memory validation for model loading.
///
/// Queries system physical memory and compares against model requirements
/// to determine whether a model can safely be loaded. Also determines the
/// optimal loading strategy based on available memory.
public enum VinetasMemory: Sendable {

  /// Number of bytes per gigabyte (1024^3).
  private static let bytesPerGB: UInt64 = 1_073_741_824

  /// Memory thresholds for loading strategy selection (in bytes).
  private static let sequentialThreshold: UInt64 = 32 * bytesPerGB
  private static let balancedThreshold: UInt64 = 64 * bytesPerGB

  /// The system's total physical memory in bytes.
  public static var systemMemoryBytes: UInt64 {
    ProcessInfo.processInfo.physicalMemory
  }

  /// The system's total physical memory in gigabytes.
  public static var systemMemoryGB: Int {
    Int(systemMemoryBytes / bytesPerGB)
  }

  /// Validates whether the system has sufficient memory for a given model.
  ///
  /// - Parameter model: The model to validate against.
  /// - Returns: `true` if the system has at least the model's minimum required memory.
  public static func validate(for model: VinetasModel) -> Bool {
    let requiredBytes = UInt64(model.minimumMemoryGB) * bytesPerGB
    return systemMemoryBytes >= requiredBytes
  }

  /// Validates whether the given memory amount (in bytes) is sufficient for a model.
  ///
  /// This overload exists for testing with arbitrary memory values.
  ///
  /// - Parameters:
  ///   - model: The model to validate against.
  ///   - availableMemoryBytes: The available memory in bytes to check.
  /// - Returns: `true` if the available memory meets or exceeds the model's requirement.
  public static func validate(for model: VinetasModel, availableMemoryBytes: UInt64) -> Bool {
    let requiredBytes = UInt64(model.minimumMemoryGB) * bytesPerGB
    return availableMemoryBytes >= requiredBytes
  }

  /// Validates whether the system has sufficient memory for a given model descriptor.
  ///
  /// This overload accepts any ``ModelDescriptor`` conforming type, enabling
  /// engine-agnostic memory validation for models described via the engine abstraction.
  ///
  /// - Parameter model: The model descriptor to validate against.
  /// - Returns: `true` if the system has at least the model's minimum required memory.
  public static func validate(for model: any ModelDescriptor) -> Bool {
    let requiredBytes = UInt64(model.minimumMemoryGB) * bytesPerGB
    return systemMemoryBytes >= requiredBytes
  }

  /// Determines the optimal loading strategy for the given memory amount.
  ///
  /// - `"sequential"` — Under 32 GB: load models one at a time, unloading before loading the next.
  /// - `"balanced"` — 32-63 GB: keep the current model loaded, load the next in parallel when possible.
  /// - `"resident"` — 64 GB+: keep all models resident in memory for instant switching.
  ///
  /// - Parameter availableMemoryBytes: The available memory in bytes.
  /// - Returns: A string describing the loading strategy.
  public static func loadingStrategy(availableMemoryBytes: UInt64) -> String {
    if availableMemoryBytes >= balancedThreshold {
      return "resident"
    } else if availableMemoryBytes >= sequentialThreshold {
      return "balanced"
    } else {
      return "sequential"
    }
  }

  /// Determines the optimal loading strategy for the current system.
  ///
  /// - Returns: A string describing the loading strategy.
  public static func loadingStrategy() -> String {
    loadingStrategy(availableMemoryBytes: systemMemoryBytes)
  }

  /// The minimum memory required for a model, in bytes.
  ///
  /// - Parameter model: The model to query.
  /// - Returns: The required memory in bytes.
  public static func requiredMemoryBytes(for model: VinetasModel) -> UInt64 {
    UInt64(model.minimumMemoryGB) * bytesPerGB
  }

  // MARK: - iOS MLX Budget API

  /// The number of bytes available to this process before jetsam, as reported
  /// by `os_proc_available_memory()`.
  ///
  /// Returns a positive `UInt64` on iOS (the per-process jetsam cap minus
  /// current footprint). Returns `nil` on macOS, where there is no per-process
  /// jetsam cap and the concept does not apply.
  public static var processAvailableMemoryBytes: UInt64? {
    #if os(iOS)
      let available = os_proc_available_memory()
      guard available > 0 else { return nil }
      return UInt64(available)
    #else
      return nil
    #endif
  }

  /// Configures MLX's memory and cache limits for the current process based on
  /// the available per-process memory reported by the OS.
  ///
  /// On iOS, this sets `MLX.Memory.memoryLimit` to `availableBytes * safetyFraction`
  /// and `MLX.Memory.cacheLimit` to `cacheLimitBytes`, causing MLX to
  /// self-throttle before reaching the jetsam cap.
  ///
  /// On macOS this function is a no-op — macOS does not impose a per-process
  /// jetsam cap, and macOS memory behavior is intentionally left unmodified.
  ///
  /// - Parameters:
  ///   - availableBytes: The process-available memory in bytes. Defaults to
  ///     ``processAvailableMemoryBytes``. Pass an explicit value in tests.
  ///   - safetyFraction: Fraction of `availableBytes` to allow MLX to use
  ///     (default 0.8 — leaves a 20 % buffer before the jetsam cap).
  ///   - cacheLimitBytes: Hard cap on MLX's buffer cache (default 32 MiB).
  public static func configureMLXBudgetForCurrentProcess(
    availableBytes: UInt64? = processAvailableMemoryBytes,
    safetyFraction: Double = 0.8,
    cacheLimitBytes: Int = 32 * 1_048_576
  ) {
    #if os(iOS)
      guard let available = availableBytes, available > 0 else { return }
      Memory.memoryLimit = Int(Double(available) * safetyFraction)
      Memory.cacheLimit = cacheLimitBytes
    #endif
  }

  /// Releases MLX's buffer cache immediately.
  ///
  /// Calls `MLX.Memory.clearCache()`, which frees all cached (but not
  /// actively used) Metal buffers back to the system allocator. Safe to call
  /// on both iOS and macOS.
  public static func releaseMLXCache() {
    Memory.clearCache()
  }
}

import Foundation
import MLX
import Testing

@testable import SwiftVinetas

@Suite("VinetasMemory Tests")
struct VinetasMemoryTests {

  // MARK: - Constants

  private static let bytesPerGB: UInt64 = 1_073_741_824

  // MARK: - Klein 4B Memory Validation (16 GB threshold)

  @Test("Klein 4B passes validation with exactly 16 GB")
  func klein4bExactly16GB() {
    let result = VinetasMemory.validate(
      for: .klein4b,
      availableMemoryBytes: 16 * Self.bytesPerGB
    )
    #expect(result == true)
  }

  @Test("Klein 4B passes validation with 32 GB")
  func klein4bWith32GB() {
    let result = VinetasMemory.validate(
      for: .klein4b,
      availableMemoryBytes: 32 * Self.bytesPerGB
    )
    #expect(result == true)
  }

  @Test("Klein 4B fails validation with 8 GB")
  func klein4bWith8GB() {
    let result = VinetasMemory.validate(
      for: .klein4b,
      availableMemoryBytes: 8 * Self.bytesPerGB
    )
    #expect(result == false)
  }

  @Test("Klein 4B fails validation with 15 GB")
  func klein4bWith15GB() {
    let result = VinetasMemory.validate(
      for: .klein4b,
      availableMemoryBytes: 15 * Self.bytesPerGB
    )
    #expect(result == false)
  }

  // MARK: - Klein 9B Memory Validation (24 GB threshold)

  @Test("Klein 9B passes validation with exactly 24 GB")
  func klein9bExactly24GB() {
    let result = VinetasMemory.validate(
      for: .klein9b,
      availableMemoryBytes: 24 * Self.bytesPerGB
    )
    #expect(result == true)
  }

  @Test("Klein 9B passes validation with 64 GB")
  func klein9bWith64GB() {
    let result = VinetasMemory.validate(
      for: .klein9b,
      availableMemoryBytes: 64 * Self.bytesPerGB
    )
    #expect(result == true)
  }

  @Test("Klein 9B fails validation with 16 GB")
  func klein9bWith16GB() {
    let result = VinetasMemory.validate(
      for: .klein9b,
      availableMemoryBytes: 16 * Self.bytesPerGB
    )
    #expect(result == false)
  }

  @Test("Klein 9B fails validation with 23 GB")
  func klein9bWith23GB() {
    let result = VinetasMemory.validate(
      for: .klein9b,
      availableMemoryBytes: 23 * Self.bytesPerGB
    )
    #expect(result == false)
  }

  // MARK: - Cross-model: 16 GB is sufficient for Klein 4B but not Klein 9B

  @Test("16 GB is sufficient for Klein 4B but insufficient for Klein 9B")
  func memoryDiscriminatesBetweenModels() {
    let sixteenGB = 16 * Self.bytesPerGB
    #expect(VinetasMemory.validate(for: .klein4b, availableMemoryBytes: sixteenGB) == true)
    #expect(VinetasMemory.validate(for: .klein9b, availableMemoryBytes: sixteenGB) == false)
  }

  // MARK: - Loading Strategy Selection

  @Test("Sequential strategy for less than 32 GB")
  func sequentialStrategyUnder32GB() {
    let strategy = VinetasMemory.loadingStrategy(availableMemoryBytes: 16 * Self.bytesPerGB)
    #expect(strategy == "sequential")
  }

  @Test("Sequential strategy for 24 GB")
  func sequentialStrategy24GB() {
    let strategy = VinetasMemory.loadingStrategy(availableMemoryBytes: 24 * Self.bytesPerGB)
    #expect(strategy == "sequential")
  }

  @Test("Balanced strategy for 32 GB")
  func balancedStrategy32GB() {
    let strategy = VinetasMemory.loadingStrategy(availableMemoryBytes: 32 * Self.bytesPerGB)
    #expect(strategy == "balanced")
  }

  @Test("Balanced strategy for 48 GB")
  func balancedStrategy48GB() {
    let strategy = VinetasMemory.loadingStrategy(availableMemoryBytes: 48 * Self.bytesPerGB)
    #expect(strategy == "balanced")
  }

  @Test("Resident strategy for 64 GB")
  func residentStrategy64GB() {
    let strategy = VinetasMemory.loadingStrategy(availableMemoryBytes: 64 * Self.bytesPerGB)
    #expect(strategy == "resident")
  }

  @Test("Resident strategy for 128 GB")
  func residentStrategy128GB() {
    let strategy = VinetasMemory.loadingStrategy(availableMemoryBytes: 128 * Self.bytesPerGB)
    #expect(strategy == "resident")
  }

  // MARK: - System Memory

  @Test("System memory is nonzero")
  func systemMemoryNonzero() {
    #expect(VinetasMemory.systemMemoryBytes > 0)
  }

  @Test("System memory in GB is positive")
  func systemMemoryGBPositive() {
    #expect(VinetasMemory.systemMemoryGB > 0)
  }

  @Test("System validate returns a Bool for current system")
  func systemValidateReturnsBool() {
    // This just verifies the API works on the current system
    let result = VinetasMemory.validate(for: .klein4b)
    #expect(type(of: result) == Bool.self)
  }

  @Test("Loading strategy returns a non-empty string for current system")
  func systemLoadingStrategy() {
    let strategy = VinetasMemory.loadingStrategy()
    #expect(!strategy.isEmpty)
    #expect(["sequential", "balanced", "resident"].contains(strategy))
  }

  // MARK: - Required Memory Bytes

  @Test("Required memory bytes for Klein 4B is 16 GB in bytes")
  func requiredBytesKlein4b() {
    let required = VinetasMemory.requiredMemoryBytes(for: .klein4b)
    #expect(required == 16 * Self.bytesPerGB)
  }

  @Test("Required memory bytes for Klein 9B is 24 GB in bytes")
  func requiredBytesKlein9b() {
    let required = VinetasMemory.requiredMemoryBytes(for: .klein9b)
    #expect(required == 24 * Self.bytesPerGB)
  }
}

// MARK: - VinetasMemory iOS MLX Budget API Tests

@Suite("VinetasMemory MLX Budget Tests")
struct VinetasMemoryMLXBudgetTests {

  // MARK: - configureMLXBudgetForCurrentProcess

  @Test("configureMLXBudgetForCurrentProcess sets expected memoryLimit and cacheLimit on iOS")
  func budgetClampSetsLimits() {
    // Guard: os(iOS) for the feature boundary; !targetEnvironment(simulator) because
    // MLX's Metal backend does not fully initialize on the iOS Simulator (the default
    // Metal device name is nil on the simulator, causing a C++ nullptr crash inside
    // mlx_set_memory_limit/mlx_set_cache_limit). The production path runs on real
    // Apple Silicon iOS devices where Metal initializes correctly.
    #if os(iOS) && !targetEnvironment(simulator)
      // Snapshot current process-global MLX statics so we can restore them.
      let savedMemoryLimit = Memory.memoryLimit
      let savedCacheLimit = Memory.cacheLimit
      defer {
        Memory.memoryLimit = savedMemoryLimit
        Memory.cacheLimit = savedCacheLimit
      }

      let availableBytes: UInt64 = 4 * 1_073_741_824  // 4 GiB — deterministic injected value
      let safetyFraction: Double = 0.8
      let cacheLimitBytes: Int = 32 * 1_048_576  // 32 MiB

      VinetasMemory.configureMLXBudgetForCurrentProcess(
        availableBytes: availableBytes,
        safetyFraction: safetyFraction,
        cacheLimitBytes: cacheLimitBytes
      )

      let expectedMemoryLimit = Int(Double(availableBytes) * safetyFraction)
      #expect(Memory.memoryLimit == expectedMemoryLimit)
      #expect(Memory.cacheLimit == cacheLimitBytes)
    #endif
  }

  @Test("configureMLXBudgetForCurrentProcess is a no-op when availableBytes is nil")
  func budgetClampNoopsOnNil() {
    #if os(iOS) && !targetEnvironment(simulator)
      let savedMemoryLimit = Memory.memoryLimit
      let savedCacheLimit = Memory.cacheLimit
      defer {
        Memory.memoryLimit = savedMemoryLimit
        Memory.cacheLimit = savedCacheLimit
      }

      // Set known baseline so we can confirm no change.
      let baseline = 2 * 1_073_741_824  // 2 GiB
      Memory.memoryLimit = baseline

      VinetasMemory.configureMLXBudgetForCurrentProcess(availableBytes: nil)

      #expect(Memory.memoryLimit == baseline)
    #endif
  }

  @Test("configureMLXBudgetForCurrentProcess is a no-op when availableBytes is 0")
  func budgetClampNoopsOnZero() {
    #if os(iOS) && !targetEnvironment(simulator)
      let savedMemoryLimit = Memory.memoryLimit
      let savedCacheLimit = Memory.cacheLimit
      defer {
        Memory.memoryLimit = savedMemoryLimit
        Memory.cacheLimit = savedCacheLimit
      }

      let baseline = 2 * 1_073_741_824
      Memory.memoryLimit = baseline

      VinetasMemory.configureMLXBudgetForCurrentProcess(availableBytes: 0)

      #expect(Memory.memoryLimit == baseline)
    #endif
  }

  // MARK: - processAvailableMemoryBytes

  @Test("processAvailableMemoryBytes returns nil on macOS")
  func processAvailableMemoryBytesIsNilOnMacOS() {
    #if !os(iOS)
      #expect(VinetasMemory.processAvailableMemoryBytes == nil)
    #endif
  }

}

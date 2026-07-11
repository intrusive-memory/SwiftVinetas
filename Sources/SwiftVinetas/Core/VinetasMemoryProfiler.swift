import Foundation
import os

#if canImport(Darwin)
  import Darwin
  import MachO
#endif

/// A phase-aware, jetsam-survivable memory profiler for generation runs.
///
/// `VinetasMemoryProfiler` samples the two numbers that actually matter on iOS —
/// the process **resident footprint** (`phys_footprint`, the value Jetsam
/// watches) and the **per-process available memory** (`os_proc_available_memory`,
/// the headroom before the jetsam kill) — on a background loop, stamping each
/// sample with a caller-supplied phase label. It exists to answer one question:
/// *"how does resident footprint move through the load → encode → denoise →
/// decode phases, and how close does it get to the jetsam cap?"*
///
/// ## Why `os_log`
/// The whole point of profiling PixArt on iPad is that the process is **killed**
/// mid-run. Any results held only in memory die with it. So every sample is
/// emitted through `os_log` (unified logging), which is flushed out of the
/// process and survives the kill — retrievable afterwards from the paired Mac
/// with Console.app or `log collect`. A fsync'd CSV is written in parallel for
/// convenient offline analysis when the run *does* survive (Simulator / macOS).
///
/// ## Usage
/// ```swift
/// let profiler = VinetasMemoryProfiler(runLabel: "pixart-sigma-512")
/// profiler.start()
/// profiler.mark("load")
/// try await engine.loadModel(model) { p in profiler.mark("load:\(p.phase)") }
/// profiler.mark("generate:encode")
/// _ = try await engine.generate(request: req) { step, total, _ in
///   profiler.mark(step >= total ? "generate:decode" : "denoise:\(step)/\(total)")
/// }
/// let report = profiler.stop()
/// print(report.formattedSummary())
/// ```
///
/// The instance is safe to `mark(_:)` from any task/thread while the background
/// sampler runs; internal state is guarded by an unfair lock.
public final class VinetasMemoryProfiler: @unchecked Sendable {

  /// One point-in-time reading of process memory, stamped with the active phase.
  public struct Sample: Sendable {
    /// Milliseconds since ``start()`` (monotonic clock).
    public let elapsedMs: Double
    /// The phase label active when this sample was taken.
    public let phase: String
    /// Resident footprint (`phys_footprint`) in bytes — what Jetsam watches.
    public let residentBytes: UInt64
    /// Per-process memory available before jetsam, in bytes. 0 on macOS.
    public let availableBytes: UInt64
  }

  /// The result of a profiling run: the full sample timeline plus derived peaks.
  public struct Report: Sendable {
    public let runLabel: String
    public let samples: [Sample]
    /// Peak resident footprint observed across the whole run, in bytes.
    public let peakResidentBytes: UInt64
    /// Minimum per-process available memory observed, in bytes (0 on macOS).
    public let minAvailableBytes: UInt64
    /// Highest resident footprint reached within each phase, in first-seen order.
    public let phasePeaks: [(phase: String, peakResidentBytes: UInt64)]
    /// Memory-pressure events (warning/critical) captured during the run.
    public let pressureEvents: [(elapsedMs: Double, level: String)]
    /// Path to the streamed CSV, if file output was enabled.
    public let csvURL: URL?
  }

  // MARK: - Configuration

  private let runLabel: String
  private let intervalNanos: UInt64
  private let log: Logger
  private let csvURL: URL?

  // MARK: - Guarded state

  private struct State {
    var currentPhase = "init"
    var samples: [Sample] = []
    var peakResident: UInt64 = 0
    var minAvailable: UInt64 = .max
    // Ordered phase → peak, keeping first-seen order for a readable timeline.
    var phaseOrder: [String] = []
    var phasePeak: [String: UInt64] = [:]
    var pressureEvents: [(Double, String)] = []
    var running = false
  }
  private let state = OSAllocatedUnfairLock(initialState: State())

  private var samplerTask: Task<Void, Never>?
  private var pressureSource: DispatchSourceMemoryPressure?
  private var csvHandle: FileHandle?
  private var startTime = DispatchTime.now()
  private var samplesSinceSync = 0

  /// Create a profiler.
  ///
  /// - Parameters:
  ///   - runLabel: A short identifier for this run, used in logs and the CSV name.
  ///   - intervalMs: Sampling period in milliseconds (default 50 ms). Reads are
  ///     cheap (`task_info` is microseconds) so 50 ms is comfortable; drop to
  ///     20 ms to resolve a fast decode spike.
  ///   - csvDirectory: Directory to stream the CSV into. Pass `nil` to disable
  ///     file output and rely solely on `os_log`. Defaults to a `SwiftVinetasDebug`
  ///     folder (Desktop on macOS, temp dir on iOS).
  public init(
    runLabel: String,
    intervalMs: Double = 50,
    csvDirectory: URL? = VinetasMemoryProfiler.defaultDebugDirectory
  ) {
    self.runLabel = runLabel
    self.intervalNanos = UInt64(max(1, intervalMs) * 1_000_000)
    self.log = Logger(subsystem: "productions.intrusive-memory.vinetas", category: "memprofile")

    if let dir = csvDirectory {
      let safe = runLabel.replacingOccurrences(of: "/", with: "-")
      self.csvURL = dir.appendingPathComponent("memprofile-\(safe).csv")
    } else {
      self.csvURL = nil
    }
  }

  /// Default debug directory: `~/Desktop/SwiftVinetasDebug` on macOS, the temp
  /// directory on iOS (where a device host app can later read it back).
  public static var defaultDebugDirectory: URL {
    #if os(macOS)
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/SwiftVinetasDebug")
    #else
      URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SwiftVinetasDebug")
    #endif
  }

  // MARK: - Lifecycle

  /// Begin sampling. Idempotent — a second call while running is a no-op.
  public func start() {
    let alreadyRunning = state.withLock { s -> Bool in
      if s.running { return true }
      s.running = true
      return false
    }
    guard !alreadyRunning else { return }

    startTime = DispatchTime.now()
    openCSV()
    installPressureSource()

    log.notice("memprofile start run=\(self.runLabel, privacy: .public)")

    samplerTask = Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        self.takeSample()
        try? await Task.sleep(nanoseconds: self.intervalNanos)
        if self.state.withLock({ !$0.running }) { break }
      }
    }
  }

  /// Set the active phase label. Cheap and thread-safe — call it liberally from
  /// progress/step callbacks. The next sample (and all until the following
  /// `mark`) carries this label. Also takes an immediate sample so phase
  /// boundaries are captured even between sampler ticks.
  public func mark(_ phase: String) {
    state.withLock { s in
      s.currentPhase = phase
      if s.phasePeak[phase] == nil {
        s.phaseOrder.append(phase)
        s.phasePeak[phase] = 0
      }
    }
    takeSample()
  }

  /// Stop sampling, flush the CSV, and return the assembled ``Report``.
  /// Idempotent — safe to call from a `defer`.
  @discardableResult
  public func stop() -> Report {
    let wasRunning = state.withLock { s -> Bool in
      let prev = s.running
      s.running = false
      return prev
    }
    if wasRunning {
      takeSample()  // final reading at the true end of the run
    }
    samplerTask?.cancel()
    samplerTask = nil
    pressureSource?.cancel()
    pressureSource = nil
    try? csvHandle?.synchronize()
    try? csvHandle?.close()
    csvHandle = nil

    let report = state.withLock { s in
      Report(
        runLabel: runLabel,
        samples: s.samples,
        peakResidentBytes: s.peakResident,
        minAvailableBytes: s.minAvailable == .max ? 0 : s.minAvailable,
        phasePeaks: s.phaseOrder.map { ($0, s.phasePeak[$0] ?? 0) },
        pressureEvents: s.pressureEvents.map { (elapsedMs: $0.0, level: $0.1) },
        csvURL: csvURL
      )
    }
    if wasRunning {
      log.notice(
        "memprofile stop run=\(self.runLabel, privacy: .public) peak=\(report.peakResidentBytes / 1_048_576)MB samples=\(report.samples.count)"
      )
    }
    return report
  }

  // MARK: - Sampling

  private func takeSample() {
    let resident = Self.residentFootprintBytes()
    let available = Self.processAvailableBytes()
    let elapsedMs =
      Double(DispatchTime.now().uptimeNanoseconds &- startTime.uptimeNanoseconds) / 1_000_000

    let phase = state.withLock { s -> String in
      let phase = s.currentPhase
      s.samples.append(
        Sample(
          elapsedMs: elapsedMs, phase: phase, residentBytes: resident,
          availableBytes: available))
      if resident > s.peakResident { s.peakResident = resident }
      if available > 0, available < s.minAvailable { s.minAvailable = available }
      if resident > (s.phasePeak[phase] ?? 0) { s.phasePeak[phase] = resident }
      return phase
    }

    // Unified logging — survives a jetsam kill, retrievable via Console/log collect.
    log.notice(
      "memprofile run=\(self.runLabel, privacy: .public) t=\(Int(elapsedMs))ms phase=\(phase, privacy: .public) phys=\(resident / 1_048_576)MB avail=\(available / 1_048_576)MB"
    )

    writeCSVRow(elapsedMs: elapsedMs, phase: phase, resident: resident, available: available)
  }

  // MARK: - Memory readings

  /// Resident footprint (`phys_footprint`) of this process in bytes — the number
  /// Jetsam and `MLX.Memory.memoryLimit` actually watch. Returns 0 on failure.
  public static func residentFootprintBytes() -> UInt64 {
    #if canImport(Darwin)
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
      )
      let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      guard kr == KERN_SUCCESS else { return 0 }
      return UInt64(info.phys_footprint)
    #else
      return 0
    #endif
  }

  /// Per-process memory available before jetsam in bytes (iOS only; 0 on macOS).
  public static func processAvailableBytes() -> UInt64 {
    #if os(iOS)
      let available = os_proc_available_memory()
      return available > 0 ? UInt64(available) : 0
    #else
      return 0
    #endif
  }

  // MARK: - Memory pressure

  private func installPressureSource() {
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical], queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in
      guard let self else { return }
      let data = source.data
      let level = data.contains(.critical) ? "critical" : "warning"
      let elapsedMs =
        Double(DispatchTime.now().uptimeNanoseconds &- self.startTime.uptimeNanoseconds)
        / 1_000_000
      let resident = Self.residentFootprintBytes()
      self.state.withLock { $0.pressureEvents.append((elapsedMs, level)) }
      self.log.error(
        "memprofile PRESSURE run=\(self.runLabel, privacy: .public) t=\(Int(elapsedMs))ms level=\(level, privacy: .public) phys=\(resident / 1_048_576)MB"
      )
    }
    source.resume()
    pressureSource = source
  }

  // MARK: - CSV streaming

  private func openCSV() {
    guard let csvURL else { return }
    let fm = FileManager.default
    try? fm.createDirectory(
      at: csvURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    fm.createFile(atPath: csvURL.path, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: csvURL) else { return }
    let header = "elapsed_ms,phase,resident_bytes,resident_mb,available_bytes,available_mb\n"
    try? handle.write(contentsOf: Data(header.utf8))
    csvHandle = handle
  }

  private func writeCSVRow(
    elapsedMs: Double, phase: String, resident: UInt64, available: UInt64
  ) {
    guard let csvHandle else { return }
    let row =
      "\(String(format: "%.1f", elapsedMs)),\(phase),\(resident),\(resident / 1_048_576),\(available),\(available / 1_048_576)\n"
    try? csvHandle.write(contentsOf: Data(row.utf8))
    samplesSinceSync += 1
    if samplesSinceSync >= 10 {
      samplesSinceSync = 0
      try? csvHandle.synchronize()  // fsync so a jetsam kill keeps the tail
    }
  }
}

extension VinetasMemoryProfiler.Report {

  /// A human-readable one-screen summary: peaks, jetsam headroom, and the
  /// resident-footprint trajectory by phase. This is the artifact to read after
  /// a run to see whether the text encoder stayed resident through the loop.
  public func formattedSummary() -> String {
    let mb: (UInt64) -> String = { "\($0 / 1_048_576) MB" }
    var lines: [String] = []
    lines.append("══════════════════════════════════════════════════")
    lines.append("Memory profile — \(runLabel)")
    lines.append("══════════════════════════════════════════════════")
    lines.append("Samples:          \(samples.count)")
    lines.append("Peak resident:    \(mb(peakResidentBytes))")
    if minAvailableBytes > 0 {
      lines.append("Min avail (jetsam headroom): \(mb(minAvailableBytes))")
    }
    if !pressureEvents.isEmpty {
      let summary = pressureEvents.map { "\($0.level)@\(Int($0.elapsedMs))ms" }.joined(
        separator: ", ")
      lines.append("Memory pressure:  \(summary)")
    }
    lines.append("")
    lines.append("Resident footprint peak by phase:")
    for (phase, peak) in phasePeaks {
      lines.append(String(format: "  %-24@ %@", phase as NSString, mb(peak) as NSString))
    }
    if let csvURL {
      lines.append("")
      lines.append("CSV timeline: \(csvURL.path)")
    }
    lines.append("══════════════════════════════════════════════════")
    return lines.joined(separator: "\n")
  }
}

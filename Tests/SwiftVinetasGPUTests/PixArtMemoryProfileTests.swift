import Foundation
import Testing

@testable import SwiftVinetas

/// Memory-profiling harness for the PixArt-Sigma generation pipeline.
///
/// This is a **diagnostic**, not a pass/fail test. It wraps a single PixArt run
/// in a ``VinetasMemoryProfiler`` that samples resident footprint
/// (`phys_footprint`) and per-process jetsam headroom (`os_proc_available_memory`)
/// every 50 ms, labelling each sample with the active phase (load:T5 →
/// load:DiT → load:VAE → encode → denoise:N → decode). It answers the question
/// behind the iPad OOM: *does the ~1.2 GB T5-XXL text encoder stay resident
/// through the denoise loop?* As of SwiftTuberia 0.7.9 (REQ-MEM-01) it no longer
/// does — the encoder is freed after the encode phase, so the profile should show
/// resident footprint dropping ~1.2 GB at the encode→denoise boundary. Run it
/// against the pre-0.7.9 pipeline to see the flat ~1.6 GB baseline that OOM'd.
///
/// Every sample is emitted via `os_log`, so on a **physical iPad** the timeline
/// survives a jetsam kill and can be pulled from the paired Mac:
///
/// ```
/// # stream live while the run executes on the device:
/// log stream --device --predicate 'subsystem == "productions.intrusive-memory.vinetas"' --style compact
///
/// # or collect after a kill and inspect offline:
/// log collect --device --last 10m --output pixart.logarchive
/// log show pixart.logarchive --predicate 'category == "memprofile"' --style compact
/// ```
///
/// On macOS / Simulator the run completes and a summary + CSV are written to
/// `~/Desktop/SwiftVinetasDebug/` (macOS) or the temp dir (iOS).
///
/// Run with:
///   make profile-pixart-memory
///
/// Or selectively (macOS):
///   xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS' \
///     -only-testing:SwiftVinetasGPUTests/PixArtMemoryProfileTests
@Suite("PixArt Memory Profile", .tags(.integration, .pixart), .serialized)
struct PixArtMemoryProfileTests {

  @Test(
    "PixArt-Sigma memory profile — resident footprint by phase",
    .tags(.integration, .pixart),
    .timeLimit(.minutes(15))
  )
  func profileSingleGeneration() async throws {
    let model = PixArtModelDescriptor.sigmaXL

    // Availability check — skip cleanly if weights are not present on this device.
    let engine = try await VinetasClient.shared.router.engine(for: model)
    guard await engine.isAvailable(model) else {
      Issue.record(
        "PixArt model '\(model.displayName)' not downloaded — cannot profile. On device, run generation once from the host app to fetch weights first."
      )
      return
    }

    let profiler = VinetasMemoryProfiler(runLabel: "pixart-sigma-512")
    profiler.start()
    var report: VinetasMemoryProfiler.Report?
    defer {
      // Assemble + flush + print exactly once, whether the run completed or
      // threw. On a jetsam kill this never runs, but os_log already has the tail.
      let final = report ?? profiler.stop()
      print(final.formattedSummary())
    }

    print("── PixArt memory profile: loading model ──")
    profiler.mark("load")
    try await engine.loadModel(model) { progress in
      // progress.phase names the component being loaded (encoder → backbone → decoder).
      profiler.mark("load:\(progress.phase)")
    }

    let request = GenerationRequest(
      prompt: "A red car parked on a cobblestone street",
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    print("── PixArt memory profile: generating (\(model.defaultSteps) steps) ──")
    // The window from here to the first step callback is text encoding (T5).
    profiler.mark("generate:encode")
    let result = try await engine.generate(request: request) { step, total, _ in
      // Last step fired → the denoise loop is done and VAE decode is imminent.
      profiler.mark(step >= total ? "generate:decode" : "denoise:\(step)/\(total)")
    }

    print(
      "── PixArt memory profile: complete (\(String(format: "%.1f", result.durationSeconds))s) ──")

    // No content assertion — this is a diagnostic. The `defer` prints the summary.
    let assembled = profiler.stop()
    report = assembled
    #expect(assembled.peakResidentBytes > 0, "profiler should have captured at least one reading")
  }
}

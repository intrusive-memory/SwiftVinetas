import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

/// Diagnostic test suite for characterising intermittent PixArt garbage output.
///
/// Generates **five** images across different seeds, saves every result — good or
/// garbage — to `~/Desktop/SwiftVinetasDebug/` with timestamped filenames, then
/// prints a summary table with quality metrics.
///
/// **No assertion is made about image content.** The goal is to gather observable
/// data so that a developer or agent can inspect what the engine actually produced
/// and identify the failure mode.
///
/// Run with:
///   make test-pixart-repro
///
/// Or selectively:
///   xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS' \
///     -only-testing:SwiftVinetasGPUTests/PixArtGarbageReproTests
///
/// After running, find all outputs at:
///   ~/Desktop/SwiftVinetasDebug/
@Suite("PixArt Garbage Repro", .tags(.integration, .pixart), .serialized)
struct PixArtGarbageReproTests {

  /// Seeds to use across the five attempts.
  private let seeds: [UInt64] = [42, 43, 44, 45, 46]

  /// Output directory on the desktop for immediate human or agent inspection.
  private var debugDir: URL {
    #if os(macOS)
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/SwiftVinetasDebug")
    #else
      URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SwiftVinetasDebug")
    #endif
  }

  // MARK: - Repeated generation diagnostic

  /// Generates PixArt-Sigma XL five times across seeds 42–46, saving every
  /// output image and JSON sidecar to `~/Desktop/SwiftVinetasDebug/`.
  ///
  /// The test prints a summary table of quality metrics after all attempts
  /// complete. Inspect the saved PNGs alongside this table to build intuition
  /// about what "good" vs "garbage" outputs look like.
  @Test(
    "PixArt five-seed sweep — save all outputs for inspection",
    .tags(.integration, .pixart),
    .timeLimit(.minutes(45))
  )
  func fiveSeedSweep() async throws {
    let model = PixArtModelDescriptor.sigmaXL

    // Memory check
    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    if case .insufficient(let req, let avail) = memValidation {
      Issue.record(
        "Insufficient memory: \(req / 1_073_741_824) GB required, \(avail / 1_073_741_824) GB available"
      )
      return
    }

    // Model availability check
    let engine = try await VinetasClient.shared.router.engine(for: model)
    guard await engine.isAvailable(model) else {
      Issue.record("PixArt model '\(model.displayName)' not downloaded — run Checkpoint 2 first")
      return
    }

    // Prepare output directory
    try FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)

    // Timestamp prefix so multiple runs don't overwrite each other
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let runTimestamp = formatter.string(from: Date())
      .replacingOccurrences(of: ":", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "+0000", with: "Z")

    print("")
    print("══════════════════════════════════════════════════")
    print("PixArt Garbage Repro — \(seeds.count) attempts")
    print("Output dir: \(debugDir.path)")
    print("Run timestamp: \(runTimestamp)")
    print("══════════════════════════════════════════════════")
    print("")

    // Load model once, generate multiple times
    try await engine.loadModel(model, progress: { _ in })

    struct AttemptRecord {
      let attempt: Int
      let seed: UInt64
      let metrics: ImageQualityMetrics
      let durationSeconds: Double
      let pngFilename: String
      let threw: Bool
    }
    var records: [AttemptRecord] = []

    for (i, seed) in seeds.enumerated() {
      let attempt = i + 1
      let baseName = String(format: "pixart-%@-attempt%02d-seed%d", runTimestamp, attempt, seed)
      let pngURL = debugDir.appendingPathComponent("\(baseName).png")
      let jsonURL = debugDir.appendingPathComponent("\(baseName).json")

      print("── Attempt \(attempt)/\(seeds.count)  seed=\(seed) ──────────────────────")

      let request = GenerationRequest(
        prompt: "A red car parked on a cobblestone street",
        steps: model.defaultSteps,
        guidanceScale: model.defaultGuidance,
        seed: seed,
        width: 512,
        height: 512,
        mode: .textToImage
      )

      let result: GenerationResult
      do {
        result = try await engine.generate(request: request, stepProgress: nil)
      } catch {
        print("  ERROR: \(error)")
        records.append(
          AttemptRecord(
            attempt: attempt, seed: seed,
            metrics: ImageQualityMetrics(
              width: 0, height: 0,
              isAllBlack: true, isAllWhite: false,
              distinctColors5x5: 0, distinctColors10x10: 0,
              meanLuminance: 0, stdLuminance: 0,
              meanRed: 0, meanGreen: 0, meanBlue: 0,
              computedAt: formatter.string(from: Date())
            ),
            durationSeconds: 0,
            pngFilename: "(error — not saved)",
            threw: true
          )
        )
        continue
      }

      let metrics = computeMetrics(for: result.image)

      // Save PNG
      if let pngData = ImageOutput.pngData(from: result.image) {
        try pngData.write(to: pngURL, options: .atomic)
        print("  PNG:  \(pngURL.lastPathComponent)")
      } else {
        print("  WARNING: PNG encoding failed — image not saved")
      }

      // Save JSON sidecar
      let info = FixtureGenerationInfo(
        prompt: request.prompt,
        modelID: result.modelID,
        seed: result.seed,
        steps: request.steps,
        guidanceScale: request.guidanceScale,
        width: request.width,
        height: request.height,
        durationSeconds: result.durationSeconds,
        generatedAt: formatter.string(from: Date())
      )
      let sidecar = FixtureSidecar(generation: info, metrics: metrics)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      if let jsonData = try? encoder.encode(sidecar) {
        try? jsonData.write(to: jsonURL, options: .atomic)
      }

      // Print per-attempt metrics
      print("  size:           \(metrics.width)×\(metrics.height)")
      print(
        "  distinctColors: 5×5=\(metrics.distinctColors5x5)  10×10=\(metrics.distinctColors10x10)")
      print(
        "  luminance:      mean=\(String(format: "%.1f", metrics.meanLuminance))  std=\(String(format: "%.1f", metrics.stdLuminance))"
      )
      print(
        "  channels:       R=\(String(format: "%.1f", metrics.meanRed))  G=\(String(format: "%.1f", metrics.meanGreen))  B=\(String(format: "%.1f", metrics.meanBlue))"
      )
      print("  allBlack=\(metrics.isAllBlack)  allWhite=\(metrics.isAllWhite)")
      print("  duration:       \(String(format: "%.1f", result.durationSeconds))s")

      let obs = metricObservations(metrics)
      obs.forEach { print("  \($0)") }
      print("")

      records.append(
        AttemptRecord(
          attempt: attempt, seed: seed,
          metrics: metrics,
          durationSeconds: result.durationSeconds,
          pngFilename: pngURL.lastPathComponent,
          threw: false
        )
      )
    }

    // Summary table
    print("")
    print("══════════════════ SUMMARY ════════════════════════")
    print(
      String(
        format: "  %-4s %-6s %-10s %-11s %-9s %-7s %-7s %-8s",
        "#", "seed", "dist5x5", "dist10x10", "meanLuma", "stdLuma", "black", "threw"
      ))
    print("  " + String(repeating: "─", count: 60))
    for r in records {
      let m = r.metrics
      print(
        String(
          format: "  %-4d %-6d %-10d %-11d %-9.1f %-7.1f %-7s %-8s",
          r.attempt, r.seed,
          m.distinctColors5x5, m.distinctColors10x10,
          m.meanLuminance, m.stdLuminance,
          m.isAllBlack ? "YES" : "no",
          r.threw ? "YES" : "no"
        ))
    }
    print("")
    print("All outputs saved to: \(debugDir.path)")
    print("══════════════════════════════════════════════════")
    print("")
  }
}

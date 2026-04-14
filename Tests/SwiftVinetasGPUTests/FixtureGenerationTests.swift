import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

/// Generates reference fixture images saved to `Fixtures/generations/` for
/// visual inspection and metric calibration.
///
/// Each run **overwrites** the previous fixture so you always see the current
/// engine state. Alongside every PNG a `.json` sidecar is written with the
/// generation parameters and computed quality metrics (see `ImageQualityReport.swift`).
///
/// **No assertions are made about image content.** The test can only fail if
/// the engine throws (crash, OOM) or PNG writing fails. Quality judgement is
/// left to the developer or an agent reading the saved files.
///
/// Run with:
///   make test-fixtures
///
/// Or selectively:
///   xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS' \
///     -only-testing:SwiftVinetasGPUTests/FixtureGenerationTests
///
/// After running, inspect the output files at:
///   Tests/SwiftVinetasGPUTests/Fixtures/generations/
@Suite("Fixture Generation", .tags(.integration), .serialized)
struct FixtureGenerationTests {

  // MARK: - Shared helpers

  /// Absolute path to `Fixtures/generations/`, resolved at compile time from
  /// the location of this source file.
  private var generationsDir: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // .../SwiftVinetasGPUTests/
      .appendingPathComponent("Fixtures/generations")
  }

  /// Saves a PNG and a JSON sidecar to `generationsDir` and prints metric observations.
  private func saveFixture(
    named baseName: String,
    result: GenerationResult,
    request: GenerationRequest
  ) throws {
    let dir = generationsDir
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let pngURL = dir.appendingPathComponent("\(baseName).png")
    let jsonURL = dir.appendingPathComponent("\(baseName).json")

    try ImageOutput.writePNG(image: result.image, to: pngURL)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]

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

    let metrics = computeMetrics(for: result.image)
    let sidecar = FixtureSidecar(generation: info, metrics: metrics)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(sidecar)
    try data.write(to: jsonURL, options: .atomic)

    // Print enough detail to assess quality from the test log alone
    print("")
    print("── \(baseName) ──────────────────────────────────")
    print("  PNG:  \(pngURL.path)")
    print("  JSON: \(jsonURL.path)")
    print("  size:           \(metrics.width)×\(metrics.height)")
    print("  distinctColors: 5×5=\(metrics.distinctColors5x5)  10×10=\(metrics.distinctColors10x10)")
    print("  luminance:      mean=\(String(format: "%.1f", metrics.meanLuminance))  std=\(String(format: "%.1f", metrics.stdLuminance))")
    print("  channels:       R=\(String(format: "%.1f", metrics.meanRed))  G=\(String(format: "%.1f", metrics.meanGreen))  B=\(String(format: "%.1f", metrics.meanBlue))")
    print("  allBlack=\(metrics.isAllBlack)  allWhite=\(metrics.isAllWhite)")
    print("  duration:       \(String(format: "%.1f", result.durationSeconds))s")

    let obs = metricObservations(metrics)
    if obs.isEmpty {
      print("  (no metric observations — image may be acceptable)")
    } else {
      obs.forEach { print("  \($0)") }
    }
    print("")
  }

  // MARK: - PixArt fixture

  /// Generates a single PixArt-Sigma XL image (seed 42, 512×512) and saves it
  /// to `Fixtures/generations/pixart-seed42.png`.
  ///
  /// Skips gracefully if the model is not downloaded or memory is insufficient.
  @Test(
    "Generate PixArt-Sigma XL fixture (seed 42)",
    .tags(.integration, .pixart),
    .timeLimit(.minutes(10))
  )
  func generatePixArtFixture() async throws {
    let model = PixArtModelDescriptor.sigmaXL

    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    if case .insufficient(let req, let avail) = memValidation {
      Issue.record(
        "Insufficient memory: \(req / 1_073_741_824) GB required, \(avail / 1_073_741_824) GB available — skipping"
      )
      return
    }

    let engine = try await VinetasClient.shared.router.engine(for: model)
    guard engine.isAvailable(model) else {
      Issue.record("PixArt model '\(model.displayName)' not on disk — run Checkpoint 2 first")
      return
    }

    try await engine.loadModel(model, progress: { _ in })

    let request = GenerationRequest(
      prompt: "A red car parked on a cobblestone street",
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    let result = try await engine.generate(request: request, stepProgress: nil)
    try saveFixture(named: "pixart-seed42", result: result, request: request)
  }

  // MARK: - Flux2 fixture

  /// Generates a single Flux2 Klein 4B image (seed 42, 512×512) and saves it
  /// to `Fixtures/generations/flux2-seed42.png`.
  ///
  /// Skips gracefully if the model is not downloaded or memory is insufficient.
  @Test(
    "Generate Flux2 Klein 4B fixture (seed 42)",
    .tags(.integration, .flux2),
    .timeLimit(.minutes(10))
  )
  func generateFlux2Fixture() async throws {
    let model = Flux2ModelDescriptor.klein4B

    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    if case .insufficient(let req, let avail) = memValidation {
      Issue.record(
        "Insufficient memory: \(req / 1_073_741_824) GB required, \(avail / 1_073_741_824) GB available — skipping"
      )
      return
    }

    let engine = try await VinetasClient.shared.router.engine(for: model)
    guard engine.isAvailable(model) else {
      Issue.record("Flux2 Klein 4B '\(model.displayName)' not on disk — run Checkpoint 2 first")
      return
    }

    try await engine.loadModel(model, progress: { _ in })

    let request = GenerationRequest(
      prompt: "A red car parked on a cobblestone street",
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    let result = try await engine.generate(request: request, stepProgress: nil)
    try saveFixture(named: "flux2-seed42", result: result, request: request)
  }
}

import CoreGraphics
import Foundation
import PixArtBackbone
import SwiftAcervo
import Testing
import Tuberia
import TuberiaCatalog

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

  /// Prompt used by every fixture generator. Overridable via `make test-fixtures PROMPT="..."`,
  /// which sets `VINETAS_FIXTURE_PROMPT` (xcodebuild strips the `TEST_RUNNER_` prefix).
  private static let fixturePrompt: String = {
    let env = ProcessInfo.processInfo.environment["VINETAS_FIXTURE_PROMPT"]
    if let env, !env.isEmpty { return env }
    return "A red car parked on a cobblestone street"
  }()

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
    if obs.isEmpty {
      print("  (no metric observations — image may be acceptable)")
    } else {
      obs.forEach { print("  \($0)") }
    }
    print("")
  }

  // MARK: - PixArt fixture

  /// Generates a single PixArt-Sigma XL image (seed 42, 512×512) and saves it
  /// to `Fixtures/generations/pixart-seed42.png` (int4) or
  /// `Fixtures/generations/pixart-seed42-fp16.png` (fp16, for quantization comparison).
  ///
  /// Set the environment variable `PIXART_PRECISION=fp16` (via `make test-fixtures-fp16`)
  /// to load the fp16 DiT weights instead of the int4 weights. The fp16 weights must be
  /// generated first by running `scripts/dequantize_dit_to_fp16.py`.
  ///
  /// Skips gracefully if the required model weights are not on disk.
  @Test(
    "Generate PixArt-Sigma XL fixture (seed 42)",
    .tags(.integration, .pixart),
    .timeLimit(.minutes(60))
  )
  func generatePixArtFixture() async throws {
    let useFP16 = ProcessInfo.processInfo.environment["PIXART_PRECISION"] == "fp16"

    if useFP16 {
      try await generatePixArtFixtureFP16()
    } else {
      try await generatePixArtFixtureInt4()
    }
  }

  /// Generates the int4 PixArt fixture using the default `PixArtRecipe`.
  private func generatePixArtFixtureInt4() async throws {
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

    // NOTE: This model requires 1024×1024 (its native training resolution) to generate
    // coherent images. At 512×512, the position-embedding grid is too small relative to
    // the 1024px training base and produces colored noise instead of recognizable content.
    // 1024×1024 takes ~2 min and peaks at ~22 GB GPU; confirm sufficient memory first.
    let request = GenerationRequest(
      prompt: Self.fixturePrompt,
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 1024,
      height: 1024,
      mode: .textToImage
    )

    let result = try await engine.generate(request: request, stepProgress: nil)
    try saveFixture(named: "pixart-seed42", result: result, request: request)
  }

  /// Generates the fp16 PixArt fixture using `PixArtFP16Recipe`.
  ///
  /// Assembles the pipeline directly from `PixArtFP16Recipe` because `PixArtEngine`
  /// hardcodes `PixArtRecipe`. The fp16 DiT weights must exist at:
  ///   `$VINETAS_TEST_MODELS_DIR/pixart-sigma-xl-dit-fp16/model.safetensors`
  ///
  /// Produce them first with:
  ///   `python3 /Users/stovak/Projects/pixart-swift-mlx/scripts/dequantize_dit_to_fp16.py`
  private func generatePixArtFixtureFP16() async throws {
    // Ensure fp16 component is registered in CatalogRegistration
    _ = PixArtComponents.registered

    // The fp16 weights are produced locally by dequantize_dit_to_fp16.py and placed
    // directly in the test models dir — they are not in the App Group container.
    // Check for the safetensors file in the VINETAS_TEST_MODELS_DIR directly.
    let testModelsDir =
      ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"]
      ?? "/tmp/vinetas-test-models"
    let fp16SafetensorsPath =
      "\(testModelsDir)/pixart-sigma-xl-dit-fp16/model.safetensors"
    guard FileManager.default.fileExists(atPath: fp16SafetensorsPath) else {
      Issue.record(
        "fp16 DiT weights not found at \(fp16SafetensorsPath) — run: python3 /Users/stovak/Projects/pixart-swift-mlx/scripts/dequantize_dit_to_fp16.py"
      )
      return
    }

    let recipe = PixArtFP16Recipe()

    // Bridge CatalogRegistration → Acervo ComponentRegistry so that WeightLoader's
    // withModelAccess(componentId) can resolve component IDs to their repo paths.
    // This mirrors the bridge in PixArtEngine.loadModel.
    let catalogRegistry = CatalogRegistration.shared
    for componentId in recipe.allComponentIds {
      guard Acervo.component(componentId) == nil,
        let catalogDescriptor = catalogRegistry.descriptor(for: componentId)
      else { continue }
      let descriptor = SwiftAcervo.ComponentDescriptor(
        id: catalogDescriptor.id,
        type: .backbone,
        displayName: catalogDescriptor.id,
        repoId: catalogDescriptor.repoId,
        minimumMemoryBytes: 0
      )
      Acervo.register(descriptor)
    }

    // Assemble the pipeline (same type as PixArtEngine's internal pipeline)
    let pipeline:
      DiffusionPipeline<T5XXLEncoder, DPMSolverScheduler, PixArtDiT, SDXLVAEDecoder, ImageRenderer>
    do {
      pipeline = try .init(recipe: recipe)
    } catch {
      throw error
    }

    try await pipeline.loadModels { fraction, component in
      print("[fp16 fixture] Loading \(component) (\(Int(fraction * 100))%)")
    }
    defer { Task { await pipeline.unloadModels() } }

    let diffusionRequest = DiffusionGenerationRequest(
      prompt: Self.fixturePrompt,
      negativePrompt: nil,
      width: 512,
      height: 512,
      steps: PixArtFP16Recipe.defaultSteps,
      guidanceScale: PixArtFP16Recipe.defaultGuidanceScale,
      seed: UInt32(42),
      loRA: nil
    )

    let startTime = Date()
    let diffusionResult = try await pipeline.generate(request: diffusionRequest) { _ in }
    let duration = Date().timeIntervalSince(startTime)

    guard case .image(let cgImage) = diffusionResult.output else {
      throw VinetasError.generationFailed("fp16 pipeline returned unexpected output type")
    }

    let result = GenerationResult(
      image: cgImage,
      usedPrompt: diffusionRequest.prompt,
      seed: UInt64(diffusionResult.seed),
      durationSeconds: duration,
      modelID: "pixart-sigma-xl-fp16"
    )
    let request = GenerationRequest(
      prompt: diffusionRequest.prompt,
      steps: PixArtFP16Recipe.defaultSteps,
      guidanceScale: PixArtFP16Recipe.defaultGuidanceScale,
      seed: 42,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    try saveFixture(named: "pixart-seed42-fp16", result: result, request: request)
  }

  // MARK: - Flux2 fixture

  /// Generates a single Flux2 Klein 4B image (seed 42, 512×512) and saves it
  /// to `Fixtures/generations/flux2-seed42.png`.
  ///
  /// Skips gracefully if the model is not downloaded or memory is insufficient.
  @Test(
    "Generate Flux2 Klein 4B fixture (seed 42)",
    .tags(.integration, .flux2),
    .timeLimit(.minutes(60))
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
      prompt: Self.fixturePrompt,
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

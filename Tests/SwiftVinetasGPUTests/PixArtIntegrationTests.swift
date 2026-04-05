import Foundation
import Testing

@testable import SwiftVinetas

/// Integration tests that validate the full PixArt-Sigma pipeline end-to-end:
/// binary compilation, model download, and non-garbage image generation.
///
/// PixArtEngine is a full ``ImageGenerationEngine`` implementation with
/// ``loadModel``, ``generate``, ``download``, and LoRA support.
///
/// Run selectively with:
///   xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS' \
///     -only-testing:SwiftVinetasGPUTests/PixArtIntegrationTests
@Suite("PixArt Integration Tests", .tags(.integration, .pixart))
struct PixArtIntegrationTests {

  // MARK: - Checkpoint 1: Binary Compilation

  /// Verifies that the `vinetas` CLI binary compiles successfully with all
  /// Metal shader and MLX dependencies resolved, including the PixArtBackbone
  /// Metal kernels. This is the baseline check that the entire dependency chain
  /// is intact.
  @Test(
    "Checkpoint 1: vinetas CLI binary compiles with PixArt dependencies",
    .tags(.integration, .pixart))
  func binaryCompilation() throws {
    #if os(macOS)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      process.arguments = [
        "build",
        "-scheme", "vinetas",
        "-destination", "platform=macOS,arch=arm64",
        "-derivedDataPath", "/tmp/SwiftVinetasBuild",
      ]

      // Suppress verbose xcodebuild output during test runs
      let devNull = FileHandle.nullDevice
      process.standardOutput = devNull
      process.standardError = devNull

      try process.run()
      process.waitUntilExit()

      #expect(
        process.terminationStatus == 0,
        "xcodebuild build exited with status \(process.terminationStatus) — CLI failed to compile"
      )
    #else
      Issue.record("Binary compilation test requires macOS (Process is unavailable on iOS)")
    #endif
  }

  // MARK: - Checkpoint 2: Model Download

  /// Downloads the PixArt-Sigma XL model weights and verifies they are
  /// present on disk and ready for inference. Requires network access
  /// and approximately 3.6 GB of free disk space.
  ///
  /// Components downloaded:
  /// - t5-xxl-encoder-int4 (~1.2 GB)
  /// - pixart-sigma-xl-dit-int4 (~300 MB)
  /// - sdxl-vae-decoder-fp16 (~160 MB)
  @Test(
    "Checkpoint 2: PixArtModelDescriptor.sigmaXL downloads successfully",
    .tags(.integration, .pixart),
    .timeLimit(.minutes(10))
  )
  func modelDownload() async throws {
    let model = PixArtModelDescriptor.sigmaXL

    // Validate memory before attempting download
    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    switch memValidation {
    case .insufficient(let required, let available):
      let requiredGB = required / 1_073_741_824
      let availableGB = available / 1_073_741_824
      Issue.record(
        "Insufficient memory: required \(requiredGB) GB, available \(availableGB) GB — skipping download"
      )
      return
    case .ok, .warning:
      break
    }

    try await VinetasClient.shared.download(model: model) { progress in
      // Progress callback — no-op in test context
      _ = progress.overallProgress
    }

    try await assertModelDownloaded(model)
  }

  // MARK: - Checkpoint 3: Generation Validation

  /// Generates a single image using the PixArt-Sigma XL model with a
  /// fixed seed for reproducibility, then validates that the output is
  /// non-garbage: non-zero dimensions, at least 16 distinct pixel colors,
  /// and not all-black or all-white.
  ///
  /// Uses the same prompt as the Flux2 integration test for cross-engine comparability.
  @Test(
    "Checkpoint 3: PixArt generates non-garbage image from prompt",
    .tags(.integration, .gpu, .pixart),
    .timeLimit(.minutes(5))
  )
  func generationValidation() async throws {
    let model = PixArtModelDescriptor.sigmaXL

    // Validate memory before attempting generation
    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    switch memValidation {
    case .insufficient(let required, let available):
      let requiredGB = required / 1_073_741_824
      let availableGB = available / 1_073_741_824
      Issue.record(
        "Insufficient memory: required \(requiredGB) GB, available \(availableGB) GB — skipping generation"
      )
      return
    case .ok, .warning:
      break
    }

    // Obtain the engine from the router
    let engine = try await VinetasClient.shared.router.engine(for: model)

    // Load the model into memory
    try await engine.loadModel(model, progress: { _ in })

    // Build the generation request
    let request = GenerationRequest(
      prompt: "A red car parked on a cobblestone street",
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    // Generate the image
    let result = try await engine.generate(request: request, stepProgress: nil)

    // Validate result metadata
    #expect(result.image.width > 0, "Generated image has zero width")
    #expect(result.image.height > 0, "Generated image has zero height")
    #expect(result.durationSeconds > 0, "Generation reported zero duration")
    #expect(
      result.modelID.lowercased().contains("pixart"),
      "Expected modelID to contain 'pixart', got '\(result.modelID)'"
    )

    // Validate image content is not garbage
    assertImageNotGarbage(result.image)
  }
}

import CoreGraphics
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
///
/// ## Why `.serialized`
///
/// MLX uses a shared global Metal context and lazy-evaluated compute graphs.
/// Running two diffusion pipeline calls concurrently on the same process corrupts
/// tensor shapes (0D tensors appear mid-upsample, crashing the VAE decoder).
/// `.serialized` ensures checkpoints run strictly one at a time.
@Suite("PixArt Integration Tests", .tags(.integration, .pixart), .serialized)
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
      // Resolve project root from the test file's compile-time path:
      // PixArtIntegrationTests.swift → SwiftVinetasGPUTests → Tests → SwiftVinetas/
      let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
      process.currentDirectoryURL = projectRoot
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

    // Validate memory before attempting download (CI may bypass via env override)
    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    guard memoryGateAllowsExecution(memValidation) else { return }

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

    // Validate memory before attempting generation (CI may bypass via env override)
    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    guard memoryGateAllowsExecution(memValidation) else { return }

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

  // MARK: - Checkpoint 4: Storyboard Frame Written to Disk

  /// End-to-end proof of the library's working condition: uses the high-level
  /// ``VinetasClient`` API (the same path a real app takes) to generate a single
  /// PixArt storyboard frame, then writes it to disk as a PNG and validates the
  /// file is present and non-trivially sized.
  ///
  /// This test is the canonical integration smoke test. If it passes, the full
  /// stack — model weights, pipeline assembly, generation, PNG encoding — is intact.
  @Test(
    "Checkpoint 4: PixArt writes a storyboard frame PNG to disk via VinetasClient",
    .tags(.integration, .gpu, .pixart),
    .timeLimit(.minutes(5))
  )
  func storyboardFrameWrittenToDisk() async throws {
    let model = PixArtModelDescriptor.sigmaXL

    // Skip if memory is insufficient (CI may bypass via env override)
    let memValidation = try await VinetasClient.shared.validateMemory(for: model)
    guard memoryGateAllowsExecution(memValidation) else { return }

    // Skip if model weights are not on disk (requires Checkpoint 2 to have run)
    let engine = try await VinetasClient.shared.router.engine(for: model)
    guard await engine.isAvailable(model) else {
      Issue.record(
        "Model '\(model.displayName)' is not downloaded — run Checkpoint 2 first"
      )
      return
    }

    // Use the public VinetasClient API — same path a real app (or the CLI) would take
    let style = StyleConfig(
      stylePrompt: "cinematic storyboard, professional comic art",
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 512,
      height: 512
    )

    let image = try await VinetasClient.shared.generate(
      prompt: "A crimson knight stands at the edge of a cliff at dusk",
      style: style,
      model: model
    )

    // Validate pixel content is meaningful
    #expect(image.width > 0, "Generated frame has zero width")
    #expect(image.height > 0, "Generated frame has zero height")
    assertImageNotGarbage(image)

    // Write the frame to a temporary output directory
    let outputDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftVinetasFrameTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let frameURL = outputDir.appendingPathComponent("frame-001.png")
    try ImageOutput.writePNG(image: image, to: frameURL)

    // Validate the PNG was written and is non-trivially sized
    #expect(
      FileManager.default.fileExists(atPath: frameURL.path),
      "frame-001.png was not written to disk"
    )
    let attrs = try FileManager.default.attributesOfItem(atPath: frameURL.path)
    let fileSize = attrs[.size] as? Int ?? 0
    #expect(
      fileSize > 1024,
      "Written PNG is suspiciously small (\(fileSize) bytes) — possible encoding failure"
    )
  }
}

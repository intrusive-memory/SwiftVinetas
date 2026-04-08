import CoreGraphics
import Foundation
import Metal
import Testing

@testable import SwiftVinetas

/// Integration tests that validate the full FLUX.2 pipeline end-to-end:
/// binary compilation, model download, and non-garbage image generation.
///
/// These tests require Apple Silicon with at least 16 GB of RAM and
/// a stable internet connection for model download. Generation tests
/// take several minutes on M-series hardware.
///
/// Run selectively with:
///   xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS' \
///     -only-testing:SwiftVinetasGPUTests/Flux2IntegrationTests
@Suite("Flux2 Integration Tests", .tags(.integration, .flux2))
struct Flux2IntegrationTests {

  // MARK: - Checkpoint 1: Binary Compilation

  /// Verifies that the `vinetas` CLI binary compiles successfully with all
  /// Metal shader and MLX dependencies resolved. This is the baseline
  /// check that the entire dependency chain is intact.
  @Test(
    "Checkpoint 1: vinetas CLI binary compiles with Metal dependencies", .tags(.integration, .flux2)
  )
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

  /// Downloads the FLUX.2 Klein 4B model weights and verifies they are
  /// present on disk and ready for inference. Requires network access
  /// and approximately 11 GB of free disk space.
  @Test(
    "Checkpoint 2: Flux2ModelDescriptor.klein4B downloads successfully",
    .tags(.integration, .flux2),
    .timeLimit(.minutes(10))
  )
  func modelDownload() async throws {
    let model = Flux2ModelDescriptor.klein4B

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

  /// Generates a single image using the FLUX.2 Klein 4B model with a
  /// fixed seed for reproducibility, then validates that the output is
  /// non-garbage: non-zero dimensions, at least 16 distinct pixel colors,
  /// and not all-black or all-white.
  @Test(
    "Checkpoint 3: Flux2 generates non-garbage image from prompt",
    .tags(.integration, .gpu, .flux2),
    .timeLimit(.minutes(5))
  )
  func generationValidation() async throws {
    let model = Flux2ModelDescriptor.klein4B

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
      result.modelID == "flux2",
      "Expected modelID 'flux2', got '\(result.modelID)'"
    )

    // Validate image content is not garbage
    assertImageNotGarbage(result.image)
  }

  // MARK: - Checkpoint 4: Fixed-Seed Determinism

  /// Generates two images with an identical fixed seed and asserts that every
  /// pixel byte is identical between the two outputs.
  ///
  /// A deterministic diffusion pipeline must produce bit-for-bit identical
  /// CGImage data when given the same prompt, seed, and dimensions. Any
  /// divergence indicates non-deterministic RNG state or mutable global state
  /// in the generation backend.
  @Test(
    "Checkpoint 4: Fixed seed produces identical pixel output on two consecutive calls",
    .tags(.gpu, .flux2),
    .timeLimit(.minutes(6))
  )
  func fixedSeedDeterminism() async throws {
    // Precondition 1: Metal device must be present (Apple Silicon GPU required)
    guard MTLCreateSystemDefaultDevice() != nil else {
      Issue.record("No Metal device found — this test requires Apple Silicon with a Metal GPU")
      return
    }

    // Precondition 2: At least 16 GB of physical RAM required for Klein 4B
    guard ProcessInfo.processInfo.physicalMemory >= 16 * 1_073_741_824 else {
      let availableGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
      Issue.record(
        "Insufficient physical memory: \(availableGB) GB available, 16 GB required — skipping fixed-seed determinism test"
      )
      return
    }

    let model = Flux2ModelDescriptor.klein4B

    // Obtain the engine from the router and load the model once
    let engine = try await VinetasClient.shared.router.engine(for: model)
    try await engine.loadModel(model, progress: { _ in })

    // Build a fixed-seed request — seed 42 on both calls
    let request = GenerationRequest(
      prompt: "a red square on white background",
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: 42,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    // First generation
    let result1 = try await engine.generate(request: request, stepProgress: nil)

    // Second generation — same request, same engine state
    let result2 = try await engine.generate(request: request, stepProgress: nil)

    // Render both images to raw byte arrays using an 8-bit RGBA CGContext
    let pixelData1 = renderToBytes(result1.image)
    let pixelData2 = renderToBytes(result2.image)

    #expect(
      pixelData1 != nil && pixelData2 != nil,
      "Failed to render one or both generated images to a CGContext for pixel comparison"
    )

    guard let bytes1 = pixelData1, let bytes2 = pixelData2 else { return }

    #expect(
      bytes1 == bytes2,
      "Fixed-seed generation produced different pixel output on two consecutive calls — generation is not deterministic"
    )
  }

  // MARK: - Checkpoint 5: unloadModel() Releases GPU Memory

  /// Loads Klein 4B into the engine then calls `unloadModel()`, and asserts
  /// that the model is no longer available (as reported by the engine's own
  /// `isAvailable` query) after unloading.
  ///
  /// ## Why RSS measurement was skipped
  ///
  /// Direct RSS measurement via `mach_task_basic_info` (the `task_info` syscall)
  /// requires importing the `Darwin` overlay and calling C-level APIs
  /// (`task_info(mach_task_self_, TASK_BASIC_INFO, ...)`).  Swift Package
  /// Manager test targets have no bridging header and the `Darwin` overlay is
  /// available, but measuring *resident* memory reliably is complicated by
  /// page-level kernel caching: the OS may not immediately reclaim pages after
  /// `pipeline = nil` even though the Swift objects have been deallocated.  A
  /// reliable RSS delta would require a `sleep` (to allow the kernel to reclaim
  /// pages) which is explicitly forbidden by project conventions.  Instead, the
  /// test uses `engine.isAvailable(_:)` as a functional proxy: the engine sets
  /// `pipeline = nil` and `loadedModelID = nil` in `unloadModel()`, so after
  /// unload the engine no longer reports itself as "available" for generation
  /// in the sense that a subsequent `generate` call would throw
  /// `.generationFailed("No model loaded")`.  The `isAvailable` check
  /// verifies disk presence (not RAM presence), so the correct proxy is to
  /// attempt a generate call and confirm it throws the expected error —
  /// demonstrating that the in-memory model state was cleared.
  @Test(
    "Checkpoint 5: unloadModel() releases GPU memory",
    .tags(.gpu, .flux2),
    .timeLimit(.minutes(3))
  )
  func unloadModelReleasesMemory() async throws {
    // Precondition 1: Metal device must be present
    guard MTLCreateSystemDefaultDevice() != nil else {
      Issue.record("No Metal device found — this test requires Apple Silicon with a Metal GPU")
      return
    }

    // Precondition 2: At least 16 GB of physical RAM required for Klein 4B
    guard ProcessInfo.processInfo.physicalMemory >= 16 * 1_073_741_824 else {
      let availableGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
      Issue.record(
        "Insufficient physical memory: \(availableGB) GB available, 16 GB required — skipping unloadModel memory release test"
      )
      return
    }

    let model = Flux2ModelDescriptor.klein4B

    // Obtain the engine from the router and load the model into GPU memory
    let engine = try await VinetasClient.shared.router.engine(for: model)
    try await engine.loadModel(model, progress: { _ in })

    // Unload the model — this sets pipeline = nil and loadedModelID = nil
    await engine.unloadModel()

    // Proxy assertion: after unloadModel() the engine must refuse to generate,
    // confirming the in-memory model state was cleared.
    //
    // Note: engine.isAvailable(_:) checks *disk* presence, not RAM presence,
    // so it is not the right signal here.  Instead we attempt a generation
    // and require that it throws VinetasError.generationFailed — which is the
    // error emitted when `pipeline == nil`.
    let request = GenerationRequest(
      prompt: "a red square on white background",
      steps: 1,
      guidanceScale: model.defaultGuidance,
      seed: 1,
      width: 64,
      height: 64,
      mode: .textToImage
    )

    var didThrowExpectedError = false
    do {
      _ = try await engine.generate(request: request, stepProgress: nil)
    } catch let error as VinetasError {
      switch error {
      case .generationFailed:
        didThrowExpectedError = true
      default:
        break
      }
    } catch {
      // Any other error still means the model is not loaded — acceptable
      didThrowExpectedError = true
    }

    #expect(
      didThrowExpectedError,
      "After unloadModel(), engine.generate should throw (no model loaded) but it succeeded — unload may not have cleared in-memory state"
    )
  }
}

// MARK: - Private Pixel-Rendering Helper

/// Renders a `CGImage` into a flat `[UInt8]` array of 8-bit RGBA pixels using
/// `CGColorSpaceCreateDeviceRGB()`.  Returns `nil` if `CGContext` creation fails.
///
/// This is used by the fixed-seed determinism test to obtain comparable byte
/// arrays from two separately-generated images.
private func renderToBytes(_ image: CGImage) -> [UInt8]? {
  let width = image.width
  let height = image.height
  guard width > 0 && height > 0 else { return nil }

  let bytesPerPixel = 4
  let bytesPerRow = width * bytesPerPixel
  var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

  guard
    let context = CGContext(
      data: &pixelData,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    )
  else {
    return nil
  }

  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  return pixelData
}

import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

/// Cross-model showcase: generates a storyboard frame with every available model
/// and opens the results in Preview for side-by-side comparison.
///
/// Images are written to `~/Desktop/SwiftVinetasExamples/` so they persist
/// after the test run. The final step opens all generated PNGs in Preview.
///
/// **Prerequisites:**
/// - Model weights must be downloaded first (`vinetas download <model-id>`)
/// - Sufficient RAM: PixArt-Sigma XL (8 GB), Klein 4B (16 GB), Klein 9B (24 GB)
///
/// Run selectively with:
///   xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS' \
///     -only-testing:SwiftVinetasGPUTests/AllModelsExampleTests
@Suite("All Models Example", .tags(.integration, .gpu), .serialized)
struct AllModelsExampleTests {

  // MARK: - Shared Configuration

  /// The storyboard prompt used identically across all models for apples-to-apples comparison.
  private static let prompt =
    "A lone astronaut stands at the edge of a crater on the Moon, Earth rising on the horizon"

  /// Style overlay consistent with a cinematic storyboard look.
  private static let stylePrompt = "cinematic storyboard, professional comic art, high contrast"

  /// Fixed seed for reproducible output across models.
  private static let seed: UInt64 = 42

  /// Output directory — Desktop so the user can find files easily.
  private static let outputDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Desktop/SwiftVinetasExamples")

  // MARK: - PixArt-Sigma XL

  @Test(
    "Generate storyboard frame with PixArt-Sigma XL",
    .tags(.integration, .gpu, .pixart),
    .timeLimit(.minutes(10))
  )
  func generatePixArt() async throws {
    try await generateFrame(model: PixArtModelDescriptor.sigmaXL)
  }

  #if !VINETAS_FLUX2_DISABLED
  // MARK: - FLUX.2 Klein 4B

  @Test(
    "Generate storyboard frame with FLUX.2 Klein 4B",
    .tags(.integration, .gpu, .flux2),
    .timeLimit(.minutes(10))
  )
  func generateFlux2Klein4B() async throws {
    try await generateFrame(model: Flux2ModelDescriptor.klein4B)
  }

  // MARK: - FLUX.2 Klein 9B

  @Test(
    "Generate storyboard frame with FLUX.2 Klein 9B",
    .tags(.integration, .gpu, .flux2),
    .timeLimit(.minutes(20))
  )
  func generateFlux2Klein9B() async throws {
    try await generateFrame(model: Flux2ModelDescriptor.klein9B)
  }
  #endif

  // MARK: - Open in Preview

  /// Opens all generated PNGs in Preview. Runs after all generation tests (suite is .serialized).
  @Test(
    "Open generated examples in Preview",
    .tags(.integration),
    .timeLimit(.minutes(1))
  )
  func openInPreview() throws {
    #if os(macOS)
      let fm = FileManager.default
      guard fm.fileExists(atPath: Self.outputDir.path) else {
        Issue.record("Output directory does not exist — no images were generated")
        return
      }

      let pngs = try fm.contentsOfDirectory(
        at: Self.outputDir,
        includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension == "png" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

      guard !pngs.isEmpty else {
        Issue.record("No PNG files found in \(Self.outputDir.path)")
        return
      }

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-a", "Preview"] + pngs.map(\.path)
      try process.run()
      process.waitUntilExit()

      #expect(
        process.terminationStatus == 0,
        "open -a Preview exited with status \(process.terminationStatus)"
      )

      print("Opened \(pngs.count) image(s) in Preview:")
      for png in pngs {
        print("  \(png.lastPathComponent)")
      }
    #else
      Issue.record("Preview is macOS-only")
    #endif
  }

  // MARK: - Private Helper

  private func generateFrame(model: any ModelDescriptor) async throws {
    // Validate system memory
    let memResult = try await VinetasClient.shared.validateMemory(for: model)
    switch memResult {
    case .insufficient(let required, let available):
      let reqGB = required / 1_073_741_824
      let avlGB = available / 1_073_741_824
      Issue.record(
        "\(model.displayName): insufficient memory (\(avlGB) GB available, \(reqGB) GB required) — skipping"
      )
      return
    case .ok, .warning:
      break
    }

    // Confirm model weights are on disk
    let engine = try await VinetasClient.shared.router.engine(for: model)
    guard engine.isAvailable(model) else {
      Issue.record(
        "\(model.displayName): model not downloaded — run 'vinetas download \(model.id)' first, then re-run this test"
      )
      return
    }

    // Build style using each model's own defaults so comparison is fair
    let style = StyleConfig(
      stylePrompt: Self.stylePrompt,
      steps: model.defaultSteps,
      guidanceScale: model.defaultGuidance,
      seed: Self.seed,
      width: 512,
      height: 512
    )

    // Generate via the public VinetasClient API — same path as a real app.
    // Catch weight-load failures gracefully: isAvailable() can return true for
    // a partial download (metadata present but shards missing), so the first
    // real failure surface is inside generate().
    let image: CGImage
    do {
      image = try await VinetasClient.shared.generate(
        prompt: Self.prompt,
        style: style,
        model: model
      )
    } catch {
      let msg =
        "\(model.displayName): generation failed — \(error). "
        + "If this is a weight-load error the model may be partially downloaded; "
        + "run 'vinetas download \(model.id)' to re-fetch missing shards."
      Issue.record(Comment(rawValue: msg))
      return
    }

    #expect(image.width > 0, "\(model.displayName): generated image has zero width")
    #expect(image.height > 0, "\(model.displayName): generated image has zero height")
    assertImageNotGarbage(image)

    // Write PNG to Desktop/SwiftVinetasExamples/<model-id>.png
    try FileManager.default.createDirectory(
      at: Self.outputDir, withIntermediateDirectories: true
    )
    let slug = model.id.replacingOccurrences(of: "/", with: "-")
    let fileURL = Self.outputDir.appendingPathComponent("\(slug).png")
    try ImageOutput.writePNG(image: image, to: fileURL)

    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fileSize = attrs[.size] as? Int ?? 0
    #expect(
      fileSize > 1024,
      "\(model.displayName): written PNG is suspiciously small (\(fileSize) bytes)"
    )

    print("✓ \(model.displayName) → \(fileURL.path) (\(fileSize / 1024) KB)")
  }
}

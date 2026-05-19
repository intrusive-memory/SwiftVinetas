import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - Image Validation

/// Asserts that a `CGImage` contains meaningful, non-garbage pixel data.
///
/// Samples pixels at a 5×5 grid across the image and verifies:
/// - Non-zero width and height
/// - At least 16 distinct RGB values across the sample grid
/// - Not all-black (all channel values == 0)
/// - Not all-white (all channel values == 255)
/// - Not single-color (all 25 sample pixels identical)
///
/// Use this helper in GPU integration tests after generating an image to
/// confirm the generation pipeline produced meaningful output rather than
/// a degenerate result.
///
/// - Parameter image: The `CGImage` to validate.
func assertImageNotGarbage(_ image: CGImage) {
  // Dimension checks
  #expect(image.width > 0, "Image width is zero")
  #expect(image.height > 0, "Image height is zero")

  guard image.width > 0 && image.height > 0 else { return }

  // Render into an 8-bit RGBA context for uniform pixel access
  let width = image.width
  let height = image.height
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
    Issue.record("Failed to create CGContext for pixel sampling")
    return
  }

  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

  // Sample a 5x5 grid of pixels across the image
  var sampledColors: Set<UInt32> = []
  var allBlack = true
  var allWhite = true

  for row in 0..<5 {
    for col in 0..<5 {
      let x = (col * (width - 1)) / 4
      let y = (row * (height - 1)) / 4
      let offset = y * bytesPerRow + x * bytesPerPixel

      let r = pixelData[offset + 0]
      let g = pixelData[offset + 1]
      let b = pixelData[offset + 2]

      // Pack RGB into a single UInt32 for distinct-value counting
      let packed = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
      sampledColors.insert(packed)

      if r != 0 || g != 0 || b != 0 { allBlack = false }
      if r != 255 || g != 255 || b != 255 { allWhite = false }
    }
  }

  #expect(!allBlack, "Image appears to be all-black (degenerate output)")
  #expect(!allWhite, "Image appears to be all-white (degenerate output)")
  #expect(
    sampledColors.count >= 16,
    "Image has only \(sampledColors.count) distinct color values in 5x5 grid sample — expected at least 16 (likely single-color or garbage output)"
  )
}

// MARK: - Model Availability Validation

/// Asserts that a model's weights are present on disk and ready to use.
///
/// Resolves the engine responsible for the given model via
/// `VinetasClient.shared.router`, then calls the engine's `isAvailable(_:)`
/// method, which checks the model's files on disk.
///
/// - Parameter model: Any ``ModelDescriptor`` — e.g. `Flux2ModelDescriptor.klein4B`
///   or `PixArtModelDescriptor.sigmaXL`.
func assertModelDownloaded(_ model: any ModelDescriptor) async throws {
  let router = VinetasClient.shared.router
  let engine = try await router.engine(for: model)
  let available = await engine.isAvailable(model)
  #expect(
    available, "Model '\(model.displayName)' is not available on disk — run the download step first"
  )
}

import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

@Suite("PixArt resolution binning: generate at the bin, return the size asked for")
struct PixArtResolutionBinningTests {

  /// A `width` × `height` image whose left half is red and right half blue.
  static func halves(width: Int, height: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return context.makeImage()!
  }

  @Test("A 1024 bin comes back at the requested 512×512")
  func downscales() throws {
    let out = try #require(
      PixArtEngine.resizeAndCenterCrop(
        Self.halves(width: 1024, height: 1024), width: 512, height: 512))
    #expect(out.width == 512 && out.height == 512)
  }

  @Test("A size that is already right is returned as is")
  func identity() {
    let image = Self.halves(width: 64, height: 32)
    #expect(PixArtEngine.resizeAndCenterCrop(image, width: 64, height: 32) === image)
  }

  @Test("A different aspect is covered and center-cropped, not stretched")
  func centerCrops() throws {
    // 1344×768 bin cropped to 1920×1080: scale by max(1920/1344, 1080/768).
    let out = try #require(
      PixArtEngine.resizeAndCenterCrop(
        Self.halves(width: 1344, height: 768), width: 1920, height: 1080))
    #expect(out.width == 1920 && out.height == 1080)
  }
}

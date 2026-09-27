import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas

@Suite("ReferenceImageTests")
struct ReferenceImageTests {

  // MARK: - Fixtures (generated in-test)

  /// A solid-color RGBA image of the given size.
  private static func makeImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  /// Encodes a fixture image with ImageIO using the given UTI.
  private static func encode(_ uti: String, width: Int = 64, height: Int = 48) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data as CFMutableData, uti as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, makeImage(width: width, height: height), nil)
    #expect(CGImageDestinationFinalize(dest))
    return data as Data
  }

  /// Writes `data` to a unique temp file and returns its path.
  private static func writeTemp(_ data: Data, ext: String) throws -> String {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ReferenceImageTests-\(UUID().uuidString).\(ext)")
    try data.write(to: url)
    return url.path
  }

  private static var heicEncoderAvailable: Bool {
    let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    return types.contains("public.heic")
  }

  private static func assertDecoded(_ ref: ReferenceImage, path: String, data: Data) {
    #expect(ref.source == .file(path: path))
    #expect(ref.originalSize == ReferenceImage.Size(width: 64, height: 48))
    // 64x48 is under 1024²: floor to 32 → 64x32.
    #expect(ref.effectiveSize == ReferenceImage.Size(width: 64, height: 32))
    #expect(ref.image.width == 64)
    #expect(ref.image.height == 48)
    #expect(ref.sha256 == ReferenceImage.sha256Hex(of: data))
    #expect(ref.sha256.count == 64)
  }

  // MARK: - Decoding

  @Test("decodes a PNG file")
  func decodesPNG() throws {
    let data = Self.encode("public.png")
    let path = try Self.writeTemp(data, ext: "png")
    defer { try? FileManager.default.removeItem(atPath: path) }
    Self.assertDecoded(try ReferenceImage.load(path: path), path: path, data: data)
  }

  @Test("decodes a JPEG file")
  func decodesJPEG() throws {
    let data = Self.encode("public.jpeg")
    let path = try Self.writeTemp(data, ext: "jpg")
    defer { try? FileManager.default.removeItem(atPath: path) }
    Self.assertDecoded(try ReferenceImage.load(path: path), path: path, data: data)
  }

  @Test(
    "decodes a HEIC file",
    .enabled(if: ReferenceImageTests.heicEncoderAvailable, "no HEIC encoder on this runner"))
  func decodesHEIC() throws {
    let data = Self.encode("public.heic")
    let path = try Self.writeTemp(data, ext: "heic")
    defer { try? FileManager.default.removeItem(atPath: path) }
    Self.assertDecoded(try ReferenceImage.load(path: path), path: path, data: data)
  }

  @Test("decodes from data with a stdin source")
  func decodesStdinData() throws {
    let data = Self.encode("public.png")
    let ref = try ReferenceImage.load(data: data, source: .stdin)
    #expect(ref.source == .stdin)
    #expect(ref.source.description == "stdin")
    #expect(ref.originalSize == ReferenceImage.Size(width: 64, height: 48))
  }

  // MARK: - Errors

  @Test("missing file throws referenceNotFound naming the path")
  func missingFile() {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("ReferenceImageTests-missing-\(UUID().uuidString).png").path
    do {
      _ = try ReferenceImage.load(path: path)
      Issue.record("expected referenceNotFound")
    } catch let error as VinetasError {
      guard case .referenceNotFound(let p) = error else {
        Issue.record("wrong error: \(error)")
        return
      }
      #expect(p == path)
      let message = error.localizedDescription
      #expect(message.contains(path))
      #expect(message.contains("not found"))
    } catch {
      Issue.record("unexpected error type: \(error)")
    }
  }

  @Test("zero-byte file throws referenceEmpty naming the path")
  func zeroByteFile() throws {
    let path = try Self.writeTemp(Data(), ext: "png")
    defer { try? FileManager.default.removeItem(atPath: path) }
    do {
      _ = try ReferenceImage.load(path: path)
      Issue.record("expected referenceEmpty")
    } catch let error as VinetasError {
      guard case .referenceEmpty(let source) = error else {
        Issue.record("wrong error: \(error)")
        return
      }
      #expect(source == .file(path: path))
      let message = error.localizedDescription
      #expect(message.contains(path))
      #expect(message.contains("empty"))
    }
  }

  @Test("garbage bytes throw referenceUndecodable naming the path")
  func garbageBytes() throws {
    let garbage = Data("this is definitely not an image, just some text bytes".utf8)
    let path = try Self.writeTemp(garbage, ext: "png")
    defer { try? FileManager.default.removeItem(atPath: path) }
    do {
      _ = try ReferenceImage.load(path: path)
      Issue.record("expected referenceUndecodable")
    } catch let error as VinetasError {
      guard case .referenceUndecodable(let source) = error else {
        Issue.record("wrong error: \(error)")
        return
      }
      #expect(source == .file(path: path))
      let message = error.localizedDescription
      #expect(message.contains(path))
      #expect(message.contains("could not be decoded"))
    }
  }

  @Test("empty stdin data message names stdin")
  func emptyStdin() {
    #expect(throws: VinetasError.self) {
      _ = try ReferenceImage.load(data: Data(), source: .stdin)
    }
    #expect(VinetasError.referenceEmpty(source: .stdin).localizedDescription.contains("stdin"))
    #expect(
      VinetasError.referenceUndecodable(source: .stdin).localizedDescription.contains("stdin"))
  }

  // MARK: - SHA-256

  @Test("sha256 of \"abc\" matches the FIPS 180-2 test vector")
  func sha256OfABC() {
    #expect(
      ReferenceImage.sha256Hex(of: Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  // MARK: - FLUX.2 effective size
  //
  // Expected values derived by hand from flux-2-swift-mlx v3.4.2
  // Flux2Pipeline.swift:2204-2233 (area cap 1024², Int truncation, floor to 32, min 32).

  @Test("effective size 512x512 → 512x512 (under cap, already /32)")
  func effective512() {
    let s = ReferenceImage.flux2EffectiveSize(width: 512, height: 512)
    #expect(s.width == 512 && s.height == 512)
  }

  @Test("effective size 1024x1024 → 1024x1024 (exactly at cap, not scaled)")
  func effective1024() {
    let s = ReferenceImage.flux2EffectiveSize(width: 1024, height: 1024)
    #expect(s.width == 1024 && s.height == 1024)
  }

  @Test("effective size 2048x1024 → 1440x704")
  func effective2048x1024() {
    // scale = sqrt(1048576/2097152) = 0.70710678 → 1448 x 724 → floor32 → 1440 x 704
    let s = ReferenceImage.flux2EffectiveSize(width: 2048, height: 1024)
    #expect(s.width == 1440 && s.height == 704)
  }

  @Test("effective size 3000x2000 → 1248x832")
  func effective3000x2000() {
    // scale = sqrt(1048576/6000000) = 0.41804629 → 1254 x 836 → floor32 → 1248 x 832
    let s = ReferenceImage.flux2EffectiveSize(width: 3000, height: 2000)
    #expect(s.width == 1248 && s.height == 832)
  }

  @Test("effective size 1000x1000 → 992x992 (under cap, floor to 32)")
  func effective1000() {
    let s = ReferenceImage.flux2EffectiveSize(width: 1000, height: 1000)
    #expect(s.width == 992 && s.height == 992)
  }

  @Test("effective size clamps tiny images to 32")
  func effectiveTiny() {
    let s = ReferenceImage.flux2EffectiveSize(width: 10, height: 20)
    #expect(s.width == 32 && s.height == 32)
  }
}

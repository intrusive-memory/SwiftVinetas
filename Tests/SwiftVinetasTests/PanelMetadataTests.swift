import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas

@Suite("PanelMetadataTests")
struct PanelMetadataTests {

  // MARK: - Fixtures

  private static func makeImage(width: Int = 4, height: Int = 3) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
  }

  private static let fullMetadata = ImageOutput.PanelMetadata(
    prompt: "a lighthouse at dusk",
    model: "klein4b",
    seed: 42,
    steps: 4,
    guidance: 1.0,
    width: 1024,
    height: 768,
    durationSeconds: 12.5,
    loras: [
      ImageOutput.LoRAEntry(path: "/tmp/hero.safetensors", scale: 0.8, activationKeyword: "hero")
    ],
    generatedAt: "2026-09-26T12:00:00Z",
    mode: .imageToImage,
    engine: "flux2",
    references: [
      ImageOutput.ReferenceRecord(
        source: "refs/face.png",
        sha256: String(repeating: "ab", count: 32),
        originalWidth: 2048,
        originalHeight: 1536,
        effectiveWidth: 1024,
        effectiveHeight: 768
      )
    ],
    style: "noir",
    composedPrompt: "noir ink style, a lighthouse at dusk",
    negative: "blurry",
    negativeApplied: false
  )

  /// Sidecar JSON exactly as `development` wrote it before the provenance fields existed.
  private static let legacyJSON = """
    {
      "durationSeconds" : 25.5,
      "generatedAt" : "2026-03-09T12:00:00Z",
      "guidance" : 3.5,
      "height" : 1024,
      "loras" : [
        {
          "path" : "\\/tmp\\/test.safetensors",
          "scale" : 0.69999998807907104
        }
      ],
      "model" : "klein4b",
      "prompt" : "a comic panel",
      "seed" : 99999,
      "steps" : 20,
      "width" : 1024
    }
    """

  // MARK: - Tests

  @Test("iTXt round-trip yields an equal PanelMetadata")
  func iTXtRoundTrip() throws {
    let png = try ImageOutput.pngData(image: Self.makeImage(), metadata: Self.fullMetadata)
    let decoded = try #require(ImageOutput.readEmbeddedMetadata(from: png))
    #expect(decoded == Self.fullMetadata)
  }

  @Test("Embedded PNG still decodes with ImageIO")
  func imageIODecodes() throws {
    let png = try ImageOutput.pngData(
      image: Self.makeImage(width: 5, height: 7), metadata: Self.fullMetadata)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 5)
    #expect(image.height == 7)
  }

  @Test("Output starts with the PNG signature")
  func pngSignature() throws {
    let png = try ImageOutput.pngData(image: Self.makeImage(), metadata: Self.fullMetadata)
    #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  }

  @Test("Legacy development-format JSON (no provenance fields) decodes")
  func legacyJSONDecodes() throws {
    let meta = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self, from: Data(Self.legacyJSON.utf8))
    #expect(meta.prompt == "a comic panel")
    #expect(meta.seed == 99999)
    #expect(meta.loras?.first?.path == "/tmp/test.safetensors")
    #expect(meta.mode == nil)
    #expect(meta.engine == nil)
    #expect(meta.references == nil)
    #expect(meta.negativeApplied == nil)
  }

  @Test("iTXt chunk has keyword vinetas, is uncompressed, and sits before IEND")
  func chunkLayout() throws {
    let png = try ImageOutput.pngData(image: Self.makeImage(), metadata: Self.fullMetadata)
    let chunks = ImageOutput.pngChunks(png)
    let itxt = chunks.filter { $0.type == "iTXt" }
    #expect(itxt.count == 1)
    let chunk = try #require(itxt.first)
    #expect(chunks.last?.type == "IEND")
    #expect(chunks[chunks.count - 2].type == "iTXt")

    let bytes = [UInt8](chunk.data)
    let kwEnd = try #require(bytes.firstIndex(of: 0))
    let keyword = String(decoding: bytes[0..<kwEnd], as: UTF8.self)
    #expect(keyword == "vinetas")
    // compression flag, compression method, empty language tag, empty translated keyword
    #expect(Array(bytes[(kwEnd + 1)...(kwEnd + 4)]) == [0, 0, 0, 0])

    // Stored CRC matches CRC-32 over type + data.
    let raw = [UInt8](png)
    let crcOffset = chunk.offset + 8 + chunk.data.count
    let stored =
      UInt32(raw[crcOffset]) << 24 | UInt32(raw[crcOffset + 1]) << 16
      | UInt32(raw[crcOffset + 2]) << 8 | UInt32(raw[crcOffset + 3])
    #expect(stored == ImageOutput.crc32(Array("iTXt".utf8) + bytes))
  }

  @Test("writePanel sidecar bytes equal the embedded JSON bytes")
  func sidecarMatchesEmbedded() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("vinetas-meta-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let output = PanelOutput(
      image: Self.makeImage(),
      prompt: "test prompt",
      seed: 7,
      durationSeconds: 1.5,
      modelID: "klein4b",
      width: 4,
      height: 3
    )
    let pngURL = dir.appendingPathComponent("panel-001.png")
    try ImageOutput.writePanel(
      output, to: pngURL, style: StyleConfig(loraPath: "/tmp/a.safetensors"))

    let png = try Data(contentsOf: pngURL)
    let sidecar = try Data(contentsOf: dir.appendingPathComponent("panel-001.json"))
    let embedded = try #require(ImageOutput.embeddedMetadataJSON(from: png))
    #expect(embedded == sidecar)
    #expect(ImageOutput.readEmbeddedMetadata(from: png)?.seed == 7)
  }

  @Test("CRC-32 of \"123456789\" is 0xCBF43926")
  func crc32CheckValue() {
    #expect(ImageOutput.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
  }

  @Test("readEmbeddedMetadata returns nil for a plain PNG and for non-PNG data")
  func readReturnsNilWithoutChunk() throws {
    let plain = try #require(ImageOutput.pngData(from: Self.makeImage()))
    #expect(ImageOutput.readEmbeddedMetadata(from: plain) == nil)
    #expect(ImageOutput.readEmbeddedMetadata(from: Data("not a png".utf8)) == nil)
  }

  @Test("New optional fields are omitted from JSON when nil")
  func nilFieldsOmitted() throws {
    let legacy = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self, from: Data(Self.legacyJSON.utf8))
    let json = String(decoding: try ImageOutput.metadataJSON(legacy), as: UTF8.self)
    for key in [
      "mode", "engine", "references", "style", "composedPrompt", "negative", "negativeApplied",
    ] {
      #expect(!json.contains("\"\(key)\""))
    }
  }
}

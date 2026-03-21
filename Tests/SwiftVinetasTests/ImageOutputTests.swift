import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - Helpers

/// Creates a minimal 2×2 solid red CGImage for testing.
private func makeMiniRedImage() -> CGImage? {
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
  guard
    let context = CGContext(
      data: nil,
      width: 2,
      height: 2,
      bitsPerComponent: 8,
      bytesPerRow: 8,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    )
  else {
    return nil
  }
  context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
  return context.makeImage()
}

/// Creates a minimal `PanelOutput` for use in tests.
private func makePanelOutput(image: CGImage) -> PanelOutput {
  PanelOutput(
    image: image,
    prompt: "test prompt",
    seed: 12345,
    durationSeconds: 1.23,
    modelID: "klein4b",
    width: 2,
    height: 2
  )
}

// MARK: - Tests

@Suite("ImageOutput Tests")
struct ImageOutputTests {

  // MARK: - PNG Data

  @Test("pngData produces non-empty Data from a valid CGImage")
  func pngDataFromValidImage() {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let data = ImageOutput.pngData(from: image)
    #expect(data != nil)
    #expect((data?.count ?? 0) > 0)
  }

  @Test("pngData starts with PNG magic bytes")
  func pngDataHasPNGSignature() throws {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    guard let data = ImageOutput.pngData(from: image) else {
      Issue.record("pngData returned nil")
      return
    }
    // PNG files always start with the 8-byte signature: 89 50 4E 47 0D 0A 1A 0A
    let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let prefix = Array(data.prefix(8))
    #expect(prefix == pngSignature)
  }

  // MARK: - writePNG

  @Test("writePNG creates a file at the specified URL")
  func writePNGCreatesFile() throws {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("vinetas_test_\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    try ImageOutput.writePNG(image: image, to: tmpURL)

    #expect(FileManager.default.fileExists(atPath: tmpURL.path))
  }

  @Test("writePNG produces a non-empty PNG file")
  func writePNGProducesValidFile() throws {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("vinetas_test_\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    try ImageOutput.writePNG(image: image, to: tmpURL)

    let attrs = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
    let fileSize = attrs[.size] as? Int ?? 0
    #expect(fileSize > 0)
  }

  // MARK: - Metadata Construction

  @Test("metadata(for:style:) captures correct prompt and model")
  func metadataCapture() {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let output = makePanelOutput(image: image)
    let style = StyleConfig(steps: 20, guidanceScale: 3.5)
    let meta = ImageOutput.metadata(for: output, style: style)

    #expect(meta.prompt == "test prompt")
    #expect(meta.model == "klein4b")
    #expect(meta.seed == 12345)
    #expect(meta.steps == 20)
    #expect(meta.guidance == 3.5)
    #expect(meta.width == 2)
    #expect(meta.height == 2)
    #expect(meta.durationSeconds > 0)
    #expect(meta.loras == nil)
  }

  @Test("metadata includes LoRA entry when loraPath is set")
  func metadataWithLoRA() {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let output = makePanelOutput(image: image)
    let style = StyleConfig(loraPath: "/tmp/style.safetensors", loraScale: 0.8)
    let meta = ImageOutput.metadata(for: output, style: style)

    #expect(meta.loras != nil)
    #expect(meta.loras?.count == 1)
    #expect(meta.loras?.first?.path == "/tmp/style.safetensors")
    #expect(meta.loras?.first?.scale == 0.8)
  }

  @Test("metadata generatedAt is a non-empty ISO 8601 string")
  func metadataTimestamp() {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let output = makePanelOutput(image: image)
    let style = StyleConfig()
    let meta = ImageOutput.metadata(for: output, style: style)

    #expect(!meta.generatedAt.isEmpty)
    // ISO 8601 strings always contain 'T' as the date/time separator
    #expect(meta.generatedAt.contains("T"))
  }

  // MARK: - writeMetadata

  @Test("writeMetadata creates a JSON sidecar alongside the PNG")
  func writeMetadataCreatesSidecar() throws {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let baseName = "vinetas_test_\(UUID().uuidString)"
    let pngURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("\(baseName).png")
    let jsonURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("\(baseName).json")
    defer {
      try? FileManager.default.removeItem(at: pngURL)
      try? FileManager.default.removeItem(at: jsonURL)
    }

    let output = makePanelOutput(image: image)
    let style = StyleConfig()

    try ImageOutput.writeMetadata(for: output, to: pngURL, style: style)

    #expect(FileManager.default.fileExists(atPath: jsonURL.path))
  }

  @Test("writeMetadata produces valid JSON decodable as PanelMetadata")
  func writeMetadataProducesValidJSON() throws {
    guard let image = makeMiniRedImage() else {
      Issue.record("Failed to create test CGImage")
      return
    }
    let baseName = "vinetas_test_\(UUID().uuidString)"
    let pngURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("\(baseName).png")
    let jsonURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("\(baseName).json")
    defer {
      try? FileManager.default.removeItem(at: pngURL)
      try? FileManager.default.removeItem(at: jsonURL)
    }

    let output = makePanelOutput(image: image)
    let style = StyleConfig(steps: 10, guidanceScale: 2.0)

    try ImageOutput.writeMetadata(for: output, to: pngURL, style: style)

    let data = try Data(contentsOf: jsonURL)
    let decoded = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: data)

    #expect(decoded.prompt == "test prompt")
    #expect(decoded.model == "klein4b")
    #expect(decoded.seed == 12345)
    #expect(decoded.steps == 10)
  }

  // MARK: - PanelMetadata Codable

  @Test("PanelMetadata codable round-trip")
  func panelMetadataCodableRoundTrip() throws {
    let meta = ImageOutput.PanelMetadata(
      prompt: "a comic panel",
      model: "klein4b",
      seed: 99999,
      steps: 20,
      guidance: 3.5,
      width: 1024,
      height: 1024,
      durationSeconds: 25.5,
      loras: [ImageOutput.LoRAEntry(path: "/tmp/test.safetensors", scale: 0.7)],
      generatedAt: "2026-03-09T12:00:00Z"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(meta)
    let decoded = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: data)

    #expect(decoded.prompt == meta.prompt)
    #expect(decoded.model == meta.model)
    #expect(decoded.seed == meta.seed)
    #expect(decoded.steps == meta.steps)
    #expect(decoded.guidance == meta.guidance)
    #expect(decoded.width == meta.width)
    #expect(decoded.height == meta.height)
    #expect(decoded.durationSeconds == meta.durationSeconds)
    #expect(decoded.generatedAt == meta.generatedAt)
    #expect(decoded.loras?.count == 1)
    #expect(decoded.loras?.first?.path == "/tmp/test.safetensors")
    #expect(decoded.loras?.first?.scale == 0.7)
  }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

/// Sortie 11: `generate` output — `-o -`, embedded metadata, warnings, real
/// duration (RI-10, RI-12, RI-14). Every test routes through the
/// `CLIEnvironment` seam to a `MockEngine` registered as `pixart-sigma` (so
/// `ProGate` never engages) with `skipDownload` set.
@Suite("Generate output (Sortie 11)", .serialized)
struct GenerateOutputTests {

  // MARK: - Fixtures

  private static func makePNGData(width: Int, height: Int) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(
      data as CFMutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest))
    return data as Data
  }

  private static func tempURL(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("GenerateOutputTests-\(UUID().uuidString)\(suffix)")
  }

  private static func runGenerate(_ arguments: [String], engine: MockEngine) async throws {
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$skipDownload.withValue(true) {
        let cmd = try Generate.parse(arguments + ["--model", "pixart-sigma"])
        try await cmd.run()
      }
    }
  }

  /// Runs `body` with CLI stderr bound to a pipe and returns what it wrote.
  /// Touches no process-wide descriptor.
  private static func captureCLIStderr(_ body: () async throws -> Void) async throws -> String {
    let pipe = Pipe()
    var bodyError: Error?
    do {
      try await CLIEnvironment.$stderrDescriptor.withValue(
        pipe.fileHandleForWriting.fileDescriptor
      ) {
        try await body()
      }
    } catch {
      bodyError = error
    }
    try pipe.fileHandleForWriting.close()
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    if let bodyError { throw bodyError }
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: - -o - stream purity

  @Test("-o - writes only a PNG to fd 1; library print() output goes to stderr")
  func streamPurity() async throws {
    let marker = "MOCK-LOG-\(UUID().uuidString)"
    let engine = MockEngine(
      engineID: "pixart-sigma", maxReferenceImages: 3, printOnGenerate: marker)
    let referenceURL = Self.tempURL(".png")
    try Self.makePNGData(width: 40, height: 30).write(to: referenceURL)
    defer { try? FileManager.default.removeItem(at: referenceURL) }
    let expectedSHA = try ReferenceImage.load(path: referenceURL.path).sha256

    let cwd = FileManager.default.currentDirectoryPath
    let dashFile = (cwd as NSString).appendingPathComponent("-")
    let dashSidecar = (cwd as NSString).appendingPathComponent("-.json")
    let dashExistedBefore = FileManager.default.fileExists(atPath: dashFile)

    let result = try await StdioCapture.run {
      try await Self.runGenerate(["prompt", "-r", referenceURL.path, "-o", "-"], engine: engine)
    }
    let out = result.stdout

    // Starts with the PNG signature.
    #expect(out.count > 8)
    #expect(Array(out.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    // Ends exactly at the IEND chunk's CRC: no trailing bytes.
    let chunks = ImageOutput.pngChunks(out)
    let iend = try #require(chunks.last)
    #expect(iend.type == "IEND")
    #expect(iend.offset + 12 == out.count)

    // Decodes as an image.
    let source = try #require(CGImageSourceCreateWithData(out as CFData, nil))
    #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)

    // Embedded metadata records the reference.
    let metadata = try #require(ImageOutput.readEmbeddedMetadata(from: out))
    #expect(metadata.references?.map(\.sha256) == [expectedSHA])
    #expect(metadata.mode == .imageToImage)

    // The engine's print() was diverted to stderr, not stdout.
    let stderrText = String(decoding: result.stderr, as: UTF8.self)
    #expect(stderrText.contains(marker))
    #expect(out.range(of: Data(marker.utf8)) == nil)

    // No file named "-" and no sidecar.
    if !dashExistedBefore {
      #expect(!FileManager.default.fileExists(atPath: dashFile))
    }
    #expect(!FileManager.default.fileExists(atPath: dashSidecar))
    #expect(await engine.generateCallCount == 1)
  }

  // MARK: - Path output: PNG + sidecar with real metadata

  @Test("a path output writes x.png and x.json with the engine's seed and a real duration")
  func pathOutputWritesPNGAndSidecar() async throws {
    let engine = MockEngine(engineID: "pixart-sigma")
    let mockSeed: UInt64 = 987_654_321
    await engine.setGenerateResult(
      GenerationResult(
        image: MockEngine.create1x1Image(), usedPrompt: "prompt", seed: mockSeed,
        durationSeconds: 1.0, modelID: "pixart-sigma"))
    let pngURL = Self.tempURL("/x.png")
    try FileManager.default.createDirectory(
      at: pngURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: pngURL.deletingLastPathComponent()) }
    let jsonURL = pngURL.deletingPathExtension().appendingPathExtension("json")

    _ = try await Self.captureCLIStderr {
      try await Self.runGenerate(["prompt", "-o", pngURL.path], engine: engine)
    }

    #expect(FileManager.default.fileExists(atPath: pngURL.path))
    #expect(FileManager.default.fileExists(atPath: jsonURL.path))
    let json = try Data(contentsOf: jsonURL)
    let sidecar = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: json)
    #expect(sidecar.seed == mockSeed)
    #expect(sidecar.durationSeconds > 0)
    #expect(sidecar.prompt == "prompt")
    #expect(sidecar.engine == "pixart-sigma")

    // The PNG embeds the same metadata as the sidecar.
    let embedded = ImageOutput.readEmbeddedMetadata(from: try Data(contentsOf: pngURL))
    #expect(embedded == sidecar)
  }

  // MARK: - --negative warning

  @Test("--negative on an engine that ignores it prints a warning to stderr")
  func negativeIgnoredWarns() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", supportsNegativePrompt: false)
    let pngURL = Self.tempURL(".png")
    defer {
      try? FileManager.default.removeItem(at: pngURL)
      try? FileManager.default.removeItem(
        at: pngURL.deletingPathExtension().appendingPathExtension("json"))
    }

    let stderrText = try await Self.captureCLIStderr {
      try await Self.runGenerate(
        ["prompt", "--negative", "blurry", "-o", pngURL.path], engine: engine)
    }

    #expect(
      stderrText.contains(
        "warning: pixart-sigma does not apply negative prompts; --negative ignored"))
    let sidecar = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self,
      from: Data(contentsOf: pngURL.deletingPathExtension().appendingPathExtension("json")))
    #expect(sidecar.negative == "blurry")
    #expect(sidecar.negativeApplied == false)
  }

  @Test("--negative on an engine that applies it prints no warning")
  func negativeAppliedNoWarning() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", supportsNegativePrompt: true)
    let pngURL = Self.tempURL(".png")
    defer {
      try? FileManager.default.removeItem(at: pngURL)
      try? FileManager.default.removeItem(
        at: pngURL.deletingPathExtension().appendingPathExtension("json"))
    }

    let stderrText = try await Self.captureCLIStderr {
      try await Self.runGenerate(
        ["prompt", "--negative", "blurry", "-o", pngURL.path], engine: engine)
    }

    #expect(!stderrText.contains("does not apply negative prompts"))
  }

  // MARK: - --lora

  @Test("--lora flows into style.loraPath and is recorded in metadata")
  func loraIsApplied() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", supportsLoRAInference: true)
    let pngURL = Self.tempURL(".png")
    let jsonURL = pngURL.deletingPathExtension().appendingPathExtension("json")
    let loraURL = Self.tempURL(".safetensors")
    try Data([0]).write(to: loraURL)
    defer {
      try? FileManager.default.removeItem(at: pngURL)
      try? FileManager.default.removeItem(at: jsonURL)
      try? FileManager.default.removeItem(at: loraURL)
    }

    _ = try await Self.captureCLIStderr {
      try await Self.runGenerate(
        ["prompt", "--lora", loraURL.path, "--lora-scale", "0.5", "-o", pngURL.path],
        engine: engine)
    }

    #expect(await engine.loadLoRACallCount == 1)
    let sidecar = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self, from: Data(contentsOf: jsonURL))
    #expect(sidecar.loras == [ImageOutput.LoRAEntry(path: loraURL.path, scale: 0.5)])
  }

  @Test("a --lora load failure throws (nonzero exit) and writes no output")
  func loraFailureThrows() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", supportsLoRAInference: true)
    await engine.setLoadLoRAError(VinetasError.modelNotFound("corrupt.safetensors"))
    let pngURL = Self.tempURL(".png")
    let loraURL = Self.tempURL(".safetensors")
    try Data([0]).write(to: loraURL)
    defer { try? FileManager.default.removeItem(at: loraURL) }

    await #expect(throws: VinetasError.self) {
      _ = try await Self.captureCLIStderr {
        try await Self.runGenerate(
          ["prompt", "--lora", loraURL.path, "-o", pngURL.path], engine: engine)
      }
    }
    #expect(await engine.generateCallCount == 0)
    #expect(!FileManager.default.fileExists(atPath: pngURL.path))
  }
}

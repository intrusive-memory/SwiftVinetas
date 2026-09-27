import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

/// Sortie 10: `generate --reference` / `-r` loads and validates reference
/// images before any download or engine call (RI-1 – RI-5). Every test here
/// routes through the `CLIEnvironment` seam to a `MockEngine`, never the real
/// router, and always sets `skipDownload` so no network access happens.
@Suite("Generate --reference validation (Sortie 10)", .serialized)
struct GenerateReferenceValidationTests {

  // MARK: - Fixtures

  /// Encodes a solid-color PNG of the given pixel size.
  private static func makePNGData(width: Int, height: Int) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(
      data as CFMutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
    return data as Data
  }

  /// Writes `data` to a fresh temp file and returns its path. Registers no
  /// cleanup: files land in the system temp directory, which the OS reclaims.
  private static func writeTempFile(_ data: Data) throws -> String {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("GenerateReferenceValidationTests-\(UUID().uuidString).png")
    try data.write(to: url)
    return url.path
  }

  private static func tempOutputPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("GenerateReferenceValidationTests-out-\(UUID().uuidString).png")
      .path
  }

  /// Runs `Generate` against `engine` through the `CLIEnvironment` seam, with
  /// `skipDownload` set so no network access is attempted. The mock is
  /// registered under `engineID: "pixart-sigma"`, and every call below passes
  /// `--model pixart-sigma`, so `ProGate` never engages (only `flux2` models
  /// require the Pro unlock) and no App Store entitlement plumbing is needed.
  private static func runGenerate(_ arguments: [String], engine: MockEngine) async throws {
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$skipDownload.withValue(true) {
        let cmd = try Generate.parse(arguments + ["--model", "pixart-sigma"])
        try await cmd.run()
      }
    }
  }

  // MARK: - Missing / empty / undecodable references fail before any load

  @Test("a missing reference file throws referenceNotFound, with no model load")
  func missingReferenceFileFails() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", maxReferenceImages: 3)
    let missingPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("does-not-exist-\(UUID().uuidString).png").path
    do {
      try await Self.runGenerate(
        ["prompt", "-r", missingPath, "--output", Self.tempOutputPath()], engine: engine)
      Issue.record("Expected referenceNotFound")
    } catch VinetasError.referenceNotFound(let path) {
      #expect(path == missingPath)
    }
    #expect(await engine.loadModelCallCount == 0)
  }

  @Test("an empty reference file throws referenceEmpty, with no model load")
  func emptyReferenceFileFails() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", maxReferenceImages: 3)
    let path = try Self.writeTempFile(Data())
    do {
      try await Self.runGenerate(
        ["prompt", "-r", path, "--output", Self.tempOutputPath()], engine: engine)
      Issue.record("Expected referenceEmpty")
    } catch VinetasError.referenceEmpty(let source) {
      #expect(source == .file(path: path))
    }
    #expect(await engine.loadModelCallCount == 0)
  }

  @Test("an undecodable reference file throws referenceUndecodable, with no model load")
  func undecodableReferenceFileFails() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", maxReferenceImages: 3)
    let path = try Self.writeTempFile(Data("not an image".utf8))
    do {
      try await Self.runGenerate(
        ["prompt", "-r", path, "--output", Self.tempOutputPath()], engine: engine)
      Issue.record("Expected referenceUndecodable")
    } catch VinetasError.referenceUndecodable(let source) {
      #expect(source == .file(path: path))
    }
    #expect(await engine.loadModelCallCount == 0)
  }

  // MARK: - Count validation before any load

  @Test("4 references against a mock with max 3 throws tooManyReferences, with no model load")
  func tooManyReferencesFails() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", maxReferenceImages: 3)
    let path = try Self.writeTempFile(Self.makePNGData(width: 40, height: 30))
    do {
      try await Self.runGenerate(
        [
          "prompt", "-r", path, "-r", path, "-r", path, "-r", path,
          "--output", Self.tempOutputPath(),
        ], engine: engine)
      Issue.record("Expected tooManyReferences")
    } catch VinetasError.tooManyReferences(_, let max, let got) {
      #expect(max == 3)
      #expect(got == 4)
    }
    #expect(await engine.loadModelCallCount == 0)
  }

  @Test("1 reference against a mock with max 0 throws referencesUnsupported, with no model load")
  func unsupportedEngineFails() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", maxReferenceImages: 0)
    let path = try Self.writeTempFile(Self.makePNGData(width: 40, height: 30))
    do {
      try await Self.runGenerate(
        ["prompt", "-r", path, "--output", Self.tempOutputPath()], engine: engine)
      Issue.record("Expected referencesUnsupported")
    } catch VinetasError.referencesUnsupported(let engineID) {
      #expect(engineID == "pixart-sigma")
    }
    #expect(await engine.loadModelCallCount == 0)
  }

  // MARK: - Successful path: downscale note
  //
  // `downscaleNoteLines(for:)` is the pure, synchronous helper `Generate.run()`
  // calls to build these lines (VinetasCLICore.swift). Exercising it here
  // through `StdioCapture.run` with a plain synchronous body — no `Task` /
  // `DispatchSemaphore` bridge into async `Generate.run()` — keeps the fd-1/2
  // swap window microseconds long, matching every other `StdioCapture.run`
  // caller in the suite. An async bridge was tried and measurably raced fd 1/2
  // against unrelated, slower concurrent test suites (real Acervo network
  // attempts in `Flux2EngineTests`), twice reproducing a fatal
  // `NSFileHandleOperationException: Bad file descriptor` crash of the whole
  // xctest process across a handful of local runs. The wiring itself (that
  // `Generate.run()` calls this helper with the loaded references, before any
  // engine call) is covered separately by `endToEndWithDownscaledReference`
  // below, which never touches stdio.

  @Test("downscaleNoteLines formats a 1-based note with × dimensions, on stderr")
  func downscaleNoteOnStderr() throws {
    let path = try Self.writeTempFile(Self.makePNGData(width: 2048, height: 2048))
    let reference = try ReferenceImage.load(path: path)
    #expect(reference.originalSize == ReferenceImage.Size(width: 2048, height: 2048))
    #expect(reference.effectiveSize == ReferenceImage.Size(width: 1024, height: 1024))

    let result = try StdioCapture.run {
      for line in downscaleNoteLines(for: [reference]) {
        stderrPrint(line)
      }
    }

    let stderrText = String(data: result.stderr, encoding: .utf8) ?? ""
    #expect(stderrText.contains("note: reference 1"))
    #expect(stderrText.contains("downscaled 2048×2048 → 1024×1024"))
    #expect(result.stdout.isEmpty)
  }

  // MARK: - End-to-end: a downscaled reference still generates successfully

  @Test("a 2048x2048 reference still generates through Generate.run(), end to end")
  func endToEndWithDownscaledReference() async throws {
    let engine = MockEngine(engineID: "pixart-sigma", maxReferenceImages: 3)
    let path = try Self.writeTempFile(Self.makePNGData(width: 2048, height: 2048))
    let outputPath = Self.tempOutputPath()
    defer {
      try? FileManager.default.removeItem(atPath: outputPath)
      try? FileManager.default.removeItem(
        atPath: (outputPath as NSString).deletingPathExtension + ".json")
    }

    try await Self.runGenerate(
      ["prompt", "-r", path, "--output", outputPath], engine: engine)

    #expect(await engine.loadModelCallCount == 1)
    #expect(await engine.generateCallCount == 1)
    #expect(FileManager.default.fileExists(atPath: outputPath))
  }
}

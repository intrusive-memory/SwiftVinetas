import ArgumentParser
import Foundation
import GlosaCore
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

@Suite("Generate --shot-json", .serialized)
struct GenerateShotJSONTests {

  private static func makeShot() -> Shot {
    Shot(
      documentIndex: 1,
      prompt: "a paper boat on a still pond",
      style: "watercolour",
      model: "pixart-sigma",
      width: 512,
      height: 384,
      steps: 4,
      seed: 11
    )
  }

  private static func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("GenerateShotJSONTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func run(_ arguments: [String], stdin: Data? = nil) async throws {
    let engine = MockEngine(engineID: "pixart-sigma")
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$skipDownload.withValue(true) {
        try await CLIEnvironment.$stdinReferenceData.withValue({ stdin ?? Data() }) {
          let cmd = try Generate.parse(arguments)
          try await cmd.run()
        }
      }
    }
  }

  @Test func testShotJSONHappyPathRecordsGlosa() async throws {
    let dir = try Self.tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let shot = Self.makeShot()
    let shotURL = dir.appendingPathComponent("shot.json")
    try shot.schemaJSONData().write(to: shotURL)
    let png = dir.appendingPathComponent("out.png")

    try await Self.run(["--shot-json", shotURL.path, "-o", png.path])

    let sidecar = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self,
      from: Data(contentsOf: png.deletingPathExtension().appendingPathExtension("json")))
    #expect(sidecar.glosa?.digest == shot.renderDigest)
    #expect(sidecar.glosa?.notation == GlosaVersion.notation)
    #expect(sidecar.prompt == shot.prompt)
  }

  @Test func testShotJSONConflictsWithExplicitFlags() throws {
    do {
      _ = try Generate.parse(["--shot-json", "s.json", "--seed", "3", "--style", "noir"])
      Issue.record("expected a validation error")
    } catch {
      let message = Generate.message(for: error)
      #expect(message.contains("--seed"))
      #expect(message.contains("--style"))
      #expect(message.contains("--shot-json"))
    }
    #expect(throws: Error.self) { try Generate.parse(["a prompt", "--shot-json", "s.json"]) }
    // Output-location flags remain allowed; a prompt is still required without a shot.
    _ = try Generate.parse(["--shot-json", "s.json", "-o", "x.png", "--dry-run"])
    #expect(throws: Error.self) { try Generate.parse([]) }
  }

  @Test func testShotJSONInvalidReportsSchemaError() async throws {
    let dir = try Self.tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let bad = dir.appendingPathComponent("bad.json")
    try Data(#"{"prompt": 42}"#.utf8).write(to: bad)
    do {
      try await Self.run(["--shot-json", bad.path, "-o", dir.appendingPathComponent("o.png").path])
      Issue.record("expected an error")
    } catch let error as ValidationError {
      #expect(error.message.contains("invalid --shot-json"))
    }
  }

  @Test func testShotJSONFromStdinPath() async throws {
    let payload = Data("{}".utf8)
    #expect(try readShotJSON("-", stdin: { payload }) == payload)

    let dir = try Self.tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let shot = Self.makeShot()
    let png = dir.appendingPathComponent("stdin.png")
    try await Self.run(
      ["--shot-json", "-", "-o", png.path], stdin: try shot.schemaJSONData())
    let sidecar = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self,
      from: Data(contentsOf: png.deletingPathExtension().appendingPathExtension("json")))
    #expect(sidecar.glosa?.digest == shot.renderDigest)
  }
}

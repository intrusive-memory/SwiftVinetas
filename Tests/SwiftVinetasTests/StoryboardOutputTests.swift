import Foundation
import GlosaCore
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

/// Storyboard output resolution (REQUIREMENTS § 3) and the per-panel render
/// record (§ 4). Fixtures are synthetic and written to a temporary directory.
@Suite("Storyboard — output resolution and render record", .serialized)
struct StoryboardOutputTests {

  private static func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("StoryboardOutputTests-\(UUID().uuidString)", isDirectory: true)
      .resolvingSymlinksInPath()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func plan(output: String?) -> Storyboard.PanelPlan {
    let shot = Shot(documentIndex: 0, prompt: "a paper boat", output: output)
    return Storyboard().resolvePlan(for: shot, panelNumber: 1, fleetModel: .pixartSigma)
  }

  /// Runs a one-shot screenplay through `Storyboard.run` with a mock engine.
  private func runStoryboard(
    in folder: URL, output: String?, probe: (@Sendable (URL) -> Bool)? = nil
  ) async throws {
    let attribute = output.map { " output=\"\($0)\"" } ?? ""
    let fountain = """
      INT. HARBOUR - DAY

      [[<shot prompt="a paper boat on a still pond"\(attribute)/>]]
      """
    let screenplay = folder.appendingPathComponent("script.fountain")
    try fountain.write(to: screenplay, atomically: true, encoding: .utf8)
    let outputDir = folder.appendingPathComponent("storyboard")
    let client = VinetasClient(
      router: EngineRouter(engines: [MockEngine(engineID: "pixart-sigma")]))

    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$skipDownload.withValue(true) {
        let command = try Storyboard.parse([
          screenplay.path, "--output-dir", outputDir.path, "--model", "pixart-sigma",
        ])
        if let probe {
          try await CLIEnvironment.$directoryWritabilityProbe.withValue(probe) {
            try await command.run()
          }
        } else {
          try await command.run()
        }
      }
    }
  }

  @Test func testRelativeOutputResolvesAgainstProjectRoot() async throws {
    let root = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    try "# Project".write(
      to: root.appendingPathComponent("PROJECT.md"), atomically: true, encoding: .utf8)
    let sub = root.appendingPathComponent("episodes", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

    try await runStoryboard(in: sub, output: "boards/one.png")

    let fm = FileManager.default
    #expect(fm.fileExists(atPath: root.appendingPathComponent("boards/one.png").path))
    #expect(!fm.fileExists(atPath: sub.appendingPathComponent("boards/one.png").path))
    #expect(!fm.fileExists(atPath: sub.appendingPathComponent("storyboard/boards/one.png").path))
  }

  @Test func testRelativeOutputResolvesAgainstScreenplayFolderWithoutProject() async throws {
    let folder = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: folder) }

    try await runStoryboard(in: folder, output: "one.png")

    let fm = FileManager.default
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("one.png").path))
    #expect(!fm.fileExists(atPath: folder.appendingPathComponent("storyboard/one.png").path))
  }

  @Test func testAbsoluteOutputUnchanged() {
    let item = plan(output: "/elsewhere/final.png")
    let url = Storyboard().outputURL(
      for: item, in: URL(fileURLWithPath: "/panels"),
      relativeTo: URL(fileURLWithPath: "/project"))
    #expect(url.path == "/elsewhere/final.png")
  }

  @Test func testNoOutputUsesOutputDir() async throws {
    let folder = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: folder) }

    try await runStoryboard(in: folder, output: nil)

    #expect(
      FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("storyboard/panel-001.png").path))
  }

  @Test func testUnwritableProjectRootFailsWithPathAndRemedy() async throws {
    let folder = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: folder) }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let cwdFile = cwd.appendingPathComponent("denied.png")
    try? FileManager.default.removeItem(at: cwdFile)

    var message = ""
    do {
      try await runStoryboard(in: folder, output: "denied.png", probe: { _ in false })
      Issue.record("expected the panel to fail")
    } catch let error as StoryboardPanelError {
      message = error.message
    }

    let expectedPath = folder.appendingPathComponent("denied.png").path
    #expect(message.contains(expectedPath))
    #expect(message.contains("Grant that folder to the Vinetas app"))
    #expect(message.contains("absolute `output`"))
    #expect(message.contains("omit `output` to use --output-dir"))
    #expect(!FileManager.default.fileExists(atPath: cwdFile.path))
    #expect(!FileManager.default.fileExists(atPath: expectedPath))
  }

  @Test func testStoryboardSidecarRecordsGlosa() async throws {
    let folder = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: folder) }

    try await runStoryboard(in: folder, output: nil)

    let (score, _) = try ScreenplayShots.loadScore(
      from: folder.appendingPathComponent("script.fountain").path)
    let effective = try #require(score.effectiveShots.first)

    let data = try Data(
      contentsOf: folder.appendingPathComponent("storyboard/panel-001.json"))
    let sidecar = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: data)
    #expect(sidecar.glosa?.digest == effective.renderDigest)
    #expect(sidecar.glosa?.notation == GlosaVersion.notation)
  }
}

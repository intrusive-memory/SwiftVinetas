import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

/// Sortie 12: `batch` and `storyboard` record what they used (RI-13).
///
/// Before this sortie, `batch` wrote every sidecar from a freshly-constructed
/// default `StyleConfig(width:height:)` (dropping the actual steps/guidance
/// used), and `storyboard` called `ImageOutput.writePNG` directly (no sidecar,
/// no embedded metadata at all). Both commands now dispatch through
/// `VinetasClient.generate(_:) -> GeneratedPanel` and write with
/// `ImageOutput.writePanel(image:metadata:to:)`, so the metadata on disk is
/// exactly what `VinetasClient` recorded for that item.
@Suite("Batch and storyboard record actual metadata (Sortie 12)", .serialized)
struct BatchStoryboardMetadataTests {

  private static func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "BatchStoryboardMetadataTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - batch

  @Test("a batch item with steps: 7, guidance: 2.5 writes a sidecar recording those values")
  func batchRecordsActualStyle() async throws {
    let dir = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let yaml = """
      version: 1
      project:
        title: "Test project"
        style:
          steps: 7
          guidance: 2.5
      panels:
        - prompt: "a lone lighthouse at dusk"
      """
    let yamlURL = dir.appendingPathComponent("prompts.yaml")
    try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)
    let outputDir = dir.appendingPathComponent("panels")

    let engine = MockEngine(engineID: "pixart-sigma")
    let client = VinetasClient(router: EngineRouter(engines: [engine]))

    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$skipDownload.withValue(true) {
        let cmd = try Batch.parse([
          yamlURL.path, "--output-dir", outputDir.path, "--model", "pixart-sigma",
        ])
        try await cmd.run()
      }
    }

    let pngURL = outputDir.appendingPathComponent("panel-001.png")
    let sidecarURL = outputDir.appendingPathComponent("panel-001.json")
    #expect(FileManager.default.fileExists(atPath: pngURL.path))

    let json = try Data(contentsOf: sidecarURL)
    let metadata = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: json)
    #expect(metadata.steps == 7)
    #expect(metadata.guidance == 2.5)
    #expect(metadata.engine == "pixart-sigma")

    // The PNG embeds the same metadata as the sidecar.
    let pngData = try Data(contentsOf: pngURL)
    let embedded = ImageOutput.readEmbeddedMetadata(from: pngData)
    #expect(embedded == metadata)
  }

  // MARK: - storyboard

  @Test("a one-panel storyboard writes .png and .json with embedded vinetas metadata")
  func storyboardWritesPNGAndSidecarWithEmbeddedMetadata() async throws {
    let dir = Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let fountain = """
      INT. LIGHTHOUSE - NIGHT

      [[<shot prompt="a lone lighthouse beam sweeping the dark sea" steps="11" guidance="6.5"/>]]
      """
    let screenplayURL = dir.appendingPathComponent("script.fountain")
    try fountain.write(to: screenplayURL, atomically: true, encoding: .utf8)
    let outputDir = dir.appendingPathComponent("storyboard")

    let engine = MockEngine(engineID: "pixart-sigma")
    let client = VinetasClient(router: EngineRouter(engines: [engine]))

    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$skipDownload.withValue(true) {
        let cmd = try Storyboard.parse([
          screenplayURL.path, "--output-dir", outputDir.path, "--model", "pixart-sigma",
        ])
        try await cmd.run()
      }
    }

    let pngURL = outputDir.appendingPathComponent("panel-001.png")
    let jsonURL = outputDir.appendingPathComponent("panel-001.json")
    #expect(FileManager.default.fileExists(atPath: pngURL.path))
    #expect(FileManager.default.fileExists(atPath: jsonURL.path))

    let json = try Data(contentsOf: jsonURL)
    let sidecar = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: json)
    #expect(sidecar.steps == 11)
    #expect(sidecar.guidance == 6.5)

    let pngData = try Data(contentsOf: pngURL)
    let embedded = try #require(ImageOutput.readEmbeddedMetadata(from: pngData))
    #expect(embedded == sidecar)
  }
}

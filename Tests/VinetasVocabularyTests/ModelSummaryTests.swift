import Foundation
import Testing

@testable import VinetasVocabulary

/// Covers the `ModelSummary` catalog, its CLI-name lookup and `Codable` shape,
/// and cross-checks `klein4B` against the real granville episode and panel.
@Suite
struct ModelSummaryTests {

  @Test
  func allListsFluxThenPixArt() {
    #expect(ModelSummary.all.map(\.id) == ["flux2-klein-4b", "pixart-sigma-xl"])
  }

  @Test
  func namedFindsPixArtByCLIName() {
    #expect(ModelSummary.named(cli: "pixart-sigma") == .pixartSigmaXL)
  }

  @Test
  func namedReturnsNilForUnknownCLIName() {
    #expect(ModelSummary.named(cli: "klein9b") == nil)
  }

  @Test(arguments: [ModelSummary.klein4B, ModelSummary.pixartSigmaXL])
  func codableRoundTrip(summary: ModelSummary) throws {
    let data = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(ModelSummary.self, from: data)
    #expect(decoded == summary)
  }

  @Test(arguments: [ModelSummary.klein4B, ModelSummary.pixartSigmaXL])
  func supportsEveryAspectRatio(summary: ModelSummary) {
    #expect(summary.supportedAspectRatios == AspectRatio.allCases)
  }

  // MARK: - Granville cross-check

  /// The fields of a generated granville panel this suite compares.
  struct GeneratedPanel: Decodable {
    var model: String
    var engine: String
    var steps: Int
    var guidance: Float
  }

  private static func fixtureURL(_ name: String, _ ext: String) throws -> URL {
    try #require(
      Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures/granville")
    )
  }

  @Test
  func granvilleDefaultsShotNamesKlein4B() throws {
    let url = try Self.fixtureURL("episode_1_01_cold_open", "fountain")
    let text = try String(contentsOf: url, encoding: .utf8)
    let lines = text.components(separatedBy: "\n")
    try #require(lines.count >= 7)
    let line = lines[6]
    let shot = try #require(line.firstMatch(of: /<shot [^>]*\/>/))
    let model = try #require(String(shot.output).firstMatch(of: /model="([^"]*)"/))
    #expect(ModelSummary.named(cli: String(model.output.1)) == .klein4B)
  }

  @Test
  func granvillePanelWasGeneratedWithKlein4BDefaults() throws {
    let url = try Self.fixtureURL("ep1_sc1_01_establishing", "json")
    let panel = try JSONDecoder().decode(GeneratedPanel.self, from: Data(contentsOf: url))
    #expect(panel.model == ModelSummary.klein4B.id)
    #expect(panel.engine == ModelSummary.klein4B.engineID)
    #expect(panel.steps == ModelSummary.klein4B.defaultSteps)
    #expect(panel.guidance == ModelSummary.klein4B.defaultGuidance)
  }
}

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
  func onDeviceModelsSupportEveryControlAndCarryNoNames(summary: ModelSummary) {
    #expect(summary.supportsSteps)
    #expect(summary.supportsGuidance)
    #expect(summary.supportsSeed)
    #expect(summary.supportsNegativePrompt)
    #expect(summary.engineName == nil)
    #expect(summary.subtitle == nil)
  }

  /// A summary as 0.22.0 / 0.23.0 encoded it, before the capability fields.
  static let legacyJSON = """
    {
      "id": "flux2-klein-4b",
      "displayName": "FLUX.2 Klein 4B",
      "engineID": "flux2",
      "cliName": "klein4b",
      "minimumMemoryGB": 16,
      "approximateDownloadSize": "~11 GB",
      "defaultSteps": 8,
      "defaultGuidance": 3.5,
      "supportedAspectRatios": ["square", "wide"]
    }
    """

  @Test
  func legacyJSONWithoutCapabilityKeysDecodesToDefaults() throws {
    let decoded = try JSONDecoder().decode(
      ModelSummary.self, from: Data(Self.legacyJSON.utf8))
    #expect(decoded.id == "flux2-klein-4b")
    #expect(decoded.supportedAspectRatios == [.square, .wide])
    #expect(decoded.supportsSteps)
    #expect(decoded.supportsGuidance)
    #expect(decoded.supportsSeed)
    #expect(decoded.supportsNegativePrompt)
    #expect(decoded.engineName == nil)
    #expect(decoded.subtitle == nil)
  }

  @Test
  func capabilityFieldsRoundTrip() throws {
    let summary = ModelSummary(
      id: "openai-gpt-image-2.5-flare",
      displayName: "GPT Image 2.5 Flare",
      engineID: "cloud-openai",
      cliName: "openai-gpt-image-2.5-flare",
      minimumMemoryGB: 0,
      approximateDownloadSize: "Cloud",
      defaultSteps: 1,
      defaultGuidance: 1.0,
      supportedAspectRatios: [.square, .wide],
      supportsSteps: false,
      supportsGuidance: false,
      supportsSeed: true,
      supportsNegativePrompt: false,
      engineName: "OpenAI",
      subtitle: "OpenAI · ~$0.03/image"
    )
    let data = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(ModelSummary.self, from: data)
    #expect(decoded == summary)
    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["supportsSteps"] as? Bool == false)
    #expect(object["engineName"] as? String == "OpenAI")
  }

  @Test
  func nilNamesAreOmittedFromTheEncoding() throws {
    let data = try JSONEncoder().encode(ModelSummary.klein4B)
    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["engineName"] == nil)
    #expect(object["subtitle"] == nil)
    #expect(object["supportsNegativePrompt"] as? Bool == true)
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

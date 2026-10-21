import Foundation
import GlosaCore
import Testing

@testable import SwiftVinetas

/// `ImageOutput.PanelMetadata.glosa` — the GLOSA render record. Synthetic shots only.
@Suite("GlosaRecordTests")
struct GlosaRecordTests {

  // MARK: - Fixtures

  private static func makeShot(seed: UInt64? = 7) -> Shot {
    Shot(
      documentIndex: 3,
      prompt: "a red kite over a quiet harbour",
      style: "ink wash",
      width: 1024,
      height: 768,
      steps: 4,
      guidance: 3.5,
      seed: seed,
      preview: false,
      ref: ["refs/kite.png"],
      extraAttributes: [
        GlosaJSONMember(key: "mood", value: .string("calm")),
        GlosaJSONMember(
          key: "camera",
          value: .object([
            GlosaJSONMember(key: "lens", value: .number(35))
          ])),
      ]
    )
  }

  private static func metadata(glosa: ImageOutput.PanelMetadata.GlosaRecord?)
    -> ImageOutput.PanelMetadata
  {
    ImageOutput.PanelMetadata(
      prompt: "a red kite over a quiet harbour",
      model: "klein4b",
      seed: 7,
      steps: 4,
      guidance: 3.5,
      width: 1024,
      height: 768,
      durationSeconds: 1.25,
      generatedAt: "2026-01-01T00:00:00Z",
      glosa: glosa
    )
  }

  // MARK: - Tests

  @Test func testGlosaRecordDigestMatchesShot() {
    let shot = Self.makeShot()
    let record = ImageOutput.PanelMetadata.GlosaRecord(shot: shot)
    #expect(record.digest == shot.renderDigest)
    #expect(record.notation == GlosaVersion.notation)
  }

  @Test func testGlosaShotIsBareSchemaObject() throws {
    let record = ImageOutput.PanelMetadata.GlosaRecord(shot: Self.makeShot())
    let json = try ImageOutput.metadataJSON(Self.metadata(glosa: record))
    let root = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
    let glosa = try #require(root["glosa"] as? [String: Any])
    let shot = try #require(glosa["shot"] as? [String: Any])
    #expect(shot["prompt"] as? String == "a red kite over a quiet harbour")
    #expect(shot["object"] == nil)
    #expect(shot["documentIndex"] == nil)
    #expect(shot["mood"] as? String == "calm")
    let camera = try #require(shot["camera"] as? [String: Any])
    #expect((camera["lens"] as? NSNumber)?.intValue == 35)
    #expect(glosa["digest"] as? String == record.digest)
    #expect(glosa["notation"] as? String == GlosaVersion.notation)
  }

  @Test func testGlosaShotRoundTripsThroughShotCodec() throws {
    let shot = Self.makeShot()
    let record = ImageOutput.PanelMetadata.GlosaRecord(shot: shot)
    let json = try ImageOutput.metadataJSON(Self.metadata(glosa: record))

    let decoded = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: json)
    #expect(decoded == Self.metadata(glosa: record))
    let decodedRecord = try #require(decoded.glosa)

    // Re-serialize the sidecar's `glosa.shot` object and read it back as a shot.
    let root = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
    let glosa = try #require(root["glosa"] as? [String: Any])
    let shotObject = try #require(glosa["shot"])
    let shotData = try JSONSerialization.data(withJSONObject: shotObject)
    let reread = try Shot(schemaJSONData: shotData)
    #expect(reread.renderDigest == shot.renderDigest)
    #expect(reread.renderDigest == decodedRecord.digest)

    // The record's own decoder agrees.
    #expect(try decodedRecord.decodedShot().renderDigest == shot.renderDigest)
  }

  @Test func testGlosaRecordPreservesLargeSeed() throws {
    let seed = (UInt64(1) << 63) + 1
    let shot = Self.makeShot(seed: seed)
    let record = ImageOutput.PanelMetadata.GlosaRecord(shot: shot)
    let json = try ImageOutput.metadataJSON(Self.metadata(glosa: record))
    let decoded = try JSONDecoder().decode(ImageOutput.PanelMetadata.self, from: json)
    let reread = try #require(decoded.glosa).decodedShot()
    #expect(reread.seed == seed)
    #expect(reread.renderDigest == shot.renderDigest)
  }

  @Test func testOldSidecarWithoutGlosaDecodes() throws {
    let legacy = """
      {
        "durationSeconds" : 2.5,
        "generatedAt" : "2026-01-01T00:00:00Z",
        "guidance" : 1,
        "height" : 512,
        "model" : "klein4b",
        "prompt" : "a paper boat on a pond",
        "seed" : 11,
        "steps" : 4,
        "width" : 512
      }
      """
    let decoded = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self, from: Data(legacy.utf8))
    #expect(decoded.glosa == nil)
    #expect(decoded.prompt == "a paper boat on a pond")

    // And a record without `glosa` encodes without the key.
    let json = try ImageOutput.metadataJSON(Self.metadata(glosa: nil))
    let root = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
    #expect(root["glosa"] == nil)
  }

  @Test func testRawJSONValuePreservesIntegersAndBooleans() throws {
    let text =
      #"{"big":18446744073709551615,"neg":-9007199254740993,"flag":true,"one":1,"half":0.5,"list":[1,false,null,"x"]}"#
    let value = try RawJSONValue(jsonData: Data(text.utf8))
    guard case .object(let members) = value else {
      Issue.record("expected an object")
      return
    }
    #expect(members["big"] == .uint(UInt64.max))
    #expect(members["neg"] == .int(-9_007_199_254_740_993))
    #expect(members["flag"] == .bool(true))
    #expect(members["one"] == .int(1))
    #expect(members["half"] == .double(0.5))
    #expect(members["list"] == .array([.int(1), .bool(false), .null, .string("x")]))
    let reencoded = try RawJSONValue(jsonData: value.jsonData())
    #expect(reencoded == value)
    let compact = String(decoding: try value.jsonData(), as: UTF8.self)
    #expect(compact.contains(#""big":18446744073709551615"#))
    #expect(compact.contains(#""neg":-9007199254740993"#))
  }
}

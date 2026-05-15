import Foundation
import Testing
import VinetasCLICore
import SwiftVinetas
import Flux2Core
import PixArtBackbone
import Tuberia
import SwiftAcervo

// MARK: - EventEncoding smoke tests (Sortie 7)
//
// For each of the five host-library encoders, encodes one representative case,
// re-decodes the JSON via JSONSerialization, and asserts that the resulting
// dictionary contains the "case" discriminant key. One assertion per encoder,
// five assertions total (as required by Sortie 7 exit criteria).
//
// Test function name: testEachEncoderEmitsCaseDiscriminantKey
// (per Sortie 7 specification)

@Suite("EventEncoding smoke tests")
struct EventEncodingSmokeTests {

  private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return enc
  }()

  @Test("testEachEncoderEmitsCaseDiscriminantKey")
  func testEachEncoderEmitsCaseDiscriminantKey() throws {

    // MARK: 1. VinetasEventCodable — representative: engineRegistered

    let vinetasEvent = VinetasTelemetryEvent.engineRegistered(
      engineID: "flux2", reason: "memory threshold passed"
    )
    let vinetasData = try encoder.encode(VinetasEventCodable(event: vinetasEvent))
    let vinetasDict = try JSONSerialization.jsonObject(with: vinetasData) as? [String: Any]
    #expect(
      vinetasDict?["case"] as? String == "engineRegistered",
      "VinetasEventCodable must emit 'case' discriminant key"
    )

    // MARK: 2. Flux2EventCodable — representative: pipelineInit

    let flux2Event = Flux2TelemetryEvent.pipelineInit(
      model: "klein-4b", quantization: "int4", vaeConfig: "standard"
    )
    let flux2Data = try encoder.encode(Flux2EventCodable(event: flux2Event))
    let flux2Dict = try JSONSerialization.jsonObject(with: flux2Data) as? [String: Any]
    #expect(
      flux2Dict?["case"] as? String == "pipelineInit",
      "Flux2EventCodable must emit 'case' discriminant key"
    )

    // MARK: 3. PixArtEventCodable — representative: recipeValidated

    let pixartEvent = PixArtTelemetryEvent.recipeValidated(
      name: "pixart-sigma-fp16", checksPassed: 4
    )
    let pixartData = try encoder.encode(PixArtEventCodable(event: pixartEvent))
    let pixartDict = try JSONSerialization.jsonObject(with: pixartData) as? [String: Any]
    #expect(
      pixartDict?["case"] as? String == "recipeValidated",
      "PixArtEventCodable must emit 'case' discriminant key"
    )

    // MARK: 4. TuberiaEventCodable — representative: memoryGateChecked

    let tuberiaEvent = TuberiaTelemetryEvent.memoryGateChecked(
      requiredBytes: 4_294_967_296, passed: true
    )
    let tuberiaData = try encoder.encode(TuberiaEventCodable(event: tuberiaEvent))
    let tuberiaDict = try JSONSerialization.jsonObject(with: tuberiaData) as? [String: Any]
    #expect(
      tuberiaDict?["case"] as? String == "memoryGateChecked",
      "TuberiaEventCodable must emit 'case' discriminant key"
    )

    // MARK: 5. AcervoEventCodable — representative: cacheHit

    let acervoEvent = AcervoTelemetryEvent.cacheHit(
      modelID: "flux2-klein-4b",
      fileName: "transformer.safetensors",
      onDiskBytes: 4_294_967_296,
      ageSeconds: 86400.0
    )
    let acervoData = try encoder.encode(AcervoEventCodable(event: acervoEvent))
    let acervoDict = try JSONSerialization.jsonObject(with: acervoData) as? [String: Any]
    #expect(
      acervoDict?["case"] as? String == "cacheHit",
      "AcervoEventCodable must emit 'case' discriminant key"
    )
  }
}

import Flux2Core
import Foundation
import Testing
import Tuberia
import VinetasCLICore

// MARK: - Flux2EventEncodingTests (Sortie 11e)
//
// Round-trip tests for all 14 cases of Flux2TelemetryEvent via Flux2EventCodable
// (Flux2Core 3.2.2+: quantizationComplete, denoiseStepStart, denoiseStepComplete).
// For each case:
//  - Encodes via the same JSONEncoder config the sink uses
//  - Re-decodes via JSONSerialization
//  - Asserts the "case" discriminant string
//  - Asserts each associated-value field is present

@Suite("Flux2EventEncoding round-trips")
struct Flux2EventEncodingTests {

  // MARK: - Helpers

  private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    return enc
  }()

  private func roundTrip(_ event: Flux2TelemetryEvent) throws -> [String: Any] {
    let data = try encoder.encode(Flux2EventCodable(event: event))
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Issue.record("Round-trip did not produce a JSON object for \(event)")
      return [:]
    }
    return dict
  }

  private func makeStat() -> TuberiaTensorStat {
    TuberiaTensorStat(
      shape: [1, 64, 64, 16], dtype: "float16",
      min: -2.0, max: 2.0, mean: 0.0, std: 1.0,
      hasNaN: false, hasInf: false
    )
  }

  // MARK: - Case 1: pipelineInit

  @Test("pipelineInit encodes discriminant and all associated values")
  func testPipelineInit() throws {
    let dict = try roundTrip(
      .pipelineInit(model: "klein-4b", quantization: "int4", vaeConfig: "standard")
    )
    #expect((dict["case"] as? String) == "pipelineInit")
    #expect((dict["model"] as? String) == "klein-4b")
    #expect((dict["quantization"] as? String) == "int4")
    #expect((dict["vaeConfig"] as? String) == "standard")
  }

  // MARK: - Case 2: pipelineDispose

  @Test("pipelineDispose encodes discriminant only (no associated values)")
  func testPipelineDispose() throws {
    let dict = try roundTrip(.pipelineDispose)
    #expect((dict["case"] as? String) == "pipelineDispose")
    // No other keys expected.
    #expect(dict.count == 1, "pipelineDispose should have exactly 1 key, got \(dict.keys.sorted())")
  }

  // MARK: - Case 3: weightLoadComplete

  @Test("weightLoadComplete encodes discriminant, component rawValue, and all associated values")
  func testWeightLoadComplete() throws {
    let dict = try roundTrip(
      .weightLoadComplete(component: .transformer, paramCount: 12_000_000, durationSeconds: 3.7)
    )
    #expect((dict["case"] as? String) == "weightLoadComplete")
    #expect((dict["component"] as? String) == "transformer")
    #expect((dict["paramCount"] as? Int) == 12_000_000)
    #expect((dict["durationSeconds"] as? Double) == 3.7)
  }

  @Test("weightLoadComplete encodes WeightComponent.vae rawValue")
  func testWeightLoadCompleteVAE() throws {
    let dict = try roundTrip(
      .weightLoadComplete(component: .vae, paramCount: 5_000_000, durationSeconds: 1.2)
    )
    #expect((dict["component"] as? String) == "vae")
  }

  // MARK: - Case 4: textEncodeComplete

  @Test("textEncodeComplete encodes discriminant and all associated values")
  func testTextEncodeComplete() throws {
    let dict = try roundTrip(
      .textEncodeComplete(
        encoderName: "KleinTextEncoder",
        finalPromptLength: 77,
        embeddingStat: makeStat(),
        durationSeconds: 0.5
      )
    )
    #expect((dict["case"] as? String) == "textEncodeComplete")
    #expect((dict["encoderName"] as? String) == "KleinTextEncoder")
    #expect((dict["finalPromptLength"] as? Int) == 77)
    #expect(dict["embeddingStat"] != nil, "embeddingStat should be encoded")
    #expect((dict["durationSeconds"] as? Double) == 0.5)
  }

  // MARK: - Case 5: schedulerConfigured

  @Test("schedulerConfigured encodes discriminant and all associated values")
  func testSchedulerConfigured() throws {
    let dict = try roundTrip(
      .schedulerConfigured(numInferenceSteps: 28, shift: 3.0, imageSeqLen: 256, mu: 1.15)
    )
    #expect((dict["case"] as? String) == "schedulerConfigured")
    #expect((dict["numInferenceSteps"] as? Int) == 28)
    #expect(dict["shift"] != nil)
    #expect((dict["imageSeqLen"] as? Int) == 256)
    #expect(dict["mu"] != nil)
  }

  // MARK: - Case 6: denoiseLoopStart

  @Test("denoiseLoopStart encodes discriminant, variant rawValue, and all associated values")
  func testDenoiseLoopStart() throws {
    let dict = try roundTrip(
      .denoiseLoopStart(
        variant: .textToImage,
        totalSteps: 28,
        latentShape: [1, 64, 64, 16],
        latentDtype: "float16"
      )
    )
    #expect((dict["case"] as? String) == "denoiseLoopStart")
    #expect((dict["variant"] as? String) == "textToImage")
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect((dict["latentShape"] as? [Int]) == [1, 64, 64, 16])
    #expect((dict["latentDtype"] as? String) == "float16")
  }

  // MARK: - Case 7: denoiseLoopEnd

  @Test("denoiseLoopEnd encodes discriminant, variant rawValue, and all associated values")
  func testDenoiseLoopEnd() throws {
    let dict = try roundTrip(
      .denoiseLoopEnd(
        variant: .imageToImageKVCached,
        totalSteps: 28,
        completedSteps: 28,
        finalLatentStat: makeStat(),
        durationSeconds: 8.5
      )
    )
    #expect((dict["case"] as? String) == "denoiseLoopEnd")
    #expect((dict["variant"] as? String) == "imageToImageKVCached")
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect((dict["completedSteps"] as? Int) == 28)
    #expect(dict["finalLatentStat"] != nil, "finalLatentStat should be encoded")
    #expect((dict["durationSeconds"] as? Double) == 8.5)
  }

  // MARK: - Case 8: vaeDecodeComplete

  @Test("vaeDecodeComplete encodes discriminant and all associated values")
  func testVaeDecodeComplete() throws {
    let dict = try roundTrip(
      .vaeDecodeComplete(
        pixelStat: makeStat(), outputDims: [512, 512, 3], durationSeconds: 1.3
      )
    )
    #expect((dict["case"] as? String) == "vaeDecodeComplete")
    #expect(dict["pixelStat"] != nil, "pixelStat should be encoded")
    #expect((dict["outputDims"] as? [Int]) == [512, 512, 3])
    #expect((dict["durationSeconds"] as? Double) == 1.3)
  }

  // MARK: - Case 9: numericalAnomaly

  @Test("numericalAnomaly encodes discriminant, phase rawValue, kind rawValue, and stat")
  func testNumericalAnomaly() throws {
    let dict = try roundTrip(
      .numericalAnomaly(phase: .denoiseLoopEnd, kind: .nan, stat: makeStat())
    )
    #expect((dict["case"] as? String) == "numericalAnomaly")
    #expect((dict["phase"] as? String) == "denoiseLoopEnd")
    #expect((dict["kind"] as? String) == "nan")
    #expect(dict["stat"] != nil, "stat should be encoded")
  }

  @Test("numericalAnomaly encodes AnomalyKind.outOfRange rawValue")
  func testNumericalAnomalyOutOfRange() throws {
    let dict = try roundTrip(
      .numericalAnomaly(phase: .vaeDecode, kind: .outOfRange, stat: makeStat())
    )
    #expect((dict["kind"] as? String) == "outOfRange")
    #expect((dict["phase"] as? String) == "vaeDecode")
  }

  // MARK: - Case 10: generationCancelled

  @Test("generationCancelled encodes discriminant and optional stepIndex (present)")
  func testGenerationCancelledWithStepIndex() throws {
    let dict = try roundTrip(.generationCancelled(stepIndex: 14))
    #expect((dict["case"] as? String) == "generationCancelled")
    #expect((dict["stepIndex"] as? Int) == 14)
  }

  @Test("generationCancelled encodes discriminant with nil stepIndex (absent)")
  func testGenerationCancelledWithoutStepIndex() throws {
    let dict = try roundTrip(.generationCancelled(stepIndex: nil))
    #expect((dict["case"] as? String) == "generationCancelled")
    #expect(dict["stepIndex"] == nil, "stepIndex should be absent when nil")
  }

  // MARK: - Case 11: errorThrown

  @Test("errorThrown encodes discriminant, phase rawValue, and errorDescription")
  func testErrorThrown() throws {
    let dict = try roundTrip(
      .errorThrown(phase: .generationFailed, errorDescription: "NaN detected in latent")
    )
    #expect((dict["case"] as? String) == "errorThrown")
    #expect((dict["phase"] as? String) == "generationFailed")
    #expect((dict["errorDescription"] as? String) == "NaN detected in latent")
  }

  @Test("errorThrown encodes ErrorPhase.weightLoadFailed rawValue")
  func testErrorThrownWeightLoadFailed() throws {
    let dict = try roundTrip(
      .errorThrown(phase: .weightLoadFailed, errorDescription: "weights not found")
    )
    #expect((dict["phase"] as? String) == "weightLoadFailed")
  }

  // MARK: - Case 12: quantizationComplete (3.2.2+)

  @Test("quantizationComplete encodes discriminant, component rawValue, and quantization params")
  func testQuantizationComplete() throws {
    let dict = try roundTrip(
      .quantizationComplete(
        component: .transformer, bits: 4, groupSize: 64, durationSeconds: 2.1
      )
    )
    #expect((dict["case"] as? String) == "quantizationComplete")
    #expect((dict["component"] as? String) == "transformer")
    #expect((dict["bits"] as? Int) == 4)
    #expect((dict["groupSize"] as? Int) == 64)
    #expect((dict["durationSeconds"] as? Double) == 2.1)
  }

  // MARK: - Case 13: denoiseStepStart (3.2.2+)

  @Test("denoiseStepStart encodes discriminant, variant, step index, and t")
  func testDenoiseStepStart() throws {
    let dict = try roundTrip(
      .denoiseStepStart(
        variant: .textToImage,
        stepIndex: 3,
        totalSteps: 28,
        t: 0.875,
        latentShape: [1, 64, 64, 16],
        latentDtype: "float16"
      )
    )
    #expect((dict["case"] as? String) == "denoiseStepStart")
    #expect((dict["variant"] as? String) == "textToImage")
    #expect((dict["stepIndex"] as? Int) == 3)
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect(dict["t"] != nil)
    #expect((dict["latentShape"] as? [Int]) == [1, 64, 64, 16])
    #expect((dict["latentDtype"] as? String) == "float16")
  }

  // MARK: - Case 14: denoiseStepComplete (3.2.2+)

  @Test("denoiseStepComplete encodes discriminant, latentStat, and step metadata")
  func testDenoiseStepComplete() throws {
    let dict = try roundTrip(
      .denoiseStepComplete(
        variant: .textToImage,
        stepIndex: 3,
        totalSteps: 28,
        t: 0.875,
        latentStat: makeStat(),
        durationSeconds: 0.28
      )
    )
    #expect((dict["case"] as? String) == "denoiseStepComplete")
    #expect((dict["variant"] as? String) == "textToImage")
    #expect((dict["stepIndex"] as? Int) == 3)
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect(dict["t"] != nil)
    #expect(dict["latentStat"] != nil, "latentStat should be encoded verbatim")
    #expect((dict["durationSeconds"] as? Double) == 0.28)
  }
}

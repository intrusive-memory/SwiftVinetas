import Foundation
import Testing
import Tuberia
import VinetasCLICore

// MARK: - TuberiaEventEncodingTests (Sortie 11g)
//
// Round-trip tests for all 27 cases of TuberiaTelemetryEvent via TuberiaEventCodable.
// For each case:
//  - Encodes via the same JSONEncoder config the sink uses
//  - Re-decodes via JSONSerialization
//  - Asserts the "case" discriminant string
//  - Asserts each associated-value field
//
// Table-driven pattern used for field presence checks; helper function
// encodes + decodes + checks discriminant and then the caller checks fields.

@Suite("TuberiaEventEncoding round-trips")
struct TuberiaEventEncodingTests {

  // MARK: - Helpers

  private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    return enc
  }()

  private func roundTrip(_ event: TuberiaTelemetryEvent) throws -> [String: Any] {
    let data = try encoder.encode(TuberiaEventCodable(event: event))
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Issue.record("Round-trip did not produce a JSON object for \(event)")
      return [:]
    }
    return dict
  }

  private func makeStat(shape: [Int] = [1, 64, 64, 16]) -> TuberiaTensorStat {
    TuberiaTensorStat(
      shape: shape, dtype: "float16",
      min: -1.0, max: 1.0, mean: 0.0, std: 0.5,
      hasNaN: false, hasInf: false
    )
  }

  private let runID = UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF") ?? UUID()

  // MARK: - Case 1: pipelineConfigured

  @Test("pipelineConfigured encodes discriminant and all 11 associated values")
  func testPipelineConfigured() throws {
    let dict = try roundTrip(
      .pipelineConfigured(
        recipeName: "flux2-schnell",
        encoderType: "KleinTextEncoder",
        schedulerType: "FluxEulerScheduler",
        backboneType: "Flux2Transformer",
        decoderType: "SDXLVAE",
        rendererType: "CGImageRenderer",
        encoderQuantization: "float16",
        backboneQuantization: "int4",
        decoderQuantization: "float16",
        peakMemoryBytes: 8_589_934_592,
        phasedMemoryBytes: 12_884_901_888
      )
    )
    #expect((dict["case"] as? String) == "pipelineConfigured")
    #expect((dict["recipeName"] as? String) == "flux2-schnell")
    #expect((dict["encoderType"] as? String) == "KleinTextEncoder")
    #expect((dict["schedulerType"] as? String) == "FluxEulerScheduler")
    #expect((dict["backboneType"] as? String) == "Flux2Transformer")
    #expect((dict["decoderType"] as? String) == "SDXLVAE")
    #expect((dict["rendererType"] as? String) == "CGImageRenderer")
    #expect((dict["encoderQuantization"] as? String) == "float16")
    #expect((dict["backboneQuantization"] as? String) == "int4")
    #expect((dict["decoderQuantization"] as? String) == "float16")
    #expect(dict["peakMemoryBytes"] != nil)
    #expect(dict["phasedMemoryBytes"] != nil)
  }

  // MARK: - Case 2: pipelineStart

  @Test("pipelineStart encodes discriminant and all associated values")
  func testPipelineStart() throws {
    let dict = try roundTrip(
      .pipelineStart(
        runID: runID,
        prompt: "a cyberpunk diner",
        steps: 28,
        guidanceScale: 3.5,
        seed: 42,
        width: 512,
        height: 512
      )
    )
    #expect((dict["case"] as? String) == "pipelineStart")
    #expect(dict["runID"] != nil, "runID should be encoded")
    #expect((dict["prompt"] as? String) == "a cyberpunk diner")
    #expect((dict["steps"] as? Int) == 28)
    #expect((dict["guidanceScale"] as? Double) == 3.5)
    // seed is UInt32 — may decode as Int or UInt
    #expect(dict["seed"] != nil)
    #expect((dict["width"] as? Int) == 512)
    #expect((dict["height"] as? Int) == 512)
  }

  // MARK: - Case 3: pipelineEnd

  @Test("pipelineEnd encodes discriminant and all associated values")
  func testPipelineEnd() throws {
    let dict = try roundTrip(
      .pipelineEnd(runID: runID, totalSteps: 28, durationSeconds: 9.1, success: true)
    )
    #expect((dict["case"] as? String) == "pipelineEnd")
    #expect(dict["runID"] != nil)
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect((dict["durationSeconds"] as? Double) == 9.1)
    #expect((dict["success"] as? Bool) == true)
  }

  // MARK: - Case 4: assemblyCheckPassed

  @Test("assemblyCheckPassed encodes discriminant, check rawValue, and all associated values")
  func testAssemblyCheckPassed() throws {
    let dict = try roundTrip(
      .assemblyCheckPassed(
        check: .encoderToBackboneDim, inlet: "768", outlet: "768"
      )
    )
    #expect((dict["case"] as? String) == "assemblyCheckPassed")
    #expect((dict["check"] as? String) == "encoderToBackboneDim")
    #expect((dict["inlet"] as? String) == "768")
    #expect((dict["outlet"] as? String) == "768")
  }

  // MARK: - Case 5: assemblyCheckFailed

  @Test("assemblyCheckFailed encodes discriminant, check rawValue, and all associated values")
  func testAssemblyCheckFailed() throws {
    let dict = try roundTrip(
      .assemblyCheckFailed(
        check: .backboneToDecoder, inlet: "16", outlet: "4",
        reason: "channel mismatch"
      )
    )
    #expect((dict["case"] as? String) == "assemblyCheckFailed")
    #expect((dict["check"] as? String) == "backboneToDecoder")
    #expect((dict["inlet"] as? String) == "16")
    #expect((dict["outlet"] as? String) == "4")
    #expect((dict["reason"] as? String) == "channel mismatch")
  }

  @Test("assemblyCheckPassed encodes all AssemblyCheck rawValues")
  func testAssemblyCheckAllValues() throws {
    let checks: [(TuberiaTelemetryEvent.AssemblyCheck, String)] = [
      (.completeness, "completeness"),
      (.encoderToBackboneDim, "encoderToBackboneDim"),
      (.encoderToBackboneSeq, "encoderToBackboneSeq"),
      (.backboneToDecoder, "backboneToDecoder"),
      (.decoderToRenderer, "decoderToRenderer"),
      (.imageToImageBidirectional, "imageToImageBidirectional"),
    ]
    for (check, rawValue) in checks {
      let dict = try roundTrip(.assemblyCheckPassed(check: check, inlet: "a", outlet: "b"))
      #expect(
        (dict["check"] as? String) == rawValue,
        "AssemblyCheck.\(check) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 6: memoryGateChecked

  @Test("memoryGateChecked encodes discriminant and all associated values")
  func testMemoryGateChecked() throws {
    let dict = try roundTrip(
      .memoryGateChecked(requiredBytes: 4_294_967_296, passed: true)
    )
    #expect((dict["case"] as? String) == "memoryGateChecked")
    #expect(dict["requiredBytes"] != nil)
    #expect((dict["passed"] as? Bool) == true)
  }

  // MARK: - Case 7: weightLoadStart

  @Test("weightLoadStart encodes discriminant and all associated values")
  func testWeightLoadStart() throws {
    let dict = try roundTrip(
      .weightLoadStart(role: "backbone", componentID: "Flux2Transformer")
    )
    #expect((dict["case"] as? String) == "weightLoadStart")
    #expect((dict["role"] as? String) == "backbone")
    #expect((dict["componentID"] as? String) == "Flux2Transformer")
  }

  // MARK: - Case 8: weightLoadComplete

  @Test("weightLoadComplete encodes discriminant and all associated values")
  func testWeightLoadComplete() throws {
    let dict = try roundTrip(
      .weightLoadComplete(
        role: "backbone",
        componentID: "Flux2Transformer",
        paramCount: 12_000_000,
        totalBytes: 6_442_450_944,
        durationSeconds: 3.7
      )
    )
    #expect((dict["case"] as? String) == "weightLoadComplete")
    #expect((dict["role"] as? String) == "backbone")
    #expect((dict["componentID"] as? String) == "Flux2Transformer")
    #expect((dict["paramCount"] as? Int) == 12_000_000)
    #expect(dict["totalBytes"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 3.7)
  }

  // MARK: - Case 9: loraLoadStart

  @Test("loraLoadStart encodes discriminant and present optional fields")
  func testLoraLoadStart() throws {
    let dict = try roundTrip(
      .loraLoadStart(
        componentID: "Flux2Transformer",
        localPath: "/tmp/my-lora.safetensors",
        scale: 0.8,
        activationKeyword: "style-x"
      )
    )
    #expect((dict["case"] as? String) == "loraLoadStart")
    #expect((dict["componentID"] as? String) == "Flux2Transformer")
    #expect((dict["localPath"] as? String) == "/tmp/my-lora.safetensors")
    #expect(dict["scale"] != nil)
    #expect((dict["activationKeyword"] as? String) == "style-x")
  }

  @Test("loraLoadStart encodes nil optional fields as absent")
  func testLoraLoadStartNilOptionals() throws {
    let dict = try roundTrip(
      .loraLoadStart(componentID: nil, localPath: nil, scale: 1.0, activationKeyword: nil)
    )
    #expect((dict["case"] as? String) == "loraLoadStart")
    #expect(dict["componentID"] == nil, "componentID should be absent when nil")
    #expect(dict["localPath"] == nil, "localPath should be absent when nil")
    #expect(dict["activationKeyword"] == nil, "activationKeyword should be absent when nil")
  }

  // MARK: - Case 10: loraLoadComplete

  @Test("loraLoadComplete encodes discriminant and all associated values")
  func testLoraLoadComplete() throws {
    let dict = try roundTrip(
      .loraLoadComplete(adapterParamCount: 3_000_000, durationSeconds: 0.4)
    )
    #expect((dict["case"] as? String) == "loraLoadComplete")
    #expect((dict["adapterParamCount"] as? Int) == 3_000_000)
    #expect((dict["durationSeconds"] as? Double) == 0.4)
  }

  // MARK: - Case 11: loraApplied

  @Test("loraApplied encodes discriminant and all associated values")
  func testLoraApplied() throws {
    let dict = try roundTrip(.loraApplied(targetLayerCount: 38))
    #expect((dict["case"] as? String) == "loraApplied")
    #expect((dict["targetLayerCount"] as? Int) == 38)
  }

  // MARK: - Case 12: loraUnapplied

  @Test("loraUnapplied encodes discriminant and all associated values")
  func testLoraUnapplied() throws {
    let dict = try roundTrip(.loraUnapplied(restoredLayerCount: 38))
    #expect((dict["case"] as? String) == "loraUnapplied")
    #expect((dict["restoredLayerCount"] as? Int) == 38)
  }

  // MARK: - Case 13: componentReadinessChecked

  @Test("componentReadinessChecked encodes discriminant and all associated values")
  func testComponentReadinessChecked() throws {
    let dict = try roundTrip(
      .componentReadinessChecked(componentID: "Flux2Transformer", ready: true)
    )
    #expect((dict["case"] as? String) == "componentReadinessChecked")
    #expect((dict["componentID"] as? String) == "Flux2Transformer")
    #expect((dict["ready"] as? Bool) == true)
  }

  // MARK: - Case 14: textEncoderForwardStart

  @Test("textEncoderForwardStart encodes discriminant, role rawValue, and all associated values")
  func testTextEncoderForwardStart() throws {
    let dict = try roundTrip(
      .textEncoderForwardStart(
        role: .conditional, promptLength: 77, maxLength: 512
      )
    )
    #expect((dict["case"] as? String) == "textEncoderForwardStart")
    #expect((dict["role"] as? String) == "conditional")
    #expect((dict["promptLength"] as? Int) == 77)
    #expect((dict["maxLength"] as? Int) == 512)
  }

  @Test("textEncoderForwardStart encodes TextEncoderRole.unconditional rawValue")
  func testTextEncoderForwardStartUnconditional() throws {
    let dict = try roundTrip(
      .textEncoderForwardStart(role: .unconditional, promptLength: 0, maxLength: 512)
    )
    #expect((dict["role"] as? String) == "unconditional")
  }

  // MARK: - Case 15: textEncoderForwardComplete

  @Test("textEncoderForwardComplete encodes discriminant, role rawValue, and stats")
  func testTextEncoderForwardComplete() throws {
    let dict = try roundTrip(
      .textEncoderForwardComplete(
        role: .conditional,
        embeddingStat: makeStat(shape: [1, 77, 768]),
        maskStat: makeStat(shape: [1, 77]),
        durationSeconds: 0.15
      )
    )
    #expect((dict["case"] as? String) == "textEncoderForwardComplete")
    #expect((dict["role"] as? String) == "conditional")
    #expect(dict["embeddingStat"] != nil, "embeddingStat should be encoded")
    #expect(dict["maskStat"] != nil, "maskStat should be encoded")
    #expect((dict["durationSeconds"] as? Double) == 0.15)
  }

  // MARK: - Case 16: schedulerConfigured

  @Test("schedulerConfigured encodes discriminant and all associated values")
  func testSchedulerConfigured() throws {
    let dict = try roundTrip(
      .schedulerConfigured(
        steps: 28,
        startTimestep: nil,
        predictionType: "flow_matching",
        timestepsHead: [1000, 900, 800],
        timestepsTail: [100, 50, 0],
        sigmasHead: [1.0, 0.9, 0.8],
        sigmasTail: [0.1, 0.05, 0.0]
      )
    )
    #expect((dict["case"] as? String) == "schedulerConfigured")
    #expect((dict["steps"] as? Int) == 28)
    #expect(dict["startTimestep"] == nil, "startTimestep should be absent when nil")
    #expect((dict["predictionType"] as? String) == "flow_matching")
    #expect(dict["timestepsHead"] != nil)
    #expect(dict["timestepsTail"] != nil)
    #expect(dict["sigmasHead"] != nil)
    #expect(dict["sigmasTail"] != nil)
  }

  @Test("schedulerConfigured encodes non-nil startTimestep")
  func testSchedulerConfiguredWithStartTimestep() throws {
    let dict = try roundTrip(
      .schedulerConfigured(
        steps: 28, startTimestep: 750, predictionType: "epsilon",
        timestepsHead: [750], timestepsTail: [0],
        sigmasHead: [0.75], sigmasTail: [0.0]
      )
    )
    #expect((dict["startTimestep"] as? Int) == 750)
  }

  // MARK: - Case 17: denoiseStepStart

  @Test("denoiseStepStart encodes discriminant and all associated values")
  func testDenoiseStepStart() throws {
    let dict = try roundTrip(
      .denoiseStepStart(
        stepIndex: 0, totalSteps: 28, timestep: 1000, sigma: 1.0,
        useCFG: true, latentBeforeStat: makeStat()
      )
    )
    #expect((dict["case"] as? String) == "denoiseStepStart")
    #expect((dict["stepIndex"] as? Int) == 0)
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect((dict["timestep"] as? Int) == 1000)
    #expect(dict["sigma"] != nil)
    #expect((dict["useCFG"] as? Bool) == true)
    #expect(dict["latentBeforeStat"] != nil, "latentBeforeStat should be encoded")
  }

  // MARK: - Case 18: denoiseStepComplete

  @Test("denoiseStepComplete encodes discriminant and all associated values")
  func testDenoiseStepComplete() throws {
    let dict = try roundTrip(
      .denoiseStepComplete(
        stepIndex: 27, totalSteps: 28, timestep: 50, sigma: 0.05,
        latentAfterStat: makeStat(),
        predictionStat: makeStat(),
        durationSeconds: 0.32
      )
    )
    #expect((dict["case"] as? String) == "denoiseStepComplete")
    #expect((dict["stepIndex"] as? Int) == 27)
    #expect((dict["totalSteps"] as? Int) == 28)
    #expect((dict["timestep"] as? Int) == 50)
    #expect(dict["sigma"] != nil)
    #expect(dict["latentAfterStat"] != nil)
    #expect(dict["predictionStat"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 0.32)
  }

  // MARK: - Case 19: cfgDtypeCast

  @Test("cfgDtypeCast encodes discriminant and all associated values")
  func testCfgDtypeCast() throws {
    let dict = try roundTrip(
      .cfgDtypeCast(
        stepIndex: 5, fromDtype: "float16", toDtype: "float32",
        guidedPredictionStat: makeStat()
      )
    )
    #expect((dict["case"] as? String) == "cfgDtypeCast")
    #expect((dict["stepIndex"] as? Int) == 5)
    #expect((dict["fromDtype"] as? String) == "float16")
    #expect((dict["toDtype"] as? String) == "float32")
    #expect(dict["guidedPredictionStat"] != nil)
  }

  // MARK: - Case 20: backboneForwardStart

  @Test("backboneForwardStart encodes discriminant, branch rawValue, and all associated values")
  func testBackboneForwardStart() throws {
    let dict = try roundTrip(
      .backboneForwardStart(
        branch: .cfgConditional,
        conditioningStat: makeStat(shape: [1, 77, 768]),
        latentStat: makeStat(),
        timestep: 800
      )
    )
    #expect((dict["case"] as? String) == "backboneForwardStart")
    #expect((dict["branch"] as? String) == "cfgConditional")
    #expect(dict["conditioningStat"] != nil)
    #expect(dict["latentStat"] != nil)
    #expect((dict["timestep"] as? Int) == 800)
  }

  @Test("backboneForwardStart encodes all BackboneBranch rawValues")
  func testBackboneBranchAllValues() throws {
    let branches: [(TuberiaTelemetryEvent.BackboneBranch, String)] = [
      (.noCFG, "noCFG"),
      (.cfgConditional, "cfgConditional"),
      (.cfgUnconditional, "cfgUnconditional"),
    ]
    for (branch, rawValue) in branches {
      let dict = try roundTrip(
        .backboneForwardStart(
          branch: branch,
          conditioningStat: makeStat(),
          latentStat: makeStat(),
          timestep: 100
        )
      )
      #expect(
        (dict["branch"] as? String) == rawValue,
        "BackboneBranch.\(branch) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 21: backboneForwardComplete

  @Test("backboneForwardComplete encodes discriminant, branch rawValue, and all associated values")
  func testBackboneForwardComplete() throws {
    let dict = try roundTrip(
      .backboneForwardComplete(
        branch: .noCFG, predictionStat: makeStat(), durationSeconds: 0.45
      )
    )
    #expect((dict["case"] as? String) == "backboneForwardComplete")
    #expect((dict["branch"] as? String) == "noCFG")
    #expect(dict["predictionStat"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 0.45)
  }

  // MARK: - Case 22: decoderDecodeStart

  @Test("decoderDecodeStart encodes discriminant and all associated values")
  func testDecoderDecodeStart() throws {
    let dict = try roundTrip(
      .decoderDecodeStart(latentStat: makeStat(), scalingFactor: 0.18215)
    )
    #expect((dict["case"] as? String) == "decoderDecodeStart")
    #expect(dict["latentStat"] != nil)
    #expect(dict["scalingFactor"] != nil)
  }

  // MARK: - Case 23: decoderDecodeComplete

  @Test("decoderDecodeComplete encodes discriminant and all associated values")
  func testDecoderDecodeComplete() throws {
    let dict = try roundTrip(
      .decoderDecodeComplete(outputStat: makeStat(shape: [1, 512, 512, 3]), durationSeconds: 0.9)
    )
    #expect((dict["case"] as? String) == "decoderDecodeComplete")
    #expect(dict["outputStat"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 0.9)
  }

  // MARK: - Case 24: rendererRenderStart

  @Test("rendererRenderStart encodes discriminant and all associated values")
  func testRendererRenderStart() throws {
    let dict = try roundTrip(
      .rendererRenderStart(modality: "image", inputStat: makeStat(shape: [1, 512, 512, 3]))
    )
    #expect((dict["case"] as? String) == "rendererRenderStart")
    #expect((dict["modality"] as? String) == "image")
    #expect(dict["inputStat"] != nil)
  }

  // MARK: - Case 25: rendererRenderComplete

  @Test("rendererRenderComplete encodes discriminant and all associated values")
  func testRendererRenderComplete() throws {
    let dict = try roundTrip(
      .rendererRenderComplete(outputBytes: 786_432, durationSeconds: 0.02)
    )
    #expect((dict["case"] as? String) == "rendererRenderComplete")
    #expect((dict["outputBytes"] as? Int) == 786_432)
    #expect((dict["durationSeconds"] as? Double) == 0.02)
  }

  // MARK: - Case 26: numericalAnomaly

  @Test(
    "numericalAnomaly encodes discriminant, phase string, kind rawValue, optional stepIndex, and stat"
  )
  func testNumericalAnomaly() throws {
    let dict = try roundTrip(
      .numericalAnomaly(
        phase: "backboneForward",
        kind: .nan,
        stepIndex: 7,
        stat: makeStat()
      )
    )
    #expect((dict["case"] as? String) == "numericalAnomaly")
    // phase is a plain String in TuberiaTelemetryEvent (not an enum)
    #expect((dict["phase"] as? String) == "backboneForward")
    #expect((dict["kind"] as? String) == "nan")
    #expect((dict["stepIndex"] as? Int) == 7)
    #expect(dict["stat"] != nil)
  }

  @Test("numericalAnomaly encodes nil stepIndex as absent")
  func testNumericalAnomalyNilStepIndex() throws {
    let dict = try roundTrip(
      .numericalAnomaly(phase: "textEncoderForward", kind: .inf, stepIndex: nil, stat: makeStat())
    )
    #expect(dict["stepIndex"] == nil, "stepIndex should be absent when nil")
    #expect((dict["kind"] as? String) == "inf")
  }

  @Test("numericalAnomaly encodes all AnomalyKind rawValues")
  func testNumericalAnomalyAllKinds() throws {
    let kindsAndExpected: [(TuberiaTelemetryEvent.AnomalyKind, String)] = [
      (.nan, "nan"),
      (.inf, "inf"),
      (.outOfRange, "outOfRange"),
    ]
    for (kind, rawValue) in kindsAndExpected {
      let dict = try roundTrip(
        .numericalAnomaly(phase: "phase", kind: kind, stepIndex: nil, stat: makeStat())
      )
      #expect(
        (dict["kind"] as? String) == rawValue,
        "AnomalyKind.\(kind) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 27: errorThrown

  @Test(
    "errorThrown encodes discriminant, phase rawValue, errorDescription, and optional stepIndex")
  func testErrorThrown() throws {
    let dict = try roundTrip(
      .errorThrown(
        phase: .backboneForward, errorDescription: "NaN in backbone output", stepIndex: 14)
    )
    #expect((dict["case"] as? String) == "errorThrown")
    #expect((dict["phase"] as? String) == "backboneForward")
    #expect((dict["errorDescription"] as? String) == "NaN in backbone output")
    #expect((dict["stepIndex"] as? Int) == 14)
  }

  @Test("errorThrown encodes nil stepIndex as absent")
  func testErrorThrownNilStepIndex() throws {
    let dict = try roundTrip(
      .errorThrown(phase: .assembly, errorDescription: "incomplete pipeline", stepIndex: nil)
    )
    #expect(dict["stepIndex"] == nil, "stepIndex should be absent when nil")
  }

  @Test("errorThrown encodes all ErrorPhase rawValues")
  func testErrorThrownAllPhases() throws {
    let phasesAndExpected: [(TuberiaTelemetryEvent.ErrorPhase, String)] = [
      (.assembly, "assembly"),
      (.memoryGate, "memoryGate"),
      (.weightLoad, "weightLoad"),
      (.loraLoad, "loraLoad"),
      (.componentReadiness, "componentReadiness"),
      (.missingComponent, "missingComponent"),
      (.textEncoderForward, "textEncoderForward"),
      (.schedulerConfigure, "schedulerConfigure"),
      (.schedulerStep, "schedulerStep"),
      (.backboneForward, "backboneForward"),
      (.decoderDecode, "decoderDecode"),
      (.rendererRender, "rendererRender"),
      (.other, "other"),
    ]
    for (phase, rawValue) in phasesAndExpected {
      let dict = try roundTrip(.errorThrown(phase: phase, errorDescription: "test", stepIndex: nil))
      #expect(
        (dict["phase"] as? String) == rawValue,
        "ErrorPhase.\(phase) should encode as '\(rawValue)'"
      )
    }
  }
}

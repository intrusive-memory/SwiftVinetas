import Foundation
import SwiftVinetas
import Testing
import Tuberia
import VinetasCLICore

// MARK: - VinetasEventEncodingTests (Sortie 11d)
//
// Round-trip tests for all 23 cases of VinetasTelemetryEvent via VinetasEventCodable.
// For each case:
//  - Encodes via the same JSONEncoder config the sink uses (.sortedKeys, .withoutEscapingSlashes, .iso8601)
//  - Re-decodes via JSONSerialization
//  - Asserts the "case" discriminant string
//  - Asserts each associated-value field is present in the JSON dictionary

@Suite("VinetasEventEncoding round-trips")
struct VinetasEventEncodingTests {

  // MARK: - Helpers

  private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    return enc
  }()

  private func roundTrip(_ event: VinetasTelemetryEvent) throws -> [String: Any] {
    let data = try encoder.encode(VinetasEventCodable(event: event))
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Issue.record("Round-trip did not produce a JSON object for \(event)")
      return [:]
    }
    return dict
  }

  private func makeStat() -> TuberiaTensorStat {
    TuberiaTensorStat(
      shape: [1, 768], dtype: "float32",
      min: -1.0, max: 1.0, mean: 0.0, std: 0.5,
      hasNaN: false, hasInf: false
    )
  }

  // MARK: - Case 1: clientInitialized

  @Test("clientInitialized encodes discriminant and all associated values")
  func testClientInitialized() throws {
    let dict = try roundTrip(
      .clientInitialized(
        version: "1.0.0",
        registeredEngines: ["flux2", "pixart"],
        deviceMemoryGB: 16,
        deviceArch: "arm64"
      )
    )
    #expect((dict["case"] as? String) == "clientInitialized")
    #expect((dict["version"] as? String) == "1.0.0")
    #expect((dict["registeredEngines"] as? [String]) == ["flux2", "pixart"])
    #expect((dict["deviceMemoryGB"] as? Int) == 16)
    #expect((dict["deviceArch"] as? String) == "arm64")
  }

  // MARK: - Case 2: engineRegistered

  @Test("engineRegistered encodes discriminant and all associated values")
  func testEngineRegistered() throws {
    let dict = try roundTrip(
      .engineRegistered(engineID: "flux2", reason: "memory threshold passed")
    )
    #expect((dict["case"] as? String) == "engineRegistered")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["reason"] as? String) == "memory threshold passed")
  }

  // MARK: - Case 3: engineSkipped

  @Test("engineSkipped encodes discriminant and all associated values")
  func testEngineSkipped() throws {
    let dict = try roundTrip(
      .engineSkipped(engineID: "pixart", reason: "insufficient memory")
    )
    #expect((dict["case"] as? String) == "engineSkipped")
    #expect((dict["engineID"] as? String) == "pixart")
    #expect((dict["reason"] as? String) == "insufficient memory")
  }

  // MARK: - Case 4: generationStart

  @Test("generationStart encodes discriminant and all associated values")
  func testGenerationStart() throws {
    let dict = try roundTrip(
      .generationStart(
        prompt: "a cyberpunk diner",
        promptLength: 18,
        engineID: "flux2",
        modelID: "klein4b",
        steps: 28,
        guidanceScale: 3.5,
        seed: 42,
        width: 512,
        height: 512,
        mode: .textToImage,
        referenceImageCount: 0,
        loraAttached: false,
        loraScale: nil,
        upsamplePromptRequested: false,
        interpretImageCount: 0
      )
    )
    #expect((dict["case"] as? String) == "generationStart")
    #expect((dict["prompt"] as? String) == "a cyberpunk diner")
    #expect((dict["promptLength"] as? Int) == 18)
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["steps"] as? Int) == 28)
    #expect((dict["seed"] as? UInt64) == 42 || (dict["seed"] as? Int) == 42)
    #expect((dict["width"] as? Int) == 512)
    #expect((dict["height"] as? Int) == 512)
    #expect((dict["mode"] as? String) == "textToImage")
    #expect((dict["referenceImageCount"] as? Int) == 0)
    #expect((dict["loraAttached"] as? Bool) == false)
    #expect(dict["loraScale"] == nil, "loraScale should be absent when nil")
    #expect((dict["upsamplePromptRequested"] as? Bool) == false)
    #expect((dict["interpretImageCount"] as? Int) == 0)
  }

  // MARK: - Case 5: generationEnd

  @Test("generationEnd encodes discriminant and all associated values")
  func testGenerationEnd() throws {
    let dict = try roundTrip(
      .generationEnd(
        engineID: "flux2",
        modelID: "klein4b",
        success: true,
        durationSeconds: 12.5,
        outputDims: [512, 512, 3],
        actualSeed: 42
      )
    )
    #expect((dict["case"] as? String) == "generationEnd")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["success"] as? Bool) == true)
    #expect((dict["durationSeconds"] as? Double) == 12.5)
    #expect(dict["outputDims"] != nil)
    #expect(dict["actualSeed"] != nil)
  }

  // MARK: - Case 6: engineSelected

  @Test("engineSelected encodes discriminant and all associated values")
  func testEngineSelected() throws {
    let dict = try roundTrip(
      .engineSelected(
        engineID: "flux2", modelID: "klein4b", requestedFeature: "img2img", fallbackUsed: false
      )
    )
    #expect((dict["case"] as? String) == "engineSelected")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["requestedFeature"] as? String) == "img2img")
    #expect((dict["fallbackUsed"] as? Bool) == false)
  }

  // MARK: - Case 7: engineNotFound

  @Test("engineNotFound encodes discriminant and all associated values")
  func testEngineNotFound() throws {
    let dict = try roundTrip(
      .engineNotFound(modelID: "unknown-model", requestedEngineID: "missing-engine")
    )
    #expect((dict["case"] as? String) == "engineNotFound")
    #expect((dict["modelID"] as? String) == "unknown-model")
    #expect((dict["requestedEngineID"] as? String) == "missing-engine")
  }

  // MARK: - Case 8: engineFeatureNegotiated

  @Test("engineFeatureNegotiated encodes discriminant and all associated values")
  func testEngineFeatureNegotiated() throws {
    let dict = try roundTrip(
      .engineFeatureNegotiated(
        engineID: "flux2",
        requestedFeatures: ["img2img", "lora"],
        supportedFeatures: ["img2img"],
        unsupportedFeatures: ["lora"]
      )
    )
    #expect((dict["case"] as? String) == "engineFeatureNegotiated")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["requestedFeatures"] as? [String]) == ["img2img", "lora"])
    #expect((dict["supportedFeatures"] as? [String]) == ["img2img"])
    #expect((dict["unsupportedFeatures"] as? [String]) == ["lora"])
  }

  // MARK: - Case 9: memoryValidationStart

  @Test("memoryValidationStart encodes discriminant and all associated values")
  func testMemoryValidationStart() throws {
    let dict = try roundTrip(
      .memoryValidationStart(
        modelID: "klein4b", engineID: "flux2",
        estimatedRequiredMB: 8192.0, availableMB: 16384.0
      )
    )
    #expect((dict["case"] as? String) == "memoryValidationStart")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["estimatedRequiredMB"] as? Double) == 8192.0)
    #expect((dict["availableMB"] as? Double) == 16384.0)
  }

  // MARK: - Case 10: memoryValidationResult

  @Test("memoryValidationResult encodes discriminant, verdict rawValue, and all fields")
  func testMemoryValidationResult() throws {
    let dict = try roundTrip(
      .memoryValidationResult(
        modelID: "klein4b", engineID: "flux2",
        verdict: .sufficient, requiredMB: 8192.0, availableMB: 16384.0
      )
    )
    #expect((dict["case"] as? String) == "memoryValidationResult")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["verdict"] as? String) == "sufficient")
    #expect((dict["requiredMB"] as? Double) == 8192.0)
    #expect((dict["availableMB"] as? Double) == 16384.0)
  }

  @Test("memoryValidationResult encodes warningMarginal verdict rawValue")
  func testMemoryValidationResultMarginal() throws {
    let dict = try roundTrip(
      .memoryValidationResult(
        modelID: "klein9b", engineID: "flux2",
        verdict: .warningMarginal, requiredMB: 14000.0, availableMB: 15000.0
      )
    )
    #expect((dict["verdict"] as? String) == "warningMarginal")
  }

  // MARK: - Case 11: modelLoadStart

  @Test("modelLoadStart encodes discriminant and all associated values")
  func testModelLoadStart() throws {
    let dict = try roundTrip(
      .modelLoadStart(modelID: "klein4b", engineID: "flux2")
    )
    #expect((dict["case"] as? String) == "modelLoadStart")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["engineID"] as? String) == "flux2")
  }

  // MARK: - Case 12: modelLoadComplete

  @Test("modelLoadComplete encodes discriminant and all associated values")
  func testModelLoadComplete() throws {
    let dict = try roundTrip(
      .modelLoadComplete(modelID: "klein4b", engineID: "flux2", durationSeconds: 5.2)
    )
    #expect((dict["case"] as? String) == "modelLoadComplete")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["durationSeconds"] as? Double) == 5.2)
  }

  // MARK: - Case 13: modelUnload

  @Test("modelUnload encodes discriminant and all associated values")
  func testModelUnload() throws {
    let dict = try roundTrip(
      .modelUnload(modelID: "klein4b", engineID: "flux2")
    )
    #expect((dict["case"] as? String) == "modelUnload")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["engineID"] as? String) == "flux2")
  }

  // MARK: - Case 14: modelAvailabilityChecked

  @Test("modelAvailabilityChecked encodes discriminant and all associated values")
  func testModelAvailabilityChecked() throws {
    let dict = try roundTrip(
      .modelAvailabilityChecked(modelID: "klein4b", available: true)
    )
    #expect((dict["case"] as? String) == "modelAvailabilityChecked")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["available"] as? Bool) == true)
  }

  // MARK: - Case 15: modelDeleted

  @Test("modelDeleted encodes discriminant and all associated values")
  func testModelDeleted() throws {
    let dict = try roundTrip(
      .modelDeleted(modelID: "klein4b")
    )
    #expect((dict["case"] as? String) == "modelDeleted")
    #expect((dict["modelID"] as? String) == "klein4b")
  }

  // MARK: - Case 16: concurrencyGateRejected

  @Test("concurrencyGateRejected encodes discriminant and all associated values")
  func testConcurrencyGateRejected() throws {
    let dict = try roundTrip(
      .concurrencyGateRejected(
        engineID: "flux2", modelID: "klein4b", reason: "generation already in progress"
      )
    )
    #expect((dict["case"] as? String) == "concurrencyGateRejected")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["modelID"] as? String) == "klein4b")
    #expect((dict["reason"] as? String) == "generation already in progress")
  }

  // MARK: - Case 17: loraAttachStart

  @Test("loraAttachStart encodes discriminant and all associated values")
  func testLoraAttachStart() throws {
    let dict = try roundTrip(
      .loraAttachStart(
        engineID: "flux2", sourceURL: "/tmp/my-lora.safetensors", scale: 0.8
      )
    )
    #expect((dict["case"] as? String) == "loraAttachStart")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["sourceURL"] as? String) == "/tmp/my-lora.safetensors")
    #expect((dict["scale"] as? Double) == 0.8)
  }

  // MARK: - Case 18: loraAttachComplete

  @Test("loraAttachComplete encodes discriminant and all associated values")
  func testLoraAttachComplete() throws {
    let dict = try roundTrip(
      .loraAttachComplete(
        engineID: "flux2", sourceURL: "/tmp/my-lora.safetensors", durationSeconds: 1.1
      )
    )
    #expect((dict["case"] as? String) == "loraAttachComplete")
    #expect((dict["engineID"] as? String) == "flux2")
    #expect((dict["sourceURL"] as? String) == "/tmp/my-lora.safetensors")
    #expect((dict["durationSeconds"] as? Double) == 1.1)
  }

  // MARK: - Case 19: classifierForwardStart

  @Test("classifierForwardStart encodes discriminant and all associated values")
  func testClassifierForwardStart() throws {
    let dict = try roundTrip(
      .classifierForwardStart(imageDims: [224, 224, 3])
    )
    #expect((dict["case"] as? String) == "classifierForwardStart")
    #expect((dict["imageDims"] as? [Int]) == [224, 224, 3])
  }

  // MARK: - Case 20: classifierForwardComplete

  @Test("classifierForwardComplete encodes discriminant and all associated values")
  func testClassifierForwardComplete() throws {
    let dict = try roundTrip(
      .classifierForwardComplete(
        topLabel: "cat",
        topScore: 0.95,
        top5Labels: ["cat", "dog", "kitten", "puppy", "rabbit"],
        top5Scores: [0.95, 0.03, 0.01, 0.005, 0.002],
        durationSeconds: 0.12
      )
    )
    #expect((dict["case"] as? String) == "classifierForwardComplete")
    #expect((dict["topLabel"] as? String) == "cat")
    #expect((dict["topScore"] as? Double) == 0.95)
    #expect((dict["top5Labels"] as? [String]) == ["cat", "dog", "kitten", "puppy", "rabbit"])
    #expect(dict["top5Scores"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 0.12)
  }

  // MARK: - Case 21: featureExtractionStart

  @Test("featureExtractionStart encodes discriminant and all associated values")
  func testFeatureExtractionStart() throws {
    let dict = try roundTrip(
      .featureExtractionStart(imageDims: [518, 518, 3])
    )
    #expect((dict["case"] as? String) == "featureExtractionStart")
    #expect((dict["imageDims"] as? [Int]) == [518, 518, 3])
  }

  // MARK: - Case 22: featureExtractionComplete

  @Test("featureExtractionComplete encodes discriminant and featureStat")
  func testFeatureExtractionComplete() throws {
    let dict = try roundTrip(
      .featureExtractionComplete(
        featureDim: 768, featureStat: makeStat(), durationSeconds: 0.25
      )
    )
    #expect((dict["case"] as? String) == "featureExtractionComplete")
    #expect((dict["featureDim"] as? Int) == 768)
    #expect(dict["featureStat"] != nil, "featureStat should be encoded verbatim")
    #expect((dict["durationSeconds"] as? Double) == 0.25)
  }

  // MARK: - Case 23: errorThrown

  @Test("errorThrown encodes discriminant, phase rawValue, and errorDescription")
  func testErrorThrown() throws {
    let dict = try roundTrip(
      .errorThrown(phase: .generationFailed, errorDescription: "denoising failed")
    )
    #expect((dict["case"] as? String) == "errorThrown")
    #expect((dict["phase"] as? String) == "generationFailed")
    #expect((dict["errorDescription"] as? String) == "denoising failed")
  }

  @Test("errorThrown encodes other ErrorPhase rawValues")
  func testErrorThrownPhaseVariants() throws {
    let phases: [(VinetasTelemetryEvent.ErrorPhase, String)] = [
      (.clientInit, "clientInit"),
      (.engineRouting, "engineRouting"),
      (.modelLoad, "modelLoad"),
      (.loraAttach, "loraAttach"),
      (.classifierForward, "classifierForward"),
      (.featureExtraction, "featureExtraction"),
      (.other, "other"),
    ]
    for (phase, rawValue) in phases {
      let dict = try roundTrip(.errorThrown(phase: phase, errorDescription: "test"))
      #expect(
        (dict["phase"] as? String) == rawValue,
        "ErrorPhase.\(phase) should encode as '\(rawValue)'"
      )
    }
  }
}

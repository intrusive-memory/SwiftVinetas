import Foundation
import SwiftVinetas
import Tuberia

// MARK: - VinetasEventCodable
//
// Flattens each `VinetasTelemetryEvent` case to a JSON object with a top-level
// "case" discriminant key plus the case's named fields at the same level.
//
// Example output:
//   {"case":"generationStart","prompt":"…","engineID":"flux2",…}
//
// TuberiaTensorStat is already Codable (it conforms in SwiftTuberia), so
// featureExtractionComplete encodes the stat verbatim without redefining it.
//
// Covers all 23 top-level cases of VinetasTelemetryEvent (S1).

public struct VinetasEventCodable: Encodable {
  public let event: VinetasTelemetryEvent

  public init(event: VinetasTelemetryEvent) {
    self.event = event
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch event {

    // MARK: - Client lifecycle

    case .clientInitialized(let version, let registeredEngines, let deviceMemoryGB, let deviceArch):
      try container.encode("clientInitialized", forKey: .case)
      try container.encode(version, forKey: .version)
      try container.encode(registeredEngines, forKey: .registeredEngines)
      try container.encode(deviceMemoryGB, forKey: .deviceMemoryGB)
      try container.encode(deviceArch, forKey: .deviceArch)

    case .engineRegistered(let engineID, let reason):
      try container.encode("engineRegistered", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(reason, forKey: .reason)

    case .engineSkipped(let engineID, let reason):
      try container.encode("engineSkipped", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(reason, forKey: .reason)

    // MARK: - Generation request handoff

    case .generationStart(
      let
        prompt, let promptLength, let engineID, let modelID, let steps, let guidanceScale, let seed,
      let
        width, let height, let mode, let referenceImageCount, let loraAttached, let loraScale,
      let
        upsamplePromptRequested, let interpretImageCount
    ):
      try container.encode("generationStart", forKey: .case)
      try container.encode(prompt, forKey: .prompt)
      try container.encode(promptLength, forKey: .promptLength)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(steps, forKey: .steps)
      try container.encode(guidanceScale, forKey: .guidanceScale)
      try container.encode(seed, forKey: .seed)
      try container.encode(width, forKey: .width)
      try container.encode(height, forKey: .height)
      try container.encode(mode.rawValue, forKey: .mode)
      try container.encode(referenceImageCount, forKey: .referenceImageCount)
      try container.encode(loraAttached, forKey: .loraAttached)
      try container.encodeIfPresent(loraScale, forKey: .loraScale)
      try container.encode(upsamplePromptRequested, forKey: .upsamplePromptRequested)
      try container.encode(interpretImageCount, forKey: .interpretImageCount)

    case .generationEnd(
      let engineID, let modelID, let success, let durationSeconds, let outputDims, let actualSeed):
      try container.encode("generationEnd", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(success, forKey: .success)
      try container.encode(durationSeconds, forKey: .durationSeconds)
      try container.encodeIfPresent(outputDims, forKey: .outputDims)
      try container.encodeIfPresent(actualSeed, forKey: .actualSeed)

    // MARK: - Engine routing

    case .engineSelected(let engineID, let modelID, let requestedFeature, let fallbackUsed):
      try container.encode("engineSelected", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encodeIfPresent(requestedFeature, forKey: .requestedFeature)
      try container.encode(fallbackUsed, forKey: .fallbackUsed)

    case .engineNotFound(let modelID, let requestedEngineID):
      try container.encode("engineNotFound", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(requestedEngineID, forKey: .requestedEngineID)

    case .engineFeatureNegotiated(
      let
        engineID, let requestedFeatures, let supportedFeatures, let unsupportedFeatures
    ):
      try container.encode("engineFeatureNegotiated", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(requestedFeatures, forKey: .requestedFeatures)
      try container.encode(supportedFeatures, forKey: .supportedFeatures)
      try container.encode(unsupportedFeatures, forKey: .unsupportedFeatures)

    // MARK: - Memory pre-validation

    case .memoryValidationStart(let modelID, let engineID, let estimatedRequiredMB, let availableMB):
      try container.encode("memoryValidationStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(estimatedRequiredMB, forKey: .estimatedRequiredMB)
      try container.encode(availableMB, forKey: .availableMB)

    case .memoryValidationResult(
      let modelID, let engineID, let verdict, let requiredMB, let availableMB):
      try container.encode("memoryValidationResult", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(verdict.rawValue, forKey: .verdict)
      try container.encode(requiredMB, forKey: .requiredMB)
      try container.encode(availableMB, forKey: .availableMB)

    // MARK: - Model lifecycle

    case .modelLoadStart(let modelID, let engineID):
      try container.encode("modelLoadStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)

    case .modelLoadComplete(let modelID, let engineID, let durationSeconds):
      try container.encode("modelLoadComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case .modelUnload(let modelID, let engineID):
      try container.encode("modelUnload", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)

    case .modelAvailabilityChecked(let modelID, let available):
      try container.encode("modelAvailabilityChecked", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(available, forKey: .available)

    case .modelDeleted(let modelID):
      try container.encode("modelDeleted", forKey: .case)
      try container.encode(modelID, forKey: .modelID)

    // MARK: - Concurrency gate

    case .concurrencyGateRejected(let engineID, let modelID, let reason):
      try container.encode("concurrencyGateRejected", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(reason, forKey: .reason)

    // MARK: - LoRA

    case .loraAttachStart(let engineID, let sourceURL, let scale):
      try container.encode("loraAttachStart", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(sourceURL, forKey: .sourceURL)
      try container.encode(scale, forKey: .scale)

    case .loraAttachComplete(let engineID, let sourceURL, let durationSeconds):
      try container.encode("loraAttachComplete", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(sourceURL, forKey: .sourceURL)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Image understanding side-channels

    case .classifierForwardStart(let imageDims):
      try container.encode("classifierForwardStart", forKey: .case)
      try container.encode(imageDims, forKey: .imageDims)

    case .classifierForwardComplete(
      let
        topLabel, let topScore, let top5Labels, let top5Scores, let durationSeconds
    ):
      try container.encode("classifierForwardComplete", forKey: .case)
      try container.encode(topLabel, forKey: .topLabel)
      try container.encode(topScore, forKey: .topScore)
      try container.encode(top5Labels, forKey: .top5Labels)
      try container.encode(top5Scores, forKey: .top5Scores)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case .featureExtractionStart(let imageDims):
      try container.encode("featureExtractionStart", forKey: .case)
      try container.encode(imageDims, forKey: .imageDims)

    case .featureExtractionComplete(let featureDim, let featureStat, let durationSeconds):
      try container.encode("featureExtractionComplete", forKey: .case)
      try container.encode(featureDim, forKey: .featureDim)
      // TuberiaTensorStat is Codable — encode verbatim, no new fields added.
      try container.encode(featureStat, forKey: .featureStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Error side-channel

    case .errorThrown(let phase, let errorDescription):
      try container.encode("errorThrown", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(errorDescription, forKey: .errorDescription)
    }
  }

  // MARK: - CodingKeys

  private enum CodingKeys: String, CodingKey {
    case `case`
    case version
    case registeredEngines
    case deviceMemoryGB
    case deviceArch
    case engineID
    case reason
    case prompt
    case promptLength
    case modelID
    case steps
    case guidanceScale
    case seed
    case width
    case height
    case mode
    case referenceImageCount
    case loraAttached
    case loraScale
    case upsamplePromptRequested
    case interpretImageCount
    case success
    case durationSeconds
    case outputDims
    case actualSeed
    case requestedFeature
    case fallbackUsed
    case requestedEngineID
    case requestedFeatures
    case supportedFeatures
    case unsupportedFeatures
    case estimatedRequiredMB
    case availableMB
    case verdict
    case requiredMB
    case available
    case sourceURL
    case scale
    case imageDims
    case topLabel
    case topScore
    case top5Labels
    case top5Scores
    case featureDim
    case featureStat
    case phase
    case errorDescription
  }
}

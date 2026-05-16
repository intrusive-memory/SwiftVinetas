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

    case let .clientInitialized(version, registeredEngines, deviceMemoryGB, deviceArch):
      try container.encode("clientInitialized", forKey: .case)
      try container.encode(version, forKey: .version)
      try container.encode(registeredEngines, forKey: .registeredEngines)
      try container.encode(deviceMemoryGB, forKey: .deviceMemoryGB)
      try container.encode(deviceArch, forKey: .deviceArch)

    case let .engineRegistered(engineID, reason):
      try container.encode("engineRegistered", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(reason, forKey: .reason)

    case let .engineSkipped(engineID, reason):
      try container.encode("engineSkipped", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(reason, forKey: .reason)

    // MARK: - Generation request handoff

    case let .generationStart(
      prompt, promptLength, engineID, modelID, steps, guidanceScale, seed,
      width, height, mode, referenceImageCount, loraAttached, loraScale,
      upsamplePromptRequested, interpretImageCount
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

    case let .generationEnd(engineID, modelID, success, durationSeconds, outputDims, actualSeed):
      try container.encode("generationEnd", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(success, forKey: .success)
      try container.encode(durationSeconds, forKey: .durationSeconds)
      try container.encodeIfPresent(outputDims, forKey: .outputDims)
      try container.encodeIfPresent(actualSeed, forKey: .actualSeed)

    // MARK: - Engine routing

    case let .engineSelected(engineID, modelID, requestedFeature, fallbackUsed):
      try container.encode("engineSelected", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encodeIfPresent(requestedFeature, forKey: .requestedFeature)
      try container.encode(fallbackUsed, forKey: .fallbackUsed)

    case let .engineNotFound(modelID, requestedEngineID):
      try container.encode("engineNotFound", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(requestedEngineID, forKey: .requestedEngineID)

    case let .engineFeatureNegotiated(
      engineID, requestedFeatures, supportedFeatures, unsupportedFeatures
    ):
      try container.encode("engineFeatureNegotiated", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(requestedFeatures, forKey: .requestedFeatures)
      try container.encode(supportedFeatures, forKey: .supportedFeatures)
      try container.encode(unsupportedFeatures, forKey: .unsupportedFeatures)

    // MARK: - Memory pre-validation

    case let .memoryValidationStart(modelID, engineID, estimatedRequiredMB, availableMB):
      try container.encode("memoryValidationStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(estimatedRequiredMB, forKey: .estimatedRequiredMB)
      try container.encode(availableMB, forKey: .availableMB)

    case let .memoryValidationResult(modelID, engineID, verdict, requiredMB, availableMB):
      try container.encode("memoryValidationResult", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(verdict.rawValue, forKey: .verdict)
      try container.encode(requiredMB, forKey: .requiredMB)
      try container.encode(availableMB, forKey: .availableMB)

    // MARK: - Model lifecycle

    case let .modelLoadStart(modelID, engineID):
      try container.encode("modelLoadStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)

    case let .modelLoadComplete(modelID, engineID, durationSeconds):
      try container.encode("modelLoadComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case let .modelUnload(modelID, engineID):
      try container.encode("modelUnload", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(engineID, forKey: .engineID)

    case let .modelAvailabilityChecked(modelID, available):
      try container.encode("modelAvailabilityChecked", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(available, forKey: .available)

    case let .modelDeleted(modelID):
      try container.encode("modelDeleted", forKey: .case)
      try container.encode(modelID, forKey: .modelID)

    // MARK: - Concurrency gate

    case let .concurrencyGateRejected(engineID, modelID, reason):
      try container.encode("concurrencyGateRejected", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(reason, forKey: .reason)

    // MARK: - LoRA

    case let .loraAttachStart(engineID, sourceURL, scale):
      try container.encode("loraAttachStart", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(sourceURL, forKey: .sourceURL)
      try container.encode(scale, forKey: .scale)

    case let .loraAttachComplete(engineID, sourceURL, durationSeconds):
      try container.encode("loraAttachComplete", forKey: .case)
      try container.encode(engineID, forKey: .engineID)
      try container.encode(sourceURL, forKey: .sourceURL)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Image understanding side-channels

    case let .classifierForwardStart(imageDims):
      try container.encode("classifierForwardStart", forKey: .case)
      try container.encode(imageDims, forKey: .imageDims)

    case let .classifierForwardComplete(
      topLabel, topScore, top5Labels, top5Scores, durationSeconds
    ):
      try container.encode("classifierForwardComplete", forKey: .case)
      try container.encode(topLabel, forKey: .topLabel)
      try container.encode(topScore, forKey: .topScore)
      try container.encode(top5Labels, forKey: .top5Labels)
      try container.encode(top5Scores, forKey: .top5Scores)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case let .featureExtractionStart(imageDims):
      try container.encode("featureExtractionStart", forKey: .case)
      try container.encode(imageDims, forKey: .imageDims)

    case let .featureExtractionComplete(featureDim, featureStat, durationSeconds):
      try container.encode("featureExtractionComplete", forKey: .case)
      try container.encode(featureDim, forKey: .featureDim)
      // TuberiaTensorStat is Codable — encode verbatim, no new fields added.
      try container.encode(featureStat, forKey: .featureStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Error side-channel

    case let .errorThrown(phase, errorDescription):
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

import Foundation
import Flux2Core
import Tuberia

// MARK: - Flux2EventCodable
//
// Flattens each `Flux2TelemetryEvent` case to a JSON object with a top-level
// "case" discriminant key plus the case's named fields at the same level.
//
// Example output:
//   {"case":"denoiseLoopEnd","variant":"textToImage","totalSteps":28,…}
//
// TuberiaTensorStat is already Codable (it conforms in SwiftTuberia), so
// stat-bearing cases encode verbatim without redefining TuberiaTensorStat.
//
// Covers all 14 top-level cases of Flux2TelemetryEvent (Flux2Core 3.2.2+).

public struct Flux2EventCodable: Encodable {
  public let event: Flux2TelemetryEvent

  public init(event: Flux2TelemetryEvent) {
    self.event = event
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch event {

    // MARK: - Pipeline lifecycle

    case let .pipelineInit(model, quantization, vaeConfig):
      try container.encode("pipelineInit", forKey: .case)
      try container.encode(model, forKey: .model)
      try container.encode(quantization, forKey: .quantization)
      try container.encode(vaeConfig, forKey: .vaeConfig)

    case .pipelineDispose:
      try container.encode("pipelineDispose", forKey: .case)

    // MARK: - Weight loading

    case let .weightLoadComplete(component, paramCount, durationSeconds):
      try container.encode("weightLoadComplete", forKey: .case)
      try container.encode(component.rawValue, forKey: .component)
      try container.encode(paramCount, forKey: .paramCount)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Quantization

    case let .quantizationComplete(component, bits, groupSize, durationSeconds):
      try container.encode("quantizationComplete", forKey: .case)
      try container.encode(component.rawValue, forKey: .component)
      try container.encode(bits, forKey: .bits)
      try container.encode(groupSize, forKey: .groupSize)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Text encoding

    case let .textEncodeComplete(encoderName, finalPromptLength, embeddingStat, durationSeconds):
      try container.encode("textEncodeComplete", forKey: .case)
      try container.encode(encoderName, forKey: .encoderName)
      try container.encode(finalPromptLength, forKey: .finalPromptLength)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(embeddingStat, forKey: .embeddingStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Scheduler

    case let .schedulerConfigured(numInferenceSteps, shift, imageSeqLen, mu):
      try container.encode("schedulerConfigured", forKey: .case)
      try container.encode(numInferenceSteps, forKey: .numInferenceSteps)
      try container.encode(shift, forKey: .shift)
      try container.encode(imageSeqLen, forKey: .imageSeqLen)
      try container.encode(mu, forKey: .mu)

    // MARK: - Denoise loop

    case let .denoiseLoopStart(variant, totalSteps, latentShape, latentDtype):
      try container.encode("denoiseLoopStart", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(latentShape, forKey: .latentShape)
      try container.encode(latentDtype, forKey: .latentDtype)

    case let .denoiseLoopEnd(variant, totalSteps, completedSteps, finalLatentStat, durationSeconds):
      try container.encode("denoiseLoopEnd", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(completedSteps, forKey: .completedSteps)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(finalLatentStat, forKey: .finalLatentStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case let .denoiseStepStart(variant, stepIndex, totalSteps, t, latentShape, latentDtype):
      try container.encode("denoiseStepStart", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(stepIndex, forKey: .stepIndex)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(t, forKey: .t)
      try container.encode(latentShape, forKey: .latentShape)
      try container.encode(latentDtype, forKey: .latentDtype)

    case let .denoiseStepComplete(
      variant, stepIndex, totalSteps, t, latentStat, durationSeconds
    ):
      try container.encode("denoiseStepComplete", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(stepIndex, forKey: .stepIndex)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(t, forKey: .t)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(latentStat, forKey: .latentStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - VAE decode

    case let .vaeDecodeComplete(pixelStat, outputDims, durationSeconds):
      try container.encode("vaeDecodeComplete", forKey: .case)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(pixelStat, forKey: .pixelStat)
      try container.encode(outputDims, forKey: .outputDims)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Anomaly side-channel

    case let .numericalAnomaly(phase, kind, stat):
      try container.encode("numericalAnomaly", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(kind.rawValue, forKey: .kind)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(stat, forKey: .stat)

    // MARK: - Cancellation

    case let .generationCancelled(stepIndex):
      try container.encode("generationCancelled", forKey: .case)
      try container.encodeIfPresent(stepIndex, forKey: .stepIndex)

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
    case model
    case quantization
    case vaeConfig
    case component
    case paramCount
    case durationSeconds
    case encoderName
    case finalPromptLength
    case embeddingStat
    case numInferenceSteps
    case shift
    case imageSeqLen
    case mu
    case variant
    case totalSteps
    case latentShape
    case latentDtype
    case completedSteps
    case finalLatentStat
    case pixelStat
    case outputDims
    case phase
    case kind
    case stat
    case stepIndex
    case errorDescription
    // quantizationComplete
    case bits
    case groupSize
    // denoiseStep{Start,Complete}
    case t
    case latentStat
  }
}

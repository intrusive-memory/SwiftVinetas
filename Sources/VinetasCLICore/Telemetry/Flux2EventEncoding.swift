import Flux2Core
import Foundation
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

    case .pipelineInit(let model, let quantization, let vaeConfig):
      try container.encode("pipelineInit", forKey: .case)
      try container.encode(model, forKey: .model)
      try container.encode(quantization, forKey: .quantization)
      try container.encode(vaeConfig, forKey: .vaeConfig)

    case .pipelineDispose:
      try container.encode("pipelineDispose", forKey: .case)

    // MARK: - Weight loading

    case .weightLoadComplete(let component, let paramCount, let durationSeconds):
      try container.encode("weightLoadComplete", forKey: .case)
      try container.encode(component.rawValue, forKey: .component)
      try container.encode(paramCount, forKey: .paramCount)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Quantization

    case .quantizationComplete(let component, let bits, let groupSize, let durationSeconds):
      try container.encode("quantizationComplete", forKey: .case)
      try container.encode(component.rawValue, forKey: .component)
      try container.encode(bits, forKey: .bits)
      try container.encode(groupSize, forKey: .groupSize)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Text encoding

    case .textEncodeComplete(
      let encoderName, let finalPromptLength, let embeddingStat, let durationSeconds):
      try container.encode("textEncodeComplete", forKey: .case)
      try container.encode(encoderName, forKey: .encoderName)
      try container.encode(finalPromptLength, forKey: .finalPromptLength)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(embeddingStat, forKey: .embeddingStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Scheduler

    case .schedulerConfigured(let numInferenceSteps, let shift, let imageSeqLen, let mu):
      try container.encode("schedulerConfigured", forKey: .case)
      try container.encode(numInferenceSteps, forKey: .numInferenceSteps)
      try container.encode(shift, forKey: .shift)
      try container.encode(imageSeqLen, forKey: .imageSeqLen)
      try container.encode(mu, forKey: .mu)

    // MARK: - Denoise loop

    case .denoiseLoopStart(let variant, let totalSteps, let latentShape, let latentDtype):
      try container.encode("denoiseLoopStart", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(latentShape, forKey: .latentShape)
      try container.encode(latentDtype, forKey: .latentDtype)

    case .denoiseLoopEnd(
      let variant, let totalSteps, let completedSteps, let finalLatentStat, let durationSeconds):
      try container.encode("denoiseLoopEnd", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(completedSteps, forKey: .completedSteps)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(finalLatentStat, forKey: .finalLatentStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case .denoiseStepStart(
      let variant, let stepIndex, let totalSteps, let t, let latentShape, let latentDtype):
      try container.encode("denoiseStepStart", forKey: .case)
      try container.encode(variant.rawValue, forKey: .variant)
      try container.encode(stepIndex, forKey: .stepIndex)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(t, forKey: .t)
      try container.encode(latentShape, forKey: .latentShape)
      try container.encode(latentDtype, forKey: .latentDtype)

    case .denoiseStepComplete(
      let
        variant, let stepIndex, let totalSteps, let t, let latentStat, let durationSeconds
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

    case .vaeDecodeComplete(let pixelStat, let outputDims, let durationSeconds):
      try container.encode("vaeDecodeComplete", forKey: .case)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(pixelStat, forKey: .pixelStat)
      try container.encode(outputDims, forKey: .outputDims)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Anomaly side-channel

    case .numericalAnomaly(let phase, let kind, let stat):
      try container.encode("numericalAnomaly", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(kind.rawValue, forKey: .kind)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(stat, forKey: .stat)

    // MARK: - Cancellation

    case .generationCancelled(let stepIndex):
      try container.encode("generationCancelled", forKey: .case)
      try container.encodeIfPresent(stepIndex, forKey: .stepIndex)

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

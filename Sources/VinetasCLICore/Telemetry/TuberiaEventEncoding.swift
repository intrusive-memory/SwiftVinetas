import Foundation
import Tuberia

// MARK: - TuberiaEventCodable
//
// Flattens each `TuberiaTelemetryEvent` case to a JSON object with a top-level
// "case" discriminant key plus the case's named fields at the same level.
//
// Example output:
//   {"case":"denoiseStepStart","stepIndex":0,"totalSteps":28,…}
//
// TuberiaTensorStat is already Codable (it conforms in SwiftTuberia), so
// stat-bearing cases encode verbatim without redefining TuberiaTensorStat.
//
// Covers all 27 top-level cases of TuberiaTelemetryEvent.

public struct TuberiaEventCodable: Encodable {
  public let event: TuberiaTelemetryEvent

  public init(event: TuberiaTelemetryEvent) {
    self.event = event
  }

  // swiftlint:disable:next function_body_length
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch event {

    // MARK: - Lifecycle

    case .pipelineConfigured(
      let
        recipeName, let encoderType, let schedulerType, let backboneType, let decoderType,
      let rendererType,
      let
        encoderQuantization, let backboneQuantization, let decoderQuantization,
      let
        peakMemoryBytes, let phasedMemoryBytes
    ):
      try container.encode("pipelineConfigured", forKey: .case)
      try container.encode(recipeName, forKey: .recipeName)
      try container.encode(encoderType, forKey: .encoderType)
      try container.encode(schedulerType, forKey: .schedulerType)
      try container.encode(backboneType, forKey: .backboneType)
      try container.encode(decoderType, forKey: .decoderType)
      try container.encode(rendererType, forKey: .rendererType)
      try container.encode(encoderQuantization, forKey: .encoderQuantization)
      try container.encode(backboneQuantization, forKey: .backboneQuantization)
      try container.encode(decoderQuantization, forKey: .decoderQuantization)
      try container.encode(peakMemoryBytes, forKey: .peakMemoryBytes)
      try container.encode(phasedMemoryBytes, forKey: .phasedMemoryBytes)

    case .pipelineStart(
      let runID, let prompt, let steps, let guidanceScale, let seed, let width, let height):
      try container.encode("pipelineStart", forKey: .case)
      try container.encode(runID, forKey: .runID)
      try container.encode(prompt, forKey: .prompt)
      try container.encode(steps, forKey: .steps)
      try container.encode(guidanceScale, forKey: .guidanceScale)
      try container.encode(seed, forKey: .seed)
      try container.encode(width, forKey: .width)
      try container.encode(height, forKey: .height)

    case .pipelineEnd(let runID, let totalSteps, let durationSeconds, let success):
      try container.encode("pipelineEnd", forKey: .case)
      try container.encode(runID, forKey: .runID)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(durationSeconds, forKey: .durationSeconds)
      try container.encode(success, forKey: .success)

    // MARK: - Assembly validation

    case .assemblyCheckPassed(let check, let inlet, let outlet):
      try container.encode("assemblyCheckPassed", forKey: .case)
      try container.encode(check.rawValue, forKey: .check)
      try container.encode(inlet, forKey: .inlet)
      try container.encode(outlet, forKey: .outlet)

    case .assemblyCheckFailed(let check, let inlet, let outlet, let reason):
      try container.encode("assemblyCheckFailed", forKey: .case)
      try container.encode(check.rawValue, forKey: .check)
      try container.encode(inlet, forKey: .inlet)
      try container.encode(outlet, forKey: .outlet)
      try container.encode(reason, forKey: .reason)

    // MARK: - Memory gate

    case .memoryGateChecked(let requiredBytes, let passed):
      try container.encode("memoryGateChecked", forKey: .case)
      try container.encode(requiredBytes, forKey: .requiredBytes)
      try container.encode(passed, forKey: .passed)

    // MARK: - Weight loading

    case .weightLoadStart(let role, let componentID):
      try container.encode("weightLoadStart", forKey: .case)
      try container.encode(role, forKey: .role)
      try container.encode(componentID, forKey: .componentID)

    case .weightLoadComplete(
      let role, let componentID, let paramCount, let totalBytes, let durationSeconds):
      try container.encode("weightLoadComplete", forKey: .case)
      try container.encode(role, forKey: .role)
      try container.encode(componentID, forKey: .componentID)
      try container.encode(paramCount, forKey: .paramCount)
      try container.encode(totalBytes, forKey: .totalBytes)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - LoRA

    case .loraLoadStart(let componentID, let localPath, let scale, let activationKeyword):
      try container.encode("loraLoadStart", forKey: .case)
      try container.encodeIfPresent(componentID, forKey: .componentID)
      try container.encodeIfPresent(localPath, forKey: .localPath)
      try container.encode(scale, forKey: .scale)
      try container.encodeIfPresent(activationKeyword, forKey: .activationKeyword)

    case .loraLoadComplete(let adapterParamCount, let durationSeconds):
      try container.encode("loraLoadComplete", forKey: .case)
      try container.encode(adapterParamCount, forKey: .adapterParamCount)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case .loraApplied(let targetLayerCount):
      try container.encode("loraApplied", forKey: .case)
      try container.encode(targetLayerCount, forKey: .targetLayerCount)

    case .loraUnapplied(let restoredLayerCount):
      try container.encode("loraUnapplied", forKey: .case)
      try container.encode(restoredLayerCount, forKey: .restoredLayerCount)

    // MARK: - Component readiness

    case .componentReadinessChecked(let componentID, let ready):
      try container.encode("componentReadinessChecked", forKey: .case)
      try container.encode(componentID, forKey: .componentID)
      try container.encode(ready, forKey: .ready)

    // MARK: - Text encoder handoff

    case .textEncoderForwardStart(let role, let promptLength, let maxLength):
      try container.encode("textEncoderForwardStart", forKey: .case)
      try container.encode(role.rawValue, forKey: .role)
      try container.encode(promptLength, forKey: .promptLength)
      try container.encode(maxLength, forKey: .maxLength)

    case .textEncoderForwardComplete(let role, let embeddingStat, let maskStat, let durationSeconds):
      try container.encode("textEncoderForwardComplete", forKey: .case)
      try container.encode(role.rawValue, forKey: .role)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(embeddingStat, forKey: .embeddingStat)
      try container.encode(maskStat, forKey: .maskStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Scheduler

    case .schedulerConfigured(
      let
        steps, let startTimestep, let predictionType, let timestepsHead, let timestepsTail,
      let
        sigmasHead, let sigmasTail
    ):
      try container.encode("schedulerConfigured", forKey: .case)
      try container.encode(steps, forKey: .steps)
      try container.encodeIfPresent(startTimestep, forKey: .startTimestep)
      try container.encode(predictionType, forKey: .predictionType)
      try container.encode(timestepsHead, forKey: .timestepsHead)
      try container.encode(timestepsTail, forKey: .timestepsTail)
      try container.encode(sigmasHead, forKey: .sigmasHead)
      try container.encode(sigmasTail, forKey: .sigmasTail)

    // MARK: - Per-step denoise

    case .denoiseStepStart(
      let
        stepIndex, let totalSteps, let timestep, let sigma, let useCFG, let latentBeforeStat
    ):
      try container.encode("denoiseStepStart", forKey: .case)
      try container.encode(stepIndex, forKey: .stepIndex)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(timestep, forKey: .timestep)
      try container.encode(sigma, forKey: .sigma)
      try container.encode(useCFG, forKey: .useCFG)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(latentBeforeStat, forKey: .latentBeforeStat)

    case .denoiseStepComplete(
      let
        stepIndex, let totalSteps, let timestep, let sigma, let latentAfterStat, let predictionStat,
      let durationSeconds
    ):
      try container.encode("denoiseStepComplete", forKey: .case)
      try container.encode(stepIndex, forKey: .stepIndex)
      try container.encode(totalSteps, forKey: .totalSteps)
      try container.encode(timestep, forKey: .timestep)
      try container.encode(sigma, forKey: .sigma)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(latentAfterStat, forKey: .latentAfterStat)
      try container.encode(predictionStat, forKey: .predictionStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - CFG dtype cast

    case .cfgDtypeCast(let stepIndex, let fromDtype, let toDtype, let guidedPredictionStat):
      try container.encode("cfgDtypeCast", forKey: .case)
      try container.encode(stepIndex, forKey: .stepIndex)
      try container.encode(fromDtype, forKey: .fromDtype)
      try container.encode(toDtype, forKey: .toDtype)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(guidedPredictionStat, forKey: .guidedPredictionStat)

    // MARK: - Backbone boundary

    case .backboneForwardStart(let branch, let conditioningStat, let latentStat, let timestep):
      try container.encode("backboneForwardStart", forKey: .case)
      try container.encode(branch.rawValue, forKey: .branch)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(conditioningStat, forKey: .conditioningStat)
      try container.encode(latentStat, forKey: .latentStat)
      try container.encode(timestep, forKey: .timestep)

    case .backboneForwardComplete(let branch, let predictionStat, let durationSeconds):
      try container.encode("backboneForwardComplete", forKey: .case)
      try container.encode(branch.rawValue, forKey: .branch)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(predictionStat, forKey: .predictionStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Decoder handoff

    case .decoderDecodeStart(let latentStat, let scalingFactor):
      try container.encode("decoderDecodeStart", forKey: .case)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(latentStat, forKey: .latentStat)
      try container.encode(scalingFactor, forKey: .scalingFactor)

    case .decoderDecodeComplete(
      let outputStat, let durationSeconds, let residentBytesBefore, let residentBytesAfter):
      try container.encode("decoderDecodeComplete", forKey: .case)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(outputStat, forKey: .outputStat)
      try container.encode(durationSeconds, forKey: .durationSeconds)
      try container.encode(residentBytesBefore, forKey: .residentBytesBefore)
      try container.encode(residentBytesAfter, forKey: .residentBytesAfter)

    // MARK: - Renderer handoff

    case .rendererRenderStart(let modality, let inputStat):
      try container.encode("rendererRenderStart", forKey: .case)
      try container.encode(modality, forKey: .modality)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(inputStat, forKey: .inputStat)

    case .rendererRenderComplete(let outputBytes, let durationSeconds):
      try container.encode("rendererRenderComplete", forKey: .case)
      try container.encode(outputBytes, forKey: .outputBytes)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Anomaly side-channel

    case .numericalAnomaly(let phase, let kind, let stepIndex, let stat):
      try container.encode("numericalAnomaly", forKey: .case)
      try container.encode(phase, forKey: .phase)
      try container.encode(kind.rawValue, forKey: .kind)
      try container.encodeIfPresent(stepIndex, forKey: .stepIndex)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(stat, forKey: .stat)

    // MARK: - Error side-channel

    case .errorThrown(let phase, let errorDescription, let stepIndex):
      try container.encode("errorThrown", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(errorDescription, forKey: .errorDescription)
      try container.encodeIfPresent(stepIndex, forKey: .stepIndex)
    }
  }

  // MARK: - CodingKeys

  private enum CodingKeys: String, CodingKey {
    case `case`
    // pipelineConfigured
    case recipeName
    case encoderType
    case schedulerType
    case backboneType
    case decoderType
    case rendererType
    case encoderQuantization
    case backboneQuantization
    case decoderQuantization
    case peakMemoryBytes
    case phasedMemoryBytes
    // pipelineStart / pipelineEnd
    case runID
    case prompt
    case steps
    case guidanceScale
    case seed
    case width
    case height
    case totalSteps
    case durationSeconds
    case success
    // assembly
    case check
    case inlet
    case outlet
    case reason
    // memoryGate
    case requiredBytes
    case passed
    // weight load
    case role
    case componentID
    case paramCount
    case totalBytes
    // lora
    case localPath
    case scale
    case activationKeyword
    case adapterParamCount
    case targetLayerCount
    case restoredLayerCount
    // component readiness
    case ready
    // text encoder
    case promptLength
    case maxLength
    case embeddingStat
    case maskStat
    // scheduler
    case startTimestep
    case predictionType
    case timestepsHead
    case timestepsTail
    case sigmasHead
    case sigmasTail
    // denoise step
    case stepIndex
    case timestep
    case sigma
    case useCFG
    case latentBeforeStat
    case latentAfterStat
    case predictionStat
    // cfgDtypeCast
    case fromDtype
    case toDtype
    case guidedPredictionStat
    // backbone
    case branch
    case conditioningStat
    case latentStat
    // decoder
    case scalingFactor
    case outputStat
    case residentBytesBefore
    case residentBytesAfter
    // renderer
    case modality
    case inputStat
    case outputBytes
    // anomaly / error
    case phase
    case kind
    case stat
    case errorDescription
  }
}

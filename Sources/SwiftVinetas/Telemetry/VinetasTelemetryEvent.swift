import Foundation
import Tuberia  // for TuberiaTensorStat

public enum VinetasTelemetryEvent: Sendable {

  // --- Client lifecycle ---
  case clientInitialized(
    version: String, registeredEngines: [String], deviceMemoryGB: Int, deviceArch: String)
  case engineRegistered(engineID: String, reason: String)
  case engineSkipped(engineID: String, reason: String)

  // --- Generation request handoff (memory boundary on start/end) ---
  case generationStart(
    prompt: String,
    promptLength: Int,
    engineID: String,
    modelID: String,
    steps: Int,
    guidanceScale: Double,
    seed: UInt64,
    width: Int,
    height: Int,
    mode: GenerationModeTag,
    referenceImageCount: Int,
    loraAttached: Bool,
    loraScale: Double?,
    upsamplePromptRequested: Bool,
    interpretImageCount: Int
  )
  case generationEnd(
    engineID: String,
    modelID: String,
    success: Bool,
    durationSeconds: Double,
    outputDims: [Int]?,
    actualSeed: UInt64?
  )

  // --- Engine routing ---
  case engineSelected(
    engineID: String, modelID: String, requestedFeature: String?, fallbackUsed: Bool)
  case engineNotFound(modelID: String, requestedEngineID: String)
  case engineFeatureNegotiated(
    engineID: String, requestedFeatures: [String], supportedFeatures: [String],
    unsupportedFeatures: [String])

  // --- Memory pre-validation ---
  case memoryValidationStart(
    modelID: String, engineID: String, estimatedRequiredMB: Double, availableMB: Double)
  case memoryValidationResult(
    modelID: String, engineID: String, verdict: MemoryVerdict, requiredMB: Double,
    availableMB: Double)

  // --- Model lifecycle ---
  case modelLoadStart(modelID: String, engineID: String)
  case modelLoadComplete(modelID: String, engineID: String, durationSeconds: Double)
  case modelUnload(modelID: String, engineID: String)
  case modelAvailabilityChecked(modelID: String, available: Bool)
  case modelDeleted(modelID: String)

  // --- Concurrency gate ---
  case concurrencyGateRejected(engineID: String, modelID: String, reason: String)

  // --- LoRA at the engine level ---
  case loraAttachStart(engineID: String, sourceURL: String, scale: Double)
  case loraAttachComplete(engineID: String, sourceURL: String, durationSeconds: Double)

  // --- Image understanding side-channels ---
  case classifierForwardStart(imageDims: [Int])
  case classifierForwardComplete(
    topLabel: String, topScore: Double, top5Labels: [String], top5Scores: [Double],
    durationSeconds: Double)
  case featureExtractionStart(imageDims: [Int])
  case featureExtractionComplete(
    featureDim: Int, featureStat: TuberiaTensorStat, durationSeconds: Double)

  // --- Error side-channel ---
  case errorThrown(phase: ErrorPhase, errorDescription: String)

  public enum GenerationModeTag: String, Sendable {
    case textToImage
    case imageToImage
    case preview
  }

  public enum MemoryVerdict: String, Sendable {
    case sufficient
    case warningMarginal
    case insufficient
    case unavailable
  }

  public enum ErrorPhase: String, Sendable {
    case clientInit
    case engineRouting
    case engineNotFound
    case modelNotSupported
    case modelNotFound
    case modelDownload
    case modelLoad
    case memoryValidation
    case generationFailed
    case generationConcurrency
    case loraAttach
    case classifierForward
    case featureExtraction
    case other
  }
}

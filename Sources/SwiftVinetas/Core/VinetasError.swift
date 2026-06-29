import Foundation

/// Errors thrown by SwiftVinetas operations.
public enum VinetasError: Error, LocalizedError {
  case modelNotFound(String)
  case insufficientMemory(required: UInt64, available: UInt64)
  case generationFailed(String)
  case invalidPromptFile(URL)
  case downloadFailed(String)

  /// No engine registered with the given engine ID.
  case engineNotFound(engineID: String)

  /// The specified model is not supported by the given engine.
  case modelNotSupported(modelID: String, engineID: String)

  /// A LoRA adapter trained for one engine was used with a different engine.
  case loraIncompatible(loraEngine: String, currentEngine: String)

  /// The requested feature is not supported by the given engine.
  case engineFeatureUnsupported(feature: EngineFeature, engineID: String)

  /// One or more required model components are incomplete or corrupted on disk.
  ///
  /// Thrown by ``Flux2Engine/loadModel(_:progress:)`` when
  /// `Acervo.verifyIntegrity` returns `.partial` for a required component
  /// before the deep loader runs (C4 · R2.2 · R6). The user must re-download
  /// the model to restore a complete, hash-verified copy.
  case modelIncomplete(modelID: String, components: [String])

  public var errorDescription: String? {
    switch self {
    case .modelNotFound(let model):
      return
        "Model not found: '\(model)'. Run `vinetas download --model \(model)` to download it, or run `vinetas list` to see available models."
    case .insufficientMemory(let required, let available):
      let requiredGB = required / 1_073_741_824
      let availableGB = available / 1_073_741_824
      return
        "Insufficient memory: model requires \(requiredGB) GB but only \(availableGB) GB available. Close other applications to free memory, or try the Klein 4B model (`--model klein4b`) which requires 16 GB."
    case .generationFailed(let reason):
      return
        "Generation failed: \(reason). If this persists, try reducing image dimensions with `--aspect square` or lowering `--steps`."
    case .invalidPromptFile(let url):
      return
        "Could not parse prompt file at '\(url.path)'. Ensure the file exists, is valid YAML, and follows the SwiftVinetas prompt format."
    case .downloadFailed(let reason):
      return
        "Model download failed: \(reason). Check your network connection and try again with `vinetas download --model <model>`."
    case .engineNotFound(let engineID):
      return
        "No engine registered with ID '\(engineID)'. Available engines can be listed via VinetasClient.shared.router."
    case .modelNotSupported(let modelID, let engineID):
      return
        "Model '\(modelID)' is not supported by engine '\(engineID)'."
    case .loraIncompatible(let loraEngine, let currentEngine):
      return
        "LoRA adapter trained for engine '\(loraEngine)' is incompatible with current engine '\(currentEngine)'. Generation will proceed without LoRA."
    case .engineFeatureUnsupported(let feature, let engineID):
      return
        "Feature '\(feature)' is not supported by engine '\(engineID)'."
    case .modelIncomplete(let modelID, let components):
      let list = components.joined(separator: ", ")
      return
        "Model '\(modelID)' is incomplete or corrupted on disk — re-download it to continue. "
        + "Affected components: \(list)."
    }
  }
}

import Foundation

/// Errors thrown by SwiftVinetas operations.
public enum VinetasError: Error, LocalizedError {
  case modelNotFound(String)
  case insufficientMemory(required: UInt64, available: UInt64)
  case generationFailed(String)
  case invalidPromptFile(URL)
  case downloadFailed(String)

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
    }
  }
}

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
            "Model not found: \(model). Run `vinetas download --model \(model)` first."
        case .insufficientMemory(let required, let available):
            "Insufficient memory: model needs \(required / 1_073_741_824) GB but only \(available / 1_073_741_824) GB available."
        case .generationFailed(let reason):
            "Generation failed: \(reason)"
        case .invalidPromptFile(let url):
            "Could not parse prompt file: \(url.path)"
        case .downloadFailed(let reason):
            "Model download failed: \(reason)"
        }
    }
}

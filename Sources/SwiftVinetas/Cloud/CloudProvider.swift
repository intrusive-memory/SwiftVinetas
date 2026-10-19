import Foundation

/// A commercial image-generation vendor reachable over HTTPS with a
/// user-supplied API key.
///
/// Each provider is surfaced as its own ``ImageGenerationEngine``
/// (``CloudImageEngine``) under ``engineID``, so the existing
/// `engineID`-keyed routing, picker grouping, and telemetry work unchanged.
/// The vendor's models are enumerated in ``models``; the API key is read
/// through a ``CloudAPIKeyStoring`` at generation time and is never written to
/// `UserDefaults`, logs, telemetry, or any file.
///
/// Cloud models are **not** Pro-gated: the user pays the vendor directly.
public enum CloudProvider: String, CaseIterable, Sendable, Identifiable, Codable, Hashable {

  /// OpenAI Images API (`gpt-image-2.5` family).
  case openAI = "openai"

  /// Google Gemini API image models (Nano Banana family).
  case google = "google"

  /// Black Forest Labs' hosted FLUX API (`flux-2-pro`, `flux-2-flex`).
  case blackForestLabs = "bfl"

  /// Stability AI's Stable Image API (`core`, `ultra`).
  case stabilityAI = "stability"

  public var id: String { rawValue }

  /// The engine identifier models of this provider route through. Prefixed
  /// with `cloud-` so a cloud engine can never collide with an on-device
  /// engine (`flux2`, `pixart-sigma`).
  public var engineID: String { "cloud-\(rawValue)" }

  /// Full vendor name for settings screens and error messages.
  public var displayName: String {
    switch self {
    case .openAI: return "OpenAI"
    case .google: return "Google"
    case .blackForestLabs: return "Black Forest Labs"
    case .stabilityAI: return "Stability AI"
    }
  }

  /// Short name for an engine badge next to a prompt or picker section.
  public var shortName: String {
    switch self {
    case .openAI: return "OpenAI"
    case .google: return "Gemini"
    case .blackForestLabs: return "BFL"
    case .stabilityAI: return "Stability"
    }
  }

  /// Where the user obtains an API key.
  public var consoleURL: URL {
    switch self {
    case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
    case .google: return URL(string: "https://aistudio.google.com/apikey")!
    case .blackForestLabs: return URL(string: "https://dashboard.bfl.ai")!
    case .stabilityAI: return URL(string: "https://platform.stability.ai/account/keys")!
    }
  }

  /// The vendor's terms, used as the ``ModelLicense`` for cloud models.
  public var termsURL: URL {
    switch self {
    case .openAI: return URL(string: "https://openai.com/policies/terms-of-use")!
    case .google: return URL(string: "https://ai.google.dev/gemini-api/terms")!
    case .blackForestLabs: return URL(string: "https://bfl.ai/legal/terms-of-service")!
    case .stabilityAI: return URL(string: "https://stability.ai/terms-of-use")!
    }
  }

  /// Placeholder shown in an empty API-key field.
  public var keyPlaceholder: String {
    switch self {
    case .openAI: return "sk-…"
    case .google: return "AIza…"
    case .blackForestLabs: return "BFL API key"
    case .stabilityAI: return "sk-…"
    }
  }

  /// The environment variable ``EnvironmentAPIKeyStore`` reads first for this
  /// provider. This is how agents, cron shells, and CI supply a key without a
  /// keychain or a GUI session.
  public var environmentVariable: String {
    switch self {
    case .openAI: return "OPENAI_API_KEY"
    case .google: return "GEMINI_API_KEY"
    case .blackForestLabs: return "BFL_API_KEY"
    case .stabilityAI: return "STABILITY_API_KEY"
    }
  }

  /// Alternative variable names honoured after ``environmentVariable``, for
  /// vendors whose own SDKs accept more than one spelling.
  public var environmentVariableAliases: [String] {
    switch self {
    case .google: return ["GOOGLE_API_KEY"]
    case .openAI, .blackForestLabs, .stabilityAI: return []
    }
  }

  /// The models this provider exposes, in picker order.
  public var models: [CloudModelDescriptor] {
    switch self {
    case .openAI: return [.gptImage25Flare, .gptImage25Sunburst]
    case .google: return [.nanoBanana21, .gemini31FlashImage, .gemini3ProImage]
    case .blackForestLabs: return [.flux2Pro, .flux2Flex]
    case .stabilityAI: return [.stableImageCore, .stableImageUltra]
    }
  }

  /// Resolves an engine identifier back to its provider, or `nil` for an
  /// on-device engine.
  public static func provider(forEngineID engineID: String) -> CloudProvider? {
    allCases.first { $0.engineID == engineID }
  }
}

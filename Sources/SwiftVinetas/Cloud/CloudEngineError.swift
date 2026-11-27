import Foundation

/// Failures specific to the API-key-backed cloud engines.
///
/// Thrown unwrapped from ``CloudImageEngine`` through ``VinetasClient`` so a
/// host can branch on them: the CLI maps ``missingAPIKey(_:)`` and
/// ``moderated(provider:)`` to distinct exit codes.
public enum CloudEngineError: LocalizedError, Sendable, Equatable {

  /// No key resolved for the provider from any configured
  /// ``CloudAPIKeyStoring``.
  case missingAPIKey(CloudProvider)

  /// `generate` was called before `loadModel`.
  case noModelLoaded

  /// The descriptor handed to the engine is not one of its models.
  case unsupportedModel(modelID: String, engineID: String)

  /// The engine does not implement the requested feature (e.g. LoRA).
  case unsupportedFeature(String, provider: CloudProvider)

  /// The vendor returned a non-2xx status. `message` is the vendor's own
  /// explanation when the body carried one.
  case httpStatus(provider: CloudProvider, status: Int, message: String?)

  /// The vendor returned 2xx but the body was not what the adapter expects.
  case invalidResponse(provider: CloudProvider, detail: String)

  /// The vendor's safety filter rejected the prompt or the output.
  case moderated(provider: CloudProvider)

  /// An asynchronous job did not finish within the polling budget.
  case timedOut(provider: CloudProvider)

  /// The returned bytes could not be decoded as an image.
  case imageDecodingFailed(provider: CloudProvider)

  /// The requested aspect ratio is not one the model supports. Thrown before
  /// any request is made, so nothing is sent and nothing is billed.
  /// `requested` is the nearest Vinetas ratio to the request's width and
  /// height; `supported` is the model's ``CloudModelDescriptor/supportedAspectRatios``.
  case unsupportedAspectRatio(modelID: String, requested: AspectRatio, supported: [AspectRatio])

  /// The vendor no longer offers the model, or this key can't use it (for
  /// example, an OpenAI organisation that must be verified first). `modelID`
  /// is the Vinetas model ID (``CloudModelDescriptor/id``). `reason` is the
  /// vendor's own explanation when the body carried one.
  case modelUnavailable(provider: CloudProvider, modelID: String, reason: String?)

  /// The vendor rejected the API key itself. The vendor's message is never
  /// kept: some vendors echo part of the key back in it.
  case keyRejected(provider: CloudProvider, reason: KeyRejectionReason)

  /// Why a vendor rejected an API key.
  public enum KeyRejectionReason: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// The key existed but has expired or been revoked.
    case expired
    /// The vendor does not recognise the key.
    case invalid
    /// The key is valid but not allowed to use this service.
    case notPermitted
  }

  /// Where a host lets the user supply an API key. The error text names only
  /// the ways that actually work for the caller.
  public enum KeySourceHint: Sendable, Equatable {
    /// The Vinetas app: the environment variable or Settings → Cloud Engines.
    case appSettings
    /// The command-line tool: the environment variable only. It has no
    /// keychain access group, so a key saved in the app is invisible to it.
    case environmentOnly
  }

  /// Placeholder vendor message for a 401/403 that carried no body message.
  /// ``description(keySource:)`` expands it into the host-appropriate advice.
  static let authFallbackMessage = "check the API key"

  public var errorDescription: String? {
    description(keySource: .appSettings)
  }

  /// The error text with key-supply advice for `keySource`. ``errorDescription``
  /// is this with ``KeySourceHint/appSettings``; the CLI passes
  /// ``KeySourceHint/environmentOnly``.
  public func description(keySource: KeySourceHint) -> String {
    func advice(_ provider: CloudProvider) -> String {
      switch keySource {
      case .appSettings:
        return "\(provider.environmentVariable) or Vinetas → Settings → Cloud Engines"
      case .environmentOnly:
        return provider.environmentVariable
      }
    }
    switch self {
    case .missingAPIKey(let provider):
      switch keySource {
      case .appSettings:
        return
          "No \(provider.displayName) API key found. Set \(provider.environmentVariable) in the "
          + "environment, or add a key in Vinetas → Settings → Cloud Engines."
      case .environmentOnly:
        return
          "No \(provider.displayName) API key found. Set \(provider.environmentVariable) in the "
          + "environment."
      }
    case .noModelLoaded:
      return "The cloud engine has no model selected."
    case .unsupportedModel(let modelID, let engineID):
      return "Model \(modelID) is not served by engine \(engineID)."
    case .unsupportedFeature(let feature, let provider):
      return "\(feature) is not supported by \(provider.displayName)."
    case .unsupportedAspectRatio(let modelID, let requested, let supported):
      return
        "Model \(modelID) does not support the \(requested.rawValue) aspect ratio. "
        + "Supported: \(supported.map(\.rawValue).joined(separator: ", "))."
    case .httpStatus(let provider, let status, let rawMessage):
      let message =
        rawMessage == Self.authFallbackMessage
        ? "\(Self.authFallbackMessage) (\(advice(provider)))" : rawMessage
      if let message, !message.isEmpty {
        return "\(provider.displayName) returned HTTP \(status): \(message)"
      }
      return "\(provider.displayName) returned HTTP \(status)."
    case .invalidResponse(let provider, let detail):
      return "Unexpected response from \(provider.displayName): \(detail)"
    case .moderated(let provider):
      return "\(provider.displayName) declined this prompt under its content policy."
    case .timedOut(let provider):
      return "\(provider.displayName) did not finish the image in time."
    case .imageDecodingFailed(let provider):
      return "The image returned by \(provider.displayName) could not be decoded."
    case .modelUnavailable(let provider, let modelID, let reason):
      var text =
        "\(provider.displayName) no longer offers the model \(modelID), or your API key can't "
        + "use it. Choose another model, or check your account at \(provider.consoleURL.absoluteString)."
      if let reason, !reason.isEmpty {
        text += " \(provider.displayName) said: \(reason)"
      }
      return text
    case .keyRejected(let provider, let reason):
      let why: String
      switch reason {
      case .expired: why = "it has expired"
      case .invalid: why = "it isn't valid"
      case .notPermitted: why = "it isn't allowed to use this service"
      }
      return
        "\(provider.displayName) rejected your API key: \(why). Check or replace the key at "
        + "\(provider.consoleURL.absoluteString), then update it in \(advice(provider))."
    }
  }
}

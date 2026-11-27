import Foundation

/// What a request is, so ``CloudErrorClassifier`` knows which vendor errors it
/// may map to a specific ``CloudEngineError`` case.
enum CloudRequestKind: Sendable, Equatable {
  /// Not sent with the user's key (e.g. a signed image download URL). Every
  /// failure stays ``CloudEngineError/httpStatus(provider:status:message:)``.
  case unclassified
  /// Sent with the user's key, but not about a model (e.g. a BFL polling
  /// request). Only key rejections are classified.
  case authenticated
  /// A generation request for the Vinetas model `modelID`. Key rejections and
  /// "model not found / not allowed" are both classified.
  case generation(modelID: String)
}

/// Maps a vendor's non-2xx response to ``CloudEngineError/modelUnavailable(provider:modelID:reason:)``
/// or ``CloudEngineError/keyRejected(provider:reason:)`` (requirements R-10a,
/// § 10.1). Returns `nil` for anything else, so the caller falls back to
/// ``CloudEngineError/httpStatus(provider:status:message:)``.
///
/// The vendor's message is kept only for `modelUnavailable`. A key rejection
/// never carries it: OpenAI echoes part of the key back in its 401 message.
enum CloudErrorClassifier {

  static func classify(
    status: Int, body: Data, provider: CloudProvider, kind: CloudRequestKind
  ) -> CloudEngineError? {
    let modelID: String?
    switch kind {
    case .unclassified: return nil
    case .authenticated: modelID = nil
    case .generation(let id): modelID = id
    }
    let error = errorObject(body)
    switch provider {
    case .openAI: return openAI(status: status, error: error, modelID: modelID)
    case .google: return google(status: status, error: error, modelID: modelID)
    case .blackForestLabs:
      return bfl(status: status, message: CloudHTTP.errorMessage(from: body), modelID: modelID)
    case .stabilityAI:
      return stability(
        status: status, message: CloudHTTP.errorMessage(from: body), modelID: modelID)
    }
  }

  // MARK: - Vendors

  /// OpenAI: `400` with `error.param == "model"` (unknown model on
  /// generation), `404 model_not_found`, or a `403` about organisation
  /// verification → model unavailable. `401` → key rejected, with
  /// `expired_secret_key` kept apart from `invalid_api_key`. A `400` about any
  /// other parameter (e.g. `size`) is not classified.
  private static func openAI(status: Int, error: [String: Any]?, modelID: String?)
    -> CloudEngineError?
  {
    let code = error?["code"] as? String
    let param = error?["param"] as? String
    let message = error?["message"] as? String
    if status == 401 {
      return .keyRejected(
        provider: .openAI, reason: code == "expired_secret_key" ? .expired : .invalid)
    }
    guard let modelID else { return nil }
    switch status {
    case 400 where param == "model":
      return .modelUnavailable(provider: .openAI, modelID: modelID, reason: message)
    case 403, 404:
      let lowered = message?.lowercased() ?? ""
      let mentionsVerification =
        lowered.contains("verif")
        && (lowered.contains("organization") || lowered.contains("organisation"))
      if code == "model_not_found" || mentionsVerification {
        return .modelUnavailable(provider: .openAI, modelID: modelID, reason: message)
      }
      return nil
    default:
      return nil
    }
  }

  /// Google: `404` with `error.status == "NOT_FOUND"` (the `/models` and
  /// `:generateContent` shape) or flat `error.code == "not_found"` (the
  /// `/interactions` shape) → model unavailable. A `400`/`401` whose
  /// `ErrorInfo` reason is `API_KEY_INVALID` → key rejected (Google reports a
  /// bad key as `400 INVALID_ARGUMENT`, not 401). `403 PERMISSION_DENIED` →
  /// key not permitted.
  private static func google(status: Int, error: [String: Any]?, modelID: String?)
    -> CloudEngineError?
  {
    let statusName = error?["status"] as? String
    let flatCode = error?["code"] as? String
    let message = error?["message"] as? String
    let reasons = ((error?["details"] as? [[String: Any]]) ?? []).compactMap {
      $0["reason"] as? String
    }

    if reasons.contains("API_KEY_INVALID") {
      let expired = message?.lowercased().contains("expired") == true
      return .keyRejected(provider: .google, reason: expired ? .expired : .invalid)
    }
    if status == 403, statusName == "PERMISSION_DENIED" {
      return .keyRejected(provider: .google, reason: .notPermitted)
    }
    if status == 404, let modelID, statusName == "NOT_FOUND" || flatCode == "not_found" {
      return .modelUnavailable(provider: .google, modelID: modelID, reason: message)
    }
    return nil
  }

  /// Black Forest Labs: `404` on the model path → model unavailable; `401` →
  /// key invalid; `403` → key not permitted.
  private static func bfl(status: Int, message: String?, modelID: String?) -> CloudEngineError? {
    switch status {
    case 401: return .keyRejected(provider: .blackForestLabs, reason: .invalid)
    case 403: return .keyRejected(provider: .blackForestLabs, reason: .notPermitted)
    case 404:
      guard let modelID else { return nil }
      return .modelUnavailable(provider: .blackForestLabs, modelID: modelID, reason: message)
    default: return nil
    }
  }

  /// Stability AI: `404` on the model path → model unavailable; `401` → key
  /// invalid. `403` is the vendor's moderation response and is left alone.
  private static func stability(status: Int, message: String?, modelID: String?)
    -> CloudEngineError?
  {
    switch status {
    case 401: return .keyRejected(provider: .stabilityAI, reason: .invalid)
    case 404:
      guard let modelID else { return nil }
      return .modelUnavailable(provider: .stabilityAI, modelID: modelID, reason: message)
    default: return nil
    }
  }

  // MARK: - Body parsing

  /// The `error` object of a `{"error": {…}}` body, or `nil`.
  private static func errorObject(_ body: Data) -> [String: Any]? {
    guard !body.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else { return nil }
    return object["error"] as? [String: Any]
  }
}

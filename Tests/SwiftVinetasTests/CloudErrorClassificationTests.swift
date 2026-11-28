import Foundation
import Testing

@testable import SwiftVinetas

// Covers `CloudErrorClassifier` through each vendor adapter (requirements
// R-10, R-10a, R-11 and § 10.1): a vendor's "model not found / not allowed"
// response becomes `modelUnavailable`, a rejected key becomes `keyRejected`,
// and everything else stays `httpStatus`. Response bodies are the ones
// recorded from the live OpenAI and Google APIs on 2026-11-26 (no keys in
// them). BFL and Stability bodies are assumed (no keys yet; § 10.2), so those
// tests pin the status mapping, not the body.

// MARK: - URLProtocol stub

/// Same shape as the stub in `CloudEngineTests.swift`, but with its own
/// process-global state so this suite can't race with that file's suites.
private final class ErrorStubURLProtocol: URLProtocol, @unchecked Sendable {

  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var requests: [URLRequest] = []

  static func reset() {
    handler = nil
    requests = []
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ErrorStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

// MARK: - Recorded vendor bodies (requirements § 10.1)

private enum Body {
  /// `POST /v1/images/generations` with an unknown model.
  static let openAIUnknownModel = #"""
    {"error": {"message": "The model 'gpt-image-9-fake' does not exist.",
    "type": "image_generation_user_error", "param": "model", "code": "invalid_value"}}
    """#
  /// `POST /v1/images/generations` with a real model and a bad size.
  static let openAIBadSize = #"""
    {"error": {"message": "Invalid size '1x1'. Width and height must both be divisible by 16.",
    "type": "image_generation_user_error", "param": "size", "code": "invalid_value"}}
    """#
  /// `GET /v1/models/{id}` with an unknown model.
  static let openAIModelNotFound = #"""
    {"error": {"message": "The model 'gpt-image-9-fake' does not exist",
    "type": "invalid_request_error", "param": "model", "code": "model_not_found"}}
    """#
  /// A bad key. The vendor echoes part of the key back in the message.
  static let openAIInvalidKey = #"""
    {"error": {"message": "Incorrect API key provided: sk-fake. You can find your API key at https://platform.openai.com/account/api-keys.",
    "type": "invalid_request_error", "param": null, "code": "invalid_api_key"}}
    """#
  /// An expired key (same shape as `openAIInvalidKey`, different code).
  static let openAIExpiredKey = #"""
    {"error": {"message": "Your API key has expired.",
    "type": "invalid_request_error", "param": null, "code": "expired_secret_key"}}
    """#
  /// An unverified organisation (unconfirmed shape, § 10.2 item 1).
  static let openAIUnverifiedOrg = #"""
    {"error": {"message": "Your organization must be verified to use the model `gpt-image-2.5-flare`.",
    "type": "invalid_request_error", "param": null, "code": null}}
    """#
  /// `POST /v1beta/interactions` with an unknown model: a flat error body.
  static let googleInteractionsNotFound = #"""
    {"error":{"message":"Model 'gemini-9-fake-image' not found. Did you mean 'gemini-3-pro-image'? Please verify the model name against the supported list: https://ai.google.dev/gemini-api/docs/models","code":"not_found"}}
    """#
  /// `:generateContent` with an unknown model: the nested `/models` shape.
  static let googleGenerateContentNotFound = #"""
    {"error": {"code": 404,
    "message": "models/gemini-9-fake-image is not found for API version v1beta, or is not supported for generateContent. Call ModelService.ListModels to see the list of available models and their supported methods.",
    "status": "NOT_FOUND"}}
    """#
  /// A bad key: `400 INVALID_ARGUMENT` with reason `API_KEY_INVALID`.
  static let googleInvalidKey = #"""
    {"error": {"code": 400, "message": "API key not valid. Please pass a valid API key.",
    "status": "INVALID_ARGUMENT",
    "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "API_KEY_INVALID",
    "domain": "googleapis.com", "metadata": {"service": "generativelanguage.googleapis.com"}},
    {"@type": "type.googleapis.com/google.rpc.LocalizedMessage", "locale": "en-US",
    "message": "API key not valid. Please pass a valid API key."}]}}
    """#
  static let googlePermissionDenied = #"""
    {"error": {"code": 403, "message": "The caller does not have permission",
    "status": "PERMISSION_DENIED"}}
    """#
  static let bflNotFound = #"{"detail": "Not Found"}"#
  static let stabilityNotFound = #"""
    {"id": "0", "name": "not_found", "errors": ["The requested model was not found."]}
    """#
  static let stabilityModerated = #"""
    {"id": "0", "name": "content_moderation", "errors": ["Your request was flagged."]}
    """#
}

// MARK: - Tests

@Suite("Cloud vendor error classification", .serialized)
struct CloudErrorClassificationTests {

  /// Runs one generation through `client` against a stub that always answers
  /// `status` with `body`, and returns the thrown error.
  private func failure(
    _ provider: CloudProvider, client: any CloudProviderClient, model: CloudModelDescriptor,
    status: Int, body: String
  ) async throws -> CloudEngineError {
    defer { ErrorStubURLProtocol.reset() }
    ErrorStubURLProtocol.handler = { request in
      (
        HTTPURLResponse(
          url: request.url!, statusCode: status, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!,
        Data(body.utf8)
      )
    }
    let engine = CloudImageEngine(
      provider: provider,
      keyStore: InMemoryAPIKeyStore(keys: [provider: "test-key-not-real"]),
      client: client,
      session: ErrorStubURLProtocol.makeSession())
    try await engine.loadModel(model, progress: { _ in })
    let request = GenerationRequest(
      prompt: "a lighthouse at dusk", negativePrompt: nil, steps: 28, guidanceScale: 3.5,
      seed: 7, width: 1024, height: 1024, mode: .textToImage)
    do {
      _ = try await engine.generate(request: request, stepProgress: nil)
    } catch let error as CloudEngineError {
      return error
    }
    Issue.record("expected a CloudEngineError")
    return .noModelLoaded
  }

  // OpenAI

  @Test("OpenAI 400 with param model on generation is modelUnavailable")
  func openAIUnknownModelOnGeneration() async throws {
    let model = CloudModelDescriptor.gptImage25Flare
    let error = try await failure(
      .openAI, client: OpenAIImageClient(), model: model, status: 400,
      body: Body.openAIUnknownModel)
    #expect(
      error
        == .modelUnavailable(
          provider: .openAI, modelID: model.id,
          reason: "The model 'gpt-image-9-fake' does not exist."))
  }

  @Test("OpenAI 404 model_not_found is modelUnavailable")
  func openAIModelNotFound() async throws {
    let model = CloudModelDescriptor.gptImage26Flare
    let error = try await failure(
      .openAI, client: OpenAIImageClient(), model: model, status: 404,
      body: Body.openAIModelNotFound)
    guard case .modelUnavailable(.openAI, model.id, _) = error else {
      Issue.record("unexpected \(error)")
      return
    }
  }

  @Test("OpenAI 403 about organisation verification is modelUnavailable with that reason")
  func openAIUnverifiedOrganisation() async throws {
    let model = CloudModelDescriptor.gptImage25Flare
    let error = try await failure(
      .openAI, client: OpenAIImageClient(), model: model, status: 403,
      body: Body.openAIUnverifiedOrg)
    guard case .modelUnavailable(.openAI, model.id, let reason) = error else {
      Issue.record("unexpected \(error)")
      return
    }
    #expect(reason?.contains("must be verified") == true)
  }

  @Test("OpenAI 401 invalid_api_key is keyRejected(.invalid) and never echoes the key")
  func openAIInvalidKey() async throws {
    let error = try await failure(
      .openAI, client: OpenAIImageClient(), model: .gptImage25Flare, status: 401,
      body: Body.openAIInvalidKey)
    #expect(error == .keyRejected(provider: .openAI, reason: .invalid))
    for keySource in [CloudEngineError.KeySourceHint.appSettings, .environmentOnly] {
      let text = error.description(keySource: keySource)
      #expect(!text.contains("sk-"))
      #expect(!text.contains("test-key-not-real"))
      #expect(text.contains("platform.openai.com"))
    }
  }

  @Test("OpenAI 401 expired_secret_key is keyRejected(.expired)")
  func openAIExpiredKey() async throws {
    let error = try await failure(
      .openAI, client: OpenAIImageClient(), model: .gptImage25Flare, status: 401,
      body: Body.openAIExpiredKey)
    #expect(error == .keyRejected(provider: .openAI, reason: .expired))
  }

  @Test("OpenAI 400 with param size stays httpStatus")
  func openAIBadSizeStaysHTTPStatus() async throws {
    let error = try await failure(
      .openAI, client: OpenAIImageClient(), model: .gptImage25Flare, status: 400,
      body: Body.openAIBadSize)
    #expect(
      error
        == .httpStatus(
          provider: .openAI, status: 400,
          message: "Invalid size '1x1'. Width and height must both be divisible by 16."))
  }

  // Google

  @Test("Google 404 with flat code not_found on /interactions is modelUnavailable")
  func googleInteractionsNotFound() async throws {
    let model = CloudModelDescriptor.gemini31FlashImage
    let error = try await failure(
      .google, client: GeminiImageClient(), model: model, status: 404,
      body: Body.googleInteractionsNotFound)
    guard case .modelUnavailable(.google, model.id, let reason) = error else {
      Issue.record("unexpected \(error)")
      return
    }
    #expect(reason?.contains("gemini-9-fake-image") == true)
  }

  @Test("Google 404 with status NOT_FOUND is modelUnavailable")
  func googleNestedNotFound() async throws {
    let model = CloudModelDescriptor.nanoBanana21
    let error = try await failure(
      .google, client: GeminiImageClient(), model: model, status: 404,
      body: Body.googleGenerateContentNotFound)
    guard case .modelUnavailable(.google, model.id, _) = error else {
      Issue.record("unexpected \(error)")
      return
    }
  }

  @Test("Google 400 with reason API_KEY_INVALID is keyRejected(.invalid)")
  func googleInvalidKey() async throws {
    let error = try await failure(
      .google, client: GeminiImageClient(), model: .gemini31FlashImage, status: 400,
      body: Body.googleInvalidKey)
    #expect(error == .keyRejected(provider: .google, reason: .invalid))
    let app = try #require(error.errorDescription)
    #expect(app.contains("aistudio.google.com"))
    #expect(app.contains("Settings → Cloud Engines"))
    let cli = error.description(keySource: .environmentOnly)
    #expect(cli.contains("GEMINI_API_KEY"))
    #expect(!cli.contains("Settings"))
  }

  @Test("Google 403 PERMISSION_DENIED is keyRejected(.notPermitted)")
  func googlePermissionDenied() async throws {
    let error = try await failure(
      .google, client: GeminiImageClient(), model: .gemini31FlashImage, status: 403,
      body: Body.googlePermissionDenied)
    #expect(error == .keyRejected(provider: .google, reason: .notPermitted))
  }

  // Black Forest Labs

  @Test("BFL 404 on the model path is modelUnavailable")
  func bflNotFound() async throws {
    let model = CloudModelDescriptor.flux2Pro
    let error = try await failure(
      .blackForestLabs, client: BFLImageClient(), model: model, status: 404,
      body: Body.bflNotFound)
    guard case .modelUnavailable(.blackForestLabs, model.id, _) = error else {
      Issue.record("unexpected \(error)")
      return
    }
  }

  @Test("BFL 401 is keyRejected(.invalid) and 403 is keyRejected(.notPermitted)")
  func bflKeyRejected() async throws {
    let unauthorized = try await failure(
      .blackForestLabs, client: BFLImageClient(), model: .flux2Pro, status: 401,
      body: #"{"detail": "Not authenticated"}"#)
    #expect(unauthorized == .keyRejected(provider: .blackForestLabs, reason: .invalid))
    let forbidden = try await failure(
      .blackForestLabs, client: BFLImageClient(), model: .flux2Pro, status: 403,
      body: #"{"detail": "Forbidden"}"#)
    #expect(forbidden == .keyRejected(provider: .blackForestLabs, reason: .notPermitted))
  }

  // Stability AI

  @Test("Stability 404 on the model path is modelUnavailable")
  func stabilityNotFound() async throws {
    let model = CloudModelDescriptor.stableImageCore
    let error = try await failure(
      .stabilityAI, client: StabilityImageClient(), model: model, status: 404,
      body: Body.stabilityNotFound)
    guard case .modelUnavailable(.stabilityAI, model.id, _) = error else {
      Issue.record("unexpected \(error)")
      return
    }
  }

  @Test("Stability 401 is keyRejected(.invalid)")
  func stabilityUnauthorized() async throws {
    let error = try await failure(
      .stabilityAI, client: StabilityImageClient(), model: .stableImageCore, status: 401,
      body: #"{"id": "0", "name": "unauthorized", "errors": ["authentication failed"]}"#)
    #expect(error == .keyRejected(provider: .stabilityAI, reason: .invalid))
  }

  @Test("Stability 403 (moderation) stays httpStatus")
  func stabilityForbiddenUnchanged() async throws {
    let error = try await failure(
      .stabilityAI, client: StabilityImageClient(), model: .stableImageCore, status: 403,
      body: Body.stabilityModerated)
    #expect(
      error
        == .httpStatus(provider: .stabilityAI, status: 403, message: "Your request was flagged."))
  }

  // Retry and scope

  @Test("a classified error is not retried: one request only")
  func classifiedErrorsAreNotRetried() async throws {
    let cases: [(Int, String)] = [
      (400, Body.openAIUnknownModel), (401, Body.openAIInvalidKey),
      (404, Body.openAIModelNotFound),
    ]
    for (status, body) in cases {
      defer { ErrorStubURLProtocol.reset() }
      ErrorStubURLProtocol.handler = { request in
        (
          HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
          Data(body.utf8)
        )
      }
      await #expect(throws: CloudEngineError.self) {
        _ = try await CloudHTTP.perform(
          URLRequest(url: URL(string: "https://stub.invalid/v1/images/generations")!),
          session: ErrorStubURLProtocol.makeSession(), provider: .openAI,
          kind: .generation(modelID: "gpt-image-2.5-flare"),
          retryDelays: CloudHTTP.defaultRetryDelays)
      }
      #expect(ErrorStubURLProtocol.requests.count == 1)
    }
  }

  @Test("an unclassified request (e.g. an image download) keeps httpStatus")
  func unclassifiedRequestKeepsHTTPStatus() async throws {
    defer { ErrorStubURLProtocol.reset() }
    ErrorStubURLProtocol.handler = { request in
      (
        HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
        Data(Body.bflNotFound.utf8)
      )
    }
    await #expect(
      throws: CloudEngineError.httpStatus(
        provider: .blackForestLabs, status: 404, message: "Not Found")
    ) {
      _ = try await CloudHTTP.perform(
        URLRequest(url: URL(string: "https://stub.invalid/sample.png")!),
        session: ErrorStubURLProtocol.makeSession(), provider: .blackForestLabs)
    }
  }

  @Test("modelUnavailable says the vendor no longer offers the model and names its console")
  func modelUnavailableDescription() {
    let error = CloudEngineError.modelUnavailable(
      provider: .google, modelID: "gemini-3-pro-image", reason: nil)
    let text = error.description(keySource: .environmentOnly)
    #expect(text.contains("no longer offers the model gemini-3-pro-image"))
    #expect(text.contains("aistudio.google.com"))
  }
}

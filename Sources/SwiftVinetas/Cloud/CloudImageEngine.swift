import Foundation

/// An ``ImageGenerationEngine`` backed by one ``CloudProvider``'s HTTP API.
///
/// Interchangeable with ``Flux2Engine`` / ``PixArtEngine`` at every call
/// site: ``VinetasClient`` registers one instance per provider by default,
/// so a ``CloudModelDescriptor`` routes through ``EngineRouter`` like any
/// other model. Nothing is downloaded or loaded into memory — `loadModel`
/// only records the selected model and checks that a key resolves, and the
/// model-management methods are no-ops.
///
/// Keys come from the injected ``CloudAPIKeyStoring`` (by default
/// ``ChainedAPIKeyStore/default``: environment, then shared keychain) and are
/// read per call; they never appear in errors, telemetry, or logs.
public actor CloudImageEngine: ImageGenerationEngine {

  public nonisolated let provider: CloudProvider

  /// Where this engine resolves keys from. Hosts read ``CloudAPIKeyStoring/keySource(for:)``
  /// to show "configured / not configured" without ever touching the key.
  public nonisolated let keyStore: any CloudAPIKeyStoring

  private let client: any CloudProviderClient
  private let session: URLSession

  /// The model selected by the last successful `loadModel`.
  private var loadedModel: CloudModelDescriptor?

  /// Creates an engine for `provider` with the production vendor adapter.
  ///
  /// - Parameters:
  ///   - provider: The vendor this engine fronts.
  ///   - keyStore: Where API keys resolve from; defaults to the
  ///     environment-then-keychain chain.
  ///   - session: The `URLSession` to use; `nil` builds one tuned for slow
  ///     image endpoints (long timeouts, no response cache).
  public init(
    provider: CloudProvider,
    keyStore: any CloudAPIKeyStoring = ChainedAPIKeyStore.default,
    session: URLSession? = nil
  ) {
    self.init(provider: provider, keyStore: keyStore, client: nil, session: session)
  }

  init(
    provider: CloudProvider,
    keyStore: any CloudAPIKeyStoring,
    client: (any CloudProviderClient)?,
    session: URLSession? = nil
  ) {
    self.provider = provider
    self.keyStore = keyStore
    self.client = client ?? Self.defaultClient(for: provider)
    self.session = session ?? CloudHTTP.makeSession()
  }

  static func defaultClient(for provider: CloudProvider) -> any CloudProviderClient {
    switch provider {
    case .openAI: return OpenAIImageClient()
    case .google: return GeminiImageClient()
    case .blackForestLabs: return BFLImageClient()
    case .stabilityAI: return StabilityImageClient()
    }
  }

  // MARK: - Identity & catalog

  public nonisolated var engineID: String { provider.engineID }

  public nonisolated var supportedModels: [any ModelDescriptor] { provider.models }

  public nonisolated func supports(_ feature: EngineFeature) -> Bool {
    switch feature {
    case .textToImage: return true
    case .negativePrompt: return provider.models.contains { $0.supportsNegativePrompt }
    case .imageToImage(let count):
      return provider.models.contains { $0.maxReferenceImages >= max(1, count) }
    case .loraInference, .loraTraining, .promptUpsampling: return false
    }
  }

  /// The selected model's vendor limit; `0` for providers whose adapter
  /// sends text only, and for descriptors this engine does not serve.
  public nonisolated func maxReferenceImages(for model: any ModelDescriptor) -> Int {
    (try? resolve(model))?.maxReferenceImages ?? 0
  }

  // MARK: - Lifecycle

  public func loadModel(
    _ model: any ModelDescriptor,
    progress: @escaping @Sendable (LoadProgress) -> Void
  ) async throws {
    let descriptor = try resolve(model)
    guard keyStore.apiKey(for: provider) != nil else {
      throw CloudEngineError.missingAPIKey(provider)
    }
    loadedModel = descriptor
    progress(LoadProgress(phase: "Ready", fraction: 1.0))
  }

  public func unloadModel() async {
    loadedModel = nil
  }

  // MARK: - Generation

  public func generate(
    request: GenerationRequest,
    stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
  ) async throws -> GenerationResult {
    guard let model = loadedModel else { throw CloudEngineError.noModelLoaded }
    guard let apiKey = keyStore.apiKey(for: provider) else {
      throw CloudEngineError.missingAPIKey(provider)
    }
    if case .imageToImage(let references) = request.mode,
      references.count > model.maxReferenceImages
    {
      guard model.maxReferenceImages > 0 else {
        throw CloudEngineError.unsupportedFeature("Image-to-image", provider: provider)
      }
      throw VinetasError.tooManyReferences(
        model: model.id, max: model.maxReferenceImages, got: references.count)
    }

    // Cloud models follow instructions rather than sampler parameters, so the
    // structured bundle (style, frame, aspect, character, reference roles) is
    // spelled out in the prompt itself. Hand-built requests without a bundle
    // go through verbatim.
    var vendorRequest = request
    if let bundle = request.bundle {
      vendorRequest.prompt = bundle.rendered(nativeNegativePrompt: model.supportsNegativePrompt)
    }

    let start = Date()
    let output = try await client.generate(
      vendorRequest, model: model, apiKey: apiKey, session: session)
    let duration = Date().timeIntervalSince(start)

    return GenerationResult(
      image: output.image,
      usedPrompt: vendorRequest.prompt,
      seed: output.seed ?? request.seed ?? 0,
      durationSeconds: duration,
      modelID: model.id
    )
  }

  /// The exact prompt text this engine would send for `request` on `model`,
  /// without contacting the vendor. Backs `vinetas generate --dry-run`.
  public nonisolated func vendorPrompt(
    for request: GenerationRequest, model: any ModelDescriptor
  ) -> String {
    guard let bundle = request.bundle else { return request.prompt }
    let nativeNegative = (try? resolve(model))?.supportsNegativePrompt ?? false
    return bundle.rendered(nativeNegativePrompt: nativeNegative)
  }

  // MARK: - LoRA (unsupported)

  public func loadLoRA(at path: URL, scale: Float) async throws {
    throw CloudEngineError.unsupportedFeature("LoRA", provider: provider)
  }

  public func unloadLoRA() async {}

  // MARK: - Model management (no-ops: nothing lives on disk)

  public func download(
    _ model: any ModelDescriptor,
    progress: @Sendable (DownloadProgress) -> Void
  ) async throws {
    _ = try resolve(model)
    progress(DownloadProgress(fraction: 1.0, message: "Cloud model — nothing to download"))
  }

  /// `true` when `model` belongs to this provider and a key resolves.
  public func isAvailable(_ model: any ModelDescriptor) async -> Bool {
    (try? resolve(model)) != nil && keyStore.apiKey(for: provider) != nil
  }

  public func delete(_ model: any ModelDescriptor) async throws {}

  public func diskSize(of model: any ModelDescriptor) async -> Int64? { nil }

  /// Cloud models run on the vendor's hardware; local memory is irrelevant.
  public nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation {
    .ok
  }

  // MARK: - Helpers

  private nonisolated func resolve(_ model: any ModelDescriptor) throws -> CloudModelDescriptor {
    guard let descriptor = model as? CloudModelDescriptor, descriptor.provider == provider else {
      throw CloudEngineError.unsupportedModel(modelID: model.id, engineID: engineID)
    }
    return descriptor
  }
}

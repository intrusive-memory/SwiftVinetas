import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas

// Covers the API-key-backed cloud engines in the library: catalog shape, key
// stores and the resolution chain, `EngineRouter` registration, the default
// `VinetasClient` wiring, engine lifecycle rules, and each vendor adapter's
// request/response shaping against a stubbed `URLProtocol` (no network).

// MARK: - URLProtocol stub

/// Routes every request made through a stub session to a per-test handler.
/// The handler is process-global, so the suites that use it are `.serialized`.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {

  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  /// Every request the stub saw, in order.
  nonisolated(unsafe) static var requests: [URLRequest] = []

  static func reset() {
    handler = nil
    requests = []
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
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

extension URLRequest {
  /// `httpBody` is `nil` inside a `URLProtocol`; the body arrives as a stream.
  fileprivate var bodyData: Data {
    if let body = httpBody { return body }
    guard let stream = httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }

  fileprivate var jsonBody: [String: Any] {
    (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]) ?? [:]
  }
}

private func httpResponse(
  _ url: URL?, status: Int = 200, headers: [String: String] = [:]
) -> HTTPURLResponse {
  HTTPURLResponse(
    url: url ?? URL(string: "https://stub.invalid")!, statusCode: status, httpVersion: nil,
    headerFields: headers)!
}

/// A 64×64 solid PNG.
private let stubPNG: Data = {
  let context = CGContext(
    data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  precondition(CGImageDestinationFinalize(destination))
  return data as Data
}()

private func makeRequest(
  width: Int = 1344, height: Int = 768, seed: UInt64? = 7, negative: String? = nil,
  steps: Int = 28, guidance: Float = 3.5
) -> GenerationRequest {
  GenerationRequest(
    prompt: "a lighthouse at dusk", negativePrompt: negative, steps: steps, guidanceScale: guidance,
    seed: seed, width: width, height: height, mode: .textToImage)
}

// MARK: - Catalog

@Suite("Cloud catalog")
struct CloudCatalogTests {

  @Test("model ids are unique, resolvable, and route to a cloud- engine")
  func cloudModelIDsAreUniqueAndResolvable() {
    let ids = CloudModelDescriptor.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ids.count == 9)
    for model in CloudModelDescriptor.all {
      #expect(CloudModelDescriptor.byID[model.id] == model)
      #expect(model.engineID.hasPrefix("cloud-"))
      #expect(model.provider.models.contains(model))
      #expect(model.minimumMemoryGB == 0)
      #expect(model.approximateDownloadSize == "Cloud")
      #expect(!model.supportedAspectRatios.isEmpty)
    }
  }

  @Test("the CLI name of a cloud model is its full id")
  func cliNameIsID() {
    for model in CloudModelDescriptor.all {
      #expect(model.cliName == model.id)
      #expect(model.summary.cliName == model.id)
    }
  }

  @Test("provider engine ids round-trip and never collide with on-device engines")
  func providerEngineIDsRoundTrip() {
    for provider in CloudProvider.allCases {
      #expect(CloudProvider.provider(forEngineID: provider.engineID) == provider)
      #expect(!provider.models.isEmpty)
    }
    #expect(CloudProvider.provider(forEngineID: "flux2") == nil)
    #expect(CloudProvider.provider(forEngineID: "pixart-sigma") == nil)
  }

  @Test("every provider names a distinct environment variable")
  func environmentVariablesAreDistinct() {
    let names = CloudProvider.allCases.map(\.environmentVariable)
    #expect(Set(names).count == names.count)
    #expect(CloudProvider.openAI.environmentVariable == "OPENAI_API_KEY")
    #expect(CloudProvider.google.environmentVariable == "GEMINI_API_KEY")
    #expect(CloudProvider.google.environmentVariableAliases == ["GOOGLE_API_KEY"])
    #expect(CloudProvider.blackForestLabs.environmentVariable == "BFL_API_KEY")
    #expect(CloudProvider.stabilityAI.environmentVariable == "STABILITY_API_KEY")
  }

  @Test("the license names the vendor's terms")
  func licenseIsVendorTerms() {
    if case .custom(let name, let url) = CloudModelDescriptor.flux2Pro.license {
      #expect(name.contains("Black Forest Labs"))
      #expect(url == CloudProvider.blackForestLabs.termsURL)
    } else {
      Issue.record("cloud license should be .custom")
    }
  }
}

// MARK: - Dimensions

@Suite("Cloud dimensions")
struct CloudDimensionTests {

  @Test("fit scales, snaps, and clamps")
  func fitScalesSnapsAndClamps() {
    let fitted = CloudDimensions.fit(
      width: 3840, height: 2160, maxEdge: 1440, minEdge: 256, multiple: 32)
    #expect(fitted.width == 1440)
    #expect(fitted.height == 800)
    #expect(fitted.height % 32 == 0)

    let small = CloudDimensions.fit(
      width: 100, height: 100, maxEdge: 1440, minEdge: 256, multiple: 32)
    #expect(small.width == 256 && small.height == 256)

    let unchanged = CloudDimensions.fit(
      width: 1024, height: 1024, maxEdge: 1440, minEdge: 256, multiple: 32)
    #expect(unchanged.width == 1024 && unchanged.height == 1024)
  }

  @Test("Stability picks the nearest aspect preset")
  func stabilityPicksNearestPreset() {
    #expect(StabilityImageClient.aspectRatio(width: 1344, height: 768) == "16:9")
    #expect(StabilityImageClient.aspectRatio(width: 1024, height: 1024) == "1:1")
    #expect(StabilityImageClient.aspectRatio(width: 768, height: 1344) == "9:16")
    #expect(StabilityImageClient.aspectRatio(width: 1536, height: 640) == "21:9")
    #expect(StabilityImageClient.aspectRatio(width: 1216, height: 832) == "3:2")
  }

  @Test("OpenAI size honours the vendor rules")
  func openAISizeHonoursVendorRules() {
    #expect(OpenAIImageClient.size(width: 1344, height: 768) == "1344x768")
    #expect(OpenAIImageClient.size(width: 1024, height: 1024) == "1024x1024")
    #expect(OpenAIImageClient.size(width: 768, height: 1344) == "768x1344")
    #expect(OpenAIImageClient.size(width: 3840, height: 2160) == "2048x1152")
    #expect(OpenAIImageClient.size(width: 2048, height: 512) == "auto")
  }

  @Test("Gemini size tiers and ratios")
  func geminiSizeTiersAndRatios() {
    #expect(GeminiImageClient.imageSize(width: 1024, height: 1024) == "1K")
    #expect(GeminiImageClient.imageSize(width: 2048, height: 512) == "2K")
    #expect(GeminiImageClient.imageSize(width: 2160, height: 3840) == "4K")
    #expect(GeminiImageClient.aspectRatio(width: 1216, height: 832) == "3:2")
    #expect(GeminiImageClient.aspectRatio(width: 1536, height: 640) == "21:9")
    #expect(GeminiImageClient.aspectRatio(width: 768, height: 1344) == "9:16")
  }
}

// MARK: - Key stores

@Suite("Cloud key stores")
struct CloudKeyStoreTests {

  @Test("in-memory store round-trips, reports its source, and removes")
  func inMemoryStore() throws {
    let store = InMemoryAPIKeyStore()
    #expect(store.apiKey(for: .openAI) == nil)
    #expect(store.keySource(for: .openAI) == nil)
    try store.setAPIKey("k", for: .openAI)
    #expect(store.apiKey(for: .openAI) == "k")
    #expect(store.keySource(for: .openAI) == "memory")
    try store.removeAPIKey(for: .openAI)
    #expect(store.apiKey(for: .openAI) == nil)
  }

  @Test("environment store reads the primary variable, then aliases, trims, and is read-only")
  func environmentStore() {
    let store = EnvironmentAPIKeyStore(environment: [
      "OPENAI_API_KEY": "  sk-env  ",
      "GOOGLE_API_KEY": "AIza-alias",
      "BFL_API_KEY": "   ",
    ])
    #expect(store.apiKey(for: .openAI) == "sk-env")
    #expect(store.keySource(for: .openAI) == "environment (OPENAI_API_KEY)")
    // Alias honoured when the primary is absent.
    #expect(store.apiKey(for: .google) == "AIza-alias")
    #expect(store.resolvedVariable(for: .google) == "GOOGLE_API_KEY")
    // Whitespace-only is "not set".
    #expect(store.apiKey(for: .blackForestLabs) == nil)
    #expect(store.apiKey(for: .stabilityAI) == nil)

    #expect(throws: CloudKeyStoreError.readOnly("environment")) {
      try store.setAPIKey("x", for: .openAI)
    }
    #expect(throws: CloudKeyStoreError.readOnly("environment")) {
      try store.removeAPIKey(for: .openAI)
    }
  }

  @Test("environment primary wins over an alias")
  func environmentPrimaryWins() {
    let store = EnvironmentAPIKeyStore(environment: [
      "GEMINI_API_KEY": "primary", "GOOGLE_API_KEY": "alias",
    ])
    #expect(store.apiKey(for: .google) == "primary")
    #expect(store.resolvedVariable(for: .google) == "GEMINI_API_KEY")
  }

  @Test("chain resolves first-wins, writes to the first writable store, removes everywhere")
  func chainResolution() throws {
    let env = EnvironmentAPIKeyStore(environment: ["OPENAI_API_KEY": "from-env"])
    let memory = InMemoryAPIKeyStore(keys: [.openAI: "from-memory", .stabilityAI: "stab"])
    let chain = ChainedAPIKeyStore([env, memory])

    #expect(chain.apiKey(for: .openAI) == "from-env")
    #expect(chain.keySource(for: .openAI) == "environment (OPENAI_API_KEY)")
    #expect(chain.apiKey(for: .stabilityAI) == "stab")
    #expect(chain.keySource(for: .stabilityAI) == "memory")
    #expect(chain.apiKey(for: .google) == nil)
    #expect(chain.keySource(for: .google) == nil)

    // Writes skip the read-only environment and land in memory.
    try chain.setAPIKey("new-bfl", for: .blackForestLabs)
    #expect(memory.apiKey(for: .blackForestLabs) == "new-bfl")

    try chain.removeAPIKey(for: .stabilityAI)
    #expect(memory.apiKey(for: .stabilityAI) == nil)

    // A chain with no writable member refuses writes.
    let readOnly = ChainedAPIKeyStore([env])
    #expect(throws: CloudKeyStoreError.readOnly("chain")) {
      try readOnly.setAPIKey("x", for: .openAI)
    }
  }

  @Test("migrateKeys moves keys once, skips providers already present, and is idempotent")
  func migrateKeys() throws {
    let legacy = InMemoryAPIKeyStore(keys: [.openAI: "old-openai", .google: "old-google"])
    let shared = InMemoryAPIKeyStore(keys: [.google: "already-shared"])

    let moved = try KeychainAPIKeyStore.migrateKeys(from: legacy, to: shared)
    #expect(moved == [.openAI])
    #expect(shared.apiKey(for: .openAI) == "old-openai")
    #expect(legacy.apiKey(for: .openAI) == nil)
    // The destination's own value wins; the legacy copy is left untouched
    // rather than silently discarded.
    #expect(shared.apiKey(for: .google) == "already-shared")
    #expect(legacy.apiKey(for: .google) == "old-google")

    let again = try KeychainAPIKeyStore.migrateKeys(from: legacy, to: shared)
    #expect(again.isEmpty)
  }

  @Test("the macOS shared keychain store targets the data-protection keychain with the team group")
  func sharedKeychainStoreConfiguration() {
    #if os(macOS)
      #expect(
        KeychainAPIKeyStore.shared.accessGroup == KeychainAPIKeyStore.vinetasSharedAccessGroup)
      #expect(
        KeychainAPIKeyStore.vinetasSharedAccessGroup.hasSuffix("io.intrusive-memory.Vinetas.shared")
      )
    #else
      #expect(KeychainAPIKeyStore.shared.accessGroup == nil)
    #endif
    #expect(KeychainAPIKeyStore.legacy.accessGroup == nil)
    #expect(KeychainAPIKeyStore.shared.service == KeychainAPIKeyStore.defaultService)
  }
}

// MARK: - Router registration

@Suite("EngineRouter registration")
struct EngineRouterRegistrationTests {

  @Test("register adds an engine and its models; unregister removes them")
  func registerAndUnregister() async throws {
    let router = EngineRouter(engines: [MockEngine(engineID: "pixart-sigma")])
    let cloud = CloudImageEngine(provider: .openAI, keyStore: InMemoryAPIKeyStore())

    await router.register(cloud)
    #expect(await router.registeredEngineIDs == ["pixart-sigma", "cloud-openai"])
    let models = await router.allModels
    #expect(models.contains { $0.id == CloudModelDescriptor.gptImage25Flare.id })
    let resolved = try await router.engine(for: CloudModelDescriptor.gptImage25Flare)
    #expect(resolved.engineID == "cloud-openai")

    await router.unregister(engineID: "cloud-openai")
    #expect(await router.registeredEngineIDs == ["pixart-sigma"])
    await #expect(throws: VinetasError.self) {
      _ = try await router.engine(for: CloudModelDescriptor.gptImage25Flare)
    }
  }

  @Test("register replaces an engine with the same id in place")
  func registerReplaces() async throws {
    let first = CloudImageEngine(provider: .blackForestLabs, keyStore: InMemoryAPIKeyStore())
    let second = CloudImageEngine(
      provider: .blackForestLabs, keyStore: InMemoryAPIKeyStore(keys: [.blackForestLabs: "k"]))
    let router = EngineRouter(engines: [first, MockEngine(engineID: "flux2")])

    await router.register(second)
    #expect(await router.registeredEngineIDs == ["cloud-bfl", "flux2"])
    let resolved = try await router.engine(for: CloudModelDescriptor.flux2Pro)
    #expect(resolved as? CloudImageEngine === second)
    #expect(await resolved.isAvailable(CloudModelDescriptor.flux2Pro))
  }
}

// MARK: - Default client wiring

@Suite("VinetasClient default cloud registration")
struct CloudDefaultRegistrationTests {

  @Test("the default client registers one engine per provider and lists every cloud model")
  func defaultClientRegistersCloudEngines() async throws {
    let client = VinetasClient()
    let ids = await client.router.registeredEngineIDs
    for provider in CloudProvider.allCases {
      #expect(ids.contains(provider.engineID))
    }
    #expect(ids.contains("flux2") && ids.contains("pixart-sigma"))

    let models = await client.router.allModels
    for cloud in CloudModelDescriptor.all {
      #expect(models.contains { $0.id == cloud.id })
    }

    let engine = try await client.router.engine(for: CloudModelDescriptor.flux2Pro)
    #expect(engine.engineID == "cloud-bfl")
    #expect(engine is CloudImageEngine)
  }

  @Test("validateMemory is .ok for a cloud model without special-casing")
  func validateMemoryIsOK() async throws {
    let client = VinetasClient()
    if case .ok = try await client.validateMemory(for: CloudModelDescriptor.stableImageCore) {
    } else {
      Issue.record("cloud models must never be memory-gated")
    }
  }

  @Test("the default engines resolve keys through the environment-first chain")
  func defaultEnginesUseTheChain() async throws {
    let client = VinetasClient()
    let engine = try await client.router.engine(for: CloudModelDescriptor.gptImage25Flare)
    let cloud = try #require(engine as? CloudImageEngine)
    let chain = try #require(cloud.keyStore as? ChainedAPIKeyStore)
    #expect(chain.stores.count == 2)
    #expect(chain.stores[0] is EnvironmentAPIKeyStore)
    #expect(chain.stores[1] is KeychainAPIKeyStore)
  }
}

// MARK: - Engine rules

@Suite("CloudImageEngine")
struct CloudImageEngineTests {

  @Test("loadModel requires a key; generate requires loadModel")
  func loadModelRequiresKey() async {
    let engine = CloudImageEngine(provider: .openAI, keyStore: InMemoryAPIKeyStore())
    await #expect(throws: CloudEngineError.missingAPIKey(.openAI)) {
      try await engine.loadModel(CloudModelDescriptor.gptImage25Flare, progress: { _ in })
    }
    await #expect(throws: CloudEngineError.noModelLoaded) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }

  @Test("the engine rejects descriptors it does not serve and reports availability by key")
  func rejectsForeignDescriptors() async {
    let engine = CloudImageEngine(
      provider: .openAI, keyStore: InMemoryAPIKeyStore(keys: [.openAI: "k"]))
    await #expect(throws: CloudEngineError.self) {
      try await engine.loadModel(CloudModelDescriptor.flux2Pro, progress: { _ in })
    }
    await #expect(throws: CloudEngineError.self) {
      try await engine.loadModel(Flux2ModelDescriptor.klein4B, progress: { _ in })
    }
    #expect(await engine.isAvailable(CloudModelDescriptor.gptImage25Flare))
    #expect(await !engine.isAvailable(CloudModelDescriptor.flux2Pro))
    #expect(await engine.availability(CloudModelDescriptor.gptImage25Flare) == .available)
    if case .ok = engine.validateMemory(for: CloudModelDescriptor.gptImage25Flare) {
    } else {
      Issue.record("cloud engine must always report .ok memory")
    }
  }

  @Test("no key → notAvailable; download and delete are no-ops; diskSize is nil")
  func modelManagementNoOps() async throws {
    let engine = CloudImageEngine(provider: .google, keyStore: InMemoryAPIKeyStore())
    #expect(await engine.availability(CloudModelDescriptor.nanoBanana21) == .notAvailable)

    nonisolated(unsafe) var messages: [String] = []
    try await engine.download(CloudModelDescriptor.nanoBanana21) { messages.append($0.message) }
    #expect(messages == ["Cloud model — nothing to download"])
    try await engine.delete(CloudModelDescriptor.nanoBanana21)
    #expect(await engine.diskSize(of: CloudModelDescriptor.nanoBanana21) == nil)
  }

  @Test("capabilities: no LoRA; references per model; negative prompt per provider")
  func capabilities() async {
    let openAI = CloudImageEngine(provider: .openAI, keyStore: InMemoryAPIKeyStore())
    let google = CloudImageEngine(provider: .google, keyStore: InMemoryAPIKeyStore())
    let bfl = CloudImageEngine(provider: .blackForestLabs, keyStore: InMemoryAPIKeyStore())
    let stability = CloudImageEngine(provider: .stabilityAI, keyStore: InMemoryAPIKeyStore())
    #expect(openAI.supports(.textToImage))
    #expect(!openAI.supports(.loraInference))
    #expect(!openAI.supports(.loraTraining))
    #expect(openAI.supports(.imageToImage(maxReferenceImages: 10)))
    #expect(!openAI.supports(.imageToImage(maxReferenceImages: 11)))
    #expect(!bfl.supports(.imageToImage(maxReferenceImages: 1)))
    #expect(!stability.supports(.imageToImage(maxReferenceImages: 1)))
    #expect(!openAI.supports(.negativePrompt))
    #expect(stability.supports(.negativePrompt))

    #expect(openAI.maxReferenceImages(for: CloudModelDescriptor.gptImage25Flare) == 10)
    #expect(google.maxReferenceImages(for: CloudModelDescriptor.nanoBanana21) == 10)
    #expect(google.maxReferenceImages(for: CloudModelDescriptor.gemini3ProImage) == 6)
    #expect(bfl.maxReferenceImages(for: CloudModelDescriptor.flux2Pro) == 0)
    #expect(stability.maxReferenceImages(for: CloudModelDescriptor.stableImageCore) == 0)
    // A descriptor the engine does not serve has no references.
    #expect(openAI.maxReferenceImages(for: CloudModelDescriptor.nanoBanana21) == 0)

    await #expect(throws: CloudEngineError.unsupportedFeature("LoRA", provider: .openAI)) {
      try await openAI.loadLoRA(at: URL(fileURLWithPath: "/tmp/x.safetensors"), scale: 0.8)
    }
  }

  @Test("image-to-image is refused before any network call where the model takes no references")
  func imageToImageRefused() async throws {
    let engine = CloudImageEngine(
      provider: .stabilityAI, keyStore: InMemoryAPIKeyStore(keys: [.stabilityAI: "k"]),
      client: StabilityImageClient(), session: StubURLProtocol.makeSession())
    try await engine.loadModel(CloudModelDescriptor.stableImageCore, progress: { _ in })
    let reference = try CloudHTTP.decodeImage(stubPNG, provider: .stabilityAI)
    let request = GenerationRequest(
      prompt: "p", steps: 1, guidanceScale: 1, width: 1024, height: 1024,
      mode: .imageToImage(references: [reference]))
    await #expect(
      throws: CloudEngineError.unsupportedFeature("Image-to-image", provider: .stabilityAI)
    ) {
      _ = try await engine.generate(request: request, stepProgress: nil)
    }
  }

  @Test("more references than the model takes is refused before any network call")
  func tooManyReferencesRefused() async throws {
    let engine = CloudImageEngine(
      provider: .google, keyStore: InMemoryAPIKeyStore(keys: [.google: "k"]),
      client: GeminiImageClient(), session: StubURLProtocol.makeSession())
    try await engine.loadModel(CloudModelDescriptor.gemini3ProImage, progress: { _ in })
    let reference = try CloudHTTP.decodeImage(stubPNG, provider: .google)
    let request = GenerationRequest(
      prompt: "p", steps: 1, guidanceScale: 1, width: 1024, height: 1024,
      mode: .imageToImage(references: Array(repeating: reference, count: 7)))
    await #expect(throws: VinetasError.self) {
      _ = try await engine.generate(request: request, stepProgress: nil)
    }
  }

  @Test("VinetasClient refuses references for a cloud model before loading it")
  func clientRefusesReferences() async throws {
    let engine = CloudImageEngine(
      provider: .blackForestLabs, keyStore: InMemoryAPIKeyStore(keys: [.blackForestLabs: "k"]))
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    let reference = try ReferenceImage.load(data: stubPNG, source: .stdin)
    await #expect(throws: VinetasError.self) {
      _ = try await client.generate(
        PanelRequest(
          prompt: "p", style: StyleConfig(), model: CloudModelDescriptor.flux2Pro,
          references: [reference]))
    }
  }
}

// MARK: - Vendor adapters (stubbed network)

@Suite("Cloud vendor adapters", .serialized)
struct CloudVendorAdapterTests {

  private func engine(_ provider: CloudProvider, client: any CloudProviderClient)
    -> CloudImageEngine
  {
    CloudImageEngine(
      provider: provider,
      keyStore: InMemoryAPIKeyStore(keys: [provider: "secret-key"]),
      client: client,
      session: StubURLProtocol.makeSession())
  }

  @Test("OpenAI decodes base64 and sends a bearer token")
  func openAIDecodesBase64AndSendsBearer() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = ["data": [["b64_json": stubPNG.base64EncodedString()]]]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }

    let engine = engine(.openAI, client: OpenAIImageClient())
    try await engine.loadModel(CloudModelDescriptor.gptImage25Flare, progress: { _ in })
    let result = try await engine.generate(
      request: makeRequest(width: 1344, height: 768), stepProgress: nil)

    #expect(result.image.width == 64)
    #expect(result.modelID == CloudModelDescriptor.gptImage25Flare.id)
    #expect(result.usedPrompt == "a lighthouse at dusk")

    let request = try #require(StubURLProtocol.requests.first)
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    let body = request.jsonBody
    #expect(body["model"] as? String == "gpt-image-2.5-flare")
    #expect(body["size"] as? String == "1344x768")
    #expect(body["prompt"] as? String == "a lighthouse at dusk")
    #expect(body["seed"] == nil && body["steps"] == nil)
  }

  @Test("VinetasClient metadata records the vendor's actual output size and the cloud engine")
  func clientMetadataRecordsActualSize() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = ["data": [["b64_json": stubPNG.base64EncodedString()]]]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }
    let client = VinetasClient(
      router: EngineRouter(engines: [engine(.openAI, client: OpenAIImageClient())]))
    let panel = try await client.generate(
      PanelRequest(
        prompt: "a lighthouse", style: StyleConfig(width: 1344, height: 768),
        model: CloudModelDescriptor.gptImage25Flare))
    #expect(panel.metadata.engine == "cloud-openai")
    #expect(panel.metadata.model == CloudModelDescriptor.gptImage25Flare.id)
    #expect(panel.metadata.width == 64)
    #expect(panel.metadata.height == 64)
  }

  @Test("OpenAI surfaces the vendor's error message verbatim")
  func openAISurfacesVendorErrorMessage() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = ["error": ["message": "Incorrect API key provided"]]
      return (
        httpResponse(request.url, status: 401), try JSONSerialization.data(withJSONObject: json)
      )
    }
    let engine = engine(.openAI, client: OpenAIImageClient())
    try await engine.loadModel(CloudModelDescriptor.gptImage25Flare, progress: { _ in })
    await #expect(
      throws: CloudEngineError.httpStatus(
        provider: .openAI, status: 401, message: "Incorrect API key provided")
    ) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }

  @Test("a bodiless 401 points at the environment variable, never at a key")
  func bodilessUnauthorizedHint() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in (httpResponse(request.url, status: 403), Data()) }
    do {
      _ = try await CloudHTTP.perform(
        URLRequest(url: URL(string: "https://stub.invalid/x")!),
        session: StubURLProtocol.makeSession(), provider: .blackForestLabs)
      Issue.record("expected httpStatus")
    } catch let error as CloudEngineError {
      guard case .httpStatus(_, 403, let message) = error else {
        Issue.record("unexpected \(error)")
        return
      }
      #expect(message?.contains("BFL_API_KEY") == true)
      #expect(message?.contains("secret") == false)
    }
  }

  @Test("429 is retried with back-off and the retry succeeds")
  func rateLimitIsRetried() async throws {
    defer { StubURLProtocol.reset() }
    nonisolated(unsafe) var calls = 0
    StubURLProtocol.handler = { request in
      calls += 1
      if calls == 1 {
        return (httpResponse(request.url, status: 429, headers: ["Retry-After": "0"]), Data())
      }
      return (httpResponse(request.url), Data("ok".utf8))
    }
    let (data, response) = try await CloudHTTP.perform(
      URLRequest(url: URL(string: "https://stub.invalid/x")!),
      session: StubURLProtocol.makeSession(), provider: .openAI, retryDelays: [0.01, 0.01])
    #expect(response.statusCode == 200)
    #expect(String(decoding: data, as: UTF8.self) == "ok")
    #expect(calls == 2)
  }

  @Test("429 past the retry budget surfaces as httpStatus; Retry-After is clamped")
  func rateLimitExhausted() async throws {
    defer { StubURLProtocol.reset() }
    nonisolated(unsafe) var calls = 0
    StubURLProtocol.handler = { request in
      calls += 1
      return (
        httpResponse(request.url, status: 429),
        try JSONSerialization.data(withJSONObject: ["error": ["message": "slow down"]])
      )
    }
    await #expect(
      throws: CloudEngineError.httpStatus(provider: .openAI, status: 429, message: "slow down")
    ) {
      _ = try await CloudHTTP.perform(
        URLRequest(url: URL(string: "https://stub.invalid/x")!),
        session: StubURLProtocol.makeSession(), provider: .openAI, retryDelays: [0.01])
    }
    #expect(calls == 2)
    #expect(
      CloudHTTP.retryAfter(httpResponse(nil, status: 429, headers: ["Retry-After": "900"])) == 30)
    #expect(
      CloudHTTP.retryAfter(httpResponse(nil, status: 429, headers: ["Retry-After": "x"])) == nil)
  }

  @Test("BFL submits, polls, and downloads the sample")
  func bflSubmitsPollsAndDownloadsSample() async throws {
    defer { StubURLProtocol.reset() }
    nonisolated(unsafe) var polls = 0
    StubURLProtocol.handler = { request in
      let path = request.url!.path
      if request.httpMethod == "POST" {
        #expect(request.value(forHTTPHeaderField: "x-key") == "secret-key")
        let json: [String: Any] = [
          "id": "job-1", "polling_url": "https://api.bfl.ai/v1/get_result?id=job-1",
        ]
        return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
      }
      if path.hasSuffix("get_result") {
        polls += 1
        let json: [String: Any] =
          polls < 2
          ? ["status": "Pending"]
          : ["status": "Ready", "result": ["sample": "https://delivery.bfl.ai/sample.png"]]
        return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
      }
      return (httpResponse(request.url), stubPNG)
    }

    var client = BFLImageClient()
    client.pollInterval = 0.01
    let engine = engine(.blackForestLabs, client: client)
    try await engine.loadModel(CloudModelDescriptor.flux2Flex, progress: { _ in })
    let result = try await engine.generate(
      request: makeRequest(width: 3840, height: 2160, seed: 99), stepProgress: nil)

    #expect(result.image.width == 64)
    #expect(result.seed == 99)
    #expect(polls == 2)

    let submit = try #require(StubURLProtocol.requests.first)
    #expect(submit.url?.absoluteString == "https://api.bfl.ai/v1/flux-2-flex")
    let body = submit.jsonBody
    #expect(body["width"] as? Int == 1440)
    #expect(body["height"] as? Int == 800)
    #expect(body["seed"] as? Int == 99)
    #expect(body["steps"] as? Int == 28)
    #expect((body["guidance"] as? Double).map { abs($0 - 3.5) < 0.01 } == true)
  }

  @Test("BFL pro omits steps/guidance and surfaces moderation")
  func bflProModelOmitsStepsAndSurfacesModeration() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      if request.httpMethod == "POST" {
        let body = request.jsonBody
        #expect(body["steps"] == nil && body["guidance"] == nil)
        let json: [String: Any] = [
          "id": "job-2", "polling_url": "https://api.bfl.ai/v1/get_result?id=job-2",
        ]
        return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
      }
      return (
        httpResponse(request.url),
        try JSONSerialization.data(withJSONObject: ["status": "Content Moderated"])
      )
    }
    var client = BFLImageClient()
    client.pollInterval = 0.01
    let engine = engine(.blackForestLabs, client: client)
    try await engine.loadModel(CloudModelDescriptor.flux2Pro, progress: { _ in })
    await #expect(throws: CloudEngineError.moderated(provider: .blackForestLabs)) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }

  @Test("Stability sends multipart and reads the seed header")
  func stabilitySendsMultipartAndReadsSeedHeader() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      (httpResponse(request.url, headers: ["seed": "123456", "finish-reason": "SUCCESS"]), stubPNG)
    }

    let engine = engine(.stabilityAI, client: StabilityImageClient())
    try await engine.loadModel(CloudModelDescriptor.stableImageCore, progress: { _ in })
    let result = try await engine.generate(
      request: makeRequest(width: 1344, height: 768, seed: 5, negative: "blurry"), stepProgress: nil
    )

    #expect(result.image.width == 64)
    #expect(result.seed == 123_456)

    let request = try #require(StubURLProtocol.requests.first)
    #expect(
      request.url?.absoluteString == "https://api.stability.ai/v2beta/stable-image/generate/core")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=")
        == true)
    let body = String(decoding: request.bodyData, as: UTF8.self)
    #expect(body.contains("name=\"aspect_ratio\"\r\n\r\n16:9"))
    #expect(body.contains("name=\"negative_prompt\"\r\n\r\nblurry"))
    #expect(body.contains("name=\"seed\"\r\n\r\n5"))
    #expect(body.contains("name=\"output_format\"\r\n\r\npng"))
  }

  @Test("Stability content filter is moderation")
  func stabilityContentFilterIsModeration() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      (httpResponse(request.url, headers: ["finish-reason": "CONTENT_FILTERED"]), stubPNG)
    }
    let engine = engine(.stabilityAI, client: StabilityImageClient())
    try await engine.loadModel(CloudModelDescriptor.stableImageUltra, progress: { _ in })
    await #expect(throws: CloudEngineError.moderated(provider: .stabilityAI)) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }

  @Test("undecodable bytes are reported")
  func undecodableBytesAreReported() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in (httpResponse(request.url), Data("not an image".utf8)) }
    let engine = engine(.stabilityAI, client: StabilityImageClient())
    try await engine.loadModel(CloudModelDescriptor.stableImageCore, progress: { _ in })
    await #expect(throws: CloudEngineError.imageDecodingFailed(provider: .stabilityAI)) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }

  @Test("Gemini sends an interaction and decodes the image block")
  func geminiSendsInteractionAndDecodesImageBlock() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = [
        "id": "int-1", "status": "completed",
        "steps": [
          ["type": "thought", "summary": []],
          [
            "type": "model_output",
            "content": [
              ["type": "text", "text": "Here you go."],
              ["type": "image", "mime_type": "image/jpeg", "data": stubPNG.base64EncodedString()],
            ],
          ],
        ],
      ]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }

    let engine = engine(.google, client: GeminiImageClient())
    try await engine.loadModel(CloudModelDescriptor.nanoBanana21, progress: { _ in })
    let result = try await engine.generate(
      request: makeRequest(width: 3840, height: 2160, seed: 7), stepProgress: nil)

    #expect(result.image.width == 64)
    #expect(result.modelID == CloudModelDescriptor.nanoBanana21.id)

    let request = try #require(StubURLProtocol.requests.first)
    #expect(
      request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions"
    )
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "secret-key")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    let body = request.jsonBody
    #expect(body["model"] as? String == "gemini-nano-banana-2.1")
    #expect(body["input"] as? String == "a lighthouse at dusk")
    let format = try #require(body["response_format"] as? [String: Any])
    #expect(format["type"] as? String == "image")
    #expect(format["mime_type"] as? String == "image/jpeg")
    #expect(format["aspect_ratio"] as? String == "16:9")
    #expect(format["image_size"] as? String == "4K")
    #expect(body["generation_config"] == nil && body["seed"] == nil)
  }

  @Test("Gemini text-only reply is moderation")
  func geminiTextOnlyReplyIsModeration() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = [
        "status": "completed",
        "steps": [
          [
            "type": "model_output",
            "content": [["type": "text", "text": "I can't help with that."]],
          ]
        ],
      ]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }
    let engine = engine(.google, client: GeminiImageClient())
    try await engine.loadModel(CloudModelDescriptor.gemini3ProImage, progress: { _ in })
    await #expect(throws: CloudEngineError.moderated(provider: .google)) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }

  @Test("Gemini surfaces interaction errors")
  func geminiSurfacesInteractionErrors() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = [
        "status": "failed",
        "errors": [
          [
            "code": "https://ai.google.dev/errors/invalid_argument",
            "message": "image_size must be 1K, 2K or 4K",
          ]
        ],
        "steps": [],
      ]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }
    let engine = engine(.google, client: GeminiImageClient())
    try await engine.loadModel(CloudModelDescriptor.gemini31FlashImage, progress: { _ in })
    await #expect(
      throws: CloudEngineError.invalidResponse(
        provider: .google, detail: "image_size must be 1K, 2K or 4K")
    ) {
      _ = try await engine.generate(request: makeRequest(), stepProgress: nil)
    }
  }
}

// MARK: - Reference images and the prompt bundle (stubbed network)

extension CloudVendorAdapterTests {

  /// The image-to-image request a host builds: a bundle plus references.
  private func referenceRequest(count: Int) throws -> GenerationRequest {
    let reference = try CloudHTTP.decodeImage(stubPNG, provider: .openAI)
    var request = makeRequest(width: 1344, height: 768)
    request.mode = .imageToImage(references: Array(repeating: reference, count: count))
    request.bundle = PromptBundle(
      panelPrompt: "a lighthouse at dusk", stylePrompt: "ink wash", negativePrompt: "text",
      width: 1344, height: 768,
      character: .init(name: "Mara", description: "grey braid"), referenceCount: count,
      steps: 28, guidanceScale: 3.5, seed: 7)
    return request
  }

  @Test("OpenAI sends references to /edits as repeated image[] multipart parts")
  func openAISendsReferencesAsMultipart() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = ["data": [["b64_json": stubPNG.base64EncodedString()]]]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }

    let engine = engine(.openAI, client: OpenAIImageClient())
    try await engine.loadModel(CloudModelDescriptor.gptImage25Sunburst, progress: { _ in })
    let result = try await engine.generate(request: referenceRequest(count: 2), stepProgress: nil)

    let request = try #require(StubURLProtocol.requests.first)
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))

    let body = String(decoding: request.bodyData, as: UTF8.self)
    #expect(body.components(separatedBy: "name=\"image[]\"").count - 1 == 2)
    #expect(body.contains("filename=\"reference-1.jpg\""))
    #expect(body.contains("filename=\"reference-2.jpg\""))
    #expect(body.contains("Content-Type: image/jpeg"))
    #expect(body.contains("name=\"model\"\r\n\r\ngpt-image-2.5-sunburst\r\n"))
    #expect(body.contains("name=\"size\"\r\n\r\n1344x768\r\n"))
    // The prompt is the rendered bundle, and that is what the result reports.
    #expect(body.contains("Frame: 1344×768 pixels, 16:9 landscape aspect ratio."))
    #expect(body.contains("The 2 attached images show Mara."))
    #expect(body.contains("Avoid: text."))
    #expect(result.usedPrompt.contains("Character: Mara — grey braid"))
  }

  @Test("OpenAI without references stays on /generations")
  func openAIWithoutReferencesUsesGenerations() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = ["data": [["b64_json": stubPNG.base64EncodedString()]]]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }
    let engine = engine(.openAI, client: OpenAIImageClient())
    try await engine.loadModel(CloudModelDescriptor.gptImage25Flare, progress: { _ in })
    _ = try await engine.generate(request: referenceRequest(count: 0), stepProgress: nil)
    let request = try #require(StubURLProtocol.requests.first)
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
  }

  @Test("Gemini sends references as inline image blocks after the text block")
  func geminiSendsReferenceBlocks() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = [
        "status": "completed",
        "steps": [
          [
            "type": "model_output",
            "content": [
              ["type": "image", "mime_type": "image/jpeg", "data": stubPNG.base64EncodedString()]
            ],
          ]
        ],
      ]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }

    let engine = engine(.google, client: GeminiImageClient())
    try await engine.loadModel(CloudModelDescriptor.nanoBanana21, progress: { _ in })
    _ = try await engine.generate(request: referenceRequest(count: 3), stepProgress: nil)

    let body = try #require(StubURLProtocol.requests.first).jsonBody
    let input = try #require(body["input"] as? [[String: Any]])
    #expect(input.count == 4)
    #expect(input[0]["type"] as? String == "text")
    let text = try #require(input[0]["text"] as? String)
    #expect(text.contains("The 3 attached images show Mara."))
    for block in input.dropFirst() {
      #expect(block["type"] as? String == "image")
      #expect(block["mime_type"] as? String == "image/jpeg")
      let data = try #require((block["data"] as? String).flatMap { Data(base64Encoded: $0) })
      #expect(data.starts(with: [0xFF, 0xD8]))  // JPEG SOI
    }
    let format = try #require(body["response_format"] as? [String: Any])
    #expect(format["aspect_ratio"] as? String == "16:9")
  }

  @Test("a request without a bundle reaches the vendor verbatim")
  func requestWithoutBundleIsVerbatim() async throws {
    defer { StubURLProtocol.reset() }
    StubURLProtocol.handler = { request in
      let json: [String: Any] = ["data": [["b64_json": stubPNG.base64EncodedString()]]]
      return (httpResponse(request.url), try JSONSerialization.data(withJSONObject: json))
    }
    let engine = engine(.openAI, client: OpenAIImageClient())
    try await engine.loadModel(CloudModelDescriptor.gptImage25Flare, progress: { _ in })
    let result = try await engine.generate(request: makeRequest(), stepProgress: nil)
    #expect(result.usedPrompt == "a lighthouse at dusk")
    #expect(
      try #require(StubURLProtocol.requests.first).jsonBody["prompt"] as? String
        == "a lighthouse at dusk")
  }
}

@Suite("Cloud reference encoding")
struct CloudReferenceEncodingTests {

  @Test("references are flattened to JPEG and capped at the upload edge")
  func encodeReferenceDownscales() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 3000, height: 1500, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let data = try CloudHTTP.encodeReference(image, provider: .google)
    #expect(data.starts(with: [0xFF, 0xD8]))
    let decoded = try CloudHTTP.decodeImage(data, provider: .google)
    #expect(decoded.width == CloudHTTP.referenceMaxEdge)
    #expect(decoded.height == CloudHTTP.referenceMaxEdge / 2)
  }
}

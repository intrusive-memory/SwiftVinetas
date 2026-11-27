import Foundation
import Testing

@testable import SwiftVinetas

// Covers generation-time invalidation (requirement R-10): a generation that
// reports a model gone or a key rejected updates the availability snapshot, and
// the original error still reaches the caller. Everything goes through a
// stubbed `URLProtocol`; the key is a fake and the snapshots live in a temp
// directory.

private final class InvalidationStubURLProtocol: URLProtocol, @unchecked Sendable {

  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  static func reset() { handler = nil }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [InvalidationStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
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

private func respond(_ request: URLRequest, _ status: Int, _ body: String)
  -> (HTTPURLResponse, Data)
{
  (
    HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!,
    Data(body.utf8)
  )
}

private let openAIListingBody: String = {
  let items = CloudProvider.openAI.models.map { #"{"id": "\#($0.vendorModelID)"}"# }
  return #"{"data": [\#(items.joined(separator: ","))]}"#
}()

private let unknownModelBody = #"""
  {"error": {"message": "The model 'gpt-image-9-fake' does not exist.",
             "type": "invalid_request_error", "param": "model", "code": null}}
  """#

private let invalidKeyBody = #"""
  {"error": {"message": "Incorrect API key provided.", "type": "invalid_request_error",
             "param": null, "code": "invalid_api_key"}}
  """#

private struct Rig {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("cloud-invalidation-\(UUID().uuidString)", isDirectory: true)
  let keys = InMemoryAPIKeyStore(keys: [.openAI: "invalidation-test-key-not-real"])
  let service: CloudModelAvailability
  let engine: CloudImageEngine

  init() {
    let service = CloudModelAvailability(
      keyStore: keys, session: InvalidationStubURLProtocol.makeSession(),
      storeDirectory: directory)
    self.service = service
    self.engine = CloudImageEngine(
      provider: .openAI, keyStore: keys, client: nil,
      session: InvalidationStubURLProtocol.makeSession(),
      onCloudError: { await service.handle($0) })
  }

  func cleanUp() { try? FileManager.default.removeItem(at: directory) }

  func generate(_ model: CloudModelDescriptor) async throws {
    try await engine.loadModel(model, progress: { _ in })
    _ = try await engine.generate(
      request: GenerationRequest(
        prompt: "a lighthouse", negativePrompt: nil, steps: 1, guidanceScale: 1, seed: 1,
        width: 1024, height: 1024, mode: .textToImage),
      stepProgress: nil)
  }
}

@Suite("Cloud generation-time invalidation", .serialized)
struct CloudInvalidationTests {

  @Test("A model-gone generation removes the model, publishes once, and rethrows unchanged")
  func modelGoneRemovesModel() async throws {
    defer { InvalidationStubURLProtocol.reset() }
    InvalidationStubURLProtocol.handler = { request in
      request.httpMethod == "GET"
        ? respond(request, 200, openAIListingBody) : respond(request, 400, unknownModelBody)
    }
    let rig = Rig()
    defer { rig.cleanUp() }
    let model = CloudModelDescriptor.gptImage25Flare

    let first = await rig.service.refresh(.openAI)
    #expect(first.status == .available)
    #expect(await rig.service.availableModels().contains(model))

    var updates = rig.service.updates.makeAsyncIterator()
    do {
      try await rig.generate(model)
      Issue.record("expected modelUnavailable")
    } catch let error as CloudEngineError {
      #expect(
        error
          == .modelUnavailable(
            provider: .openAI, modelID: model.id,
            reason: "The model 'gpt-image-9-fake' does not exist."))
    }

    let update = await updates.next()
    #expect(update?.provider == .openAI)
    #expect(update?.modelIDs.contains(model.id) == false)
    #expect(update?.status == .available)
    #expect(update?.checkedAt == first.checkedAt)
    #expect(!(await rig.service.availableModels().contains(model)))
    #expect(await rig.service.availableModels().contains(.gptImage25Sunburst))

    // Persisted: a relaunched service sees the model gone.
    let relaunched = CloudModelAvailability(
      keyStore: rig.keys, session: InvalidationStubURLProtocol.makeSession(),
      storeDirectory: rig.directory)
    #expect(await relaunched.snapshot(for: .openAI)?.modelIDs.contains(model.id) == false)

    // Exactly one update: the next one is the forced re-check that restores it.
    InvalidationStubURLProtocol.handler = { respond($0, 200, openAIListingBody) }
    await rig.service.refresh(.openAI, force: true)
    let next = await updates.next()
    #expect(next?.modelIDs.contains(model.id) == true)
  }

  @Test("A key-rejected generation marks the snapshot .keyRejected with no models")
  func keyRejectedMarksSnapshot() async throws {
    defer { InvalidationStubURLProtocol.reset() }
    InvalidationStubURLProtocol.handler = { request in
      request.httpMethod == "GET"
        ? respond(request, 200, openAIListingBody) : respond(request, 401, invalidKeyBody)
    }
    let rig = Rig()
    defer { rig.cleanUp() }

    await rig.service.refresh(.openAI)
    var updates = rig.service.updates.makeAsyncIterator()
    do {
      try await rig.generate(.gptImage25Flare)
      Issue.record("expected keyRejected")
    } catch let error as CloudEngineError {
      #expect(error == .keyRejected(provider: .openAI, reason: .invalid))
    }
    let update = await updates.next()
    #expect(update?.status == .keyRejected(reason: .invalid))
    #expect(update?.modelIDs.isEmpty == true)
    #expect(await rig.service.availableModels().isEmpty)
    let relaunched = CloudModelAvailability(
      keyStore: rig.keys, session: InvalidationStubURLProtocol.makeSession(),
      storeDirectory: rig.directory)
    #expect(await relaunched.snapshot(for: .openAI)?.status == .keyRejected(reason: .invalid))
  }

  @Test("With no snapshot yet, the D-2 baseline minus the model is used, in memory only")
  func noSnapshotUsesBaseline() async throws {
    let rig = Rig()
    defer { rig.cleanUp() }
    let model = CloudModelDescriptor.gptImage25Flare

    await rig.service.markUnavailable(provider: .openAI, modelID: model.id)
    let snapshot = try #require(await rig.service.snapshot(for: .openAI))
    #expect(snapshot.status == .unreachable)
    #expect(!snapshot.isChecked)
    #expect(snapshot.modelIDs == Set(CloudProvider.openAI.models.map(\.id)).subtracting([model.id]))
    #expect(CloudAvailabilityStore(directory: rig.directory).read(.openAI) == nil)
  }

  @Test("Other errors and an already-removed model change nothing and publish nothing")
  func unrelatedErrorsAreIgnored() async throws {
    defer { InvalidationStubURLProtocol.reset() }
    InvalidationStubURLProtocol.handler = { respond($0, 200, openAIListingBody) }
    let rig = Rig()
    defer { rig.cleanUp() }
    let first = await rig.service.refresh(.openAI)

    await rig.service.handle(.moderated(provider: .openAI))
    await rig.service.handle(.timedOut(provider: .openAI))
    #expect(await rig.service.snapshot(for: .openAI) == first)

    await rig.service.markUnavailable(provider: .openAI, modelID: "not-a-model")
    #expect(await rig.service.snapshot(for: .openAI) == first)
  }
}

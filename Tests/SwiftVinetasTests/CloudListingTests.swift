import Foundation
import Testing

@testable import SwiftVinetas

// Covers the vendor listing calls (requirements R-3, R-6, R-9, R-9a) through
// each adapter against a stubbed `URLProtocol` (no network, no real key).
// OpenAI and Google bodies are trimmed from listings recorded 2026-11-26.

private final class ListingStubURLProtocol: URLProtocol, @unchecked Sendable {

  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var requests: [URLRequest] = []

  static func reset() {
    handler = nil
    requests = []
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ListingStubURLProtocol.self]
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

private func reply(_ request: URLRequest, _ body: String) -> (HTTPURLResponse, Data) {
  reply(request, 200, body)
}

private func reply(_ request: URLRequest, _ status: Int, _ body: String)
  -> (HTTPURLResponse, Data)
{
  (
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
    Data(body.utf8)
  )
}

@Suite("Cloud vendor listing calls", .serialized)
struct CloudListingTests {

  private static let fakeKey = "listing-test-key-not-real"

  private func day(_ text: String) -> Date { CloudListing.parseDay(text)! }

  // MARK: OpenAI

  private static let openAIListing = #"""
    {"object":"list","data":[
      {"id":"gpt-image-2.5-flare","object":"model","created":1,"owned_by":"system","shutdown_date":null},
      {"id":"gpt-image-2.5-flare-2026-09-08","object":"model","created":1,"owned_by":"system"},
      {"id":"gpt-image-1.5","object":"model","created":1,"owned_by":"system","shutdown_date":"2026-12-01"},
      {"id":"gpt-image-2","object":"model","created":1,"owned_by":"system","shutdown_date":"2027-02-10"}
    ]}
    """#

  @Test("OpenAI listing: one GET, IDs, and past and future shutdown dates")
  func openAIListing() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = { reply($0, Self.openAIListing) }
    let listing = try await OpenAIImageClient().listAvailableModels(
      apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())

    #expect(ListingStubURLProtocol.requests.count == 1)
    let request = ListingStubURLProtocol.requests[0]
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.fakeKey)")

    #expect(
      listing.modelIDs == [
        "gpt-image-2.5-flare", "gpt-image-2.5-flare-2026-09-08", "gpt-image-1.5", "gpt-image-2",
      ])
    #expect(listing.shutdownDates.count == 2)
    let now = day("2026-11-26")
    #expect(try #require(listing.shutdownDates["gpt-image-1.5"]) == day("2026-12-01"))
    #expect(try #require(listing.shutdownDates["gpt-image-2"]) == day("2027-02-10"))
    #expect(listing.shutdownDates["gpt-image-1.5"]! > now)
    // A shutdown date in the past, relative to a later clock.
    #expect(listing.shutdownDates["gpt-image-1.5"]! < day("2026-12-02"))
    #expect(listing.shutdownDates["gpt-image-2.5-flare"] == nil)
  }

  @Test("OpenAI listing with a rejected key is keyRejected and never carries the key")
  func openAIRejectedKey() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = {
      reply(
        $0, 401,
        #"{"error":{"message":"Incorrect API key provided: \#(Self.fakeKey).","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}"#
      )
    }
    let error = await #expect(throws: CloudEngineError.self) {
      _ = try await OpenAIImageClient().listAvailableModels(
        apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    }
    #expect(error == .keyRejected(provider: .openAI, reason: .invalid))
    #expect(!"\(String(describing: error))".contains(Self.fakeKey))
  }

  @Test("a listing 404 is httpStatus, not modelUnavailable")
  func listing404IsNotModelGone() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = {
      reply($0, 404, #"{"error":{"message":"nope","code":"model_not_found"}}"#)
    }
    let error = await #expect(throws: CloudEngineError.self) {
      _ = try await OpenAIImageClient().listAvailableModels(
        apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    }
    guard case .httpStatus(.openAI, 404, _)? = error else {
      Issue.record("expected httpStatus 404, got \(String(describing: error))")
      return
    }
  }

  // MARK: Google

  @Test("Google listing: two pages, pageSize=1000, the second request carries pageToken")
  func googlePaging() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = { request in
      let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
      if items?.first(where: { $0.name == "pageToken" })?.value == "TOKEN-2" {
        return reply(
          request,
          #"{"models":[{"name":"models/gemini-3-pro-image"},{"name":"models/gemini-3.1-flash-image-preview"}]}"#
        )
      }
      return reply(
        request,
        #"{"models":[{"name":"models/gemini-2.5-flash"},{"name":"models/gemini-nano-banana-2.1"}],"nextPageToken":"TOKEN-2"}"#
      )
    }
    let listing = try await GeminiImageClient().listAvailableModels(
      apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())

    let requests = ListingStubURLProtocol.requests
    #expect(requests.count == 2)
    func query(_ request: URLRequest, _ name: String) -> String? {
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == name }?.value
    }
    #expect(requests[0].url?.host == "generativelanguage.googleapis.com")
    #expect(requests[0].url?.path == "/v1beta/models")
    #expect(query(requests[0], "pageSize") == "1000")
    #expect(query(requests[0], "pageToken") == nil)
    #expect(query(requests[1], "pageSize") == "1000")
    #expect(query(requests[1], "pageToken") == "TOKEN-2")
    #expect(requests[0].value(forHTTPHeaderField: "x-goog-api-key") == Self.fakeKey)

    // The `models/` prefix is stripped, and both pages are merged.
    #expect(
      listing.modelIDs == [
        "gemini-2.5-flash", "gemini-nano-banana-2.1", "gemini-3-pro-image",
        "gemini-3.1-flash-image-preview",
      ])
    #expect(listing.shutdownDates.isEmpty)
  }

  @Test("Google paging stops at the page cap if the server never stops")
  func googlePageCap() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = {
      reply($0, #"{"models":[{"name":"models/m"}],"nextPageToken":"again"}"#)
    }
    let listing = try await GeminiImageClient().listAvailableModels(
      apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    #expect(ListingStubURLProtocol.requests.count == CloudListing.maxPages)
    #expect(listing.modelIDs == ["m"])
  }

  @Test("Google listing with a bad key (400 API_KEY_INVALID) is keyRejected")
  func googleRejectedKey() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = {
      reply(
        $0, 400,
        #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com"}]}}"#
      )
    }
    let error = await #expect(throws: CloudEngineError.self) {
      _ = try await GeminiImageClient().listAvailableModels(
        apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    }
    #expect(error == .keyRejected(provider: .google, reason: .invalid))
  }

  // MARK: BFL and Stability

  @Test("BFL credits success means the key works and the vendor lists no models")
  func bflCredits() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = { reply($0, #"{"credits":12.5}"#) }
    let listing = try await BFLImageClient().listAvailableModels(
      apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    let request = try #require(ListingStubURLProtocol.requests.first)
    #expect(ListingStubURLProtocol.requests.count == 1)
    #expect(request.url?.absoluteString == "https://api.bfl.ai/v1/credits")
    #expect(request.value(forHTTPHeaderField: "x-key") == Self.fakeKey)
    #expect(listing.modelIDs == nil)
    #expect(!listing.vendorListsModels)
    #expect(listing != CloudVendorListing(modelIDs: []))
  }

  @Test("BFL credits with a rejected key is keyRejected")
  func bflRejectedKey() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = { reply($0, 401, #"{"detail":"Not authenticated"}"#) }
    let error = await #expect(throws: CloudEngineError.self) {
      _ = try await BFLImageClient().listAvailableModels(
        apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    }
    #expect(error == .keyRejected(provider: .blackForestLabs, reason: .invalid))
  }

  @Test("Stability balance success means the key works and the vendor lists no models")
  func stabilityBalance() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = { reply($0, #"{"credits":25.0}"#) }
    let listing = try await StabilityImageClient().listAvailableModels(
      apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    let request = try #require(ListingStubURLProtocol.requests.first)
    #expect(ListingStubURLProtocol.requests.count == 1)
    #expect(request.url?.absoluteString == "https://api.stability.ai/v1/user/balance")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.fakeKey)")
    #expect(listing.modelIDs == nil)
  }

  @Test("Stability balance with a rejected key is keyRejected")
  func stabilityRejectedKey() async throws {
    defer { ListingStubURLProtocol.reset() }
    ListingStubURLProtocol.handler = {
      reply($0, 401, #"{"id":"x","name":"unauthorized","errors":["Incorrect API key"]}"#)
    }
    let error = await #expect(throws: CloudEngineError.self) {
      _ = try await StabilityImageClient().listAvailableModels(
        apiKey: Self.fakeKey, session: ListingStubURLProtocol.makeSession())
    }
    #expect(error == .keyRejected(provider: .stabilityAI, reason: .invalid))
  }

  // MARK: R-3 matching

  @Test("vendor aliases match exactly, only on the 2.5 OpenAI models")
  func aliasMatching() {
    let flare = CloudModelDescriptor.gptImage25Flare
    #expect(flare.matches(vendorID: "gpt-image-2.5-flare"))
    #expect(flare.matches(vendorID: "gpt-image-2.5-flare-2026-09-08"))
    #expect(!flare.matches(vendorID: "gpt-image-2.5-flare-2026"))
    #expect(!flare.matches(vendorID: "gpt-image-2.5-sunburst-2026-09-08"))
    #expect(
      CloudModelDescriptor.gptImage25Sunburst.matches(
        vendorID: "gpt-image-2.5-sunburst-2026-09-08"))
    let withAliases = CloudModelDescriptor.all.filter { !$0.vendorAliases.isEmpty }
    #expect(
      Set(withAliases.map(\.id)) == [
        "openai-gpt-image-2.5-flare", "openai-gpt-image-2.5-sunburst",
      ])
  }
}

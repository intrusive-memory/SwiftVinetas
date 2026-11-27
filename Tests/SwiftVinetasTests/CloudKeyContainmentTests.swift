import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas

// Requirement R-18: an API key goes only to its own vendor's host, only in that
// vendor's auth header, and is never in a URL, a body, another host's request,
// an error message, or a file on disk. Every listing and generation path of all
// four vendors runs against a stub that records each request.

private struct RecordedRequest: Sendable {
  let url: URL
  let headers: [String: String]
  let body: Data
}

private final class ContainmentStubURLProtocol: URLProtocol, @unchecked Sendable {

  enum Mode: Sendable { case success, keyRejected, vendorError }

  nonisolated(unsafe) static var mode: Mode = .success
  nonisolated(unsafe) static var requests: [RecordedRequest] = []

  static func reset() {
    mode = .success
    requests = []
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ContainmentStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(
      RecordedRequest(
        url: request.url!, headers: request.allHTTPHeaderFields ?? [:], body: request.allBody))
    let (response, data) = Self.reply(to: request)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func respond(_ request: URLRequest, _ body: Data) -> (HTTPURLResponse, Data) {
    respond(request, 200, headers: [:], body)
  }

  private static func respond(
    _ request: URLRequest, headers: [String: String], _ body: Data
  ) -> (HTTPURLResponse, Data) {
    respond(request, 200, headers: headers, body)
  }

  private static func respond(
    _ request: URLRequest, _ status: Int, headers: [String: String], _ body: Data
  ) -> (HTTPURLResponse, Data) {
    (
      HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
      body
    )
  }

  private static func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
  }

  static func reply(to request: URLRequest) -> (HTTPURLResponse, Data) {
    let host = request.url!.host ?? ""
    let isGET = request.httpMethod == "GET"
    let isListing = isGET && host != "delivery.bfl.ai" && !request.url!.path.contains("get_result")

    if host != "delivery.bfl.ai", !isListing || mode != .success {
      switch mode {
      case .keyRejected:
        return respond(
          request, 401, headers: ["Content-Type": "application/json"],
          json(["error": ["message": "Incorrect API key provided", "code": "invalid_api_key"]]))
      case .vendorError:
        if !isListing || host == "api.openai.com" {
          return respond(
            request, 400, headers: ["Content-Type": "application/json"],
            json(["error": ["message": "Something is wrong with the request"]]))
        }
      case .success:
        break
      }
    }

    switch host {
    case "api.openai.com":
      if isGET {
        let ids = CloudProvider.openAI.models.map { ["id": $0.vendorModelID] }
        return respond(request, json(["data": ids]))
      }
      return respond(request, json(["data": [["b64_json": png.base64EncodedString()]]]))
    case "generativelanguage.googleapis.com":
      if isGET {
        let names = CloudProvider.google.models.map { ["name": "models/\($0.vendorModelID)"] }
        return respond(request, json(["models": names]))
      }
      return respond(
        request,
        json([
          "id": "i", "status": "completed",
          "steps": [
            [
              "type": "model_output",
              "content": [
                ["type": "image", "mime_type": "image/png", "data": png.base64EncodedString()]
              ],
            ]
          ],
        ]))
    case "api.bfl.ai":
      if isGET && request.url!.path.hasSuffix("credits") {
        return respond(request, json(["credits": 1.0]))
      }
      if isGET {
        return respond(
          request,
          json(["status": "Ready", "result": ["sample": "https://delivery.bfl.ai/s.png"]]))
      }
      return respond(
        request, json(["id": "j", "polling_url": "https://api.bfl.ai/v1/get_result?id=j"]))
    case "api.stability.ai":
      if isGET { return respond(request, json(["credits": 1.0])) }
      return respond(request, headers: ["seed": "1", "finish-reason": "SUCCESS"], png)
    case "delivery.bfl.ai":
      return respond(request, png)
    default:
      return respond(request, 404, headers: [:], Data())
    }
  }
}

extension URLRequest {
  /// `httpBody` is `nil` inside a `URLProtocol`; the body arrives as a stream.
  fileprivate var allBody: Data {
    if let body = httpBody { return body }
    guard let stream = httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: 4096)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

private let png: Data = {
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

@Suite("Cloud key containment (R-18)", .serialized)
struct CloudKeyContainmentTests {

  private static let hosts: [CloudProvider: String] = [
    .openAI: "api.openai.com",
    .google: "generativelanguage.googleapis.com",
    .blackForestLabs: "api.bfl.ai",
    .stabilityAI: "api.stability.ai",
  ]

  private static let authHeaders: [CloudProvider: String] = [
    .openAI: "authorization",
    .google: "x-goog-api-key",
    .blackForestLabs: "x-key",
    .stabilityAI: "authorization",
  ]

  private static let keys: [CloudProvider: String] = Dictionary(
    uniqueKeysWithValues: CloudProvider.allCases.map {
      ($0, "R18-SECRET-\($0.rawValue)-0123456789abcdef")
    })

  /// Runs listing and every model's generation for all vendors in `mode`,
  /// returning every thrown error.
  private func exercise(_ mode: ContainmentStubURLProtocol.Mode, directory: URL) async
    -> [any Error]
  {
    ContainmentStubURLProtocol.mode = mode
    let store = InMemoryAPIKeyStore(keys: Self.keys)
    let service = CloudModelAvailability(
      keyStore: store, session: ContainmentStubURLProtocol.makeSession(),
      storeDirectory: directory)
    var errors: [any Error] = []

    for provider in CloudProvider.allCases {
      await service.refresh(provider, force: true)

      var bfl = BFLImageClient()
      bfl.pollInterval = 0.01
      let client: any CloudProviderClient =
        provider == .blackForestLabs ? bfl : CloudImageEngine.defaultClient(for: provider)
      let engine = CloudImageEngine(
        provider: provider, keyStore: store, client: client,
        session: ContainmentStubURLProtocol.makeSession(),
        onCloudError: { await service.handle($0) })
      for model in provider.models {
        do {
          try await engine.loadModel(model, progress: { _ in })
          _ = try await engine.generate(
            request: GenerationRequest(
              prompt: "a lighthouse at dusk", negativePrompt: "blurry", steps: 4,
              guidanceScale: 3.5, seed: 7, width: 1024, height: 1024, mode: .textToImage),
            stepProgress: nil)
          if mode != .success { Issue.record("\(model.id) unexpectedly succeeded in \(mode)") }
        } catch {
          errors.append(error)
        }
      }
    }
    return errors
  }

  private func assertContained(_ requests: [RecordedRequest]) {
    let allKeys = Self.keys
    var sawOwnAuth: Set<CloudProvider> = []
    #expect(!requests.isEmpty)
    for request in requests {
      let host = request.url.host ?? ""
      #expect(request.url.scheme == "https")
      for (provider, key) in allKeys {
        let ownHost = host == Self.hosts[provider]
        #expect(!request.url.absoluteString.contains(key), "key in URL \(request.url)")
        #expect(
          !String(decoding: request.body, as: UTF8.self).contains(key), "key in body of \(host)")
        for (name, value) in request.headers where value.contains(key) {
          let isAuth = name.lowercased() == Self.authHeaders[provider]
          #expect(ownHost && isAuth, "\(provider) key in \(name) sent to \(host)")
          if ownHost && isAuth { sawOwnAuth.insert(provider) }
        }
      }
    }
    #expect(sawOwnAuth == Set(CloudProvider.allCases), "every vendor's auth header was exercised")
    // The BFL sample download goes to another host and must carry no credential.
    let delivery = requests.filter { $0.url.host == "delivery.bfl.ai" }
    #expect(!delivery.isEmpty)
    for request in delivery { #expect(request.headers["x-key"] == nil) }
  }

  @Test("Listing and generation for every vendor send each key only to its own host's auth header")
  func keysStayWithTheirVendor() async throws {
    defer { ContainmentStubURLProtocol.reset() }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("cloud-key-containment-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    var errors: [any Error] = []
    var allRequests: [RecordedRequest] = []
    for mode in [
      ContainmentStubURLProtocol.Mode.success, .vendorError, .keyRejected,
    ] {
      ContainmentStubURLProtocol.requests = []
      errors += await exercise(mode, directory: directory)
      allRequests += ContainmentStubURLProtocol.requests
    }
    assertContained(allRequests)

    // Every generation path is covered: all twelve models, in each mode.
    let generations = allRequests.filter { $0.headers.isEmpty == false && $0.body.isEmpty == false }
    #expect(generations.count >= CloudModelDescriptor.all.count)
    #expect(errors.count >= CloudModelDescriptor.all.count * 2)

    // No thrown error mentions a key, in either description or either advice style.
    for error in errors {
      var texts = ["\(error)", error.localizedDescription, String(reflecting: error)]
      if let cloud = error as? CloudEngineError {
        texts.append(cloud.description(keySource: .appSettings))
        texts.append(cloud.description(keySource: .environmentOnly))
      }
      for text in texts {
        for key in Self.keys.values {
          #expect(!text.contains(key), "key in error text: \(text)")
        }
      }
    }

    // Nothing written under the store directory contains a key.
    let files =
      FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath } ?? []
    #expect(!files.isEmpty)
    for file in files {
      let data = try Data(contentsOf: file)
      for key in Self.keys.values {
        #expect(data.range(of: Data(key.utf8)) == nil, "key in \(file.lastPathComponent)")
      }
    }
  }
}

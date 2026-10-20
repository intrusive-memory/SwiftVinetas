import CoreGraphics
import Foundation
import GlosaCore
import ImageIO
import Testing

@testable import SwiftVinetas

/// A private, always-succeeding no-network URL stub (own type, so it cannot
/// collide with the stub other suites use).
private final class ShotStubURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let png = ShotStubURLProtocol.png
    let json: [String: Any] = ["data": [["b64_json": png.base64EncodedString()]]]
    let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://stub.invalid")!, statusCode: 200,
      httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  static let png: Data = {
    let context = CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }()
}

@Suite("PanelRequestShotTests")
struct PanelRequestShotTests {

  private static func makeShot() -> Shot {
    Shot(
      documentIndex: 1,
      prompt: "a paper boat on a still pond",
      style: "watercolour",
      width: 1024,
      height: 768,
      steps: 4,
      guidance: 3.5,
      seed: 11,
      preview: false
    )
  }

  @Test func testLocalEngineRecordsGlosa() async throws {
    let shot = Self.makeShot()
    let client = VinetasClient(router: EngineRouter(engines: [MockEngine()]))
    let panel = try await client.generate(
      PanelRequest(prompt: shot.prompt, model: MockModelDescriptor(), shot: shot))
    #expect(panel.metadata.glosa?.digest == shot.renderDigest)
    #expect(panel.metadata.glosa?.notation == GlosaVersion.notation)
  }

  @Test func testCloudEngineRecordsGlosa() async throws {
    let shot = Self.makeShot()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ShotStubURLProtocol.self]
    let engine = CloudImageEngine(
      provider: .openAI,
      keyStore: InMemoryAPIKeyStore(keys: [.openAI: "secret-key"]),
      client: OpenAIImageClient(),
      session: URLSession(configuration: config))
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    let panel = try await client.generate(
      PanelRequest(
        prompt: shot.prompt, style: StyleConfig(width: 1344, height: 768),
        model: CloudModelDescriptor.gptImage25Flare, shot: shot))
    #expect(panel.metadata.engine == "cloud-openai")
    #expect(panel.metadata.glosa?.digest == shot.renderDigest)
  }

  @Test func testNoShotNoGlosa() async throws {
    let client = VinetasClient(router: EngineRouter(engines: [MockEngine()]))
    let panel = try await client.generate(
      PanelRequest(prompt: "a paper boat", model: MockModelDescriptor()))
    #expect(panel.metadata.glosa == nil)
  }
}

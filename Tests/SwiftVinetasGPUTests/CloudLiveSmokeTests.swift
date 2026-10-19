import Foundation
import Testing

@testable import SwiftVinetas

// Live cloud smoke test — hits the real OpenAI endpoint with the key in the
// environment. Local only: skipped whenever OPENAI_API_KEY is unset (so it
// never runs in CI, which has no secret), and never part of `make test-unit`.
//
//   OPENAI_API_KEY=… make test-gpu   # or run this suite from Xcode
//
// Acceptance criterion 1 of docs/REQUIREMENTS-CLOUD-ENGINES.md: with the key
// in the environment and no GUI ever launched, a cloud model renders through
// the default client. Criterion 7 (no key material on disk) is checked on the
// PNG + metadata the run produces.

@Suite("Cloud live smoke (OPENAI_API_KEY)", .tags(.integration), .serialized)
struct CloudLiveSmokeTests {

  static var hasOpenAIKey: Bool {
    EnvironmentAPIKeyStore().apiKey(for: .openAI) != nil
  }

  @Test(
    "gpt-image-2.5-flare renders through the default client with the key from the environment",
    .enabled(if: hasOpenAIKey))
  func openAIRendersFromEnvironment() async throws {
    let client = VinetasClient()
    let model = CloudModelDescriptor.gptImage25Flare
    #expect(await client.availability(model: model) == .available)

    let panel = try await client.generate(
      PanelRequest(
        prompt: "a plain red circle centred on a white background, flat vector style",
        style: StyleConfig(width: 1024, height: 1024),
        model: model))

    #expect(panel.image.width >= 512)
    #expect(panel.metadata.engine == "cloud-openai")
    #expect(panel.metadata.model == model.id)
    #expect(panel.metadata.width == panel.image.width)

    // The PNG and its embedded metadata must never carry the key.
    let key = try #require(EnvironmentAPIKeyStore().apiKey(for: .openAI))
    let png = try ImageOutput.pngData(image: panel.image, metadata: panel.metadata)
    #expect(png.range(of: Data(key.utf8)) == nil)
  }
}

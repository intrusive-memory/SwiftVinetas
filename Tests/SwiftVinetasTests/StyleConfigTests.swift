import Foundation
import Testing

@testable import SwiftVinetas

@Suite("StyleConfig Tests")
struct StyleConfigTests {

  @Test("Default values are sensible")
  func defaultValues() {
    let config = StyleConfig()
    #expect(config.steps == 20)
    #expect(config.guidanceScale == 3.5)
    #expect(config.width == 1024)
    #expect(config.height == 1024)
    #expect(config.seed == nil)
  }

  @Test("Codable round-trip")
  func codableRoundTrip() throws {
    let config = StyleConfig(
      stylePrompt: "noir comic",
      negativePrompt: "blurry, low quality",
      steps: 50,
      guidanceScale: 9.0,
      seed: 42,
      width: 768,
      height: 512
    )
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(StyleConfig.self, from: data)
    #expect(decoded.stylePrompt == "noir comic")
    #expect(decoded.steps == 50)
    #expect(decoded.seed == 42)
  }
}

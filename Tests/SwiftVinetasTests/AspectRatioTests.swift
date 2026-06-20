import Foundation
import Testing

@testable import SwiftVinetas

@Suite("AspectRatio Tests")
struct AspectRatioTests {

  // MARK: - Preset Dimensions (platform-tiered)
  //
  // macOS generates at television resolution (each ratio fit inside a 3840×2160
  // 4K UHD frame); iOS uses a smaller memory-safe tier. See `AspectRatio`.

  @Test("square preset: macOS 2160×2160, iOS 1024×1024")
  func squareDimensions() {
    #if os(macOS)
    #expect(AspectRatio.square.width == 2160)
    #expect(AspectRatio.square.height == 2160)
    #else
    #expect(AspectRatio.square.width == 1024)
    #expect(AspectRatio.square.height == 1024)
    #endif
  }

  @Test("wide preset: macOS 3840×2160 (4K UHD), iOS 1344×768")
  func wideDimensions() {
    #if os(macOS)
    #expect(AspectRatio.wide.width == 3840)
    #expect(AspectRatio.wide.height == 2160)
    #else
    #expect(AspectRatio.wide.width == 1344)
    #expect(AspectRatio.wide.height == 768)
    #endif
  }

  @Test("ultrawide preset: macOS 3840×1600, iOS 1536×640")
  func ultrawideDimensions() {
    #if os(macOS)
    #expect(AspectRatio.ultrawide.width == 3840)
    #expect(AspectRatio.ultrawide.height == 1600)
    #else
    #expect(AspectRatio.ultrawide.width == 1536)
    #expect(AspectRatio.ultrawide.height == 640)
    #endif
  }

  @Test("portrait preset: macOS 2160×3840, iOS 768×1344")
  func portraitDimensions() {
    #if os(macOS)
    #expect(AspectRatio.portrait.width == 2160)
    #expect(AspectRatio.portrait.height == 3840)
    #else
    #expect(AspectRatio.portrait.width == 768)
    #expect(AspectRatio.portrait.height == 1344)
    #endif
  }

  @Test("panel preset: macOS 3232×2160, iOS 1216×832")
  func panelDimensions() {
    #if os(macOS)
    #expect(AspectRatio.panel.width == 3232)
    #expect(AspectRatio.panel.height == 2160)
    #else
    #expect(AspectRatio.panel.width == 1216)
    #expect(AspectRatio.panel.height == 832)
    #endif
  }

  @Test("strip preset: macOS 3840×960, iOS 2048×512")
  func stripDimensions() {
    #if os(macOS)
    #expect(AspectRatio.strip.width == 3840)
    #expect(AspectRatio.strip.height == 960)
    #else
    #expect(AspectRatio.strip.width == 2048)
    #expect(AspectRatio.strip.height == 512)
    #endif
  }

  // MARK: - All Presets Are Multiples of 16 (the real VAE/DiT constraint)

  @Test("all preset dimensions are multiples of 16")
  func allPresetsAreMultiplesOf16() {
    for ratio in AspectRatio.allCases {
      #expect(
        ratio.width % 16 == 0, "\(ratio.rawValue) width \(ratio.width) is not a multiple of 16")
      #expect(
        ratio.height % 16 == 0, "\(ratio.rawValue) height \(ratio.height) is not a multiple of 16")
    }
  }

  // MARK: - macOS TV tier stays within a single 4K UHD frame

  #if os(macOS)
  @Test("macOS presets never exceed a 3840×2160 4K UHD frame")
  func macOSPresetsFitWithin4KFrame() {
    for ratio in AspectRatio.allCases {
      let longEdge = max(ratio.width, ratio.height)
      let shortEdge = min(ratio.width, ratio.height)
      #expect(longEdge <= 3840, "\(ratio.rawValue) long edge \(longEdge) exceeds 3840")
      #expect(shortEdge <= 2160, "\(ratio.rawValue) short edge \(shortEdge) exceeds 2160")
    }
  }
  #endif

  // MARK: - CaseIterable

  @Test("allCases contains all six presets")
  func allCasesCount() {
    #expect(AspectRatio.allCases.count == 6)
  }

  // MARK: - StyleConfig Integration

  @Test("styleConfig(base:) sets correct dimensions for the platform tier")
  func styleConfigIntegration() {
    let config = AspectRatio.wide.styleConfig()
    #expect(config.width == AspectRatio.wide.width)
    #expect(config.height == AspectRatio.wide.height)
  }

  @Test("styleConfig preserves base style prompt")
  func styleConfigPreservesBaseProperties() {
    let base = StyleConfig(stylePrompt: "noir comic", steps: 30)
    let config = AspectRatio.portrait.styleConfig(base: base)
    #expect(config.stylePrompt == "noir comic")
    #expect(config.steps == 30)
    #expect(config.width == AspectRatio.portrait.width)
    #expect(config.height == AspectRatio.portrait.height)
  }
}

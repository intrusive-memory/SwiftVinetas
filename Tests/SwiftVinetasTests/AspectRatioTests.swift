import Foundation
import Testing

@testable import SwiftVinetas

@Suite("AspectRatio Tests")
struct AspectRatioTests {

  // MARK: - Desired Preset Dimensions (platform-tiered, pre-clamp)
  //
  // macOS *targets* television resolution (each ratio fit inside a 3840×2160 4K
  // UHD frame); iOS uses a smaller memory-safe tier. These assert the desired
  // ceiling; `.width`/`.height` may be clamped below this per device — see the
  // device-clamp tests further down. See `AspectRatio` / `ResolutionClamp`.

  @Test("square desired: macOS 2160×2160, iOS 1024×1024")
  func squareDesiredDimensions() {
    #if os(macOS)
      #expect(AspectRatio.square.desiredWidth == 2160)
      #expect(AspectRatio.square.desiredHeight == 2160)
    #else
      #expect(AspectRatio.square.desiredWidth == 1024)
      #expect(AspectRatio.square.desiredHeight == 1024)
    #endif
  }

  @Test("wide desired: macOS 3840×2160 (4K UHD), iOS 1344×768")
  func wideDesiredDimensions() {
    #if os(macOS)
      #expect(AspectRatio.wide.desiredWidth == 3840)
      #expect(AspectRatio.wide.desiredHeight == 2160)
    #else
      #expect(AspectRatio.wide.desiredWidth == 1344)
      #expect(AspectRatio.wide.desiredHeight == 768)
    #endif
  }

  @Test("ultrawide desired: macOS 3840×1600, iOS 1536×640")
  func ultrawideDesiredDimensions() {
    #if os(macOS)
      #expect(AspectRatio.ultrawide.desiredWidth == 3840)
      #expect(AspectRatio.ultrawide.desiredHeight == 1600)
    #else
      #expect(AspectRatio.ultrawide.desiredWidth == 1536)
      #expect(AspectRatio.ultrawide.desiredHeight == 640)
    #endif
  }

  @Test("portrait desired: macOS 2160×3840, iOS 768×1344")
  func portraitDesiredDimensions() {
    #if os(macOS)
      #expect(AspectRatio.portrait.desiredWidth == 2160)
      #expect(AspectRatio.portrait.desiredHeight == 3840)
    #else
      #expect(AspectRatio.portrait.desiredWidth == 768)
      #expect(AspectRatio.portrait.desiredHeight == 1344)
    #endif
  }

  @Test("panel desired: macOS 3232×2160, iOS 1216×832")
  func panelDesiredDimensions() {
    #if os(macOS)
      #expect(AspectRatio.panel.desiredWidth == 3232)
      #expect(AspectRatio.panel.desiredHeight == 2160)
    #else
      #expect(AspectRatio.panel.desiredWidth == 1216)
      #expect(AspectRatio.panel.desiredHeight == 832)
    #endif
  }

  @Test("strip desired: macOS 3840×960, iOS 2048×512")
  func stripDesiredDimensions() {
    #if os(macOS)
      #expect(AspectRatio.strip.desiredWidth == 3840)
      #expect(AspectRatio.strip.desiredHeight == 960)
    #else
      #expect(AspectRatio.strip.desiredWidth == 2048)
      #expect(AspectRatio.strip.desiredHeight == 512)
    #endif
  }

  #if !os(macOS)
    @Test("iOS dimensions are unclamped (actual == desired)")
    func iOSDimensionsUnclamped() {
      for ratio in AspectRatio.allCases {
        #expect(ratio.width == ratio.desiredWidth)
        #expect(ratio.height == ratio.desiredHeight)
      }
    }
  #endif

  // MARK: - Invariants on the (possibly clamped) actual dimensions

  @Test("all actual preset dimensions are multiples of 16")
  func allPresetsAreMultiplesOf16() {
    for ratio in AspectRatio.allCases {
      #expect(
        ratio.width % 16 == 0, "\(ratio.rawValue) width \(ratio.width) is not a multiple of 16")
      #expect(
        ratio.height % 16 == 0, "\(ratio.rawValue) height \(ratio.height) is not a multiple of 16")
    }
  }

  @Test("actual dimensions never exceed the desired ceiling")
  func actualNeverExceedsDesired() {
    for ratio in AspectRatio.allCases {
      #expect(ratio.width <= ratio.desiredWidth)
      #expect(ratio.height <= ratio.desiredHeight)
    }
  }

  // MARK: - macOS desired tier stays within a single 4K UHD frame

  #if os(macOS)
    @Test("macOS desired presets never exceed a 3840×2160 4K UHD frame")
    func macOSDesiredPresetsFitWithin4KFrame() {
      for ratio in AspectRatio.allCases {
        let longEdge = max(ratio.desiredWidth, ratio.desiredHeight)
        let shortEdge = min(ratio.desiredWidth, ratio.desiredHeight)
        #expect(longEdge <= 3840, "\(ratio.rawValue) long edge \(longEdge) exceeds 3840")
        #expect(shortEdge <= 2160, "\(ratio.rawValue) short edge \(shortEdge) exceeds 2160")
      }
    }

    // The crash guard: on THIS machine's real Metal device, the worst-case
    // attention buffer for every preset's actual dimensions must fit the
    // per-buffer ceiling — otherwise generation aborts `mlx_eval` on step 1.
    @Test("macOS actual dimensions fit the real device's max buffer length")
    func macOSActualDimensionsFitDeviceBuffer() {
      let cap = ResolutionClamp.maxBufferLengthBytes
      for ratio in AspectRatio.allCases {
        let bytes = worstCaseAttentionBytes(width: ratio.width, height: ratio.height)
        #expect(
          bytes <= cap,
          "\(ratio.rawValue) \(ratio.width)×\(ratio.height) needs \(bytes) B > cap \(cap) B")
      }
    }
  #endif

  // MARK: - CaseIterable

  @Test("allCases contains all six presets")
  func allCasesCount() {
    #expect(AspectRatio.allCases.count == 6)
  }

  // MARK: - StyleConfig Integration

  @Test("styleConfig() sets the actual (clamped) dimensions")
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

  // MARK: - Helpers

  /// Worst-case single attention-score buffer for a resolution, matching the
  /// allocation that aborts `mlx_eval`: `heads × tokens² × 4`, tokens = (W/16)(H/16).
  private func worstCaseAttentionBytes(width: Int, height: Int) -> UInt64 {
    let tokens = UInt64((width / 16) * (height / 16))
    return UInt64(ResolutionClamp.attentionHeadsWorstCase)
      * tokens * tokens
      * UInt64(ResolutionClamp.scoreBytes)
  }
}

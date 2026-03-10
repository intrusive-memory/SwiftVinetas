import Foundation
import Testing
@testable import SwiftVinetas

@Suite("AspectRatio Tests")
struct AspectRatioTests {

    // MARK: - Preset Dimensions

    @Test("square preset is 1024x1024")
    func squareDimensions() {
        #expect(AspectRatio.square.width == 1024)
        #expect(AspectRatio.square.height == 1024)
    }

    @Test("wide preset is 1344x768")
    func wideDimensions() {
        #expect(AspectRatio.wide.width == 1344)
        #expect(AspectRatio.wide.height == 768)
    }

    @Test("ultrawide preset is 1536x640")
    func ultrawideDimensions() {
        #expect(AspectRatio.ultrawide.width == 1536)
        #expect(AspectRatio.ultrawide.height == 640)
    }

    @Test("portrait preset is 768x1344")
    func portraitDimensions() {
        #expect(AspectRatio.portrait.width == 768)
        #expect(AspectRatio.portrait.height == 1344)
    }

    @Test("panel preset is 1216x832")
    func panelDimensions() {
        #expect(AspectRatio.panel.width == 1216)
        #expect(AspectRatio.panel.height == 832)
    }

    @Test("strip preset is 2048x512")
    func stripDimensions() {
        #expect(AspectRatio.strip.width == 2048)
        #expect(AspectRatio.strip.height == 512)
    }

    // MARK: - All Presets Are Multiples of 64

    @Test("all preset dimensions are multiples of 64")
    func allPresetsAreMultiplesOf64() {
        for ratio in AspectRatio.allCases {
            #expect(ratio.width % 64 == 0, "\(ratio.rawValue) width \(ratio.width) is not a multiple of 64")
            #expect(ratio.height % 64 == 0, "\(ratio.rawValue) height \(ratio.height) is not a multiple of 64")
        }
    }

    // MARK: - CaseIterable

    @Test("allCases contains all six presets")
    func allCasesCount() {
        #expect(AspectRatio.allCases.count == 6)
    }

    // MARK: - StyleConfig Integration

    @Test("styleConfig(base:) sets correct dimensions")
    func styleConfigIntegration() {
        let config = AspectRatio.wide.styleConfig()
        #expect(config.width == 1344)
        #expect(config.height == 768)
    }

    @Test("styleConfig preserves base style prompt")
    func styleConfigPreservesBaseProperties() {
        let base = StyleConfig(stylePrompt: "noir comic", steps: 30)
        let config = AspectRatio.portrait.styleConfig(base: base)
        #expect(config.stylePrompt == "noir comic")
        #expect(config.steps == 30)
        #expect(config.width == 768)
        #expect(config.height == 1344)
    }
}

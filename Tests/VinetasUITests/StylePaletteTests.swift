import Testing
import VinetasVocabulary

@testable import VinetasUI

@Suite struct StylePaletteTests {

  /// The V7 components of `hex` at `opacity`.
  private func v7(
    _ hex: UInt32,
    opacity: Double = 1
  ) -> (red: Double, green: Double, blue: Double, opacity: Double) {
    (
      red: Double((hex >> 16) & 0xff) / 255,
      green: Double((hex >> 8) & 0xff) / 255,
      blue: Double(hex & 0xff) / 255,
      opacity: opacity
    )
  }

  @Test func darkValuesAreTheV7Components() {
    #expect(VinetasStylePalette.darkValue(.rowBackground) == v7(0x2a2a2c))
    #expect(VinetasStylePalette.darkValue(.rowHover) == v7(0x323234))
    #expect(VinetasStylePalette.darkValue(.border) == v7(0x38383a))
    #expect(VinetasStylePalette.darkValue(.primaryText) == v7(0xf5f5f7))
    #expect(VinetasStylePalette.darkValue(.secondaryText) == v7(0x8e8e93))
    #expect(VinetasStylePalette.darkValue(.tertiaryText) == v7(0x6a6a6e))
    #expect(VinetasStylePalette.darkValue(.accent) == v7(0x0a84ff, opacity: 1.0))
    #expect(VinetasStylePalette.darkValue(.accentSoft) == v7(0x0a84ff, opacity: 0.18))
  }

  @Test func lightSourcesAreTheSystemColours() {
    #expect(VinetasStylePalette.lightSource(.rowBackground) == .quaternarySystemFill)
    #expect(VinetasStylePalette.lightSource(.rowHover) == .tertiarySystemFill)
    #expect(VinetasStylePalette.lightSource(.border) == .separator)
    #expect(VinetasStylePalette.lightSource(.primaryText) == .label)
    #expect(VinetasStylePalette.lightSource(.secondaryText) == .secondaryLabel)
    #expect(VinetasStylePalette.lightSource(.tertiaryText) == .tertiaryLabel)
    #expect(VinetasStylePalette.lightSource(.accent) == .accentColor)
    #expect(VinetasStylePalette.lightSource(.accentSoft) == .accentColorSoft)
  }

  @Test func accentSoftOpacityIsEighteenPercent() {
    #expect(VinetasStylePalette.accentSoftOpacity == 0.18)
  }

  @Test func everyTokenResolvesToAColour() {
    #expect(VinetasStylePalette.Token.allCases.count == 8)
    for token in VinetasStylePalette.Token.allCases {
      _ = VinetasStylePalette.color(token)
    }
  }
}

import Testing

@testable import VinetasVocabulary

struct StyleSwatchPaletteTests {
  @Test func everyStyleHasNineComponentsInUnitRange() {
    for style in StoryboardStyle.allCases {
      let components = style.swatchPalette.colors.flatMap { [$0.red, $0.green, $0.blue] }
      #expect(components.count == 9, "\(style)")
      #expect(components.allSatisfy { (0.0...1.0).contains($0) }, "\(style)")
    }
  }

  @Test func midCenturyModernFirstTripleIsC4923a() {
    let first = StoryboardStyle.midCenturyModern.swatchPalette.first
    #expect(first.red == Double(0xc4) / 255.0)
    #expect(first.green == Double(0x92) / 255.0)
    #expect(first.blue == Double(0x3a) / 255.0)
  }
}

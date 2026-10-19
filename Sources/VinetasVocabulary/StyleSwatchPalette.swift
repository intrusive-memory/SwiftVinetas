import Foundation

/// An sRGB value with each channel expressed as a `Double` in `0...1`.
///
/// This target links no UI framework, so a host converts the components
/// into its own value type.
public struct StyleSwatchRGB: Hashable, Sendable {
  /// The red channel, in `0...1`.
  public let red: Double

  /// The green channel, in `0...1`.
  public let green: Double

  /// The blue channel, in `0...1`.
  public let blue: Double

  /// Creates a value from three `0...1` channel values.
  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Creates a value from a 24-bit `0xRRGGBB` value.
  fileprivate init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xff) / 255.0,
      green: Double((hex >> 8) & 0xff) / 255.0,
      blue: Double(hex & 0xff) / 255.0
    )
  }
}

/// The three-value palette a style picker paints into a style's swatch.
public struct StyleSwatchPalette: Hashable, Sendable {
  /// The first value of the palette.
  public let first: StyleSwatchRGB

  /// The second value of the palette.
  public let second: StyleSwatchRGB

  /// The third value of the palette.
  public let third: StyleSwatchRGB

  /// Creates a palette from three values.
  public init(first: StyleSwatchRGB, second: StyleSwatchRGB, third: StyleSwatchRGB) {
    self.first = first
    self.second = second
    self.third = third
  }

  /// The three values in order, for iteration.
  public var colors: [StyleSwatchRGB] { [first, second, third] }

  fileprivate init(_ first: UInt32, _ second: UInt32, _ third: UInt32) {
    self.init(
      first: StyleSwatchRGB(hex: first),
      second: StyleSwatchRGB(hex: second),
      third: StyleSwatchRGB(hex: third)
    )
  }
}

extension StoryboardStyle {
  /// The three-value palette for this style's picker swatch.
  public var swatchPalette: StyleSwatchPalette {
    switch self {
    case .midCenturyModern:
      return StyleSwatchPalette(0xc4923a, 0xf0d8a3, 0x1f6a64)
    case .pencilSketchComic:
      return StyleSwatchPalette(0x2b2b2b, 0x8c8c8c, 0xe8e2d4)
    case .darkAcademic:
      return StyleSwatchPalette(0x3b2a1a, 0xc9a26a, 0x6b4423)
    case .dustBowlPhoto:
      return StyleSwatchPalette(0xc4a574, 0x8a6e4a, 0x4a3a2a)
    case .noirGraphicNovel:
      return StyleSwatchPalette(0x0a0a0a, 0xf0f0f0, 0x5a5a5a)
    case .watercolorStoryboard:
      return StyleSwatchPalette(0xc46a55, 0xf1c27d, 0x5b3a3a)
    case .japaneseScroll:
      return StyleSwatchPalette(0x1a1a1a, 0x9c8b6c, 0xcfcfcf)
    case .retroSciFiPulp:
      return StyleSwatchPalette(0xff5d3b, 0xf4d35e, 0x2a3f8a)
    case .popArtComic:
      return StyleSwatchPalette(0xffeb3b, 0xe91e63, 0x2196f3)
    case .minimalistLineArt:
      return StyleSwatchPalette(0xf4f1ea, 0xc7c7cc, 0x1a1a1a)
    case .photoRealistic:
      return StyleSwatchPalette(0x4a6b8a, 0xc9b88a, 0x6e6e6e)
    case .kodachrome1970s:
      return StyleSwatchPalette(0xd97b3f, 0xe5b85c, 0x8a4a2a)
    case .germanExpressionist:
      return StyleSwatchPalette(0x0a0a0a, 0xe8e8e8, 0x4a4a4a)
    case .spaghettiWestern:
      return StyleSwatchPalette(0xc97a3a, 0xd9a55c, 0x6b3a1a)
    case .watercolorAsianAnimation:
      return StyleSwatchPalette(0xbcd8a8, 0x7fa6c4, 0xf0d8a3)
    case .wesAndersonSymmetric:
      return StyleSwatchPalette(0xe2b06e, 0x86a8a3, 0xa73e2c)
    case .wuxiaInkBrush:
      return StyleSwatchPalette(0xc8453a, 0x1a1a1a, 0xd9c896)
    case .gialloHorror:
      return StyleSwatchPalette(0xc81a3a, 0x1a4a9a, 0x1a0a1a)
    case .atticRedFigure:
      return StyleSwatchPalette(0xc4622e, 0x0a0706, 0x8a3a1a)
    case .custom:
      return StyleSwatchPalette(0x3a3a3c, 0x5a5a5e, 0x2a2a2c)
    }
  }
}

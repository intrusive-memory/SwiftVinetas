// VinetasStylePalette.swift
// VinetasUI
//
// The eight semantic colours the style list draws with. Dark appearance keeps
// the Vinetas V7 values; light appearance uses the platform's system colours.

import SwiftUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

/// The style list's semantic colours, resolved per appearance.
///
/// | Token | V7 name | Light | Dark |
/// |---|---|---|---|
/// | `rowBackground` | `bgInput` | quaternarySystemFill | `0x2a2a2c` |
/// | `rowHover` | `bgInputHover` | tertiarySystemFill | `0x323234` |
/// | `border` | `border` | separator | `0x38383a` |
/// | `primaryText` | `fg` | label | `0xf5f5f7` |
/// | `secondaryText` | `fg3` | secondaryLabel | `0x8e8e93` |
/// | `tertiaryText` | `fg4` | tertiaryLabel | `0x6a6a6e` |
/// | `accent` | `accent` | `Color.accentColor` | `0x0a84ff` at 1.0 |
/// | `accentSoft` | `accentSoft` | `Color.accentColor` at 0.18 | `0x0a84ff` at 0.18 |
///
/// ``darkValue(_:)`` and ``lightSource(_:)`` are the two pure tables; the
/// dynamic colours ``color(_:)`` returns are built from them and nothing else.
enum VinetasStylePalette {

  /// A semantic colour of the style list.
  enum Token: CaseIterable {
    /// A row's resting fill.
    case rowBackground
    /// A row's fill under the pointer.
    case rowHover
    /// A row's outline.
    case border
    /// Style names.
    case primaryText
    /// Genre captions.
    case secondaryText
    /// Counts and other quiet text.
    case tertiaryText
    /// The selected row's outline and checkmark.
    case accent
    /// The selected row's fill.
    case accentSoft
  }

  /// The system colour a token takes in light appearance.
  enum LightSource: Hashable {
    /// quaternarySystemFill.
    case quaternarySystemFill
    /// tertiarySystemFill.
    case tertiarySystemFill
    /// separator (`separatorColor` on macOS).
    case separator
    /// label (`labelColor` on macOS).
    case label
    /// secondaryLabel (`secondaryLabelColor` on macOS).
    case secondaryLabel
    /// tertiaryLabel (`tertiaryLabelColor` on macOS).
    case tertiaryLabel
    /// `Color.accentColor`.
    case accentColor
    /// `Color.accentColor` at ``VinetasStylePalette/accentSoftOpacity``.
    case accentColorSoft
  }

  /// The opacity of the soft accent fill in both appearances.
  static let accentSoftOpacity: Double = 0.18

  /// The V7 dark-appearance components of `token`, each in `0...1`.
  static func darkValue(
    _ token: Token
  ) -> (red: Double, green: Double, blue: Double, opacity: Double) {
    func rgb(
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
    switch token {
    case .rowBackground: return rgb(0x2a2a2c)
    case .rowHover: return rgb(0x323234)
    case .border: return rgb(0x38383a)
    case .primaryText: return rgb(0xf5f5f7)
    case .secondaryText: return rgb(0x8e8e93)
    case .tertiaryText: return rgb(0x6a6a6e)
    case .accent: return rgb(0x0a84ff)
    case .accentSoft: return rgb(0x0a84ff, opacity: accentSoftOpacity)
    }
  }

  /// The system colour `token` takes in light appearance.
  static func lightSource(_ token: Token) -> LightSource {
    switch token {
    case .rowBackground: return .quaternarySystemFill
    case .rowHover: return .tertiarySystemFill
    case .border: return .separator
    case .primaryText: return .label
    case .secondaryText: return .secondaryLabel
    case .tertiaryText: return .tertiaryLabel
    case .accent: return .accentColor
    case .accentSoft: return .accentColorSoft
    }
  }

  /// The colour for `token`: ``darkValue(_:)`` in dark appearance,
  /// ``lightSource(_:)`` in light appearance.
  static func color(_ token: Token) -> Color {
    #if os(macOS)
      let dynamic = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? darkPlatformColor(token) : lightPlatformColor(lightSource(token))
      }
      return Color(nsColor: dynamic)
    #elseif os(iOS)
      let dynamic = UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        return isDark ? darkPlatformColor(token) : lightPlatformColor(lightSource(token))
      }
      return Color(uiColor: dynamic)
    #endif
  }

  /// A row's resting fill.
  static var rowBackground: Color { color(.rowBackground) }
  /// A row's fill under the pointer.
  static var rowHover: Color { color(.rowHover) }
  /// A row's outline.
  static var border: Color { color(.border) }
  /// Style names.
  static var primaryText: Color { color(.primaryText) }
  /// Genre captions.
  static var secondaryText: Color { color(.secondaryText) }
  /// Counts and other quiet text.
  static var tertiaryText: Color { color(.tertiaryText) }
  /// The selected row's outline and checkmark.
  static var accent: Color { color(.accent) }
  /// The selected row's fill.
  static var accentSoft: Color { color(.accentSoft) }

  #if os(macOS)
    private static func darkPlatformColor(_ token: Token) -> NSColor {
      let value = darkValue(token)
      return NSColor(
        srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
    }

    private static func lightPlatformColor(_ source: LightSource) -> NSColor {
      switch source {
      case .quaternarySystemFill: return .quaternarySystemFill
      case .tertiarySystemFill: return .tertiarySystemFill
      case .separator: return .separatorColor
      case .label: return .labelColor
      case .secondaryLabel: return .secondaryLabelColor
      case .tertiaryLabel: return .tertiaryLabelColor
      case .accentColor: return NSColor(Color.accentColor)
      case .accentColorSoft:
        return NSColor(Color.accentColor).withAlphaComponent(accentSoftOpacity)
      }
    }
  #elseif os(iOS)
    private static func darkPlatformColor(_ token: Token) -> UIColor {
      let value = darkValue(token)
      return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
    }

    private static func lightPlatformColor(_ source: LightSource) -> UIColor {
      switch source {
      case .quaternarySystemFill: return .quaternarySystemFill
      case .tertiarySystemFill: return .tertiarySystemFill
      case .separator: return .separator
      case .label: return .label
      case .secondaryLabel: return .secondaryLabel
      case .tertiaryLabel: return .tertiaryLabel
      case .accentColor: return UIColor(Color.accentColor)
      case .accentColorSoft:
        return UIColor(Color.accentColor).withAlphaComponent(accentSoftOpacity)
      }
    }
  #endif
}

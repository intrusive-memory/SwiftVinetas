// GradientSwatch.swift
// VinetasUI
//
// The three-band diagonal swatch most styles show in the style list.

import SwiftUI
import VinetasVocabulary

/// Three diagonal bands at 135° painted from a style's ``StyleSwatchPalette``.
///
/// The bands stop at 0–38 %, 38–70 % and 70–100 %, as in the Vinetas V7
/// handoff. The colours are fixed sRGB values, identical in light and dark
/// appearance.
struct GradientSwatch: View {

  /// The three values painted into the bands, in order.
  let palette: StyleSwatchPalette

  var body: some View {
    let first = Self.color(palette.first)
    let second = Self.color(palette.second)
    let third = Self.color(palette.third)
    LinearGradient(
      stops: [
        .init(color: first, location: 0.0),
        .init(color: first, location: 0.38),
        .init(color: second, location: 0.38),
        .init(color: second, location: 0.70),
        .init(color: third, location: 0.70),
        .init(color: third, location: 1.0),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  /// The SwiftUI colour of one palette value.
  static func color(_ value: StyleSwatchRGB) -> Color {
    Color(red: value.red, green: value.green, blue: value.blue)
  }
}

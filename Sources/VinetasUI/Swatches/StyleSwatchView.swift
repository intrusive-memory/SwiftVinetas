// StyleSwatchView.swift
// VinetasUI
//
// The 56 × 40 swatch at the leading edge of every style row, and of the
// style picker button that shows the selected style.

import SwiftUI
import VinetasVocabulary

/// A style's 56 × 40 swatch with a 7 pt corner radius.
///
/// Mid-Century Modern draws its static ``MidCenturySwatch`` scene, *Other*
/// (``StoryboardStyle/custom``) draws an ellipsis on the hover fill, and every
/// other style draws its ``GradientSwatch``.
struct StyleSwatchView: View {

  /// The swatch's width in points.
  static let width: CGFloat = 56
  /// The swatch's height in points.
  static let height: CGFloat = 40
  /// The swatch's corner radius in points.
  static let cornerRadius: CGFloat = 7

  /// The style the swatch represents.
  let style: StoryboardStyle

  var body: some View {
    Group {
      switch style {
      case .midCenturyModern:
        MidCenturySwatch()
      case .custom:
        CustomSwatch()
      default:
        GradientSwatch(palette: style.swatchPalette)
      }
    }
    .frame(width: Self.width, height: Self.height)
    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    .overlay(
      RoundedRectangle(cornerRadius: Self.cornerRadius)
        .inset(by: 0.5)
        .stroke(Color.white.opacity(0.06), lineWidth: 1)
    )
    .accessibilityHidden(true)
  }
}

/// The *Other* swatch: an ellipsis on the row hover fill.
private struct CustomSwatch: View {
  var body: some View {
    ZStack {
      VinetasStylePalette.rowHover
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(VinetasStylePalette.secondaryText)
    }
  }
}

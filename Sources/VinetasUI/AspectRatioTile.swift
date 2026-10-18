// AspectRatioTile.swift
// VinetasUI
//
// One selectable aspect-ratio preset: a small rectangle drawn in the ratio's
// proportions above its "16:9"-style label. Moved from the Vinetas app's
// macOS generation settings panel.

import SwiftUI
import VinetasVocabulary

/// A tappable tile that shows an aspect ratio's shape and label.
///
/// The tile draws its rectangle from the ratio's desired dimensions, so its
/// shape never depends on the device the panel runs on. It is identified
/// `VinetasUIAccessibility.aspectRatioTile(ratio.rawValue)` and carries the
/// selected trait while `isSelected` is `true`.
struct AspectRatioTile: View {

  /// The longest side of the drawn rectangle, in points.
  nonisolated static let maximumShapeSide: CGFloat = 36

  /// The human-readable ratio of `ratio`, for example `"16:9"`.
  nonisolated static func label(for ratio: AspectRatio) -> String {
    switch ratio {
    case .square: return "1:1"
    case .wide: return "16:9"
    case .ultrawide: return "2.4:1"
    case .portrait: return "9:16"
    case .panel: return "3:2"
    case .strip: return "4:1"
    }
  }

  /// The size of the rectangle drawn for `ratio`: its longer side is
  /// ``maximumShapeSide`` and the other keeps the ratio's proportions.
  nonisolated static func shapeSize(for ratio: AspectRatio) -> CGSize {
    let width = CGFloat(ratio.desiredWidth)
    let height = CGFloat(ratio.desiredHeight)
    if width >= height {
      return CGSize(width: maximumShapeSide, height: maximumShapeSide * height / width)
    }
    return CGSize(width: maximumShapeSide * width / height, height: maximumShapeSide)
  }

  let ratio: AspectRatio
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    let size = Self.shapeSize(for: ratio)
    let shape = RoundedRectangle(cornerRadius: 3)
    Button(action: select) {
      VStack(spacing: 4) {
        shape
          .fill(isSelected ? VinetasStylePalette.accent : VinetasStylePalette.rowBackground)
          .frame(width: size.width, height: size.height)
          .overlay(
            shape.strokeBorder(
              isSelected ? VinetasStylePalette.accent : VinetasStylePalette.border,
              lineWidth: isSelected ? 2 : 1
            )
          )
          .frame(height: Self.maximumShapeSide)
        Text(verbatim: Self.label(for: ratio))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(
            isSelected ? VinetasStylePalette.primaryText : VinetasStylePalette.secondaryText)
      }
      .frame(width: 48, height: 60)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(localized("\(Self.label(for: ratio)) aspect ratio"))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier(VinetasUIAccessibility.aspectRatioTile(ratio.rawValue))
  }
}

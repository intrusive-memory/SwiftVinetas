// VinetasStyleList.swift
// VinetasUI
//
// The vertical list of storyboard styles: swatch, name and genre caption per
// row, the selected row haloed in the accent colour, *Other* last.

import SwiftUI
import VinetasVocabulary

/// A vertical list of every ``StoryboardStyle``, for choosing a style prompt.
///
/// `selection` holds a style's `promptText`. The presets come first, sorted
/// by display name, and *Other* comes last; choosing *Other* sets the
/// selection to `StoryboardStyle.customTag`. A selection that matches no
/// preset — free text the host loaded from a script — is a custom style, so
/// it highlights *Other*.
///
/// Each row shows the style's swatch, display name and genre caption; the
/// selected row carries the accent halo and a checkmark. Choosing a row only
/// sets the binding: dismissing a popover or popping a pushed screen is the
/// caller's job.
///
/// The list takes its shape from the resolved panel layout:
///
/// - `.sidebar` and `.regular`: a 340 pt wide list, 5.5 rows tall, the body
///   of a popover or an inline list.
/// - `.compact`: an inset-grouped `List` that fills the screen it is pushed
///   onto.
///
/// The list draws no outer background; the host's container supplies it. It
/// is identified `VinetasUIAccessibility.stylePickerList`, and each row
/// `VinetasUIAccessibility.stylePickerRow(_:)` with the style's raw value.
public struct VinetasStyleList: View {

  /// The space between rows, in points.
  static let rowSpacing: CGFloat = 6
  /// A row's minimum height, in points.
  static let rowMinHeight: CGFloat = 56
  /// A row's corner radius, in points.
  static let rowCornerRadius: CGFloat = 7
  /// How many rows the popover form shows; the half-clipped last row makes
  /// it obvious the list scrolls.
  static let visibleRows: CGFloat = 5.5
  /// The popover form's width, in points.
  static let popoverWidth: CGFloat = 340

  /// The scrolling height of the popover form: 5.5 rows and their spacing.
  static var listHeight: CGFloat {
    visibleRows * rowMinHeight + (visibleRows - 1) * rowSpacing + 4
  }

  /// The rows in order: the presets sorted by display name, then *Other*.
  static var rowStyles: [StoryboardStyle] {
    StoryboardStyle.sortedPresets + [.custom]
  }

  /// The selection value a row writes: the style's `promptText`, or
  /// `StoryboardStyle.customTag` for *Other*.
  static func tag(for style: StoryboardStyle) -> String {
    style == .custom ? StoryboardStyle.customTag : style.promptText
  }

  /// The row a selection highlights: the preset whose `promptText` it is,
  /// otherwise *Other* (``StoryboardStyle/custom``), which covers
  /// `StoryboardStyle.customTag` and free text alike.
  static func selectedStyle(for selection: String) -> StoryboardStyle {
    StoryboardStyle.from(promptText: selection) ?? .custom
  }

  /// The accessibility identifier of the row for `style`.
  static func rowIdentifier(for style: StoryboardStyle) -> String {
    VinetasUIAccessibility.stylePickerRow(style.rawValue)
  }

  @Binding private var selection: String
  @Environment(\.resolvedPanelLayout) private var layout

  /// Creates a style list bound to a style prompt.
  ///
  /// - Parameter selection: The selected style's `promptText`, or
  ///   `StoryboardStyle.customTag` when *Other* is chosen.
  public init(selection: Binding<String>) {
    _selection = selection
  }

  /// The list in the shape the resolved panel layout asks for.
  public var body: some View {
    switch layout {
    case .sidebar, .regular:
      popoverList
    case .compact:
      compactList
    }
  }

  private var styleCountLabel: String {
    localized("\(Self.rowStyles.count) styles")
  }

  /// The 340 pt, 5.5-row list of a popover or an inline picker.
  private var popoverList: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(localized("Style"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)

        Spacer()

        Text(styleCountLabel)
          .font(.system(size: 11, weight: .regular))
          .foregroundStyle(VinetasStylePalette.tertiaryText)
          .lineLimit(1)
          .fixedSize()
      }

      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: Self.rowSpacing) {
          ForEach(Self.rowStyles) { style in
            VinetasStyleListRow(
              style: style,
              isSelected: Self.selectedStyle(for: selection) == style
            ) {
              selection = Self.tag(for: style)
            }
          }
        }
      }
      .frame(height: Self.listHeight)
      .accessibilityIdentifier(VinetasUIAccessibility.stylePickerList)
    }
    .frame(width: Self.popoverWidth)
  }

  /// The full-screen inset-grouped list of the compact pushed screen.
  private var compactList: some View {
    List {
      Section {
        ForEach(Self.rowStyles) { style in
          let isSelected = Self.selectedStyle(for: selection) == style
          Button {
            selection = Self.tag(for: style)
          } label: {
            VinetasStyleRowLabel(style: style, isSelected: isSelected)
              .frame(minHeight: Self.rowMinHeight)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowBackground(isSelected ? VinetasStylePalette.accentSoft : nil)
          .styleRowAccessibility(style: style, isSelected: isSelected)
        }
      } header: {
        Text(styleCountLabel)
      }
    }
    .compactListStyle()
    .accessibilityIdentifier(VinetasUIAccessibility.stylePickerList)
  }
}

// MARK: - Rows

/// One haloed row of the popover form.
private struct VinetasStyleListRow: View {

  let style: StoryboardStyle
  let isSelected: Bool
  let onTap: () -> Void

  @State private var isHovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: VinetasStyleList.rowCornerRadius)
    Button(action: onTap) {
      VinetasStyleRowLabel(style: style, isSelected: isSelected)
        .padding(8)
        .frame(minHeight: VinetasStyleList.rowMinHeight)
        .background(rowBackground)
        .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
        .clipShape(shape)
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
    .styleRowAccessibility(style: style, isSelected: isSelected)
  }

  private var rowBackground: Color {
    if isSelected { return VinetasStylePalette.accentSoft }
    return isHovering ? VinetasStylePalette.rowHover : VinetasStylePalette.rowBackground
  }

  private var borderColor: Color {
    isSelected ? VinetasStylePalette.accent : VinetasStylePalette.border
  }
}

/// A row's content: swatch, name, genre caption and the selection checkmark.
private struct VinetasStyleRowLabel: View {

  let style: StoryboardStyle
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      StyleSwatchView(style: style)

      VStack(alignment: .leading, spacing: 2) {
        Text(style.displayName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(VinetasStylePalette.primaryText)
          .lineLimit(1)

        Text(style.caption ?? localized("Custom prompt"))
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(VinetasStylePalette.secondaryText)
          .lineLimit(1)
          .truncationMode(.tail)
      }

      Spacer(minLength: 4)

      if isSelected {
        Image(systemName: "checkmark")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(VinetasStylePalette.accent)
          .padding(.trailing, 4)
      }
    }
  }
}

extension View {

  /// The identifier, label, value and traits every style row carries.
  fileprivate func styleRowAccessibility(style: StoryboardStyle, isSelected: Bool) -> some View {
    accessibilityIdentifier(VinetasStyleList.rowIdentifier(for: style))
      .accessibilityLabel(style.displayName)
      .accessibilityValue(style.caption ?? "")
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  /// Inset-grouped on iOS; the nearest inset style on macOS, which has none.
  @ViewBuilder
  fileprivate func compactListStyle() -> some View {
    #if os(iOS)
      listStyle(.insetGrouped)
    #else
      listStyle(.inset)
    #endif
  }
}

// MARK: - Previews

/// The granville establishing panel's `style`, verbatim: free text, so the
/// previews highlight *Other*.
private let granvilleEstablishingStyle =
  "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"

#Preview("Sidebar (macOS)", traits: .fixedLayout(width: 340, height: 760)) {
  VinetasStyleList(selection: .constant(granvilleEstablishingStyle))
    .vinetasPanelLayout(.sidebar)
}

#Preview("Regular (iPad)", traits: .fixedLayout(width: 1032, height: 1376)) {
  VinetasStyleList(selection: .constant(granvilleEstablishingStyle))
    .vinetasPanelLayout(.regular)
}

#Preview("Compact (iPhone)", traits: .fixedLayout(width: 402, height: 874)) {
  VinetasStyleList(selection: .constant(granvilleEstablishingStyle))
    .vinetasPanelLayout(.compact)
}

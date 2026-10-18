// VinetasStylePicker.swift
// VinetasUI
//
// The control that chooses a storyboard style: a button that opens the style
// list in a popover, a chevron row that pushes it, or the list inline — the
// form picked from the resolved panel layout, the picker style and whether a
// navigation stack is available.

import SwiftUI
import VinetasVocabulary

/// A control for choosing a ``StoryboardStyle`` prompt.
///
/// `selection` holds the style prompt itself: a preset's `promptText`, or the
/// free text of a custom style. Choosing *Other* keeps a custom style that is
/// already selected, and otherwise restores the last custom text typed here
/// (empty at first). Whenever the selection is not a preset — free text,
/// empty, or `StoryboardStyle.customTag` — the picker shows a text field for
/// the custom style, identified `VinetasUIAccessibility.promptStyleCustom`.
///
/// The picker takes one of three forms, decided by
/// ``form(layout:style:navigationAvailable:)``:
///
/// - ``Form/button`` — in the `.sidebar` and `.regular` layouts: a button
///   showing the selected style's swatch, name and genre caption that opens
///   ``VinetasStyleList`` in a popover, 340 pt wide and 5.5 rows tall, and
///   closes it as soon as a style is chosen.
/// - ``Form/navigationRow`` — in the `.compact` layout, when the host says a
///   `NavigationStack` encloses the panel (`vinetasNavigationStackAvailable`,
///   the default): a chevron row with the same label that pushes the full
///   style list and pops back on choice.
/// - ``Form/inlineList`` — whenever the host applies
///   `vinetasStylePickerStyle(.list)`: the 5.5-row list inline, whatever the
///   layout.
///
/// In the `.compact` layout without a navigation stack
/// (`vinetasNavigationStackAvailable(false)`) the picker falls back to the
/// ``Form/button`` form: SwiftUI cannot detect an enclosing stack, and a
/// `NavigationLink` outside one does nothing, so the list opens in a popover
/// instead.
///
/// The button and the row are identified
/// `VinetasUIAccessibility.promptStylePicker`. The picker draws no outer
/// background.
public struct VinetasStylePicker: View {

  /// The shape the picker takes.
  public enum Form: Sendable, Equatable, CaseIterable {
    /// A button that opens the style list in a popover.
    case button
    /// A chevron row that pushes the style list onto the navigation stack.
    case navigationRow
    /// The style list itself, inline, 5.5 rows tall.
    case inlineList
  }

  /// The form the picker takes for a panel layout, picker style and
  /// navigation-stack availability.
  ///
  /// `.list` always gives ``Form/inlineList``. Under `.automatic`, the
  /// `.sidebar` and `.regular` layouts give ``Form/button``; `.compact` gives
  /// ``Form/navigationRow`` when a navigation stack is available and
  /// ``Form/button`` when it is not.
  ///
  /// - Parameters:
  ///   - layout: The resolved panel layout.
  ///   - style: The picker style the host chose.
  ///   - navigationAvailable: Whether a `NavigationStack` encloses the panel.
  /// - Returns: The picker's form.
  public nonisolated static func form(
    layout: VinetasPanelLayout,
    style: VinetasStylePickerStyle,
    navigationAvailable: Bool
  ) -> Form {
    switch style {
    case .list:
      return .inlineList
    case .automatic:
      switch layout {
      case .sidebar, .regular:
        return .button
      case .compact:
        return navigationAvailable ? .navigationRow : .button
      }
    }
  }

  /// Whether `selection` is one of the preset styles' `promptText`.
  nonisolated static func isPreset(_ selection: String) -> Bool {
    StoryboardStyle.from(promptText: selection) != nil
  }

  @Binding private var selection: String
  @Environment(\.resolvedPanelLayout) private var layout
  @Environment(\.vinetasStylePickerStyle) private var pickerStyle
  @Environment(\.vinetasNavigationStackAvailable) private var navigationAvailable

  @State private var isListPresented = false
  @State private var lastCustomText = ""

  /// Creates a style picker bound to a style prompt.
  ///
  /// - Parameter selection: The selected style's `promptText`, or the custom
  ///   style's free text.
  public init(selection: Binding<String>) {
    _selection = selection
  }

  private var form: Form {
    Self.form(layout: layout, style: pickerStyle, navigationAvailable: navigationAvailable)
  }

  private var selectedStyle: StoryboardStyle {
    VinetasStyleList.selectedStyle(for: selection)
  }

  /// The picker in the form the layout, picker style and stack flag ask for,
  /// followed by the custom style field when the selection is not a preset.
  public var body: some View {
    if layout == .compact {
      // In a compact inset-grouped form each part is its own row.
      control
      customStyleField
    } else {
      VStack(alignment: .leading, spacing: 8) {
        control
        customStyleField
      }
    }
  }

  // MARK: - Forms

  @ViewBuilder
  private var control: some View {
    switch form {
    case .button:
      popoverButton
    case .navigationRow:
      navigationRow
    case .inlineList:
      VinetasStyleList(selection: listSelection)
        .vinetasPanelLayout(.regular)
    }
  }

  /// The binding the style list writes through: *Other* restores the last
  /// custom text, a preset is written as is, and either choice closes the
  /// popover.
  private var listSelection: Binding<String> {
    Binding(
      get: { selection },
      set: { newValue in
        let current = selection
        if newValue == StoryboardStyle.customTag {
          if Self.isPreset(current) {
            selection = lastCustomText
          }
        } else {
          if !Self.isPreset(current), current != StoryboardStyle.customTag {
            lastCustomText = current
          }
          selection = newValue
        }
        isListPresented = false
      }
    )
  }

  private var popoverButton: some View {
    VStack(alignment: .leading, spacing: 6) {
      if layout != .compact {
        heading
      }
      Button {
        isListPresented = true
      } label: {
        let shape = RoundedRectangle(cornerRadius: VinetasStyleList.rowCornerRadius)
        HStack(spacing: 12) {
          VinetasStylePickerLabel(style: selectedStyle)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(VinetasStylePalette.secondaryText)
            .padding(.trailing, 4)
        }
        .padding(8)
        .frame(minHeight: VinetasStyleList.rowMinHeight)
        .background(VinetasStylePalette.rowBackground)
        .overlay(shape.strokeBorder(VinetasStylePalette.border, lineWidth: 1))
        .clipShape(shape)
        .contentShape(shape)
      }
      .buttonStyle(.plain)
      .pickerAccessibility(style: selectedStyle)
      .popover(isPresented: $isListPresented, arrowEdge: .bottom) {
        VinetasStyleList(selection: listSelection)
          .vinetasPanelLayout(.regular)
          .padding(12)
          .presentationCompactAdaptation(.popover)
      }
    }
  }

  private var navigationRow: some View {
    NavigationLink {
      VinetasStyleListDestination(selection: listSelection)
    } label: {
      VinetasStylePickerLabel(style: selectedStyle)
        .frame(minHeight: VinetasStyleList.rowMinHeight)
        .contentShape(Rectangle())
    }
    .pickerAccessibility(style: selectedStyle)
  }

  /// The "Style" heading and style count drawn above the popover button.
  private var heading: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(localized("Style"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(VinetasStylePalette.primaryText)
      Spacer()
      Text(localized("\(VinetasStyleList.rowStyles.count) styles"))
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(VinetasStylePalette.tertiaryText)
        .lineLimit(1)
        .fixedSize()
    }
  }

  // MARK: - Custom style

  /// The text the custom field edits: the free-text selection, or empty for
  /// the bare *Other* sentinel.
  private var customText: Binding<String> {
    Binding(
      get: { selection == StoryboardStyle.customTag ? "" : selection },
      set: { newValue in
        lastCustomText = newValue
        selection = newValue
      }
    )
  }

  @ViewBuilder
  private var customStyleField: some View {
    if !Self.isPreset(selection) {
      TextField(localized("Describe your style…"), text: customText, axis: .vertical)
        .lineLimit(2...4)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(localized("Custom style prompt"))
        .accessibilityIdentifier(VinetasUIAccessibility.promptStyleCustom)
    }
  }
}

// MARK: - Pieces

/// The selected style's swatch, name and genre caption.
private struct VinetasStylePickerLabel: View {

  let style: StoryboardStyle

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
    }
  }
}

/// The pushed style list of the compact navigation row; pops on choice.
private struct VinetasStyleListDestination: View {

  @Binding var selection: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VinetasStyleList(
      selection: Binding(
        get: { selection },
        set: { newValue in
          selection = newValue
          dismiss()
        }
      )
    )
    .vinetasPanelLayout(.compact)
    .navigationTitle(localized("Style"))
  }
}

extension View {

  /// The identifier, label and value the picker button and row carry.
  fileprivate func pickerAccessibility(style: StoryboardStyle) -> some View {
    accessibilityIdentifier(VinetasUIAccessibility.promptStylePicker)
      .accessibilityLabel(localized("Style"))
      .accessibilityValue(style.displayName)
  }
}

// MARK: - Previews

#Preview("Sidebar (macOS)", traits: .fixedLayout(width: 340, height: 760)) {
  @Previewable @State var style =
    "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"
  VinetasStylePicker(selection: $style)
    .padding()
    .vinetasPanelLayout(.sidebar)
}

#Preview("Regular (iPad)", traits: .fixedLayout(width: 1032, height: 1376)) {
  @Previewable @State var style =
    "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"
  VinetasStylePicker(selection: $style)
    .padding()
    .vinetasPanelLayout(.regular)
}

#Preview("Compact (iPhone)", traits: .fixedLayout(width: 402, height: 874)) {
  @Previewable @State var style =
    "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"
  NavigationStack {
    SwiftUI.Form {
      Section {
        VinetasStylePicker(selection: $style)
      }
    }
    .formStyle(.grouped)
  }
  .vinetasPanelLayout(.compact)
}

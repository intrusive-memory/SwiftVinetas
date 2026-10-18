// VinetasPromptPanel.swift
// VinetasUI
//
// The prompt half of the storyboard panel editor: the primary prompt with its
// engine badge and hint, an optional caption, the style picker with its
// prompt text, and the negative prompt — laid out for the resolved panel
// layout.

import SwiftUI
import VinetasVocabulary

#if os(macOS)
  import AppKit
#endif

/// The prompt editor for one storyboard panel.
///
/// The panel edits three strings — the primary `prompt`, the `stylePrompt`
/// chosen with ``VinetasStylePicker``, and the `negativePrompt` — and, when
/// the host passes a `caption` binding, a single-line caption under the
/// prompt. `selectedModel` only labels the prompt with an engine badge and
/// writing hints; the panel never changes the model.
///
/// Choosing a preset style writes that style's `negativePromptText` into
/// `negativePrompt` and reveals the Negative Prompt section, so the change is
/// visible (see ``applyPreset(_:to:)``). A custom style leaves the negative
/// prompt alone.
///
/// The panel takes its shape from the resolved panel layout:
///
/// - `.sidebar`: one column — the prompt editor, the caption, the style
///   picker button, the style's *Prompt text* disclosure, and the Negative
///   Prompt disclosure, collapsed until a preset is chosen.
/// - `.regular`: the same column with a 140 pt minimum prompt editor; the
///   keyboard dismisses interactively on scroll.
/// - `.compact`: an inset-grouped form — Prompt and Caption in one group with
///   the engine badge in its header, Style as a chevron row, and Negative
///   Prompt expanded under its own header; a 100 pt minimum prompt editor.
///
/// The panel draws no outer background and no action buttons; the host's
/// container supplies both. Its controls are identified
/// `VinetasUIAccessibility.promptPrimary`, `.promptCaption`,
/// `.promptNegativeToggle`, `.promptNegative` and
/// `.stylePickerPromptTextDisclosure`.
public struct VinetasPromptPanel: View {

  /// Writes the negative prompt a style prompt implies.
  ///
  /// When `stylePrompt` is a preset's `promptText`, `negativePrompt` becomes
  /// that style's `negativePromptText`. `StoryboardStyle.customTag` and free
  /// text leave `negativePrompt` unchanged.
  ///
  /// - Parameters:
  ///   - stylePrompt: The style prompt just chosen.
  ///   - negativePrompt: The negative prompt to update.
  public nonisolated static func applyPreset(_ stylePrompt: String, to negativePrompt: inout String)
  {
    guard let style = StoryboardStyle.from(promptText: stylePrompt) else { return }
    negativePrompt = style.negativePromptText
  }

  /// The minimum height of the prompt editor in `layout`, in points.
  nonisolated static func promptEditorMinHeight(for layout: VinetasPanelLayout) -> CGFloat {
    layout == .regular ? 140 : 100
  }

  /// The short engine name shown in the badge beside the Prompt label.
  nonisolated static func engineBadge(for model: ModelSummary) -> String {
    switch model.engineID {
    case "flux2": return "FLUX.2"
    case "pixart-sigma": return "PixArt"
    default: return model.displayName
    }
  }

  /// Prompt-writing guidance for `model`'s engine, or `nil` when there is none.
  nonisolated static func promptHint(for model: ModelSummary) -> String? {
    switch model.engineID {
    case "flux2":
      return localized(
        "FLUX.2 responds well to detailed, descriptive prose. Include lighting, composition, and style cues."
      )
    case "pixart-sigma":
      return localized(
        "PixArt-Sigma works best with concise, keyword-rich prompts. Separate concepts with commas."
      )
    default:
      return nil
    }
  }

  /// Negative-prompt guidance for `model`'s engine, or `nil` when there is none.
  nonisolated static func negativeHint(for model: ModelSummary) -> String? {
    switch model.engineID {
    case "pixart-sigma":
      return localized(
        "PixArt-Sigma uses classifier-free guidance — negative prompts have strong effect.")
    default:
      return nil
    }
  }

  @Binding private var prompt: String
  @Binding private var stylePrompt: String
  @Binding private var negativePrompt: String
  private let caption: Binding<String>?
  private let selectedModel: ModelSummary

  @Environment(\.resolvedPanelLayout) private var layout

  /// `nil` until the user or a preset choice opens or closes the Negative
  /// Prompt section; until then it is expanded only at compact width.
  @State private var negativeExpandedChoice: Bool?
  @State private var promptTextExpanded = false

  /// Creates a prompt panel.
  ///
  /// - Parameters:
  ///   - prompt: The primary prompt.
  ///   - stylePrompt: The style prompt: a preset's `promptText` or free text.
  ///   - negativePrompt: The negative prompt.
  ///   - selectedModel: The model the prompt is written for; it picks the
  ///     engine badge and hints.
  ///   - caption: The caption shown under the prompt, or `nil` (the default)
  ///     for no caption field.
  public init(
    prompt: Binding<String>,
    stylePrompt: Binding<String>,
    negativePrompt: Binding<String>,
    selectedModel: ModelSummary,
    caption: Binding<String>? = nil
  ) {
    _prompt = prompt
    _stylePrompt = stylePrompt
    _negativePrompt = negativePrompt
    self.selectedModel = selectedModel
    self.caption = caption
  }

  /// The panel in the shape the resolved panel layout asks for.
  public var body: some View {
    switch layout {
    case .sidebar:
      column(spacing: 12)
    case .regular:
      column(spacing: 16)
        .dismissesKeyboardOnScroll()
    case .compact:
      Form {
        compactSections
      }
      .formStyle(.grouped)
      .dismissesKeyboardOnScroll()
    }
  }

  // MARK: - State

  private var negativeExpanded: Binding<Bool> {
    Binding(
      get: { negativeExpandedChoice ?? (layout == .compact) },
      set: { negativeExpandedChoice = $0 }
    )
  }

  /// The style binding handed to the picker: a preset choice also writes the
  /// preset's negative prompt and reveals the Negative Prompt section.
  private var styleSelection: Binding<String> {
    Binding(
      get: { stylePrompt },
      set: { newValue in
        stylePrompt = newValue
        guard VinetasStylePicker.isPreset(newValue) else { return }
        var negative = negativePrompt
        Self.applyPreset(newValue, to: &negative)
        negativePrompt = negative
        negativeExpandedChoice = true
      }
    )
  }

  // MARK: - Sidebar and regular

  private func column(spacing: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: spacing) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(localized("Prompt"))
            .font(.headline)
            .foregroundStyle(VinetasStylePalette.primaryText)
          Spacer()
          engineBadge
        }
        promptEditor
          .frame(maxHeight: 200)
          .editorChrome()
        hint(Self.promptHint(for: selectedModel))
      }

      if let caption {
        VStack(alignment: .leading, spacing: 6) {
          Text(localized("Caption"))
            .font(.headline)
            .foregroundStyle(VinetasStylePalette.primaryText)
          captionField(caption)
            .textFieldStyle(.roundedBorder)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        VinetasStylePicker(selection: styleSelection)
        promptTextDisclosure
      }

      DisclosureGroup(isExpanded: negativeExpanded) {
        VStack(alignment: .leading, spacing: 4) {
          negativeEditor
            .frame(minHeight: 60, maxHeight: 120)
            .editorChrome()
            .padding(.top, 4)
          hint(Self.negativeHint(for: selectedModel))
        }
      } label: {
        Text(localized("Negative Prompt"))
          .font(.headline)
          .foregroundStyle(VinetasStylePalette.primaryText)
      }
      .accessibilityIdentifier(VinetasUIAccessibility.promptNegativeToggle)
    }
    .padding()
  }

  // MARK: - Compact

  /// The compact layout's sections, ready for an enclosing inset-grouped
  /// `Form`.
  @ViewBuilder
  var compactSections: some View {
    Section {
      promptEditor
      if let caption {
        LabeledContent(localized("Caption")) {
          captionField(caption)
            .multilineTextAlignment(.trailing)
        }
      }
    } header: {
      HStack(alignment: .firstTextBaseline) {
        Text(localized("Prompt"))
        Spacer()
        engineBadge
      }
    } footer: {
      hint(Self.promptHint(for: selectedModel))
    }

    Section {
      VinetasStylePicker(selection: styleSelection)
      promptTextDisclosure
    } header: {
      HStack(alignment: .firstTextBaseline) {
        Text(localized("Style"))
        Spacer()
        Text(localized("\(VinetasStyleList.rowStyles.count) styles"))
      }
    }

    Section {
      if negativeExpanded.wrappedValue {
        negativeEditor
          .frame(minHeight: 60)
      }
    } header: {
      Button {
        negativeExpandedChoice = !negativeExpanded.wrappedValue
      } label: {
        HStack {
          Text(localized("Negative Prompt"))
          Spacer()
          Image(systemName: negativeExpanded.wrappedValue ? "chevron.up" : "chevron.down")
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(localized("Negative prompt section"))
      .accessibilityIdentifier(VinetasUIAccessibility.promptNegativeToggle)
    } footer: {
      if negativeExpanded.wrappedValue {
        hint(Self.negativeHint(for: selectedModel))
      }
    }
  }

  // MARK: - Pieces

  private var promptEditor: some View {
    TextEditor(text: $prompt)
      .font(.body)
      .scrollContentBackground(.hidden)
      .frame(minHeight: Self.promptEditorMinHeight(for: layout))
      .accessibilityLabel(localized("Primary prompt"))
      .accessibilityHint(localized("Describe the image you want to generate"))
      .accessibilityIdentifier(VinetasUIAccessibility.promptPrimary)
  }

  private var negativeEditor: some View {
    TextEditor(text: $negativePrompt)
      .font(.body)
      .scrollContentBackground(.hidden)
      .accessibilityLabel(localized("Negative Prompt"))
      .accessibilityHint(localized("Describe what you want to avoid in the generated image"))
      .accessibilityIdentifier(VinetasUIAccessibility.promptNegative)
  }

  private func captionField(_ caption: Binding<String>) -> some View {
    TextField(localized("Caption"), text: caption)
      .lineLimit(1)
      .accessibilityLabel(localized("Caption"))
      .accessibilityIdentifier(VinetasUIAccessibility.promptCaption)
  }

  /// The selected preset's prompt text behind a disclosure; nothing for a
  /// custom style, whose text is already in the custom field.
  @ViewBuilder
  private var promptTextDisclosure: some View {
    if VinetasStylePicker.isPreset(stylePrompt) {
      DisclosureGroup(isExpanded: $promptTextExpanded) {
        Text(stylePrompt)
          .font(.system(size: 12, weight: .regular, design: .monospaced))
          .foregroundStyle(VinetasStylePalette.secondaryText)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .editorChrome()
          .padding(.top, 4)
          .accessibilityLabel(localized("Style prompt text"))
      } label: {
        Text(localized("Prompt text"))
          .font(.subheadline)
          .foregroundStyle(VinetasStylePalette.secondaryText)
      }
      .accessibilityIdentifier(VinetasUIAccessibility.stylePickerPromptTextDisclosure)
    }
  }

  private var engineBadge: some View {
    Text(verbatim: Self.engineBadge(for: selectedModel))
      .font(.caption2)
      .foregroundStyle(VinetasStylePalette.secondaryText)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(VinetasStylePalette.rowBackground, in: Capsule())
      .textCase(nil)
  }

  @ViewBuilder
  private func hint(_ text: String?) -> some View {
    if let text {
      Text(text)
        .font(.caption)
        .foregroundStyle(VinetasStylePalette.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - Platform modifiers

extension View {

  /// The rounded, outlined field fill of the prompt editors.
  fileprivate func editorChrome() -> some View {
    let shape = RoundedRectangle(cornerRadius: 8)
    return background(editorFill)
      .clipShape(shape)
      .overlay(shape.strokeBorder(VinetasStylePalette.border, lineWidth: 1))
  }

  /// The text-field fill colour of the current platform.
  fileprivate var editorFill: Color {
    #if os(iOS)
      Color(.secondarySystemBackground)
    #else
      Color(nsColor: .textBackgroundColor)
    #endif
  }

  /// Dismisses the keyboard interactively as the content scrolls (iOS only).
  @ViewBuilder
  fileprivate func dismissesKeyboardOnScroll() -> some View {
    #if os(iOS)
      scrollDismissesKeyboard(.interactively)
    #else
      self
    #endif
  }
}

// MARK: - Previews

#Preview("Sidebar (macOS)", traits: .fixedLayout(width: 340, height: 760)) {
  @Previewable @State var prompt =
    "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame."
  @Previewable @State var style =
    "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"
  @Previewable @State var negative =
    "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry"
  VinetasPromptPanel(
    prompt: $prompt,
    stylePrompt: $style,
    negativePrompt: $negative,
    selectedModel: .klein4B
  )
  .vinetasPanelLayout(.sidebar)
}

#Preview("Regular (iPad)", traits: .fixedLayout(width: 1032, height: 1376)) {
  @Previewable @State var prompt =
    "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame."
  @Previewable @State var style =
    "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"
  @Previewable @State var negative =
    "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry"
  VinetasPromptPanel(
    prompt: $prompt,
    stylePrompt: $style,
    negativePrompt: $negative,
    selectedModel: .klein4B
  )
  .vinetasPanelLayout(.regular)
}

#Preview("Compact (iPhone)", traits: .fixedLayout(width: 402, height: 874)) {
  @Previewable @State var prompt =
    "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame."
  @Previewable @State var style =
    "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light"
  @Previewable @State var negative =
    "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry"
  NavigationStack {
    VinetasPromptPanel(
      prompt: $prompt,
      stylePrompt: $style,
      negativePrompt: $negative,
      selectedModel: .klein4B
    )
  }
  .vinetasPanelLayout(.compact)
}

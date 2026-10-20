// VinetasPromptComposer.swift
// VinetasUI
//
// The prompt panel and the generation settings panel stacked and bound to one
// `VinetasPromptDraft`, with Default and Randomize expressed as `nil`.

import SwiftUI
import VinetasVocabulary

/// The whole storyboard panel editor — ``VinetasPromptPanel`` with its style
/// picker, and ``VinetasGenerationSettingsPanel`` — bound to one
/// ``VinetasPromptDraft``.
///
/// Default and Randomize are expressed as `nil` in the draft. A Default
/// toggle that is on means its field is `nil`, and the control shows the
/// selected model's default dimmed; turning the toggle off writes that
/// default into the field as a starting point. The composer never writes a
/// model default into the draft while a Default toggle is on. A `nil` seed
/// means Randomize is on. Changing the model changes nothing else: resetting
/// steps, guidance or aspect ratio is the host's job. The bridging is the
/// pure ``setDefault(_:on:in:model:)`` and ``setRandomize(_:in:)``.
///
/// The composer takes its shape from the resolved panel layout:
///
/// - `.sidebar`: the two panels stacked in one column, unscrolled — the
///   host's container (for example an inspector) scrolls it.
/// - `.regular`: the two panels stacked in one scrolling column.
/// - `.compact`: one inset-grouped form holding both panels' sections, so
///   the screen scrolls as a whole. Put it in a `NavigationStack` so the
///   style row can push the style list.
///
/// With `showsReferenceControls` on, a References row (an ordered list the
/// user can add to, remove from and reorder, capped at the selected model's
/// `maxReferenceImages` and disabled at 0) and a Character row appear; they
/// are absent from the view hierarchy otherwise. A host may pass a
/// `statusSection` — content shown below the controls — and gets nothing
/// by default (`EmptyView`).
///
/// The composer draws no outer background and no action buttons; the host
/// supplies both.
public struct VinetasPromptComposer<StatusSection: View>: View {

  private typealias Rules = VinetasPromptComposer<EmptyView>

  @Binding private var draft: VinetasPromptDraft
  private let models: [ModelSummary]
  private let showsCaption: Bool
  let showsReferenceControls: Bool
  private let statusSection: StatusSection

  @Environment(\.resolvedPanelLayout) private var layout

  /// Creates a composer with a host-supplied status section.
  ///
  /// - Parameters:
  ///   - draft: The draft every control edits.
  ///   - models: The models to offer, already filtered by the host.
  ///   - showsCaption: Whether to show the caption field under the prompt.
  ///   - showsReferenceControls: Whether to show the References and
  ///     Character rows.
  ///   - statusSection: Host content shown below the controls.
  public init(
    draft: Binding<VinetasPromptDraft>,
    models: [ModelSummary] = ModelSummary.all,
    showsCaption: Bool = false,
    showsReferenceControls: Bool = false,
    @ViewBuilder statusSection: () -> StatusSection
  ) {
    _draft = draft
    self.models = models
    self.showsCaption = showsCaption
    self.showsReferenceControls = showsReferenceControls
    self.statusSection = statusSection()
  }

  /// The composer in the shape the resolved panel layout asks for.
  public var body: some View {
    switch layout {
    case .sidebar:
      column
    case .regular:
      ScrollView {
        column
      }
      .dismissesKeyboardOnScrollInComposer()
    case .compact:
      Form {
        promptPanel
          .environment(\.vinetasEmbedsCompactSections, true)
        settingsPanel
          .environment(\.vinetasEmbedsCompactSections, true)
        if showsReferenceControls {
          Section { referencesRow }
          Section { characterRow }
        }
        statusSection
      }
      .formStyle(.grouped)
      .dismissesKeyboardOnScrollInComposer()
    }
  }

  // MARK: - Layout

  private var column: some View {
    VStack(alignment: .leading, spacing: 0) {
      promptPanel
      Divider()
        .padding(.horizontal)
      settingsPanel
      if showsReferenceControls {
        Divider()
          .padding(.horizontal)
        VStack(alignment: .leading, spacing: 12) {
          referencesRow
          characterRow
        }
        .padding()
      }
      statusSection
    }
  }

  // MARK: - Reference rows

  private var referenceLimit: Int { Rules.referenceLimit(for: selectedModel) }

  private var referencesRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(localized("References"))
        .font(.headline)
      if referenceLimit == 0 {
        Text(localized("This model does not use reference images"))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier(VinetasUIAccessibility.referencesUnsupportedNote)
      }
      ForEach(Array(draft.references.indices), id: \.self) { index in
        HStack {
          TextField(
            localized("Path or name"),
            text: referenceBinding(index)
          )
          .accessibilityLabel(Text(localized("Reference \(index + 1)")))
          .accessibilityIdentifier(VinetasUIAccessibility.referenceItem(index))
          Button {
            Rules.moveReference(from: index, by: -1, in: &draft)
          } label: {
            Image(systemName: "chevron.up")
          }
          .disabled(index == 0)
          .accessibilityLabel(Text(localized("Move reference up")))
          .accessibilityIdentifier(VinetasUIAccessibility.referenceMoveUp(index))
          Button {
            Rules.moveReference(from: index, by: 1, in: &draft)
          } label: {
            Image(systemName: "chevron.down")
          }
          .disabled(index == draft.references.count - 1)
          .accessibilityLabel(Text(localized("Move reference down")))
          .accessibilityIdentifier(VinetasUIAccessibility.referenceMoveDown(index))
          Button {
            Rules.removeReference(at: index, in: &draft)
          } label: {
            Image(systemName: "minus.circle")
          }
          .accessibilityLabel(Text(localized("Remove reference")))
          .accessibilityIdentifier(VinetasUIAccessibility.referenceRemove(index))
        }
        .buttonStyle(.borderless)
      }
      Button {
        Rules.addReference(in: &draft, limit: referenceLimit)
      } label: {
        Label(localized("Add reference"), systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .disabled(!Rules.canAddReference(count: draft.references.count, limit: referenceLimit))
      .accessibilityIdentifier(VinetasUIAccessibility.referencesAdd)
    }
    .disabled(referenceLimit == 0)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(VinetasUIAccessibility.referencesList)
  }

  private var characterRow: some View {
    TextField(
      localized("Character"),
      text: Binding(
        get: { draft.character ?? "" },
        set: { draft.character = $0.isEmpty ? nil : $0 }
      ),
      prompt: Text(localized("Character name"))
    )
    .accessibilityIdentifier(VinetasUIAccessibility.characterField)
  }

  private func referenceBinding(_ index: Int) -> Binding<String> {
    Binding(
      get: { draft.references.indices.contains(index) ? draft.references[index] : "" },
      set: { if draft.references.indices.contains(index) { draft.references[index] = $0 } }
    )
  }

  private var promptPanel: some View {
    VinetasPromptPanel(
      prompt: $draft.prompt,
      stylePrompt: $draft.stylePrompt,
      negativePrompt: $draft.negativePrompt,
      selectedModel: selectedModel,
      caption: showsCaption ? caption : nil
    )
  }

  private var settingsPanel: some View {
    VinetasGenerationSettingsPanel(
      models: models,
      selectedModel: modelSelection,
      aspectRatio: aspectRatio,
      steps: steps,
      guidance: guidance,
      seed: seed,
      randomizeSeed: randomizeSeed,
      useDefaultSteps: useDefault(.steps),
      useDefaultGuidance: useDefault(.guidance),
      useDefaultAspectRatio: useDefault(.aspectRatio)
    )
  }

  // MARK: - Bindings

  /// The model the draft names: from `models` first, then the shipped
  /// models, falling back to the first offered model.
  private var selectedModel: ModelSummary {
    models.first { $0.id == draft.modelID } ?? draft.model ?? models.first
      ?? .pixartSigmaXL
  }

  private var modelSelection: Binding<ModelSummary> {
    Binding(
      get: { selectedModel },
      set: { draft.modelID = $0.id }
    )
  }

  /// The caption; clearing the field stores `nil`.
  private var caption: Binding<String> {
    Binding(
      get: { draft.caption ?? "" },
      set: { draft.caption = $0.isEmpty ? nil : $0 }
    )
  }

  // Each value binding shows the model's default while its field is `nil`
  // and drops writes until the toggle is off, so a default never lands in
  // the draft without the user turning Default off.

  private var aspectRatio: Binding<AspectRatio> {
    Binding(
      get: { draft.aspectRatio ?? selectedModel.supportedAspectRatios.first ?? .square },
      set: { if draft.aspectRatio != nil { draft.aspectRatio = $0 } }
    )
  }

  private var steps: Binding<Int> {
    Binding(
      get: { draft.steps ?? selectedModel.defaultSteps },
      set: { if draft.steps != nil { draft.steps = $0 } }
    )
  }

  private var guidance: Binding<Float> {
    Binding(
      get: { draft.guidance ?? selectedModel.defaultGuidance },
      set: { if draft.guidance != nil { draft.guidance = $0 } }
    )
  }

  private var seed: Binding<UInt64> {
    Binding(
      get: { draft.seed ?? 0 },
      set: { if draft.seed != nil { draft.seed = $0 } }
    )
  }

  private var randomizeSeed: Binding<Bool> {
    Binding(
      get: { draft.seed == nil },
      set: { Rules.setRandomize($0, in: &draft) }
    )
  }

  private func useDefault(_ field: Rules.DraftField) -> Binding<Bool> {
    Binding(
      get: {
        switch field {
        case .steps: draft.steps == nil
        case .guidance: draft.guidance == nil
        case .aspectRatio: draft.aspectRatio == nil
        }
      },
      set: { Rules.setDefault(field, on: $0, in: &draft, model: selectedModel) }
    )
  }
}

// MARK: - Pure rules (EmptyView-constrained so bare `VinetasPromptComposer.x` keeps resolving)

extension VinetasPromptComposer where StatusSection == EmptyView {

  /// A draft field that has a Default toggle.
  public enum DraftField: Sendable, CaseIterable {
    /// ``VinetasPromptDraft/steps``.
    case steps
    /// ``VinetasPromptDraft/guidance``.
    case guidance
    /// ``VinetasPromptDraft/aspectRatio``.
    case aspectRatio
  }

  /// Applies a Default toggle change to `draft`.
  ///
  /// Turning Default on sets `field` to `nil`. Turning it off writes
  /// `model`'s default into a `nil` field as a starting point — its
  /// `defaultSteps`, its `defaultGuidance`, or the first of its
  /// `supportedAspectRatios` — and leaves a field that already holds a
  /// value unchanged.
  ///
  /// - Parameters:
  ///   - field: The field whose toggle changed.
  ///   - isDefault: Whether the Default toggle is now on.
  ///   - draft: The draft to update.
  ///   - model: The selected model, whose defaults seed the field.
  public nonisolated static func setDefault(
    _ field: DraftField,
    on isDefault: Bool,
    in draft: inout VinetasPromptDraft,
    model: ModelSummary
  ) {
    switch field {
    case .steps:
      if isDefault {
        draft.steps = nil
      } else if draft.steps == nil {
        draft.steps = model.defaultSteps
      }
    case .guidance:
      if isDefault {
        draft.guidance = nil
      } else if draft.guidance == nil {
        draft.guidance = model.defaultGuidance
      }
    case .aspectRatio:
      if isDefault {
        draft.aspectRatio = nil
      } else if draft.aspectRatio == nil {
        draft.aspectRatio = model.supportedAspectRatios.first
      }
    }
  }

  /// Applies a Randomize toggle change to `draft`.
  ///
  /// Turning Randomize on sets the seed to `nil`. Turning it off keeps a
  /// seed the draft already holds, and otherwise writes `0` — the value the
  /// disabled seed field shows while Randomize is on — as a starting point.
  ///
  /// - Parameters:
  ///   - on: Whether Randomize is now on.
  ///   - draft: The draft to update.
  public nonisolated static func setRandomize(_ on: Bool, in draft: inout VinetasPromptDraft) {
    if on {
      draft.seed = nil
    } else if draft.seed == nil {
      draft.seed = 0
    }
  }

  /// The number of reference images `model` accepts.
  nonisolated static func referenceLimit(for model: ModelSummary) -> Int {
    max(0, model.maxReferenceImages)
  }

  /// Whether another reference fits under `limit`.
  nonisolated static func canAddReference(count: Int, limit: Int) -> Bool {
    limit > 0 && count < limit
  }

  /// Appends an empty reference unless `limit` is reached.
  nonisolated static func addReference(in draft: inout VinetasPromptDraft, limit: Int) {
    guard canAddReference(count: draft.references.count, limit: limit) else { return }
    draft.references.append("")
  }

  /// Removes the reference at `index`, if it exists.
  nonisolated static func removeReference(at index: Int, in draft: inout VinetasPromptDraft) {
    guard draft.references.indices.contains(index) else { return }
    draft.references.remove(at: index)
  }

  /// Moves the reference at `index` by `offset` positions, clamped to the list.
  nonisolated static func moveReference(
    from index: Int, by offset: Int, in draft: inout VinetasPromptDraft
  ) {
    let target = index + offset
    guard draft.references.indices.contains(index), draft.references.indices.contains(target)
    else { return }
    draft.references.swapAt(index, target)
  }
}

// MARK: - Default status section

extension VinetasPromptComposer where StatusSection == EmptyView {

  /// Creates a composer with no status section.
  ///
  /// - Parameters:
  ///   - draft: The draft every control edits.
  ///   - models: The models to offer, already filtered by the host.
  ///   - showsCaption: Whether to show the caption field under the prompt.
  ///   - showsReferenceControls: Whether to show the References and
  ///     Character rows.
  public init(
    draft: Binding<VinetasPromptDraft>,
    models: [ModelSummary] = ModelSummary.all,
    showsCaption: Bool = false,
    showsReferenceControls: Bool = false
  ) {
    self.init(
      draft: draft, models: models, showsCaption: showsCaption,
      showsReferenceControls: showsReferenceControls
    ) { EmptyView() }
  }
}

// MARK: - Platform modifiers

extension View {

  /// Dismisses the keyboard interactively as the content scrolls (iOS only).
  @ViewBuilder
  fileprivate func dismissesKeyboardOnScrollInComposer() -> some View {
    #if os(iOS)
      scrollDismissesKeyboard(.interactively)
    #else
      self
    #endif
  }
}

// MARK: - Previews

extension VinetasPromptDraft {

  /// The establishing shot of granville episode 1 as a draft, captioned with
  /// its scene heading.
  fileprivate static let establishingShot = VinetasPromptDraft(
    prompt:
      "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame.",
    caption: "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET",
    stylePrompt:
      "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light",
    negativePrompt:
      "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry",
    modelID: "flux2-klein-4b",
    aspectRatio: .wide,
    steps: 8,
    guidance: 3.5,
    seed: 22
  )
}

#Preview("Sidebar (macOS)", traits: .fixedLayout(width: 340, height: 760)) {
  @Previewable @State var draft = VinetasPromptDraft.establishingShot
  ScrollView {
    VinetasPromptComposer(draft: $draft, showsCaption: true)
  }
  .vinetasPanelLayout(.sidebar)
}

#Preview("Regular (iPad)", traits: .fixedLayout(width: 1032, height: 1376)) {
  @Previewable @State var draft = VinetasPromptDraft.establishingShot
  VinetasPromptComposer(draft: $draft, showsCaption: true)
    .vinetasPanelLayout(.regular)
}

#Preview("Compact (iPhone)", traits: .fixedLayout(width: 402, height: 874)) {
  @Previewable @State var draft = VinetasPromptDraft.establishingShot
  NavigationStack {
    VinetasPromptComposer(draft: $draft, showsCaption: true)
  }
  .vinetasPanelLayout(.compact)
}

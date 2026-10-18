// VinetasGenerationSettingsPanel.swift
// VinetasUI
//
// The generation half of the storyboard panel editor: the model picker with
// its download size and memory text, the aspect-ratio tiles, the steps and
// guidance sliders, and the seed — laid out for the resolved panel layout.

import SwiftUI
import VinetasVocabulary

/// The generation settings editor for one storyboard panel.
///
/// The panel edits the model, aspect ratio, steps, guidance and seed the
/// host passes as bindings. It offers exactly the `models` the host passes,
/// grouped by engine; each model's approximate download size and minimum
/// memory are shown as text only and never gate a choice. Changing the model
/// changes nothing else: resetting steps, guidance or aspect ratio to a
/// model's defaults is the host's job.
///
/// Each `useDefault…` binding the host passes adds a Default toggle beside
/// its control and disables the control while the toggle is on; a `nil`
/// binding (the default) renders no toggle. The `footnote` is drawn under
/// the model picker.
///
/// The panel takes its shape from the resolved panel layout:
///
/// - `.sidebar`: one column — Model, Aspect Ratio as one horizontal strip of
///   tiles, Steps, Guidance, and Seed with Randomize. Default and Randomize
///   are checkboxes on macOS.
/// - `.regular`: the same column with Steps and Guidance side by side.
/// - `.compact`: an inset-grouped form — Model as an inline menu row with the
///   size and memory in its footer, wrapping aspect-ratio tiles with a
///   Default switch row, Steps and Guidance cells with their value and a
///   Default switch, and Seed with a Randomize switch.
///
/// The panel draws no outer background and no action buttons; the host's
/// container supplies both. Its controls are identified through
/// `VinetasUIAccessibility`: `.generationModelPicker`,
/// `.generationAspectRatioSelection`, `aspectRatioTile(_:)`,
/// `.generationStepsSlider`, `.generationStepsUseDefault`,
/// `.generationGuidanceSlider`, `.generationGuidanceUseDefault`,
/// `.generationAspectRatioUseDefault`, `.generationSeedField` and
/// `.generationRandomizeSeed`.
public struct VinetasGenerationSettingsPanel<Footnote: View>: View {

  private let models: [ModelSummary]
  @Binding private var selectedModel: ModelSummary
  @Binding private var aspectRatio: AspectRatio
  @Binding private var steps: Int
  @Binding private var guidance: Float
  @Binding private var seed: UInt64
  @Binding private var randomizeSeed: Bool
  private let useDefaultSteps: Binding<Bool>?
  private let useDefaultGuidance: Binding<Bool>?
  private let useDefaultAspectRatio: Binding<Bool>?
  private let footnote: Footnote

  @Environment(\.resolvedPanelLayout) private var layout
  @Environment(\.vinetasEmbedsCompactSections) private var embedsCompactSections

  /// Creates a generation settings panel with a footnote under the model
  /// picker.
  ///
  /// - Parameters:
  ///   - models: The models to offer, already filtered by the host; the
  ///     picker groups them by `engineID` in first-seen order.
  ///   - selectedModel: The chosen model.
  ///   - aspectRatio: The chosen aspect ratio; the tiles offer the selected
  ///     model's `supportedAspectRatios`.
  ///   - steps: The inference steps, from 1 to 50.
  ///   - guidance: The guidance scale, from 1.0 to 20.0 in steps of 0.5.
  ///   - seed: The seed.
  ///   - randomizeSeed: Whether each generation picks a new seed; while it is
  ///     `true` the seed field is disabled.
  ///   - useDefaultSteps: Whether steps follow the model's default, or `nil`
  ///     (the default) for no Default toggle.
  ///   - useDefaultGuidance: Whether guidance follows the model's default, or
  ///     `nil` (the default) for no Default toggle.
  ///   - useDefaultAspectRatio: Whether the aspect ratio follows the default,
  ///     or `nil` (the default) for no Default toggle.
  ///   - footnote: A view drawn under the model picker.
  public init(
    models: [ModelSummary],
    selectedModel: Binding<ModelSummary>,
    aspectRatio: Binding<AspectRatio>,
    steps: Binding<Int>,
    guidance: Binding<Float>,
    seed: Binding<UInt64>,
    randomizeSeed: Binding<Bool>,
    useDefaultSteps: Binding<Bool>? = nil,
    useDefaultGuidance: Binding<Bool>? = nil,
    useDefaultAspectRatio: Binding<Bool>? = nil,
    @ViewBuilder footnote: () -> Footnote
  ) {
    self.models = models
    _selectedModel = selectedModel
    _aspectRatio = aspectRatio
    _steps = steps
    _guidance = guidance
    _seed = seed
    _randomizeSeed = randomizeSeed
    self.useDefaultSteps = useDefaultSteps
    self.useDefaultGuidance = useDefaultGuidance
    self.useDefaultAspectRatio = useDefaultAspectRatio
    self.footnote = footnote()
  }

  /// The panel in the shape the resolved panel layout asks for.
  public var body: some View {
    switch layout {
    case .sidebar:
      column(stepsAndGuidanceSideBySide: false)
    case .regular:
      column(stepsAndGuidanceSideBySide: true)
    case .compact:
      if embedsCompactSections {
        compactSections
      } else {
        Form {
          compactSections
        }
        .formStyle(.grouped)
      }
    }
  }

  // MARK: - State

  private var engineGroups: [(engineID: String, models: [ModelSummary])] {
    VinetasGenerationSettingsPanel<EmptyView>.groupedByEngine(models)
  }

  private var stepsLocked: Bool { useDefaultSteps?.wrappedValue == true }
  private var guidanceLocked: Bool { useDefaultGuidance?.wrappedValue == true }
  private var aspectRatioLocked: Bool { useDefaultAspectRatio?.wrappedValue == true }

  private var guidanceText: String { String(format: "%.1f", guidance) }

  // MARK: - Sidebar and regular

  private func column(stepsAndGuidanceSideBySide: Bool) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        heading(localized("Model"))
        modelPicker
          .labelsHidden()
        modelInfoRow
        footnote
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          heading(localized("Aspect Ratio"))
          Spacer()
          if let useDefaultAspectRatio {
            aspectRatioDefaultToggle(useDefaultAspectRatio)
              .checkboxToggleOnMacOS()
              .font(.caption)
          }
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            aspectRatioTiles
          }
          .padding(.horizontal, 2)
        }
        .aspectRatioSelection(locked: aspectRatioLocked)
      }

      if stepsAndGuidanceSideBySide {
        HStack(alignment: .top, spacing: 24) {
          stepsColumn
            .frame(maxWidth: .infinity)
          guidanceColumn
            .frame(maxWidth: .infinity)
        }
      } else {
        stepsColumn
        guidanceColumn
      }

      VStack(alignment: .leading, spacing: 8) {
        heading(localized("Seed"))
        HStack {
          seedField
            .textFieldStyle(.roundedBorder)
          randomizeToggle
            .checkboxToggleOnMacOS()
            .fixedSize()
        }
      }
    }
    .padding()
  }

  private var stepsColumn: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        heading(localized("Steps"))
        Spacer()
        valueText("\(steps)")
        if let useDefaultSteps {
          stepsDefaultToggle(useDefaultSteps)
            .checkboxToggleOnMacOS()
            .font(.caption)
        }
      }
      stepsSlider
    }
  }

  private var guidanceColumn: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        heading(localized("Guidance"))
        Spacer()
        valueText(guidanceText)
        if let useDefaultGuidance {
          guidanceDefaultToggle(useDefaultGuidance)
            .checkboxToggleOnMacOS()
            .font(.caption)
        }
      }
      guidanceSlider
    }
  }

  // MARK: - Compact

  /// The compact layout's sections, ready for an enclosing inset-grouped
  /// `Form`.
  @ViewBuilder
  var compactSections: some View {
    Section {
      modelPicker
    } header: {
      Text(localized("Model"))
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        modelInfoRow
        footnote
      }
    }

    Section {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
        aspectRatioTiles
      }
      .aspectRatioSelection(locked: aspectRatioLocked)
      if let useDefaultAspectRatio {
        aspectRatioDefaultToggle(useDefaultAspectRatio)
          .toggleStyle(.switch)
      }
    } header: {
      Text(localized("Aspect Ratio"))
    }

    Section {
      LabeledContent(localized("Steps")) {
        valueText("\(steps)")
      }
      stepsSlider
      if let useDefaultSteps {
        stepsDefaultToggle(useDefaultSteps)
          .toggleStyle(.switch)
      }
    }

    Section {
      LabeledContent(localized("Guidance")) {
        valueText(guidanceText)
      }
      guidanceSlider
      if let useDefaultGuidance {
        guidanceDefaultToggle(useDefaultGuidance)
          .toggleStyle(.switch)
      }
    }

    Section {
      LabeledContent(localized("Seed")) {
        seedField
          .multilineTextAlignment(.trailing)
      }
      randomizeToggle
        .toggleStyle(.switch)
    } header: {
      Text(localized("Seed"))
    }
  }

  // MARK: - Pieces

  private func heading(_ text: String) -> some View {
    Text(text)
      .font(.headline)
      .foregroundStyle(VinetasStylePalette.primaryText)
  }

  private func valueText(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.body.monospacedDigit())
      .foregroundStyle(VinetasStylePalette.secondaryText)
  }

  /// The model menu, one section per engine in first-seen order.
  private var modelPicker: some View {
    Picker(localized("Model"), selection: $selectedModel) {
      ForEach(engineGroups, id: \.engineID) { group in
        Section {
          ForEach(group.models) { model in
            Text(verbatim: model.displayName)
              .tag(model)
          }
        } header: {
          Text(verbatim: Self.engineName(of: group.models))
        }
      }
    }
    .pickerStyle(.menu)
    .accessibilityLabel(localized("Model selection"))
    .accessibilityHint(localized("Choose the model to use for image generation"))
    .accessibilityIdentifier(VinetasUIAccessibility.generationModelPicker)
  }

  /// The selected model's download size and minimum memory, as text.
  private var modelInfoRow: some View {
    HStack(spacing: 12) {
      Label(selectedModel.approximateDownloadSize, systemImage: "arrow.down.circle")
      Label(localized("\(selectedModel.minimumMemoryGB) GB RAM"), systemImage: "memorychip")
    }
    .font(.caption)
    .foregroundStyle(VinetasStylePalette.secondaryText)
  }

  private var aspectRatioTiles: some View {
    ForEach(selectedModel.supportedAspectRatios, id: \.self) { ratio in
      AspectRatioTile(ratio: ratio, isSelected: aspectRatio == ratio) {
        aspectRatio = ratio
      }
    }
  }

  private var stepsSlider: some View {
    Slider(
      value: Binding(
        get: { Double(steps) },
        set: { steps = Int($0.rounded()) }
      ),
      in: 1...50,
      step: 1
    )
    .disabled(stepsLocked)
    .opacity(stepsLocked ? 0.5 : 1)
    .accessibilityLabel(localized("Inference steps"))
    .accessibilityHint(localized("Higher values produce more detail but take longer"))
    .accessibilityValue(localized("\(steps) steps"))
    .accessibilityIdentifier(VinetasUIAccessibility.generationStepsSlider)
  }

  private var guidanceSlider: some View {
    Slider(
      value: Binding(
        get: { Double(guidance) },
        set: { guidance = Float($0) }
      ),
      in: 1.0...20.0,
      step: 0.5
    )
    .disabled(guidanceLocked)
    .opacity(guidanceLocked ? 0.5 : 1)
    .accessibilityLabel(localized("Guidance scale"))
    .accessibilityHint(localized("Controls how closely the image follows the prompt"))
    .accessibilityValue(guidanceText)
    .accessibilityIdentifier(VinetasUIAccessibility.generationGuidanceSlider)
  }

  private var seedField: some View {
    TextField(localized("Seed"), value: $seed, format: .number)
      .numberPadKeyboard()
      .disabled(randomizeSeed)
      .foregroundStyle(
        randomizeSeed ? VinetasStylePalette.secondaryText : VinetasStylePalette.primaryText
      )
      .accessibilityLabel(localized("Seed value"))
      .accessibilityHint(
        localized("Determines the starting noise pattern for reproducible results")
      )
      .accessibilityIdentifier(VinetasUIAccessibility.generationSeedField)
  }

  private var randomizeToggle: some View {
    Toggle(localized("Randomize"), isOn: $randomizeSeed)
      .accessibilityLabel(localized("Randomize seed"))
      .accessibilityHint(localized("When enabled, a new random seed is used for each generation"))
      .accessibilityIdentifier(VinetasUIAccessibility.generationRandomizeSeed)
  }

  private func stepsDefaultToggle(_ isOn: Binding<Bool>) -> some View {
    Toggle(localized("Default"), isOn: isOn)
      .accessibilityLabel(localized("Use default steps"))
      .accessibilityHint(
        localized("When enabled, locks steps to the selected model's recommended value")
      )
      .accessibilityIdentifier(VinetasUIAccessibility.generationStepsUseDefault)
  }

  private func guidanceDefaultToggle(_ isOn: Binding<Bool>) -> some View {
    Toggle(localized("Default"), isOn: isOn)
      .accessibilityLabel(localized("Use default guidance"))
      .accessibilityHint(
        localized("When enabled, locks guidance to the selected model's recommended value")
      )
      .accessibilityIdentifier(VinetasUIAccessibility.generationGuidanceUseDefault)
  }

  private func aspectRatioDefaultToggle(_ isOn: Binding<Bool>) -> some View {
    Toggle(localized("Default"), isOn: isOn)
      .accessibilityLabel(localized("Use default aspect ratio"))
      .accessibilityHint(localized("When enabled, locks the aspect ratio to the default"))
      .accessibilityIdentifier(VinetasUIAccessibility.generationAspectRatioUseDefault)
  }

  /// The section title of one engine group: the engine's short name.
  nonisolated static func engineName(of models: [ModelSummary]) -> String {
    guard let first = models.first else { return "" }
    return VinetasPromptPanel.engineBadge(for: first)
  }
}

extension VinetasGenerationSettingsPanel where Footnote == EmptyView {

  /// Creates a generation settings panel with no footnote.
  ///
  /// - Parameters:
  ///   - models: The models to offer, already filtered by the host; the
  ///     picker groups them by `engineID` in first-seen order.
  ///   - selectedModel: The chosen model.
  ///   - aspectRatio: The chosen aspect ratio.
  ///   - steps: The inference steps, from 1 to 50.
  ///   - guidance: The guidance scale, from 1.0 to 20.0 in steps of 0.5.
  ///   - seed: The seed.
  ///   - randomizeSeed: Whether each generation picks a new seed.
  ///   - useDefaultSteps: Whether steps follow the model's default, or `nil`
  ///     (the default) for no Default toggle.
  ///   - useDefaultGuidance: Whether guidance follows the model's default, or
  ///     `nil` (the default) for no Default toggle.
  ///   - useDefaultAspectRatio: Whether the aspect ratio follows the default,
  ///     or `nil` (the default) for no Default toggle.
  public init(
    models: [ModelSummary],
    selectedModel: Binding<ModelSummary>,
    aspectRatio: Binding<AspectRatio>,
    steps: Binding<Int>,
    guidance: Binding<Float>,
    seed: Binding<UInt64>,
    randomizeSeed: Binding<Bool>,
    useDefaultSteps: Binding<Bool>? = nil,
    useDefaultGuidance: Binding<Bool>? = nil,
    useDefaultAspectRatio: Binding<Bool>? = nil
  ) {
    self.init(
      models: models,
      selectedModel: selectedModel,
      aspectRatio: aspectRatio,
      steps: steps,
      guidance: guidance,
      seed: seed,
      randomizeSeed: randomizeSeed,
      useDefaultSteps: useDefaultSteps,
      useDefaultGuidance: useDefaultGuidance,
      useDefaultAspectRatio: useDefaultAspectRatio,
      footnote: { EmptyView() }
    )
  }

  /// Groups `models` by `engineID`, keeping both the engines and the models
  /// within each engine in the order they first appear.
  ///
  /// - Parameter models: The models to group.
  /// - Returns: One `(engineID, models)` pair per distinct engine.
  public nonisolated static func groupedByEngine(
    _ models: [ModelSummary]
  ) -> [(engineID: String, models: [ModelSummary])] {
    var groups: [(engineID: String, models: [ModelSummary])] = []
    for model in models {
      if let index = groups.firstIndex(where: { $0.engineID == model.engineID }) {
        groups[index].models.append(model)
      } else {
        groups.append((engineID: model.engineID, models: [model]))
      }
    }
    return groups
  }
}

// MARK: - Platform modifiers

extension View {

  /// Checkbox style on macOS; the platform's default toggle elsewhere.
  @ViewBuilder
  fileprivate func checkboxToggleOnMacOS() -> some View {
    #if os(macOS)
      toggleStyle(.checkbox)
    #else
      self
    #endif
  }

  /// The number-pad keyboard on iOS; nothing elsewhere.
  @ViewBuilder
  fileprivate func numberPadKeyboard() -> some View {
    #if os(iOS)
      keyboardType(.numberPad)
    #else
      self
    #endif
  }

  /// The aspect-ratio tile group: dimmed and disabled while `locked`, and
  /// identified as one container whose tiles stay visible to UI tests.
  fileprivate func aspectRatioSelection(locked: Bool) -> some View {
    disabled(locked)
      .opacity(locked ? 0.5 : 1)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(localized("Aspect ratio selection"))
      .accessibilityIdentifier(VinetasUIAccessibility.generationAspectRatioSelection)
  }
}

// MARK: - Previews

#Preview("Sidebar (macOS)", traits: .fixedLayout(width: 340, height: 760)) {
  @Previewable @State var model = ModelSummary.klein4B
  @Previewable @State var aspect = AspectRatio.wide
  @Previewable @State var steps = 8
  @Previewable @State var guidance: Float = 3.5
  @Previewable @State var seed: UInt64 = 22
  @Previewable @State var randomize = false
  @Previewable @State var defaultSteps = false
  @Previewable @State var defaultGuidance = false
  @Previewable @State var defaultAspect = false
  VinetasGenerationSettingsPanel(
    models: ModelSummary.all,
    selectedModel: $model,
    aspectRatio: $aspect,
    steps: $steps,
    guidance: $guidance,
    seed: $seed,
    randomizeSeed: $randomize,
    useDefaultSteps: $defaultSteps,
    useDefaultGuidance: $defaultGuidance,
    useDefaultAspectRatio: $defaultAspect
  )
  .vinetasPanelLayout(.sidebar)
}

#Preview("Regular (iPad)", traits: .fixedLayout(width: 1032, height: 1376)) {
  @Previewable @State var model = ModelSummary.klein4B
  @Previewable @State var aspect = AspectRatio.wide
  @Previewable @State var steps = 8
  @Previewable @State var guidance: Float = 3.5
  @Previewable @State var seed: UInt64 = 22
  @Previewable @State var randomize = false
  VinetasGenerationSettingsPanel(
    models: ModelSummary.all,
    selectedModel: $model,
    aspectRatio: $aspect,
    steps: $steps,
    guidance: $guidance,
    seed: $seed,
    randomizeSeed: $randomize
  )
  .vinetasPanelLayout(.regular)
}

#Preview("Compact (iPhone)", traits: .fixedLayout(width: 402, height: 874)) {
  @Previewable @State var model = ModelSummary.klein4B
  @Previewable @State var aspect = AspectRatio.wide
  @Previewable @State var steps = 8
  @Previewable @State var guidance: Float = 3.5
  @Previewable @State var seed: UInt64 = 22
  @Previewable @State var randomize = false
  @Previewable @State var defaultSteps = false
  @Previewable @State var defaultGuidance = false
  @Previewable @State var defaultAspect = false
  NavigationStack {
    VinetasGenerationSettingsPanel(
      models: ModelSummary.all,
      selectedModel: $model,
      aspectRatio: $aspect,
      steps: $steps,
      guidance: $guidance,
      seed: $seed,
      randomizeSeed: $randomize,
      useDefaultSteps: $defaultSteps,
      useDefaultGuidance: $defaultGuidance,
      useDefaultAspectRatio: $defaultAspect
    )
  }
  .vinetasPanelLayout(.compact)
}

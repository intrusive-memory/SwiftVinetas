---
type: execution-plan
requirements_file: docs/REQUIREMENTS-vinetas-ui.md
recon_report: RECON_REPORT.md
---

# EXECUTION_PLAN.md — SwiftVinetas: `VinetasUI`, the prompt panel as a portable popup

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Mission Scope

This plan covers **step 1** of `docs/REQUIREMENTS-vinetas-ui.md`: § 1 (`VinetasVocabulary`),
§ 2 (`VinetasUI`) and the release-readiness half of § 3, all in this repo. Steps 2 (Vinetas
adopts) and 3 (Escribir links) are separate breakdowns in those repos and start only after
our next minor release is tagged.

The requirements were audited in `RECON_REPORT.md`. Nine of their premises did not hold,
and the user answered with a direction rather than an amended document. **Where this
section and the requirements disagree, this section wins.** The requirements file still
states the old premises and should be amended before the step-2 breakdown reads it.

### User direction (2026-10-06)

> "ok, let's adapt the panel from vinetas to the popup metaphor for Mac and iOS and do
> some reference layouts for iPad, iPhone and mac. We want it portable to add to any other
> program where we want to generate an image."

How this plan reads it (the reading itself is `OQ-1`):

- **The style picker becomes a popup on every platform.** A button showing the selected
  style's swatch, name and genre caption opens the style list. The inline 5.5-row list
  stays available as an opt-in style, so a host can keep today's look.
- **The whole panel can be presented as a popup.** A view modifier presents the composer
  as a popover on macOS and iPad and as a sheet on iPhone, with a host-supplied action
  row. This is the form another program adds with one line.
- **Reference layouts** are named, device-sized `#Preview`s for Mac, iPad and iPhone on
  every public surface: fifteen in all.
- **Portable** means `VinetasUI` knows nothing about Vinetas: no Pro, no downloads, no
  memory checks, no generation, and no dependency beyond `VinetasVocabulary`.

This supersedes § 2.2's `.compact` row and § 2.3's `Menu`, makes the popup an explicit
exception to Non-goal 3 ("no redesign"), and means Acceptance 4's "no edit to any XCUITest
file" will not hold in step 2 if Vinetas adopts the popup. Everything else in Non-goal 3
stands: spacing, slider ranges, tile strip and row design move as they are.

### Decisions taken on the recon report's recommendation

The user saw these recommendations and did not object; they were not separately
confirmed. Each is cheap to reverse before Sortie 4.

- **Optional Default bindings.** The three `useDefault…` bindings on the settings panel
  are optional; `nil` renders no toggle. The package never resets steps or guidance when
  the model changes.
- **Apple system frameworks only.** `ResolutionClamp.swift` moves unchanged with its
  conditional `import Metal`. The dependency rule is "no package dependencies", not
  "Foundation only".
- **Previews without device pinning.** `#Preview(traits:)` has no device trait. Each
  preview forces its layout through `.vinetasPanelLayout(…)` and sizes the canvas with
  `traits: .fixedLayout(width:height:)`.

### Corrections absorbed from recon

- `promptText` is what the Vinetas app persists, and `rawValue` feeds accessibility
  identifiers and the exported catalogue. **Both are frozen.** No case is renamed,
  reordered, added or removed, and no prompt string changes by a byte.
- The Mid-Century swatch is static. `TimelineView` is forbidden in `VinetasUI`; the
  animation was removed from the app because it starved MLX of GPU time.
- The UI work is a merge of two diverged forks plus `MidCenturySwatch.swift`, not a move.
- The accessibility namespace carries nineteen existing strings (the requirements list
  seventeen) plus one new one.
- CI has no lint step and no iOS job today; Work Unit 3 adds both.

### Other decisions

- **The target is named `VinetasVocabulary`.** The requirements let breakdown rename it
  once; it stays.
- **The release is outside the mission.** A mission branch cannot tag. The mission ends
  release-ready; the user then opens the pull request and runs `ship-swift-library minor`,
  which bumps the version literals and flips the manifest to remote-only. No sortie edits
  a version literal or names a version number.
- **No Klein 9B and no memory gating** (standing user directives). `ModelSummary` has
  exactly two models. `minimumMemoryGB` is display text only.

### Rules for every sortie

1. Build and test only through Makefile targets or XcodeBuildMCP. **Never** `swift build`
   or `swift test`. `swift package dump-package` is allowed; it only reads the manifest.
2. Read Vinetas app source only through
   `git -C ~/Projects/apps/Vinetas show 0c25a3d:<path>`. Never edit that checkout, the
   worktree beside it, or any sibling dependency checkout.
3. `Sources/VinetasVocabulary` and `Sources/VinetasUI` import no package product.
   `VinetasUI` imports `VinetasVocabulary`, SwiftUI and platform frameworks only.
4. Do not edit `Sources/VinetasCLICore`, `Sources/vinetas` or `Tests/SwiftVinetasGPUTests`.
5. This machine runs Xcode 27; CI runs `macos-26`. Use no API introduced after the OS 26
   SDKs. CI is the truth for the UI target.
6. In `VinetasUI`, every user-facing string goes through
   `String(localized:bundle: .module)`, and every accessibility identifier comes from
   `VinetasUIAccessibility`.
7. Run `make lint` before each commit.

`<start>` in exit criteria means the mission's `starting_point_commit`.

Reference canvas sizes for previews, in points: Mac 340 × 760, iPad 1032 × 1376,
iPhone 402 × 874. Preview names are exactly `"Sidebar (macOS)"`, `"Regular (iPad)"` and
`"Compact (iPhone)"` for views, and `"Popup (macOS)"`, `"Popup (iPad)"`,
`"Popup (iPhone)"` for the popup.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU-1 Vocabulary | `Sources/VinetasVocabulary`, `Tests/VinetasVocabularyTests`, `Package.swift` | 3 (S1–S3) | 0 | none |
| WU-2 UI | `Sources/VinetasUI`, `Tests/VinetasUITests`, `Package.swift`, `Makefile` | 9 (S4–S12) | 1 | WU-1 |
| WU-3 Release readiness | `Makefile`, `.github/workflows/tests.yml`, `AGENTS.md`, `README.md`, `docs/` | 2 (S13–S14) | 2 | WU-2 |

---

## WU-1 Vocabulary

### Sortie 1: Carve the `VinetasVocabulary` target

**Entry criteria**:
- [ ] First sortie — no prerequisites.
- [ ] Recon facts in force: the three files are a closed set (R-02); their tests reference
      nothing outside them (R-13); nothing uses a module-qualified spelling (R-14).

**Tasks**:
1. In `Package.swift`, add target `VinetasVocabulary` with no dependencies, library
   product `VinetasVocabulary`, and test target `VinetasVocabularyTests` depending on it.
   Add `"VinetasVocabulary"` to the `SwiftVinetas` target's dependencies.
2. `git mv` `AspectRatio.swift`, `ResolutionClamp.swift` and `StyleConfig.swift` from
   `Sources/SwiftVinetas/Core/` to `Sources/VinetasVocabulary/`, contents unchanged.
3. `git mv` `AspectRatioTests.swift`, `ResolutionClampTests.swift` and
   `StyleConfigTests.swift` to `Tests/VinetasVocabularyTests/`, changing only
   `@testable import SwiftVinetas` to `@testable import VinetasVocabulary`.
4. Create `Sources/SwiftVinetas/VinetasVocabularyReExport.swift` containing
   `@_exported import VinetasVocabulary` and a doc comment naming it the compatibility
   shim.
5. In the `Makefile`, add `-only-testing:VinetasVocabularyTests` to `test-unit` and
   `test-unit-ios`.

**Exit criteria**:
- [ ] `swift package dump-package | jq -c '[.targets[]|select(.name=="VinetasVocabulary")|.dependencies[]]'` prints `[]`.
- [ ] `grep -h '^import' Sources/VinetasVocabulary/*.swift | sort -u` prints exactly `import Foundation` and `import Metal`.
- [ ] `git diff --name-status -M <start> -- Sources/SwiftVinetas` lists exactly four entries: three renames out of `Core/` and one added file.
- [ ] `git diff --stat <start> -- Sources/VinetasCLICore Sources/vinetas Tests/SwiftVinetasGPUTests` is empty.
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0, and `build/test-output.log` shows passing results for the suites declared in the three moved test files.

### Sortie 2: `ModelSummary` and the descriptor drift test

**Entry criteria**:
- [ ] Sortie 1 exit criteria met.
- [ ] Recon facts in force: `ModelDescriptor` carries all eight fields with matching names
      and types (R-06); the statics are `Flux2ModelDescriptor.klein4B` and
      `PixArtModelDescriptor.sigmaXL` (R-07).

**Tasks**:
1. Add `Codable` to `AspectRatio`'s declaration in `Sources/VinetasVocabulary/AspectRatio.swift`.
2. Create `Sources/VinetasVocabulary/ModelSummary.swift` with the struct from
   requirements § 1.2 and these literal values:

   | Static | id | displayName | engineID | minimumMemoryGB | approximateDownloadSize | defaultSteps | defaultGuidance |
   |---|---|---|---|---|---|---|---|
   | `klein4B` | `flux2-klein-4b` | `FLUX.2 Klein 4B` | `flux2` | 16 | `~11 GB` | 8 | 3.5 |
   | `pixartSigmaXL` | `pixart-sigma-xl` | `PixArt-Sigma XL` | `pixart-sigma` | 8 | `~3.6 GB` | 20 | 4.5 |

   Both use `AspectRatio.allCases`. `all` is `[klein4B, pixartSigmaXL]`.
3. In `Sources/SwiftVinetas/Engine/ModelDescriptor.swift`, add requirement
   `var summary: ModelSummary { get }` and a default implementation in the existing
   protocol extension, built from the descriptor's own eight fields.
4. Create `Tests/VinetasVocabularyTests/ModelSummaryTests.swift`: `Codable` round-trip
   for both statics, `all.count == 2`, `all` order, and the two ids.
5. Create `Tests/SwiftVinetasTests/ModelSummaryDriftTests.swift` asserting
   `Flux2ModelDescriptor.klein4B.summary == ModelSummary.klein4B` and
   `PixArtModelDescriptor.sigmaXL.summary == ModelSummary.pixartSigmaXL`.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with both new test files' suites passing in `build/test-output.log`.
- [ ] `git diff --stat <start> -- Sources/SwiftVinetas/Engine/Flux2Engine.swift Sources/SwiftVinetas/Engine/PixArtEngine.swift` is empty.
- [ ] `grep -n -i '9b' Sources/VinetasVocabulary/ModelSummary.swift` prints nothing.
- [ ] `grep -c 'requiresPro' Sources/VinetasVocabulary/ModelSummary.swift` prints `0`.
- [ ] `make build` exits 0.

### Sortie 3: `StoryboardStyle` arrives in the vocabulary

**Entry criteria**:
- [ ] Sortie 1 exit criteria met.
- [ ] `git -C ~/Projects/apps/Vinetas cat-file -e 0c25a3d^{commit}` exits 0.
- [ ] Recon facts in force: the source file imports Foundation only and uses no other app
      symbol; `swatchPalette` lives in `StylePickerListView.swift:228–276` as
      `(Color, Color, Color)` built from hex strings (V-05).

**Tasks**:
1. Create `Sources/VinetasVocabulary/StoryboardStyle.swift` from
   `Vinetas/Models/StoryboardStyle.swift` at `0c25a3d`. Mark the enum and its non-private
   members `public`. Change no case name, case order or string literal.
2. Create `Sources/VinetasVocabulary/StoryboardStyle+Swatch.swift` with
   `public struct SwatchRGB: Hashable, Sendable { red, green, blue: Double }` and
   `public var swatchPalette: (SwatchRGB, SwatchRGB, SwatchRGB)`, converting each hex
   string in the app's `swatchPalette` to components in `0...1`.
3. Copy `VinetasTests/Fixtures/storyboard-styles.json` byte-for-byte to
   `Tests/VinetasVocabularyTests/Fixtures/`, and add `resources: [.copy("Fixtures")]` to
   the test target.
4. Port `VinetasTests/StoryboardStyleTests.swift` (9 tests) and
   `StoryboardStyleCatalogTests.swift` (4 tests) to `Tests/VinetasVocabularyTests/`,
   importing `@testable import VinetasVocabulary` and loading the fixture through
   `Bundle.module`.
5. Create `Tests/VinetasVocabularyTests/StoryboardStyleFrozenTests.swift`: the twenty
   `rawValue`s as a literal array in declaration order, and every palette component
   re-encoded to six-digit hex equal to the app's source hex string.

**Exit criteria**:
- [ ] `diff <(git -C ~/Projects/apps/Vinetas show 0c25a3d:VinetasTests/Fixtures/storyboard-styles.json) Tests/VinetasVocabularyTests/Fixtures/storyboard-styles.json` prints nothing.
- [ ] `diff <(git -C ~/Projects/apps/Vinetas show 0c25a3d:Vinetas/Models/StoryboardStyle.swift | grep -o '"[^"]*"') <(grep -o '"[^"]*"' Sources/VinetasVocabulary/StoryboardStyle.swift)` prints nothing.
- [ ] `grep -h '^import' Sources/VinetasVocabulary/*.swift | sort -u` still prints exactly `import Foundation` and `import Metal`.
- [ ] `make test-unit` exits 0 with the three StoryboardStyle test files' suites passing in `build/test-output.log`.

---

## WU-2 UI

### Sortie 4: Scaffold the `VinetasUI` target, identifiers and string catalogue

**Entry criteria**:
- [ ] Sorties 1–3 exit criteria met.
- [ ] Unverified by recon (U-1): no package in this collection ships a string catalogue.
      This sortie proves that `Localizable.xcstrings` builds and resolves through
      `bundle: .module` under `xcodebuild` before any view depends on it. If it does not,
      report a plan defect.

**Tasks**:
1. In `Package.swift`: set `defaultLocalization: "en"`; add target `VinetasUI` with
   dependencies exactly `["VinetasVocabulary"]` and `resources: [.process("Resources")]`;
   add library product `VinetasUI`; add test target `VinetasUITests` depending on
   `VinetasUI` and `VinetasVocabulary`.
2. Create `Sources/VinetasUI/VinetasUIAccessibility.swift`, a `public enum` of
   `public static let` strings in the `AcervoUIAccessibility` style, with exactly these:

   | Constant | Value |
   |---|---|
   | `promptPrimary` | `prompt.primary` |
   | `promptCaption` | `prompt.caption` (new) |
   | `promptStylePicker` | `prompt.stylePicker` |
   | `promptStyleCustom` | `prompt.styleCustom` |
   | `promptNegativeToggle` | `prompt.negativeToggle` |
   | `promptNegative` | `prompt.negative` |
   | `stylePickerList` | `stylePicker.list` |
   | `stylePickerRowPrefix` | `stylePicker.row` |
   | `stylePickerPromptTextDisclosure` | `stylePicker.promptTextDisclosure` |
   | `generationModelPicker` | `generation.modelPicker` |
   | `generationAspectRatioSelection` | `generation.aspectRatioSelection` |
   | `generationAspectRatioTilePrefix` | `generation.aspectRatioTile` |
   | `generationAspectRatioUseDefault` | `generation.aspectRatioUseDefault` |
   | `generationStepsSlider` | `generation.stepsSlider` |
   | `generationStepsUseDefault` | `generation.stepsUseDefault` |
   | `generationGuidanceSlider` | `generation.guidanceSlider` |
   | `generationGuidanceUseDefault` | `generation.guidanceUseDefault` |
   | `generationSeedField` | `generation.seedField` |
   | `generationRandomizeSeed` | `generation.randomizeSeed` |
   | `generationMemoryWarning` | `generation.memoryWarning` |

3. Create `Sources/VinetasUI/Resources/Localizable.xcstrings` (source language `en`) with
   one seed key, and an internal helper that wraps `String(localized:bundle: .module)`.
4. Create `Tests/VinetasUITests/AccessibilityIdentifierTests.swift` asserting each
   constant equals its literal, and `LocalizationTests.swift` asserting the seed key
   resolves to its English value through the module bundle.
5. In the `Makefile`: add `-only-testing:VinetasUITests` to `test-unit` and
   `test-unit-ios`; add `build-ui` (scheme `VinetasUI`, macOS) and `build-ui-ios` (same
   scheme, `$(DESTINATION_IOS)`); make `build-ios` also build `VinetasUI`; add
   `verify-ui-isolation`, which builds scheme `VinetasUI` into a fresh derived-data
   directory and fails if any `*.build` directory under its `Intermediates.noindex` is
   named `Flux2Core`, `PixArtBackbone`, `Tuberia`, `TuberiaCatalog`, `MLX`, `Cmlx` or
   `SwiftAcervo`.

**Exit criteria**:
- [ ] `swift package dump-package | jq -c '[.targets[]|select(.name=="VinetasUI")|.dependencies[]|(.byName//.target//.product)[0]]'` prints `["VinetasVocabulary"]`.
- [ ] `grep -rn -E '^import (SwiftVinetas|Flux2Core|PixArtBackbone|Tuberia|TuberiaCatalog|SwiftAcervo|MLX)' Sources/VinetasUI Sources/VinetasVocabulary` prints nothing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `make verify-ui-isolation` exits 0.
- [ ] `make test-unit` exits 0 with both new suites passing.
- [ ] `make test-unit-ios` exits 0, so the resource bundle also resolves on iOS.

### Sortie 5: Layout resolver and environment override

**Entry criteria**:
- [ ] Sortie 4 exit criteria met.
- [ ] Shape to follow: SwiftEscribo `v0.4.2`,
      `Sources/SwiftEscribo/EscriboWell.swift:146–188`, read through
      `git -C ~/Projects/package-collection/pkg/SwiftEscribo show v0.4.2:<path>` (E-01).

**Tasks**:
1. Create `Sources/VinetasUI/VinetasPanelLayout.swift`:
   `public enum VinetasPanelLayout: Sendable, CaseIterable { case sidebar, regular, compact }`.
2. Add package-local `Platform` (`macOS`, `iOS`, with `static var current`) and
   `HorizontalSizeClass` (`compact`, `regular`) enums, and the pure function
   `VinetasPanelLayout.resolve(platform:horizontalSizeClass:)`: macOS gives `.sidebar`
   for any size class; iOS gives `.regular` at regular width and `.compact` at compact
   width or when the size class is unknown.
3. Add `EnvironmentValues.vinetasPanelLayout: VinetasPanelLayout?` (default `nil`) and
   `View.vinetasPanelLayout(_:)`.
4. Add an internal helper that returns the effective layout: the environment override
   when set, otherwise `resolve` on the current platform and size class.
5. Create `Tests/VinetasUITests/PanelLayoutTests.swift`: all six platform × size-class
   combinations (including `nil`), and override-beats-resolution for all three cases.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `PanelLayoutTests` suite passing.
- [ ] `make build-ui-ios` exits 0.
- [ ] `grep -c 'horizontalSizeClass: nil' Tests/VinetasUITests/PanelLayoutTests.swift` prints at least `2`.

### Sortie 6: Semantic palette and swatch views

**Entry criteria**:
- [ ] Sortie 4 exit criteria met.
- [ ] Source to port, at Vinetas `0c25a3d`:
      `Vinetas/Views/GenerationStudio/StylePickerListView.swift` lines 158–224
      (`StyleSwatchView`, `GradientSwatch`, `CustomSwatch`, `StylePalette`) and
      `Vinetas/Views/GenerationStudio/MidCenturySwatch.swift`.

**Tasks**:
1. Create `Sources/VinetasUI/VinetasPalette.swift` with eight semantic tokens. In dark
   appearance they resolve to the app's values: row background `0x2a2a2c`, row hover
   `0x323234`, border `0x38383a`, primary text `0xf5f5f7`, secondary text `0x8e8e93`,
   tertiary text `0x6a6a6e`, accent `0x0a84ff`, accent-soft `0x0a84ff` at 0.18 opacity.
   In light appearance they resolve to system fills, `.secondary`-class text and
   `Color.accentColor`. Expose the dark values through a pure function a test can read.
2. Add a `Color` initializer from `SwatchRGB`.
3. Port `StyleSwatchView`, `GradientSwatch` and `CustomSwatch`, reading colours from
   `StoryboardStyle.swatchPalette`.
4. Port `MidCenturySwatch` as the static drawing it is today.
5. Create `Tests/VinetasUITests/PaletteTests.swift`: each dark token equals its hex
   above; a swatch view can be constructed for all twenty styles.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `PaletteTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -rn 'TimelineView' Sources/VinetasUI` prints nothing.

### Sortie 7: The style list

**Entry criteria**:
- [ ] Sorties 5 and 6 exit criteria met.
- [ ] Source to port, at Vinetas `0c25a3d`:
      `Vinetas/Views/GenerationStudio/StylePickerListView.swift` lines 18–156
      (`StylePickerListView`, `StyleRowView`).

**Tasks**:
1. Create a pure selection model in `Sources/VinetasUI/StyleSelection.swift`: the row
   order (`StoryboardStyle.sortedPresets` then `.custom`), the mapping from a
   `promptText` binding value to the selected style, and the `customTag` sentinel for
   *Other*.
2. Create the list view in `Sources/VinetasUI/VinetasStyleList.swift`: 5.5 visible rows,
   each row a button with swatch, name, genre caption and a checkmark when selected,
   coloured from `VinetasPalette`.
3. Apply identifiers `stylePickerList` to the list and
   `"\(stylePickerRowPrefix).\(style.rawValue)"` to each row.
4. Move the list's strings (style count, *Other*, *Custom prompt*, accessibility labels)
   into the catalogue.
5. Create `Tests/VinetasUITests/StyleSelectionTests.swift`: row count is 20, a preset's
   `promptText` selects that preset, `customTag` and unknown text select `.custom`.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `StyleSelectionTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.

### Sortie 8: `VinetasStylePicker`, the popup

**Entry criteria**:
- [ ] Sortie 7 exit criteria met.
- [ ] `OQ-1` and `OQ-2` resolved. The tasks below assume their recommendations.

**Tasks**:
1. Create `Sources/VinetasUI/VinetasStylePicker.swift`:
   `public struct VinetasStylePicker: View` with `init(selection: Binding<String>)`.
2. Add `public enum VinetasStylePickerStyle: Sendable { case popup, list }`, an
   environment value defaulting to `.popup`, and `View.vinetasStylePickerStyle(_:)`.
   `.list` shows the Sortie 7 list inline.
3. Build the popup: a button identified `promptStylePicker` whose label shows the
   selected style's swatch, name and genre caption. It presents the Sortie 7 list in a
   popover when the effective layout is `.sidebar` or `.regular`, and in a sheet with
   medium and large detents when it is `.compact`.
4. Choosing a row sets the binding and dismisses. Choosing *Other* sets the binding to
   `customTag` and dismisses.
5. Add a pure function mapping layout to presentation (popover or sheet), and three
   `#Preview`s with the standard names and canvas sizes.
6. Create `Tests/VinetasUITests/StylePickerTests.swift`: the layout-to-presentation
   mapping for all three layouts, and the label's name and caption for one preset and
   for `.custom`.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `StylePickerTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -c '#Preview("' Sources/VinetasUI/VinetasStylePicker.swift` prints `3`.
- [ ] `grep -c -E '#Preview\("(Sidebar \(macOS\)|Regular \(iPad\)|Compact \(iPhone\))"' Sources/VinetasUI/VinetasStylePicker.swift` prints `3`.

### Sortie 9: `VinetasPromptPanel`

**Entry criteria**:
- [ ] Sortie 8 exit criteria met.
- [ ] Sources to merge, at Vinetas `0c25a3d`:
      `Vinetas/Views/GenerationStudio/PromptInputPanel.swift` (233 lines) and
      `VinetasIOS/Views/GenerationStudio/PromptInputPanel.swift` (303 lines).

**Tasks**:
1. Create `Sources/VinetasUI/VinetasPromptPanel.swift` with `prompt`, `stylePrompt` and
   `negativePrompt` bindings, `selectedModel: ModelSummary`, and
   `caption: Binding<String>? = nil`.
2. Merge the forks under `#if os`. macOS keeps the `DisclosureGroup` and `TextField`
   negative prompt, the `TextField` custom style, and the window-background outer fill.
   iOS keeps the toggle button and `TextEditor` negative prompt, the `TextEditor` custom
   style, `.scrollDismissesKeyboard(.interactively)`, and no outer fill.
3. Take the prompt editor's minimum height from a pure function of layout: 100 for
   `.sidebar`, 140 for `.regular`, 100 for `.compact`.
4. Embed `VinetasStylePicker`; show the custom-style field when the selection is
   `customTag`; keep the style prompt-text disclosure, identified
   `stylePickerPromptTextDisclosure`.
5. Derive the engine badge and the prompt hints from `selectedModel.engineID` through a
   pure function. When `caption` is non-nil, show a single-line field under the prompt
   identified `promptCaption`.
6. Move every string into the catalogue and add three `#Preview`s.
7. Create `Tests/VinetasUITests/PromptPanelTests.swift`: the minimum height for each
   layout, and the hint text for `flux2` and `pixart-sigma`.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `PromptPanelTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -c '#Preview("' Sources/VinetasUI/VinetasPromptPanel.swift` prints `3`.
- [ ] `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.
- [ ] [judgment] Every string literal the diff passes to `Text`, `TextField`, `Toggle`, `Button`, `Label`, `.accessibilityLabel`, `.accessibilityHint` or `.help` is resolved through the module bundle, and its key exists in `Localizable.xcstrings`.

### Sortie 10: `VinetasGenerationSettingsPanel`

**Entry criteria**:
- [ ] Sorties 5 and 6 exit criteria met.
- [ ] Sources to merge, at Vinetas `0c25a3d`:
      `Vinetas/Views/GenerationStudio/GenerationSettingsPanel.swift` (329 lines) and
      `VinetasIOS/Views/GenerationStudio/GenerationSettingsPanel.swift` (351 lines).

**Tasks**:
1. Create `Sources/VinetasUI/VinetasGenerationSettingsPanel.swift` with
   `models: [ModelSummary]`; bindings for `selectedModel`, `aspectRatio`, `steps`,
   `guidance`, `seed` and `randomizeSeed`; optional bindings `useDefaultSteps`,
   `useDefaultGuidance` and `useDefaultAspectRatio` defaulting to `nil`; and a
   `@ViewBuilder footnote` slot rendered under the model picker.
2. Build the model picker from a pure grouping function (sections by `engineID`, input
   order kept), each row showing download size and RAM, identified
   `generationModelPicker`.
3. Keep one `AspectRatioTile` and one internal `ratioLabel`, with the macOS metrics
   (36 pt in 48 × 60) and iOS metrics (40 pt in 52 × 64) each on its own platform. The
   tiles stay a horizontal scrolling strip in every layout.
4. Build Steps (1…50, step 1) and Guidance (1.0…20.0, step 0.5): side by side in
   `.regular`, stacked in `.sidebar` and `.compact`. Render a Default toggle only when
   its binding is non-nil; when it is on, dim and disable the control. Add no reset
   logic.
5. Build the seed field and Randomize toggle; use the number pad on iOS.
6. Move every string into the catalogue and add three `#Preview`s.
7. Create `Tests/VinetasUITests/SettingsPanelTests.swift`: grouping of
   `ModelSummary.all` gives two sections in FLUX.2-then-PixArt order, and the size-and-RAM
   subtitle text for one model.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `SettingsPanelTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -c '#Preview("' Sources/VinetasUI/VinetasGenerationSettingsPanel.swift` prints `3`.
- [ ] `grep -n 'onChange(of: selectedModel' Sources/VinetasUI/VinetasGenerationSettingsPanel.swift` prints nothing.
- [ ] `grep -rn -i -E 'isProActive|requiresPro|MemoryValidator|physicalMemory' Sources/VinetasUI` prints nothing.
- [ ] [judgment] Every string literal the diff passes to `Text`, `TextField`, `Toggle`, `Button`, `Label`, `Section`, `.accessibilityLabel`, `.accessibilityHint` or `.help` is resolved through the module bundle, and its key exists in `Localizable.xcstrings`.

### Sortie 11: `VinetasPromptDraft` and `VinetasPromptComposer`

**Entry criteria**:
- [ ] Sorties 9 and 10 exit criteria met.

**Tasks**:
1. Create `Sources/VinetasUI/VinetasPromptDraft.swift` with the struct from requirements
   § 2.3 and a public memberwise initializer.
2. Create pure binding adapters from the draft to the three views: steps and guidance
   show the draft value or, when it is `nil`, the selected model's default; turning a
   Default toggle on stores `nil`, turning it off stores the model's default; Randomize
   on stores `seed = nil`; the selected model is looked up by `modelID` in `models`,
   falling back to the first model when the id is unknown.
3. Create `Sources/VinetasUI/VinetasPromptComposer.swift`:
   `init(draft:models:showsCaption:)`, the three views stacked in a scroll view. An
   explicit steps or guidance value is kept when the model changes.
4. Add three `#Preview`s.
5. Create `Tests/VinetasUITests/PromptDraftTests.swift`: `Codable` round-trip with and
   without `nil` fields; each adapter rule in task 2; the composer can be placed in an
   `NSHostingView` or `UIHostingController` without a window.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `PromptDraftTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -c '#Preview("' Sources/VinetasUI/VinetasPromptComposer.swift` prints `3`.

### Sortie 12: The popup presentation

**Entry criteria**:
- [ ] Sortie 11 exit criteria met.
- [ ] `OQ-1` and `OQ-3` resolved. The tasks below assume their recommendations.

**Tasks**:
1. Create `Sources/VinetasUI/VinetasPromptPopup.swift` with
   `View.vinetasPromptPopup(isPresented:draft:models:showsCaption:actions:)`, where
   `actions` is a `@ViewBuilder` row the host fills. The package draws no Generate
   button.
2. Add a pure function mapping layout to presentation: popover for `.sidebar` and
   `.regular`, sheet for `.compact`.
3. Build the popup content: the composer in a scroll view with the action row pinned
   below it. Reference sizes: 340 pt ideal width on macOS (300 minimum, 420 maximum),
   480 pt ideal width on iPad, medium and large detents with a drag indicator on iPhone.
   Inside the popup the panels draw no outer fill.
4. Add three `#Preview`s of the popup content named `"Popup (macOS)"`, `"Popup (iPad)"`
   and `"Popup (iPhone)"`.
5. Create `Tests/VinetasUITests/PromptPopupTests.swift`: the layout-to-presentation
   mapping for all three layouts, and the popup content can be placed in a hosting view
   without a window.

**Exit criteria**:
- [ ] `make test-unit` exits 0 with the `PromptPopupTests` suite passing.
- [ ] `make build-ui` and `make build-ui-ios` exit 0.
- [ ] `grep -rh '#Preview("' Sources/VinetasUI | wc -l` prints `15`.
- [ ] `make verify-ui-isolation` exits 0.
- [ ] `make test-unit-ios` exits 0.

---

## WU-3 Release readiness

### Sortie 13: CI gates for lint, iOS and isolation

**Entry criteria**:
- [ ] Sortie 12 exit criteria met.
- [ ] Recon facts in force: `tests.yml` has one job on `macos-26` running `make build`
      then `make test-unit`; `make lint` rewrites in place (R-11, R-12).
- [ ] Unverified by recon (U-2): whether the `macos-26` runner has a simulator matching
      the iOS destination. This cannot be settled until the workflow first runs on a
      pull request; record it in the sortie report as open.

**Tasks**:
1. In the `Makefile`, change `DESTINATION_IOS` to a `?=` assignment so CI can override
   it, and add `lint-check`, which runs `make lint` and then `git diff --exit-code`.
2. In `.github/workflows/tests.yml`, add `make lint-check` as the first step after
   checkout in the existing job, and `make verify-ui-isolation` after `make test-unit`.
3. Add a second job, `unit-tests-ios`, on `macos-26`, running `make test-unit-ios` with
   `DESTINATION_IOS='platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
4. Fix the one existing `swift-format` lint diagnostic (`ReplaceForEachWithForLoop`) if
   `make lint` does not already rewrite it.

**Exit criteria**:
- [ ] `make lint-check` exits 0 on a clean tree.
- [ ] `ruby -ryaml -e 'YAML.load_file(".github/workflows/tests.yml")'` exits 0.
- [ ] `grep -c 'runs-on: macos-26' .github/workflows/tests.yml` prints `2`.
- [ ] In `tests.yml`, the line containing `make lint-check` comes before the line containing `make build`.
- [ ] `grep -c "name=iPhone 17,OS=26.5" .github/workflows/tests.yml` prints `1`.
- [ ] `make test-unit` and `make verify-ui-isolation` exit 0.

### Sortie 14: Products documentation and integration guide

**Entry criteria**:
- [ ] Sortie 12 exit criteria met.

**Tasks**:
1. Add a *Products* table to `AGENTS.md` and to `README.md` with one row each for
   `SwiftVinetas`, `VinetasCLICore`, `vinetas`, `VinetasVocabulary` and `VinetasUI`,
   stating what each links.
2. Create `docs/VINETAS_UI.md`, the integration guide for another program: link
   `VinetasUI` only; the three ways in (the popup modifier, the composer, the three
   views); the layout override; the style-picker style; what the host owns (filtering
   models, resetting on model change, the footnote, generation).
3. Add the new Makefile targets (`build-ui`, `build-ui-ios`, `verify-ui-isolation`,
   `lint-check`) to the build list in `CLAUDE.md` and `AGENTS.md`.
4. Add a note to `docs/VINETAS_UI.md` for step 2: the app's `ratioLabel` extension and
   `storyboard-styles.json` export script now have package counterparts.

**Exit criteria**:
- [ ] In both `AGENTS.md` and `README.md`, a section headed *Products* contains a table whose first column holds exactly these five names, one per row: `SwiftVinetas`, `VinetasCLICore`, `vinetas`, `VinetasVocabulary`, `VinetasUI`.
- [ ] `test -f docs/VINETAS_UI.md` exits 0, and `grep -c -E 'vinetasPromptPopup|VinetasPromptComposer|vinetasPanelLayout|vinetasStylePickerStyle' docs/VINETAS_UI.md` prints at least `4`.
- [ ] `swift package dump-package | jq -c '[.products[].name]|sort'` prints `["SwiftVinetas","VinetasCLICore","VinetasUI","VinetasVocabulary","vinetas"]`.
- [ ] `git diff --stat <start> -- Sources/VinetasCLICore Sources/vinetas Tests/SwiftVinetasGPUTests` is empty.
- [ ] `git diff <start> -- Sources/SwiftVinetas/Vinetas.swift` is empty (version literals untouched).
- [ ] `make build` exits 0 and `make lint-check` exits 0.

---

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

`Package.resolved` is gitignored. On this machine every `intrusive-memory` dependency
resolves to its sibling directory, ahead of its release tag; CI resolves the newest
release in range. The two new targets depend on none of these.

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| intrusive-memory/flux-2-swift-mlx | sibling path; 1 commit past `v3.4.3` (`9a36b2635eb0`) | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | sibling path; 4 past `v0.25.0` (`13e2879b165d`) | `~/Projects/package-collection/pkg/SwiftAcervo` | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | sibling path; 1 past `v0.9.0` (`d74977ac96b4`) | `~/Projects/package-collection/pkg/SwiftTuberia` | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | sibling path; 1 past `v0.8.2` (`3ce254137d17`) | `~/Projects/package-collection/pkg/pixart-swift-mlx` | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/glosa-av | sibling path; 1 past `v0.8.1` (`efb640ff0f8c`) | `~/Projects/package-collection/pkg/glosa-av` | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | sibling path; 19 past `v7.2.5` (`baf830a930f9`) | `~/Projects/package-collection/pkg/SwiftCompartido` | SIBLING_ACTIVE, LOCAL_AHEAD |
| marcprux/universal | `5.3.0` (`7919463ce636`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `1.8.2` (`6a52f3251125`) | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `0.7.1` (`e4e01cb59fb7`) | `~/Projects/swift-tokenizers` | LOCAL_BEHIND |
| apple/swift-certificates | `1.19.4` (`449dbbecd0f3`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-crypto | `3.15.1` (`95ba0316a9b7`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-asn1 | `1.7.1` (`a9a5efd40eaf`) | — | NO_LOCAL_CHECKOUT |

Source repositories the sorties read but do not depend on:

| Repository | Path | Revision to read | Used by |
|---|---|---|---|
| intrusive-memory/Vinetas | `~/Projects/apps/Vinetas` | `0c25a3d` | Sorties 3, 6, 7, 9, 10 |
| intrusive-memory/SwiftEscribo | `~/Projects/package-collection/pkg/SwiftEscribo` | tag `v0.4.2` | Sortie 5 |
| intrusive-memory/SwiftAcervo | `~/Projects/package-collection/pkg/SwiftAcervo` | tag `v0.25.0` | Sortie 4 (identifier-enum style) |

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). Each entry MUST be resolved before refinement can proceed past Pass 1. -->

### OQ-1: What "the popup metaphor" covers
**Affects**: Sortie 8, Sortie 12
**Question**: Does the direction mean the style picker becomes a popup, the whole panel is presented as a popup, or both?
**Source**: User direction, 2026-10-06; supersedes requirements § 2.2 (line 199) and § 2.3 (lines 236–243).
**Why blocking**: Under the first reading Sortie 12 is not wanted; under the second, Sortie 8's default should be the inline list.
**Recommendation**: Both, as planned. The style picker is a popup by default with the inline list as an opt-in style, and `vinetasPromptPopup` presents the whole composer.
**Rationale**: A 5.5-row list does not fit a popover or an iPhone sheet, so the two readings need each other; and "portable to add to any other program" is best served by a one-line presentation modifier. Keeping the list as an opt-in style lets Vinetas choose in step 2 without a package change.

### OQ-2: How the style popup is built
**Affects**: Sortie 8
**Question**: Is the style popup a SwiftUI `Menu`, as requirements § 2.3 words it, or a button that opens the existing list in a popover (a sheet on iPhone)?
**Source**: Requirements § 2.3, lines 236–243; implied by Sortie 8 tasks.
**Why blocking**: The two need different code, different tests and different identifiers on the rows.
**Recommendation**: A button that opens the existing list in a popover, or a sheet at compact width.
**Rationale**: `Menu` rows render only a title and a small image on both platforms, so the gradient swatches and genre captions would be lost or need rasterizing. The popover reuses the list rows as they are and keeps the `stylePicker.list` and `stylePicker.row.<rawValue>` identifiers, so a UI test only gains one tap on `prompt.stylePicker`.

### OQ-3: What form the reference layouts take
**Affects**: Sortie 8, Sortie 9, Sortie 10, Sortie 11, Sortie 12
**Question**: Are the reference layouts for iPad, iPhone and Mac the named `#Preview`s, or also something reviewable outside Xcode (committed images, or a small gallery app)?
**Source**: User direction, 2026-10-06; requirements § 2.2 (lines 220–225), Acceptance 2; recon T-03 and U-3.
**Why blocking**: Exit criteria can count previews, but no sortie can verify that they render; committed images or a gallery app would be an extra sortie.
**Recommendation**: The fifteen named previews at the reference canvas sizes, plus one manual look by the user after Sortie 12 and before Work Unit 3.
**Rationale**: The requirements already define the previews as "the package's own display of the panel"; the package has no app target to screenshot, and `ImageRenderer` does not draw platform controls such as sliders and text editors, so automated images would misrepresent the panel.

## Summary

| Metric | Value |
|--------|-------|
| Work units | 3 |
| Total sorties | 14 |
| Open questions | 3 |
| Dependencies mapped | 12 |
| Dependency structure | layers |

---
type: project
title: SwiftVinetas — VinetasUI, the prompt panel as a reusable inspector element
updated: 2026-10-18
state: draft
supersedes: docs/REQUIREMENTS-vinetas-ui.md (2026-10-05) and the "popup metaphor" direction of 2026-10-06
design: https://claude.ai/artifact/1JSXFojxUWxYWo9dTyztSX
---

# SwiftVinetas — `VinetasUI`, the prompt panel as a reusable inspector element

The Vinetas app's Generation Studio sidebar — prompt, style list, negative prompt, model,
aspect ratio, steps, guidance, seed — is the best description of an image anyone in this
collection has written, and it is locked inside one app target, twice. This mission moves
it into SwiftVinetas as a SwiftUI product, `VinetasUI`, that **links no inference stack**,
shapes it as a **right-hand inspector pane** on macOS and iPad and a **pushed screen** on
iPhone, documents how a host adopts it, and ships it as SwiftVinetas 0.22.0.

The first host is Escribir, which uses the element to compose a **storyboard prompt** and
save it into a `.fountain` file as a GLOSA `<shot …/>` note. Escribir's side is
`Escribir/docs/REQUIREMENTS-storyboard.md` and is not this mission. What this mission
owes Escribir is a value type it can serialize, a pane it can place, and a guide that
says how.

**Design spec:** the canvas *VinetasUI Prompt Panel* —
<https://claude.ai/artifact/1JSXFojxUWxYWo9dTyztSX>. The artboards that bind are
**"macOS · Right-hand inspector panel"** and the three **iPhone** artboards (host screen,
pushed Image Prompt screen, pushed Style list). The two sheet artboards were the rejected
alternative and are kept on the canvas for the record. Where the canvas and this document
disagree, **the canvas wins** and this document is amended to match.

This document is the requirements input for the mission supervisor's breakdown. The
untracked `EXECUTION_PLAN.md` and `RECON_REPORT.md` in this repo were written against the
2026-10-05 version and the popup direction; the recon's factual corrections are absorbed
below, and the plan is to be regenerated from this document.

## What exists today (validated 2026-10-06)

Against SwiftVinetas `development` at `d88dd27` (0.21.0-dev), Vinetas `0c25a3d`, Escribir
`ccc2ef5` (no SwiftVinetas dependency), glosa-av `0.8.1-dev`, SwiftAcervo 0.25.0 as the
precedent. Every finding below was checked against the files it names; nine of the
previous document's premises did not hold and are corrected here.

**The panel is seven files, in the app, and the two platforms have diverged.** macOS:
`Vinetas/Views/GenerationStudio/PromptInputPanel.swift` (233 lines),
`StylePickerListView.swift` (294, including the swatch view and the `StylePalette`
tokens, and the `swatchPalette` extension), `MidCenturySwatch.swift` (191, a static
`Canvas`), `GenerationSettingsPanel.swift` (329, including `AspectRatioTile`). iOS:
`VinetasIOS/Views/GenerationStudio/PromptInputPanel.swift` (303) and
`GenerationSettingsPanel.swift` (351). **iOS uses the same vertical style list macOS
does** — there is no popup picker on any platform, and `prompt.stylePicker` is a constant
no view references. The iOS forks differ from macOS in: size-class layouts (Steps and
Guidance side by side at regular width; 140 pt prompt editor at regular, 100 at compact),
`.scrollDismissesKeyboard(.interactively)`, `String(localized:)` wrappers, a toggle
button plus `TextEditor` for the negative prompt (macOS: `DisclosureGroup` plus
`TextField`), a `TextEditor` for the custom style, `.numberPad` on the seed field, no
outer background fill, and **no "Default" toggles at all** — the iOS settings panel resets
steps and guidance inside the view in `.onChange(of: selectedModel)`. The macOS panel
owns three `useDefault…` bindings and leaves the reset to `GenerationViewModel`. Aspect
tiles are a horizontal `ScrollView` at every size class; nothing wraps. The data behind
them is `Vinetas/Models/StoryboardStyle.swift` (19 presets + `.custom`, each with
`displayName`, `genre`, `promptText`, `negativePromptText`) and
`Vinetas/Models/AvailableModel.swift` (two models, projecting the descriptors below).

**The vocabulary is nearly engine-free, with two exceptions.** In
`Sources/SwiftVinetas/Core/`, `AspectRatio`, `StyleConfig`, `VinetasError` and
`VinetasModelInfo` import Foundation only. `ResolutionClamp.swift` imports **Metal**
conditionally (`MTLCreateSystemDefaultDevice().maxBufferLength` at lines 71–72), and
`AspectRatio.swift:105` calls it, so the two move together. `ModelDescriptor` (the
protocol, `Engine/ModelDescriptor.swift`) imports Foundation only and already requires
all eight fields `ModelSummary` needs, with matching names and types. The conforming
statics — `Flux2ModelDescriptor.klein4B` in `Engine/Flux2Engine.swift:35` and
`PixArtModelDescriptor.sigmaXL` in `Engine/PixArtEngine.swift:39` — are the values:

| Static | id | displayName | engineID | RAM | Download | Steps | Guidance | CLI name |
|---|---|---|---|---|---|---|---|---|
| `Flux2ModelDescriptor.klein4B` | `flux2-klein-4b` | FLUX.2 Klein 4B | `flux2` | 16 | `~11 GB` | 8 | 3.5 | `klein4b` |
| `PixArtModelDescriptor.sigmaXL` | `pixart-sigma-xl` | PixArt-Sigma XL | `pixart-sigma` | 8 | `~3.6 GB` | 20 | 4.5 | `pixart-sigma` |

Both list `AspectRatio.allCases`. The **CLI name** column is the vocabulary the `vinetas`
executable and the GLOSA `<shot model="…">` attribute use
(`VinetasModel` in `Sources/SwiftVinetas/Vinetas.swift:1753`, cases `klein4b` and
`pixartSigma = "pixart-sigma"`; the enum is `@available(*, deprecated)` at `:1749–1751`, and
the CLI still resolves `--model` through `VinetasModel(rawValue:)` at six sites in
`Sources/VinetasCLICore/VinetasCLICore.swift`, the help string being `:63`); it exists
nowhere as a field on the descriptor today. A host writing a `<shot>` needs it.

**The single `SwiftVinetas` target links everything.** Its dependencies are `Flux2Core`,
`SwiftAcervo`, `Tuberia`, `TuberiaCatalog`, `PixArtBackbone`, `YAML`, `JSON`. There is no
engine-free target to depend on; any product that imports `SwiftVinetas` imports MLX.
The package contains **no SwiftUI**, no `.xcstrings`, no `Resources/`, and no
`defaultLocalization`.

**The precedent is one package over.** SwiftAcervo ships `SwiftAcervo` and
`SwiftAcervoUI` from one `Package.swift`, with a public `AcervoUIAccessibility` enum of
identifier constants. It has no string catalogue. This mission does the same shape, with
one difference: the UI product must **not** depend on the core product (§ 2.1).

**The accessibility identifiers are load-bearing.** `Vinetas/AccessibilityID.swift` is
mirrored into `VinetasUITests/` and `VinetasIOSUITests/` (not verbatim: the copies differ
in imports and forwarded constants). Five UI-test files drive the panel through nineteen
strings (`VinetasUITests/{VinetasUITests,MemoryGatingUITests,ScreenshotUITests}.swift`,
`VinetasIOSUITests/{GenerationIntegrationTests,VinetasIOSUITests}.swift`; only
`VinetasIOSUITests.swift:275` asserts the inline `stylePicker.list`): `prompt.primary`, `stylePicker.list`, `stylePicker.row.<rawValue>`,
`stylePicker.promptTextDisclosure` (a raw literal in both panels), `prompt.stylePicker`,
`prompt.styleCustom`, `prompt.negativeToggle`, `prompt.negative`,
`generation.modelPicker`, `generation.aspectRatioSelection`,
`generation.aspectRatioTile.<rawValue>`, `generation.stepsSlider`,
`generation.stepsUseDefault`, `generation.guidanceSlider`,
`generation.guidanceUseDefault`, `generation.aspectRatioUseDefault`,
`generation.seedField`, `generation.randomizeSeed`, `generation.memoryWarning`. Every
one of those strings is a contract.

**Two things are persisted, and both are frozen.** `AppDefaults.swift:72–73` stores the
default style's **`promptText`**, recovered with `StoryboardStyle.from(promptText:)`;
`rawValue` feeds the `stylePicker.row.<rawValue>` identifiers and the exported catalogue
fixture (`VinetasTests/Fixtures/storyboard-styles.json`, guarded by
`StoryboardStyleCatalogTests`, exported by `Scripts/sync-storyboard-styles.sh` to the
`vinetas-skills` repo). No case may be renamed, reordered, added or removed, and no
`promptText` or `negativePromptText` may change by a byte.

**The style list is dark-only by construction.** `StylePalette` is eight hardcoded
colours (`0x2a2a2c` row, `0x32…` hover, `0x38…` border, `0xf5f5f7` text, `0x8e8e93` and
`0x6a6a6e` secondary, `0x0a84ff` accent at 1.0 and 0.18). The rest of the studio reads
`Color(nsColor: .windowBackgroundColor)` / `Color(.secondarySystemBackground)`. In light
appearance the style list is a dark island.

**The Mid-Century swatch is static.** `MidCenturySwatch.swift:11–19` records that the
`TimelineView(.animation)` redraw starved MLX of GPU time and was removed; every draw call
passes `t: 0`. It moves as it is; the animation is not reintroduced.

**Previews cannot pin a device.** `PreviewTrait` in the SDK offers `fixedLayout(width:
height:)` and orientations only; `.previewDevice(_:)` is deprecated in the 27 SDK. The
reference layouts are therefore fixed-size canvases that force a layout through the
environment (§ 2.2).

**CI runs neither lint nor an iOS job.** `.github/workflows/tests.yml` has one job,
"Unit Tests (macOS)" on `macos-26`, running `make build` then `make test-unit`. `make
lint` is `swift format -i -r .` and cannot fail. `make test-unit` and `make test-unit-ios`
both pass `-only-testing:SwiftVinetasTests`, so a new test target does not run until the
Makefile names it. The local toolchain is Xcode 27 / Swift 6.4; CI is `macos-26`, and CI
is the truth for the UI target: no API introduced after the OS 26 SDKs.

**Release mechanics.** `VinetasClient.version` and `Vinetas.version` are literal
`"0.21.0-dev"` strings in `Vinetas.swift` (lines 48 and 1125), also in `AGENTS.md:8`
(`README.md` carries none: its `:42` is a consumer pin and `:235` a release note). `Package.swift` on `development` carries the `sibling(…)` helper; a
release tag ships a remote-only manifest (`toggle-sibling-libraries`,
`ship-swift-library`). Escribir's `.xcodeproj` resolves packages by **remote tag only**,
so the host cannot begin until this is tagged.

## Scope

- **§ 1 `VinetasVocabulary`** — a new engine-free target: the names, numbers and
  presets a prompt UI needs, with no engine behind them.
- **§ 2 `VinetasUI`** — a new SwiftUI target and product, depending on § 1 only: the
  three panels, one composite, one draft value, one inspector presentation, one
  accessibility namespace, one string catalogue, three reference layouts.
- **§ 3 The host guide** — how a program adopts the element, written in the package
  and kept true by the package's own tests.
- **§ 4 SwiftVinetas 0.22.0** — the release, source-compatible for every existing
  consumer, with the CI gates the release needs.

Out of this mission, sequenced after it: Vinetas adopting 0.22.0 and deleting its copies
(a Vinetas mission), and Escribir's storyboard panel (`Escribir/docs/
REQUIREMENTS-storyboard.md`). Both wait on the tag from § 4.

## 1. `VinetasVocabulary`

### 1.1 What moves in

From `Sources/SwiftVinetas/Core/`, **moved** (not copied), with their tests:
`AspectRatio.swift`, `ResolutionClamp.swift`, `StyleConfig.swift`. `ResolutionClamp`
keeps its conditional `import Metal`: the rule for this target is **Apple system
frameworks only, no package dependencies**, not "Foundation only" (D-9). The two
internal members its tests reach (`attentionHeadsWorstCase`, `scoreBytes`) stay internal;
the tests move with the types and switch to `@testable import VinetasVocabulary`.

From the Vinetas app, **moved**: `StoryboardStyle` — the enum, `displayName`, `genre`,
`caption`, `promptText`, `baseNegative`, `styleSpecificNegative`, `negativePromptText`,
`customTag`, `sortedPresets`, `from(promptText:)` — made `public`, with the
`swatchPalette` **restated as three `(red, green, blue)` triples of `Double`** in a
`StyleSwatchPalette` value, not `SwiftUI.Color`. `VinetasUI` turns triples into colours.
The `StoryboardStyleTests` and `StoryboardStyleCatalogTests` in `VinetasTests/` move to
`VinetasVocabularyTests` with the catalogue fixture, and keep passing. A new test pins all
twenty `rawValue`s and all twenty `promptText`s and `negativePromptText`s byte for byte
against a committed fixture, so a drift fails in the package (D-10). The home of
`Scripts/sync-storyboard-styles.sh` is a Vinetas-adoption question and is recorded here
so it is not lost.

### 1.2 What is new: `ModelSummary`

```swift
public struct ModelSummary: Hashable, Sendable, Identifiable, Codable {
  public let id: String                 // "flux2-klein-4b", "pixart-sigma-xl"
  public let displayName: String        // "FLUX.2 Klein 4B"
  public let engineID: String           // "flux2", "pixart-sigma"
  public let cliName: String            // "klein4b", "pixart-sigma" — the GLOSA/CLI vocabulary
  public let minimumMemoryGB: Int       // display text only; never a gate
  public let approximateDownloadSize: String
  public let defaultSteps: Int
  public let defaultGuidance: Float
  public let supportedAspectRatios: [AspectRatio]

  public static let klein4B: ModelSummary
  public static let pixartSigmaXL: ModelSummary
  public static let all: [ModelSummary]            // display order: FLUX.2 first, then PixArt
  public static func named(cli name: String) -> ModelSummary?   // inverse of cliName
}
```

This is `AvailableModel`'s display projection, promoted to the package, with the engine
left behind and one addition: **`cliName`**, so a host can write `<shot model="…">` and
read it back without a mapping table of its own. It carries **no** `requiresPro`: Pro is a
Vinetas-app business rule (`engineID == "flux2"`), and Escribir sells nothing. Hosts
filter the list; the picker shows what it is given (§ 2.3). Exactly two models; Klein 9B
is out of scope and is not listed, planned or mentioned (standing directive).

**The summary cannot drift from the descriptor.** `ModelDescriptor` gains
`var summary: ModelSummary { get }` with a default implementation built from its own
fields plus a `cliName` requirement, and `SwiftVinetasTests` asserts
`Flux2ModelDescriptor.klein4B.summary == ModelSummary.klein4B` and the same for PixArt,
and that each `summary.cliName` is one of `VinetasModel.allCases.map(\.rawValue)` (the
enum is deprecated — the test silences that one warning locally rather than dropping the
round-trip). A descriptor edit
that forgets the summary fails the package's own unit tests, not an app's.

### 1.3 Compatibility

`SwiftVinetas` depends on `VinetasVocabulary` and re-exports it
(`@_exported import VinetasVocabulary` in one file, documented as the compatibility
shim). Every type that moved keeps its name and module-qualified spelling for a
consumer that writes `import SwiftVinetas` — the CLI, the GPU tests, Vinetas today —
so **no existing source changes to compile against 0.22.0**. That is what makes this a
minor release and not a major one.

## 2. `VinetasUI`

### 2.1 The dependency rule

`VinetasUI` depends on `VinetasVocabulary`, SwiftUI and platform frameworks. **It does
not depend on `SwiftVinetas`, and it imports no package product.** A consumer that links
only the `VinetasUI` product must end up with no `Flux2Core`, `PixArtBackbone`,
`Tuberia`, `MLX` or `SwiftAcervo` symbol in its binary. The package proves this itself:
`make verify-ui-isolation` builds a throwaway executable that imports only `VinetasUI`,
and fails if `otool -L` / `nm` on the product show any of those five names or if the
build log compiles any of those targets. Package resolution will still *clone* those
repositories — SwiftPM resolves the manifest's full dependency graph — and that cost is
named in § The honest list rather than hidden.

### 2.2 One source, three layouts

One set of source files, `#if os(macOS)` / `#if os(iOS)` only where the API genuinely
differs (`Color(nsColor:)` / `Color(.secondarySystemBackground)`,
`.toggleStyle(.checkbox)` is macOS-only, `.keyboardType(.numberPad)` is iOS-only). The
package builds for `.macOS(.v26)` and `.iOS(.v26)`, and those two platforms are **three
displays**:

| Layout | Where it is the default | What it is (per the canvas) |
|---|---|---|
| `.sidebar` | macOS; iPad as an inspector column | **The inspector column.** 340 pt ideal width (300 min, 420 max), single column in the app's order: Prompt with engine badge and hint, Caption when asked for, Style popup button, *Prompt text* disclosure, Negative Prompt disclosure (collapsed until a preset is chosen), Model picker with size and RAM, Aspect Ratio tiles in one horizontal strip with Default, Steps and Guidance sliders each with value and Default, Seed with Randomize. No outer fill: the host's pane supplies the background. |
| `.regular` | iOS, `horizontalSizeClass == .regular` and **not** inside an inspector | Today's iPad fork: Steps and Guidance **side by side**, prompt editor 140 pt minimum, `.scrollDismissesKeyboard(.interactively)`. Style is the same popup button and popover as `.sidebar`. |
| `.compact` | iOS, `horizontalSizeClass == .compact` | **The pushed screen** from the canvas: an inset-grouped form — Prompt and Caption in one group with the engine badge on the header, Style as a **chevron row** that pushes the style list, Negative Prompt expanded under its own header, Model as an inline menu row with size and RAM in the footer, Aspect Ratio tiles **wrapping** with a Default switch row, Steps and Guidance each as a cell with value and a Default switch, Seed with a Randomize switch. Prompt editor 100 pt minimum, keyboard dismissal on scroll. The host owns the navigation bar and its trailing action (§ 2.6). |

```swift
public enum VinetasPanelLayout: Sendable, CaseIterable { case sidebar, regular, compact
  /// Pure. `platform` is the package's own enum; `horizontalSizeClass` is nil on macOS.
  public static func resolve(platform: VinetasPlatform, horizontalSizeClass: VinetasSizeClass?) -> VinetasPanelLayout
}
extension EnvironmentValues {
  /// nil = resolve from platform and size class; a host sets it to force one.
  public var vinetasPanelLayout: VinetasPanelLayout?
}
extension View { public func vinetasPanelLayout(_ layout: VinetasPanelLayout?) -> some View }
```

The resolution is a **pure function**, tested for every platform × size-class
combination in the shape SwiftEscribo's `WellLane.width(on:horizontalSizeClass:)` uses.
The inspector presentation (§ 2.6) sets `.sidebar` explicitly, so an iPad inspector never
gets the side-by-side `.regular` sliders in a 340 pt column by accident.

**Every layout is displayed.** Each public view, and the composer, carries a `#Preview`
per layout — `"Sidebar (macOS)"`, `"Regular (iPad)"`, `"Compact (iPhone)"` — forcing
its layout through `.vinetasPanelLayout(…)` and sized with
`traits: .fixedLayout(width:height:)` at the reference canvas sizes **340 × 760** (Mac),
**1032 × 1376** (iPad) and **402 × 874** (iPhone 17). Those previews are the package's
own display of the panel on every supported platform, reviewable without an app, and
§ Acceptance 2 counts them.

### 2.3 The views

Three views, the same three the app has, with the same bindings — proven shapes, merged
from the two forks:

- **`VinetasPromptPanel`** — `prompt`, `stylePrompt`, `negativePrompt` bindings;
  `selectedModel: ModelSummary` for the engine badge and hints; **plus** an optional
  `caption: Binding<String>?` that, when non-nil, shows a single-line *Caption* field
  under the prompt, identified `prompt.caption` (Escribir needs it for `<shot caption>`;
  Vinetas passes `nil` and sees no change). Picking a preset replaces the negative
  prompt with that style's `negativePromptText` and reveals the Negative Prompt section,
  as the app does today.
- **`VinetasStylePicker`** — `selection: Binding<String>` over `promptText`, the
  `customTag` sentinel for *Other*. Its form follows the layout: in `.sidebar` and
  `.regular` it is a **button** (identified `prompt.stylePicker`) showing the selected
  style's swatch, name and genre caption, which opens **`VinetasStyleList`** in a
  popover; in `.compact` it is a **navigation row** with the same label and a chevron,
  which pushes `VinetasStyleList` onto the host's `NavigationStack`. A host that has no
  `NavigationStack` at compact width gets the popover form, so the row never dead-ends.
  Choosing a row sets the binding and dismisses. `vinetasStylePickerStyle(.list)` is an
  environment opt-in that shows the list inline instead, 5.5 rows tall, so Vinetas can
  keep today's look in its studio without a package change.
- **`VinetasStyleList`** — the 5.5-row-per-screen vertical list, public on its own:
  swatch, name, genre caption, accent halo and checkmark on the selected row, *Other*
  last. Identified `stylePicker.list`, rows `stylePicker.row.<rawValue>`. Row design,
  spacing (6 pt), minimum height (56 pt), radius (7 pt) and the 56 × 40 swatch move as
  they are. In a popover it is 340 pt wide and 5.5 rows tall; pushed, it fills the
  screen as an inset-grouped list.
- **`VinetasGenerationSettingsPanel`** — `models: [ModelSummary]` (the host has already
  filtered; the picker groups by `engineID` and shows size and RAM), `selectedModel`,
  `aspectRatio`, `steps`, `guidance`, `seed`, `randomizeSeed` bindings; **three optional
  bindings** `useDefaultSteps`, `useDefaultGuidance`, `useDefaultAspectRatio`
  (`Binding<Bool>?`, `nil` renders no toggle, so Vinetas iOS can pass `nil` and look
  unchanged); **plus** a `@ViewBuilder footnote` slot rendered under the model picker — a
  generic host slot for app-side notes the package must not know about. (No view renders
  `generation.memoryWarning` today on either platform; memory gating was removed. The
  identifier stays in `VinetasUIAccessibility` only for compatibility with the existing
  `MemoryGatingUITests.swift:89`, which is stale.) No `isProActive`; no in-view reset on model change.

And one composite for hosts that want the whole panel as one value:

```swift
public struct VinetasPromptDraft: Hashable, Sendable, Codable {
  public var prompt = ""
  public var caption: String? = nil       // nil = no caption field value
  public var stylePrompt = ""             // a preset's promptText, or free text
  public var negativePrompt = ""
  public var modelID = ModelSummary.pixartSigmaXL.id
  public var aspectRatio: AspectRatio?    // nil = Default (omit)
  public var steps: Int?                  // nil = Default (omit)
  public var guidance: Float?             // nil = Default (omit)
  public var seed: UInt64?                // nil = Randomize (omit)

  public var model: ModelSummary? { ModelSummary.all.first { $0.id == modelID } }
  public var style: StoryboardStyle? { StoryboardStyle.from(promptText: stylePrompt) }
  public static let empty: VinetasPromptDraft
}

public struct VinetasPromptComposer: View {
  public init(draft: Binding<VinetasPromptDraft>, models: [ModelSummary] = ModelSummary.all,
              showsCaption: Bool = false)
}
```

`VinetasPromptComposer` is the three views stacked, bound to one struct, with "Default"
and "Randomize" expressed as `nil`. The composer never writes a model's default value
back into the draft: a Default toggle on means the field is `nil`, the slider shows the
selected model's default value dimmed, and turning the toggle off writes that value into
the field as a starting point. That is the whole of what "Default" means in the package;
a host gives it its own meaning on save (Escribir: omit the attribute). Vinetas keeps
using the three views directly, because its `GenerationViewModel` observes each field
separately on purpose and a single-struct binding would invalidate the whole column on
every keystroke.

What the views do **not** do, on purpose: reset steps and guidance when the model
changes (host's job), know about Pro, know about downloads, know about memory, generate
anything, or draw a Save or Generate button.

### 2.4 Appearance

`StylePalette`'s eight tokens become **semantic**: row background, hover, border, primary
and secondary text, accent, accent-soft. In dark appearance they resolve to the V7 values
the app ships today, so a dark-mode screenshot of the studio before and after adoption is
the same list. In light appearance they resolve to the system equivalents
(`.quaternarySystemFill`-class fills, `.secondary` text, `Color.accentColor`), so the
list stops being a dark island. The swatch gradients are content, not chrome, and are
identical in both appearances. The views draw **no outer background**: the host's pane,
window or form supplies it, which is what lets the same view sit in Vinetas's sidebar,
a macOS inspector and an iOS form.

### 2.5 Identifiers and strings

`public enum VinetasUIAccessibility` in the SwiftAcervoUI shape, with **every one of the
nineteen strings from § What exists today unchanged** — `promptPrimary =
"prompt.primary"`, `stylePickerRowPrefix = "stylePicker.row"`,
`stylePickerPromptTextDisclosure = "stylePicker.promptTextDisclosure"`, and the rest —
plus one new constant, `promptCaption = "prompt.caption"`. No view in `VinetasUI` uses a
string literal as an identifier (`grep -rn 'accessibilityIdentifier("' Sources/VinetasUI`
prints nothing), and a package unit test asserts the enum's values equal the documented
strings.

Every user-facing string goes through `String(localized:bundle: .module)` with
`Sources/VinetasUI/Resources/Localizable.xcstrings`, English only (Vinetas's catalogue
holds no other language). Style display names and genre captions are vocabulary data,
not catalogue keys, and stay as they are.

### 2.6 The inspector presentation

The chosen host form on macOS and iPad is a right-hand inspector. The package ships it as
one modifier so a host adds it in one line:

```swift
extension View {
  /// Presents the composer as a trailing inspector (SwiftUI `.inspector`) on macOS and
  /// iPad, 340 pt ideal (300…420). `actions` is the host's row, pinned below the
  /// scrolling composer: Save, Cancel, Remove — whatever the host means. The package
  /// draws no action of its own. `header` is an optional row above the composer for the
  /// host's title and navigation ("Shot 2 of 7 ‹ ›").
  public func vinetasPromptInspector<Header: View, Actions: View>(
    isPresented: Binding<Bool>,
    draft: Binding<VinetasPromptDraft>,
    models: [ModelSummary] = ModelSummary.all,
    showsCaption: Bool = false,
    @ViewBuilder header: () -> Header = { EmptyView() },
    @ViewBuilder actions: () -> Actions
  ) -> some View
}
```

Inside the inspector the layout is forced to `.sidebar` and the composer scrolls between
the pinned header and the pinned action row, exactly as the canvas draws it. The
inspector is **non-modal**: the host's document stays editable while it is open, and the
host decides what the draft tracks (Escribir: the caret). On **iPhone** the modifier does
nothing but return `self` with a documented precondition failure in debug builds: the
compact form is a pushed screen, and pushing is the host's navigation stack to own
(§ 3 recipe 2). SwiftUI's own `.inspector` would present a sheet on iPhone, which is the
form the user rejected.

The pushed form needs nothing from the package beyond `VinetasPromptComposer` at
`.compact` and `VinetasStyleList` as the destination the style row pushes; both are
public and the recipe shows the host's part.

## 3. The host guide

The element is only reusable if a second program can adopt it from the documentation
alone. This mission writes `docs/VinetasUI.md` in this repo, linked from `README.md` and
`AGENTS.md`, and the package's DocC comments say the same things in the same words. The
guide contains, in this order:

1. **What you link.** `VinetasUI` and `VinetasVocabulary`, nothing else; what resolution
   clones and why it is not linked; the `otool`/`nm` recipe from `make
   verify-ui-isolation` for a host that wants its own proof; the statement that no
   App Group, entitlement or model download is involved.
2. **Recipe 1 — macOS / iPad inspector.** A complete `ContentView` of under forty lines:
   a `@State` `VinetasPromptDraft`, a `@State` `Bool`, a toolbar toggle with
   `sidebar.trailing`, `.vinetasPromptInspector(isPresented:draft:actions:)` with a Save
   button that hands the draft to the host's own save function. Shown against the
   canvas's inspector artboard.
3. **Recipe 2 — iPhone pushed screen.** A `NavigationStack` with a row (chevron) that
   pushes a screen holding `VinetasPromptComposer(draft:showsCaption:)` with a trailing
   `Save` in the navigation bar; the style row's push to `VinetasStyleList` happens
   inside the composer and needs nothing from the host but the stack. Shown against the
   canvas's three iPhone artboards. The same code at regular width on iPad gets the
   `.regular` layout without change; a host that wants the inspector on iPad uses
   recipe 1 there instead, keyed on `horizontalSizeClass`.
4. **Recipe 3 — the three views directly**, for a host with its own observable per
   field (the Vinetas pattern), including the optional Default bindings and the footnote
   slot.
5. **The draft's contract.** Field by field: what `nil` means, that `stylePrompt` is a
   preset's `promptText` or free text and how `style` recovers the preset, that
   `modelID` is a `ModelSummary.id` and `model?.cliName` is the external vocabulary, and
   that `Codable` conformance is stable across 0.22.x (a host may persist it).
6. **Mapping to a GLOSA `<shot>`** as a worked table — `prompt`, `caption`, `style =
   stylePrompt`, `model = cliName`, `aspect = aspectRatio?.rawValue`, `steps`,
   `guidance`, `seed`, `negative` — written as documentation of the draft, not as code:
   the writer lives in the host (Escribir's requirements say where). The table is the
   contract both repos test against.
7. **Appearance, layout override, identifiers, strings** — one paragraph each, pointing
   at `VinetasPanelLayout`, `vinetasStylePickerStyle`, `VinetasUIAccessibility`, and the
   `.module` bundle.

Recipes 1 and 2 are **compiled**: `Tests/VinetasUITests/HostRecipeTests.swift` contains
each recipe verbatim as a hosting view and instantiates it without a window, so the
guide cannot show code that no longer builds (D-11).

## 4. SwiftVinetas 0.22.0

The mission ends **release-ready**; the release itself is outside it (a mission branch
cannot tag). The user then opens the pull request and runs `ship-swift-library minor`,
which bumps the version literals, flips `Package.swift` to remote-only and tags. No
sortie edits a version literal or names a version number. `AGENTS.md` and `README.md`
gain a *Products* table — `SwiftVinetas`, `VinetasCLICore`, `vinetas`,
`VinetasVocabulary`, `VinetasUI` — with one line each on what links what, and a pointer
to `docs/VinetasUI.md`.

CI (`tests.yml`) gains what the release needs: `make lint-check` first (format, then
`git diff --exit-code`, so lint can fail); `make test-unit` running
`VinetasVocabularyTests` and `VinetasUITests` (view-model level: draft round-trip,
identifier constants, palette resolution, layout resolver, host recipes; no XCUITest in
a package) alongside the existing suites; `make verify-ui-isolation`; and a second job
`unit-tests-ios` on `macos-26` running `make test-unit-ios` with
`DESTINATION_IOS='platform=iOS Simulator,name=iPhone 17,OS=26.5'`. `make build-ios`
builds `VinetasUI` for the simulator. The Makefile's `-only-testing:` filters name every
test target that must run.

## The honest list

- **Resolution cost.** SwiftPM clones the full graph — `flux-2-swift-mlx`, `mlx-swift`
  (large, C++), `pixart-swift-mlx`, `SwiftTuberia`, `SwiftAcervo`, `swift-tokenizers`,
  `swift-certificates` — into a host's `SourcePackages` even though only two small
  targets compile. First resolution on a fresh runner is minutes, not seconds. Escribir
  measures it (its § 5); if the number is rejected, the answer is a binary `xcframework`
  of `VinetasUI` from this repo's release workflow, a later mission (OQ-1).
- **Light mode changes the look.** § 2.4 is a visible change for any host in light
  appearance. It is the right change, and it is the one place "unchanged screenshots"
  is not the acceptance.
- **The compact form is new design.** iPhone today shows the vertical list; the pushed
  screen with a chevron row is the user's call from the canvas. Vinetas's iOS UI tests
  (iPhone 17, compact) look for `stylePicker.list` inline and will need an edit when
  Vinetas adopts the package, unless Vinetas opts into `.list` style. That is recorded
  for the Vinetas mission; nothing in this repo runs those tests.
- **Two repos, one tag between them.** Escribir cannot start before this is tagged.

## Non-goals

1. **No generation in `VinetasUI`.** It draws a description of an image. `VinetasClient`
   stays where it is. No Generate, Save or Cancel button is drawn by the package.
2. **No new styles, no reordering, no renamed cases, no changed prompt strings.**
3. **No redesign of the controls.** Spacing, 340 pt ideal width, 5.5 visible rows, the
   tiles, the sliders' ranges (1…50, 1.0…20.0 by 0.5) are moved as they are. The
   inspector form and the compact form are new *containers*, not new controls.
4. **No animated swatch.** `TimelineView` is forbidden in `VinetasUI`.
5. **No change to `VinetasCLICore` or the `vinetas` executable** beyond compiling
   against the moved types through the re-export and `ModelDescriptor.cliName`.
6. **No Vinetas-app change and no Escribir change** in this mission.
7. **No binary framework** unless OQ-1 forces it.
8. **No Klein 9B, no memory gating.** Standing directives.

## Decisions

- **D-1 — Extract, not copy; into SwiftVinetas, not a new package.** The user, 2026-10-05.
- **D-2 — `VinetasUI` does not depend on `SwiftVinetas`.** Proven by `make
  verify-ui-isolation` in CI.
- **D-3 — `ModelSummary` carries no `requiresPro`; it carries `cliName`.** Hosts filter;
  hosts write the CLI vocabulary without a table of their own.
- **D-4 — Semantic colours, V7 values in dark, no outer fill.** § 2.4.
- **D-5 — Source-compatible 0.22.0.** The re-export keeps every `import SwiftVinetas`
  consumer compiling unchanged.
- **D-6 — Three views stay the primary API; the composer and the inspector are
  additive.**
- **D-7 — macOS and iPad: right-hand inspector. iPhone: pushed screen with a chevron
  row for Style.** The user, 2026-10-06, choosing between the canvas's sheet and
  inspector artboards. This retires the 2026-10-06 "popup metaphor" direction and the
  2026-10-05 `.compact` popup `Menu`.
- **D-8 — The package draws no action button.** Save, Generate, Cancel, Remove are the
  host's row in the inspector's `actions` slot or the host's navigation bar.
- **D-9 — `VinetasVocabulary` is Apple-frameworks-only, not Foundation-only.**
  `ResolutionClamp` moves unchanged with its conditional Metal import.
- **D-10 — `promptText`, `negativePromptText` and `rawValue` are all frozen** and pinned
  by a fixture test in the package.
- **D-11 — The host guide's recipes are compiled tests.** Documentation that cannot rot.
- **D-12 — Optional Default bindings; `nil` in the draft is the only meaning of
  Default inside the package.** The host decides what `nil` means on save.
- **D-13 — Previews are fixed-size canvases forcing a layout**, not device-pinned.

## Open questions

- **OQ-1 — Acceptable resolution cost in a host.** Measured in Escribir's mission. If
  rejected, `VinetasUI` ships as an `xcframework` from this repo's release workflow.
- **OQ-2 — Resolved:** the target is named `VinetasVocabulary`.
- **OQ-3 — Resolved** as D-13: fixed-layout previews at the three reference sizes,
  plus one manual look by the user before the Escribir mission starts.

## Acceptance

1. **Release-ready on the mission branch:** `swift package dump-package` lists products
   `SwiftVinetas`, `VinetasCLICore`, `vinetas`, `VinetasVocabulary`, `VinetasUI`;
   `VinetasUI`'s target dependencies are exactly `VinetasVocabulary`;
   `VinetasVocabulary` has no package dependencies.
2. `make lint-check`, `make test-unit`, `make test-unit-ios` and `make
   verify-ui-isolation` green in CI, including the descriptor-equals-summary test, the
   `cliName` round-trip, the identifier-string test, the frozen-vocabulary fixture test,
   the layout-resolver test for every platform × size-class combination, and the two
   compiled host recipes. `VinetasPromptPanel`, `VinetasStylePicker`, `VinetasStyleList`,
   `VinetasGenerationSettingsPanel` and `VinetasPromptComposer` each have three
   `#Preview`s named for the three layouts at the reference sizes, and the inspector has
   one named `"Inspector (macOS)"`; all sixteen render in Xcode's canvas.
3. The `vinetas` CLI and `SwiftVinetasGPUTests` build against the branch **with no
   source change** outside `Package.swift` and the `cliName` addition.
4. A dark-appearance render of `VinetasStyleList` at 340 pt matches the Vinetas studio's
   list row for row, swatch for swatch; a light-appearance render shows system fills and
   text with the same swatches.
5. `docs/VinetasUI.md` exists with the seven sections of § 3, `README.md` and `AGENTS.md`
   carry the Products table and link it, and every code block in the guide's recipes 1
   and 2 is byte-identical to the corresponding test in `HostRecipeTests.swift`.
6. The canvas's inspector artboard and the three iPhone artboards are reproduced by the
   previews closely enough that the user signs off on one manual look (OQ-3).

---
type: doc
updated: 2026-10-18
---

# VinetasUI host guide

`VinetasUI` is the storyboard prompt panel as a SwiftUI package: the prompt, an optional caption, the style, the negative prompt, the model, and the generation settings, for macOS and iOS. It draws no Save or Generate button, generates nothing, and downloads nothing. The host owns every action and decides what the edited values mean on save. This guide is everything a second app needs to adopt it. The DocC comments on the public symbols use the same words.

Every sample here is granville episode 1's establishing shot, copied from the real project: the prompt from the `<shot>` directive and the panel `ep1_sc1_01_establishing.json`, the settings from the defaults shot at line 7 of `episode_1_01_cold_open.fountain`, and the caption from that script's scene heading at line 9.

## 1. What you link

Link two products of the `SwiftVinetas` package, and nothing else:

```swift
.product(name: "VinetasUI", package: "SwiftVinetas"),
.product(name: "VinetasVocabulary", package: "SwiftVinetas"),
```

- `VinetasUI` holds the views, `VinetasPromptDraft`, the inspector modifier, the layout and environment values, and `VinetasUIAccessibility`. It depends on `VinetasVocabulary`, SwiftUI and platform frameworks only. It does not depend on `SwiftVinetas` and imports no other package's product.
- `VinetasVocabulary` holds the engine-free vocabulary the views speak: `StoryboardStyle`, `StyleSwatchPalette`, `AspectRatio` and `ModelSummary`. It links no UI framework and no inference stack.

**What resolution clones.** SwiftPM resolves a package's whole dependency graph, so adding `SwiftVinetas` still *clones* everything its manifest names: flux-2-swift-mlx (and MLX through it), pixart-swift-mlx, SwiftTuberia, SwiftAcervo, glosa-av, SwiftCompartido, universal, swift-tokenizers, swift-argument-parser, swift-certificates, swift-crypto and swift-asn1. That is a one-time cost in the package cache. None of it is compiled or linked into your app, because no target `VinetasUI` or `VinetasVocabulary` depends on uses any of it.

**The proof.** `make verify-ui-isolation` builds `Tools/UIIsolationProbe`, a throwaway executable that imports only `VinetasUI`, through `xcodebuild`, then fails if any of three checks matches the pattern `MLX|Flux2|PixArt|Tuberia|Acervo`:

```sh
PATTERN='MLX|Flux2|PixArt|Tuberia|Acervo'
otool -L "$BIN" | grep -E "$PATTERN"     # linked libraries
nm -gU "$BIN" | grep -E "$PATTERN"       # exported symbols
grep -E 'SwiftCompile|CompileSwift|SwiftDriver|Ld ' build.log | grep -E "$PATTERN"   # what the build compiled
```

`$BIN` is the built executable and `build.log` is the `xcodebuild` output (`build/ui-isolation.log` in this repo). All three commands printing nothing is a pass. `EXPECT_FAIL=1 make verify-ui-isolation` is the detector's self-test: it builds `UIIsolationProbeEngine`, which imports `SwiftVinetas` on purpose, and passes only if the checks fire. A host that wants its own proof runs the same three commands on its own app binary and build log.

**What is not involved.** No App Group, no entitlement, no model download and no model file. The panel describes models through `ModelSummary`; running one is the host's business.

**`ModelSummary` fields.** `id`, `displayName`, `engineID`, `cliName`, `minimumMemoryGB`, `approximateDownloadSize`, `defaultSteps`, `defaultGuidance` and `supportedAspectRatios` describe the model. Since 0.24.0 it also carries `supportsSteps`, `supportsGuidance`, `supportsSeed` and `supportsNegativePrompt` (default `true`), and `engineName` and `subtitle` (default `nil`). The on-device models keep the defaults; `ModelDescriptor.summary` of a `CloudModelDescriptor` fills in the vendor's flags, its short name (`engineName`, e.g. "OpenAI") and "vendor · price hint" (`subtitle`). A summary encoded by 0.22.0 or 0.23.0 still decodes: missing flags read `true`, missing names `nil`.

## 2. Recipe 1 — macOS / iPad inspector

The panel as a non-modal trailing inspector: a `@State` draft, a `@State` Bool, a toolbar toggle with the `sidebar.trailing` symbol, and `.vinetasPromptInspector(isPresented:draft:actions:)` with a Save button that hands the draft to the host's own save. This is the canvas's *macOS · Right-hand inspector panel* artboard: the `.sidebar` layout in a column 340 pt ideal (300 min, 420 max), the composer scrolling between the optional header and the pinned action row, and the document still editable while the inspector is open.

<!-- recipe-1:begin -->
```swift
struct ContentView: View {
  @State private var draft = VinetasPromptDraft(
    prompt:
      "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame.",
    caption: "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET",
    stylePrompt:
      "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light",
    negativePrompt:
      "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry",
    modelID: ModelSummary.klein4B.id,
    aspectRatio: .wide,
    steps: 8,
    guidance: 3.5,
    seed: 22
  )
  @State private var showsInspector = true

  var body: some View {
    NavigationStack {
      Text(draft.caption ?? draft.prompt)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
          Button("Prompt", systemImage: "sidebar.trailing") { showsInspector.toggle() }
        }
        .vinetasPromptInspector(isPresented: $showsInspector, draft: $draft) {
          Button("Save") { save(draft) }
            .padding()
        }
    }
  }

  /// The host's own save: write the `<shot>`, the file, the record.
  func save(_ draft: VinetasPromptDraft) {}
}
```
<!-- recipe-1:end -->

The inspector forces the `.sidebar` layout, so an iPad never gets the `.regular` side-by-side sliders in a 340 pt column. The package draws no action of its own: everything in `actions`, and in the optional `header` overload (a title, "Shot 2 of 7 ‹ ›"), is the host's. What the draft tracks while the inspector is open (a selection, the caret) is also the host's decision.

On iPhone the modifier returns the view unchanged, and in a debug build it trips an `assertionFailure` when the view is rendered. Use recipe 2 there.

## 3. Recipe 2 — iPhone pushed screen

On iPhone the panel is a pushed screen, not a sheet: a `NavigationStack` with a chevron row that pushes a screen holding `VinetasPromptComposer(draft:showsCaption:)`, with a trailing `Save` in the navigation bar. These are the canvas's three iPhone artboards: *iPhone · Host screen* (the row), *iPhone · Storyboard Prompt (pushed, full scroll extent)* (the composer's `.compact` inset-grouped form), and *iPhone · Style (pushed)* (the style list).

<!-- recipe-2:begin -->
```swift
struct ShotListView: View {
  @State private var draft = VinetasPromptDraft(
    prompt:
      "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame.",
    caption: "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET",
    stylePrompt:
      "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light",
    negativePrompt:
      "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry",
    modelID: ModelSummary.klein4B.id,
    aspectRatio: .wide,
    steps: 8,
    guidance: 3.5,
    seed: 22
  )

  var body: some View {
    NavigationStack {
      List {
        NavigationLink {
          ShotPromptScreen(draft: $draft, save: save)
        } label: {
          Text(draft.caption ?? draft.prompt)
            .lineLimit(2)
        }
      }
      .navigationTitle("Cold Open")
    }
  }

  /// The host's own save: write the `<shot>`, the file, the record.
  func save(_ draft: VinetasPromptDraft) {}
}

struct ShotPromptScreen: View {
  @Binding var draft: VinetasPromptDraft
  let save: (VinetasPromptDraft) -> Void

  var body: some View {
    VinetasPromptComposer(draft: $draft, showsCaption: true)
      .navigationTitle("Storyboard Prompt")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save(draft) }
        }
      }
  }
}
```
<!-- recipe-2:end -->

The style row's push to `VinetasStyleList` happens inside the composer and needs nothing from the host but the stack. Without a stack, see `vinetasNavigationStackAvailable` in section 7.

The same code at regular width on iPad gets the `.regular` layout without change: one scrolling column with Steps and Guidance side by side. A host that wants the inspector on iPad uses recipe 1 there instead, keyed on `horizontalSizeClass` (`.regular` → recipe 1, `.compact` → recipe 2).

## 4. Recipe 3 — the three views directly

A host that keeps its own observable per field (the Vinetas pattern, where a single-struct binding would invalidate the whole column on every keystroke) uses the three views the composer stacks:

```swift
VinetasPromptPanel(
  prompt: $model.prompt,
  stylePrompt: $model.stylePrompt,
  negativePrompt: $model.negativePrompt,
  selectedModel: model.selectedModel,
  caption: $model.caption  // optional; nil (the default) shows no caption field
)
VinetasGenerationSettingsPanel(
  models: ModelSummary.all,
  selectedModel: $model.selectedModel,
  aspectRatio: $model.aspectRatio,
  steps: $model.steps,
  guidance: $model.guidance,
  seed: $model.seed,
  randomizeSeed: $model.randomizeSeed,
  useDefaultSteps: $model.useDefaultSteps,  // optional; nil renders no Default toggle
  useDefaultGuidance: $model.useDefaultGuidance,  // optional
  useDefaultAspectRatio: $model.useDefaultAspectRatio  // optional
) {
  Text("Your note under the model picker")  // the footnote slot; optional
}
VinetasStylePicker(selection: $model.stylePrompt)  // on its own, outside the prompt panel
```

`model` stands for the host's own observable object; this recipe is a shape, not compiled code.

- **`VinetasPromptPanel`** edits `prompt`, `stylePrompt` and `negativePrompt`. `selectedModel` only labels the prompt with an engine badge and writing hints; the panel never changes the model. When the model's `supportsNegativePrompt` is `false` (every shipped cloud model), a note under the negative prompt says the engine ignores it; the field stays editable. A `caption` binding adds a single-line caption field under the prompt; `nil` shows none. Choosing a preset style writes that style's `negativePromptText` into `negativePrompt` and reveals the Negative Prompt section; a custom style leaves the negative prompt alone. The panel already contains a `VinetasStylePicker`; use the picker on its own only where you build the prompt fields yourself.
- **`VinetasGenerationSettingsPanel`** offers exactly the `models` you pass, grouped by `engineID`, with each model's approximate download size and minimum memory as text that never gates a choice. When the selected model's `supportsSteps`, `supportsGuidance` or `supportsSeed` is `false`, that control (the seed field with Randomize) is disabled and dimmed, with a short note under it. A group is titled with its models' `engineName` when they carry one (a cloud vendor's short name, such as "OpenAI"), else "FLUX.2" or "PixArt"; a model's `subtitle`, when it has one, replaces the size and memory text. The three `useDefault…` bindings are optional: each one you pass adds a Default toggle beside its control and disables the control while the toggle is on; `nil` (the default) renders no toggle, so a host can pass `nil` and look unchanged. The trailing `footnote` closure is drawn under the model picker, for app-side notes the package does not know about; the initializer without it draws none. Changing the model changes nothing else: resetting steps, guidance or aspect ratio to a model's defaults is the host's job.
- **`VinetasStylePicker`** binds a style prompt: a preset's `promptText`, or free text. `StoryboardStyle.customTag` is *Other*. Its form follows the layout (section 7).

## 5. The draft's contract

`VinetasPromptDraft` is the whole panel as one value. "Default" and "Randomize" are `nil`; what `nil` means on save is the host's decision (for example, omitting the attribute). The composer never writes a model's default into the draft while a Default toggle is on: the control shows the selected model's default dimmed, and turning the toggle off writes that default into the field as a starting point.

| Field | Type | `nil` or empty means |
|---|---|---|
| `prompt` | `String` | The primary prompt. Empty means no prompt yet. |
| `caption` | `String?` | `nil` means no caption value. The composer stores `nil` when the caption field is cleared, and shows the field only when `showsCaption` is `true`. |
| `stylePrompt` | `String` | A preset's `promptText`, or free text. `style` recovers the preset: `StoryboardStyle.from(promptText:)` gives the preset whose `promptText` matches, and `nil` for free text, the empty string and `StoryboardStyle.customTag`. |
| `negativePrompt` | `String` | The negative prompt. Choosing a preset replaces it with that style's `negativePromptText`. |
| `modelID` | `String` | A `ModelSummary.id`, such as `flux2-klein-4b`. `model` is the shipped `ModelSummary` with that id, or `nil` if none matches. `model?.cliName` (`klein4b`) is the external vocabulary: the name the CLI and GLOSA `model=` use. The default is PixArt-Sigma XL. |
| `aspectRatio` | `AspectRatio?` | `nil` means Default: the selected model's default ratio. |
| `steps` | `Int?` | `nil` means Default: the selected model's `defaultSteps`. |
| `guidance` | `Float?` | `nil` means Default: the selected model's `defaultGuidance`. |
| `seed` | `UInt64?` | `nil` means Randomize: pick a new seed for each generation. |

`VinetasPromptDraft.empty` has every field at its default: empty prompts, no caption, PixArt-Sigma XL, and Default / Randomize everywhere.

**Persistence.** A draft is `Codable` with stable keys, each the field's name (`prompt`, `caption`, `stylePrompt`, `negativePrompt`, `modelID`, `aspectRatio`, `steps`, `guidance`, `seed`). `aspectRatio` is encoded as the ratio's `rawValue` string. A `nil` field is omitted, and a missing key decodes to the field's default. A host may persist encoded drafts and expect them to decode across the next minor release's patch line.

## 6. Mapping to a GLOSA `<shot>`

How a host writes a draft into a GLOSA `<shot>` directive. This is documentation of the draft, not package code: the writer lives in the host. The example columns are the two directives in granville's `episode_1_01_cold_open.fountain` that the recipes' draft comes from: the prompt-less **defaults shot** at line 7, whose attributes every later shot in the scene inherits, and the **establishing shot** at line 11. The recipes' draft is the two merged, which is also what `ep1_sc1_01_establishing.json` records the CLI generated.

| `<shot>` attribute | From the draft | Defaults shot (line 7) | Establishing shot (line 11) |
|---|---|---|---|
| `prompt` | `prompt` | (absent) | `Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer …` |
| `caption` | `caption`; `nil` → omit | (absent) | (absent); the recipes' draft carries the line-9 scene heading `EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET` |
| `style` | `stylePrompt` | `photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light` | (inherited) |
| `model` | `model?.cliName` | `klein4b` (`modelID` `flux2-klein-4b`) | (inherited) |
| `aspect` | `aspectRatio?.rawValue`; `nil` → omit | `wide` | (inherited) |
| `steps` | `steps`; `nil` → omit | `8` | (inherited) |
| `guidance` | `guidance`; `nil` → omit | `3.5` | (inherited) |
| `seed` | `seed`; `nil` → omit | `22` | (inherited) |
| `negative` | `negativePrompt` | `text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry` | (inherited) |

`nil` means omit the attribute, so the reader's defaults apply. An empty `stylePrompt` or `negativePrompt` names nothing, and a host normally omits it too. Attributes the draft does not hold, such as the establishing shot's `output`, are the host's own. The table is the contract the hosts that write `<shot>` test against.

## 7. Appearance, layout override, identifiers, strings

**Layout.** Every view takes its shape from a `VinetasPanelLayout`. `.sidebar` is the inspector column: the default on macOS, and the layout the inspector forces on iPad. `.regular` is iOS at regular width outside an inspector (iPad full screen), with Steps and Guidance side by side. `.compact` is iOS at compact width: the iPhone pushed screen, an inset-grouped form. `VinetasPanelLayout.resolve(platform:horizontalSizeClass:)` is the pure function that picks one (macOS is always `.sidebar`; on iOS an unknown size class counts as `.regular`). A host forces a layout with `.vinetasPanelLayout(_:)`, and passing `nil` restores resolving it.

**Style picker.** In `.sidebar` and `.regular` the picker is a button showing the selected style's swatch, name and genre caption, and opens `VinetasStyleList` in a popover, 340 pt wide and 5.5 rows tall. In `.compact` it is a chevron row that pushes the list onto the host's `NavigationStack`. `.vinetasStylePickerStyle(.list)` shows the 5.5-row list inline instead, whatever the layout; `.automatic` is the default.

**No navigation stack.** SwiftUI cannot detect an enclosing `NavigationStack`, and a `NavigationLink` outside one does nothing. A host that presents the panel at compact width without a stack applies `.vinetasNavigationStackAvailable(false)` (the environment value `vinetasNavigationStackAvailable`, `true` by default), and the style row falls back to the button that opens the list in a popover, so it never dead-ends.

**Appearance.** The views draw no outer background: the host's pane, window or form supplies it, which is what lets the same view sit in a sidebar, a macOS inspector and an iOS form. The palette is semantic. In dark appearance it resolves to the values the Vinetas app ships; in light appearance it resolves to the system fills, `.secondary` text and `Color.accentColor`. Style swatches are content, identical in both.

**Identifiers.** Every accessibility identifier a VinetasUI view sets comes from `VinetasUIAccessibility`; reference its constants in UI tests rather than the strings. The prompt panel uses `prompt.primary`, `prompt.caption`, `prompt.negativeToggle`, `prompt.negative` and `stylePicker.promptTextDisclosure`; the style picker uses `prompt.stylePicker` for its button or chevron row and `prompt.styleCustom` for the custom style field; the style list uses `stylePicker.list`, and rows `stylePicker.row.<style.rawValue>` (`stylePickerRow(_:)`); the settings panel uses `generation.modelPicker`, `generation.aspectRatioSelection`, tiles `generation.aspectRatioTile.<ratio.rawValue>` (`aspectRatioTile(_:)`), `generation.stepsSlider`, `generation.stepsUseDefault`, `generation.guidanceSlider`, `generation.guidanceUseDefault`, `generation.aspectRatioUseDefault`, `generation.seedField` and `generation.randomizeSeed`; the notes under unsupported controls are `generation.stepsUnsupportedNote`, `generation.guidanceUnsupportedNote`, `generation.seedUnsupportedNote` and, in the prompt panel, `prompt.negativeUnsupportedNote`. `generation.memoryWarning` is kept for existing host UI tests only; no view renders it.

**Strings.** Every user-facing string resolves in the package's own English catalogue, `Localizable.xcstrings`, through `String(localized:bundle: .module)`, never the host's main bundle. Style display names and genre captions are `StoryboardStyle` vocabulary data, not catalogue keys.

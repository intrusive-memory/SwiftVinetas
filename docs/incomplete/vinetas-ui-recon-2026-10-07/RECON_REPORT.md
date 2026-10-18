---
type: recon-report
state: current
requirements_file: docs/REQUIREMENTS-vinetas-ui.md
requirements_sha256: 3f1d73d753c9d94459ec5e61ab1efeba3c3c51253f119ef1f216748285299803
project_head: 795aa1825bf6b0de2644df32c5442ec111277079
search_root: ~/Projects
generated: 2026-10-07
verdict: BLOCKED
blocking: 4
supersedes: the 2026-10-06 report written against the popup-metaphor draft (sha c21ea1a7…)
---

# RECON_REPORT.md — SwiftVinetas `VinetasUI` (inspector element)

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**BLOCKED** — 52 assumptions checked across five loci: 47 confirmed, 3 stale, 1 refuted,
1 unverifiable.

The four blocking findings are **citation and count errors in the requirements text**, not
design defects. None changes a type, a view, a layout, or a sortie. Each is fixed by
amending one sentence; the recommended amendment is given under each. After the amendment
the report must be re-stamped (the `requirements_sha256` above will no longer match).

The 2026-10-06 `EXECUTION_PLAN.md` at the repo root was generated against the superseded
popup-metaphor draft and is **not valid for this document**; `breakdown` must regenerate it.

## Assumption Findings

### Locus: repo — SwiftVinetas at `795aa18` (`development`, source identical to `d88dd27`)

| ID | Kind | Claim (requirements § What exists today) | Verdict | Evidence |
|----|------|-------|---------|----------|
| R-01 | A-FILE | `AspectRatio`, `StyleConfig`, `VinetasError`, `VinetasModelInfo` import Foundation only; `ResolutionClamp` imports Metal conditionally and calls `MTLCreateSystemDefaultDevice().maxBufferLength` at 71–72 | CONFIRMED | `Core/ResolutionClamp.swift:1,3–5,71–72`; `grep '^import' Core/*.swift`. Core/ holds 12 files in all; the other seven (LoRAManager, PanelOutput, ImageOutput, PromptFile, VinetasPipeline, VinetasMemory, VinetasMemoryProfiler) import Flux2Core/MLX/YAML/etc. and are not part of the move |
| R-02 | A-INVARIANT | `AspectRatio.swift:105` calls `ResolutionClamp`; the three moving files are a closed set | CONFIRMED | `Core/AspectRatio.swift:105` = `return ResolutionClamp.clampedDimensions(…)`. Hub: every capitalised identifier used in the three files, checked against type declarations elsewhere in `Sources/` — zero outside-the-set hits |
| R-03 | A-INVARIANT | Internal `attentionHeadsWorstCase` / `scoreBytes` are reached only by their two test files; no non-public member of the three types is used elsewhere in `Sources/` | CONFIRMED | Declarations `Core/ResolutionClamp.swift:39,43`; uses `Tests/SwiftVinetasTests/ResolutionClampTests.swift:20,22`, `AspectRatioTests.swift:172,174`. Hub grep of all internal members (`safetyFraction`, `pixelsPerToken`, `minimumEdge`, `fallbackMaxBufferLengthBytes`, …) outside Core/: only unrelated locals of the same name |
| R-04 | A-API | `ModelDescriptor` (`Engine/ModelDescriptor.swift`) imports Foundation only and already requires all eight `ModelSummary` fields with matching names and types | CONFIRMED | `Engine/ModelDescriptor.swift:1,13`. The protocol also requires `license: ModelLicense` and `componentIds: [String]` (default `[]`); the summary omits both. No `cliName` or `summary` member exists today |
| R-05 | A-API | `Flux2ModelDescriptor.klein4B` at `Engine/Flux2Engine.swift:35`, `PixArtModelDescriptor.sigmaXL` at `Engine/PixArtEngine.swift:39`, with the table's values; both list `AspectRatio.allCases` | CONFIRMED | `Flux2Engine.swift:16` (engineID `"flux2"`), `:35–43`; `PixArtEngine.swift:39–48`. `Flux2ModelDescriptor` has exactly one static; no `9B` in `Sources/` outside base64 noise in `AppleRootCA.swift` |
| **R-06** | A-API | `VinetasModel(rawValue:)` lives at `Sources/VinetasCLICore/VinetasCLICore.swift:63` and is the CLI's model vocabulary (`klein4b`, `pixart-sigma`) | **STALE** | The enum is `public enum VinetasModel: String, Sendable, Codable, CaseIterable` in `Sources/SwiftVinetas/Vinetas.swift:1753`, cases `klein4b = "klein4b"`, `pixartSigma = "pixart-sigma"` — and it is `@available(*, deprecated, message: "Use ModelDescriptor types directly …")` (`:1749–1751`). `VinetasCLICore.swift:63` is the `--model` option's help string; the CLI still resolves through `VinetasModel(rawValue:)` at `VinetasCLICore.swift:164,338,447,581,916,1034`. See B-1 |
| R-07 | A-CONFIG | Products, `SwiftVinetas` target deps, platforms as stated; no `defaultLocalization`; no engine-free target | CONFIRMED | `Package.swift:43–65` (no `defaultLocalization` key), `:155–166` |
| R-08 | A-INVARIANT | No SwiftUI, no `.xcstrings`, no `Resources/` in the package | CONFIRMED | `grep -rn "import SwiftUI" Sources Tests` empty; `find … -name '*.xcstrings' -o -name Resources` empty |
| R-09 | A-CONFIG | `tests.yml` has one job "Unit Tests (macOS)" on `macos-26` running `make build` then `make test-unit`; no lint, no iOS job | CONFIRMED | `.github/workflows/tests.yml` job `unit-tests`; `grep -n 'lint\|format' .github/workflows/*.yml` empty. Also present: `pixart-integration.yml` (job `pixart-integration`, also on PRs to `main`/`development`) and `release.yml` (`build-and-release`, on release) |
| R-10 | A-CONFIG | `make lint` is `swift format -i -r .`; `test-unit` and `test-unit-ios` filter `-only-testing:SwiftVinetasTests`; `build-ios` exists; no `lint-check`, no `verify-ui-isolation` | CONFIRMED | `Makefile:291–292`, `:131`, `:245`, `:96–100`; `.PHONY` at `:68` lists neither new target. `DESTINATION_IOS` default (`:32`) is `platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1` — not the iPhone 17 / 26.5 the requirements name for the new CI job |
| **R-11** | A-CONFIG | `"0.21.0-dev"` appears in `Vinetas.swift:48,1125`, `AGENTS.md:8`, `README.md:42,235` | **STALE** | `git grep -n '0.21.0-dev'`: `Sources/SwiftVinetas/Vinetas.swift:48,1125`, `AGENTS.md:8`, and (now tracked) `docs/REQUIREMENTS-vinetas-ui.md:39,140`. **`README.md` has none**: `:42` is `from: "0.21.0"`, `:235` is the v0.21.0 release note. See B-2 |
| R-12 | A-CONFIG | A release tag ships a remote-only manifest | CONFIRMED | `git show v0.21.0:Package.swift \| grep -nE 'sibling\(\|path:'` empty (exit 1) |
| R-13 | A-FILE | The three Core test files exist, Swift Testing, `@testable import SwiftVinetas` | CONFIRMED | `Tests/SwiftVinetasTests/{AspectRatio,ResolutionClamp,StyleConfig}Tests.swift:1–3` |
| R-14 | A-INVARIANT | All new names are free (`VinetasVocabulary`, `VinetasUI`, `ModelSummary`, `VinetasPanelLayout`, `VinetasPlatform`, `VinetasSizeClass`, the five view names, `VinetasPromptDraft`, `VinetasUIAccessibility`, `StyleSwatchPalette`, `StoryboardStyle`, `lint-check`, `verify-ui-isolation`, `HostRecipeTests`) | CONFIRMED | grep over `Sources Tests Makefile Package.swift`: zero hits |
| R-15 | A-FILE | `AGENTS.md`, `README.md` exist with no Products table; no `docs/VinetasUI.md` | CONFIRMED | `ls`; `grep -niE 'products' AGENTS.md README.md` empty |
| R-16 | A-INVARIANT | No module-qualified or reflected use of the moving types (re-export is sufficient) | CONFIRMED | grep for `SwiftVinetas\.(AspectRatio\|ResolutionClamp\|StyleConfig)`, `String(reflecting`, `_typeName`, `NSClassFromString`: zero. Blast radius of the move (files outside Core/ naming the types): `Vinetas.swift`, `PanelRequest.swift`, both `Engine/*Engine.swift`, `ModelDescriptor.swift`, `VinetasCLICore.swift`, `Storyboard/StoryboardCommand.swift`, 16 unit-test files, 4 GPU-test files |
| R-17 | A-CONFIG | `Package.resolved` is gitignored; no committed lock | CONFIRMED | `.gitignore:13–14`; `git ls-files Package.resolved` empty |
| R-18 | A-FILE | `SwiftVinetasGPUTests` exists, excluded from `test-unit`, compiles against the moved types through `import SwiftVinetas` | CONFIRMED | directory present; `Makefile:131` filter; `StyleConfig` named in `PixArtIntegrationTests.swift:187`, `ReferenceGenerationGPUTests.swift:72,99,139`, `AllModelsExampleTests.swift:141`, `BatchIntegrationTests.swift:147`. `Sources/vinetas` names none of the three |

### Locus: source — Vinetas app at `0c25a3d` (`docs/dossier-integration`, clean)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| V-01 | A-FILE | Seven panel files at the stated line counts; `StylePickerListView` holds the swatch view, `StylePalette` and the `swatchPalette` extension; `MidCenturySwatch` is a static `Canvas`; iOS has no own list file | CONFIRMED | `wc -l`: 233 / 294 / 191 / 329 / 303 / 351. `StyleSwatchView` `:158`, `enum StylePalette` `:215`, `extension StoryboardStyle` `:232`; `Canvas` `MidCenturySwatch.swift:27`; `AspectRatioTile` `GenerationSettingsPanel.swift:259`. `StylePickerListView.swift` and `MidCenturySwatch.swift` reach the iOS target through the synchronized root group (`project.pbxproj:136–236`; exception set `:152–169` excludes the other macOS studio files, not these two) |
| V-02 | A-BEHAVIOR | No popup picker on any platform; `prompt.stylePicker` is a constant no view references | CONFIRMED | `Vinetas/Views/GenerationStudio/PromptInputPanel.swift:100` and `VinetasIOS/…/PromptInputPanel.swift:128` embed `StylePickerListView` inline. `AccessibilityID.promptStylePicker = "prompt.stylePicker"` (`AccessibilityID.swift:110`): no view and no UI test references it |
| V-03 | A-BEHAVIOR | The eleven listed iOS-vs-macOS divergences | CONFIRMED | (a) iOS `GenerationSettingsPanel.swift:52–56`; (b) `PromptInputPanel.swift:73,101`; (c) `:83`; (d) iOS `:91` vs macOS `GenerationSettingsPanel.swift:86`; (e) iOS `:182–200,212` vs macOS `:142,146`; (f) iOS `:131`; (g) iOS `GenerationSettingsPanel.swift:249`; (h) macOS `PromptInputPanel.swift:171`, `GenerationSettingsPanel.swift:53`; (i) iOS `:94–107`; (j) macOS `:25–27,84–86`, `GenerationViewModel.swift:110–124`; (k) iOS `:145`, macOS `:138` |
| V-04 | A-API | `StoryboardStyle`: 19 presets + `.custom`, the listed members, Foundation only; `swatchPalette` lives elsewhere | CONFIRMED | `Vinetas/Models/StoryboardStyle.swift:8,17,18–37`; members at `:42,70,97,103,150 (private static),156 (private),207,214,218,225`, all internal. `swatchPalette` at `StylePickerListView.swift:232` returns `(Color, Color, Color)` |
| V-05 | A-API | `AvailableModel` projects the two descriptors; Pro is `engineID == "flux2"` | CONFIRMED | `Vinetas/Models/AvailableModel.swift:9,62–63,80,85,88,93,115`. Also imports SwiftData and SwiftVinetas; `recommendedSteps` overrides FLUX.2 to 8 |
| V-06 | A-DATA | `AccessibilityID.swift` mirrored non-verbatim into two UI-test targets; the nineteen strings exist; `stylePicker.promptTextDisclosure` is a raw literal in both panels | CONFIRMED | 18 of 19 are constants in `Vinetas/AccessibilityID.swift` (prefixes carry no trailing dot: `:39`, `:121`); `stylePicker.promptTextDisclosure` is a literal at `Vinetas/…/PromptInputPanel.swift:137` and `VinetasIOS/…/PromptInputPanel.swift:172`. Both copies `diff` non-empty (missing the three `…UseDefault` constants; iOS copy also lacks `generationMemoryWarning`). `prompt.caption` exists nowhere |
| **V-07** | A-FILE | **Four** UI-test files drive the panel | **STALE** | Five: `VinetasUITests/{VinetasUITests,MemoryGatingUITests,ScreenshotUITests}.swift`, `VinetasIOSUITests/{GenerationIntegrationTests,VinetasIOSUITests}.swift`. Only `VinetasIOSUITests/VinetasIOSUITests.swift:275` uses `stylePickerList` — the iOS test the honest list says will need an edit. See B-3 |
| V-08 | A-BEHAVIOR | `AppDefaults.swift:72–73` persists `promptText`, recovered with `from(promptText:)` | CONFIRMED | `Vinetas/Models/AppDefaults.swift:71–73`; recovery call at `GenerationViewModel.swift:430` and both panels. No other persistence of `StoryboardStyle` |
| V-09 | A-DATA | Fixture JSON, `StoryboardStyleCatalogTests` via `#filePath`, `sync-storyboard-styles.sh` → `vinetas-skills`, `StoryboardStyleTests` | CONFIRMED | `VinetasTests/Fixtures/storyboard-styles.json` (19 entries; keys `id, displayName, genre, prompt, negative`); `StoryboardStyleCatalogTests.swift:49,63–64`; `Scripts/sync-storyboard-styles.sh:26` |
| V-10 | A-BEHAVIOR | `StylePalette`: eight hex tokens as listed | CONFIRMED | `StylePickerListView.swift:216–223` (`bgInput 0x2a2a2c`, `bgInputHover 0x323234`, `border 0x38383a`, `fg 0xf5f5f7`, `fg3 0x8e8e93`, `fg4 0x6a6a6e`, `accent 0x0a84ff`, `accentSoft` = accent `.opacity(0.18)`), built with `Color(red:green:blue:)`; swatches use a private `hex(_:)` Scanner helper `:280–287` |
| V-11 | A-BEHAVIOR | `MidCenturySwatch.swift:11–19` records the `TimelineView` removal; every draw passes `t: 0` | CONFIRMED | `:12–19` comment; `:40–44` five calls with `t: 0`; `TimelineView` appears only in the comment |
| V-12 | A-BEHAVIOR | Slider ranges 1…50 / 1.0…20.0 by 0.5; 340 pt ideal (300…420); 5.5 rows; 6 pt spacing; 56 pt min row; 7 pt radius; 56 × 40 swatch | CONFIRMED | `GenerationSettingsPanel.swift:185,219`; `GenerationStudioView.swift:56` (`minWidth: 300, idealWidth: 340, maxWidth: 420`); `StylePickerListView.swift:22,23,25,95,130` |
| V-13 | A-DATA | `Localizable.xcstrings` is English only | CONFIRMED | `sourceLanguage` `en`; language set across all strings `{en}` |
| V-14 | A-BEHAVIOR | Picking a preset replaces the negative prompt and reveals the section | CONFIRMED | macOS `PromptInputPanel.swift:38–52` (`:47`, `:49` — reveal only when the text is non-empty); iOS `:54–58` |
| V-15 | A-BEHAVIOR | Model picker groups by engine and shows size and RAM; `isProActive` is a panel parameter | CONFIRMED | `GenerationSettingsPanel.swift:32,37–42,65,72,102` |
| **V-16** | A-BEHAVIOR | iOS renders a memory warning identified `generation.memoryWarning` (app logic the package must take through a footnote slot) | **REFUTED** | The identifier is declared (`AccessibilityID.swift:133`) and referenced by `VinetasUITests/MemoryGatingUITests.swift:89`, but **no view applies it** on either platform. Both panels show only the informational `Label("… GB RAM", systemImage: "memorychip")` (macOS `:116`, iOS `:132`); the macOS comment `:94–96` says memory is informational, no gate. See B-4 |
| V-17 | A-CONFIG | Vinetas pins SwiftVinetas `upToNextMajor` from 0.21.0 | CONFIRMED | `Vinetas.xcodeproj/project.pbxproj:1534–1537` |
| V-18 | A-CONFIG | Vinetas's own iOS test destination is iPhone 17 | CONFIRMED | `Makefile:14–17,178,186` (`IOS_SIM_OS ?= 26.1`) |

### Locus: precedents — SwiftAcervo at `v0.25.0`, SwiftEscribo at `v0.4.2` (read via `git show` at the tag)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| S-01 | A-CONFIG | One manifest ships `SwiftAcervo` and `SwiftAcervoUI`; UI depends on core | CONFIRMED | `Package.swift:13–22,37–40` at v0.25.0 |
| S-02 | A-API | `public enum AcervoUIAccessibility` of `public static let` string constants | CONFIRMED | `Sources/SwiftAcervoUI/AcervoUIAccessibility.swift:1–30` |
| S-03 | A-DATA | The precedent has no string catalogue, no `defaultLocalization`, bare literals | CONFIRMED | tag tree has no `.xcstrings`; `AcervoModelDownloadInterstitial.swift:294` |
| S-04 | A-FILE | A `SwiftAcervoUITests` target exists | CONFIRMED | `Package.swift:45–48` |
| S-05 | A-CONFIG | Precedent platforms `.macOS(.v26)`, `.iOS(.v26)` | CONFIRMED | `Package.swift:8–11` |
| E-01 | A-API | `WellLane.width(on:horizontalSizeClass:)` is a pure static with package-local `Platform` / `HorizontalSizeClass` enums; size class optional | CONFIRMED | `Sources/SwiftEscribo/EscriboWell.swift:146–166,181` at v0.4.2 |
| E-02 | A-FILE | A Swift Testing test enumerates platform × size class | CONFIRMED | `Tests/SwiftEscriboTests/EscriboWellTests.swift:75–87` |

(Probe beyond the requirements: SwiftEscribo v0.4.2 has no `EnvironmentValues`/`View` modifier pair to copy for `vinetasPanelLayout`; the shape must be written fresh.)

### Locus: toolchain (this Mac; CI is `macos-26` and UNVERIFIABLE offline)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| T-01 | A-CONFIG | Local Xcode 27 / Swift 6.4 / SDK 27 | CONFIRMED | `xcodebuild -version` 27.0; `swift --version` 6.4; both SDKs 27.0 |
| T-02 | A-API | `PreviewTrait` has `fixedLayout(width:height:)` and orientations, no device trait; `previewDevice` deprecated in the 27 SDK | CONFIRMED | DeveloperToolsSupport swiftinterface: `defaultLayout`, `sizeThatFitsLayout`, `fixedLayout(width:height:)`, `portrait`/`landscape`/`portraitUpsideDown`, `assistiveAccess`; no device trait. SwiftUI macOS interface `:15498` `previewDevice` `@available(…, deprecated: 27.0)` |
| T-03 | A-API | `.inspector(isPresented:content:)` and `inspectorColumnWidth(min:ideal:max:)` exist on macOS and iOS at the package floor | CONFIRMED | macOS interface `:14960–14970`, iOS `:14514–14525`, both `@available(iOS 17.0, macOS 14.0, *)`. The interface carries no doc comment; "sheet on compact" is Apple documentation, not verified here |
| T-04 | A-CONFIG | iPhone 17 on iOS 26.5 and iPad Pro 13-inch (M5) on 26.1 exist locally; 26.5 runtime installed | CONFIRMED | `xcrun simctl list devices available` / `list runtimes` |
| T-05 | A-CONFIG | `swift-format`, `otool`, `nm` resolve | CONFIRMED | `xcrun --find …` → XcodeDefault toolchain |
| T-06 | A-API | `.toggleStyle(.checkbox)` macOS-only; `.keyboardType` iOS-only; `.scrollDismissesKeyboard` on iOS | CONFIRMED | iOS interface `:15771–15777,15783–15787`: `checkbox` and `CheckboxToggleStyle` are declared but `@available(iOS, unavailable)`; `keyboardType` iOS `:4496`, absent on macOS; `scrollDismissesKeyboard` on both (`macOS :16012`, iOS `:15583`) |
| T-07 | A-API | `String(localized:bundle:)` exists; SwiftPM generates `Bundle.module` for resource targets | CONFIRMED / UNVERIFIABLE | Foundation interface `:21988–21993`. `Bundle.module` is SwiftPM behaviour, not in the SDK — see Unverifiable |

### Locus: Escribir at `ccc2ef5` (step 3; informational, hub-verified)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| X-01 | A-CONFIG | No SwiftVinetas dependency; packages resolve by remote tag only | CONFIRMED | `grep -ci vinetas Escribir.xcodeproj/project.pbxproj` = 0; three `XCRemoteSwiftPackageReference`s (`:1171–1187`), zero `XCLocalSwiftPackageReference` |
| X-02 | A-FILE | `docs/REQUIREMENTS-storyboard.md` is Escribir's side | CONFIRMED | Committed 2026-10-07 as `0452dbb` on `feature/vinetas-storyboard` (worktree `.claude/worktrees/vinetas-storyboard`); not on `development` |

## Blocking findings

#### B-1 — R-06 STALE: `VinetasModel` is not where the requirements say, and it is deprecated
**Claim**: *"`Sources/VinetasCLICore/VinetasCLICore.swift:63`, `VinetasModel(rawValue:)`"* (§ What exists today, line 82) and § 1.2's test *"`VinetasModel(rawValue: summary.cliName)` resolves for both"*.
**Found**: `Sources/SwiftVinetas/Vinetas.swift:1749–1755` — the enum is in the core library, marked `@available(*, deprecated, message: "Use ModelDescriptor types directly …")`. The CLI still calls it at six sites.
**Impact**: The `cliName` round-trip test in `SwiftVinetasTests` would compile against a deprecated symbol and emit a warning; the citation sends a sortie agent to the wrong file.
**Options**:
1. Amend line 82 to cite `Sources/SwiftVinetas/Vinetas.swift:1753` and note the deprecation; keep the test but assert against `VinetasModel.allCases.map(\.rawValue)` with the deprecation silenced locally *(recommended; no design change)*.
2. Drop the `VinetasModel` round-trip and assert `cliName` against the literal strings the CLI's `--model` help documents (`VinetasCLICore.swift:63`).

#### B-2 — R-11 STALE: `README.md` carries no `0.21.0-dev` literal
**Claim**: *"`"0.21.0-dev"` … also in `AGENTS.md:8` and `README.md:42, 235`"* (§ What exists today, lines 139–141).
**Found**: `README.md:42` is `from: "0.21.0"` (a consumer pin example); `:235` is the v0.21.0 release note. `git grep` finds the literal only in `Vinetas.swift:48,1125`, `AGENTS.md:8`, and the requirements file itself.
**Impact**: None on sorties (no sortie edits a version literal); a wrong instruction to `ship-swift-library` could touch README lines that should not change.
**Options**:
1. Amend the sentence to drop `README.md` *(recommended)*.

#### B-3 — V-07 STALE: five UI-test files, not four
**Claim**: *"Four UI-test files drive the panel through nineteen strings"* (§ What exists today, line 98).
**Found**: five — the three macOS files plus `VinetasIOSUITests/GenerationIntegrationTests.swift` and `VinetasIOSUITests/VinetasIOSUITests.swift`. The latter, at `:275`, is the only test anywhere that asserts the inline `stylePicker.list`.
**Impact**: The honest list's third bullet is right in substance; the Vinetas-adoption mission needs the file name.
**Options**:
1. Amend to "five" and name `VinetasIOSUITests.swift:275` as the one that asserts the inline list *(recommended)*.

#### B-4 — V-16 REFUTED: no view renders `generation.memoryWarning`
**Claim**: *"a `@ViewBuilder footnote` slot rendered under the model picker, so iOS's memory warning (`generation.memoryWarning`, app logic) is passed in rather than known by the package"* (§ 2.3, lines 315–317), and the nineteen-identifier contract including `generation.memoryWarning` (line 106).
**Found**: The identifier is declared (`AccessibilityID.swift:133`) and a macOS UI test queries it (`MemoryGatingUITests.swift:89`), but no view on either platform applies it. Both panels show only the informational RAM label. Memory gating was removed from the app and the package (standing directive).
**Impact**: The footnote slot's stated justification is false. The slot itself is harmless and cheap; `VinetasUIAccessibility.generationMemoryWarning` would be a dead constant that a stale macOS UI test still names.
**Options**:
1. Keep the footnote slot as a generic host slot, reword § 2.3 to say so, and keep the constant for identifier-compatibility with the existing (stale) UI test *(recommended; no API change)*.
2. Drop the footnote slot and the constant; record that `MemoryGatingUITests.swift:89` is dead in the Vinetas-adoption mission.

## Local Dependency Map

`Package.resolved` is gitignored (`.gitignore:13–14`); there is no committed lock. On this
machine every `intrusive-memory` dependency resolves to its sibling directory; on CI each
resolves to the newest release in range. The two new targets depend on none of them.

| Dependency | Declared | Resolved here | Local checkout | Local HEAD vs newest tag | Status |
|------------|----------|---------------|----------------|--------------------------|--------|
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.3` | `../flux-2-swift-mlx` (path) | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | `9a36b263`, 1 past `v3.4.3`, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` | `../SwiftAcervo` (path) | `…/pkg/SwiftAcervo` | `13e2879b`, 4 past `v0.25.0`, **dirty** | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` | `../SwiftTuberia` (path) | `…/pkg/SwiftTuberia` | `d74977ac`, 1 past `v0.9.0`, **dirty** | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.2` | `../pixart-swift-mlx` (path) | `…/pkg/pixart-swift-mlx` | `3ce25413`, 1 past `v0.8.2`, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/glosa-av | `from: 0.8.1` | `../glosa-av` (path) | `…/pkg/glosa-av` | `efb640ff`, 1 past `v0.8.1`, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | `from: 7.2.5` | `../SwiftCompartido` (path) | `…/pkg/SwiftCompartido` | `baf830a9`, 19 past `v7.2.5`, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| marcprux/universal | `from: 5.3.0` | `5.3.0` (`7919463c`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | `1.8.2` (`6a52f325`) | — | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor: 0.7.1` | `0.7.1` (`e4e01cb5`) | `~/Projects/swift-tokenizers` | `37f999a4`, detached near `0.6.2` | LOCAL_BEHIND |
| apple/swift-certificates | `from: 1.0.0` | `1.19.4` (`449dbbec`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-crypto | `from: 3.0.0` | `3.15.1` (`95ba0316`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-asn1 | `from: 1.0.0` | `1.7.1` (`a9a5efd4`) | — | — | NO_LOCAL_CHECKOUT |

`.build/checkouts/` holds copies of the six sibling packages at their release tags (e.g.
SwiftAcervo `87ec22c3` = `v0.25.0`) from a previous CI-style resolve; they are not what the
local build uses and were not used for verification.

Repositories the mission reads but does not depend on:

| Repository | Local checkout | HEAD | Note |
|---|---|---|---|
| intrusive-memory/Vinetas | `~/Projects/apps/Vinetas` | `0c25a3d` on `docs/dossier-integration`, clean | Matches the revision the requirements name; source for § 1.1 and § 2 |
| intrusive-memory/Vinetas | `~/Projects/worktrees/Vinetas-personaje` | `0c25a3d` on `requirements/personaje`, dirty | Worktree, same commit; not used |
| intrusive-memory/Escribir | `~/Projects/apps/Escribir` | `ccc2ef5` on `development` | Step 3 host; no SwiftVinetas dependency |
| intrusive-memory/Escribir | `…/Escribir/.claude/worktrees/vinetas-storyboard` | `0452dbb` on `feature/vinetas-storyboard` | Holds the committed storyboard requirements |
| intrusive-memory/SwiftAcervo | `…/pkg/SwiftAcervo` | dirty | Precedent; verified at `v0.25.0` via `git show` |
| intrusive-memory/SwiftEscribo | `…/pkg/SwiftEscribo` | `a8f8d6e`, dirty | Precedent; verified at `v0.4.2` via `git show` |

### Drift and ambiguity notes

- **All six sibling dependencies are ahead of their release tags, two with uncommitted
  changes.** Local builds of the existing targets see code CI does not. Nothing in this
  report rests on drifted source: the new targets depend on none of them, and every
  precedent was read at its tag.
- **The local toolchain is a major version ahead of CI** (Xcode 27 / Swift 6.4 here;
  `macos-26` there). CI is the truth for the UI target: no API newer than the OS 26 SDKs.
- **CI is unpinned by design.** No committed lock; each run resolves the newest release in
  range.
- **The Makefile's iOS destination is an iPad on 26.1**, while the requirements' new
  `unit-tests-ios` job names iPhone 17 on 26.5. Both simulators exist locally. The plan must
  decide which the Makefile default becomes, or parameterise it.
- **`pixart-integration.yml` also runs on pull requests** to `main` and `development`; the
  mission must keep it green, not only `tests.yml`.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| T-07b | SwiftPM synthesises `Bundle.module` for a target that declares resources, and `String(localized:bundle: .module)` with an `.xcstrings` requires `defaultLocalization` in the manifest | SwiftPM behaviour, not in the SDK; no build run during recon | The first `VinetasUI` sortie's `make build` — add `defaultLocalization: "en"` to the manifest in the scaffold sortie and treat a missing-`Bundle.module` compile error as the signal |
| T-03b | SwiftUI `.inspector` presents as a sheet on iPhone (compact) | swiftinterface carries no doc comments; not run | Apple docs; moot for this mission because § 2.6 makes the modifier a no-op on iPhone |
| — | Package resolution cost in a host (OQ-1) | Measured in Escribir's mission, by design | Escribir § 5 |

## Handoff to breakdown

- Every `CONFIRMED` row is safe as a sortie entry criterion without re-checking.
- The four blocking findings are doc amendments; once applied, re-stamp this report
  (`requirements_sha256`) rather than re-running the spokes — no source changed.
- Carry into the plan, from the evidence above:
  - `ModelDescriptor` also requires `license` and `componentIds`; the `summary` default
    implementation ignores them.
  - `VinetasModel` is deprecated in `Vinetas.swift:1753`; silence the warning in the one
    round-trip test or assert against the raw strings.
  - The move's blast radius outside Core/ is 7 source files and 20 test files that name
    the three types; the `@_exported import` must land in the same sortie as the move.
  - `StylePalette` is an `enum` of static `Color`s built from `Color(red:green:blue:)`;
    `swatchPalette` returns `(Color, Color, Color)` — the triples in `StyleSwatchPalette`
    come from the swatch colours' hex strings (`StylePickerListView.swift:232–287`).
  - `stylePicker.promptTextDisclosure` has no constant today; `VinetasUIAccessibility`
    adds one.
  - iOS's `horizontalSizeClass` branch for Steps/Guidance is at iOS
    `GenerationSettingsPanel.swift:52–56`; the 140/100 editor height at
    `PromptInputPanel.swift:73`.
  - Makefile `DESTINATION_IOS` default is the iPad on 26.1; the new iOS job needs its own
    destination value.
  - Add `defaultLocalization: "en"` to `Package.swift` in the `VinetasUI` scaffold sortie.
- The stale root `EXECUTION_PLAN.md` (2026-10-06, popup metaphor) must be regenerated, not
  resumed.

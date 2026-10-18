---
type: recon-report
state: current
requirements_file: docs/REQUIREMENTS-vinetas-ui.md
requirements_sha256: 85a931d780ff7d3f6f764832cb2df1026bff72cf93446c430a45976d402990cd
project_head: b7872158a692b6fce6f87db5e58e216c1ebd1ff3
search_root: ~/Projects
generated: 2026-10-18
verdict: CLEAR
supersedes: the 2026-10-07 BLOCKED report (archived at docs/incomplete/vinetas-ui-recon-2026-10-07/), whose four blocking findings were doc-citation errors fixed in b787215
---

# RECON_REPORT.md — SwiftVinetas `VinetasUI` (inspector element)

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**CLEAR** — 54 assumptions checked across five loci: 54 confirmed (one with an unverifiable
half), 0 stale, 0 refuted, 0 confirmed-local-only.

Source under audit is unchanged since the 2026-10-07 recon: SwiftVinetas `development` at
`d88dd27` (local `b787215` differs only by `docs/REQUIREMENTS-vinetas-ui.md`), the Vinetas app
at `0c25a3d` (clean), precedents read at their tags. The four amended sentences (B-1…B-4 of the
superseded report) now match the code. The root `EXECUTION_PLAN.md` from 2026-10-06 was the
popup-metaphor plan and has been archived beside the old report; `breakdown` must generate a
fresh one.

## Assumption Findings

### Locus: repo — SwiftVinetas at `b787215` (`development`; source identical to `origin/development` `d88dd27`)

| ID | Kind | Claim (§ What exists today unless noted) | Verdict | Evidence |
|----|------|-------|---------|----------|
| R-01 | A-FILE | `AspectRatio`, `StyleConfig`, `VinetasError`, `VinetasModelInfo` import Foundation only; `ResolutionClamp` imports Metal under `#if canImport(Metal)` and calls `MTLCreateSystemDefaultDevice()` ~71 | CONFIRMED | `Core/{AspectRatio,StyleConfig,VinetasError,VinetasModelInfo}.swift:1`; `Core/ResolutionClamp.swift:1,3–4,71`. The other seven Core/ files import CoreGraphics/Flux2Core/ImageIO/YAML/MLX/os/Darwin and are not part of the move |
| R-02 | A-INVARIANT | `AspectRatio.swift:105` calls `ResolutionClamp.clampedDimensions`; the three moving files are a closed set | CONFIRMED | `Core/AspectRatio.swift:105` (inside `#if os(macOS)`). `Vinetas.swift:991` also calls the public `clampedDimensions` — a caller, not a dependency of the set |
| R-03 | A-INVARIANT | `attentionHeadsWorstCase` / `scoreBytes` reached only by their two test files; no non-public member used elsewhere in `Sources/` | CONFIRMED | decls `Core/ResolutionClamp.swift:39,43` (internal), `:61` internal, `:130` private; uses `Tests/SwiftVinetasTests/ResolutionClampTests.swift:20,22`, `AspectRatioTests.swift:172,174`; `safetyFraction` hits in VinetasMemory* are an unrelated parameter |
| R-04 | A-API | `ModelDescriptor` imports Foundation only and requires the eight `ModelSummary` fields; no `cliName` / `summary` today | CONFIRMED | `Engine/ModelDescriptor.swift:1,12`; requirements at `:15,18,21,24,27,30,33,36,39,49`; `componentIds` defaulted `:59`. Also requires `license: ModelLicense` (`:24`). grep `cliName\|summary` in Engine/: none |
| R-05 | A-API | `Flux2ModelDescriptor.klein4B` (`Flux2Engine.swift:35`, engineID `"flux2"`), `PixArtModelDescriptor.sigmaXL` (`PixArtEngine.swift:39`); both `AspectRatio.allCases`; one Flux2 static only | CONFIRMED | `Flux2Engine.swift:16,35,43,70`; `PixArtEngine.swift:39,42,48`. No 9B |
| R-06 | A-API | *(amended)* `VinetasModel` is `public enum … String, Sendable, Codable, CaseIterable` at `Vinetas.swift:1753`, cases `klein4b` / `pixartSigma = "pixart-sigma"`, deprecated at `:1749–1751`; CLI resolves `--model` through `VinetasModel(rawValue:)` at six sites; help string `VinetasCLICore.swift:63` | CONFIRMED | `Vinetas.swift:1749–1751,1753–1755`; `VinetasCLICore.swift:164,338,447,581,916,1034`. **Nit:** the `@Option(… help:)` spans `:62–63` with the literal on `:62` |
| R-06b | A-API | *(amended § 1.2 test)* `VinetasModel.allCases.map(\.rawValue)` == `["klein4b", "pixart-sigma"]` | CONFIRMED | `Vinetas.swift:1753–1755`; the CLI already does exactly this at `VinetasCLICore.swift:165` |
| R-07 | A-CONFIG | Products, `SwiftVinetas` target deps (Flux2Core, SwiftAcervo, Tuberia, TuberiaCatalog, PixArtBackbone, YAML, JSON), platforms `.macOS(.v26)`/`.iOS(.v26)`, no `defaultLocalization`, no engine-free target | CONFIRMED | `Package.swift:45–47,49–62,155–164`; other targets `:169,189,201,215` all depend on engines or SwiftVinetas; `sibling(` at `:23,35,81,92,101,110,117,126` |
| R-08 | A-INVARIANT | No SwiftUI, no `.xcstrings`, no `Resources/` | CONFIRMED | `grep -rn 'import SwiftUI' Sources Tests` empty; `git ls-files \| grep -i 'xcstrings\|^Resources'` empty (`bin/*.bundle/Resources` is untracked build output) |
| R-09 | A-CONFIG | `tests.yml`: one job `unit-tests` "Unit Tests (macOS)" on `macos-26`, `make build` → `make test-unit`; no lint step; `pixart-integration.yml` also on PRs to main/development | CONFIRMED | `.github/workflows/tests.yml` (plus an Acervo-warning log check and a summary step — neither is lint); `pixart-integration.yml:33–35` |
| R-10 | A-CONFIG | `lint` = `swift format -i -r .`; `test-unit`/`test-unit-ios` filter `SwiftVinetasTests`; `build-ios` exists; no `lint-check`/`verify-ui-isolation`; `DESTINATION_IOS` = iPad Pro 13-inch (M5) on 26.1 | CONFIRMED | `Makefile:291–292, 125/131, 239/245, 96, 32`; `.PHONY:68` lists neither new target |
| R-11 | A-CONFIG | *(amended)* `"0.21.0-dev"` in `Vinetas.swift:48,1125` and `AGENTS.md:8`; **not** in `README.md` | CONFIRMED | `git grep -n '0.21.0-dev'` → `AGENTS.md:8`, `Vinetas.swift:48,1125`, plus the requirements doc's own `:39,:145`. `README.md:42` = `from: "0.21.0"`, `:235` = release note |
| R-12 | A-CONFIG | A release tag ships a remote-only manifest | CONFIRMED | `git show v0.21.0:Package.swift \| grep -n 'sibling(\|path:'` → no match (185-line file) |
| R-13 | A-FILE | Three Core test files exist, Swift Testing, `@testable import SwiftVinetas` | CONFIRMED | `Tests/SwiftVinetasTests/{AspectRatio,ResolutionClamp,StyleConfig}Tests.swift:1–5` |
| R-14 | A-INVARIANT | All new names are free | CONFIRMED | `git grep -nw` over Sources, Tests, Makefile, Package.swift: zero hits for all 13 names |
| R-15 | A-FILE | `AGENTS.md`/`README.md` exist, no Products section; no `docs/VinetasUI.md` | CONFIRMED | `ls`; `grep -ni products AGENTS.md README.md` empty |
| R-16 | A-INVARIANT | No module-qualified or reflected use of the three types | CONFIRMED | `git grep` for `SwiftVinetas\.(AspectRatio\|ResolutionClamp\|StyleConfig)`, `String(reflecting:`, `_typeName`, `NSClassFromString` in Sources/Tests: none. Blast radius: 11 source files (incl. 4 other Core/ files, both engines, ModelDescriptor, PanelRequest, Vinetas, StoryboardCommand, VinetasCLICore), 4 GPU-test files, 13 unit-test files + the three own test files |
| R-17 | A-CONFIG | `Package.resolved` gitignored, not tracked | CONFIRMED | `.gitignore:13–14`; `git ls-files Package.resolved` empty |
| R-18 | A-FILE | `SwiftVinetasGPUTests` exists, excluded from `test-unit`, names `StyleConfig`; `Sources/vinetas` names none of the three | CONFIRMED | dir present; `Makefile:131`; `AllModelsExampleTests.swift:141`, `BatchIntegrationTests.swift:147`, `PixArtIntegrationTests.swift:187`; `grep -rnw … Sources/vinetas` empty |

### Locus: source — Vinetas app at `0c25a3d` (`docs/dossier-integration`, clean, HEAD == cited revision)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| V-01 | A-FILE | Seven panel files; `StyleSwatchView` / `StylePalette` / `swatchPalette` in `StylePickerListView.swift`; `MidCenturySwatch` is a static `Canvas`; iOS has no own list file, reaches the two shared files via the synchronized root group | CONFIRMED | `wc -l`: macOS 233/329/475/294/191, iOS 303/351 (iOS files live at `VinetasIOS/Views/GenerationStudio/`); `StylePickerListView.swift:158,215,232`; `MidCenturySwatch.swift:27`; `project.pbxproj:151–170` exception set excludes the other studio files only; iOS `PromptInputPanel.swift:128` uses the list |
| V-02 | A-BEHAVIOR | No popup picker; `prompt.stylePicker` is a constant no view references | CONFIRMED | `StylePickerListView(selection:)` at macOS `PromptInputPanel.swift:100`, iOS `:128`; `promptStylePicker` declared `AccessibilityID.swift:110` (+ mirrors `:96`, `:105`), referenced nowhere else |
| V-03 | A-BEHAVIOR | iOS branches on `horizontalSizeClass` for Steps/Guidance; 140/100 editor height | CONFIRMED | iOS `GenerationSettingsPanel.swift:34,52`; iOS `PromptInputPanel.swift:73` |
| V-04 | A-API | `StoryboardStyle`: 19 presets + `.custom`, Foundation only, `swatchPalette` elsewhere | CONFIRMED | `Vinetas/Models/StoryboardStyle.swift:8,18–37` (20 cases); no `swatchPalette` in file |
| V-05 | A-API | `AvailableModel` projects the two descriptors; Pro is `engineID == "flux2"`; imports SwiftData + SwiftVinetas; `recommendedSteps` overrides FLUX.2 to 8 | CONFIRMED | `AvailableModel.swift:9–11,62–63,80,85,88`. Second static is named `pixartSigmaXL`; the file also imports `SwiftAcervoUI` |
| V-06 | A-DATA | `AccessibilityID.swift` mirrored non-verbatim into both UI-test targets; the nineteen strings exist; `stylePicker.promptTextDisclosure` is a raw literal in both panels; `prompt.caption` nowhere | CONFIRMED | all three copies `diff` non-empty; constants `:36,37,110,126,127,133`; literal at macOS `PromptInputPanel.swift:137`, iOS `:172`; `prompt.caption` no hits. `generationMemoryWarning` is absent from the iOS mirror |
| V-07 | A-FILE | *(amended)* Five UI-test files drive the panel (three macOS, two iOS); only `VinetasIOSUITests.swift:275` asserts `stylePicker.list` | CONFIRMED | identifier grep over both UI-test dirs hits exactly the five named files; `:275` is the only non-declaration `stylePickerList` reference. The directories hold other files (Markup/ModelManagement/Paywall/LaunchTests) that do not touch the panel — the spoke's "refuted in part" was about those, which the claim never excludes |
| V-08 | A-BEHAVIOR | `AppDefaults.swift:72–73` stores the default style's `promptText`, recovered with `StoryboardStyle.from(promptText:)`; no other `StoryboardStyle` persistence | CONFIRMED | `AppDefaults.swift:71–73` (`defaultStylePrompt: String`, fallback `StoryboardStyle.photoRealistic.promptText`); recovery `GenerationViewModel.swift:430`. **Carry:** the defaults key is `defaultStylePrompt`, and the recovery call is in the view model, not in `AppDefaults` |
| V-09 | A-DATA | Fixture JSON 19 entries, `#filePath` lookup, sync script → `vinetas-skills` | CONFIRMED | `VinetasTests/Fixtures/storyboard-styles.json` (19 under a `styles` key; keys id/displayName/genre/prompt/negative); `StoryboardStyleCatalogTests.swift:49`; `Scripts/sync-storyboard-styles.sh:26` |
| V-10 | A-BEHAVIOR | `StylePalette`: eight hex tokens; private `hex(_:)` | CONFIRMED | `StylePickerListView.swift:216–223,278` |
| V-11 | A-BEHAVIOR | `MidCenturySwatch.swift:11–19` records `TimelineView` removal; every draw passes `t: 0` | CONFIRMED | `:12–19` comment (`:16` the only `TimelineView`); `:40–44` |
| V-12 | A-BEHAVIOR | Sliders 1…50 / 1.0…20.0 by 0.5; 300/340/420 pt; 5.5 rows; 6 pt spacing; 56 pt row; 7 pt radius; 56×40 swatch | CONFIRMED | `GenerationSettingsPanel.swift:185,219`; `GenerationStudioView.swift:56`; `StylePickerListView.swift:22 (rowSpacing = 6, hub-verified),23,25,95,130–134` |
| V-13 | A-DATA | `Localizable.xcstrings` English only | CONFIRMED | `Vinetas/Localizable.xcstrings`: sourceLanguage `en`, localization keys `{en}` |
| V-14 | A-BEHAVIOR | Preset pick replaces the negative prompt and reveals the section when non-empty | CONFIRMED | macOS `PromptInputPanel.swift:38–52`; iOS `:51–57` |
| V-15 | A-BEHAVIOR | Model picker grouped by engine with size + RAM; `isProActive` a parameter | CONFIRMED | `GenerationSettingsPanel.swift:32,65,72,102` |
| V-16 | A-BEHAVIOR | *(amended)* No view renders `generation.memoryWarning`; constant declared `AccessibilityID.swift:133`, referenced only by `MemoryGatingUITests.swift:89`; panels show only the RAM label | CONFIRMED | repo-wide grep: constant at `AccessibilityID.swift:133` + macOS mirror `:116`; sole use `MemoryGatingUITests.swift:89`; no `accessibilityIdentifier(…generationMemoryWarning)` in `Vinetas/` or `VinetasIOS/`; `memorychip` labels macOS `GenerationSettingsPanel.swift:116`, iOS `:132` |
| V-17 | A-CONFIG | Vinetas pins SwiftVinetas `upToNextMajor` from 0.21.0 | CONFIRMED | `project.pbxproj:1532–1539` |
| V-18 | A-CONFIG | Vinetas's own iOS test destination is iPhone 17 | CONFIRMED | `Makefile:14 (IOS_SIM_NAME ?= iPhone 17), :15 (IOS_SIM_OS ?= 26.1), :17` |

### Locus: precedents — SwiftAcervo at `v0.25.0`, SwiftEscribo at `v0.4.2` (read with `git show` at the tag; both checkouts have moved on)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| S-01 | A-CONFIG | One manifest ships `SwiftAcervo` + `SwiftAcervoUI`; UI depends on core | CONFIRMED | `Package.swift:16–19,31–34` @ v0.25.0 |
| S-02 | A-API | `public enum AcervoUIAccessibility` of `public static let` strings | CONFIRMED | `Sources/SwiftAcervoUI/AcervoUIAccessibility.swift:26`; 31 `public static let`, 0 `static var` |
| S-03 | A-DATA | No string catalogue, no `defaultLocalization`, bare literals | CONFIRMED | no `.xcstrings` in the tag tree; `Package.swift` lacks `defaultLocalization`; `AcervoModelDownloadInterstitial.swift:109–117`. Its doc comment `:34–35` mentions a catalogue that does not exist |
| S-04 | A-FILE | `SwiftAcervoUITests` target exists | CONFIRMED | `Package.swift:51–54` |
| S-05 | A-CONFIG | Platforms `.macOS(.v26)`, `.iOS(.v26)` | CONFIRMED | `Package.swift:7–10` |
| E-01 | A-API | `WellLane.width(on:horizontalSizeClass:)` pure static with package-local `Platform` / optional `HorizontalSizeClass` | CONFIRMED | `Sources/SwiftEscribo/EscriboWell.swift:181` (body `:181–187`); enums nested in `WellLane` at `:143,146,163` |
| E-02 | A-FILE | A Swift Testing test enumerates platform × size class | CONFIRMED | `Tests/SwiftEscriboTests/EscriboWellTests.swift:4,75–79,82–86` (explicit `#expect` lines, every combination incl. nil) |
| E-03 | A-API | No `EnvironmentValues`/`EnvironmentKey` pattern to copy for `vinetasPanelLayout` | CONFIRMED | `git grep -n -E 'EnvironmentValues\|EnvironmentKey' v0.4.2` → nothing; the shape must be written fresh |

### Locus: toolchain (this Mac; CI is `macos-26` and UNVERIFIABLE offline)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| T-01 | A-CONFIG | Local Xcode 27 / Swift 6.4 / SDK 27 | CONFIRMED | Xcode 27.1 (27A9275); Swift 6.4; MacOSX27.0.sdk, iPhoneOS27.1.sdk, iPhoneSimulator27.1.sdk |
| T-02 | A-API | `PreviewTrait` has `fixedLayout(width:height:)` + orientations, no device trait; `previewDevice` deprecated | CONFIRMED | DeveloperToolsSupport `arm64e-apple-macos.swiftinterface:163,166,169,175,179–188` (orientations are `portrait`, `landscapeLeft`, `landscapeRight`, `portraitUpsideDown`; `assistiveAccess` `:151`); SwiftUI macOS interface `:15498–15499` `deprecated: 27.0` |
| T-03 | A-API | `.inspector(isPresented:content:)` + `inspectorColumnWidth(min:ideal:max:)` on macOS and iOS, `iOS 17 / macOS 14` | CONFIRMED | macOS interface `:14960,14965,14967`; iOS `:14515,14520,14522` (`ideal` required, `min`/`max` default nil; an `inspectorColumnWidth(_:)` overload also exists) |
| T-04 | A-CONFIG | iPhone 17 and iPad Pro 13-inch (M5) simulators exist; iOS 26.5 and 26.1 runtimes installed | CONFIRMED | `simctl list devices available` shows both (one per runtime; an iPhone 17 is Booted); `simctl list runtimes`: iOS 18.4, 18.5, 26.0 ×2, 26.1, 26.3, 26.5, 27.0 ×3. The spoke graded this STALE because more runtimes are installed than the two named; the claim asserts presence, not exclusivity, and the cited evidence confirms it |
| T-05 | A-CONFIG | `swift-format`, `otool`, `nm` resolve | CONFIRMED | `xcrun --find` → XcodeDefault toolchain for all three |
| T-06 | A-API | `.checkbox` macOS-only; `keyboardType` iOS-only; `scrollDismissesKeyboard` on both | CONFIRMED | iOS interface `:15770–15777,15781–15787,15801–15804` (`@available(iOS, unavailable)`); `keyboardType` iOS `:4494–4496`, macOS `grep -c` = 0; `scrollDismissesKeyboard` iOS `:15583`, macOS `:16012` |
| T-07 | A-API | `String(localized:bundle:)` exists; SwiftPM synthesises `Bundle.module` for resource targets | CONFIRMED / UNVERIFIABLE | Foundation macOS interface `:21988–21993` (four `init(localized:…bundle:…)` overloads). `Bundle.module` is SwiftPM behaviour — see Unverifiable |

### Locus: Escribir (step-3 host; informational)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| X-01 | A-CONFIG | No SwiftVinetas dependency; packages resolve by remote version requirement only | CONFIRMED | `grep -ci vinetas project.pbxproj` = 0 at both `ccc2ef5` (cited) and `e07091c` (current development); `XCLocalSwiftPackageReference` = 0 at both; remote refs 3 → 4 (`swift-markdown` added; SwiftEscribo floor now 0.4.4, SwiftProyecto 5.3.0, SwiftRepositorio 0.2.1) |
| X-02 | A-FILE | `docs/REQUIREMENTS-storyboard.md` is on `feature/vinetas-storyboard`, not on `development` | CONFIRMED | `cat-file -e 0452dbb:docs/REQUIREMENTS-storyboard.md` ok; absent from the whole tree at `e07091c`. (Escribir PR #71 carries it, base `development`) |

## Blocking findings

None.

## Local Dependency Map

`Package.resolved` is gitignored (`.gitignore:13–14`); there is no committed lock. The root
`Package.resolved` present locally lists only the non-sibling pins — every `intrusive-memory`
dependency resolves to its sibling directory here (`sibling(…)` helper, `Package.swift:23–40`),
while CI resolves each to the newest release in range. **Every sibling's `from:` floor equals its
newest tag, so CI resolves exactly the tag named.** The two new targets (`VinetasVocabulary`,
`VinetasUI`) depend on none of these.

| Dependency | Declared | CI resolves | Local checkout | Local HEAD vs tag | Status |
|------------|----------|-------------|----------------|-------------------|--------|
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.3` | `v3.4.3` | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | `9a36b26`, 1 ahead, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` | `v0.25.0` | `…/pkg/SwiftAcervo` | `13e2879`, 4 ahead, **dirty** | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` | `v0.9.0` | `…/pkg/SwiftTuberia` | `d74977a`, 1 ahead, **dirty** | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.2` | `v0.8.2` | `…/pkg/pixart-swift-mlx` | `3ce2541`, 1 ahead, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/glosa-av | `from: 0.8.1` | `v0.8.1` | `…/pkg/glosa-av` | `efb640f`, 1 ahead, clean | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | `from: 7.2.5` | `v7.2.5` | `…/pkg/SwiftCompartido` | `8894c6e`, 20 ahead, **dirty** | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| marcprux/universal | `from: 5.3.0` | `5.3.0` (`7919463c`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | `1.8.2` (`6a52f325`) | — | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor: 0.7.1` | `0.7.1` (`e4e01cb5`) | `~/Projects/swift-tokenizers` | `37f999a`, detached near `0.6.2` | LOCAL_BEHIND |
| apple/swift-certificates | `from: 1.0.0` | `1.19.4` (`449dbbec`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-crypto | `from: 3.0.0` | `3.15.1` (`95ba0316`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-asn1 | `from: 1.0.0` | `1.7.1` (`a9a5efd4`) | — | — | NO_LOCAL_CHECKOUT |

`.build/checkouts/` holds the six sibling packages at their release tags from an earlier
CI-style resolve (e.g. SwiftAcervo `87ec22c` = `v0.25.0`); the local build does not use them and
they were not used for verification.

Repositories the mission reads but does not depend on:

| Repository | Local checkout | HEAD | Note |
|---|---|---|---|
| intrusive-memory/Vinetas | `~/Projects/apps/Vinetas` | `0c25a3d` on `docs/dossier-integration`, clean | Matches the cited revision; source for § 1.1 and § 2 |
| intrusive-memory/Vinetas | `~/Projects/worktrees/Vinetas-personaje` | `0c25a3d` on `requirements/personaje`, dirty | Worktree, same commit; not used (AMBIGUOUS by path, resolved by the authoritative `apps/` checkout) |
| intrusive-memory/Escribir | `~/Projects/apps/Escribir` | `e07091c` on `development` | Step-3 host; still no SwiftVinetas dependency |
| intrusive-memory/Escribir | `…/Escribir/.claude/worktrees/vinetas-storyboard` | `0452dbb` on `feature/vinetas-storyboard` | Holds the storyboard requirements (PR #71) |
| intrusive-memory/SwiftAcervo | `…/pkg/SwiftAcervo` | dirty | Precedent; verified at `v0.25.0` via `git show` |
| intrusive-memory/SwiftEscribo | `…/pkg/SwiftEscribo` | `5a82cde` (newest tag `v0.4.4`) | Precedent; verified at `v0.4.2` via `git show` |

### Drift and ambiguity notes

- **All six sibling dependencies are ahead of their release tags, three with uncommitted
  changes.** Local builds of the existing targets see code CI does not. Nothing in this report
  rests on drifted source: the new targets depend on none of them, and every precedent was read
  at its tag.
- **The local toolchain is a major version ahead of CI** (Xcode 27.1 / Swift 6.4 here; `macos-26`
  there). CI is the truth for the UI target: no API newer than the OS 26 SDKs.
- **CI is unpinned by design.** No committed lock; each run resolves the newest release in range
  — today that is exactly the `from:` floors.
- **The Makefile's iOS destination is an iPad on 26.1** (`Makefile:32`), while the requirements'
  new `unit-tests-ios` job names iPhone 17 on 26.5. Both simulators exist locally. The plan must
  decide which the Makefile default becomes, or parameterise it.
- **`pixart-integration.yml` also runs on pull requests** to `main` and `development`; the
  mission must keep it green, not only `tests.yml`.
- **Escribir moved** from the cited `ccc2ef5` to `e07091c` (added `swift-markdown`, raised three
  floors); nothing the requirements rest on changed.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| T-07b | SwiftPM synthesises `Bundle.module` for a target that declares resources, and `String(localized:bundle: .module)` with an `.xcstrings` requires `defaultLocalization` in the manifest | SwiftPM behaviour, not in the SDK; no build run during recon | The first `VinetasUI` sortie's `make build` — add `defaultLocalization: "en"` in the scaffold sortie and treat a missing-`Bundle.module` compile error as the signal |
| T-03b | SwiftUI `.inspector` presents as a sheet on iPhone (compact) | swiftinterface carries no doc comments; not run | Apple docs; moot because § 2.6 makes the modifier a no-op on iPhone |
| — | Package resolution cost in a host (OQ-1) | Measured in Escribir's mission, by design | Escribir § 5 |
| — | CI (`macos-26`) SDK surface | Offline | The first CI run of the `VinetasUI` scaffold sortie |

## Handoff to breakdown

- Every `CONFIRMED` row is safe as a sortie entry criterion without re-checking.
- `UNVERIFIABLE` items become `## Open Questions` entries or explicit verification steps in the
  first dependent sortie's entry criteria — never a silent assumption.
- Carry into the plan, from the evidence above:
  - `ModelDescriptor` also requires `license` and `componentIds` (defaulted); the `summary`
    default implementation ignores them.
  - `VinetasModel` is deprecated at `Vinetas.swift:1749–1751`; the one round-trip test asserts
    against `allCases.map(\.rawValue)` with the deprecation warning silenced locally.
  - The CLI `--model` help literal is at `VinetasCLICore.swift:62` (the `@Option` spans 62–63).
  - The move's blast radius outside the three files is 11 source files and 20 test files that
    name the types; the `@_exported import` must land in the same sortie as the move.
  - `StylePalette` is an `enum` of static `Color`s; `swatchPalette` returns `(Color, Color, Color)`
    — the triples in `StyleSwatchPalette` come from the swatch hex strings
    (`StylePickerListView.swift:216–287`).
  - `stylePicker.promptTextDisclosure` has no constant today; `VinetasUIAccessibility` adds one.
    `generationMemoryWarning` is absent from the iOS mirror; the macOS mirror is the only copy.
  - `AppDefaults` stores the style's prompt text under the key `defaultStylePrompt`; recovery via
    `StoryboardStyle.from(promptText:)` is in `GenerationViewModel.swift:430`.
  - `AvailableModel`'s second static is `pixartSigmaXL`; the file imports `SwiftAcervoUI`.
  - iOS `horizontalSizeClass` branch for Steps/Guidance at iOS `GenerationSettingsPanel.swift:52`;
    the 140/100 editor height at iOS `PromptInputPanel.swift:73`.
  - Makefile `DESTINATION_IOS` default is the iPad on 26.1; the new iOS job needs its own value.
  - Add `defaultLocalization: "en"` to `Package.swift` in the `VinetasUI` scaffold sortie.
  - SwiftEscribo has no environment-key precedent (E-03); `vinetasPanelLayout` is written fresh.
- The 2026-10-06 popup-metaphor `EXECUTION_PLAN.md` is archived at
  `docs/incomplete/vinetas-ui-recon-2026-10-07/`; generate a new plan, do not resume it.

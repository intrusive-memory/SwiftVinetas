---
type: execution-plan
state: executing
requirements_file: docs/REQUIREMENTS-vinetas-ui.md
requirements_sha256: 85a931d780ff7d3f6f764832cb2df1026bff72cf93446c430a45976d402990cd
recon_report: RECON_REPORT.md
recon_verdict: CLEAR
project_head: b7872158a692b6fce6f87db5e58e216c1ebd1ff3
generated: 2026-10-18
refined: 2026-10-18
open_questions_resolved: 2026-10-18
supersedes: docs/incomplete/vinetas-ui-recon-2026-10-07/EXECUTION_PLAN-popup-metaphor-stale.md (not resumed; regenerated from the inspector-direction requirements)
feature_name: OPERATION SIDEBOARD SHUFFLE
starting_point_commit: b7872158a692b6fce6f87db5e58e216c1ebd1ff3
mission_branch: mission/sideboard-shuffle/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVinetas `VinetasUI` (prompt panel as a reusable inspector element)

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Mission

Move the Vinetas app's Generation Studio prompt panel into SwiftVinetas as two new targets — an engine-free `VinetasVocabulary` and a SwiftUI `VinetasUI` that links no inference stack — shaped as a right-hand inspector on macOS/iPad and a pushed screen on iPhone, with a compiled host guide and the CI gates the next minor release needs. The mission ends **release-ready on the mission branch** with a **draft** PR open against `development` whose CI is green; the user ships it afterwards with `/ship-swift-library minor`. No sortie edits a version literal or names a version number.

Source of truth for *what*: `docs/REQUIREMENTS-vinetas-ui.md` (§ references below are to that document; where it and the design canvas disagree, the canvas wins). Source of truth for *what is already there*: `RECON_REPORT.md` — every `CONFIRMED` row is cited here as ground truth without a re-check; its two `UNVERIFIABLE` items (T-07b `Bundle.module`, CI SDK surface) appear below as explicit verification steps (Sortie 2, Sortie 5) and as Sortie 14's draft-PR exit criterion.

### Standing rules for every sortie

- **Build and test only through the Makefile** (`make build`, `make test-unit`, `make test-unit-ios`, `make build-ios`, `make lint`, and the new `make lint-check` / `make verify-ui-isolation` once they exist) or XcodeBuildMCP. **Never `swift build` or `swift test`** (repo rule: Metal shaders will not compile). `swift package dump-package` is manifest inspection, not a build, and is allowed.
- **CI is the truth for the UI target.** CI is `macos-26` (Swift 6.3.x, OS 26 SDKs); local is Xcode 27.1 / Swift 6.4 (T-01). No API introduced after the OS 26 SDKs in `VinetasVocabulary` or `VinetasUI`. A green local build does not prove it compiles on CI; the proof is the draft PR Sortie 14 opens.
- **iOS runs on CI's destination from the first sortie.** Sortie 1 sets `DESTINATION_IOS` to `platform=iOS Simulator,name=iPhone 17,OS=26.5`; every `make test-unit-ios` in this plan runs there. `OS=latest` is never used anywhere.
- **Format before you exit.** Run `make lint` (it formats in place) and confirm `swift format lint --strict -r <paths this sortie touched>` exits 0. Sortie 12 turns this into the CI gate `make lint-check`.
- **DocC on every public symbol you add.** Every `public` declaration added to `Sources/VinetasVocabulary` or `Sources/VinetasUI` carries a `///` summary line. **The DocC check** (named as such in exit criteria) is: `awk 'FNR==1{prev=""} $0 ~ /^[[:space:]]*(public|open)[[:space:]]/ && prev !~ /^[[:space:]]*(\/\/\/|@)/ {print FILENAME":"FNR": "$0} $0 !~ /^[[:space:]]*$/ {prev=$0}' <files>` — it prints every `public` line whose preceding non-blank line is neither a `///` comment nor an attribute, and must print nothing. Sortie 13 reconciles wording with the guide.
- **No version numbers.** The `-dev` version literals at `Sources/SwiftVinetas/Vinetas.swift:48,1125` and `AGENTS.md:8` are untouched. The release is "the next minor release" and is outside the mission. The version guard used below is `git diff HEAD -- Sources/SwiftVinetas/Vinetas.swift AGENTS.md | grep -E '^[-+].*[0-9]+\.[0-9]+\.[0-9]+(-dev)?'` printing nothing.
- **No change to the Vinetas app, Escribir, the granville project, or any dependency checkout.** Files that "move" from the Vinetas app are *copied into this repo*; their deletion from the app is the Vinetas-adoption mission. Paths in § Local Dependency Map and § Repositories read are read-only.
- **Real fixtures, never invented samples.** Every sample a test, preview, recipe or doc table uses — shots, prompts, drafts, host-recipe inputs, serializer round-trips — is copied from the real granville project: `~/Projects/podcasts/granville/episodes/episode_1_01_cold_open.fountain` (14 GLOSA `[[ <shot …/> ]]` directives: the prompt-less **defaults shot** at line 7 with `style=`, `aspect="wide"`, `model="klein4b"`, `steps="8"`, `guidance="3.5"`, `seed="22"`, `negative=`; then 13 per-shot directives with `prompt`, `ref`, `output`) and `~/Projects/podcasts/granville/storyboards/*.json` (13 generated panels, keys `composedPrompt`, `durationSeconds`, `engine`, `generatedAt`, `guidance`, `height`, `loras`, `mode`, `model`, `negative`, `negativeApplied`, `prompt`, `references`, `seed`, `steps`, `style`, `width`). Sorties copy the exact files they need into the package's test `Fixtures/` (the only values invented are shapes the real set lacks, e.g. an unknown model id). Fixtures are read through `Bundle.module` (the test target declares `resources: [.copy("Fixtures")]`); if `Bundle.module` fails on a destination, the fallback is a `#filePath`-relative URL as `StoryboardStyleCatalogTests` does in the Vinetas app, and the SwiftFijos package (`~/Projects/package-collection/pkg/SwiftFijos`) is the optional house helper for fixture discovery.
- **No Klein 9B, no memory gating, no `TimelineView`, no Generate/Save/Cancel button drawn by the package** (standing directives; Non-goals 1, 4, 8).
- Accessibility identifiers in `VinetasUI` come only from `VinetasUIAccessibility`; `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` must print nothing from Sortie 5 onward.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU-1 `VinetasVocabulary` | `Sources/VinetasVocabulary`, `Tests/VinetasVocabularyTests`, `Package.swift`, `Sources/SwiftVinetas` (shim + `cliName`), `Makefile` (filters + iOS destination) | 4 (Sorties 1–4) | 1 | none |
| WU-2 `VinetasUI` | `Sources/VinetasUI`, `Tests/VinetasUITests`, `Package.swift`, `Makefile` (filter) | 7 (Sorties 5–11) | 2 | WU-1 |
| WU-3 Release phase | `Makefile`, `Tools/UIIsolationProbe`, `docs/VinetasUI.md`, `Tests/VinetasUITests/HostRecipe*.swift`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `.github/workflows/tests.yml` | 3 (Sorties 12–14) | 3 | WU-2 |

Dependency layers: **Layer 1** WU-1 → **Layer 2** WU-2 → **Layer 3** WU-3. Sorties run in numeric order inside each work unit; see § Parallelism Structure for why nothing runs concurrently.

---

## WU-1 — `VinetasVocabulary` (`Sources/VinetasVocabulary`)

Requirements: § 1.1 What moves in, § 1.2 `ModelSummary`, § 1.3 Compatibility, D-1, D-3, D-5, D-9, D-10; Acceptance 1 (vocabulary half), 3.

### Sortie 1: Scaffold `VinetasVocabulary`, move the three Core types behind a re-export shim, pin the iOS destination

**Priority**: 44 — blocks all 13 later sorties (depth 13 × 3); establishes the target and the Makefile shape every sortie's exit criteria depend on; risk 2 (manifest + file moves across an 11-file blast radius).

**Entry criteria**:
- [ ] First sortie — no prerequisites. Working tree clean on the mission branch.
- [ ] Ground truth (recon `CONFIRMED`, cite, do not re-prove): the moving set is exactly `Sources/SwiftVinetas/Core/{AspectRatio,ResolutionClamp,StyleConfig}.swift` (R-01, R-02); `ResolutionClamp.swift` keeps `#if canImport(Metal) import Metal` (D-9); the only non-public members reached from outside the three files are `attentionHeadsWorstCase` / `scoreBytes`, used solely by `Tests/SwiftVinetasTests/{ResolutionClampTests,AspectRatioTests}.swift` (R-03); nothing module-qualifies or reflects the three type names (R-16); all new target/product names are free (R-14).
- [ ] Blast radius to keep compiling **without edits**: 11 source files outside the three (`Core/{ImageOutput,LoRAManager,PromptFile,VinetasPipeline}.swift`, `Engine/{Flux2Engine,PixArtEngine,ModelDescriptor}.swift`, `PanelRequest.swift`, `Vinetas.swift`, `VinetasCLICore/Storyboard/StoryboardCommand.swift`, `VinetasCLICore/VinetasCLICore.swift`) and 20 test files (4 in `SwiftVinetasGPUTests`, 13 unit-test files plus the three moving ones) that name the types (R-16, R-18).
- [ ] Ground truth for the Makefile edit: `DESTINATION_IOS` at `Makefile:32` is `'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'`; the iPhone 17 simulator and the iOS 26.5 runtime exist locally (T-04).

**Tasks**:
1. `Package.swift`: add `.library(name: "VinetasVocabulary", targets: ["VinetasVocabulary"])`; add `.target(name: "VinetasVocabulary")` with **no** `dependencies:` (D-9: Apple system frameworks only, no package dependency); add `"VinetasVocabulary"` to the `SwiftVinetas` target's dependencies; add `.testTarget(name: "VinetasVocabularyTests", dependencies: ["VinetasVocabulary"])`.
2. `git mv` the three files to `Sources/VinetasVocabulary/` (a rename in the diff, not a copy). Change nothing inside them except what the compiler requires; `ResolutionClamp`'s conditional `import Metal` stays.
3. Add `Sources/SwiftVinetas/VinetasVocabularyExports.swift` containing exactly one `@_exported import VinetasVocabulary` with a doc comment naming it the compatibility shim for `import SwiftVinetas` consumers (§ 1.3, D-5). Where a file *inside* the `SwiftVinetas` or `VinetasCLICore` module fails to compile because imports are file-scoped, add a plain `import VinetasVocabulary` to that file in `Sources/SwiftVinetas/` only — **no edit to `Sources/VinetasCLICore`, `Sources/vinetas`, or `Tests/SwiftVinetasGPUTests`** (Acceptance 3; their `import SwiftVinetas` must suffice through the shim).
4. `git mv` `Tests/SwiftVinetasTests/{AspectRatioTests,ResolutionClampTests,StyleConfigTests}.swift` to `Tests/VinetasVocabularyTests/` and change their import to `@testable import VinetasVocabulary` (R-13); the two internal members stay internal.
5. `Makefile`: (a) add `-only-testing:VinetasVocabularyTests` beside `-only-testing:SwiftVinetasTests` in both `test-unit` and `test-unit-ios` (`Makefile:131,245`; the filters are the reason a new test target is otherwise silent); (b) change `Makefile:32` to `DESTINATION_IOS = 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`, still overridable from the environment exactly as today (OQ-1 decision). No other Makefile change in this sortie.
6. Run `make lint`.

**Exit criteria**:
- [ ] `swift package dump-package | jq '.targets[] | select(.name=="VinetasVocabulary") | .dependencies'` prints `[]`; `.products[].name` includes `VinetasVocabulary`.
- [ ] `git diff -M HEAD --name-status` shows status `R` for all six moved files (three sources, three tests); `ls Sources/SwiftVinetas/Core/` no longer lists the three.
- [ ] `grep -rn '@_exported import VinetasVocabulary' Sources/` prints exactly one line, in `Sources/SwiftVinetas/VinetasVocabularyExports.swift`.
- [ ] `git diff --stat HEAD -- Sources/VinetasCLICore Sources/vinetas Tests/SwiftVinetasGPUTests` prints nothing.
- [ ] `grep -n "^DESTINATION_IOS = 'platform=iOS Simulator,name=iPhone 17,OS=26.5'$" Makefile` prints one line; `grep -n 'OS=latest' Makefile` prints nothing.
- [ ] `make build` exits 0 (CLI links through the shim).
- [ ] `make test-unit` exits 0 and `build/test-output.log` shows `VinetasVocabularyTests` executed (grep the suite names `AspectRatioTests`, `ResolutionClampTests`, `StyleConfigTests` in the log) with zero failures across `SwiftVinetasTests` and `VinetasVocabularyTests`.
- [ ] `make test-unit-ios` exits 0 and `build/test-output-ios.log` contains `iPhone 17` (the run used the new default).
- [ ] `swift format lint --strict -r Sources/VinetasVocabulary Sources/SwiftVinetas/VinetasVocabularyExports.swift Tests/VinetasVocabularyTests Package.swift` exits 0.
- [ ] The version guard prints nothing.

### Sortie 2: Bring `StoryboardStyle` into the vocabulary with the two style fixtures and the frozen-vocabulary test

**Priority**: 42 — blocks 12 sorties; `StoryboardStyle` is reused by Sorties 3, 7, 8, 10; risk 3 (first `Bundle.module` resource target — recon T-07b).

**Entry criteria**:
- [ ] Sortie 1 exit criteria met.
- [ ] Source to read (read-only; Vinetas app at `0c25a3d`, `~/Projects/apps/Vinetas`): `Vinetas/Models/StoryboardStyle.swift` (20 cases incl. `.custom`; `displayName`, `genre`, `caption`, `promptText`, `baseNegative`, `styleSpecificNegative`, `negativePromptText`, `customTag = "__custom__"`, `sortedPresets`, `from(promptText:)` — V-04), `VinetasTests/{StoryboardStyleTests,StoryboardStyleCatalogTests}.swift` and `VinetasTests/Fixtures/storyboard-styles.json` (19 entries under a `styles` key, keys `id/displayName/genre/prompt/negative`, loaded via `#filePath` — V-09).
- [ ] Fixture shape (OQ-3a decision): the frozen vocabulary is its **own second file** `Tests/VinetasVocabularyTests/Fixtures/style-vocabulary.json`; `storyboard-styles.json` (19 entries, the `vinetas-skills` contract) is copied **unchanged** and never extended.
- [ ] **Verification step for recon T-07b (`Bundle.module`)**: this sortie's test target declares `resources: [.copy("Fixtures")]` and loads via `Bundle.module`, the pattern `SwiftVinetasGPUTests` already uses (`Package.swift` GPU test target; `BatchIntegrationTests.swift:18`). If `Bundle.module` fails to synthesise or the fixture is not found on the iPhone 17 simulator run, fall back to the `#filePath` lookup and record the outcome in the sortie report — it informs Sortie 5's `.xcstrings` plan.

**Tasks**:
1. Add `Sources/VinetasVocabulary/StoryboardStyle.swift`: the app's enum made `public` (type, every case, `displayName`, `genre`, `caption`, `promptText`, `negativePromptText`, `customTag`, `sortedPresets`, `from(promptText:)`; `baseNegative`/`styleSpecificNegative` may stay non-public). **Byte-identical** `rawValue`s, case order, `promptText` and `negativePromptText` (D-10, Non-goal 2). Foundation only. `///` on every public symbol.
2. Copy `StoryboardStyleTests.swift` and `StoryboardStyleCatalogTests.swift` into `Tests/VinetasVocabularyTests/` with `@testable import VinetasVocabulary`; copy `storyboard-styles.json` **unchanged** into `Tests/VinetasVocabularyTests/Fixtures/`; declare `resources: [.copy("Fixtures")]` on the `VinetasVocabularyTests` target and load via `Bundle.module` (entry-criteria verification step above). Both suites keep passing.
3. Add the **frozen-vocabulary fixture** `Tests/VinetasVocabularyTests/Fixtures/style-vocabulary.json`: a top-level array of twenty objects `{"rawValue", "promptText", "negativePromptText"}` in `allCases` order, including `custom`, generated from the enum once and committed. Add `FrozenVocabularyTests.swift` asserting, for all twenty cases, `rawValue`, `promptText` and `negativePromptText` equal the fixture byte for byte, and that `allCases.count == 20` in fixture order (D-10).
4. Run `make lint`.

**Exit criteria**:
- [ ] `grep -c '^\s*case ' Sources/VinetasVocabulary/StoryboardStyle.swift` is 20 and `grep -n 'import' Sources/VinetasVocabulary/StoryboardStyle.swift` shows only `import Foundation`.
- [ ] `cmp Tests/VinetasVocabularyTests/Fixtures/storyboard-styles.json ~/Projects/apps/Vinetas/VinetasTests/Fixtures/storyboard-styles.json` reports no difference.
- [ ] `python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d)==20 and d[-1]["rawValue"]=="custom" and set(d[0])=={"rawValue","promptText","negativePromptText"}' Tests/VinetasVocabularyTests/Fixtures/style-vocabulary.json` exits 0.
- [ ] `swift package dump-package | jq '.targets[] | select(.name=="VinetasVocabularyTests") | .resources[0].path'` prints `"Fixtures"`.
- [ ] `make test-unit` exits 0; `build/test-output.log` lists `StoryboardStyleTests`, `StoryboardStyleCatalogTests`, `FrozenVocabularyTests` with zero failures.
- [ ] `make test-unit-ios` exits 0 (fixture found on the iPhone 17 run — the T-07b evidence; the sortie report states which loader worked).
- [ ] `git diff --stat HEAD -- Sources/VinetasCLICore Sources/vinetas Tests/SwiftVinetasGPUTests` prints nothing.
- [ ] The DocC check over `Sources/VinetasVocabulary/StoryboardStyle.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasVocabulary Tests/VinetasVocabularyTests Package.swift` exits 0.

### Sortie 3: `StyleSwatchPalette` — the per-style colour triples

**Priority**: 36.5 — blocks 11 sorties; the palette is consumed by Sortie 7's swatches; risk 1 (pure data).

**Entry criteria**:
- [ ] Sortie 2 exit criteria met (`StoryboardStyle` exists in the vocabulary).
- [ ] Source to read (read-only, Vinetas app `0c25a3d`): `Vinetas/Views/GenerationStudio/StylePickerListView.swift:232–287` (`swatchPalette` returns `(Color, Color, Color)` built from hex strings via a private `hex(_:)` — V-10 and recon handoff).

**Tasks**:
1. Add `Sources/VinetasVocabulary/StyleSwatchPalette.swift`: a `public struct StyleSwatchPalette: Hashable, Sendable` holding three `(red, green, blue)` triples of `Double` (0…1), plus `extension StoryboardStyle { public var swatchPalette: StyleSwatchPalette }` whose values are the hex strings from `StylePickerListView.swift:232–287` converted to `Double` components (no `SwiftUI.Color` in this target; `VinetasUI` converts later). Foundation only. `///` on every public symbol.
2. Add `Tests/VinetasVocabularyTests/StyleSwatchPaletteTests.swift` asserting every case has a palette whose nine components lie in 0…1 and that `midCenturyModern`'s first triple equals `(0xc4/255, 0x92/255, 0x3a/255)` (the first hex at `StylePickerListView.swift:235`).
3. Run `make lint`.

**Exit criteria**:
- [ ] `grep -n 'import' Sources/VinetasVocabulary/StyleSwatchPalette.swift` shows only `import Foundation`; `grep -rn 'SwiftUI\|Color(' Sources/VinetasVocabulary` prints nothing.
- [ ] `make test-unit` and `make test-unit-ios` exit 0; both logs list `StyleSwatchPaletteTests` with zero failures.
- [ ] The DocC check over `Sources/VinetasVocabulary/StyleSwatchPalette.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasVocabulary Tests/VinetasVocabularyTests` exits 0.

### Sortie 4: `ModelSummary`, `ModelDescriptor.cliName`, and the descriptor-equals-summary tests against the granville panel

**Priority**: 34 — blocks 10 sorties; `ModelSummary` is reused by Sorties 9, 10, 13; risk 1.

**Entry criteria**:
- [ ] Sortie 3 exit criteria met (the `Fixtures` resource declaration from Sortie 2 is in place).
- [ ] Ground truth (recon `CONFIRMED`): `ModelDescriptor` (`Sources/SwiftVinetas/Engine/ModelDescriptor.swift`) imports Foundation only and requires `id, displayName, engineID, license: ModelLicense, minimumMemoryGB, approximateDownloadSize, defaultSteps, defaultGuidance, supportedAspectRatios, componentIds` (the last defaulted `[]`) — eight of these are `ModelSummary`'s fields; `license` and `componentIds` are **not** in the summary and the default `summary` ignores them (R-04, recon handoff). Conforming statics: `Flux2ModelDescriptor.klein4B` (`Engine/Flux2Engine.swift:35`, engineID `"flux2"`) and `PixArtModelDescriptor.sigmaXL` (`Engine/PixArtEngine.swift:39`); both list `AspectRatio.allCases`; no 9B (R-05). `VinetasModel` at `Vinetas.swift:1753` (`klein4b`, `pixartSigma = "pixart-sigma"`), deprecated at `:1749–1751`; `allCases.map(\.rawValue) == ["klein4b", "pixart-sigma"]` (R-06, R-06b). The CLI `--model` help literal is at `VinetasCLICore.swift:62` — **it stays as it is** (Non-goal 5).
- [ ] Values table (§ What exists today): klein4B → `flux2-klein-4b` / "FLUX.2 Klein 4B" / `flux2` / 16 GB / `~11 GB` / 8 / 3.5 / cli `klein4b`; sigmaXL → `pixart-sigma-xl` / "PixArt-Sigma XL" / `pixart-sigma` / 8 GB / `~3.6 GB` / 20 / 4.5 / cli `pixart-sigma`. The descriptor-equals-summary test is what proves the table.
- [ ] Real fixtures (OQ-3b decision): `~/Projects/podcasts/granville/episodes/episode_1_01_cold_open.fountain` (line 7 defaults shot carries `model="klein4b"`, `steps="8"`, `guidance="3.5"`) and `~/Projects/podcasts/granville/storyboards/ep1_sc1_01_establishing.json` (`"model" : "flux2-klein-4b"`, `"engine" : "flux2"`, `"steps" : 8`, `"guidance" : 3.5`) — the one panel set was generated with klein4B's defaults, which is exactly what the summary must reproduce.

**Tasks**:
1. Add `Sources/VinetasVocabulary/ModelSummary.swift`: `public struct ModelSummary: Hashable, Sendable, Identifiable, Codable` with exactly the nine fields of § 1.2 (`id, displayName, engineID, cliName, minimumMemoryGB, approximateDownloadSize, defaultSteps, defaultGuidance: Float, supportedAspectRatios: [AspectRatio]`), a public memberwise `init`, `static let klein4B`, `static let pixartSigmaXL`, `static let all` (FLUX.2 first, then PixArt), `static func named(cli:) -> ModelSummary?`. **No `requiresPro`** (D-3). Foundation only. `///` on every public symbol.
2. `Engine/ModelDescriptor.swift`: add the requirement `var cliName: String { get }` and an extension default `public var summary: ModelSummary` built from the descriptor's own fields plus `cliName` (ignoring `license`, `componentIds`).
3. `Engine/Flux2Engine.swift` / `Engine/PixArtEngine.swift`: add `cliName` (`"klein4b"`, `"pixart-sigma"`) to the two concrete descriptors. This is the only edit to engine files; no other `SwiftVinetas` surface changes.
4. Copy the two granville files **unchanged** to `Tests/VinetasVocabularyTests/Fixtures/granville/episode_1_01_cold_open.fountain` and `Tests/VinetasVocabularyTests/Fixtures/granville/ep1_sc1_01_establishing.json`.
5. `Tests/SwiftVinetasTests/ModelSummaryRoundTripTests.swift` (Swift Testing, `@testable import SwiftVinetas`): `Flux2ModelDescriptor.klein4B.summary == ModelSummary.klein4B`; `PixArtModelDescriptor.sigmaXL.summary == ModelSummary.pixartSigmaXL`; every `ModelSummary.all` element's `cliName` is contained in `VinetasModel.allCases.map(\.rawValue)` and vice versa — with the deprecation warning silenced **locally** for that one expression (an `@available(*, deprecated)` helper that wraps the call), not by removing the round-trip (§ 1.2).
6. `Tests/VinetasVocabularyTests/ModelSummaryTests.swift`: `all.map(\.id) == ["flux2-klein-4b", "pixart-sigma-xl"]`; `named(cli: "pixart-sigma") == .pixartSigmaXL`; `named(cli: "klein9b") == nil` (the one invented value — a shape the real set lacks); JSON `Codable` round-trip of both statics; `supportedAspectRatios == AspectRatio.allCases` for both. **Granville cross-check** in the same file: parse the `model=` attribute of the fountain's line-7 defaults shot (a regex over `<shot [^>]*/>`) and assert `ModelSummary.named(cli:)` of it `== .klein4B`; decode `ep1_sc1_01_establishing.json` (a test-only `Decodable` with `model`, `engine`, `steps: Int`, `guidance: Float`) and assert `model == ModelSummary.klein4B.id`, `engine == klein4B.engineID`, `steps == klein4B.defaultSteps`, `guidance == klein4B.defaultGuidance`.
7. Update `Tests/SwiftVinetasTests/MockEngine.swift`: `MockModelDescriptor` adopts the new `cliName` requirement (`var cliName: String { id }`) so the existing engine tests keep compiling; stage it with the sortie's other files.
7. Run `make lint`.

**Exit criteria**:
- [ ] `grep -n 'import' Sources/VinetasVocabulary/ModelSummary.swift` shows only `import Foundation`; `grep -rnw 'requiresPro\|9B\|klein9b' Sources/VinetasVocabulary` and `grep -rniE 'klein ?9b' Sources/VinetasVocabulary` both print nothing (word-anchored: the hex colour `0xc9b88a` in `StyleSwatchPalette.swift` is not a Klein 9B reference).
- [ ] `grep -n 'var cliName' Sources/SwiftVinetas/Engine/*.swift` shows the protocol requirement plus exactly two concrete implementations.
- [ ] `cmp Tests/VinetasVocabularyTests/Fixtures/granville/ep1_sc1_01_establishing.json ~/Projects/podcasts/granville/storyboards/ep1_sc1_01_establishing.json` and `cmp Tests/VinetasVocabularyTests/Fixtures/granville/episode_1_01_cold_open.fountain ~/Projects/podcasts/granville/episodes/episode_1_01_cold_open.fountain` both report no difference.
- [ ] `git diff HEAD --stat -- Sources/VinetasCLICore Sources/vinetas Tests/SwiftVinetasGPUTests` prints nothing; `sed -n 62p Sources/VinetasCLICore/VinetasCLICore.swift` is unchanged from HEAD.
- [ ] `make build` exits 0; `make test-unit` exits 0 with `ModelSummaryRoundTripTests` and `ModelSummaryTests` in `build/test-output.log`, zero failures, and **no** deprecation warning for `VinetasModel` from any file **this sortie added or changed** (grep the log for `'VinetasModel' is deprecated` and compare the file list against `git diff --name-only` for the sortie; the pre-existing warnings from `VinetasModelTests`, `ReferencePromptTests`, `CharacterPromptTests`, `CharacterTrainerTests`, `ProGateTests` and `SwiftVinetasGPUTests/BatchIntegrationTests` are expected and out of scope — Non-goal: this mission does not migrate the CLI or its tests off `VinetasModel`).
- [ ] `make test-unit-ios` exits 0 with `ModelSummaryTests` in `build/test-output-ios.log`.
- [ ] The DocC check over `Sources/VinetasVocabulary/ModelSummary.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasVocabulary Sources/SwiftVinetas/Engine Tests/SwiftVinetasTests/ModelSummaryRoundTripTests.swift Tests/VinetasVocabularyTests` exits 0.

---

## WU-2 — `VinetasUI` (`Sources/VinetasUI`)

Requirements: § 2.1–2.6, D-2, D-4, D-6, D-7, D-8, D-12, D-13; Acceptance 1 (UI half), 2 (previews, tests), 4.

Entry for the whole work unit: WU-1 complete (Sorties 1–4), so `AspectRatio`, `StoryboardStyle`, `StyleSwatchPalette` and `ModelSummary` are importable from `VinetasVocabulary`.

### Sortie 5: Scaffold `VinetasUI` — manifest, string catalogue, `VinetasUIAccessibility`, granville UI fixtures, test target

**Priority**: 33.5 — blocks 9 sorties; establishes the target, the localisation helper, the identifier contract and the fixture loader every UI sortie uses; risk 3 (first SwiftUI + `.xcstrings` + `Bundle.module` library target, CI unverified until Sortie 14).

**Entry criteria**:
- [ ] Sorties 1–4 exit criteria met.
- [ ] Ground truth (recon `CONFIRMED`): no SwiftUI, `.xcstrings`, `Resources/` or `defaultLocalization` in the package today (R-07, R-08); SwiftAcervoUI's `public enum AcervoUIAccessibility` of `public static let` strings at `SwiftAcervo v0.25.0 Sources/SwiftAcervoUI/AcervoUIAccessibility.swift:26` is the shape to copy (S-02; read with `git -C ~/Projects/package-collection/pkg/SwiftAcervo show v0.25.0:Sources/SwiftAcervoUI/AcervoUIAccessibility.swift`). `String(localized:bundle:)` exists (T-07).
- [ ] The nineteen identifier strings are the contract (V-06, § 2.5): `prompt.primary`, `stylePicker.list`, `stylePicker.row` (prefix), `stylePicker.promptTextDisclosure` (today a raw literal in both app panels — the constant is new), `prompt.stylePicker`, `prompt.styleCustom`, `prompt.negativeToggle`, `prompt.negative`, `generation.modelPicker`, `generation.aspectRatioSelection`, `generation.aspectRatioTile` (prefix), `generation.stepsSlider`, `generation.stepsUseDefault`, `generation.guidanceSlider`, `generation.guidanceUseDefault`, `generation.aspectRatioUseDefault`, `generation.seedField`, `generation.randomizeSeed`, `generation.memoryWarning` (kept for the stale `MemoryGatingUITests.swift:89` only; no view renders it — V-16). Plus the one new constant `promptCaption = "prompt.caption"`.
- [ ] **Verification step for recon T-07b / CI SDK surface**: this is the first sortie that compiles SwiftUI and `Bundle.module` for a resource-bearing *library* target. `make build` / `make test-unit` here is the evidence that `defaultLocalization: "en"` + `.xcstrings` + `Bundle.module` compose under SwiftPM; a missing-`Bundle.module` compile error is the signal (recon handoff). CI compatibility itself is proven by Sortie 14's draft PR.
- [ ] Real fixtures (OQ-3b decision): all 14 granville files — `~/Projects/podcasts/granville/episodes/episode_1_01_cold_open.fountain` and the 13 `~/Projects/podcasts/granville/storyboards/*.json` (`ep1_sc1_01_establishing`, `ep1_sc1_02_arrival`, `ep1_sc1_03_from-the-porch`, `ep1_sc1_05_bear-hug`, `ep1_sc1_06_grandmothers-joy`, `ep1_sc1_07_screen-door`, `ep1_sc1_08_three-men`, `ep1_sc1_09_i-dont-believe-you`, `ep1_sc1_10_i-was-here`, `ep1_sc1_11_the-hidden-burden`, `ep1_sc1_12_fart-appointment`, `ep1_sc1_13_too-small-door`, `ep1_sc1_14_suitcases`). The `.png` files are **not** copied.

**Tasks**:
1. `Package.swift`: add `defaultLocalization: "en"` to the `Package(...)` call (recon handoff); add `.library(name: "VinetasUI", targets: ["VinetasUI"])`; add `.target(name: "VinetasUI", dependencies: ["VinetasVocabulary"], resources: [.process("Resources")])` — dependencies **exactly** `["VinetasVocabulary"]` (D-2, Acceptance 1); add `.testTarget(name: "VinetasUITests", dependencies: ["VinetasUI"], resources: [.copy("Fixtures")])`.
2. Add `Sources/VinetasUI/Resources/Localizable.xcstrings` (sourceLanguage `en`, English only — V-13) and `Sources/VinetasUI/Localization.swift` with one internal helper that wraps `String(localized:bundle: .module)` so every later sortie routes user-facing strings through it.
3. Add `Sources/VinetasUI/VinetasUIAccessibility.swift`: `public enum VinetasUIAccessibility` with twenty `public static let` string constants (the nineteen above, unchanged, plus `promptCaption`) and two helpers `stylePickerRow(_ rawValue: String)` / `aspectRatioTile(_ rawValue: String)` that join prefix and raw value with `.`. `///` on every public symbol.
4. Copy the 14 granville files **unchanged** into `Tests/VinetasUITests/Fixtures/granville/`. Add `Tests/VinetasUITests/GranvilleFixtures.swift` (test-only): `struct GranvillePanel: Decodable` with the JSON's keys (`composedPrompt`, `durationSeconds: Double`, `engine`, `generatedAt`, `guidance: Float`, `height: Int`, `loras: [String]`, `mode`, `model`, `negative`, `negativeApplied: Bool`, `prompt`, `references: [String]`, `seed: UInt64`, `steps: Int`, `style`, `width: Int`); `enum GranvilleFixtures` with `static func panels() throws -> [GranvillePanel]` (13, sorted by file name), `static func shotDirectives() throws -> [[String: String]]` (the 14 `<shot …/>` attribute maps, parsed from the fountain with a regex), `static var defaultsShot` (the first, prompt-less directive), `static var establishingShot` (the second directive) and `static var establishingPanel` (`ep1_sc1_01_establishing.json`); `static let sceneHeading = "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET"` (fountain line 9 — the real caption text). Loader: `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures/granville")`, with the `#filePath` fallback from the standing rule.
5. Tests in `Tests/VinetasUITests/`: `AccessibilityIdentifierTests.swift` — every constant equals its documented string (a literal table of all twenty in the test), and `stylePickerRow("custom") == "stylePicker.row.custom"`; `GranvilleFixturesTests.swift` — `panels().count == 13`, `shotDirectives().count == 14`, `defaultsShot["model"] == "klein4b"`, `defaultsShot["aspect"] == "wide"`, `establishingPanel.seed == 22`, `establishingPanel.model == ModelSummary.klein4B.id`.
6. `Makefile`: add `-only-testing:VinetasUITests` to `test-unit` and `test-unit-ios` beside the two existing filters. Run `make lint`.

**Exit criteria**:
- [ ] `swift package dump-package | jq '.targets[] | select(.name=="VinetasUI") | [.dependencies[] | .byName[0] // .product[0]]'` prints `["VinetasVocabulary"]` and `.products[].name` includes `VinetasUI`; `jq '.defaultLocalization'` prints `"en"`; `jq '.targets[] | select(.name=="VinetasUITests") | .resources[0].path'` prints `"Fixtures"`.
- [ ] `grep -rn 'import' Sources/VinetasUI | grep -v 'import SwiftUI\|import VinetasVocabulary\|import Foundation\|import AppKit\|import UIKit\|import Observation'` prints nothing (no package product imported — § 2.1).
- [ ] `grep -c 'public static let' Sources/VinetasUI/VinetasUIAccessibility.swift` is 20; `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.
- [ ] `test -f Sources/VinetasUI/Resources/Localizable.xcstrings` and `python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["sourceLanguage"]=="en"' Sources/VinetasUI/Resources/Localizable.xcstrings` exits 0.
- [ ] `ls Tests/VinetasUITests/Fixtures/granville | wc -l` is 14 and `ls Tests/VinetasUITests/Fixtures/granville/*.png 2>/dev/null | wc -l` is 0; `for f in Tests/VinetasUITests/Fixtures/granville/*.json; do cmp "$f" ~/Projects/podcasts/granville/storyboards/$(basename "$f"); done` and `cmp Tests/VinetasUITests/Fixtures/granville/episode_1_01_cold_open.fountain ~/Projects/podcasts/granville/episodes/episode_1_01_cold_open.fountain` report no difference.
- [ ] `make build` exits 0; `make test-unit` exits 0 with `AccessibilityIdentifierTests` and `GranvilleFixturesTests` in `build/test-output.log`, zero failures; `make test-unit-ios` exits 0 with both suites in `build/test-output-ios.log`.
- [ ] `grep -rn '@available(macOS 27\|@available(iOS 27\|macOS 27\.\|iOS 27\.' Sources/VinetasUI Sources/VinetasVocabulary` prints nothing (OS 26 SDK ceiling; Sortie 14's CI run is the real proof).
- [ ] `grep -c 'only-testing:' Makefile` is 6.
- [ ] The DocC check over `Sources/VinetasUI/VinetasUIAccessibility.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests Package.swift` exits 0.

### Sortie 6: `VinetasPanelLayout`, `VinetasStylePickerStyle`, navigation-availability flag — the environment plumbing

**Priority**: 27.5 — blocks 8 sorties; the layout resolver is read by every view from Sortie 7 on; risk 1 (pure resolver + environment keys).

**Entry criteria**:
- [ ] Sortie 5 exit criteria met.
- [ ] Ground truth (recon `CONFIRMED`): SwiftEscribo's pure resolver `WellLane.width(on:horizontalSizeClass:)` at `v0.4.2 Sources/SwiftEscribo/EscriboWell.swift:181` and its exhaustive test `Tests/SwiftEscriboTests/EscriboWellTests.swift:75–86` are the shape for the layout resolver and its test (E-01, E-02; read with `git -C ~/Projects/package-collection/pkg/SwiftEscribo show v0.4.2:<path>`); SwiftEscribo has **no** `EnvironmentKey` precedent — `vinetasPanelLayout` is written fresh (E-03).
- [ ] Decision (refine, Pass 5): SwiftUI exposes no query for an enclosing `NavigationStack`, so the § 2.3 sentence "a host that has no `NavigationStack` at compact width gets the popover form" is implemented with an **environment flag**, not detection: `EnvironmentValues.vinetasNavigationStackAvailable: Bool`, default `true` (the compact chevron row is a `NavigationLink`, as recipe 2 provides the stack); a stack-less host applies `.vinetasNavigationStackAvailable(false)` and gets the popover form. The guide documents it in section 7.

**Tasks**:
1. Add `Sources/VinetasUI/VinetasPanelLayout.swift`: `public enum VinetasPlatform: Sendable, CaseIterable { case macOS, iOS }`, `public enum VinetasSizeClass: Sendable, CaseIterable { case compact, regular }`, `public enum VinetasPanelLayout: Sendable, CaseIterable { case sidebar, regular, compact; public static func resolve(platform:horizontalSizeClass:) -> VinetasPanelLayout }` — pure: macOS → `.sidebar` for any size class; iOS `.regular` → `.regular`; iOS `.compact` → `.compact`; iOS `nil` → `.regular` (document the nil choice in the doc comment). Plus `EnvironmentValues.vinetasPanelLayout: VinetasPanelLayout?` (nil = resolve) via an `EnvironmentKey`, `View.vinetasPanelLayout(_:)`, and an internal `resolvedPanelLayout` environment-reading helper that applies `resolve(...)` with the current platform and `@Environment(\.horizontalSizeClass)` (iOS only; nil on macOS).
2. Add `Sources/VinetasUI/VinetasStylePickerStyle.swift`: `public enum VinetasStylePickerStyle: Sendable { case automatic, list }`, `EnvironmentValues.vinetasStylePickerStyle` (default `.automatic`), `View.vinetasStylePickerStyle(_:)` (§ 2.3 opt-in; behaviour lands in Sortie 8).
3. Add `Sources/VinetasUI/VinetasNavigationAvailability.swift`: `EnvironmentValues.vinetasNavigationStackAvailable: Bool` (default `true`) and `View.vinetasNavigationStackAvailable(_:)` per the decision above. `///` on every public symbol in the three files.
4. `Tests/VinetasUITests/PanelLayoutResolverTests.swift` — explicit `#expect` for every `VinetasPlatform × (VinetasSizeClass? = nil, .compact, .regular)` combination (six lines) in the EscriboWellTests shape; `EnvironmentDefaultsTests.swift` — `EnvironmentValues().vinetasPanelLayout == nil`, `.vinetasStylePickerStyle == .automatic`, `.vinetasNavigationStackAvailable == true`.
5. Run `make lint`.

**Exit criteria**:
- [ ] `grep -c 'static func resolve' Sources/VinetasUI/VinetasPanelLayout.swift` is 1; `grep -rn 'EnvironmentKey\|@Entry' Sources/VinetasUI | wc -l` is at least 3 (three environment values).
- [ ] `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.
- [ ] `make build` exits 0; `make test-unit` and `make test-unit-ios` exit 0 with `PanelLayoutResolverTests` and `EnvironmentDefaultsTests` in both logs, zero failures.
- [ ] `grep -rn '@available(macOS 27\|@available(iOS 27\|macOS 27\.\|iOS 27\.' Sources/VinetasUI` prints nothing.
- [ ] The DocC check over `Sources/VinetasUI/VinetasPanelLayout.swift Sources/VinetasUI/VinetasStylePickerStyle.swift Sources/VinetasUI/VinetasNavigationAvailability.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests` exits 0.

### Sortie 7: Semantic palette, swatches, and `VinetasStyleList`

**Priority**: 26.5 — blocks 7 sorties; palette, swatches and list are reused by Sortie 8; risk 2 (dynamic per-platform colours).

**Entry criteria**:
- [ ] Sortie 6 exit criteria met.
- [ ] Source to read (read-only, Vinetas app `0c25a3d`): `Vinetas/Views/GenerationStudio/StylePickerListView.swift` — list (`rowSpacing = 6` at `:22`, 56 pt min row `:23`, 7 pt radius `:25`, 5.5 visible rows, 56 × 40 swatch at `:130–134`; V-12), `StyleSwatchView` (`:158`), `StylePalette` (`:215–224`; V-10); `MidCenturySwatch.swift` (static `Canvas`, every draw `t: 0`, `TimelineView` removed — V-11).
- [ ] **Palette table (OQ-5 decision)** — the eight tokens, their V7 source name, the light-appearance system colour and the dark-appearance value. Dark keeps the V7 hex; light is the system semantic colour. Tests assert this table.

  | `VinetasStylePalette` token | V7 name (`StylePalette`) | Light (macOS `NSColor` / iOS `UIColor`) | Dark (V7 hex) |
  |---|---|---|---|
  | `rowBackground` | `bgInput` | `quaternarySystemFill` / `quaternarySystemFill` | `0x2a2a2c` |
  | `rowHover` | `bgInputHover` | `tertiarySystemFill` / `tertiarySystemFill` | `0x323234` |
  | `border` | `border` | `separatorColor` / `separator` | `0x38383a` |
  | `primaryText` | `fg` | `labelColor` / `label` | `0xf5f5f7` |
  | `secondaryText` | `fg3` | `secondaryLabelColor` / `secondaryLabel` | `0x8e8e93` |
  | `tertiaryText` | `fg4` | `tertiaryLabelColor` / `tertiaryLabel` | `0x6a6a6e` |
  | `accent` | `accent` | `Color.accentColor` | `0x0a84ff` at 1.0 |
  | `accentSoft` | `accentSoft` | `Color.accentColor.opacity(0.18)` | `0x0a84ff` at 0.18 |

- [ ] Real sample for previews (standing rule): the inline preview strings are the `prompt`, `style` and `negative` of `ep1_sc1_01_establishing.json`, copied verbatim.

**Tasks**:
1. Add `Sources/VinetasUI/VinetasStylePalette.swift`: an `enum VinetasStylePalette` (internal is fine) with the eight tokens above as a nested `enum Token: CaseIterable`, each resolving to a `Color` that is the V7 hex in **dark** appearance and the table's system colour in **light** appearance (D-4, § 2.4). Implement with a dynamic provider (`NSColor(name:dynamicProvider:)` / `UIColor { trait in … }`) under `#if os(macOS)` / `#if os(iOS)`; `accent`/`accentSoft` light branch is `Color.accentColor` (with `.opacity(0.18)`). Expose two **pure, testable** tables: `static func darkValue(_ token: Token) -> (red: Double, green: Double, blue: Double, opacity: Double)` (the V7 components) and `static func lightSource(_ token: Token) -> LightSource` where `enum LightSource: Hashable { case quaternarySystemFill, tertiarySystemFill, separator, label, secondaryLabel, tertiaryLabel, accentColor, accentColorSoft }` and `static let accentSoftOpacity: Double = 0.18`; the dynamic providers are built **from** these two tables, so no hex or system-colour name appears anywhere else in the file.
2. Add `Sources/VinetasUI/Swatches/GradientSwatch.swift` (three-colour gradient from `StyleSwatchPalette` triples via `Color(red:green:blue:)`), `StyleSwatchView.swift` (56 × 40, 7 pt radius, picks `MidCenturySwatch` for `.midCenturyModern`), `MidCenturySwatch.swift` (the static `Canvas` moved as is; `t: 0`; **no `TimelineView`**, Non-goal 4). Swatch gradients are identical in both appearances.
3. Add `Sources/VinetasUI/VinetasStyleList.swift`: `public struct VinetasStyleList: View` with `selection: Binding<String>` over `promptText` (`StoryboardStyle.customTag` sentinel for *Other*, last); rows show swatch, `displayName`, `genre` caption, accent halo + checkmark on the selected row; identifiers `VinetasUIAccessibility.stylePickerList` on the list and `stylePickerRow(style.rawValue)` on each row; 6 pt spacing, 56 pt min row height, 7 pt radius; **no outer background**. Two presentations driven by the resolved layout: `.sidebar`/`.regular` → 340 pt wide, 5.5 rows tall (popover body); `.compact` → fills the screen as an inset-grouped `List`. Choosing a row sets the binding (dismissal is the caller's — Sortie 8). `///` on every public symbol.
4. Three `#Preview`s on `VinetasStyleList` named exactly `"Sidebar (macOS)"`, `"Regular (iPad)"`, `"Compact (iPhone)"`, each forcing its layout with `.vinetasPanelLayout(…)` and `traits: .fixedLayout(width:height:)` at **340 × 760**, **1032 × 1376**, **402 × 874** (D-13; `PreviewTrait.fixedLayout` exists — T-02); the selected value in each preview is the granville `style` string (free text → *Other*).
5. `Tests/VinetasUITests/StylePaletteTests.swift`: `darkValue` for each of the eight tokens equals the V7 components (`0x2a/255` … `0x0a84ff` at 1.0 and 0.18) and `lightSource` for each token equals the table above (eight explicit `#expect` lines), `accentSoftOpacity == 0.18`; `Tests/VinetasUITests/StyleListTests.swift`: `VinetasStyleList` instantiates with a constant binding for every `StoryboardStyle.allCases` value plus `customTag` and for `GranvilleFixtures.establishingPanel.style` without trapping, and the row identifier for each case is `stylePicker.row.<rawValue>`.
6. Run `make lint`.

**Exit criteria**:
- [ ] `grep -rn 'TimelineView' Sources/VinetasUI` prints nothing; `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.
- [ ] `grep -c '#Preview(' Sources/VinetasUI/VinetasStyleList.swift` is 3 and `grep -o '#Preview("[^"]*"' Sources/VinetasUI/VinetasStyleList.swift` lists the three exact names.
- [ ] `grep -n '0x' Sources/VinetasUI/VinetasStylePalette.swift` prints lines only inside the `darkValue` function (check: every printed line number lies between the `func darkValue` line and its closing brace); `grep -n 'quaternarySystemFill\|tertiarySystemFill\|separator\|secondaryLabel\|tertiaryLabel' Sources/VinetasUI/VinetasStylePalette.swift | grep -v 'case \|lightSource\|LightSource'` prints only the lines of the two `#if os` dynamic-provider `switch`es that map `LightSource` cases to platform colours (no light-branch literal outside them).
- [ ] `make test-unit` and `make test-unit-ios` exit 0 with `StylePaletteTests` and `StyleListTests` in the logs, zero failures.
- [ ] `make build` exits 0.
- [ ] The DocC check over `Sources/VinetasUI/VinetasStyleList.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests` exits 0.

### Sortie 8: `VinetasStylePicker` and `VinetasPromptPanel`

**Priority**: 21.5 — blocks 6 sorties; risk 2 (popover / navigation-row forms across three layouts).

**Entry criteria**:
- [ ] Sortie 7 exit criteria met.
- [ ] Source to read (read-only, Vinetas app `0c25a3d`): macOS `Vinetas/Views/GenerationStudio/PromptInputPanel.swift` (preset pick replaces the negative prompt and reveals the section `:38–52`; `DisclosureGroup` + `TextField` for negative; `promptTextDisclosure` literal `:137` — V-06, V-14) and iOS `VinetasIOS/Views/GenerationStudio/PromptInputPanel.swift` (toggle button + `TextEditor` for negative `:51–57`; 140/100 pt editor height by size class `:73`; `TextEditor` for custom style; `.scrollDismissesKeyboard(.interactively)`; literal `:172`). `prompt.stylePicker` is declared (`AccessibilityID.swift:110`) but referenced by no view today (V-02) — it becomes the picker button's identifier.
- [ ] Design canvas artboards that bind: "macOS · Right-hand inspector panel" and the three iPhone artboards (<https://claude.ai/artifact/1JSXFojxUWxYWo9dTyztSX>); read via the Artifact tool, not WebFetch.
- [ ] Real samples: `GranvilleFixtures.establishingPanel` (`prompt`, `style`, `negative`) for tests and, inline and verbatim, for previews.

**Tasks**:
1. Add `Sources/VinetasUI/VinetasStylePicker.swift`: `public struct VinetasStylePicker: View` with `selection: Binding<String>`. Form by resolved layout and `vinetasStylePickerStyle`: `.sidebar`/`.regular` → a **button** (identifier `promptStylePicker`) showing the selected style's swatch, name and genre caption, presenting `VinetasStyleList` in a `.popover` (340 × 5.5 rows), dismissing on choice; `.compact` with `vinetasNavigationStackAvailable == true` → a **navigation row** with the same label and a chevron that pushes `VinetasStyleList` via `NavigationLink`; `.compact` with the flag `false` → the popover form (the Sortie 6 decision — document it in the doc comment); `.list` style → the list inline, 5.5 rows tall, regardless of layout (§ 2.3). *Other* (`customTag`) shows a `TextEditor`/`TextField` for the custom style text identified `promptStyleCustom`. Expose the form decision as a pure static `VinetasStylePicker.form(layout:style:navigationAvailable:) -> Form` (`enum Form { case button, navigationRow, inlineList }`).
2. Add `Sources/VinetasUI/VinetasPromptPanel.swift`: `public struct VinetasPromptPanel: View` with `prompt`, `stylePrompt`, `negativePrompt: Binding<String>`, `selectedModel: ModelSummary` (engine badge + hint), `caption: Binding<String>? = nil` (when non-nil a single-line *Caption* field under the prompt identified `promptCaption`; Vinetas passes nil and sees no change). Sections per layout: `.sidebar` → prompt editor, caption, style picker button, *Prompt text* disclosure (`stylePickerPromptTextDisclosure`), Negative Prompt disclosure collapsed until a preset is chosen; `.regular` → same with 140 pt minimum editor and `.scrollDismissesKeyboard(.interactively)`; `.compact` → inset-grouped form: Prompt + Caption in one group with the engine badge in the header, Style as the chevron row, Negative Prompt expanded under its own header, 100 pt minimum editor. Picking a preset writes that style's `negativePromptText` into `negativePrompt` and reveals the section (V-14) — exposed as the pure static `VinetasPromptPanel.applyPreset(_ stylePrompt: String, to negativePrompt: inout String)`. Identifiers: `promptPrimary`, `promptCaption`, `promptNegativeToggle`, `promptNegative`. All user-facing strings through the Sortie 5 localisation helper (add keys to the catalogue). `#if os(iOS)` only for `.keyboardType`, `.scrollDismissesKeyboard`, `Color(.secondarySystemBackground)`; `#if os(macOS)` for `Color(nsColor:)` (T-06). **No outer background fill.** `///` on every public symbol in both files.
3. Three `#Preview`s per view (`VinetasStylePicker`, `VinetasPromptPanel`) with the three exact names and reference sizes from Sortie 7; sample content is the granville establishing shot's `prompt`, `style`, `negative`, with `selectedModel: .klein4B`.
4. `Tests/VinetasUITests/PromptPanelTests.swift`: `applyPreset(StoryboardStyle.noirGraphicNovel.promptText, to:)` sets the negative to `StoryboardStyle.noirGraphicNovel.negativePromptText`; `applyPreset(StoryboardStyle.customTag, to:)` and `applyPreset(GranvilleFixtures.establishingPanel.style, to:)` (free text) leave a negative that starts as `establishingPanel.negative` unchanged; `VinetasStylePicker.form(...)` is `.button` for `.sidebar`/`.regular`, `.navigationRow` for `.compact` + `true`, `.button` for `.compact` + `false`, `.inlineList` for `.list` on every layout; both views instantiate for each of the three layouts with constant bindings holding the establishing panel's strings without trapping.
5. Run `make lint`.

**Exit criteria**:
- [ ] `grep -c '#Preview(' Sources/VinetasUI/VinetasStylePicker.swift` is 3 and the same for `VinetasPromptPanel.swift`, names exact.
- [ ] `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing; `grep -rn 'TimelineView' Sources/VinetasUI` prints nothing.
- [ ] `grep -rn 'String(localized:' Sources/VinetasUI | grep -v 'bundle: .module' | grep -v Localization.swift` prints nothing (every call goes through the helper or names `.module`).
- [ ] `grep -n '#if os' Sources/VinetasUI/VinetasPromptPanel.swift Sources/VinetasUI/VinetasStylePicker.swift | wc -l` is at most 6, and `grep -A3 '#if os(iOS)' Sources/VinetasUI/VinetasPromptPanel.swift Sources/VinetasUI/VinetasStylePicker.swift | grep -v '#if\|#else\|#endif\|^--$\|keyboardType\|scrollDismissesKeyboard\|secondarySystemBackground\|^\S*-\s*$' | grep -c 'layout\|Layout'` is 0 (layout differences are expressed through the resolved layout, not `#if os` — T-06 set only).
- [ ] `make test-unit` and `make test-unit-ios` exit 0 with `PromptPanelTests` in the logs, zero failures; `make build` exits 0.
- [ ] The DocC check over `Sources/VinetasUI/VinetasStylePicker.swift Sources/VinetasUI/VinetasPromptPanel.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests` exits 0.

### Sortie 9: `VinetasGenerationSettingsPanel`

**Priority**: 18.5 — blocks 5 sorties; risk 2 (three layout forms, generic footnote slot).

**Entry criteria**:
- [ ] Sortie 8 exit criteria met (sequential execution; this sortie touches none of Sortie 7–8's files, and needs only Sorties 4–6).
- [ ] Source to read (read-only, Vinetas app `0c25a3d`): macOS `GenerationSettingsPanel.swift` (model picker grouped by engine with size + RAM `:32,65,72,102`; `isProActive` parameter — **dropped**; sliders 1…50 at `:185`, 1.0…20.0 by 0.5 at `:219`; `@Binding var seed: UInt64` at `:23`; `AspectRatioTile`; three `useDefault…` bindings) and iOS `GenerationSettingsPanel.swift` (Steps/Guidance side by side at regular `:34,52`; in-view reset in `.onChange(of: selectedModel)` — **dropped**; `memorychip` RAM label `:132`). Aspect tiles: horizontal strip today on both (V-03, V-12, V-15).
- [ ] Real samples: `GranvilleFixtures.establishingPanel` (`steps` 8, `guidance` 3.5, `seed` 22) and `defaultsShot["aspect"] == "wide"` for tests and previews.

**Tasks**:
1. Add `Sources/VinetasUI/AspectRatioTile.swift` (identifier `aspectRatioTile(rawValue)`), moved from the macOS panel.
2. Add `Sources/VinetasUI/VinetasGenerationSettingsPanel.swift`: `public struct VinetasGenerationSettingsPanel<Footnote: View>: View` with `models: [ModelSummary]` (host-filtered; picker groups by `engineID`, shows `approximateDownloadSize` and `minimumMemoryGB` as text only — never a gate), `selectedModel: Binding<ModelSummary>`, `aspectRatio: Binding<AspectRatio>`, `steps: Binding<Int>`, `guidance: Binding<Float>`, `seed: Binding<UInt64>` (the app's type, `GenerationSettingsPanel.swift:23`, and the draft's § 2.3 type), `randomizeSeed: Binding<Bool>`, optional `useDefaultSteps`, `useDefaultGuidance`, `useDefaultAspectRatio: Binding<Bool>?` (nil renders no toggle), and `@ViewBuilder footnote` rendered under the model picker (default `EmptyView`). Layouts: `.sidebar` → single column, aspect tiles in one horizontal strip with Default, Steps and Guidance sliders each with value and Default (checkbox on macOS via `#if os(macOS) .toggleStyle(.checkbox)`), Seed with Randomize; `.regular` → Steps and Guidance **side by side**; `.compact` → inset-grouped: Model as inline menu row with size + RAM in the footer, aspect tiles **wrapping** with a Default switch row, Steps/Guidance cells with value and a Default switch, Seed with a Randomize switch. Slider ranges 1…50 and 1.0…20.0 step 0.5 (Non-goal 3). Identifiers: `generationModelPicker`, `generationAspectRatioSelection`, `aspectRatioTile(...)`, `generationStepsSlider`, `generationStepsUseDefault`, `generationGuidanceSlider`, `generationGuidanceUseDefault`, `generationAspectRatioUseDefault`, `generationSeedField`, `generationRandomizeSeed`. **No** `isProActive`, **no** reset on model change, **no** `generation.memoryWarning` view (§ 2.3). `.keyboardType(.numberPad)` on the seed field under `#if os(iOS)`. The engine grouping is the pure static `VinetasGenerationSettingsPanel.groupedByEngine(_ models: [ModelSummary]) -> [(engineID: String, models: [ModelSummary])]`. `///` on every public symbol.
3. Three `#Preview`s with the exact names and reference sizes; preview state is `.klein4B`, `.wide`, steps 8, guidance 3.5, seed 22 (the establishing panel's values).
4. `Tests/VinetasUITests/GenerationSettingsPanelTests.swift`: `groupedByEngine(ModelSummary.all)` preserves order (`flux2` then `pixart-sigma`) and `groupedByEngine([.klein4B])` is one group; the panel instantiates for the three layouts with and without the three optional bindings, with state taken from `GranvilleFixtures.establishingPanel` (`steps`, `guidance`, `seed`) and `AspectRatio(rawValue: defaultsShot["aspect"]!) == .wide`, without trapping.
5. Run `make lint`.

**Exit criteria**:
- [ ] `grep -c '#Preview(' Sources/VinetasUI/VinetasGenerationSettingsPanel.swift` is 3, names exact.
- [ ] `grep -rn 'isProActive\|memoryWarning\|requiresPro' Sources/VinetasUI --include=*.swift | grep -v VinetasUIAccessibility.swift` prints nothing; `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.
- [ ] `grep -n '1\.\.\.50\|1\.0\.\.\.20\.0\|step: 0\.5' Sources/VinetasUI/VinetasGenerationSettingsPanel.swift` shows both ranges and the step; `grep -n 'seed: Binding<UInt64>' Sources/VinetasUI/VinetasGenerationSettingsPanel.swift` prints one line.
- [ ] `make test-unit` and `make test-unit-ios` exit 0 with `GenerationSettingsPanelTests` in the logs; `make build` exits 0.
- [ ] The DocC check over `Sources/VinetasUI/VinetasGenerationSettingsPanel.swift Sources/VinetasUI/AspectRatioTile.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests` exits 0.

### Sortie 10: `VinetasPromptDraft` and `VinetasPromptComposer`

**Priority**: 17 — blocks 4 sorties; the draft is the host contract (foundation); risk 2 (Default/Randomize bridging semantics).

**Entry criteria**:
- [ ] Sorties 8 and 9 exit criteria met.
- [ ] Real samples: all 13 `GranvilleFixtures.panels()` plus `defaultsShot` and `sceneHeading` — the fully-populated draft is the establishing shot (`prompt`, `style`, `negative`, `model` id, `.wide`, 8, 3.5, 22) with `caption = sceneHeading`.

**Tasks**:
1. Add `Sources/VinetasUI/VinetasPromptDraft.swift`: `public struct VinetasPromptDraft: Hashable, Sendable, Codable` with exactly the § 2.3 fields and defaults (`prompt = ""`, `caption: String? = nil`, `stylePrompt = ""`, `negativePrompt = ""`, `modelID = ModelSummary.pixartSigmaXL.id`, `aspectRatio: AspectRatio? = nil`, `steps: Int? = nil`, `guidance: Float? = nil`, `seed: UInt64? = nil`), computed `model: ModelSummary?` and `style: StoryboardStyle?`, `static let empty`. **`AspectRatio` is not `Codable`** (Sortie 4 hit this): hand-write `Codable` encoding `aspectRatio` as its `rawValue` string, exactly as `ModelSummary` does — do not add a conformance to `AspectRatio`. Stable `Codable` keys (document that hosts may persist it across the next minor's patch line — § 3 item 5). `///` on every public symbol.
2. Add `Sources/VinetasUI/VinetasPromptComposer.swift`: `public struct VinetasPromptComposer: View` with `init(draft: Binding<VinetasPromptDraft>, models: [ModelSummary] = ModelSummary.all, showsCaption: Bool = false)` — the three views stacked and bound to the one struct. **Default/Randomize semantics (D-12):** a Default toggle *on* means the field is `nil` and the slider shows the selected model's default dimmed; turning it *off* writes that model's default into the field as a starting point; the composer **never** writes a model default back into the draft while the toggle is on; `seed == nil` means Randomize on. Model change does not reset steps/guidance (host's job). The bridging is the pure statics `VinetasPromptComposer.setDefault(_ field: DraftField, on isDefault: Bool, in draft: inout VinetasPromptDraft, model: ModelSummary)` (`enum DraftField { case steps, guidance, aspectRatio }`) and `VinetasPromptComposer.setRandomize(_ on: Bool, in draft: inout VinetasPromptDraft)`. `///` on every public symbol.
3. Three `#Preview`s on the composer, exact names and reference sizes; the preview draft is the establishing shot.
4. `Tests/VinetasUITests/PromptDraftTests.swift`: `empty` equals a default-initialised draft; JSON round-trip of the establishing-shot draft (fully populated, `caption = sceneHeading`) and of `empty` is lossless; a draft built from each of the 13 `panels()` (`prompt`, `style`, `negative`, `modelID = panel.model`, `.wide`, `steps`, `guidance`, `seed`) round-trips losslessly and has `model == .klein4B`; `model` is `nil` for the invented id `"klein9b"`; `style` recovers each preset from its `promptText` and is `nil` for `establishingPanel.style` (free text); Codable key names are the field names (assert the encoded JSON's keys). `Tests/VinetasUITests/PromptComposerTests.swift`: `setDefault(.steps, on: true)` / `.guidance` / `.aspectRatio` set the field to `nil`; `on: false` writes `model.defaultSteps` / `model.defaultGuidance` / `model.supportedAspectRatios[0]`; `setRandomize(true)` sets `seed = nil`, `setRandomize(false)` on the establishing draft leaves `seed == 22`; composer instantiates for three layouts with `showsCaption` true and false.
5. Run `make lint`.

**Exit criteria**:
- [ ] `grep -c '#Preview(' Sources/VinetasUI/VinetasPromptComposer.swift` is 3, names exact; total `grep -rc '#Preview(' Sources/VinetasUI | awk -F: '{s+=$2} END {print s}'` is 15 (five views × three).
- [ ] `grep -n 'static func setDefault\|static func setRandomize' Sources/VinetasUI/VinetasPromptComposer.swift` prints two lines.
- [ ] `make test-unit` and `make test-unit-ios` exit 0 with `PromptDraftTests` and `PromptComposerTests` in the logs; `make build` exits 0.
- [ ] `grep -rn 'accessibilityIdentifier("' Sources/VinetasUI` prints nothing.
- [ ] The DocC check over `Sources/VinetasUI/VinetasPromptDraft.swift Sources/VinetasUI/VinetasPromptComposer.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests` exits 0.

### Sortie 11: `vinetasPromptInspector` — the inspector presentation

**Priority**: 11.5 — blocks 3 sorties; risk 2 (inspector modifier + idiom policy).

**Entry criteria**:
- [ ] Sortie 10 exit criteria met.
- [ ] **iPhone no-op (OQ-4 decision)**: on the phone idiom the modifier returns `self` unchanged and calls `assertionFailure` **from `body` evaluation only** — debug builds trap when a host renders the inspector on iPhone, release builds are a no-op; nothing fires at construction, and `precondition` is never used. Tests construct the view without evaluating `body`, so `make test-unit-ios` on iPhone 17 stays green.
- [ ] Ground truth (recon `CONFIRMED`): `.inspector(isPresented:content:)` and `.inspectorColumnWidth(min:ideal:max:)` exist on macOS and iOS in the 26 SDKs (`iOS 17 / macOS 14`; `ideal` required — T-03). Whether `.inspector` presents a sheet on iPhone is UNVERIFIABLE (T-03b) and **moot** because the modifier is a no-op on iPhone (§ 2.6).
- [ ] Real sample for the preview: the establishing-shot draft.

**Tasks**:
1. Add `Sources/VinetasUI/VinetasPromptInspector.swift`: `extension View { public func vinetasPromptInspector<Header: View, Actions: View>(isPresented:draft:models:showsCaption:header:actions:) -> some View }` with the § 2.6 signature and defaults. On macOS and on iOS when the device idiom is **pad**: `.inspector(isPresented:)` with `.inspectorColumnWidth(min: 300, ideal: 340, max: 420)`, content = `header` pinned top, `VinetasPromptComposer` scrolling in the middle with `.vinetasPanelLayout(.sidebar)` forced, `actions` pinned bottom; non-modal (no `.interactiveDismissDisabled`, no sheet). On iOS **phone** idiom: return `self` unchanged and raise `assertionFailure` from `body` evaluation (never at construction), with a doc comment pointing at recipe 2. The platform decision is the pure static `VinetasPromptInspectorPolicy.presents(onIdiom:) -> Bool` (`enum Idiom { case mac, pad, phone }`). The package draws no action of its own (D-8): this file contains no `Button`, `Toggle` or `Menu`. `///` on every public symbol.
2. Add `Sources/VinetasUI/VinetasPromptInspectorPreview.swift` under `#if os(macOS)` holding the one `#Preview("Inspector (macOS)")` at 1280 × 800: a placeholder document with the inspector open on the establishing-shot draft and a host-supplied `actions:` row (the preview is the host here, so a Save button is allowed in this file only).
3. `Tests/VinetasUITests/PromptInspectorTests.swift`: the modifier type-checks with `EmptyView` header default and a `Button` actions row (construction only — `body` is not evaluated); `VinetasPromptInspectorPolicy.presents(onIdiom:)` is `true` for `.mac`, `true` for `.pad`, `false` for `.phone`.
4. Run `make lint`.

**Exit criteria**:
- [ ] `grep -c '#Preview("Inspector (macOS)"' Sources/VinetasUI/VinetasPromptInspectorPreview.swift` is 1; repo-wide `grep -rc '#Preview(' Sources/VinetasUI | awk -F: '{s+=$2} END {print s}'` is 16 (Acceptance 2).
- [ ] `grep -n 'precondition(' Sources/VinetasUI/VinetasPromptInspector.swift` prints nothing; `grep -c 'assertionFailure(' Sources/VinetasUI/VinetasPromptInspector.swift` is 1; `grep -n 'inspectorColumnWidth(min: 300, ideal: 340, max: 420)' Sources/VinetasUI/VinetasPromptInspector.swift` prints one line.
- [ ] `grep -n 'Button(\|Toggle(\|Menu(' Sources/VinetasUI/VinetasPromptInspector.swift` prints nothing (D-8 — no Save, Cancel, Generate or Remove control drawn by the modifier).
- [ ] `make test-unit` and `make test-unit-ios` exit 0 with `PromptInspectorTests` in the logs (the iOS run is on iPhone 17 — the construction-only test is what keeps it green); `make build` exits 0.
- [ ] The DocC check over `Sources/VinetasUI/VinetasPromptInspector.swift` prints nothing.
- [ ] `swift format lint --strict -r Sources/VinetasUI Tests/VinetasUITests` exits 0.
- [ ] [judgment] The inspector content is header / scrolling composer / pinned actions in that order — decidable from the `inspector` content closure in the diff.

---

## WU-3 — Release phase (`Makefile`, `Tools/UIIsolationProbe`, `docs/VinetasUI.md`, `.github/workflows/tests.yml`)

Requirements: § 2.1 (`make verify-ui-isolation`), § 3 (seven sections), § 4 (CI), D-2, D-11; Acceptance 1, 2, 5. Also the Products table § 4 asks `AGENTS.md` and `README.md` to carry. No version literal is edited. Order: Makefile targets first (so the guide documents the committed target), then the guide, then the workflow (which runs the complete suite).

### Sortie 12: Makefile — `lint-check`, `verify-ui-isolation` with the committed probe, test filters, `build-ios`

**Priority**: 10 — blocks 2 sorties; risk 3 (new tooling: xcodebuild probe, `otool`/`nm` detectors with a self-test).

**Entry criteria**:
- [ ] Sortie 11 exit criteria met (both new products exist).
- [ ] **Probe mechanism (OQ-6 decision)**: a **committed probe package** at `Tools/UIIsolationProbe/` — a tiny package depending on this package by `path: "../.."` with two executable targets: `UIIsolationProbe` (imports **only** `VinetasUI`) and `UIIsolationProbeEngine` (imports `SwiftVinetas` on purpose — the self-test subject). Built by `make verify-ui-isolation` through `xcodebuild` (never `swift build`), then checked with `otool -L`, `nm -gU` and a grep of the build log for MLX/Flux2/PixArt/Tuberia/Acervo; `EXPECT_FAIL=1 make verify-ui-isolation` builds the engine-linking target and must make the check fail.
- [ ] Ground truth (recon `CONFIRMED`): `lint` = `swift format -i -r .` (`Makefile:291–292`); `test-unit` / `test-unit-ios` filter at `:131` / `:245` (now carrying three `-only-testing:` flags from Sorties 1 and 5); `build-ios` at `:96` builds `-scheme $(SCHEME_LIB)` (`SwiftVinetas`) only; `DERIVED_DATA = /tmp/SwiftVinetasBuild` (`:30`); `.PHONY` at `:68` (R-10). `swift-format`, `otool`, `nm` resolve via `xcrun --find` (T-05). `.gitignore:13` has an unanchored `Package.resolved`.

**Tasks**:
1. `lint-check`: `swift format -i -r .` then `git diff --exit-code` (so lint can fail). Before adding it, run `make lint` on the whole repo once; if pre-existing files change, commit that formatting-only diff as its own commit titled as such so `lint-check` starts green.
2. Add `Tools/UIIsolationProbe/Package.swift` (platforms `.macOS(.v26)`; `dependencies: [.package(path: "../..")]`; `executableTarget UIIsolationProbe` depending on `.product(name: "VinetasUI", package: "SwiftVinetas")`; `executableTarget UIIsolationProbeEngine` depending on `.product(name: "SwiftVinetas", package: "SwiftVinetas")`), `Sources/UIIsolationProbe/main.swift` (`import VinetasUI`; prints `VinetasUIAccessibility.promptPrimary` so the module is really linked) and `Sources/UIIsolationProbeEngine/main.swift` (`import SwiftVinetas`; prints `Flux2ModelDescriptor.klein4B.id`). Confirm `.gitignore` covers `Tools/UIIsolationProbe/.build/` and `Tools/UIIsolationProbe/Package.resolved` (add `Tools/UIIsolationProbe/.build/` if the existing `.build` pattern is root-anchored).
3. `verify-ui-isolation`: `SCHEME=$${EXPECT_FAIL:+UIIsolationProbeEngine}; SCHEME=$${SCHEME:-UIIsolationProbe}`; `cd Tools/UIIsolationProbe && xcodebuild build -scheme $$SCHEME -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED_DATA)/ui-isolation 2>&1 | tee ../../build/ui-isolation.log`; then on the built executable (`$(DERIVED_DATA)/ui-isolation/Build/Products/Debug/$$SCHEME`) run `otool -L` and `nm -gU`, and grep the log's `SwiftCompile|CompileSwift|SwiftDriver|Ld ` lines; `PATTERN='MLX|Flux2|PixArt|Tuberia|Acervo'`; the check **fails** (prints the matching lines, exits non-zero) if any of the three greps `-E "$$PATTERN"` matches. With `EXPECT_FAIL=1` the target exits 0 **only if** the inner check failed, and exits non-zero (printing `EXPECT_FAIL: detector did not fire`) if it passed.
4. `build-ios`: keep the existing `xcodebuild build -scheme $(SCHEME_LIB)` invocation and add a second one `xcodebuild build -scheme VinetasUI -destination $(DESTINATION_IOS) -derivedDataPath $(DERIVED_DATA)` so `VinetasUI` is built for the simulator (§ 4).
5. Confirm `test-unit` and `test-unit-ios` carry exactly `-only-testing:SwiftVinetasTests -only-testing:VinetasVocabularyTests -only-testing:VinetasUITests`; add `lint-check verify-ui-isolation` to `.PHONY` and `##` help comments; `AGENTS.md`/`CLAUDE.md` build-command lists gain the two new targets (one line each; no version edits).
6. Run `make lint`.

**Exit criteria**:
- [ ] `make lint-check` exits 0 on a clean tree; negative check: introduce a formatting error in a scratch file under `Tests/`, confirm `make lint-check` exits non-zero, then revert.
- [ ] `test -f Tools/UIIsolationProbe/Package.swift && grep -c 'executableTarget' Tools/UIIsolationProbe/Package.swift` is 2; `grep -n '^import' Tools/UIIsolationProbe/Sources/UIIsolationProbe/main.swift` prints only `import VinetasUI`; `grep -rn 'swift build\|swift run' Makefile Tools/UIIsolationProbe` prints nothing.
- [ ] `make verify-ui-isolation` exits 0 and `build/ui-isolation.log` exists; `EXPECT_FAIL=1 make verify-ui-isolation` exits 0 and its output contains at least one matched symbol or module name from `MLX|Flux2|PixArt|Tuberia|Acervo` (the detector fired on the engine-linking probe).
- [ ] `make build-ios` exits 0 and its output contains a compile line for `VinetasUI` (`grep -c 'VinetasUI' <captured output>` is at least 1).
- [ ] `grep -c 'only-testing:' Makefile` is 6; `grep -n "^DESTINATION_IOS = 'platform=iOS Simulator,name=iPhone 17,OS=26.5'$" Makefile` prints one line; `grep -n 'OS=latest' Makefile` prints nothing.
- [ ] `grep -c 'lint-check\|verify-ui-isolation' AGENTS.md CLAUDE.md` is at least 1 per file; `git status --porcelain Tools/UIIsolationProbe | grep -c 'Package.resolved\|\.build'` is 0.
- [ ] `make test-unit` and `make test-unit-ios` exit 0 end to end.
- [ ] The version guard prints nothing.

### Sortie 13: `docs/VinetasUI.md`, compiled host recipes, Products table, DocC reconciliation

**Priority**: 5 — blocks 1 sortie; risk 1 (documentation + two tests).

**Entry criteria**:
- [ ] Sortie 12 exit criteria met (every public symbol the guide names exists and `make verify-ui-isolation` is the committed target section 1 describes).
- [ ] Ground truth (recon `CONFIRMED`): `AGENTS.md` and `README.md` exist and have no Products section; `docs/VinetasUI.md` does not exist (R-15).
- [ ] Recipe-test behaviour on iPhone (OQ-4 decision): `HostRecipeTests` **constructs** each recipe's hosting view and never evaluates `body`, so recipe 1 (the inspector) is green on the iPhone 17 run.
- [ ] Real samples for the guide and tests: the fountain's line-7 defaults shot and the establishing shot directive (`episode_1_01_cold_open.fountain`) for the GLOSA table; `ep1_sc1_01_establishing.json` values for the recipes' sample draft and `sceneHeading` for the caption.

**Tasks**:
1. Write `docs/VinetasUI.md` (frontmatter `type: doc`, `updated: <today>`) with the seven § 3 sections **in order**: (1) What you link — `VinetasUI` + `VinetasVocabulary` only, what resolution clones and why it is not linked, the `otool -L` / `nm -gU` recipe exactly as `make verify-ui-isolation` runs it (name the target and `EXPECT_FAIL=1`), no App Group / entitlement / model download; (2) Recipe 1 — macOS / iPad inspector, a complete `ContentView` under forty lines (`@State` draft, `@State` Bool, toolbar toggle with `sidebar.trailing`, `.vinetasPromptInspector(isPresented:draft:actions:)` with a Save button calling the host's own save), captioned against the canvas's inspector artboard; (3) Recipe 2 — iPhone pushed screen (`NavigationStack`, chevron row pushing a screen with `VinetasPromptComposer(draft:showsCaption:)` and a trailing `Save` in the navigation bar), captioned against the three iPhone artboards, with the note that the same code at regular width on iPad gets `.regular` and a host wanting the inspector on iPad keys on `horizontalSizeClass`; (4) Recipe 3 — the three views directly, with the optional Default bindings and the footnote slot; (5) The draft's contract field by field (`nil` meanings, `stylePrompt` is a preset's `promptText` or free text and `style` recovers it, `modelID` is a `ModelSummary.id` and `model?.cliName` is the external vocabulary, `Codable` stable across the next minor's patch line); (6) Mapping to a GLOSA `<shot>` as a worked table (`prompt`, `caption`, `style = stylePrompt`, `model = cliName`, `aspect = aspectRatio?.rawValue`, `steps`, `guidance`, `seed`, `negative`) whose example column is the granville defaults shot + establishing shot, with the source file named — documentation, not code; (7) Appearance, layout override, identifiers, strings — one paragraph each pointing at `VinetasPanelLayout`, `vinetasStylePickerStyle`, `vinetasNavigationStackAvailable` (the stack-less fallback), `VinetasUIAccessibility`, the `.module` bundle. The sample draft in both recipes is the establishing shot. Wrap the recipe 1 and recipe 2 code blocks in `<!-- recipe-1:begin -->` / `<!-- recipe-1:end -->` (and `recipe-2`) HTML comment markers.
2. Add `Tests/VinetasUITests/HostRecipeTests.swift` containing each recipe **verbatim** as a hosting view between `// recipe-1:begin` / `// recipe-1:end` (and `recipe-2`) comment markers, with a test that constructs each hosting view without a window and without evaluating `body`.
3. Add `Tests/VinetasUITests/HostRecipeDocSyncTests.swift`: reads `docs/VinetasUI.md` and `HostRecipeTests.swift` via `#filePath`-relative URLs, extracts the text between the matching markers (stripping the Markdown fence lines from the doc side), and asserts byte equality for recipe 1 and recipe 2 (Acceptance 5, D-11).
4. Reconcile the DocC comments on every public symbol in `Sources/VinetasUI` and the new `Sources/VinetasVocabulary` types with the guide — same meaning of `nil`, same layout names, same identifier strings, same words (§ 3 preamble). The comments exist already (standing rule); this task edits wording only.
5. `AGENTS.md` and `README.md`: add a *Products* table — `SwiftVinetas`, `VinetasCLICore`, `vinetas`, `VinetasVocabulary`, `VinetasUI` — one line each on what links what, plus a link to `docs/VinetasUI.md`. Do **not** touch `AGENTS.md:8` (the version line) or `README.md:42,235`.
6. Run `make lint`.

**Exit criteria**:
- [ ] `test -f docs/VinetasUI.md` and `grep -c '^## ' docs/VinetasUI.md` is at least 7 with the seven headings in § 3 order (grep each title keyword in sequence with `awk`).
- [ ] `grep -c 'recipe-1:begin\|recipe-1:end\|recipe-2:begin\|recipe-2:end' docs/VinetasUI.md` is 4 and the same count in `Tests/VinetasUITests/HostRecipeTests.swift`.
- [ ] `awk '/recipe-1:begin/,/recipe-1:end/' docs/VinetasUI.md | grep -vc 'recipe-1\|^```'` is at most 40 (recipe 1 under forty lines).
- [ ] `grep -c 'verify-ui-isolation\|EXPECT_FAIL' docs/VinetasUI.md` is at least 2; `grep -c 'episode_1_01_cold_open.fountain' docs/VinetasUI.md` is at least 1; `grep -c 'vinetasNavigationStackAvailable' docs/VinetasUI.md` is at least 1.
- [ ] `grep -n 'VinetasVocabulary\|VinetasUI' README.md AGENTS.md | grep -i 'products\|docs/VinetasUI.md'` shows the table and the link in both files.
- [ ] `make test-unit` and `make test-unit-ios` exit 0 with `HostRecipeTests` and `HostRecipeDocSyncTests` in the logs, zero failures.
- [ ] The DocC check over `Sources/VinetasUI/*.swift Sources/VinetasUI/Swatches/*.swift Sources/VinetasVocabulary/StoryboardStyle.swift Sources/VinetasVocabulary/StyleSwatchPalette.swift Sources/VinetasVocabulary/ModelSummary.swift` prints nothing.
- [ ] `swift format lint --strict -r Tests/VinetasUITests Sources/VinetasUI Sources/VinetasVocabulary` exits 0.
- [ ] The version guard prints nothing.
- [ ] [judgment] Each public symbol's DocC summary line is consistent with the guide's description of it (same meaning of `nil`, same layout names, same identifier strings).

### Sortie 14: `tests.yml` — lint-check first, isolation gate, the `unit-tests-ios` job, and the draft PR that proves CI

**Priority**: 3.5 — terminal sortie; risk 3 (the only step whose truth is remote: `macos-26`).

**Entry criteria**:
- [ ] Sorties 12 and 13 exit criteria met (the full suite CI will run exists and passes locally).
- [ ] **CI proof (OQ-2 decision)**: this sortie **pushes the mission branch and opens a draft PR against `development`** so `tests.yml` runs once on `macos-26`; the exit criterion is that run green. The PR **stays draft until the mission closes** (the user converts or closes it). Local Xcode 27 / Swift 6.4 is ahead of CI; CI is the truth.
- [ ] Ground truth (recon `CONFIRMED`): `tests.yml` has one job `unit-tests` "Unit Tests (macOS)" on `macos-26` running `make build` → `make test-unit` → Acervo-warning log check → summary (R-09); `pixart-integration.yml` also runs on PRs to `main`/`development` and must stay green (recon drift note). User rule: runners `macos-26` or later; iOS destination pins an exact OS (`OS=latest` does not work).

**Tasks**:
1. `unit-tests` job: insert `make lint-check` as the first step after checkout/swift-version; keep `make build`, `make test-unit`, the Acervo-warning check and the summary; add `make verify-ui-isolation` after `make test-unit`.
2. Add job `unit-tests-ios` ("Unit Tests (iOS)") on `macos-26`, `timeout-minutes: 45`, steps: checkout, `swift --version`, `xcrun simctl list runtimes` (diagnostic), `make test-unit-ios DESTINATION_IOS='platform=iOS Simulator,name=iPhone 17,OS=26.5'` (the same value as the Makefile default — belt and braces), and an `if: always()` step that prints the tail of `build/test-output-ios.log`.
3. Do not change `pixart-integration.yml`; confirm its steps still build (they build the package; the re-export keeps them compiling).
4. Validate YAML locally (`ruby -ryaml -e 'YAML.load_file(".github/workflows/tests.yml")'`; `actionlint` if installed).
5. Run `make lint`, commit, push the mission branch, and open a **draft** PR into `development` (title prefixed `[mission]`, body naming this plan). Wait with `gh pr checks <pr> --watch` for `Unit Tests (macOS)`, `Unit Tests (iOS)` and the PixArt integration check. If a job fails for a cause that is a real defect, report `PARTIAL` with the log excerpt — never edit a check to make it pass (user rule); a fix lands as a further commit on the mission branch and the checks re-run. Leave the PR in draft.

**Exit criteria**:
- [ ] `ruby -ryaml -e 'YAML.load_file(".github/workflows/tests.yml")'` exits 0; `grep -c 'runs-on: macos-26' .github/workflows/tests.yml` is 2; `grep -n "name=iPhone 17,OS=26.5" .github/workflows/tests.yml` prints one line; `grep -rn 'OS=latest' .github/workflows` prints nothing.
- [ ] The step order in `unit-tests` is checkout → swift-version → `make lint-check` → `make build` → `make test-unit` → `make verify-ui-isolation` → Acervo-warning check → summary (`grep -n 'run: make' .github/workflows/tests.yml` prints `lint-check`, `build`, `test-unit`, `verify-ui-isolation` in that order for the first job).
- [ ] Local mirror of every CI step exits 0: `make lint-check && make build && make test-unit && make verify-ui-isolation && make test-unit-ios DESTINATION_IOS='platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- [ ] `gh pr view <pr> --json isDraft,baseRefName -q '[.isDraft,.baseRefName]'` prints `[true,"development"]`.
- [ ] `gh pr checks <pr>` reports `Unit Tests (macOS)`, `Unit Tests (iOS)` and the PixArt integration check as passing on the mission branch head.
- [ ] The version guard prints nothing; `git diff HEAD~1 -- README.md | grep -E '^[-+].*[0-9]+\.[0-9]+\.[0-9]+'` prints nothing.

---

## Manual acceptance outside the sorties

These acceptance items are human judgments the plan cannot machine-verify; they are owed by the user after Sortie 14 and before `/ship-swift-library minor`:

- **Acceptance 2 (render)** — all sixteen `#Preview`s render in Xcode's canvas.
- **Acceptance 4** — a dark-appearance render of `VinetasStyleList` at 340 pt matches the Vinetas studio's list row for row; a light render shows the OQ-5 system fills with the same swatches.
- **Acceptance 6 / requirements OQ-3** — the inspector artboard and the three iPhone artboards are reproduced closely enough for one manual sign-off.
- **Draft PR** — convert Sortie 14's draft PR to ready (or close it) when the mission closes.

---

## Parallelism Structure

**Critical Path**: Sortie 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 (length: 14 sorties — the whole plan).

**Parallel Execution Groups**: none. Every layer holds one work unit and every work unit runs its sorties in order; **maximum concurrent sortie agents: 1**.

**Why the plan declines the parallelism the graph allows** (identified, not taken):
- Sortie 4 (`ModelSummary`) needs only Sortie 1, not Sorties 2–3; Sortie 9 (settings panel) needs only Sorties 4–6, not 7–8; Sortie 12 (Makefile) needs only Sortie 5's product, not Sortie 11. Each pair *could* run concurrently.
- They are kept sequential because every sortie carries `make` build/test steps and the supervisor dispatches sorties into **one shared working tree**: concurrent `xcodebuild` runs share `DERIVED_DATA` and overwrite `build/test-output*.log`; `make lint` (`swift format -i -r .`) rewrites files another agent is mid-edit; Sorties 2 and 5 edit `Package.swift`, Sorties 1, 5 and 12 edit the `Makefile`, Sorties 12 and 13 edit `AGENTS.md`. The clobber risk outweighs the saving of roughly three sorties of wall time.
- These opportunities become safe only with a git worktree per work unit and per-worktree derived data, which this supervisor does not provide. If that lands, re-split WU-1 as {S1→S2→S3} ∥ {S4}, WU-2 as {S7→S8} ∥ {S9} after S6, and WU-3 as {S12} ∥ {S13} — the exit criteria already hold under either shape.

**Agent Constraints**:
- Every sortie runs its own `make` steps; a sortie agent may not fan out sub-agents that run `make`, `xcodebuild` or `swift format -i`.
- No sortie reads or writes outside the paths listed in its tasks and the read-only paths in § Repositories read.

---

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

`Package.resolved` is gitignored (no committed lock). Locally every `intrusive-memory` dependency resolves to its sibling checkout via the `sibling(…)` helper (`Package.swift:23–40`); CI resolves each to the newest release in range, which today is exactly the `from:` floor. **The two new targets (`VinetasVocabulary`, `VinetasUI`) depend on none of these.** All six siblings are ahead of their tags, three dirty — nothing in this plan rests on drifted source.

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.3` → CI `v3.4.3` | `~/Projects/package-collection/pkg/flux-2-swift-mlx` (`9a36b26`, 1 ahead, clean) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` → CI `v0.25.0` | `~/Projects/package-collection/pkg/SwiftAcervo` (`13e2879`, 4 ahead, dirty) | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` → CI `v0.9.0` | `~/Projects/package-collection/pkg/SwiftTuberia` (`d74977a`, 1 ahead, dirty) | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.2` → CI `v0.8.2` | `~/Projects/package-collection/pkg/pixart-swift-mlx` (`3ce2541`, 1 ahead, clean) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/glosa-av | `from: 0.8.1` → CI `v0.8.1` | `~/Projects/package-collection/pkg/glosa-av` (`efb640f`, 1 ahead, clean) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | `from: 7.2.5` → CI `v7.2.5` | `~/Projects/package-collection/pkg/SwiftCompartido` (`8894c6e`, 20 ahead, dirty) | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| marcprux/universal | `from: 5.3.0` → `5.3.0` (`7919463c`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` → `1.8.2` (`6a52f325`) | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor: 0.7.1` → `0.7.1` (`e4e01cb5`) | `~/Projects/swift-tokenizers` (`37f999a`, near `0.6.2`) | LOCAL_BEHIND |
| apple/swift-certificates | `from: 1.0.0` → `1.19.4` (`449dbbec`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-crypto | `from: 3.0.0` → `3.15.1` (`95ba0316`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-asn1 | `from: 1.0.0` → `1.7.1` (`a9a5efd4`) | — | NO_LOCAL_CHECKOUT |

### Repositories read, not depended on (read-only for every sortie)

| Repository | Local checkout | Revision | Used by |
|---|---|---|---|
| intrusive-memory/Vinetas (app) | `~/Projects/apps/Vinetas` | `0c25a3d`, `docs/dossier-integration`, clean | Sorties 2, 3, 7, 8, 9 (source of the panel, `StoryboardStyle`, palette, identifiers, fixture) |
| granville podcast project (real fixtures) | `~/Projects/podcasts/granville` — `episodes/episode_1_01_cold_open.fountain`, `storyboards/*.json` | working copy as of 2026-10-18 (13 panels) | Sorties 4, 5 (copy); 7–11, 13 (consume the copies) |
| intrusive-memory/SwiftFijos (optional fixture helper) | `~/Projects/package-collection/pkg/SwiftFijos` | newest tag | fallback only, if `Bundle.module`/`#filePath` lookup fails on CI |
| intrusive-memory/SwiftAcervo (precedent) | `~/Projects/package-collection/pkg/SwiftAcervo` — read at tag `v0.25.0` via `git show` | `v0.25.0` | Sortie 5 (`AcervoUIAccessibility` shape) |
| intrusive-memory/SwiftEscribo (precedent) | `~/Projects/package-collection/pkg/SwiftEscribo` — read at tag `v0.4.2` via `git show` | `v0.4.2` | Sortie 6 (`WellLane.width` resolver + exhaustive test shape) |
| intrusive-memory/Escribir (step-3 host; informational only) | `~/Projects/apps/Escribir` | `e07091c`, no SwiftVinetas dependency | none — out of this mission |

---

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). All six blocking questions were resolved by the user on 2026-10-18 and propagated into the sorties named under each; refine Pass 1 found zero blockers. -->

Carried from the requirements but **not blocking this plan**: requirements OQ-1 (acceptable resolution cost in a host; measured in Escribir's mission; an `xcframework` is a later mission if rejected) — no sortie here depends on its answer. Requirements OQ-2 and OQ-3 are resolved there (target name `VinetasVocabulary`; fixed-layout previews + one manual look, which is § Manual acceptance above). Recon T-07b (`Bundle.module`) is the verification step in Sorties 2 and 5; the CI SDK surface is proven by Sortie 14's draft PR.

### OQ-1 — RESOLVED 2026-10-18 (user): Makefile `DESTINATION_IOS` default
**Decision**: The default becomes `platform=iOS Simulator,name=iPhone 17,OS=26.5`, still overridable from the environment. `OS=latest` is never used. The new `unit-tests-ios` CI job passes the same destination explicitly.
**Propagated to**: Standing rules; Sortie 1 (task 5b sets it — so every iOS run in the plan is on CI's destination), Sorties 1–13 (`make test-unit-ios` exit criteria no longer reference an open default), Sortie 12 (exit criterion confirms it), Sortie 14 (task 2, exit criteria).

### OQ-2 — RESOLVED 2026-10-18 (user): may the CI sortie push and open a PR?
**Decision**: Yes. Sortie 14 pushes the mission branch and opens a **draft** PR against `development` so `tests.yml` runs once on `macos-26`; its exit criterion is that run green. The PR stays draft until the mission closes. Local Xcode 27 / Swift 6.4 is ahead of CI; CI is the truth.
**Propagated to**: Mission statement; Standing rules; Sortie 5 and 6 exit criteria (the 27-only annotation grep is the local guard, Sortie 14 the proof); Sortie 14 (entry, task 5, exit criteria — the "no push" branch is deleted); § Manual acceptance (convert/close the draft).

### OQ-3 — RESOLVED 2026-10-18 (user): fixtures
**Decision**: (a) The frozen 19+1 style vocabulary is its **own second fixture file** `Tests/VinetasVocabularyTests/Fixtures/style-vocabulary.json`; `storyboard-styles.json` (19 entries, the `vinetas-skills` contract) is copied unchanged and never extended. (b) **Every other sample — shots, prompts, drafts, host-recipe inputs, serializer round-trips — is copied from the real granville project, never invented**: `~/Projects/podcasts/granville/episodes/episode_1_01_cold_open.fountain` and `~/Projects/podcasts/granville/storyboards/*.json` (13 panels). SwiftFijos is the optional helper; a `Fixtures/` directory read via `Bundle.module` with a `#filePath` fallback (as `StoryboardStyleCatalogTests` does in the Vinetas app) is acceptable.
**Propagated to**: Standing rules (the real-fixtures rule names both sources and their shapes); Sortie 2 (tasks 2–3, exit criteria — fixture file name and shape); Sortie 4 (copies the fountain + `ep1_sc1_01_establishing.json` into the vocabulary tests; granville cross-check test); Sortie 5 (copies all 14 files into the UI tests; `GranvilleFixtures` loader + tests); Sorties 7, 8, 9, 10, 11 (tests and preview samples draw on the establishing panel, the 13 panels, the defaults shot, the scene heading); Sortie 13 (recipes' sample draft and the GLOSA worked table name the files); § Repositories read.

### OQ-4 — RESOLVED 2026-10-18 (user): iPhone no-op primitive
**Decision**: `assertionFailure` **from `body` only** — debug builds trap when the view is evaluated on iPhone, release builds are a no-op; tests construct the view without evaluating `body`. The "precondition failure" wording is removed from the plan.
**Propagated to**: Sortie 11 (entry criterion, task 1, exit criteria: `precondition(` absent, `assertionFailure(` count 1, construction-only test); Sortie 13 (entry criterion and task 2: `HostRecipeTests` constructs without evaluating `body`).

### OQ-5 — RESOLVED 2026-10-18 (user): light-appearance palette
**Decision**: Token-by-token: `bgInput → quaternarySystemFill`, `bgInputHover → tertiarySystemFill`, `border → separator`, `fg → label`, `fg3 → secondaryLabel`, `fg4 → tertiaryLabel`, `accent → accentColor`, `accentSoft → accentColor.opacity(0.18)`. Dark appearance keeps the existing hex values. Tests assert the mapping.
**Propagated to**: Sortie 7 (entry-criteria table with the `VinetasStylePalette` token ↔ V7 name ↔ light ↔ dark columns; task 1's pure `lightSource` / `darkValue` tables; task 5's eight-line test; exit criteria greps replacing the former [judgment] criterion); § Manual acceptance (Acceptance 4 light render references the table).

### OQ-6 — RESOLVED 2026-10-18 (user): isolation probe
**Decision**: A **committed probe package** at `Tools/UIIsolationProbe/` (a tiny executable package that imports only `VinetasUI`), built by `make verify-ui-isolation` through `xcodebuild` (never `swift build`), then checked with `otool -L`, `nm -gU` and a grep of the build log for MLX/Flux2/PixArt/Tuberia/Acervo symbols; plus an `EXPECT_FAIL=1` self-test that links an engine on purpose and must make the target fail.
**Propagated to**: Sortie 12 (entry criterion, tasks 2–3 — two executable targets so the self-test needs no manifest trickery, pattern `MLX|Flux2|PixArt|Tuberia|Acervo`, exit criteria incl. `EXPECT_FAIL=1`); Sortie 13 (section 1 of the guide documents the committed target; exit criterion greps `verify-ui-isolation`/`EXPECT_FAIL`); Sortie 14 (CI runs it after `make test-unit`).

---

## Open Questions & Missing Documentation

<!-- Written by refine Pass 5. -->

### Unresolved Items (must address before execution)

_None._

### Resolved during refine (for traceability)

| Sortie | Issue type | Was | Now |
|--------|-----------|-----|-----|
| 5 | Vague criterion | `swift format lint … Makefile` listed a file swift-format cannot lint | Makefile dropped from the lint path list; `grep -c 'only-testing:' Makefile` added |
| 6, 8 | Open question | Compact-width fallback "detect with an environment flag the host recipe sets, or `NavigationLink` availability — document the mechanism" (two options, one not implementable: SwiftUI cannot query for an enclosing `NavigationStack`) | `EnvironmentValues.vinetasNavigationStackAvailable` (default `true`) + `.vinetasNavigationStackAvailable(false)`; pure `VinetasStylePicker.form(...)` tested for all four combinations; documented in guide § 7 |
| 7 | Vague `[judgment]` | "light branch names a system semantic colour, dark branch is the V7 value — decidable from the diff" | `lightSource`/`darkValue` tables asserted by `StylePaletteTests`; `grep -n '0x'` confined to `darkValue`; system-colour names confined to the provider switches |
| 8 | Vague `[judgment]` | "Platform conditionals appear only where the API genuinely differs" | `#if os` count ≤ 6 and a grep that the `#if os(iOS)` bodies contain only the T-06 set |
| 8, 9, 10, 11 | Missing specifics | Pure helpers named "e.g." (`applyPreset`, `groupedByEngine`, `defaultToggleBinding`/`bridge`, `presents(onIdiom:)`) | Definite signatures: `applyPreset(_:to:)`, `groupedByEngine(_:)`, `setDefault(_:on:in:model:)` / `setRandomize(_:in:)`, `VinetasPromptInspectorPolicy.presents(onIdiom:)`; exit criteria grep them |
| 9 | Open question | `seed: Binding<UInt64>` "(or the app's seed type — match the app)" | `UInt64` — the app's `@Binding var seed: UInt64` (`GenerationSettingsPanel.swift:23`) and the draft's § 2.3 type |
| 11 | Vague `[judgment]` | "nothing in the modifier draws a Save, Cancel, Generate or Remove control" | Preview moved to `VinetasPromptInspectorPreview.swift`; `grep 'Button(\|Toggle(\|Menu('` on the modifier file prints nothing; order of header/composer/actions stays a specific judgment |
| 12 | Open question | `build-ios`: "scheme `SwiftVinetas-Package` (or add a second `xcodebuild build -scheme VinetasUI`)" | Second invocation `-scheme VinetasUI` (the package scheme would also build the macOS-only CLI executable for the simulator) |
| 13 | Vague criterion | "Sortie 11 may run in parallel; whichever lands second reconciles the text" | Makefile sortie (12) precedes the guide (13); the guide documents the committed target and greps for it |
| 1–14 | Vague criterion | Version guard greps carried a literal version string | Pattern-based guard (`[0-9]+\.[0-9]+\.[0-9]+(-dev)?`) in the standing rules, referenced as "the version guard" |

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 3 |
| Total sorties | 14 |
| Open questions | 0 blocking (6 resolved 2026-10-18) + 1 carried non-blocking (requirements OQ-1) |
| Dependencies mapped | 12 (+ 6 read-only repositories/projects) |
| Dependency structure | layers — L1: WU-1 (S1 → S2 → S3 → S4) · L2: WU-2 (S5 → S6 → S7 → S8 → S9 → S10 → S11) · L3: WU-3 (S12 → S13 → S14); sequential, max 1 concurrent agent |
| Context budget | 50 turns per sortie; estimates 21–38 turns (largest: Sortie 7 at 38, Sortie 13 at 38; smallest: Sortie 14 at 21 plus CI wait) |

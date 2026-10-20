---
type: execution-plan
state: complete
feature_name: OPERATION CONTINUITY CLERK
starting_point_commit: 238abc88f721e9bb945c5a00400da43970b0cee8
mission_branch: mission/continuity-clerk/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVinetas: storyboard shots on GLOSA notation 2.0, render records, cloud vocabulary

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Sources

- Requirements: `docs/missions/storyboard-shots/REQUIREMENTS.md` (sections § 1–§ 5, Tests, Release)
- Recon: `docs/missions/storyboard-shots/RECON_REPORT.md` — pass 4, **CLEAR**, 35/35 confirmed. Cited facts (A-01…A-35) are ground truth; sorties do not re-prove them.

## Mission-wide rules (every sortie)

- **Never** run `swift build` / `swift test`. Use only Makefile targets: `make build`, `make build-ios`, `make test-unit`, `make lint`, `make lint-check`, `make verify-ui-isolation`. `make lint-check` diffs against the git index — run `make lint`, commit, then `make lint-check`.
- **PUBLIC repository.** Fixtures are synthetic and inline (string literals written to a temporary directory). Never add or reuse private screenplay, podcast, app or character names. Do not touch or reuse existing private fixtures.
- Record `GlosaVersion.notation`, **never** `GlosaVersion.version` (local glosa-av `development` reports `0.9.0-dev`; CI resolves `0.9.0`).
- `VinetasVocabulary` and `VinetasUI` must not link GlosaCore, MLX, networking, or the `SwiftVinetas` core target. `make verify-ui-isolation` must stay green.
- Glosa-av source of truth: `git -C ~/Projects/package-collection/pkg/glosa-av show v0.9.0:<path>` (local `development` is identical except `GlosaVersion.version`). Never edit the glosa-av checkout.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never push to `main`, never force-push, never tag.

## Planning decisions (made at breakdown, with evidence — not open questions)

| ID | Decision | Evidence |
|----|----------|----------|
| D-1 | `ModelSummary.all` **stays** the two on-device models. Add `ModelSummary.cloud` (the 9 cloud summaries, `CloudModelDescriptor.all` order) and `ModelSummary.allIncludingCloud` (`all + cloud`). `named(cli:)` and `VinetasPromptDraft`'s model lookup search `allIncludingCloud`. | `VinetasVocabularyTests/ModelSummaryTests.swift:13` pins `all` to the two ids; `VinetasPromptComposer.swift:118`, `VinetasPromptInspector.swift:69,99` and `VinetasGenerationSettingsPanel.swift` default `models:` to `ModelSummary.all` — changing `all` would put cloud models in every existing host's picker, against § 5's "existing hosts are unchanged". |
| D-2 | Create a root `CHANGELOG.md` (Keep a Changelog format, `## [Unreleased]` section). | The repo has no CHANGELOG (root listing); § 1 requires the fold changes be noted in "the CHANGELOG". |
| D-3 | `ModelSummary` gains `isCloud: Bool` (decode default `false`) and `maxReferenceImages: Int` (decode default `0`). On-device values: the limit the model's engine reports (`Flux2Engine.maxReferenceImages(for:)` for Klein 4B, `0` for PixArt — `PixArtEngine.swift:178`). | Engine-owned limits: `Flux2Engine.swift:174-177`, `PixArtEngine.swift:178-180`; cloud: `CloudModelDescriptor.swift:42`. Decode defaults follow the existing back-compat rule in `ModelSummary.swift:16-19`. |
| D-4 | The render record is `ImageOutput.PanelMetadata.glosa: GlosaRecord?` with `notation: String`, `digest: String`, `shot` = the effective shot's `schemaJSONData()` carried as raw JSON. Encoding uses a small internal JSON value type that encodes objects as keyed containers and preserves integers exactly (no `Double` round-trip for `seed`). Not synthesized `Codable` on `Shot`, not `GlosaJSONValue`'s `Codable`. | Recon "Notable surprises" (`GlosaJSON.swift:9-14,49-58` wraps objects as `{"object":[…]}`); `Shot+Schema.swift:262,311` at v0.9.0. |
| D-5 | Project-root writability is checked through an injectable probe (protocol or closure) whose default tries to create the target directory and a temporary file; tests inject a denying stub. On denial the panel fails with a message naming the path and the remedy; there is no CWD fallback. | A-29, A-30: the denial only reproduces inside the sandboxed app CLI, so it cannot be tested directly. |
| D-7 | `generate --shot-json <file>` resolves `ref`/`character` with the storyboard rules, using the shot file's folder as the document folder (project root discovered from there). With `-` (stdin) there is no document folder: only absolute paths (rule 1) and Vinetas character slugs (rule 4) resolve. | REQUIREMENTS § 2 defines the rules for a document; § 4 makes `--shot-json` "supply the generation parameters" — the shot's `ref`/`character` are generation parameters. |
| D-6 | Whitespace-only `prompt` (non-empty, all whitespace) → that panel fails with an error naming the panel and "whitespace-only prompt"; it obeys `--continue-on-error`. It is **not** treated as a defaults shot (GlosaCore folds only empty prompts). | REQUIREMENTS § 1; A-35. |

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftVinetas | `~/Projects/package-collection/pkg/SwiftVinetas` | 10 | 1 | none |

---

### Sortie 1: Dependency foundation — glosa-av 0.9.0 floor, GlosaCore in core, CHANGELOG skeleton

**Priority**: 22.5 — blocks all 9 later sorties; foundation for core GlosaCore use; dependency-graph risk 3.

**Entry criteria**:
- [ ] First sortie — no prerequisites. On the mission branch; `git status --porcelain` shows no source changes.
- [ ] A-01 (floor `0.8.1` at `Package.swift:130-133`), A-11 (glosa-av `v0.9.0` = `ac24606`) are ground truth.

**Tasks**:
1. `Package.swift`: change the glosa-av `sibling(...)` floor from `0.8.1` to `0.9.0`; update its comment to say it is floored at 0.9.0 for GLOSA notation 2.0 (JSON shots, `Shot.effective`, `Shot.renderDigest`, `Shot.schemaJSONData`).
2. `Package.swift`: add `.product(name: "GlosaCore", package: "glosa-av")` to the `SwiftVinetas` target's dependencies. Do not add it to `VinetasVocabulary` or `VinetasUI`.
3. Create root `CHANGELOG.md` (D-2) with a header and an empty `## [Unreleased]` section containing `### Changed` with one line: "glosa-av floor raised to 0.9.0; the core `SwiftVinetas` target now links `GlosaCore`."

**Exit criteria**:
- [ ] `grep -n 'from: "0.9.0"' Package.swift` matches inside the glosa-av `sibling(` call.
- [ ] `grep -n 'GlosaCore' Package.swift` shows it in both the `SwiftVinetas` and `VinetasCLICore` target dependency lists and nowhere in `VinetasVocabulary`/`VinetasUI`.
- [ ] `make build` exits 0.
- [ ] `make build-ios` exits 0.
- [ ] `make verify-ui-isolation` exits 0.
- [ ] `make test-unit` exits 0 (no regressions).
- [ ] `test -f CHANGELOG.md && grep -q '## \[Unreleased\]' CHANGELOG.md`.
- [ ] `make lint` then commit; `make lint-check` exits 0. One commit on the mission branch.

---

### Sortie 2: The render record type — `PanelMetadata.glosa`

**Priority**: 20 — blocks S3, S6, S7, S10 (depth 4); foundation type reused by 3 sorties; new encoding risk 3.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED (core links GlosaCore; `make build` green).
- [ ] A-16 (`PanelMetadata` at `Core/ImageOutput.swift:60`, optional fields, old sidecars decode) and A-31 (`schemaJSONData()`, `Shot(schemaJSONData:)` at v0.9.0) are ground truth.

**Tasks**:
1. In `Sources/SwiftVinetas/Core/ImageOutput.swift` add `public struct GlosaRecord: Codable, Sendable, Equatable` nested in `PanelMetadata` with `notation: String`, `digest: String`, and the shot as raw schema JSON (D-4). Provide `public init(shot: Shot)` that sets `notation = GlosaVersion.notation`, `digest = shot.renderDigest`, shot = `shot.schemaJSONData()`; and `public func decodedShot() throws -> Shot` via `Shot(schemaJSONData:)`.
2. Implement the internal raw-JSON value type (new file under `Sources/SwiftVinetas/Core/`) that decodes from the shot bytes and encodes objects as keyed containers, arrays as unkeyed, and preserves integer values exactly (including `UInt64` above 2^53) and booleans vs numbers.
3. Add `public let glosa: GlosaRecord?` to `PanelMetadata`, optional, omitted from JSON when `nil`; extend every `PanelMetadata` initializer with a defaulted `glosa: GlosaRecord? = nil` parameter so existing call sites compile unchanged.
4. Tests in `Tests/SwiftVinetasTests/PanelMetadataTests.swift` (or a new `GlosaRecordTests.swift`), synthetic shots only:
   - `testGlosaRecordDigestMatchesShot`: `GlosaRecord(shot:).digest == shot.renderDigest` and `notation == GlosaVersion.notation`.
   - `testGlosaShotIsBareSchemaObject`: encode a `PanelMetadata` with `glosa`; parse the JSON with `JSONSerialization`; `glosa.shot` is a dictionary with key `prompt` at the top level, has no `object` key and no `documentIndex` key; an unknown/extra attribute appears at the top level.
   - `testGlosaShotRoundTripsThroughShotCodec`: re-serialize the decoded sidecar's `glosa.shot` and pass to `Shot(schemaJSONData:)`; its `renderDigest` equals the original digest.
   - `testGlosaRecordPreservesLargeSeed`: a shot with `seed` = `UInt64(1) << 63 + 1` survives encode → decode → `decodedShot()` exactly.
   - `testOldSidecarWithoutGlosaDecodes`: a JSON sidecar literal with no `glosa` key decodes with `glosa == nil`.

**Exit criteria**:
- [ ] `grep -n 'public let glosa: GlosaRecord?' Sources/SwiftVinetas/Core/ImageOutput.swift` matches.
- [ ] `grep -rn 'GlosaVersion.version' Sources Tests` returns nothing.
- [ ] The five named tests exist (`grep` each name in `Tests/SwiftVinetasTests/`) and pass under `make test-unit` (exit 0).
- [ ] `make build-ios` exits 0.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 3: `PanelRequest.shot` — `VinetasClient.generate` writes the record

**Priority**: 15.5 — blocks S6, S7, S10; establishes the host-app recording path; stubbed external API risk 3.

**Entry criteria**:
- [ ] Sortie 2 COMPLETED (`PanelMetadata.GlosaRecord` exists).
- [ ] A-13 (`PanelRequest` fields, `PanelRequest.swift:10-44`), A-24 (`VinetasClient.generate` at `Vinetas.swift:269-273`, metadata built at `:410`) are ground truth.

**Tasks**:
1. `Sources/SwiftVinetas/PanelRequest.swift`: add `public var shot: Shot?` (doc: "the effective GLOSA shot this panel renders; when set, the panel's metadata records it in `glosa`") and a defaulted `shot: Shot? = nil` init parameter (last), keeping existing call sites source-compatible.
2. `Vinetas.swift`: where `PanelMetadata` is built for `generate(_:characters:stepProgress:)` (`:410` region, and any cloud path that builds metadata separately), set `glosa: request.shot.map(PanelMetadata.GlosaRecord.init(shot:))`. When `shot` is nil, `glosa` is nil.
3. Tests (new `Tests/SwiftVinetasTests/PanelRequestShotTests.swift`):
   - `testLocalEngineRecordsGlosa`: a `VinetasClient` wired to the existing `MockEngine` generates a `PanelRequest` with a synthetic `shot`; `metadata.glosa?.digest == shot.renderDigest`.
   - `testCloudEngineRecordsGlosa`: a cloud model through the existing stubbed-HTTP test seam used by `CloudEngineTests.swift`/`VinetasClientRoutingTests.swift` (no network); `metadata.glosa?.digest == shot.renderDigest`.
   - `testNoShotNoGlosa`: a request without `shot` yields `metadata.glosa == nil`.

**Exit criteria**:
- [ ] `grep -n 'public var shot: Shot?' Sources/SwiftVinetas/PanelRequest.swift` matches.
- [ ] The three named tests exist and pass under `make test-unit` (exit 0); no test performs a real network request.
- [ ] `make build-ios` exits 0.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 4: Storyboard fold on GlosaCore — delete `ShotResolver`

**Priority**: 16 — blocks S5, S6, S7, S10; fold is foundation for every storyboard sortie; behaviour-change risk 2.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED.
- [ ] A-03, A-04 (only `StoryboardCommand.swift:65` and tests use `ShotResolver`), A-05, A-06, A-07, A-33, A-35 are ground truth.

**Tasks**:
1. `Sources/VinetasCLICore/Storyboard/ScreenplayShots.swift`: return the parsed `GlosaScore` (or add a `loadScore(from:)`) so the command can use `GlosaScore.effectiveShots`; keep parsing through `GlosaParser` only (no hand-parsing of notes).
2. `StoryboardCommand.swift`: replace `ShotResolver.resolve(rawShots)` with `score.effectiveShots`; update the type doc comment (`:9-12`). Implement D-6: a panel whose prompt is non-empty but whitespace-only is a per-panel failure (error text contains `whitespace-only prompt`), honoured by `--continue-on-error`, and in `--dry-run` it is reported to stderr rather than printed as a prompt.
3. Delete `Sources/VinetasCLICore/Storyboard/ShotResolver.swift` and `Tests/SwiftVinetasTests/ShotResolverTests.swift`; fix `ScreenplayShotsTests.swift:67,90` and the comment at `StoryboardPlanTests.swift:10`.
4. Tests (new `Tests/SwiftVinetasTests/StoryboardFoldTests.swift`), synthetic inline Fountain written to a temp dir:
   - `testNotation2AndNotation1TwinsProduceIdenticalPlans`: a notation 2.0 JSON-shot fixture and its 1.0 `<shot/>` twin (same defaults shot + 3 panels) produce identical `PanelPlan` lists (prompt, model, style, output).
   - `testOutputIsNotInheritedFromDefaults`: defaults shot with `output` → panels have `output == nil`.
   - `testRefAndCharacterFoldFromDefaults`: defaults `ref`/`character` reach the effective shot.
   - `testWhitespaceOnlyPromptIsAPanelError`.

**Exit criteria**:
- [ ] `test ! -e Sources/VinetasCLICore/Storyboard/ShotResolver.swift && test ! -e Tests/SwiftVinetasTests/ShotResolverTests.swift`.
- [ ] `grep -rn 'ShotResolver' Sources Tests` returns nothing.
- [ ] `grep -n 'effectiveShots' Sources/VinetasCLICore/Storyboard/StoryboardCommand.swift` matches.
- [ ] The four named tests exist and pass under `make test-unit` (exit 0).
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 5: Storyboard `ref` and `character` — name resolution and reference limits

**Priority**: 11 — blocks S6, S10; file I/O + resolution rules risk 2.

**Entry criteria**:
- [ ] Sortie 4 COMPLETED (effective shots carry `ref`/`character`).
- [ ] A-10, A-14 (`ReferenceValidator.swift:25-29`, runs before dispatch at `Vinetas.swift:500,623`), A-22 (`CharacterManager.loadCharacter(slug:)` `:151`, `referenceImageURLs(for:)` `:66`), A-23 are ground truth.

**Tasks**:
1. New `Sources/VinetasCLICore/Storyboard/StoryboardReferenceResolver.swift`: project root = nearest ancestor directory of the screenplay that contains `PROJECT.md`, else the screenplay's folder. Resolve each `ref` entry, first match wins: (1) absolute path that exists; (2) path relative to the project root, else the screenplay's folder; (3) `characters/<NAME>/` under the project root — first of `portrait.*`, `ref-portrait.*`, then any image in that folder alphabetically; (4) a Vinetas character with that slug (its reference images via `CharacterManager`). Inject `CharacterManager` (or a lookup closure) for tests.
2. Unresolved entry → a per-panel error whose message names the entry and lists every place searched (concrete paths); obeys `--continue-on-error`.
3. `StoryboardCommand`: pass resolved references (in `ref` order) as `PanelRequest.references` and the shot's `character` as `PanelRequest.character` (loaded via `CharacterManager`; unknown slug → per-panel error naming the slug).
4. Reference count over the model limit fails the panel before any vendor call with the existing `referencesUnsupported` (limit 0) / `tooManyReferences` errors — rely on the client's `ReferenceValidator`; add no second validator. Add a test proving the error type for a 0-limit cloud model (e.g. `bfl-flux-2-pro`) and an over-limit case, using a client with a stubbed/no-network engine.
5. Tests (new `Tests/SwiftVinetasTests/StoryboardReferenceResolverTests.swift`): one test per rule 1–4, a precedence test (rule 2 beats rule 3), `testUnresolvedRefMessageNamesEntryAndSearchedPlaces`, and `testProjectRootIsNearestProjectMD`. Synthetic temp-dir trees with tiny generated PNGs; character names like `ALICE`/`test-hero`.

**Exit criteria**:
- [ ] `test -f Sources/VinetasCLICore/Storyboard/StoryboardReferenceResolver.swift`.
- [ ] Named tests exist and pass under `make test-unit` (exit 0), including the `referencesUnsupported` and `tooManyReferences` cases; none touches the network.
- [ ] [judgment] The unresolved-reference error text names the `ref` entry verbatim and every searched location as a concrete path or slug, in rule order.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 6: Storyboard output resolution and per-panel render record

**Priority**: 7.5 — blocks S10; sandbox/file I/O risk 2. (Two closely coupled concerns — where a panel is written and what its sidecar records — kept together: the record half is one line plus one test.)

**Entry criteria**:
- [ ] Sortie 3 COMPLETED (`PanelRequest.shot`) and Sortie 5 COMPLETED (project-root discovery exists in `StoryboardReferenceResolver`).
- [ ] A-15, A-29, A-30 are ground truth.

**Tasks**:
1. `StoryboardCommand.outputURL`: a relative `output` resolves against the project root (Sortie 5's discovery), else the screenplay's folder — never the CWD and no longer under `--output-dir`. Absolute paths unchanged. Shots with no `output` keep `--output-dir` + `panel-NNN.png`.
2. Writability (D-5): before writing a panel to a project-root/screenplay-folder location, run the injectable probe; on denial fail that panel with a message containing the full path and a remedy (grant the folder to the Vinetas app / use an absolute `output` in a writable location / omit `output` to use `--output-dir`). No CWD fallback anywhere.
3. Pass `shot: <effective shot>` on every storyboard `PanelRequest` so every sidecar carries `glosa`.
4. Update `StoryboardPlanTests` output tests to the new rule. New tests: `testRelativeOutputResolvesAgainstProjectRoot`, `testRelativeOutputResolvesAgainstScreenplayFolderWithoutProject`, `testAbsoluteOutputUnchanged`, `testNoOutputUsesOutputDir`, `testUnwritableProjectRootFailsWithPathAndRemedy` (denying stub probe; asserts no file is written under the CWD), `testStoryboardSidecarRecordsGlosa` (mock engine via `CLIEnvironment.$client`; sidecar `glosa.digest == effectiveShot.renderDigest`).

**Exit criteria**:
- [ ] Named tests exist and pass under `make test-unit` (exit 0).
- [ ] `grep -n 'shot:' Sources/VinetasCLICore/Storyboard/StoryboardCommand.swift` shows the effective shot passed to `PanelRequest`.
- [ ] `grep -n 'currentDirectoryPath' Sources/VinetasCLICore/Storyboard/*.swift` returns nothing.
- [ ] [judgment] In `StoryboardCommand.swift`, a shot's relative `output` is only ever joined to the project root or the screenplay's folder — never passed to `URL(fileURLWithPath:)` on its own and never joined to `--output-dir`.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 7: `vinetas generate --shot-json <file|->`

**Priority**: 7 — blocks S10; CLI parsing risk 2.

**Entry criteria**:
- [ ] Sortie 3 and Sortie 4 COMPLETED (`PanelRequest.shot`; storyboard's `resolvePlan` maps a `Shot` to model + `StyleConfig`).
- [ ] A-25 (`Generate` at `VinetasCLICore.swift:45`, sidecar written at `:363`) is ground truth.

**Tasks**:
1. Add `@Option(name: .long) var shotJson: String?` to `Generate` (help: a bare GLOSA 2.0 shot object, a file path or `-` for stdin). Decode with `Shot(schemaJSONData:)`; on `GlosaSchemaError` exit with its `message`.
2. Map the shot to generation parameters by extracting the storyboard `resolvePlan` shot→model/`StyleConfig` mapping into one internal function used by both commands (no duplicated mapping). Shot `ref`/`character` use the Sortie 5 resolver per D-7.
3. Conflict rule: when `--shot-json` is given, any explicit generation flag (`prompt` argument, `--style`, `--model`, `--seed`, `--steps`, `--guidance`, `--width`, `--height`, `--aspect`, `--negative`, `--lora`, `--lora-scale`, `--preview`, `--reference`, `--character`) is a validation error naming the conflicting flag(s). Output-location flags remain allowed.
4. Pass `shot:` on the `PanelRequest` so the sidecar records `glosa`.
5. Tests (new `Tests/SwiftVinetasTests/CLITests/GenerateShotJSONTests.swift`): `testShotJSONHappyPathRecordsGlosa` (mock engine; sidecar `glosa.digest == shot.renderDigest`), `testShotJSONConflictsWithExplicitFlags` (parse-level validation error naming the flag), `testShotJSONInvalidReportsSchemaError`, `testShotJSONFromStdinPath` — implement the input read as an internal helper `readShotJSON(_ argument: String, stdin: () throws -> Data) throws -> Data` and test `-` with an injected `stdin` closure.

**Exit criteria**:
- [ ] `grep -n 'shot-json\|shotJson' Sources/VinetasCLICore/VinetasCLICore.swift` matches.
- [ ] Named tests exist and pass under `make test-unit` (exit 0).
- [ ] `make build` exits 0 and `./bin/vinetas generate --help` lists `--shot-json`.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 8: Vocabulary — cloud `ModelSummary` entries, `isCloud`, `maxReferenceImages`, sync test

**Priority**: 9.5 — blocks S9, S10; vocabulary is public API consumed by hosts; risk 1.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED.
- [ ] A-17 (9 cloud ids, `maxReferenceImages`), A-18, A-21, A-27 (`ModelDescriptor.summary` at `:71`), A-28 (`ModelSummaryRoundTripTests` template) are ground truth.

**Tasks**:
1. `Sources/VinetasVocabulary/ModelSummary.swift`: add `isCloud: Bool` and `maxReferenceImages: Int` (init params defaulted `false`/`0`; `init(from:)` decodes missing keys to those defaults) per D-3. Set Klein 4B's `maxReferenceImages` to the value its engine reports.
2. Add 9 hand-maintained static cloud summaries with the exact ids, display names, engine ids, cli names, capability flags, engine names, subtitles and limits of `CloudModelDescriptor.all`; `ModelSummary.cloud` (that order) and `ModelSummary.allIncludingCloud` (D-1); `named(cli:)` searches `allIncludingCloud`.
3. `Sources/SwiftVinetas/Engine/ModelDescriptor.swift` `summary`: fill `isCloud` and `maxReferenceImages` (cloud: descriptor; on-device: engine-reported value per D-3).
4. Tests: in `Tests/SwiftVinetasTests/` add `testVocabularyCloudSummariesEqualCoreMapping` (`ModelSummary.cloud == CloudModelDescriptor.all.map(\.summary)`) and `testVocabularyOnDeviceSummariesEqualCoreMapping`; in `Tests/VinetasVocabularyTests/ModelSummaryTests.swift` add `testOldSummaryJSONDecodesWithCloudDefaults` and `testAllIsStillOnDeviceOnly`.

**Exit criteria**:
- [ ] `grep -c 'isCloud' Sources/VinetasVocabulary/ModelSummary.swift` ≥ 1 and the file contains each of the 9 cloud ids.
- [ ] Named tests exist and pass under `make test-unit` (exit 0).
- [ ] `make verify-ui-isolation` exits 0; `grep -rn '^import' Sources/VinetasVocabulary` shows only Foundation/SwiftUI-family system modules.
- [ ] `make build-ios` exits 0.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 9: VinetasUI — draft `references`/`character`, composer rows, `statusSection`

**Priority**: 6.5 — blocks S10; SwiftUI risk 2.

**Entry criteria**:
- [ ] Sortie 8 COMPLETED (`ModelSummary.maxReferenceImages`, `allIncludingCloud`).
- [ ] A-19 (`VinetasPromptDraft` decode-if-present at `:127-151`), A-20 (`VinetasPromptComposer.swift:34`, init `:116`) are ground truth.

**Tasks**:
1. `VinetasPromptDraft`: add `references: [String]` (default `[]`) and `character: String?` (default `nil`), encoded and decoded with defaults when missing; model lookup (`:95`) uses `ModelSummary.allIncludingCloud` (D-1).
2. `VinetasPromptComposer`: add `showsReferenceControls: Bool = false` init parameter. When `true`, show a References row (ordered list; add / remove / reorder; add disabled at the selected model's `maxReferenceImages`; whole row disabled when the limit is 0) and a Character row (text field bound to `draft.character`). When `false`, neither row is in the view hierarchy.
3. Add a generic or `AnyView`-free `statusSection` view slot (host-supplied content, default empty) to the composer, following the existing init/slot conventions in `VinetasUI`.
4. Accessibility identifiers for the new controls following the scheme in `AccessibilityIdentifierTests.swift`; English strings in the existing string catalogue.
5. Tests (`Tests/VinetasUITests/`): `testDraftRoundTripWithReferencesAndCharacter`, `testDraftDecodesWithoutNewFields`, `testComposerHidesReferenceRowsByDefault`, `testReferenceAddDisabledAtModelLimit`, `testReferenceRowDisabledWhenLimitZero`, `testStatusSectionRendersHostContent` — using the existing view-inspection approach in `PromptComposerTests.swift`.

**Exit criteria**:
- [ ] Named tests exist and pass under `make test-unit` (exit 0).
- [ ] `make verify-ui-isolation` exits 0.
- [ ] `make build-ios` exits 0.
- [ ] `grep -n 'showsReferenceControls: Bool = false' Sources/VinetasUI/VinetasPromptComposer.swift` matches.
- [ ] `make lint` → commit → `make lint-check` exits 0.

---

### Sortie 10: Documentation — CHANGELOG, CLI reference, README

**Priority**: 1.5 — leaf; documentation only.

**Entry criteria**:
- [ ] Sorties 1–9 COMPLETED.
- [ ] A-26 (`docs/CLI_REFERENCE.md:293` documents `vinetas storyboard`) is ground truth.

**Tasks**:
1. `CHANGELOG.md` `## [Unreleased]`: under **Changed**, the three fold behaviour changes (output no longer inherited; `ref`/`character`/`caption` now honoured; whitespace-only prompt is now a per-panel error, not a defaults shot), relative `output` now resolves against the project root / screenplay folder, glosa-av 0.9.0 + core links GlosaCore; under **Added**, `PanelMetadata.glosa`, `PanelRequest.shot`, `vinetas generate --shot-json`, storyboard `ref`/`character`, cloud `ModelSummary` entries + `isCloud` / `maxReferenceImages` + `ModelSummary.cloud` / `allIncludingCloud`, `VinetasPromptDraft.references`/`character`, composer `showsReferenceControls` / `statusSection`; under **Removed**, `ShotResolver`. Note the glosa-av follow-up (whitespace-only prompts) as a known issue.
2. `docs/CLI_REFERENCE.md`: storyboard section — notation 2.0 JSON + 1.0 tags, fold semantics, the 4-rule reference resolution (first match wins) and the error, output resolution + sandbox note; `generate --shot-json` with conflict rule; the `glosa` sidecar block (`notation`, `digest`, `shot`) with a synthetic example.
3. `README.md`: brief mention of GLOSA 2.0 storyboards, render records and `--shot-json`.

**Exit criteria**:
- [ ] `grep -n 'shot-json' docs/CLI_REFERENCE.md README.md` matches in both.
- [ ] `grep -n 'PROJECT.md' docs/CLI_REFERENCE.md` matches (reference + output resolution).
- [ ] `grep -in 'whitespace-only' CHANGELOG.md` and `grep -in 'ShotResolver' CHANGELOG.md` match.
- [ ] [judgment] CLI_REFERENCE lists the four reference-resolution rules in the REQUIREMENTS § 2 order and states that relative `output` never resolves against the current directory.
- [ ] `git diff <mission starting_point_commit>..HEAD -- Sources Tests docs/CLI_REFERENCE.md README.md CHANGELOG.md | grep '^+' | grep -iE 'confessions|mr-mr-charles|meditations|casting-software|daily-dao|produciesta|escribir'` returns nothing.
- [ ] Commit; `make lint-check` exits 0.

---

## Parallelism Structure

**Critical Path**: Sortie 1 → Sortie 2 → Sortie 3 → Sortie 6 → Sortie 10 (via S4 → S5 → S6 as well; longest chain S1 → S4 → S5 → S6 → S10 and S1 → S2 → S3 → S6 → S10, length 5).

**Logical parallel groups** (no shared source files):
- **Group A** (after S1): S2 → S3 (core record) ∥ S4 → S5 (storyboard) ∥ S8 → S9 (vocabulary/UI).
- **Group B**: S6 (needs S3 + S5), S7 (needs S3 + S4).
- **Group C**: S10 (needs all).

**Execution decision: serial, one sortie agent at a time.** Every sortie's exit criteria run `make test-unit` / `make build-ios`, and the skill reserves builds for one agent at a time; all sorties share one checkout and one `.build/` directory, so concurrent agents would corrupt each other's build products and test logs. Worktree isolation would remove the collision but add merge work across `Package.swift`, `StoryboardCommand.swift` and `VinetasCLICore.swift` for little gain on a 10-sortie mission. Order: S1, S2, S3, S4, S5, S6, S7, S8, S9, S10.

**Agent Constraints**:
- **Supervising agent**: dispatches one implementer at a time; runs final `make test-unit`, `make build-ios`, `make lint-check` before the PR.
- **Sub-agents**: 1 active implementer (+ a verifier only for sorties with `[judgment]` criteria: S5, S6, S10).

## Open Questions & Missing Documentation

### Unresolved Items (must address before execution)

_None._ Pass 5 auto-fixed: S1 placeholder-file task removed; S7 stdin fork resolved (injected `stdin` closure) and `ref` handling decided (D-7); S6 judgment criterion partly converted to a `grep`; S10 private-name criterion converted to a `grep`.

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| intrusive-memory/glosa-av | sibling path; CI `0.9.0` (`ac24606`) | `~/Projects/package-collection/pkg/glosa-av` (`7459eb8`) | SIBLING_ACTIVE, LOCAL_AHEAD — source-identical to v0.9.0 except `GlosaVersion.version` |
| intrusive-memory/SwiftCompartido | sibling path; CI ≥ 7.3.1 | `~/Projects/package-collection/pkg/SwiftCompartido` | SIBLING_ACTIVE |
| intrusive-memory/flux-2-swift-mlx | sibling path; CI ≥ 3.4.3 | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | SIBLING_ACTIVE |
| intrusive-memory/SwiftAcervo | sibling path; CI ≥ 0.25.0 | `~/Projects/package-collection/pkg/SwiftAcervo` | SIBLING_ACTIVE |
| intrusive-memory/SwiftTuberia | sibling path; CI ≥ 0.9.0 | `~/Projects/package-collection/pkg/SwiftTuberia` | SIBLING_ACTIVE |
| intrusive-memory/pixart-swift-mlx | sibling path; CI ≥ 0.8.2 | `~/Projects/package-collection/pkg/pixart-swift-mlx` | SIBLING_ACTIVE |
| marcprux/universal | 5.3.0 | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | 1.8.2 | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | 0.7.1 | — | NO_LOCAL_CHECKOUT |
| apple/swift-certificates / swift-crypto / swift-asn1 | 1.19.4 / 3.15.1 / 1.7.1 | — | NO_LOCAL_CHECKOUT |

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). Each entry MUST be resolved before refinement can proceed past Pass 1. -->

_No blocking open questions identified during breakdown._

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 10 |
| Open questions | 0 |
| Dependencies mapped | 12 |
| Dependency structure | sequential |

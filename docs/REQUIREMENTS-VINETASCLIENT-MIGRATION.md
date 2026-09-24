---
type: doc
state: incomplete
updated: 2026-07-12
---

# REQUIREMENTS: Migrate off the deprecated `Vinetas` / `VinetasModel` surface

> Status: **Scoping.** Grounded in a codebase census (2026-07-12) of the
> SwiftVinetas repo and its downstream consumers (`apps/Vinetas`,
> `apps/Produciesta`). No implementation yet.

## 1. Goal & target end state

Two deprecated symbols remain in production use:

- `enum Vinetas` — `@available(*, deprecated, message: "Use VinetasClient.shared instead")`
  (`Vinetas.swift:939`). A stateless static façade over `VinetasClient.shared`.
- `enum VinetasModel` — `@available(*, deprecated, message: "Use ModelDescriptor types directly (e.g., VinetasClient.klein4B)")`
  (`Vinetas.swift:1564`). A `String`-raw enum (`klein4b`/`klein9b`/`pixart-sigma`)
  with a `.descriptor` bridge to `any ModelDescriptor`.

**Target:** no production code references `Vinetas.*` or `VinetasModel`; generation
/ download / memory / model-listing go through `VinetasClient.shared` with
`any ModelDescriptor`; understanding and character flows go through their own
non-deprecated types. Then delete the deprecated enums (and the already-dead
`VinetasPipeline`) and their tests.

> **Candid framing:** "move everything to `VinetasClient.shared`" is the
> *headline*, but it is not literally the whole target. `VinetasClient` does not
> expose image-understanding or character operations — those live on
> `ImageClassifier.shared`, `FeatureExtractor.shared`, `ReferenceSheetGenerator`,
> `CharacterTrainer`, and the character file-manifest manager. The real target is
> "off the deprecated surface," which fans out to several non-deprecated APIs.

## 2. Census — who actually uses the deprecated surface

**Good news: the blast radius is contained entirely within the SwiftVinetas repo.**

- `apps/Vinetas` (GUI host, iOS/macOS): **zero** deprecated usage in Swift
  source — it already imports `SwiftVinetas` and uses the modern surface. Only
  `docs/*.md` mention the old names historically.
- `apps/Produciesta`: does not import SwiftVinetas at all yet.
- No other package in the collection imports `SwiftVinetas` / `VinetasCLICore`.

**Real production call sites (the work):**

| Area | Files | Notes |
|---|---|---|
| CLI façade calls (`Vinetas.*`) | `VinetasCLICore.swift` (27), `Storyboard/StoryboardCommand.swift` (3) | The entire migration's production churn is here. |
| Library `VinetasModel` in **public API** | `Core/PanelOutput.swift` (5), `Core/VinetasMemory.swift` (3), `Character/Character.swift` (3), `Core/VinetasModelInfo.swift` (2) | Source-breaking to change — see §5. |
| Library `VinetasModel` internal | `Core/VinetasPipeline.swift` (7, already-deprecated type), `Engine/EngineRouter.swift` (1), `VinetasBackgroundDownloads.swift` (2, mostly the unrelated `VinetasModelDownloadEvent` name) | |
| Tests | 8 files call the façade; ~10 use `VinetasModel` incl. `VinetasModelTests.swift` (40 refs) + `VinetasClientRoutingTests.swift` (21) | |

Non-issue (false positive): `CharacterTrainer.swift:106` — `Vinetas.prepareTrainingData`
appears only inside an **error-message string**, not code.

## 3. Deprecated → non-deprecated delegation map

Every deprecated `Vinetas.*` method already shows its replacement (it forwards to
it). Migration = call the target directly.

| Deprecated `Vinetas.*` | Non-deprecated target |
|---|---|
| `generate`, `generateSequence`, `preview` | `VinetasClient.shared.generate/…/preview` |
| `download`, `listModels` | `VinetasClient.shared.download/listModels` |
| `validateMemory(for:) -> Bool` | `VinetasClient.shared.validateMemory(for:) -> MemoryValidation` **(return type changes)** |
| `classify` | `ImageClassifier.shared.classify` |
| `extractFeatures` | `FeatureExtractor.shared.extractFeatures` |
| `similarity` | `FeatureExtractor.shared.extractFeatures` + `cosineSimilarity(_:_:)` |
| `verifyCharacter` | `FeatureExtractor.shared` + `VerificationReport` (façade also does telemetry capture) |
| `createCharacter`, `listCharacters`, `loadCharacter` | character file-manifest manager |
| `generateReferenceSheets` | `ReferenceSheetGenerator.generate` (+ telemetry capture) |
| `trainCharacterLoRA` | `CharacterTrainer().train` **+ writes back `Character.lora` and re-saves** |
| `prepareTrainingData` | training-data preparer |
| `generateFromFile` | **no replacement exists — must be built (§4b)** |

> **Not pure pass-throughs.** `validateMemory`, `verifyCharacter`,
> `generateReferenceSheets`, and `trainCharacterLoRA` add telemetry capture and/or
> post-processing (e.g. `trainCharacterLoRA` updates the character manifest's LoRA
> metadata and persists it). That orchestration must be **relocated to the call
> site** (the CLI command) or pushed **down into the underlying type** — it does
> not come for free by swapping the call. Pushing it down is preferable so the GUI
> gets the same behavior.

## 4. Prerequisite API additions (blockers — do these first)

These gaps make it *impossible* to fully drop the deprecated surface without new
public API. They must land before the call-site migration.

### 4a. String ↔ `ModelDescriptor` resolver (the biggest one)

The CLI's whole model interface is string-based (`--model klein4b`, `list`,
`--help` valid-values, output-metadata `model` field). Today the only
string→descriptor bridge is `VinetasModel(rawValue:).descriptor` — deprecated.
`VinetasClient` exposes descriptors only as named statics (`.klein4B`, `.klein9B`,
`.pixartSigmaXL`, `.defaultModel`) with **no** lookup by id and **no** enumerable
list of user-selectable models.

**Add (non-deprecated), e.g. on `VinetasClient`:**
- `descriptor(forModelId: String) -> (any ModelDescriptor)?`
- `modelId(for: any ModelDescriptor) -> String` (for output metadata / plan printing)
- `selectableModels: [any ModelDescriptor]` (or `[VinetasModelInfo]`) to drive
  `--model` validation, `list`, and help text — replacing `VinetasModel.allCases`.

Without this, "just use `VinetasClient.klein4B`" cannot express a runtime string
argument. **This is the crux decision of the whole migration.**

### 4b. `generateFromFile` on `VinetasClient`

`batch` depends on `Vinetas.generateFromFile(_:model:progress:stepProgress:)`,
which has **no** `VinetasClient` equivalent. Either:
- (a) add `VinetasClient.generateFromFile(...)` taking `any ModelDescriptor`, or
- (b) refactor `batch` to parse the prompt file itself and loop `client.generate`.

Recommend (a) — keeps parity and one code path; `storyboard` deliberately does its
own per-shot loop and would not use it.

### 4c. Memory-validation overloads (or migrate callers to `MemoryValidation`)

`VinetasMemory.validate(for: VinetasModel)` / `requiredMemoryBytes(for: VinetasModel)`
are public statics keyed on the deprecated enum. Provide `any ModelDescriptor`
overloads (or move the logic behind `VinetasClient.validateMemory`) and migrate
`Info` / `ListModels`.

## 5. Public-API break assessment

Removing `VinetasModel` is **source-breaking** for these public declarations:

- `PanelOutput.model: VinetasModel?` (computed) and `PanelOutput.init(…, model: VinetasModel, …)`
- `VinetasMemory.validate(for: VinetasModel)` / `requiredMemoryBytes(for: VinetasModel)`
- `Character.init(…, model: VinetasModel?)` (already a deprecated back-compat init)

Because **no external consumer uses them** (only internal + tests), the practical
break is small — but it is still a public API change and should ride a
**minor version bump** with the changes noted in `CHANGELOG`. Options per symbol:
add a descriptor-based replacement and delete the `VinetasModel` one, or (for
`PanelOutput.model`) change the type to `String` model-id / `any ModelDescriptor`.

## 6. Migration work, by area

**A. Land prerequisite API (§4).** Resolver + `generateFromFile` + memory overloads,
with unit tests. Nothing else can proceed cleanly until this exists.

**B. Migrate the CLI (`VinetasCLICore`).** The bulk. Per command:
- `Generate`, `Batch`, `Storyboard`, `Preview`, `Download`, `Info`, `ListModels`:
  replace `VinetasModel(rawValue:)` with the §4a resolver; replace `Vinetas.*`
  with `VinetasClient.shared.*`; handle the `validateMemory` return-type change.
- `Classify`, `Features`, `Similarity`: call `ImageClassifier.shared` /
  `FeatureExtractor.shared` (+ `cosineSimilarity`) directly.
- `CharacterCommand` subtree (create/list/info/delete/reference/prepare/train/verify):
  call the character types directly; **relocate the façade's telemetry +
  manifest-writeback orchestration** (§3 note).
- `StoryboardCommand`: swap `VinetasModel`/`Vinetas.*` for the resolver +
  `VinetasClient.shared` (this is what triggered the current warnings).

**C. Migrate library internals.** `PanelOutput`, `VinetasMemory`, `Character`,
`EngineRouter`; retire or internalize `VinetasPipeline` (see §7).

**D. Migrate tests.** Update the 8 façade + ~10 `VinetasModel` test files. Decide
the fate of `VinetasModelTests.swift` (40 refs) and `VinetasClientRoutingTests.swift`
(21 refs) — convert to descriptor/resolver tests or delete with the enum.

## 7. Removal step

Once all call sites are migrated:
- Delete `enum Vinetas` and `enum VinetasModel`.
- Delete `VinetasPipeline` — already documented as the "now-deprecated" hardcoded
  Flux2 path that `generateFromFile` no longer uses (`Vinetas.swift:1019`);
  confirm no remaining refs, then remove.
- Delete their dedicated tests.

Convention alternative: keep the enums deprecated for one release cycle before
deletion. Given **zero external consumers**, deleting in the same cycle is
defensible and less confusing — recommend deleting outright, in the same PR as the
last call-site migration, behind a minor bump.

## 8. Risks / candid flags

- **Resolver design is load-bearing.** If §4a is done poorly (e.g. a stringly-typed
  switch that re-hardcodes the three ids), we've just moved `VinetasModel` without
  the deprecation. Prefer deriving `selectableModels` from the engine registry so
  new models appear without editing a second list.
- **`validateMemory` semantics.** `Bool` → `MemoryValidation` is not just a type
  swap; the façade collapsed several verdicts to `true`. Preserve the CLI's
  user-facing behavior deliberately, don't just `!= .insufficient`.
- **Character telemetry/writeback** must not be dropped in the shuffle — the GUI
  relies on the manifest LoRA writeback that lives in `trainCharacterLoRA` today.
  Push it down into `CharacterTrainer`, not into each caller.
- **Scope discipline.** This is a refactor with no user-visible feature. It should
  be behavior-preserving; guard it with the existing routing tests
  (`VinetasClientRoutingTests`) and a full `make test-unit` before/after.

## 9. Decisions to lock

1. **Resolver home & shape** — `VinetasClient.descriptor(forModelId:)` + `modelId(for:)`
   + `selectableModels`, registry-derived? *(Recommended.)*
2. **`generateFromFile`** — add to `VinetasClient` (recommended) vs. inline into `batch`.
3. **`PanelOutput.model` replacement type** — `String` id vs. `any ModelDescriptor`.
4. **Delete-now vs. deprecate-one-cycle** — recommend delete-now (no external users).
5. **`VinetasModelTests` fate** — convert vs. delete.

## 10. Rough sequencing / effort

1. **Prereq API (§4)** — resolver, `generateFromFile`, memory overloads + tests. *(1 focused PR.)*
2. **CLI migration (§6B)** — the bulk; behavior-preserving, test-guarded. *(1 PR, or split understanding/character/generation.)*
3. **Library internals + public-API swap (§6C, §5)** — minor bump, CHANGELOG. *(1 PR.)*
4. **Delete deprecated enums + `VinetasPipeline` + tests (§7).** *(folds into #3 or a final PR.)*

Each stage should leave `make test-unit` green.

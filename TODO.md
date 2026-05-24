# SwiftVinetas × SwiftAcervo 0.16 upgrade — code TODO

**Triggered by**: SwiftAcervo 0.14.0 → 0.16.0 (sibling already at `v0.16.0-2-g3a0f2f6`).
**Driver**: `/Users/stovak/Projects/SwiftAcervo/UPGRADING.md` (full file).
**Last updated**: 2026-05-23

Items are grouped by area. Each has the exact file:line site and a one-line fix.

---

## A. Build-breaking deprecated/removed API migrations (do FIRST — package will not compile otherwise)

- [ ] **Bump SwiftAcervo dependency pin** — `Package.swift:77` currently pins `from: "0.14.0"`. Change to `from: "0.16.0"` so CI and external consumers resolve a release that ships the required `primaryRepo`/`components` wire fields. (Sibling-checkout dev path is unaffected; this only matters for non-sibling resolution.)

- [ ] **Remove `Acervo.migrateFromLegacyPaths()` call** — `Sources/SwiftVinetas/Core/VinetasModelManager.swift:159`. This symbol was deleted in SwiftAcervo 0.14.1 (UPGRADING § "Upgrading to 0.14.1"). The legacy LLM/TTS/Audio/VLM cache paths have been dead since 0.12; SwiftVinetas only ever shipped against 0.13+, so no user data is at risk. Delete lines 158–170 (the entire `do { let migrated = try Acervo.migrateFromLegacyPaths() ... }` block) and replace the body of `configureStorage()` with the one-time guard plus a comment noting the migration is no longer needed. Keep the public signature so callers don't break.

- [ ] **Verify `Acervo.customBaseDirectory` is truly unused** — `Sources/SwiftVinetas/Core/VinetasModelManager.swift:175,182` reference it only in deprecation messages/comments. No call site remains. **No action**, but confirm during edit that the dead `@available(*, deprecated)` overload `configureStorage(baseURL: URL)` is still appropriate to keep as a no-op shim or whether it should be deleted now.

## B. ModelAvailability switch-exhaustiveness break (UPGRADING 0.16 Step 1)

SwiftAcervo added `case .partial(missing: [String])` to `ModelAvailability`. Every `switch` over it is now non-exhaustive. Verified call sites in SwiftVinetas:

- [ ] **No literal `switch state` over `ModelAvailability` exists in production source.** All three production sites use equality:
  - `Sources/SwiftVinetas/Vinetas.swift:651` — `await Acervo.availability(modelId) == .available`
  - `Sources/SwiftVinetas/Engine/Flux2Engine.swift:429-430` — `state != .available { return false }`
  - `Sources/SwiftVinetas/Engine/PixArtEngine.swift:487-488` — `state != .available { return false }`

  These compile against 0.16 unchanged because `ModelAvailability: Equatable`. **However**, they collapse `.partial` to "not available" silently, which loses repair-vs-download UI information. **Decision required**: leave as-is (binary collapse) or upgrade to a proper switch and propagate a `.partial` signal up to UI consumers. Recommend leave-as-is for now and file a follow-up — neither engine surfaces a UI hook for "repair" today.

- [ ] **Expose `.partial` to consumers via `VinetasClient.availability(_:)`** — `Sources/SwiftVinetas/Vinetas.swift:667` already forwards `Acervo.availability(modelId)` as-is. Confirm downstream consumers (Produciesta, etc.) handle the new fourth case in their switches. **Action**: add a one-line doc-comment update at line 656–662 noting the four-state surface (currently the doc says three states: `.available`, `.downloading(progress:)`, `.notAvailable`).

## C. Filesystem-discovery anti-patterns ("feeling around in directories")

Per UPGRADING § "stop poking the filesystem; ask the library", every `FileManager.contentsOfDirectory` / `enumerator(at:)` against a SwiftAcervo-managed directory is a bug. Verified sites:

- [ ] **`Flux2Engine.diskSize(of:)` directory enumeration** — `Sources/SwiftVinetas/Engine/Flux2Engine.swift:450-473`. Uses `Flux2ModelPaths.findModelPath(for:)` + `fm.enumerator(at: path, ...)` to sum file sizes for a component directory. **Fix**: replace with `try await Acervo.fetchManifest(for: Self.acervoRepoId(for: component)).files.reduce(0) { $0 + $1.sizeBytes }`. The signature is already `async` so the await is free. (Cross-check: if `Flux2ModelPaths.findModelPath` is itself a filesystem probe inside flux-2-swift-mlx, leave the path resolution part to the dep and only swap the size-sum half.)

- [ ] **`PixArtEngine.diskSize(of:)` directory enumeration** — `Sources/SwiftVinetas/Engine/PixArtEngine.swift:545-566`. Inside `withComponentAccess` closure, walks `handle.rootDirectoryURL` with `fm.enumerator(...)` to sum bytes. **Fix**: same pattern — call `try await Acervo.fetchManifest(forComponent: componentId).files.reduce(0) { $0 + $1.sizeBytes }` instead of enumerating. The `withComponentAccess` scope is no longer needed for the size query (it's only needed if you actually need to *read* file bytes); drop the scope and call the manifest API directly. Keep the `Acervo.isComponentReady(componentId)` guard at line 541.

- [ ] **`Flux2Engine` model-path probe** — `Sources/SwiftVinetas/Engine/Flux2Engine.swift:331` uses `FileManager.default.fileExists(atPath: path.path)` on the LoRA path. **NOT a violation** — the LoRA path is user-supplied (`loadLoRA(at path: URL, scale:)`), not a SwiftAcervo-managed directory. Leave as-is. Same logic at `Sources/SwiftVinetas/Engine/PixArtEngine.swift:366` and `Sources/SwiftVinetas/Core/LoRAManager.swift:30,66` — all user-supplied LoRA paths, all safe.

- [ ] **`Vinetas.verifyCharacter` references-directory scan** — `Sources/SwiftVinetas/Vinetas.swift:1095-1112` enumerates a user `references/` directory under a character profile. **NOT a violation** — character refs are not Acervo-managed. Leave as-is.

- [ ] **`CharacterManager` / `CharacterTrainer` directory scans** — `Sources/SwiftVinetas/Character/CharacterManager.swift:82,137-140` and `Sources/SwiftVinetas/Character/CharacterTrainer.swift:225-228,261-263`. All scan user-trained LoRA output directories under `Application Support/.../characters/`. **NOT violations** — these are SwiftVinetas-owned user artifacts, not Acervo manifests. Leave as-is.

## D. Already-correct manifest-driven sites (audit confirmed clean — no action)

These already use the right pattern; documenting so future auditors don't reopen them:

- `Sources/SwiftVinetas/Understanding/ImageClassifier.swift:179-181` — `withComponentAccess { handle in try handle.url(matching: ".safetensors") }`. Correct.
- `Sources/SwiftVinetas/Understanding/FeatureExtractor.swift:164-166` — same pattern. Correct.
- `Tests/SwiftVinetasTests/VisionActorManifestTests.swift:61,114` — uses `Acervo.fetchManifest(forComponent:)` and `manifest.files.contains { $0.path.hasSuffix(...) }`. Correct.

## E. Test-fixture audit (UPGRADING 0.14.0 Step 3)

- [ ] **No test in SwiftVinetas synthesizes a fake model directory by writing only `config.json`.** The only `config.json` reference in `Tests/` is a string-literal in a telemetry event-encoding test (`Tests/SwiftVinetasTests/CLITests/AcervoEventEncodingTests.swift:94`). **No action required.**

- [ ] **No hand-built `CDNManifest` fixtures.** No tests construct `CDNManifest` directly (grep confirms only `Acervo.fetchManifest(...)` retrieval). The new required-on-wire `primaryRepo`/`components` fields are therefore moot for in-process tests — they only matter for the real CDN, which is covered by MODELS-TO-SHIP.md. **No action required.**

## F. Documentation and comment hygiene

- [ ] **Comment refers to `Acervo.swift:1820` line range** — `Sources/SwiftVinetas/Engine/PixArtEngine.swift:512`. UPGRADING 0.16 Step 4 notes that `Acervo.swift` was decomposed into 15 files; the line-range citation is stale. **Fix**: change "per Acervo.swift:1820" to "per `Acervo+ComponentDownloads.swift` / `Acervo+DeleteModel.swift`" or just "per SwiftAcervo's `deleteComponent` contract".

- [ ] **`VinetasModelManager` doc-comment** — `Sources/SwiftVinetas/Core/VinetasModelManager.swift:48-50`. The phrase "file-presence check for `config.json`" describes the **pre-0.14.0** semantics. Post-0.14.0 `isModelAvailable` is **strict** (every manifest file present at recorded size). Update the comment to reflect strict semantics. (No code change — the semantic upgrade is already correctly applied by the library.)

- [ ] **`VinetasClient.availability(_:)` doc** — `Sources/SwiftVinetas/Vinetas.swift:656-666`. Says "three-state". Update to "four-state" and mention `.partial(missing:)`.

## G. Optional 0.16 adoption opportunities (deferred — not blockers)

Not required for the build to work, listed so they're not forgotten:

- [ ] Consider adopting `Acervo.gcEmptyModelDirectories()` in `VinetasModelManager.configureStorage()` as the modern replacement for what `migrateFromLegacyPaths` used to do (UPGRADING 0.16 TL;DR row 6). Returns the URLs it reclaimed. One-line addition.
- [ ] Consider migrating any UI surface that wants to differentiate "absent" from "in progress" from `isModelAvailable(_:)` to `availability(_:)`. Currently no Vinetas-internal UI does this; downstream Produciesta might.
- [ ] No SwiftVinetas model is currently addressed by a slug that doesn't parse as `org/repo` (verified: PixArt uses `"intrusive-memory/pixart-sigma-xl-dit-..."`, Flux uses HF repos, ViT/DINOv2 use `mlx-vision/...`). The new `availability(slug:url:)` / `ensureAvailable(slug:url:...)` slug-keyed API (UPGRADING 0.16 Step 2) is **not needed** here. Skip.

---

## H. Kill `VinetasModelManager` entirely (source-breaking; do in its own commit)

`VinetasModelManager` is a 257-line pure facade with zero unique behavior. Every method either pass-throughs to `Acervo.*` (storage/availability) or to `VinetasClient.shared.*` (engine-routed download/delete/list). Only **one** external call site exists across all sibling repos: `configureCDN(baseURL:)` in the two Vinetas apps. After TODO A.2 lands, `configureStorage()` is a no-op-with-a-lock that exists only to be called from `VinetasClient.init()`.

Note on framing: SwiftAcervo cannot absorb the whole thing. `download / delete / listAllModels` dispatch on `engineID` (Flux2 vs PixArt vs vision backbones); SwiftAcervo has no concept of an engine. Those calls must land on `VinetasClient`. Only the storage/availability pass-throughs collapse cleanly into bare `Acervo.*`.

- [ ] **Move `configureCDN(baseURL:)` to `VinetasClient`** as a new static method `VinetasClient.configureCDN(baseURL:)`. Body is the same one-liner: `ModelRegistry.cdnBaseURL = baseURL`. Update the two app call sites:
  - `/Users/stovak/Projects/Vinetas/Vinetas/VinetasApp.swift:30`
  - `/Users/stovak/Projects/Vinetas/VinetasIOS/VinetasIOSApp.swift:61`

- [ ] **Drop the `VinetasModelManager.configureStorage()` call** at `Sources/SwiftVinetas/Vinetas.swift:96`. Once `migrateFromLegacyPaths` is gone (TODO A.2), there is no work left to do. Also drop the call at `Tests/SwiftVinetasGPUTests/T5DiffuserComparisonDump.swift:52`.

- [ ] **Inline the remaining pass-throughs at each caller** (search-and-replace, no logic change):
  - `VinetasModelManager.isModelAvailable(id)` → `Acervo.isModelAvailable(id)`
  - `VinetasModelManager.sharedModelsDirectory` → `Acervo.sharedModelsDirectory`
  - `VinetasModelManager.download(model:progress:)` → `VinetasClient.shared.download(model:progress:)`
  - `VinetasModelManager.delete(_:)` → `VinetasClient.shared.delete(_:)`
  - `VinetasModelManager.listAllModels()` → `VinetasClient.shared.listModels()`

- [ ] **Delete the deprecated `VinetasModel` enum shims** — `download(model: VinetasModel)`, `isAvailable(model: VinetasModel)`, `delete(model: VinetasModel)`, `modelDirectory(for: VinetasModel)`, `transformerVariant(for:)`, `modelComponents(for:)`. All `@available(*, deprecated)`; no live callers found across sibling checkouts. The `VinetasModel` enum itself may also be dead — verify with a separate grep before deletion.

- [ ] **Delete `Sources/SwiftVinetas/Core/VinetasModelManager.swift`** in its entirety.

- [ ] **Delete `Tests/SwiftVinetasTests/VinetasModelManagerTests.swift`** in its entirety.

- [ ] **Bump SwiftVinetas to a new minor or major version** to signal the source-breaking API removal. Update `Package.swift` if it carries a version comment, and note in `CHANGELOG.md` / release notes.

**Decision required before starting**: should `VinetasClient` absorb a `configureCDN` static, or is the CDN base URL better moved to a `ModelRegistry.configure(cdnBaseURL:)` call on the Flux2Core side (closer to where it's actually consumed)? Default-recommend: put it on `VinetasClient` for caller symmetry — one type to import, mirrors the existing `VinetasClient.shared.*` surface.

---

## Ambiguities needing human judgment before edits begin

1. **`.partial` propagation.** The three `== .available` comparisons silently collapse `.partial` into "not ready." Spec-conformant but lossy — decide if engines should surface a repair-vs-download signal upward. Default-recommend: leave for follow-up.
2. **`configureStorage(baseURL:)` deprecated overload** — now does nothing. Keep as a no-op shim for source compat, or delete? UPGRADING is silent.
3. **`Package.swift` pin bump to `0.16.0`** — bump in this PR or a separate one? Sibling-checkout dev flow works at 0.14 today, so technically not blocking until a release is cut.

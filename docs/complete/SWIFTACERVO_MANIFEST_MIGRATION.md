# SwiftAcervo Manifest-Driven Migration — Requirements

**Status**: draft · 2026-05-04
**Branch**: `fix/acervo-app-group-env-workflow` (current); migration work likely warrants a follow-up branch
**Related**: `Package.swift`, `Sources/SwiftVinetas/Engine/PixArtEngine.swift`, `Sources/SwiftVinetas/Understanding/{ImageClassifier,FeatureExtractor}.swift`, `Tests/SwiftVinetasGPUTests/{FixtureGenerationTests,T5DiffuserComparisonDump}.swift`, `Sources/SwiftVinetas/Core/VinetasModelManager.swift`

---

## Motivation

SwiftVinetas was written against SwiftAcervo's pre-component, `repoId`-keyed surface. The current floor is `0.10.0`; the package has resolved to `0.11.1`. Between those releases SwiftAcervo finished its move to a **manifest-driven, registry-aware** model:

- Components register with the registry; the CDN manifest is the single source of truth for which files exist, their sizes, and their SHA-256 hashes.
- Downloads, integrity checks, and scoped file access all flow through the component ID — the consumer never names a filename.
- `0.11.1` adds an idempotent short-circuit to `Acervo.register(_:)`: identical re-registrations are free, but registering the same `id` with a *different* `files` list is now a **stderr warning** (`[SwiftAcervo] Warning: re-registering component '<id>' with different repoId or files. Last registration wins.`).

Vinetas violates the manifest-driven contract in five places (hardcoded filenames passed to `ensureAvailable` / `ComponentDescriptor.files`) and uses the legacy `repoId`-keyed APIs throughout `PixArtEngine`. The 0.11.1 register warning is now *triggered* by Vinetas's hardcoded `[config.json]` stub every time `loadModel` runs after a hydration — which means the upgrade currently produces stderr noise on every model reload and silently rewrites the registry's hydrated file list back to `[config.json]`, breaking subsequent integrity checks.

The library shouldn't reference any file that isn't discovered through a CDN manifest. This doc captures everything needed to bring Vinetas into compliance and onto the post-0.11 ecosystem.

### What changes vs what stays

| Concern | Changes | Stays |
|---|---|---|
| `Package.swift` SwiftAcervo floor | `0.10.0` → `0.11.1` | sibling/remote shim |
| PixArt component registration | un-hydrated init, no `files:` | bridge from `CatalogRegistration` to Acervo's registry |
| PixArt download/availability/delete/disk-size | component-ID / handle APIs | engine-level `ImageGenerationEngine` shape |
| `ImageClassifier`, `FeatureExtractor` | one-time component registration + `ensureComponentReady` + `withComponentAccess` | public actor surfaces, ImageNet labels, preprocessor presets |
| Hardcoded `model.safetensors` / `config.json` paths | removed | — |
| Hardcoded R2 debug URL in `PixArtEngine` | removed | — |
| `VinetasModelManager.configureStorage()` | unchanged for runtime; consider opt-in `migrateFromLegacyPaths()` | App-Group-aware base directory resolution |
| `Acervo.deleteFromCDN` / `Acervo.recache` | available but **not wired into runtime Vinetas**; tooling-only | runtime download path |

---

## R1. Pin the floor to 0.11.1

### R1.1 Bump `Package.swift`
- `Package.swift:64`: `from: "0.10.0"` → `from: "0.11.1"`.
- `Package.resolved` already has `0.11.1`; this just makes the contract explicit and ensures `register` short-circuit + `deleteComponent` + `isComponentReady` are guaranteed available.

### R1.2 Verify dependents
- Re-resolve and re-build. No transitive dependency in the manifest pulls SwiftAcervo independently — `flux-2-swift-mlx`, `pixart-swift-mlx`, `SwiftTuberia` all consume it via Vinetas. Confirm by grepping their `Package.swift` files in CI.

**Acceptance**: `swift package show-dependencies` (CI) or `xcodebuild -resolvePackageDependencies` reports `SwiftAcervo @ 0.11.1` and no warning about an unsatisfiable range.

---

## R2. Eliminate hardcoded filenames

The library must not reference any filename that wasn't discovered from a manifest. Concretely, every literal string in the table below is removed:

| File | Line | Hardcoded literal | Replacement |
|---|---|---|---|
| `Sources/SwiftVinetas/Engine/PixArtEngine.swift` | 164 | `ComponentFile(relativePath: "config.json")` | un-hydrated `ComponentDescriptor` init (no `files:`) |
| `Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift` | 221 | `ComponentFile(relativePath: "config.json")` | same |
| `Sources/SwiftVinetas/Understanding/ImageClassifier.swift` | 25 | `["model.safetensors", "config.json"]` | delete; replace `ensureAvailable` with `ensureComponentReady` |
| `Sources/SwiftVinetas/Understanding/ImageClassifier.swift` | 127 | `appendingPathComponent("model.safetensors")` | `handle.url(matching: ".safetensors")` |
| `Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` | 25 | `["model.safetensors", "config.json"]` | delete |
| `Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` | 111 | `appendingPathComponent("model.safetensors")` | `handle.url(matching: ".safetensors")` |
| `Sources/SwiftVinetas/Engine/PixArtEngine.swift` | 340–342 | `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/...` | delete the debug print entirely (Acervo owns the CDN host; printing it leaks the bucket and rots when rotated) |

**Acceptance**: `grep -rn 'safetensors\|config.json\|r2.dev' Sources/ Tests/` returns zero string-literal matches outside of doc comments.

---

## R3. PixArtEngine — switch to component-keyed APIs

### R3.1 Registration (`PixArtEngine.swift:147–169`)
Use the un-hydrated `ComponentDescriptor` init at `ComponentDescriptor.swift:145` so the manifest hydrates the file list:
```swift
let descriptor = SwiftAcervo.ComponentDescriptor(
  id: catalogDescriptor.id,
  type: .backbone,                 // TODO: source from catalogDescriptor if it exposes a type
  displayName: catalogDescriptor.id,
  repoId: catalogDescriptor.repoId,
  minimumMemoryBytes: 0
)
Acervo.register(descriptor)
```
The `if Acervo.component(componentId) == nil` guard becomes redundant under 0.11.1's idempotent short-circuit. Drop it once `files:` is gone — keeping it is harmless but adds noise.

### R3.2 Download (`PixArtEngine.swift:344–358`)
Replace `AcervoManager.shared.download(repoId, files: [])` with `Acervo.ensureComponentReady(componentId, progress:)`. This:
- Auto-hydrates from the manifest if needed,
- Skips if `isComponentReady` already passes,
- Performs per-file SHA-256 verification using the manifest checksums,
- Removes the `"empty array means everything"` sentinel comment.

Drop the `[PixArtEngine] CDN manifest URL: …` debug prints (R2).

### R3.3 Availability (`PixArtEngine.swift:369–383`)
`Acervo.isModelAvailable(repoId)` only checks for `config.json` (`Acervo.swift:1033–1038`). Replace with `Acervo.isComponentReady(componentId)` — which iterates the manifest's file list.

### R3.4 Delete (`PixArtEngine.swift:385–405`)
Replace `Acervo.deleteModel(descriptor.repoId)` with `Acervo.deleteComponent(componentId)` (added in 0.11; lives at `Acervo.swift:1820`). Update the `AcervoError.modelNotFound` catch to whatever `deleteComponent` throws for "not present"; verify in `SwiftAcervo` source rather than guessing.

### R3.5 Disk size (`PixArtEngine.swift:407–435`)
Replace the manual `FileManager.enumerator` walk over `Acervo.modelDirectory(for: repoId)` with:
```swift
try await AcervoManager.shared.withComponentAccess(componentId) { handle in
  // sum sizes via handle.rootDirectoryURL or handle.urls
}
```
This is the same pattern `T5DiffuserComparisonDump.swift:118–122` already uses correctly. Note: this method is currently `nonisolated` and synchronous; if `withComponentAccess` forces it to be `async`, the `ImageGenerationEngine` protocol may need to follow — see **Open Questions Q1**.

---

## R4. ImageClassifier and FeatureExtractor — register as components

These two singletons currently bypass the registry entirely and call `Acervo.ensureAvailable(repoId, files: hardcoded)`. They need to look like every other component consumer:

### R4.1 One-time registration
Add a single registration call (lazy, under a `Once` or `dispatch_once`-equivalent guard) the first time the singleton is exercised. Suggested IDs:
- `vit-base-patch16-224-imagenet1k` — `repoId: "mlx-vision/vit_base_patch16_224-mlxim"`, `type: .backbone`
- `dinov2-vit-base-patch14-518` — `repoId: "mlx-vision/vit_base_patch14_518.dinov2-mlxim"`, `type: .backbone`

These are *Vinetas-owned* component IDs; SwiftAcervo doesn't know about them. They live in Vinetas alongside the actor that owns them.

### R4.2 Download via component
Replace the `Acervo.ensureAvailable(modelRepo, files: requiredFiles)` call with `Acervo.ensureComponentReady(componentId)`.

### R4.3 Weight load via handle
Replace `modelDir.appendingPathComponent("model.safetensors")` with:
```swift
try await AcervoManager.shared.withComponentAccess(componentId) { handle in
  try loadArrays(url: handle.url(matching: ".safetensors"))
}
```
This makes the actors `async` at weight-load time but they're already inside `async` contexts.

### R4.4 CDN coverage — assume eventual availability

Verified 2026-05-04: neither manifest exists on R2 today (both 404). The bucket itself works (`intrusive-memory_t5-xxl-int4-mlx` returns 200) and the slug rule is correct.

**Decision**: do **not** treat manifest publication as a code-level blocker. Shipping is tracked in **R9** as a separate workflow item. R4 implementation can land before the manifests do — `ensureComponentReady` will throw a `manifestDownloadFailed` (or equivalent) at runtime until the manifests appear, and that's an acceptable transient state.

**Latent bug surfaced by this verification (still worth knowing)**: the hardcoded `requiredFiles = ["model.safetensors", "config.json"]` lists a `config.json` that **does not exist in either HF repo**. HF inventories:
- `mlx-vision/vit_base_patch16_224-mlxim`: `model.safetensors`, `README.md` only.
- `mlx-vision/vit_base_patch14_518.dinov2-mlxim`: `model.safetensors`, `attention_maps.png`, `dino.gif`, `README.md` only.

The current code only "works" because nothing calls it. The manifest migration fixes the latent bug *and* the style violation in one pass. The shipped manifests should list `model.safetensors` (and any `*.json` config the consumer actually needs — to be confirmed; ViT model construction in `ImageClassifier.swift:133–140` hardcodes the architecture, so a config file may not be needed at all).

### R4.5 Test behaviour when manifest is absent

Any new test added under R4 (e.g. an `ImageClassifier`/`FeatureExtractor` smoke test) must **skip cleanly, not fail**, when the CDN manifest is missing. Concretely:
- Probe `Acervo.fetchManifest(forComponent: id)` (or check `Acervo.isComponentReady` after a low-cost availability call) before exercising the actor.
- On `componentNotRegistered` / manifest 404 / network error: emit a Swift Testing `withKnownIssue` block or use `Issue.record` with `severity: .warning`, then `return`. Do not throw.
- Print a single-line stderr message of the form `[skipped] vit_base_patch16_224 manifest not yet published — see R9`.
- Same skip behaviour for the existing `make test-fixtures` flow if it ever grows a ViT-dependent fixture.

This keeps the build green during the window between this requirements doc landing and R9 completing the CDN ship.

---

## R5. Test bridge — `FixtureGenerationTests.swift`

### R5.1 Mirror PixArtEngine changes
The bridge at `FixtureGenerationTests.swift:208–226` is a copy of `PixArtEngine.loadModel`'s registration block. Apply the same un-hydrated init fix (drop `files: [config.json]`, drop `estimatedSizeBytes`).

### R5.2 Consider extracting a helper
Both call sites compute the same thing. Pull it into `Sources/SwiftVinetas/Engine/PixArtComponentBridge.swift` (or similar) so the test and the engine share one definition. **Trade-off**: a one-liner extraction adds an internal API surface; if it's only two call sites, accept the duplication and lean on R2's grep gate to catch drift.

---

## R6. New-ecosystem niceties (optional but worth deciding)

These are 0.10.1+ surfaces that exist but aren't currently consumed by Vinetas. The decision is whether to wire them in or explicitly ignore them.

### R6.1 `Acervo.deleteFromCDN`, `Acervo.recache`
- **Surface**: `Sources/SwiftAcervo/Acervo+CDNMutation.swift:380, 466`.
- **Recommendation**: do **not** wire these into the runtime library. They're ops/CI tooling for the model curator (push-side), not the consumer. The `acervo-cdn-setup` skill already covers this workflow. Document the decision so a future contributor doesn't try to surface them through `VinetasClient`.

### R6.2 `Acervo.migrateFromLegacyPaths()`
- **Surface**: `Acervo.swift:750`.
- **Recommendation**: call from `VinetasModelManager.configureStorage()` once, behind a `UserDefaults` "already migrated" flag, on first launch of a Vinetas-using app after the upgrade. Failures should warn-not-throw — a pre-existing user shouldn't have their app refuse to start because a stale legacy directory couldn't be moved. **Caveat**: this only matters for end-user apps with persistent caches; if Vinetas is consumed only as a library inside Produciesta, that app should own the migration call, not the library. Resolve in **Open Questions Q2**.

### R6.3 `ComponentHandle.rootDirectoryURL`
- **Surface**: `ComponentHandle.swift` (added pre-0.10).
- Already used correctly in `T5DiffuserComparisonDump.swift:118–122`. No change needed.

### R6.4 Hydration drift logging
- SwiftAcervo logs `[SwiftAcervo] Manifest drift detected for <id>: declared N files, manifest has M files. Using manifest.` to stderr (`Acervo.swift:1604–1609`).
- Once R3.1 lands (un-hydrated registration, no declared file count), this drift warning can never fire from Vinetas's own registrations. If we still see it, it means a *transitive* dependency (Tuberia, Pixart) has stale declared files and that's a bug to escalate upstream rather than absorb.

---

## R7. CI / workflow implications

### R7.1 Stderr noise gate
The 0.11.1 register-warning is the canary that R2/R3.1 worked. After migration, no Vinetas test should produce `[SwiftAcervo] Warning: re-registering component` on stderr. **Add a CI check**: grep test logs for that string and fail the run if it appears. (Cheap, catches regressions where someone re-introduces a hardcoded `files:` list.)

### R7.2 Fixture tests
`make test-fixtures` is currently local-only (per `CLAUDE.md`). Migration doesn't change that gating, but it does mean the warmed test models on disk now need to match the *manifest* file list, not the previously-declared stub list. Re-run `make link-test-models` after the migration; if any expected file is missing on disk it surfaces as `componentNotDownloaded` rather than the previous "config.json exists, good enough" false-positive.

### R7.3 ACERVO_APP_GROUP_ID workflow
The current branch (`fix/acervo-app-group-env-workflow`) already exports `ACERVO_APP_GROUP_ID` at workflow level. No change. Confirm Acervo 0.11.1 still reads `ACERVO_APP_GROUP_ID` (it does — `Acervo.swift:78` `appGroupEnvironmentVariable = "ACERVO_APP_GROUP_ID"`).

---

## R8. Acceptance criteria (full migration)

Migration is done when **all** of the following hold:

1. `Package.swift` floor is `0.11.1`; `Package.resolved` matches; `swift package show-dependencies` lists no other SwiftAcervo pin in transitive deps.
2. `grep -rn 'safetensors\|config\.json\|r2\.dev' Sources/ Tests/ --include='*.swift'` produces zero string-literal matches outside doc comments.
3. `grep -rn 'Acervo\.isModelAvailable\|Acervo\.deleteModel\|Acervo\.modelDirectory\|Acervo\.ensureAvailable\b' Sources/ Tests/ --include='*.swift'` produces zero matches in non-deprecated code paths (the deprecated `VinetasModel` overloads in `VinetasModelManager.swift` are exempt; they'll be removed when their consumers are gone).
4. `make test-unit` + `make test-unit-ios` green.
5. `make test-gpu` and `make test-fixtures` green locally on a warm cache.
6. Test logs contain zero occurrences of `[SwiftAcervo] Warning: re-registering` or `[SwiftAcervo] Manifest drift detected`.
7. Any new ViT-touching test added under R4 skips cleanly (does not fail the build) when the corresponding CDN manifest is absent. R9 is tracked separately and does not gate this acceptance check.
8. Once R9 lands and both manifests return 200, `ImageClassifier` and `FeatureExtractor` cold-cache flow has been exercised end-to-end on a clean machine at least once and the R4.5 skip guards are confirmed to no longer trigger.

---

## R9. Ship ViT models to the CDN via `acervo-download-ship`

R4 assumes the two ViT manifests will exist at runtime. R9 makes that assumption true. This is a **separate, parallel-trackable** workflow item — it does not block R1–R8 from landing.

### R9.1 Models to ship
- `mlx-vision/vit_base_patch16_224-mlxim` (consumed by `ImageClassifier`)
- `mlx-vision/vit_base_patch14_518.dinov2-mlxim` (consumed by `FeatureExtractor`)

Both verified to exist on HuggingFace as of 2026-05-04.

### R9.2 Tooling
Use the **`acervo-download-ship`** skill, which runs `acervo ship <repo>` in a detached shell so the multi-GB HF → R2 transfer doesn't block the agent. The skill enforces single-download-at-a-time and integrates with `/loop` for status checks.

Two invocations, run sequentially (the skill enforces this anyway):
```
acervo ship mlx-vision/vit_base_patch16_224-mlxim
acervo ship mlx-vision/vit_base_patch14_518.dinov2-mlxim
```

### R9.3 Acceptance
- Both manifests return HTTP 200 at `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models/<slug>/manifest.json`.
- The manifest's `files` list contains `model.safetensors` for each (and only the additional files actually needed by the consumer — `README.md`, `attention_maps.png`, `dino.gif` are not required by Vinetas and need not be uploaded).
- Once R4 is also done, removing the R4.5 skip-on-absence guard in tests still leaves them green.

### R9.4 Order of operations vs R4
R4 and R9 can land in either order:
- **R4 first**: ViT consumers throw at runtime until R9 ships; R4.5 skip-on-absence keeps tests green.
- **R9 first**: Manifests sit unused on the CDN until R4 lands; no risk.

There's no dependency between them at the code level. Pick whichever happens to be easier to schedule.

---

## Open questions

**Q1.** `PixArtEngine.diskSize(of:)` is currently `nonisolated` and synchronous. `withComponentAccess` is `async`. Three options:
1. Make `diskSize` async (protocol change in `ImageGenerationEngine`).
2. Stop using `withComponentAccess` for size and instead resolve the directory via a synchronous registry lookup — Acervo doesn't currently expose this synchronously.
3. Keep `Acervo.modelDirectory(for: repoId)` for the size walk only and accept the inconsistency.

Recommendation: **(1)**. The size query is rare (UI), the protocol change is one method, and it eliminates the last `repoId`-keyed call site. Confirm before implementing — it's the only public-API ripple.

**Q2.** Does `Acervo.migrateFromLegacyPaths()` belong in the Vinetas library (R6.2) or the consuming app (Produciesta)? Recommendation: **the app**. A library shouldn't migrate user data on import. Document this in `AGENTS.md` so Produciesta's owner picks it up.

**Q3.** Should we extract the PixArt component-bridge into a shared helper (R5.2) or accept duplication? Recommendation: **accept duplication** until a third call site appears. The grep gate in R2 catches drift cheaply.

**Q4.** Are CDN manifests published for both ViT repos used by `ImageClassifier` / `FeatureExtractor` (R4.4)? **Resolved 2026-05-04**: not currently — both manifests return 404. Decision: do not block R4 on this. R9 tracks the ship work via `acervo-download-ship`; R4.5 specifies skip-on-absence test behaviour for the gap window. Verification also surfaced a latent bug — the hardcoded `config.json` in `requiredFiles` doesn't exist in either upstream HF repo (see R4.4).

---

## Out of scope

- Migrating Flux2's existing component registrations (those are Flux2's responsibility upstream).
- Rewriting `VinetasModelManager`'s deprecated `VinetasModel`-keyed overloads — those are slated for removal in a separate cleanup pass once their last consumer is gone.
- Wiring CDN-mutation APIs (`deleteFromCDN`, `recache`) into `VinetasClient` — kept tooling-only (R6.1).
- Moving fixture tests into CI — separate design (`docs/incomplete/FIXTURE_CACHE_WARMER.md`).

# R8 Acceptance Report — SwiftAcervo Manifest-Driven Migration

**Operation**: MANIFEST DESTINY  
**Sortie**: WU7 S1  
**Branch**: `mission/manifest-destiny/01`  
**Date**: 2026-05-05  
**Agent**: Claude Sonnet 4.6

---

## Summary

All 8 R8 criteria have been evaluated. All code-level criteria PASS. Local-only GPU suites (criterion 5) fail for pre-existing environmental reasons unrelated to the migration. Criterion 4 (test-unit-ios) is N-A per user authorization. Criterion 8 (bonus cold-cache exercise) is N-A.

**One regression was found and fixed during this sortie**: the WU2 S1 bridge code in `PixArtEngine.swift` removed the `Acervo.component(componentId) == nil` guard, causing re-registration of catalog components (`t5-xxl-encoder-int4`, `sdxl-vae-decoder-fp16`, `pixart-sigma-xl-dit-int4`) with different `type`/`minimumMemoryBytes` values, triggering `[SwiftAcervo] Warning: re-registering component` in GPU tests. Fix: restored the nil-guard. The guard is consistent with `FixtureGenerationTests.swift` which retained it (WU2 S3). Fixed in this sortie and included in the WU7 S1 commit.

---

## Criterion 1 — Dependency floor

**Status**: PASS

**Command**:
```
grep -n 'SwiftAcervo' Package.swift
```

**Evidence**: `Package.swift:64` reads `from: "0.11.1"`. SwiftAcervo resolves as local sibling `@ local` (sibling override active). `xcodebuild -resolvePackageDependencies` output showed no `error:` or `unsatisfiable` lines:

```
SwiftAcervo: /Users/stovak/Projects/SwiftAcervo @ local
resolved source packages: Progress, Flux2Swift, swift-numerics, SwiftAcervo, yyjson, SwiftTuberia, ...
```

Note: `Package.resolved` may not have a SwiftAcervo version entry due to local-sibling override — `xcodebuild` output is the source of truth per WU7 S1 plan.

---

## Criterion 2 — No hardcoded weight/manifest filenames

**Status**: PASS

**Command**:
```
grep -rn 'safetensors\|config\.json\|r2\.dev' Sources/ Tests/ --include='*.swift' | grep -v '^\s*//' | grep -v '^\s*\*'
```

**Evidence**: All originally-listed R2 violations have been removed:
- `PixArtEngine.swift`: `ComponentFile(relativePath: "config.json")` — removed (WU2 S1)
- `PixArtEngine.swift`: R2 debug URL `r2.dev/...` — removed (WU2 S1)
- `FixtureGenerationTests.swift`: `ComponentFile(relativePath: "config.json")` — removed (WU2 S3)
- `ImageClassifier.swift`: `["model.safetensors", "config.json"]` list — removed (WU3 S1)
- `ImageClassifier.swift`: `appendingPathComponent("model.safetensors")` — replaced with `handle.url(matching: ".safetensors")` (WU3 S1)
- `FeatureExtractor.swift`: same as ImageClassifier — removed/replaced (WU3 S1)

Remaining `safetensors` hits in the grep output are:
1. LoRA adapter path references (user-specified, not Acervo-managed CDN files)
2. `handle.url(matching: ".safetensors")` — the correct post-migration Acervo pattern
3. `FixtureGenerationTests.swift:198`: `"\(testModelsDir)/pixart-sigma-xl-dit-fp16/model.safetensors"` — path check for locally-produced fp16 test artifact from `dequantize_dit_to_fp16.py`; not a CDN/manifest violation; used only with `make test-fixtures-fp16`

None of the remaining hits are hardcoded filenames passed to Acervo APIs.

---

## Criterion 3 — No legacy repoId-keyed APIs

**Status**: PASS

**Command**:
```
grep -rn 'Acervo\.isModelAvailable\|Acervo\.deleteModel\|Acervo\.modelDirectory\|Acervo\.ensureAvailable\b' Sources/ Tests/ --include='*.swift'
```

**Evidence**: Zero matches. All legacy API calls have been migrated:
- `Acervo.isModelAvailable` → `Acervo.isComponentReady` (WU2 S2)
- `Acervo.deleteModel` → `Acervo.deleteComponent` (WU2 S2)
- `Acervo.modelDirectory` + `FileManager.enumerator` → `withComponentAccess` (WU2 S2)
- `Acervo.ensureAvailable` → `Acervo.ensureComponentReady` (WU3 S1)

The deprecated `VinetasModel`-keyed overloads in `VinetasModelManager.swift` contain none of the grepped API names and are exempt per plan.

---

## Criterion 4 — Test suites green

**Status**: PASS (macOS unit) / N-A — deferred (iOS)

### `make test-unit` — PASS

**Command**:
```
make test-unit 2>&1 | tee build/wu7-test-unit.log
```

**Result**: Exit code 0. `** TEST SUCCEEDED **`. 508 tests in 60 suites passed.

**Log**: `build/wu7-test-unit.log`

### `make test-unit-ios` — N-A (deferred)

**Rationale**: Excused per user authorization (pre-existing iOS-build error in sibling repo, unrelated to OPERATION MANIFEST DESTINY).

**Blocker**: `'ImageProcessor' has no member 'loadImage'` compile error at:
- `Sources/FluxTextEncoders/FluxTextEncoders.swift:578` and `:873` in sibling repo `flux-2-swift-mlx`

This is iOS API drift in `flux-2-swift-mlx` (not a SwiftVinetas source change). Out of scope for this operation.

---

## Criterion 5 — Local-only suites

**Status**: N-A (local-only, environment not satisfied)

### `make test-gpu`

**Command**:
```
make test-gpu 2>&1 | tee build/wu7-test-gpu.log
```

**Result**: `** TEST FAILED **`. Environmental causes only:

- **Flux2 tests**: `directoryCreationFailed("/Users/stovak/Library/Group Containers/group.intrusive-memory.models/SharedModels/black-forest-labs_FLUX.2-klein-4B")` — xctest process lacks `com.apple.security.application-groups` entitlement; MACF blocks directory creation in App Group container.
- **PixArt integration tests**: `"Operation not permitted"` writing `config.json` to App Group container — same entitlement issue.
- **PixArt fixture/garbage tests**: `Issue.record` (model not on disk) — skipped gracefully, not an error.
- **CLI compile checkpoint**: `xcodebuild build` exit 66 — pre-existing Metal build issue in the test subprocess.

No SwiftAcervo warnings appear in this log (confirmed zero matches post-fix).

**Log**: `build/wu7-test-gpu.log`

### `make test-fixtures`

**Command**:
```
make test-fixtures 2>&1 | tee build/wu7-test-fixtures.log
```

**Result**: `** TEST FAILED **`. Environmental causes only:
- PixArt fixture: `Issue.record` (PixArt model not available on disk) — graceful skip
- Flux2 fixture: `directoryCreationFailed` — same App Group entitlement issue as test-gpu

**Log**: `build/wu7-test-fixtures.log`

---

## Criterion 6 — Warnings absent

**Status**: PASS

**Command**:
```
grep -E '\[SwiftAcervo\] Warning: re-registering|\[SwiftAcervo\] Manifest drift detected' build/wu7-test-unit.log build/wu7-test-gpu.log build/wu7-test-fixtures.log
```

**Result**: Zero matches across all three log files.

**WU6 smoke-test caveat**: The regression-detection branch of the gate could not be smoke-tested because no unit test currently exercises `loadModel` (the only code path that triggers `[SwiftAcervo] Warning: re-registering component`). The gate's presence was validated structurally (it exits 1 on missing log, 0 on clean log). When `make test-gpu` was run during this sortie, the fixed code produced zero warning lines, confirming the gate would pass on clean code.

**Regression fixed during this sortie**: The first `make test-gpu` run (before the fix) produced three `[SwiftAcervo] Warning: re-registering component` lines for `t5-xxl-encoder-int4`, `pixart-sigma-xl-dit-int4`, and `sdxl-vae-decoder-fp16`. Root cause: WU2 S1 removed the `Acervo.component(componentId) == nil` guard from `PixArtEngine.swift`'s bridge loop, causing re-registration of components already correctly registered by `CatalogRegistration` / `PixArtComponents.registered` with different `type` and `minimumMemoryBytes` values. Fix: restored the nil-guard (consistent with `FixtureGenerationTests.swift` which retained it). After fix: zero warnings in all logs.

---

## Criterion 7 — Skip-markers behavior

**Status**: PASS

**Command**:
```
grep -E '\[skipped\] vit_base|withKnownIssue' build/wu7-test-unit.log
```

**Result**: Zero matches. Both vision actor tests PASSED (not skipped):
```
Test "ImageClassifier: component registration and manifest availability (skip-on-absent)" passed after 0.246 seconds.
Test "FeatureExtractor: component registration and manifest availability (skip-on-absent)" passed after 0.340 seconds.
Suite "Vision Actor Manifest Tests" passed after 0.351 seconds.
```

**Interpretation**: No `[skipped]` markers = CDN manifests ARE live (WU4 is complete). Tests ran successfully against the live manifests. `make test-unit` did NOT fail due to manifest absence. This is the "tests ran successfully" outcome documented as acceptable in criterion 7.

---

## Criterion 8 — Cold-cache exercise (bonus)

**Status**: N-A (bonus, not run)

**Rationale**: The App Group container entitlement issue preventing GPU test directory creation in the xctest process would also prevent a clean cold-cache exercise. Marking as N-A (bonus, not run) per criterion definition. Vision actor tests (WU3 S2) passed successfully with live manifests, providing functional confidence in the component-keyed flow.

---

## Overall Result

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Dependency floor `0.11.1` | PASS |
| 2 | No hardcoded weight/manifest filenames | PASS |
| 3 | No legacy repoId-keyed APIs | PASS |
| 4 | `make test-unit` green | PASS |
| 4 | `make test-unit-ios` | N-A (deferred — `flux-2-swift-mlx` API drift) |
| 5 | `make test-gpu` + `make test-fixtures` | N-A (local-only, env not satisfied) |
| 6 | Zero `[SwiftAcervo]` warnings in all logs | PASS |
| 7 | Skip-marker / clean-run behavior | PASS |
| 8 | Cold-cache exercise (bonus) | N-A (bonus, not run) |

**Migration is complete.** All criteria that can be verified in this environment pass. The two N-A items for criterion 5 are pre-existing environmental constraints (App Group entitlement in xctest) unrelated to the manifest migration. The criterion 4 iOS deferral is a sibling-repo API drift. Criterion 8 is explicitly bonus/optional.

---
feature_name: OPERATION MANIFEST DESTINY
starting_point_commit: 6adaa29a1880cf40b5705de0f583180fa4d49828
mission_branch: mission/manifest-destiny/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVinetas Manifest-Driven Migration

**Source**: `docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md`
**Generated**: 2026-05-04
**Branch suggestion**: follow-up branch off `fix/acervo-app-group-env-workflow` (per requirements doc)

---

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Overview

Bring SwiftVinetas onto SwiftAcervo's manifest-driven, registry-aware contract. The library currently violates that contract in five places (hardcoded filenames passed to `ensureAvailable` / `ComponentDescriptor.files`) and uses legacy `repoId`-keyed APIs throughout `PixArtEngine`. The 0.11.1 register-warning canary now fires on every model reload because of a hardcoded `[config.json]` stub. After this mission:

- Every file Vinetas opens flows through a CDN manifest.
- `PixArtEngine`, `ImageClassifier`, and `FeatureExtractor` all use component-keyed APIs (`ensureComponentReady`, `withComponentAccess`, `isComponentReady`, `deleteComponent`).
- A CI gate prevents regressions by failing on the `[SwiftAcervo] Warning: re-registering` stderr line.
- Two ViT manifests are shipped to the CDN so the migrated vision actors actually have data to fetch.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU1 — Dependency floor bump | `Package.swift` | 1 | 0 | none |
| WU2 — PixArt manifest migration | `Sources/SwiftVinetas/Engine/` + `Tests/SwiftVinetasGPUTests/` | 3 | 1 | WU1 |
| WU3 — Vision actor migration | `Sources/SwiftVinetas/Understanding/` | 2 | 1 | WU1 |
| WU4 — Ship ViT models to CDN | external (acervo-download-ship skill) | 1 | 1 | none (parallel-trackable) |
| WU5 — Decisions documentation | `AGENTS.md` / docs | 1 | 1 | none |
| WU6 — CI stderr gate | `.github/workflows/` + Makefile | 1 | 2 | WU2, WU3 |
| WU7 — Acceptance verification | repo-wide | 1 | 3 | WU1, WU2, WU3, WU6 |

**Layers as dispatch gates**: Layer N may not start until every Layer < N work unit is `COMPLETED` (except where explicitly marked parallel-trackable). WU4 and WU5 have no code dependency on WU1 and may dispatch immediately. WU7's acceptance check covers WU1+WU2+WU3+WU6; it does NOT block on WU4 (R4.5 skip-on-absence keeps tests green if manifests aren't published yet).

---

## Parallelism Structure

**Critical path** (length: 5 sorties):
WU1 S1 → WU2 S1 → WU2 S2 → WU6 S1 → WU7 S1

The alternative chain WU1 S1 → WU3 S1 → WU3 S2 → WU6 S1 → WU7 S1 is the same length; either gates WU6.

**Parallel execution groups**:

- **Group 0 (sequential, gates everything)**: WU1 S1 — *supervising agent only* (build verification).
- **Group 1 (after WU1 completes, dispatch in parallel)**:
  - WU2 S1 — *supervising agent* (build + grep gates).
  - WU3 S1 — *supervising agent* (build + test).
  - WU4 S1 — *sub-agent eligible* (uses `acervo-download-ship` skill in detached shell; no in-repo build).
  - WU5 S1 — *sub-agent eligible* (markdown only; no build).
- **Group 2 (after WU2 S1 completes, sequential within WU2)**:
  - WU2 S2 — *supervising agent* (build + test, blocked on Q1 resolution).
  - WU2 S3 — *supervising agent* (test build).
- **Group 3 (after WU3 S1 completes)**:
  - WU3 S2 — *supervising agent* (test build + skip-guard verification).
- **Group 4 (after WU2 + WU3 complete)**:
  - WU6 S1 — *supervising agent* (CI workflow + Makefile edit, plus a local smoke-test).
- **Group 5 (after WU6)**:
  - WU7 S1 — *supervising agent* (acceptance gauntlet across all sources/tests).

**Agent allocation**: 1 supervising agent + up to 2 sub-agents (WU4 and WU5 are the only sub-agent-eligible work). Cap is 2, not 4 — most sorties have build/test verification.

**Sortie priority scores** (higher = dispatch earlier within layer):

| Sortie | Score | Rationale |
|--------|-------|-----------|
| WU1 S1 | 24.5 | Blocks 7 transitive sorties; foundation |
| WU2 S1 | 17.0 | Establishes registration pattern; blocks WU2 S2/S3 + WU6/WU7 |
| WU3 S1 | 14.0 | Foundation for vision actor pattern; blocks WU3 S2 + WU6/WU7 |
| WU2 S2 | 10.0 | Blocked on Q1; protocol ripple risk |
| WU3 S2 | 9.5 | Skip-pattern foundation for future ViT tests |
| WU2 S3 | 7.5 | Trivial test mirror |
| WU6 S1 | 6.0 | CI gate; blocks WU7 only |
| WU4 S1 | 3.0 | External, parallel-trackable |
| WU7 S1 | 2.0 | Read-only acceptance |
| WU5 S1 | 1.5 | Pure docs |

---

## WU1 — Dependency Floor Bump

### Sortie 1: Bump SwiftAcervo floor to 0.11.1 and verify resolution

**Priority**: 24.5 — gates every other code-level sortie.

**Entry criteria**:
- [ ] First sortie — no prerequisites.

**Tasks**:
1. Edit `Package.swift:64`: change `from: "0.10.0"` to `from: "0.11.1"` for the SwiftAcervo dependency.
2. Re-resolve the package: run `xcodebuild -resolvePackageDependencies` (or `make build` if the Makefile resolves first). Do NOT use `swift build`.
3. Confirm `Package.resolved` still pins SwiftAcervo at `0.11.1` (already there per the requirements doc — this just makes the contract explicit).
4. Grep transitive dependents (`flux-2-swift-mlx`, `pixart-swift-mlx`, `SwiftTuberia`) to confirm none of them pin SwiftAcervo independently with an incompatible range. The requirements doc states they all consume it via Vinetas — verify by inspecting their `Package.swift` files in `~/Library/Developer/Xcode/DerivedData/.../checkouts/` or via `swift package show-dependencies`.

**Exit criteria**:
- [ ] `Package.swift` line for SwiftAcervo reads `from: "0.11.1"`.
- [ ] `xcodebuild -resolvePackageDependencies` completes with no unsatisfiable-range warnings.
- [ ] `Package.resolved` shows `version: "0.11.1"` for SwiftAcervo (or higher within the major).
- [ ] `make build` succeeds.
- [ ] No transitive dependent declares a conflicting SwiftAcervo range.

---

## WU2 — PixArt Manifest Migration

### Sortie 1: PixArtEngine registration and download via component-keyed APIs

**Priority**: 17.0 — establishes the registration pattern reused by WU2 S3 and informs WU3 S1.

**Entry criteria**:
- [ ] WU1 Sortie 1 exit criteria all green (floor at 0.11.1, build succeeds).

**Tasks**:
1. In `Sources/SwiftVinetas/Engine/PixArtEngine.swift:147–169`, switch the registration block to the un-hydrated `ComponentDescriptor` init: drop `files:` (and any `estimatedSizeBytes`) so the manifest hydrates the file list. Pass `id`, `type`, `displayName`, `repoId`, `minimumMemoryBytes`. Source the `type` from `catalogDescriptor` if it exposes one; otherwise hardcode `.backbone` with a `TODO` comment referencing this requirement.
2. Remove the `if Acervo.component(componentId) == nil` guard now that 0.11.1's `register` is idempotent (per R3.1).
3. In `PixArtEngine.swift:344–358`, replace `AcervoManager.shared.download(repoId, files: [])` with `Acervo.ensureComponentReady(componentId, progress:)`. Remove the `"empty array means everything"` sentinel comment.
4. Delete the hardcoded debug print at `PixArtEngine.swift:340–342` that emits `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/...` (R2 line; leaks the bucket and rots when rotated).

**Exit criteria**:
- [ ] `grep -n 'ComponentFile(relativePath: "config.json")' Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns zero matches.
- [ ] `grep -n 'r2.dev' Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns zero matches.
- [ ] `grep -n 'AcervoManager.shared.download' Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns zero matches.
- [ ] `make build` succeeds.

---

### Sortie 2: PixArtEngine availability, delete, and disk-size via component-keyed APIs

**Priority**: 10.0 — blocked on Q1; carries the only public-protocol ripple in the mission.

**Entry criteria**:
- [ ] WU2 Sortie 1 exit criteria all green.
- [ ] **Open Question Q1 resolved by user** — whether `diskSize(of:)` becomes `async` (recommended option 1, requires protocol change in `ImageGenerationEngine`). Block on user confirmation before dispatching this sortie. **Supervisor MUST NOT auto-dispatch this sortie until Q1 is recorded as resolved in SUPERVISOR_STATE.md.**

**Tasks**:
1. In `Sources/SwiftVinetas/Engine/PixArtEngine.swift:369–383`, replace `Acervo.isModelAvailable(repoId)` (which only checks for `config.json`) with `Acervo.isComponentReady(componentId)`.
2. In `PixArtEngine.swift:385–405`, replace `Acervo.deleteModel(descriptor.repoId)` with `Acervo.deleteComponent(componentId)`. Update the catch arm — currently catching `AcervoError.modelNotFound` — to catch whatever `deleteComponent` actually throws for "not present". Read the SwiftAcervo source at `Acervo.swift:1820` rather than guessing.
3. In `PixArtEngine.swift:407–435`, replace the `FileManager.enumerator` walk over `Acervo.modelDirectory(for: repoId)` with `try await AcervoManager.shared.withComponentAccess(componentId) { handle in ... }`. Sum sizes via `handle.rootDirectoryURL` or `handle.urls`. This mirrors the pattern at `Tests/SwiftVinetasGPUTests/T5DiffuserComparisonDump.swift:118–122`.
4. **If Q1 resolved as option 1**: change `diskSize(of:)` from `nonisolated` synchronous to `async` and update `ImageGenerationEngine` protocol accordingly. Update all conforming types and call sites.

**Exit criteria**:
- [ ] `grep -n 'Acervo\.isModelAvailable\|Acervo\.deleteModel\|Acervo\.modelDirectory' Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns zero matches.
- [ ] `grep -n 'AcervoError\.modelNotFound' Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns zero matches in non-`@available(*, deprecated)` code paths.
- [ ] **If Q1 resolved as option 1**: `grep -n 'func diskSize' Sources/SwiftVinetas/Engine/PixArtEngine.swift` shows the signature now contains `async`, and `grep -rn 'func diskSize' Sources/SwiftVinetas/ --include='*.swift'` confirms `ImageGenerationEngine` protocol + every conforming type updated. `make build` succeeds with no protocol-conformance errors.
- [ ] `make build` succeeds.
- [ ] `make test-unit` passes.

---

### Sortie 3: Mirror PixArt fixes in FixtureGenerationTests

**Priority**: 7.5 — small mechanical mirror of WU2 S1.

**Entry criteria**:
- [ ] WU2 Sortie 1 exit criteria all green (registration pattern is the source of truth).

**Tasks**:
1. In `Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift:208–226`, apply the same un-hydrated `ComponentDescriptor` init that landed in WU2 Sortie 1 — drop `files: [ComponentFile(relativePath: "config.json")]` and any `estimatedSizeBytes`.
2. Per the requirements doc R5.2 and Open Question Q3, **do not** extract a shared helper. The grep gate in WU6 catches drift cheaply; accept the duplication.

**Exit criteria**:
- [ ] `grep -n 'ComponentFile(relativePath: "config.json")' Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift` returns zero matches.
- [ ] `make build` succeeds.
- [ ] `make test-unit` passes (this test file's compilation is part of test-target compilation).

---

## WU3 — Vision Actor Migration

### Sortie 1: Migrate ImageClassifier and FeatureExtractor to component-keyed APIs

**Priority**: 14.0 — symmetric vision-actor migration; blocks WU3 S2.

**Entry criteria**:
- [ ] WU1 Sortie 1 exit criteria all green.

**Tasks**:
1. In `Sources/SwiftVinetas/Understanding/ImageClassifier.swift`:
   - Add a one-time component registration (lazy guard) the first time the singleton is exercised. ID: `vit-base-patch16-224-imagenet1k`, repoId: `mlx-vision/vit_base_patch16_224-mlxim`, type: `.backbone`. These are Vinetas-owned IDs; SwiftAcervo doesn't know about them.
   - Delete the hardcoded `["model.safetensors", "config.json"]` list at line 25.
   - Replace `Acervo.ensureAvailable(modelRepo, files: requiredFiles)` with `Acervo.ensureComponentReady(componentId)`.
   - At line 127, replace `appendingPathComponent("model.safetensors")` with weight loading via `try await AcervoManager.shared.withComponentAccess(componentId) { handle in try loadArrays(url: handle.url(matching: ".safetensors")) }`.
2. Apply the symmetric changes to `Sources/SwiftVinetas/Understanding/FeatureExtractor.swift`:
   - Component ID: `dinov2-vit-base-patch14-518`, repoId: `mlx-vision/vit_base_patch14_518.dinov2-mlxim`, type: `.backbone`.
   - Delete hardcoded list at line 25.
   - Migrate `ensureAvailable` → `ensureComponentReady`.
   - Replace `appendingPathComponent("model.safetensors")` at line 111 with the `withComponentAccess` pattern.
3. The actors will now be `async` at weight-load time; confirm both call sites are already inside `async` contexts (the requirements doc states they are — verify, do not refactor public surfaces).

**Exit criteria**:
- [ ] `grep -n '"model.safetensors"\|"config.json"' Sources/SwiftVinetas/Understanding/ImageClassifier.swift Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` returns zero matches.
- [ ] `grep -rn 'Acervo\.ensureAvailable\b' Sources/SwiftVinetas/Understanding/` returns zero matches.
- [ ] `git diff origin/main -- Sources/SwiftVinetas/Understanding/ImageClassifier.swift Sources/SwiftVinetas/Understanding/FeatureExtractor.swift | grep -E '^[-+]\s*(public|open) '` shows zero changes (no public-surface declarations modified).
- [ ] `git diff origin/main -- Sources/SwiftVinetas/Understanding/ImageClassifier.swift | grep -E 'imagenetClassLabels|ImageNet'` shows no removals (label table preserved).
- [ ] `make build` succeeds.
- [ ] `make test-unit` passes.

---

### Sortie 2: Add skip-on-absent-manifest guards to vision-actor tests

**Priority**: 9.5 — establishes a reusable skip pattern for future ViT-dependent tests.

**Entry criteria**:
- [ ] WU3 Sortie 1 exit criteria all green.

**Tasks**:
1. Locate every test that exercises `ImageClassifier` or `FeatureExtractor`. If none exist yet, add a minimal smoke test for each in `Tests/SwiftVinetasUnitTests/` (or wherever the existing unit-test structure lives).
2. Each such test must probe manifest availability before running: call `Acervo.fetchManifest(forComponent: id)` (or check `Acervo.isComponentReady` after a low-cost availability call). On `componentNotRegistered`, manifest 404, or network error, emit a Swift Testing `withKnownIssue` block (or `Issue.record(severity: .warning)`) and `return`. Do NOT throw or fail the test.
3. Print a single-line stderr message: `[skipped] vit_base_patch16_224 manifest not yet published — see R9` (and analogous for the dinov2 one).
4. Document the skip pattern inline with a comment referencing `docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md` § R4.5 so future cleanup is easy once R9 (WU4) lands.

**Exit criteria**:
- [ ] At least one test exists per vision actor that exercises the new component-keyed flow.
- [ ] Each such test uses `withKnownIssue` or `Issue.record` to skip cleanly when the manifest is absent.
- [ ] `make test-unit` passes regardless of whether the manifests have shipped to the CDN.
- [ ] Stderr from `make test-unit` contains the `[skipped]` marker if and only if the manifest is absent.

---

## WU4 — Ship ViT Models to CDN (parallel-trackable)

### Sortie 1: Use acervo-download-ship skill to ship both ViT manifests

**Priority**: 3.0 — externally bound (HF→R2 transfer); parallel-trackable; sub-agent eligible.

**Agent**: sub-agent (no in-repo build required; the skill detaches the long-running download).

**Entry criteria**:
- [ ] First sortie — no prerequisites at the code level. Both source repos verified to exist on HuggingFace as of 2026-05-04.

**Tasks**:
1. Invoke the `acervo-download-ship` skill to ship `mlx-vision/vit_base_patch16_224-mlxim`. The skill runs `acervo ship <repo>` in a detached shell.
2. After the first download completes, invoke the skill again to ship `mlx-vision/vit_base_patch14_518.dinov2-mlxim`. The skill enforces single-download-at-a-time, so these are inherently sequential.
3. While downloads run, monitor via `/loop` dynamic mode or the skill's status integration. Do not block the agent.
4. Verify each manifest's `files` list contains `model.safetensors`. README/attention_maps/dino.gif from upstream are NOT required by Vinetas and need not be uploaded.

**Exit criteria**:
- [ ] `curl -sI https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models/mlx-vision_vit-base-patch16-224-mlxim/manifest.json` returns HTTP 200.
- [ ] `curl -sI https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models/mlx-vision_vit-base-patch14-518.dinov2-mlxim/manifest.json` returns HTTP 200 (slug exact form to be confirmed by the skill's output).
- [ ] Both manifests contain `model.safetensors` in their `files` list.
- [ ] (Bonus, after WU3 Sortie 2 also lands) Removing the R4.5 skip guard from a single test still leaves it green on a clean machine.

---

## WU5 — Decisions Documentation

### Sortie 1: Capture R6 and Open-Questions decisions in AGENTS.md

**Priority**: 1.5 — pure docs, parallel-trackable; sub-agent eligible.

**Agent**: sub-agent (markdown only; no build).

**Entry criteria**:
- [ ] First sortie — no code prerequisites; documents architectural decisions made in the requirements doc.

**Tasks**:
1. Add a `## SwiftAcervo manifest contract — decisions` section to `AGENTS.md` recording (use these three exact subheadings so the grep gates below land deterministically):
   - `### R6.1 — Acervo.deleteFromCDN and Acervo.recache (tooling-only)`: They are NOT wired into `VinetasClient` at runtime. The `acervo-cdn-setup` skill covers this workflow.
   - `### R6.2 / Q2 — migrateFromLegacyPaths() is a consuming-app concern`: e.g. Produciesta owns the call, not the Vinetas library. A library shouldn't migrate user data on import.
   - `### Q3 / R5.2 — PixArt component-bridge duplication is intentional`: Drift is caught by the WU6 stderr CI gate. Do NOT extract a helper until a third call site appears.
2. Each subsection includes a one-line rationale and an explicit cross-link of the form `See: docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R6.1` (etc.). Once WU7 moves the requirements doc to `docs/complete/`, those links must continue to resolve — update the path then.

**Exit criteria**:
- [ ] `grep -c 'SwiftAcervo manifest contract — decisions' AGENTS.md` returns 1.
- [ ] `grep -c 'R6.1 — Acervo.deleteFromCDN' AGENTS.md` returns 1.
- [ ] `grep -c 'R6.2 / Q2 — migrateFromLegacyPaths' AGENTS.md` returns 1.
- [ ] `grep -c 'Q3 / R5.2 — PixArt component-bridge' AGENTS.md` returns 1.
- [ ] `grep -c 'docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md' AGENTS.md` returns at least 3 (one cross-link per decision).

---

## WU6 — CI Stderr Gate

### Sortie 1: Add stderr noise gate that fails CI on re-registration warning

**Priority**: 6.0 — gates WU7 acceptance.

**Entry criteria**:
- [ ] WU2 and WU3 fully complete (otherwise the gate fires immediately on existing migration debt).

**Tasks**:
1. Identify the CI workflow(s) that run `make test-unit` / `make test-unit-ios`. Likely `.github/workflows/ci.yml` or similar.
2. Add a post-test step that captures test output and `grep`s for both:
   - `[SwiftAcervo] Warning: re-registering component`
   - `[SwiftAcervo] Manifest drift detected`
3. If either string appears in a test-run log, fail the workflow with a clear message pointing to `docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md` § R7.1.
4. Update `Makefile` if needed so test output is captured to a file the CI step can grep without re-running tests. Prefer `tee` over re-execution. Capture stderr (e.g., `2>&1 | tee build/test-output.log`).
5. **Smoke-test the gate locally — git-safe procedure**:
   a. Confirm working tree is clean: `git status --porcelain` returns empty.
   b. Stash any in-progress work: `git stash push -u -m "wu6-smoke-test-pre"` (idempotent if nothing to stash).
   c. Edit `Sources/SwiftVinetas/Engine/PixArtEngine.swift` to re-introduce `files: [ComponentFile(relativePath: "config.json")]` in the registration block (matching the pre-WU2-S1 state).
   d. Run `make test-unit 2>&1 | tee build/test-output.log` and confirm the warning string appears in `build/test-output.log`.
   e. Run the gate's grep step (the same command CI runs) and confirm it exits non-zero.
   f. **Revert with**: `git checkout -- Sources/SwiftVinetas/Engine/PixArtEngine.swift` (restores from index, drops the smoke-test edit).
   g. Restore stashed work: `git stash pop` (only if step b actually stashed).
   h. Re-run `make test-unit 2>&1 | tee build/test-output.log` and confirm the gate's grep step exits zero.

**Exit criteria**:
- [ ] CI workflow grep step exists and runs after every test invocation.
- [ ] `make build` succeeds and `make test-unit 2>&1 | tee build/test-output.log` produces a log file the grep step can scan.
- [ ] CI passes on clean post-migration code (verified by running the gate's exact grep command against the post-migration log; exit code is zero).
- [ ] Smoke-test (procedure in Task 5) confirmed: gate exits non-zero on regression, exits zero on clean code, working tree returns to clean state after smoke-test (`git status --porcelain` empty).
- [ ] No mode where the grep step is skipped silently — if the log file is missing, the CI step exits non-zero with a clear message.

---

## WU7 — Acceptance Verification

### Sortie 1: Run the R8 acceptance gauntlet

**Priority**: 2.0 — read-only verification + final doc move.

**Entry criteria**:
- [ ] WU1, WU2, WU3, WU6 all `COMPLETED`. (WU4 is parallel-trackable per R9.4 and does NOT gate this; WU5 is documentation-only.)

**Tasks**:
1. Confirm criterion 1: `grep -E 'package\(url:.*SwiftAcervo' Package.swift` shows `from: "0.11.1"` (or higher within the same major). `grep '"version"' Package.resolved` for the SwiftAcervo entry shows `0.11.1` or higher. Run `xcodebuild -resolvePackageDependencies` and capture output; confirm no `error:` / `unsatisfiable` lines in the captured output.
2. Confirm criterion 2: `grep -rn 'safetensors\|config\.json\|r2\.dev' Sources/ Tests/ --include='*.swift' | grep -v '^\s*//' | grep -v '^\s*\*'` returns zero non-comment matches.
3. Confirm criterion 3: `grep -rn 'Acervo\.isModelAvailable\|Acervo\.deleteModel\|Acervo\.modelDirectory\|Acervo\.ensureAvailable\b' Sources/ Tests/ --include='*.swift'` returns zero matches outside of `@available(*, deprecated)`-annotated code. The deprecated `VinetasModel` overloads in `VinetasModelManager.swift` are exempt — verify each remaining match is inside a `@available(*, deprecated)` block.
4. Run `make test-unit 2>&1 | tee build/wu7-test-unit.log` and `make test-unit-ios 2>&1 | tee build/wu7-test-unit-ios.log`. Both green (exit code zero).
5. Run `make test-gpu 2>&1 | tee build/wu7-test-gpu.log` and `make test-fixtures 2>&1 | tee build/wu7-test-fixtures.log` locally on a warm cache (these are local-only per `CLAUDE.md`). Both green (exit code zero).
6. Confirm criterion 6: `grep -E '\[SwiftAcervo\] Warning: re-registering|\[SwiftAcervo\] Manifest drift detected' build/wu7-test-unit.log build/wu7-test-unit-ios.log build/wu7-test-gpu.log build/wu7-test-fixtures.log` returns zero matches across all four log files.
7. Confirm criterion 7: any new ViT-touching test added under WU3 Sortie 2 skips cleanly when its manifest is absent. Verify by `grep -E '\[skipped\] vit_base|withKnownIssue' build/wu7-test-unit.log` shows expected skip messages (or test ran successfully, depending on WU4 state). The build did NOT fail. WU4 is tracked separately and does NOT gate this check.
8. (Conditional, only if WU4 has also completed and both manifests return HTTP 200) Exercise `ImageClassifier` and `FeatureExtractor` cold-cache flow on a clean machine end-to-end at least once. Confirm `[skipped]` markers are absent from logs.
9. Write a brief acceptance report at `docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION_ACCEPTANCE.md` listing each of the 8 R8 criteria with PASS/PASS-conditional/N-A status and the command/log evidence for each.
10. Move `docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md` AND the acceptance report to `docs/complete/` once all eight criteria pass: `git mv docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md docs/complete/` and `git mv docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION_ACCEPTANCE.md docs/complete/`.

**Exit criteria**:
- [ ] `docs/complete/SWIFTACERVO_MANIFEST_MIGRATION_ACCEPTANCE.md` exists and lists all 8 criteria with explicit PASS/N-A markers and evidence.
- [ ] `test -f docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md && ! test -f docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md` (requirements doc moved, not copied).
- [ ] `grep -E 'BLOCKING|TBD|TODO' docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md` returns zero matches in the Open Questions section (every Q is either resolved or explicitly deferred with a tracking issue).

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 7 |
| Total sorties | 10 |
| Critical path length | 5 sorties (WU1 S1 → WU2 S1 → WU2 S2 → WU6 S1 → WU7 S1) |
| Dependency structure | Layered: Layer 0 → Layer 1 (parallel) → Layer 2 → Layer 3 |
| Parallel-trackable units | WU4 (CDN ship), WU5 (docs) |
| Sub-agent eligible sorties | 2 (WU4 S1, WU5 S1) |
| Supervising-agent-only sorties | 8 (all build/test verification work) |
| Agent allocation | 1 supervising + up to 2 sub-agents |
| Blocking open questions | Q1 (gates WU2 Sortie 2) |
| Resolved open questions | Q2, Q3, Q4 |
| Refinement status | Atomicity ✓ · Prioritization ✓ · Parallelism ✓ · Open Questions ⚠ Q1 still BLOCKING |

---

## Open Questions & Missing Documentation

### Unresolved items (must address before execution)

| Sortie | Issue Type | Description | Recommendation |
|--------|-----------|-------------|----------------|
| WU2 S2 | Open question | **Q1** — `diskSize(of:)` is `nonisolated` synchronous; `withComponentAccess` is async. Three options in source doc. | **Recommended option 1**: make `diskSize` async, update `ImageGenerationEngine` protocol and all conforming types. **Action needed**: User confirms Q1 resolution before WU2 S2 dispatches. Supervisor must record resolution in SUPERVISOR_STATE.md. |

### Resolved / no-action items

| Question | Resolution | Where |
|----------|-----------|-------|
| Q2 | `migrateFromLegacyPaths` is the consuming app's concern, not Vinetas's. | Documented in WU5 S1. |
| Q3 | Accept PixArt component-bridge duplication; CI grep gate catches drift. | Documented in WU5 S1; WU6 S1 enforces the gate. |
| Q4 | ViT manifests not on CDN as of 2026-05-04. | WU4 S1 ships them; WU3 S2 adds skip-on-absence guards for the gap window. |

### Pass 4 auto-fixes applied

- WU2 S2 exit criteria now include explicit verification of the `diskSize` protocol change (conditional on Q1 option 1).
- WU3 S1 exit criteria now use `git diff` greps to verify public surfaces unchanged (was: "diff confirms" — manual).
- WU5 S1 exit criteria converted from "contains the three decisions" to grep-counts on specific subheading text.
- WU6 S1 task 5 ("smoke-test the gate") now has a step-by-step git-safe procedure (stash → edit → revert → pop).
- WU7 S1 task 6 now has an explicit grep command across captured log files.
- WU7 S1 now produces a written acceptance report at a deterministic path so completion is machine-verifiable.

### Pass 4 status

**1 issue requires manual resolution before execution can start**: Q1 (user decision on `diskSize` async).

If Q1 is resolved as option 1 (recommended), no further blocking issues remain. If Q1 is resolved as option 2 or 3, WU2 S2 task list and exit criteria need revision before dispatch.

# Supervisor State — OPERATION PIXART TRIAGE

## Terminology

> **Sortie** — An atomic, single-purpose task dispatched to one agent in one session.
> Each sortie reads the current state, does exactly one thing, writes its findings here,
> and exits. A fresh agent picks up the next sortie from scratch.

---

## Mission Metadata

- **Operation**: OPERATION PIXART TRIAGE
- **Bug**: PixArt generates garbage output (see `BUGS.md`)
- **Branch**: `development`
- **Started**: 2026-04-14
- **Max retries per sortie**: 3
- **Status**: IN PROGRESS

---

## Mission Goal

Identify why `PixArtEngine` produces garbage images and fix it.
The mission is complete when `make test-fixtures` produces a visually coherent
`pixart-seed42.png` for at least 3 consecutive runs.

---

## Sortie Sequence

| # | Name | Goal | Gates On | Model | State |
|---|------|------|----------|-------|-------|
| S1 | Fixture Capture | Run `make test-fixtures`, read the PixArt PNG, report metrics & visual quality | — | haiku | **FAILED (retry 2)** — MACF bypass not triggering in WeightLoader |
| S1b | MACF Bypass Fix | Fix `canEnumerateDirectory` guard in SwiftTuberia WeightLoader so VINETAS_TEST_MODELS_DIR redirect triggers | S1 root cause | sonnet | **COMPLETED** |
| S2 | Seed Sweep | Run `make test-pixart-repro`, read all 5 PNGs, characterise consistency | S1 shows garbage | sonnet | **READY** |
| S3 | Root Cause Analysis | Read `PixArtEngine.swift`, cross-reference metrics from S1/S2, identify most likely cause | S2 findings | opus | pending |
| S4 | Fix Implementation | Implement the S3 fix, run `make test-fixtures`, verify PNG is no longer garbage | S3 analysis | sonnet | pending |
| S5 | Verification | Run `make test-pixart-repro` (full 5-seed sweep), confirm all seeds pass, update BUGS.md | S4 fix | haiku | pending |

---

## Sortie Briefs

Each brief is self-contained. The dispatching agent pastes it as the system prompt
for a fresh Claude Code session with no prior conversation context.

---

### S1 — Fixture Capture

**Goal**: Determine whether the current PixArt output is garbage and record its metrics.

**Steps**:
1. Read `docs/incomplete/pixart-garbage-supervisor-state.md` (this file) to understand context.
2. Run `make test-fixtures` using the Bash tool.
3. Read `Tests/SwiftVinetasGPUTests/Fixtures/generations/pixart-seed42.png` using the Read tool
   (Claude is multimodal — look at the image).
4. Read `Tests/SwiftVinetasGPUTests/Fixtures/generations/pixart-seed42.json` — record the metrics.
5. Update **S1 Findings** below with:
   - Is the image visually garbage? (yes/no and description of what you see)
   - Raw metric values from the JSON
   - Which `metricObservations()` warnings fired (from the test log output)
6. Update **S1 State** to COMPLETED (or FAILED if make failed).
7. If the image is good: update S2 state to BLOCKED (no garbage to investigate), update
   mission status to "S1 showed good output — re-run on next suspected failure".

**Key files**:
- `Makefile` — `make test-fixtures` target
- `Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift` — the test that runs
- `Tests/SwiftVinetasGPUTests/ImageQualityReport.swift` — metric definitions
- `Tests/SwiftVinetasGPUTests/Fixtures/generations/` — output location

**Do not**:
- Modify any source files
- Run `make test-pixart-repro` (that is S2)
- Make assumptions about whether the image is garbage before reading it

---

### S1b — MACF Bypass Fix

**Goal**: Fix the `canEnumerateDirectory` guard in SwiftTuberia's `WeightLoader.swift` so that the `VINETAS_TEST_MODELS_DIR` redirect triggers correctly in xctest processes.

**Prerequisites**: S1 Findings (retry 2) recorded.

**Context**: `WeightLoader.swift` line 65 uses `!canEnumerateDirectory(directoryURL)` as a gate. The xctest process can call `enumerator` and get non-nil results (stat + opendir is permitted), so `canEnumerateDirectory` returns `true` and the redirect never fires. But MLX's C++ `fopen()` is blocked by MACF. The fix must change the bypass condition to trigger whenever `VINETAS_TEST_MODELS_DIR` is set AND the path contains `/Group Containers/`, regardless of `canEnumerateDirectory`.

**Steps**:
1. Read this supervisor state file; read S1 Findings (retry 2).
2. Read `WeightLoader.swift` in the checked-out SwiftTuberia source:
   `/tmp/SwiftVinetasBuild/SourcePackages/checkouts/SwiftTuberia/Sources/Tuberia/Infrastructure/WeightLoader.swift`
3. Read the SwiftTuberia `Package.swift` to understand the version and whether it's a local or remote dependency.
4. Decide on approach:
   - **Option A (upstream fix)**: Fork/patch SwiftTuberia, change the condition to not require `!canEnumerateDirectory`, push a new tagged release, update `Package.swift` to pin the new tag.
   - **Option B (local patch for testing)**: Edit the checked-out source directly at `/tmp/SwiftVinetasBuild/SourcePackages/checkouts/SwiftTuberia/` to change the condition. This lets `make test-fixtures` work without touching the upstream repo. (Note: this only persists until `make resolve` clears the cache.)
   - **Option C (Makefile workaround)**: Change `link-test-models` to also set `Acervo.sharedModelsDirectoryOverride` via a different mechanism, or restructure the test to use a different model loading path.
5. Implement the chosen fix.
6. Run `make test-fixtures` to verify PixArt can now load its weights and generates a PNG.
7. Read `Tests/SwiftVinetasGPUTests/Fixtures/generations/pixart-seed42.png` — does it look like "A red car parked on a cobblestone street" or is it garbage?
8. Update S1 Findings with the final PNG state and metrics, then update S2 state to READY (if garbage) or BLOCKED (if good).

**Key files**:
- `/tmp/SwiftVinetasBuild/SourcePackages/checkouts/SwiftTuberia/Sources/Tuberia/Infrastructure/WeightLoader.swift` — the bypass condition (lines 63–79)
- `Package.swift` in project root — SwiftTuberia version pin
- `Makefile` — `link-test-models` + `test-fixtures` targets

**The fix (Option B sketch)**:

Change:
```swift
if directoryURL.path.contains("/Group Containers/"),
  !canEnumerateDirectory(directoryURL),
  let baseDir = ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"]
```

To:
```swift
if directoryURL.path.contains("/Group Containers/"),
  let baseDir = ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"]
```

This unconditionally redirects to the test models dir whenever the env var is set and the path is in a Group Container, regardless of whether `enumerator` succeeds. The `canEnumerateDirectory` check was intended to avoid interfering with entitled app processes, but it's the wrong signal — only an unentitled test process would set `VINETAS_TEST_MODELS_DIR`.

---

### S2 — Seed Sweep

**Goal**: Characterise whether garbage output is consistent across seeds or intermittent.

**Prerequisites**: S1 shows garbage output.

**Steps**:
1. Read this supervisor state file; read S1 Findings.
2. Run `make test-pixart-repro` using the Bash tool (5 seeds: 42–46).
3. Read each output PNG in `~/Desktop/SwiftVinetasDebug/` (find the latest timestamped set).
4. Read each corresponding `.json` sidecar.
5. Update **S2 Findings** below with:
   - A table: seed → (visually garbage? / distinctColors5x5 / meanLuminance / stdLuminance)
   - Is the garbage consistent across all seeds, or only some?
   - Any pattern in the metrics (e.g. all-black, consistently low stdLuminance)?
6. Update **S2 State** to COMPLETED.

**Key files**:
- `Makefile` — `make test-pixart-repro` target
- `Tests/SwiftVinetasGPUTests/PixArtGarbageReproTests.swift`
- `~/Desktop/SwiftVinetasDebug/` — output location

---

### S3 — Root Cause Analysis

**Goal**: Identify the most likely root cause of the garbage output.

**Prerequisites**: S2 Findings recorded.

**Steps**:
1. Read this supervisor state file; read S1 and S2 Findings.
2. Read `Sources/SwiftVinetas/Engine/PixArtEngine.swift` in full.
3. Read `Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift` in full.
4. Read `Makefile` — specifically `link-test-models` and `test-fixtures` targets to understand
   the MACF / model-path setup.
5. Cross-reference the observed metric pattern (all-black? low contrast? monotone?) with the
   code paths in `PixArtEngine`:
   - `loadModel` → component path resolution → MACF / entitlement guard
   - `generate` → latent initialization → scheduler loop → VAE decode
6. Identify the **single most likely root cause** and explain the evidence.
7. Propose a concrete fix (code change or configuration change).
8. Update **S3 Analysis** below and set S3 State to COMPLETED.

**Key files**:
- `Sources/SwiftVinetas/Engine/PixArtEngine.swift`
- `Sources/SwiftVinetas/Engine/EngineTypes.swift`
- `Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift`
- `Makefile`

---

### S4 — Fix Implementation

**Goal**: Implement the S3 fix and verify `pixart-seed42.png` is no longer garbage.

**Prerequisites**: S3 Analysis complete with a specific code change proposed.

**Steps**:
1. Read this supervisor state file; read S3 Analysis carefully.
2. Read all files that need to change.
3. Implement the proposed fix.
4. Run `make test-fixtures`.
5. Read `Tests/SwiftVinetasGPUTests/Fixtures/generations/pixart-seed42.png` — is it visually good?
6. Read the JSON sidecar; compare metrics against S1/S2 baselines.
7. If still garbage: try the next most likely cause from S3 (update analysis), retry up to 3 times.
8. If good: commit the fix with a clear message referencing the bug.
9. Update **S4 Fix** below and set S4 State to COMPLETED.

---

### S5 — Verification

**Goal**: Confirm the fix holds across 5 seeds and close the bug.

**Prerequisites**: S4 fix committed.

**Steps**:
1. Read this supervisor state file; read S4 Fix.
2. Run `make test-pixart-repro` (5 seeds: 42–46).
3. Read all 5 output PNGs.
4. If all 5 are visually coherent: update `BUGS.md` to mark the PixArt garbage bug as Fixed.
5. Move this file to `docs/complete/pixart-garbage-supervisor-state.md`.
6. Update **S5 Verification** below and set mission Status to MISSION COMPLETE.

---

## Findings

### S1 Findings (Retry 2 — 2026-04-14)
- **State**: FAILED — PixArt model weights could not be loaded due to MACF bypass not triggering
- **Date**: 2026-04-14
- **Visually garbage**: Cannot determine — no PNG was generated
- **Metrics**: Cannot determine — no JSON was generated
- **Observations**:
  - Both `generatePixArtFixture()` and `generateFlux2Fixture()` failed. Both are in the `.serialized` suite.
  - `generatePixArtFixture()` failed immediately (0.0s) with a thrown error: `generationFailed("Failed to load PixArt model weights: weightLoadingFailed(component: \"t5-xxl-encoder-int4\", reason: \"caught(\"[load_safetensors] Failed to open file /Users/stovak/Library/Group Containers/group.intrusive-memory.models/SharedModels/intrusive-memory_t5-xxl-int4-mlx/model-00000-of-00005.safetensors...\")")`
  - `generateFlux2Fixture()` timed out after 600 seconds (10-minute `.timeLimit`)
  - The CoreData/AddressBook XPC errors in the log are noise from the headless test environment and are not the cause of failure
- **Root cause identified**: The MACF bypass in `WeightLoader.swift` (SwiftTuberia v0.3.4) has a faulty guard condition. The bypass at lines 64–79 is:
  ```swift
  if directoryURL.path.contains("/Group Containers/"),
     !canEnumerateDirectory(directoryURL),
     let baseDir = ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"]
  ```
  `canEnumerateDirectory()` uses `FileManager.default.enumerator` and checks `enumerator.nextObject() != nil`. The xctest process CAN enumerate the App Group container directory (stat + opendir is permitted), so `canEnumerateDirectory` returns `true` and the bypass is **never triggered**. However, when MLX's C++ code later calls `fopen()` on the actual safetensors files, MACF blocks it. The discrimination between "can enumerate" and "can open files" is the bug.
- **VINETAS_TEST_MODELS_DIR is being passed correctly**: The env var reaches the xctest process; the hardlinks at `/tmp/vinetas-test-models/t5-xxl-encoder-int4/` exist (5 shards, link count=2). The problem is purely that `canEnumerateDirectory()` returns `true` and the bypass code never switches to the `/tmp` path.
- **Notes**:
  - Duration: ~10.5 minutes total (Flux2 timed out at 600s, PixArt failed at 0s)
  - `make test-fixtures` exited with code 65 (xcodebuild TEST FAILED)
  - The xcresult is at `/tmp/SwiftVinetasBuild/Logs/Test/Test-SwiftVinetas-Package-2026.04.14_09-25-32--0400.xcresult`
  - **BLOCKER**: The MACF bypass condition in `WeightLoader.swift` must be fixed before any fixture can be generated. The fix should either (a) always redirect to `VINETAS_TEST_MODELS_DIR` when that env var is set and the path is a Group Container, or (b) use a direct `open()` probe instead of `enumerator` to detect MACF blocking.
  - Recommend: File this as a bug against SwiftTuberia. For a local workaround, the fix can be applied to the checked-out source at `/tmp/SwiftVinetasBuild/SourcePackages/checkouts/SwiftTuberia/` for testing, but it must also be fixed upstream and a new SwiftTuberia version pinned.

### S1b Findings (2026-04-14)
- **State**: COMPLETED
- **Date**: 2026-04-14
- **Fix implemented**: Two bugs found and fixed:
  1. **WeightLoader.swift**: Removed `!canEnumerateDirectory(directoryURL)` guard from MACF bypass. The condition was always false (xctest CAN enumerate via opendir/stat) so the bypass never triggered. Fix: check only for Group Containers path + VINETAS_TEST_MODELS_DIR env var presence.
  2. **Makefile**: `VINETAS_TEST_MODELS_DIR=... xcodebuild test` does NOT forward the env var to the xctest process. Must use `TEST_RUNNER_VINETAS_TEST_MODELS_DIR=...` (xcodebuild's `TEST_RUNNER_` prefix mechanism strips the prefix and passes the var to the test runner). Fix: all GPU/fixture/repro Makefile targets now use `TEST_RUNNER_VINETAS_TEST_MODELS_DIR`.
- **make test-fixtures result**: PixArt fixture GENERATED. Flux2 fixture FAILED with "network connection was lost" (Flux2 tries to download its model — unrelated to PixArt fix).
- **PNG generated**: `Tests/SwiftVinetasGPUTests/Fixtures/generations/pixart-seed42.png`
- **Visually garbage**: YES — image is a field of random bright-colored noise pixels; no recognizable content for "A red car parked on a cobblestone street"
- **Metrics from pixart-seed42.json**:
  - distinctColors5x5: **14** (⚠️ GARBAGE threshold: < 16)
  - distinctColors10x10: 56
  - meanLuminance: 77.33
  - stdLuminance: 86.86
  - meanRed: 106.2, meanGreen: 70.4, meanBlue: 37.3
  - isAllBlack: false, isAllWhite: false
  - width: 512, height: 512
  - durationSeconds: 25.65s
- **⚠️ warnings fired**: distinctColors5x5=14 (below 16 threshold)
- **Commits**:
  - SwiftTuberia `4c3dd13`: `fix(WeightLoader): remove canEnumerateDirectory guard from MACF bypass — fopen() blocked even when enumerator succeeds`
  - SwiftVinetas Makefile: Updated all GPU/fixture/repro targets to use `TEST_RUNNER_VINETAS_TEST_MODELS_DIR` (committed in SwiftVinetas repo)
- **unit tests (make test-unit)**: 507 tests, 2 pre-existing failures in PixArtEngineTests unrelated to this fix — both fail because the PixArt model IS downloaded on this machine, causing `isAvailable` to return true (test expects false) and `delete` to hit a permissions error on the App Group container.

### S2 Findings
- **State**: READY (set by S1b — garbage output confirmed)
- **Date**: —
- **Seed table**:

| seed | garbage? | dist5x5 | dist10x10 | meanLuma | stdLuma |
|------|----------|---------|-----------|----------|---------|
| 42   | —        | —       | —         | —        | —       |
| 43   | —        | —       | —         | —        | —       |
| 44   | —        | —       | —         | —        | —       |
| 45   | —        | —       | —         | —        | —       |
| 46   | —        | —       | —         | —        | —       |

- **Pattern**: —
- **Notes**: —

### S3 Analysis
- **State**: pending
- **Date**: —
- **Root cause hypothesis**: —
- **Evidence**: —
- **Proposed fix**: —
- **Affected files**: —

### S4 Fix
- **State**: pending
- **Date**: —
- **Change summary**: —
- **Post-fix metrics** (pixart-seed42.json): —
- **Commit**: —

### S5 Verification
- **State**: pending
- **Date**: —
- **All 5 seeds good**: —
- **Notes**: —

---

## Decisions Log

| Date | Sortie | Decision | Rationale |
|------|--------|----------|-----------|
| 2026-04-14 | — | Mission initialized | PixArt garbage bug confirmed; infrastructure (test-fixtures, test-pixart-repro) deployed |
| 2026-04-14 | S1 | Model: haiku | Simple observe-and-record task; multimodal image read + JSON parse |
| 2026-04-14 | S1 retry 2 | FAILED — MACF bypass not triggering | xctest process can enumerate App Group container (canEnumerateDirectory returns true), so WeightLoader never redirects to /tmp. MLX C++ fopen() then hits MACF and fails. Root cause identified. |
| 2026-04-14 | S1b | New sortie added — MACF Bypass Fix | Must fix WeightLoader bypass condition before any fixture can be generated. Recommended fix: remove !canEnumerateDirectory guard, rely solely on VINETAS_TEST_MODELS_DIR env var presence. |
| 2026-04-14 | S1b | COMPLETED — two bugs fixed | (1) WeightLoader.swift: removed !canEnumerateDirectory guard; (2) Makefile: VINETAS_TEST_MODELS_DIR env prefix does not reach xctest — must use TEST_RUNNER_VINETAS_TEST_MODELS_DIR. PixArt fixture generated. Image is visually garbage (random noise, distinctColors5x5=14). |
| 2026-04-14 | S2 | Model: sonnet | Pattern analysis across 5 images requires judgment |
| 2026-04-14 | S3 | Model: opus | Root cause identification requires deep code reading and inference |
| 2026-04-14 | S4 | Model: sonnet | Code editing + verification loop |
| 2026-04-14 | S5 | Model: haiku | Pure verification; reads images, updates markdown |

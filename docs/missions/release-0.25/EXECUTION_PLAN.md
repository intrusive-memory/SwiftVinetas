---
type: execution-plan
feature_name: OPERATION CLOUD CEILING
starting_point_commit: 92e3d998d1271f855a5ab68f26a5ed6443af8c27
mission_branch: mission/cloud-ceiling/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVinetas next minor release: readiness

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Scope of this run

Source: `docs/missions/release-0.25/REQUIREMENTS.md` (recon: `RECON_REPORT.md`, fourth pass, CLEAR).

In scope: precondition 6 (cloud requests not clamped to the local GPU limit), precondition 2
(version strings and stale versions in `README.md` / `AGENTS.md`), precondition 4 (make
targets pass on `development`).

**Out of scope for this run (the user approves the release):** `/ship-swift-library`, the
flip to remote-only dependencies (`/toggle-sibling-libraries`), the PR into `main` (draft
PR #79), tagging, the GitHub release, `/branch-hygiene`, `/update-package-library`.

Repository rules that bind every sortie: public repo — add no private app/podcast names to
code, tests, docs or commit messages (existing ones stay; separate mission). Never
`swift build` / `swift test`; use `make`. Never push to `main`, never force-push. Commits end
with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `development` requires a PR
with `Unit Tests (macOS)`.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| CloudClampFix | `/Users/stovak/Projects/package-collection/pkg/SwiftVinetas` | 2 | 1 | none |
| ReleasePrep | `/Users/stovak/Projects/package-collection/pkg/SwiftVinetas` | 2 | 2 | CloudClampFix |

## CloudClampFix

### Sortie 1: Skip the GPU resolution clamp for cloud models, with a test

**Priority**: 13.5 — blocks 3 sorties (depth 3 ×3 = 9), local-GPU vs cloud rule reused at 5 sites (foundation 2), behaviour change (risk 2), complexity 1.

**Entry criteria**:
- [ ] Working tree on the mission branch, branched from `origin/development` (`92e3d99` or later).
- [ ] RECON A-10, A-11, A-13 CONFIRMED: `buildRequest` (`Sources/SwiftVinetas/Vinetas.swift:1133–1154`) clamps unconditionally at `:1143`; callers at `:513`, `:632`, `:680`, `:753`; separate telemetry clamp at `:331`; `model` (an `any ModelDescriptor`) is in scope at all five sites.

**Tasks**:
1. In `Sources/SwiftVinetas/Vinetas.swift`, add a `model: any ModelDescriptor` parameter to `buildRequest`, and apply `ResolutionClamp.clampedDimensions` only when `!(model is CloudModelDescriptor)`; otherwise pass `style.width` / `style.height` through. Keep the existing defense-in-depth comment, extended with one sentence on why cloud is exempt.
2. Pass `model` at all four `buildRequest` call sites (`:513`, `:632`, `:680`, `:753`).
3. Apply the same rule to the telemetry clamp at `:331` (factor a single private helper used by both places so the rule lives in one spot).
4. Add a test to `Tests/SwiftVinetasTests/CharacterPanelTests.swift` or `PanelRequestTests.swift`: `VinetasClient.prepare` with a `CloudImageEngine(provider:keyStore: InMemoryAPIKeyStore())` and a `CloudModelDescriptor` at an explicit 8192×8192 `StyleConfig` yields `prepared.request.width == 8192`, `prepared.request.height == 8192` and `prepared.bundle.width/height == 8192`. No network, no key.
5. `make lint`, commit (`fix(cloud): don't clamp cloud requests to the local GPU buffer limit`).

**Exit criteria**:
- [ ] `grep -n "ResolutionClamp.clampedDimensions" Sources/SwiftVinetas/Vinetas.swift` returns exactly one line, inside the new helper.
- [ ] `grep -c "buildRequest(" Sources/SwiftVinetas/Vinetas.swift` = 5 and every call passes `model:`.
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0 and `build/test-output.log` shows the new test passed and `PanelRequestTests` "the engine receives the clamped effective size" passed.
- [ ] `make lint-check` exits 0 after commit.
- [ ] `git diff --stat origin/development..HEAD` touches only `Sources/SwiftVinetas/Vinetas.swift` and one test file.

**Task type**: code — **SUPERVISING AGENT ONLY** (build + test).

### Sortie 2: PR the fix into `development`, merge on green

**Priority**: 10 — blocks 2 sorties (6), external CI (risk 3), complexity 1.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED; mission branch pushed to `origin`.

**Tasks**:
1. Open a PR mission branch → `development` (title `fix(cloud): don't clamp cloud requests to the local GPU buffer limit`), body: Summary, cause, the four call sites + `:331`, Test plan; ends with the Claude Code attribution line. Not a draft (CI skips drafts).
2. Wait for checks (deferred, poll interval 60 s).
3. Merge (merge commit, matching repo history) once `Unit Tests (macOS)` **and** `Unit Tests (iOS)` are `success`. `Unit Tests (iOS)` is not a required check on `development`, so it is checked by hand (RECON W-3).

**Exit criteria**:
- [ ] `gh pr checks <N>` shows `Unit Tests (macOS)` = pass and `Unit Tests (iOS)` = pass (the iOS log no longer fails `CloudCLITests.dryRunPrintsResolvedRequest`).
- [ ] `gh pr view <N> --json state -q .state` = `MERGED`.

**Task type**: deferred — **SUPERVISING AGENT ONLY**.

## ReleasePrep

### Sortie 3: Version strings and stale versions in README.md / AGENTS.md

**Priority**: 4.5 — blocks 1 sortie (3), docs/config (risk 1), complexity 0.5.

**Entry criteria**:
- [ ] Sortie 2 COMPLETED; new branch `chore/release-0.25.0-prep` from updated `origin/development`.
- [ ] RECON A-02, A-03 CONFIRMED (line numbers below).
- [ ] Next minor release version = latest semver tag (`v0.24.0`, per `gh release view`) + minor = `0.25.0`; re-derive at dispatch with `git tag --sort=-v:refname | head -1`.

**Tasks**:
1. `Sources/SwiftVinetas/Vinetas.swift:48` and `:1277`: `"0.24.0-dev"` → the next minor version.
2. `AGENTS.md:8` `**Version**:` → the next minor version.
3. `AGENTS.md:143`, `:145`, `:147` dependency rows → the `Package.swift` floors (SwiftTubería `0.9.0`, SwiftAcervo `0.25.0`, SwiftCompartido `7.3.1`); rows `:142`, `:144`, `:146` already match.
4. `README.md:54` `from: "0.24.0"` → the next minor version; add a `**v<next minor>**` entry at the top of `README.md` `## Status` (line ~256) summarizing REQUIREMENTS.md § "What is being released" plus the cloud-clamp fix, with no private names.
5. Commit the mission artifacts under `docs/missions/release-0.25/` (allowed by precondition 1) in a separate `docs:` commit.

**Exit criteria**:
- [ ] `grep -rn "0\.24\.0-dev" Sources AGENTS.md README.md` returns nothing.
- [ ] `grep -n 'version = "' Sources/SwiftVinetas/Vinetas.swift` shows the next minor version twice.
- [ ] `AGENTS.md` rows for SwiftTubería / SwiftAcervo / SwiftCompartido equal `Package.swift` `from:` values (`grep -n 'from: "' Package.swift`).
- [ ] `README.md` `## Status` first entry is `**v<next minor>**`.
- [ ] `git diff origin/development..HEAD -- README.md AGENTS.md Sources | grep '^+' | grep -Eic 'escribir|produciesta|granville|vinetas app'` = 0.
- [ ] [judgment] The new README Status entry names every bullet of REQUIREMENTS.md § "What is being released" (OpenAI/Gemini reference images, `maxReferenceImages`, `PromptBundle`, `PanelRequest.character` / `prepare` / `PreparedPanel`, CLI `--character` / `--dry-run` / `list --json`) and the cloud-clamp fix, in the style of the v0.24.0 entry.
- [ ] `git diff --stat origin/development..HEAD` touches only `Sources/SwiftVinetas/Vinetas.swift`, `AGENTS.md`, `README.md`, `docs/missions/release-0.25/*`.

**Task type**: code — sub-agent eligible (no build), but folded into Sortie 4's builds.

### Sortie 4: Verify make targets on the release-prep branch; PR into `development`, merge on green

**Priority**: 3.5 — leaf; external CI (risk 3), complexity 0.5.

**Entry criteria**:
- [ ] Sortie 3 COMPLETED.

**Tasks**:
1. Run `make build`, `make build-ios`, `make test-unit`, `make test-unit-ios`, then (after commit) `make lint-check`.
2. Push; open a PR `chore/release-0.25.0-prep` → `development`; merge once `Unit Tests (macOS)` and `Unit Tests (iOS)` pass.

**Exit criteria**:
- [ ] `make build`, `make build-ios`, `make test-unit`, `make test-unit-ios`, `make lint-check` each exit 0 (precondition 4).
- [ ] PR checks `Unit Tests (macOS)` and `Unit Tests (iOS)` = pass; PR state `MERGED`.
- [ ] `origin/development` reports the next minor version at `Vinetas.swift:48`; draft PR #79 untouched; no tags created (`git ls-remote --tags origin | grep -c v0.25` = 0).

**Task type**: command + deferred — **SUPERVISING AGENT ONLY**.

## Parallelism Structure

**Critical Path**: Sortie 1 → Sortie 2 → Sortie 3 → Sortie 4 (length: 4 sorties).

**Parallel Execution Groups**: none. Every sortie depends on the previous one (Sortie 3 branches from the `development` that Sortie 2 merges), and Sorties 1, 2, 4 build, test or wait on CI.

**Agent Constraints**:
- **Supervising agent**: Sorties 1, 2, 4 (builds, tests, CI waits) and Sortie 3 (too small to justify a dispatch; turn estimate < 15% of budget).
- **Sub-agents**: one independent `[judgment]` verifier for Sortie 3 (§3f), no builds.

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

All six `intrusive-memory` deps are SIBLING_ACTIVE locally (resolve to `../<Name>`); CI resolves the remote floors. Drift was judged harmless (RECON § Drift); CI is the arbiter.

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| intrusive-memory/flux-2-swift-mlx | floor 3.4.3 (= latest release) | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | floor 0.25.0 (= latest) | `~/Projects/package-collection/pkg/SwiftAcervo` | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | floor 0.9.0 (= latest) | `~/Projects/package-collection/pkg/SwiftTuberia` | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | floor 0.8.2 (= latest) | `~/Projects/package-collection/pkg/pixart-swift-mlx` | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/glosa-av | floor 0.8.1 (= latest) | `~/Projects/package-collection/pkg/glosa-av` | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftCompartido | floor 7.3.1 (= latest) | `~/Projects/package-collection/pkg/SwiftCompartido` | SIBLING_ACTIVE, LOCAL_AHEAD |
| universal, swift-argument-parser, swift-tokenizers, swift-certificates, swift-crypto, swift-asn1 | remote | — | NO_LOCAL_CHECKOUT |

## Refinement Log

| Pass | Result |
|------|--------|
| 1. Blocking open questions | None. |
| 2. Atomicity & testability | 4 sorties, all within budget (est. turns: S1 ≈ 20, S2 ≈ 8, S3 ≈ 12, S4 ≈ 12). S3 undersized but kept separate: different branch and PR from S1/S2. No splits/merges. |
| 3. Priority | Order unchanged (strict dependency chain). Scores added. |
| 4. Parallelism | Sequential; all supervising-agent; one verifier sub-agent. |
| 5. Vague criteria | S3 "summarizing" README entry → `[judgment]` criterion with named contents; private-name check made a concrete grep. S1 "new test passed" — the test name is fixed by the implementer and recorded in SUPERVISOR_STATE.md. |

## Open Questions

_No blocking open questions identified during breakdown._

Decisions taken from the requirements and repo conventions (not blockers):
- The fix keys on `model is CloudModelDescriptor` (REQUIREMENTS precondition 6, explicit).
- The release-prep version bump lands on `development` via its own PR and is merged on green; this publishes nothing. `/ship-swift-library` later finds the version already set.

## Summary

| Metric | Value |
|--------|-------|
| Work units | 2 |
| Total sorties | 4 |
| Open questions | 0 |
| Dependencies mapped | 12 |
| Dependency structure | layers (CloudClampFix → ReleasePrep) |

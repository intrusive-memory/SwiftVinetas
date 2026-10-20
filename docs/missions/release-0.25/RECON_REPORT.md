---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 0963d5d559c1ab24282baeba842180974ce565d4c53b1a08396b0c6db60ce68c
project_head: 92e3d99
search_root: ~/Projects/package-collection/pkg
generated: 2026-10-20
verdict: CLEAR
---

# RECON_REPORT.md — SwiftVinetas 0.25.0 release (fourth recon)

## Fourth recon delta (2026-10-20, HEAD `92e3d99`)

Re-run because the requirements changed after the third recon (committed in `63d8664`, merged as PR #82). The hub re-verified only what moved:

- **A-01 (CONFIRMED)**: `git log origin/main..origin/development` now also lists `63d8664` and `92e3d99`; `git diff --stat e06c2a0 HEAD` = 4 files, all under `docs/missions/`. Precondition 1 now allows these.
- **A-13 (CONFIRMED, W-1 resolved)**: the requirements now key on `model is CloudModelDescriptor`. `model` is in scope at all four `buildRequest` callers (`Vinetas.swift:513` via `prepare(_:on:characters:)` `let model = request.model` at `:463`; `:632`, `:680`, `:753` inside functions taking `model`) and at the `:331` clamp (`let model = request.model`, `:287`). `buildRequest` itself (`:1133–1154`) takes no model, so the fix adds a parameter. Line numbers `:331`, `:513`, `:632`, `:680`, `:753`, `:1143` unchanged (`grep -n`).
- **A-14 (CONFIRMED, W-2 resolved)**: the requirements now ask for a new cloud test and leave `PanelRequestTests.swift:117–125` as is.
- **A-02/A-03/A-04 re-checked**: `Vinetas.swift:48`, `:1277`, `AGENTS.md:8`, `:143`, `:145`, `:147`, `README.md:54` unchanged; `gh release view` latest still equals each floor. `Package.swift` unchanged since the third recon.
- Verdict unchanged: **CLEAR**. A-07 remains UNVERIFIABLE (make targets).
- Note: `README.md` `## Status` (line 256) and `AGENTS.md` `## Recent Changes` (line 289, last entry v0.20.1) carry per-version notes; neither has a 0.25.0 entry yet.


## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Method and scope notes

- Third recon. It replaces the second, which was BLOCKED only on precondition 1's commit list. The requirements now allow docs-only `docs/missions/` commits (precondition 1), name the stale `AGENTS.md` dependency rows (precondition 2), and require a fix for the iOS cloud-resolution clamp before release (precondition 6, Non-goals).
- `development` HEAD is still `d3afaf8`, the same commit the second recon audited. Findings about repository content at that commit (private-name counts, released API surface) are re-cited from that audit and spot-checked, not re-derived from scratch.
- The hub did all the verification itself. No spokes were dispatched; the claims are small git, grep and `gh` checks. Every verdict cites a file:line or command output.
- **Network use (deliberate exception to recon's offline rule), all read-only:** `gh release view` for the six sibling dependencies and SwiftVinetas; `gh api` GETs for branch protection on `main` and `development`, check runs on `ae0cd66`, `adb115a`, `18acd83`, `d3afaf8`, and the open-PR list. Nothing was written remotely.
- No builds, tests, package resolution, commits or pushes. The only file written is this report. The uncommitted edits to `REQUIREMENTS.md` (expected) and to `docs/missions/storyboard-shots/` were left alone.
- Private and non-public project names are never quoted here; matches are reported as counts only.

## Verdict

**CLEAR** — 17 assumptions checked: 16 confirmed, 0 blocking, 1 unverifiable (the make targets passing, which recon cannot run). Four non-blocking warnings: two on precondition 6's wording (W-1, W-2), one on the existing draft PR (W-3), and one on frontmatter (W-4).

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-INVARIANT | `development` is ahead of `main` by `95b5e87`, `d7246ba`, `ae0cd66`, `e06c2a0`, then docs-only `docs/missions/` commits (`18acd83`, `d3afaf8`); no other code (REQUIREMENTS.md:29–31) | repo | CONFIRMED | `git log --oneline main..development` = exactly those 6. `development..main` is empty. `main` = `origin/main` = `07929ac`; `development` = `origin/development` = `d3afaf8`. `git diff --stat e06c2a0 d3afaf8`: 4 files, all under `docs/missions/`, +464 lines, no Sources/Tests/Package changes |
| A-02 | A-FILE | `Vinetas.swift:48` and `:1277` read `0.24.0-dev`; 0.24.0 is released (REQUIREMENTS.md:32–33) | repo | CONFIRMED | `Sources/SwiftVinetas/Vinetas.swift:48`, `:1277` = `"0.24.0-dev"`. `gh release view` latest = `v0.24.0`. `AGENTS.md:8` = `**Version**: 0.24.0-dev`; `README.md:54` = `from: "0.24.0"` |
| A-03 | A-FILE | `AGENTS.md` dependency rows list SwiftTubería 0.7.9, SwiftAcervo 0.24.1, SwiftCompartido 7.2.5, older than the `Package.swift` floors (REQUIREMENTS.md:34–36) | repo | CONFIRMED | `AGENTS.md:143` SwiftTubería `0.7.9` vs `Package.swift:117` `0.9.0`; `AGENTS.md:145` SwiftAcervo `0.24.1` vs `Package.swift:108` `0.25.0`; `AGENTS.md:147` SwiftCompartido `7.2.5` vs `Package.swift:142` `7.3.1`. The other three rows match (`:142` 3.4.3, `:144` 0.8.2, `:146` 0.8.1) |
| A-04 | A-DEP | Every `sibling(...)` dep has a published release at or above its floor (REQUIREMENTS.md:37–38) | dep:* (6) | CONFIRMED | Floors `Package.swift:97,108,117,126,133,142`. `gh release view` latest: flux-2-swift-mlx `v3.4.3`, SwiftAcervo `v0.25.0`, SwiftTuberia `v0.9.0`, pixart-swift-mlx `v0.8.2`, glosa-av `v0.8.1`, SwiftCompartido `v7.3.1`; all `draft=false pre=false`, each equal to its floor |
| A-05 | A-CONFIG | No `siblingBranch(...)` / branch pin in use (REQUIREMENTS.md:38–39) | repo | CONFIRMED | Branch overload is defined at `Package.swift:35`, but all six call sites (`Package.swift:94–142`) pass `from:` |
| A-06 | A-CONFIG | Makefile targets `test-unit`, `build`, `build-ios`, `lint-check` exist (REQUIREMENTS.md:40) | repo | CONFIRMED | `Makefile:147`, `:104`, `:114`, `:331`. The iOS job's target `test-unit-ios` is at `Makefile:273` |
| A-07 | A-BEHAVIOR | Those four targets pass on `development` (REQUIREMENTS.md:40–41) | repo | UNVERIFIABLE | Recon does not build. CI: `18acd83` (PR #81 head) `Unit Tests (macOS)` = success, `PixArt Integration (macOS)` = success. `d3afaf8` (merge) checks all `skipped` |
| A-08 | A-CONFIG | `main` protection requires `Unit Tests (macOS)` and `PixArt Integration (macOS)` (REQUIREMENTS.md:42–43) | external (GitHub) | CONFIRMED | `gh api .../branches/main/protection` → `["Unit Tests (macOS)","PixArt Integration (macOS)"]`. `development` → `["Unit Tests (macOS)"]` |
| A-09 | A-BEHAVIOR | `Unit Tests (iOS)` fails one test, `CloudCLITests.dryRunPrintsResolvedRequest()`, at `:597` and `:603`, expected 1344×768, got 720×400 (REQUIREMENTS.md:44–46) | repo + external | CONFIRMED | Test at `Tests/SwiftVinetasTests/CLITests/CloudCLITests.swift:570`; `:597` expects `Frame: 1344×768 pixels…`, `:603` expects `bundle["width"] == 1344`. It passes `--width 1344 --height 768` explicitly (`:584`), so `AspectRatio`'s own clamp is not involved. Check runs: `ae0cd66` and `18acd83` `Unit Tests (iOS)` = failure; `adb115a` (0.24.0 bump) = success. The 720 value and the single-failing-test result come from the job logs read in the second recon (jobs `118637685183`, `118713898885`); not re-fetched |
| A-10 | A-BEHAVIOR | `buildRequest` (`Vinetas.swift:1143`) clamps every request to the local GPU limit, including cloud-routed ones (REQUIREMENTS.md:47–49) | repo | CONFIRMED | `Vinetas.swift:1133–1154`: `buildRequest(prompt:style:mode:)` takes no engine or model and unconditionally calls `ResolutionClamp.clampedDimensions` at `:1143`. Four callers: `:513` (`prepare`), `:632`, `:680` (`generateSequence`), `:753` (`generate(prompt:character:…)`) |
| A-11 | A-BEHAVIOR | The clamp is derived from the local GPU's buffer limit (`ResolutionClamp.swift:69–76`) | repo | CONFIRMED | `Sources/VinetasVocabulary/ResolutionClamp.swift:69–76`: `maxBufferLengthBytes` = `MTLCreateSystemDefaultDevice().maxBufferLength`, fallback 16 GB; default argument of `clampedDimensions` (`:104–108`) |
| A-12 | A-INVARIANT | The clamp predates PR #80; PR #80's test is the first to assert the size (REQUIREMENTS.md:50) | repo | CONFIRMED | At `07929ac` (`main`, pre-PR #80) `buildRequest` already clamps (`git show 07929ac:…/Vinetas.swift`, clamp at line 1012, 5 `buildRequest(` occurrences). `ResolutionClamp.swift` last changed in `3521f0a` (v0.22.0); 0-line diff `07929ac..HEAD`. `CloudEngineTests.swift:948` also asserts `Frame: 1344×768`, but it calls `engine.generate` directly with a hand-built request, so it never goes through `buildRequest` and is unaffected |
| A-13 | A-API | The routed engine is known where the clamp is applied, so the clamp can be skipped for a `CloudImageEngine` (REQUIREMENTS.md:52–53) | repo | CONFIRMED (qualified; see W-1) | `CloudImageEngine` is `public actor` (`Cloud/CloudImageEngine.swift:15`), and `engine is CloudImageEngine` is already used at `Vinetas.swift:492`. **Not inside `buildRequest`** (no engine parameter). At the call sites: `:513` has the engine (`prepare(_:on:characters:)`, `:458–460`). This is the failing test's path (CLI `--dry-run` → `client.prepare`, `VinetasCLICore.swift:320` → `:454–455`) and the main `generate(_ PanelRequest)` path (`:362`). `:680` has the engine (`:656–661`). `:632` runs before routing unless references are supplied (`:619–625`). `:753` builds the request **before** routing (`:780`) and sends it to the engine. The `model` descriptor is in scope at all four sites (`CloudModelDescriptor.engineID` = `provider.engineID`, `CloudModelDescriptor.swift:44`) |
| A-14 | A-INVARIANT | Local-engine size assertions exist that are not host-agnostic (implied by REQUIREMENTS.md:53–54) | repo | CONFIRMED (already satisfied; see W-2) | The only test that checks a size `buildRequest` produced for an on-device engine is `PanelRequestTests.swift:117–125` (`MockEngine`). It already expects `ResolutionClamp.clampedDimensions(width: 8192, height: 8192)` (`:120`), so it is host-agnostic. The other literal-size asserts (`RequestTranslationTests`, `GenerationRequestTests`, `PromptFileTests`, `StoryboardPlanTests`, `ReferenceImageTests`, `TrainingDataTests`) test config parsing or image resizing, not `buildRequest` |
| A-15 | A-INVARIANT | PR #80 adds no private app or podcast names (REQUIREMENTS.md:55–56) | repo | CONFIRMED | Second-recon scan at the same commits: added lines in `git diff 07929ac e06c2a0` matching the private-name pattern list = **0**; PR #81 (`e06c2a0..d3afaf8`) = **0**. HEAD unchanged since |
| A-16 | A-DATA | The repo already holds ~200 lines in ~45 tracked files with private names, public since earlier tags (REQUIREMENTS.md:73–75) | repo | CONFIRMED | Second-recon `git grep` at `d3afaf8`, excluding `graphify-out/`: 205 lines in 45 files; also 205 at `v0.24.0`. HEAD unchanged since |
| A-17 | A-API | Released surface exists: `CloudModelDescriptor.maxReferenceImages`, `PromptBundle`, `PanelRequest.character`, `VinetasClient.prepare(_:characters:)`, `PreparedPanel`, OpenAI edits, 1536 px re-encode, Gemini 10/6, CLI `--character`/`--dry-run`/`list` `maxReferenceImages`, CLI_REFERENCE (REQUIREMENTS.md:16–25) | repo | CONFIRMED | Spot-checked: `Cloud/CloudModelDescriptor.swift:42` (`maxReferenceImages`), `Cloud/CloudHTTP.swift:187` (`referenceMaxEdge = 1536`), `Core/PromptBundle.swift:17`, `Vinetas.swift:450` (`prepare(_:characters:)`), `VinetasCLICore.swift:155` (`dryRun`), `:319–320`. Full cite list in the second recon (same HEAD) |

No blocking findings.

## Warnings (non-blocking; fix the requirements wording or carry into the sortie)

### W-1 — Precondition 6 names one call site; the clamp is reached from four, plus a telemetry clamp

"Skip `ResolutionClamp` when the routed engine is a `CloudImageEngine`" cannot be done inside `buildRequest` as it stands, because it has no engine. A fix that only touches `prepare` (`Vinetas.swift:513`) turns the failing test green and covers the main `generate(_ PanelRequest)` path. It leaves cloud requests clamped on:

- `generate(prompt:character:style:model:)`: the request is built at `:753`, before routing at `:780`, and that request is what the engine receives.
- `generateSequence`: the loop at `:680` has the engine. The telemetry-only `firstRequest` at `:632` is built before routing.
- The separate telemetry clamp at `Vinetas.swift:331` (`generationStart` width/height), outside `buildRequest`.

**Recommendation**: amend precondition 6 to say "pass the engine (or key on `model is CloudModelDescriptor`, which is known before routing) into `buildRequest` and skip the clamp for cloud at every call site, including the `:331` telemetry clamp". Add an exit criterion that `grep -n "ResolutionClamp.clampedDimensions" Sources/SwiftVinetas/Vinetas.swift` shows no unconditional use. Keying on the descriptor is the smaller change: it needs no reordering at `:753` or `:632`.

### W-2 — "Make the local-engine size assertions host-agnostic" is already true

`PanelRequestTests.swift:117–125` already derives its expectation from `ResolutionClamp`. No local-engine assertion needs to change. The test work the fix really needs is a **new** cloud-path assertion: a cloud request must keep its explicit size (e.g. 8192×8192 through `prepare` with a `CloudImageEngine` must stay unclamped). Without it nothing on macOS catches a regression, because macOS's clamp is a no-op at 1344×768. **Recommendation**: reword the clause to "keep `PanelRequestTests.effectiveSizeIsClamped` as is; add a cloud-engine test that asserts an oversized explicit size is not clamped".

### W-3 — Open draft PR #79 (`development` → `main`) already exists

`gh api .../pulls?state=open` → `#79 development->main draft=true`. The ship flow should reuse it (the `create-pull-request` skill finalizes an existing draft) rather than open a second one. Also, precondition 6's fix PR targets `development`. Because `development` requires only `Unit Tests (macOS)`, the iOS job will not block that PR's merge, so check it by hand before merging.

### W-4 — Requirements frontmatter is `type: project`

`breakdown` stamps `type: requirements`.

## Local Dependency Map

All six intrusive-memory deps use the `sibling(...)` helper, and every `../<Name>` exists. So **local builds resolve all six to local paths (SIBLING_ACTIVE)**, while CI resolves the remote floors. `Package.resolved` exists locally and is untracked (`git ls-files Package.resolved` → empty).

| Dependency | Floor | Latest release | Local checkout (`~/Projects/package-collection/pkg/…`) | Local HEAD | Ahead of tag | Status |
|---|---|---|---|---|---|---|
| flux-2-swift-mlx | 3.4.3 | v3.4.3 | `flux-2-swift-mlx` | `9a36b26` development, clean | 1 | SIBLING_ACTIVE, LOCAL_AHEAD |
| SwiftAcervo | 0.25.0 | v0.25.0 | `SwiftAcervo` | `13e2879` development, 1 untracked | 4 | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| SwiftTuberia | 0.9.0 | v0.9.0 | `SwiftTuberia` | `d74977a` development, 2 untracked | 1 | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| pixart-swift-mlx | 0.8.2 | v0.8.2 | `pixart-swift-mlx` | `3ce2541` development, clean | 1 | SIBLING_ACTIVE, LOCAL_AHEAD |
| glosa-av | 0.8.1 | v0.8.1 | `glosa-av` | `eed3dc9` development, 2 dirty | 3 | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| SwiftCompartido | 7.3.1 | v7.3.1 | `SwiftCompartido` | `af5a734` development, clean | 1 | SIBLING_ACTIVE, LOCAL_AHEAD |
| universal, swift-argument-parser, swift-tokenizers, swift-certificates, swift-crypto, swift-asn1 | remote only | — | — | — | — | NO_LOCAL_CHECKOUT |

### Drift and ambiguity notes

- Every checkout's HEAD, ahead-count and dirty state is unchanged since the second recon. The second recon found the commits ahead of each tag to be version strings or docs, except glosa-av's `Shot.ref` / `Shot.character`. SwiftVinetas `Sources/VinetasCLICore/Storyboard/` does not reference those (no `git grep` hits). Drift is harmless for this release. Still, build the precondition 6 fix with `make` the way CI does, or confirm it on CI: locally the siblings resolve to these checkouts.
- No AMBIGUOUS checkouts: each remote maps to one checkout under the search root.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-07 | `make test-unit`, `build`, `build-ios`, `lint-check` pass on `development` | Recon does not build | Run them after the precondition 6 fix lands, plus `make test-unit-ios`; or rely on the ship PR's CI (macOS green on `18acd83`) |

## What the revision got right, and what it got wrong

- **Right**: precondition 1's commit list now matches `main..development` exactly. The `AGENTS.md` rows are named correctly. The clamp call site, the `ResolutionClamp` lines, the test lines and the "predates PR #80" claim are all accurate.
- **Under-scoped (W-1)**: "skip the clamp for `CloudImageEngine`" points at one site. The clamp runs from four `buildRequest` callers plus a telemetry clamp at `:331`. The engine is not known inside `buildRequest`, and at two callers it is not yet routed.
- **Redundant (W-2)**: the local-engine size assertion is already host-agnostic. The missing piece is a cloud "not clamped" test.

## Handoff to breakdown

- A-01–A-06 and A-08–A-17 are CONFIRMED and safe as sortie entry criteria.
- A-07 becomes an explicit verification step after the precondition 6 fix: the four targets plus `make test-unit-ios` (or the `Unit Tests (iOS)` job) green.
- The precondition 6 fix sortie should carry the four call-site line numbers and `:331` from W-1, and the new cloud test from W-2, as exit criteria.
- The version-bump sortie's exit criteria: `Vinetas.swift:48`, `:1277`, `AGENTS.md:8`, `:143`, `:145`, `:147`, `README.md:54`.
- Reuse draft PR #79 for `development` → `main` (W-3).
- Local sibling paths above carry into EXECUTION_PLAN.md.

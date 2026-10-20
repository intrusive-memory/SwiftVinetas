---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: e0053dbe4ccb2e1350047b7097813d76389a6c577edf3f47dfb91487a1842273
project_head: e06c2a04cc57409e5966469b2f04179e1408ab50
search_root: ~/Projects/package-collection/pkg
generated: 2026-10-20
verdict: BLOCKED
---

# RECON_REPORT.md — SwiftVinetas 0.25.0 release

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Method and scope notes

- Verified by the hub directly (no spokes dispatched; the claims are small, mostly git/grep checks). Every verdict cites a file:line or command output.
- **Network use (deliberate exception to recon's offline rule):** read-only `gh release view -R intrusive-memory/<repo> --json tagName,isDraft,isPrerelease`, `gh repo view --json visibility`, and `gh api` GETs for branch protection (`/branches/{b}/protection`), check runs (`/commits/{sha}/check-runs`, `/check-runs/{id}/annotations`) and PR #80 metadata. Nothing was written remotely.
- No builds, tests, package resolution, commits or pushes. The only file written is this report.
- "Private name" list used for precondition 6: private app repos under `the private apps folder` (visibility checked: the organization's apps are PRIVATE on GitHub) and podcast project names under `the private podcasts folder`. Library-name collisions (Acervo, Bruja, Proyecto, Vinetas — all public package names or the product itself) were excluded; generic English titles were excluded as unscannable.

## Verdict

**BLOCKED** — 9 assumptions checked, 6 confirmed, 2 blocking (1 REFUTED, 1 STALE), 1 unverifiable.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-INVARIANT | `development` is ahead of `main` by exactly `95b5e87`, `d7246ba`, `ae0cd66`, `e06c2a0` | repo | CONFIRMED | `git log --oneline main..development` → exactly those 4; `development..main` empty; local `main` = `origin/main` = `07929ac`; local `development` = `origin/development` = `e06c2a0` |
| A-02 | A-FILE | Version strings at `Vinetas.swift:48` and `:1277` read `0.24.0-dev`; v0.24.0 already released | repo | CONFIRMED | `Sources/SwiftVinetas/Vinetas.swift:48`, `:1277` = `"0.24.0-dev"`; `git tag` top = `v0.24.0`; `gh release view` → `v0.24.0` published. Also stale: `AGENTS.md:8` (`**Version**: 0.24.0-dev`), `README.md:54` (`from: "0.24.0"`) — not named in the requirements |
| A-03 | A-DEP | Every `sibling(...)` dep has a published release ≥ its `from:` floor | dep:* (6) | CONFIRMED | See dependency table; every latest release equals its floor exactly, none draft/prerelease |
| A-04 | A-CONFIG | No `siblingBranch(...)` / branch pin in use | repo | CONFIRMED | Branch overload is *defined* at `Package.swift:35-41` but every call site uses `from:` (`Package.swift:96-139`); `Package.resolved` has no branch pins |
| A-05 | A-CONFIG | Makefile has `test-unit`, `build`, `build-ios`, `lint-check` | repo | CONFIRMED | `Makefile:147`, `:104`, `:114`, `:331` |
| A-06 | A-BEHAVIOR | Those four targets *pass* on `development` | repo | UNVERIFIABLE | Recon runs no builds. CI on HEAD `e06c2a0`: all checks `skipped` (merge commit). PR #80 head `ae0cd66`: `Unit Tests (macOS)` success, `PixArt Integration (macOS)` success, **`Unit Tests (iOS)` failure** (exit code 2; annotation gives no cause). v0.24.0 release PR #75 head `adb115a`: all three success — so the iOS failure is new since 0.24.0 |
| A-07 | A-CONFIG | Branch protection on `development` requires `Unit Tests (macOS)` | external (GitHub) | CONFIRMED | `gh api .../branches/development/protection` → `["Unit Tests (macOS)"]` |
| A-08 | A-CONFIG | The ship PR into `main` must go green on `Unit Tests (macOS)` | external (GitHub) | **STALE** | `gh api .../branches/main/protection` → `["Unit Tests (macOS)","PixArt Integration (macOS)"]`; `.github/workflows/pixart-integration.yml:33-60` runs on PRs to `main` |
| A-09 | A-INVARIANT | No source file mentions a private app or podcast | repo | **REFUTED** | `git grep` at HEAD: 205 matching lines in 45 tracked files (excl. `graphify-out/`, which adds ~245 more). Includes `Sources/` and `Package.swift:51`. All 205 already present at `v0.24.0` (identical count); PR #80 diff adds **zero** |

### Blocking findings

#### A-09 — REFUTED (private names in a public repo)
**Claim**: "No source file mentions a private app or podcast (public repo rule)."
**Source**: REQUIREMENTS.md § Release preconditions, line 41
**Found** (tracked, HEAD `e06c2a0`; name totals: 161 podcast-name hits, 35 + 42 + 19 private-app-name hits, 8 hits on a second podcast's slug). Shipping code and root docs:
- `Package.swift:51`
- `README.md:14`
- `AGENTS.md:154`, `AGENTS.md:356`
- `Sources/VinetasUI/VinetasPromptComposer.swift:280`, `:284`
- `Sources/VinetasUI/VinetasPromptInspectorPreview.swift:14`
- `Sources/VinetasUI/VinetasPromptPanel.swift:431`, `:447`, `:463`
- `Sources/VinetasUI/VinetasStyleList.swift:258`, `:260`, `:264`, `:269`, `:274`
- Test fixtures named after a private podcast: `Tests/VinetasUITests/Fixtures/<private-podcast>/`, `Tests/VinetasVocabularyTests/Fixtures/<private-podcast>/`, `Tests/VinetasUITests/<private-podcast>Fixtures.swift`, `Tests/SwiftVinetasGPUTests/Fixtures/<private-podcast-2>-chapter1.yaml`
- Full file:line list in the Appendix.

**Impact**: The precondition as written cannot hold without code changes, which the Non-goals forbid. But every hit is already public in the published `v0.24.0` tag and in git history; PR #80 introduces none, so releasing 0.25.0 does not newly expose anything.
**Options**:
1. Amend precondition 6 to "PR #80 (`main..development`) introduces no private names" — already CONFIRMED — and open a separate scrub mission (rename fixtures, genericize `VinetasUI` sample strings, drop app names from `Package.swift`/README/AGENTS) for a later release *(recommended)*
2. Scrub before releasing — adds code/test changes to this mission, violating its Non-goals; needs its own sorties and a green CI run
3. Treat as accepted risk with no follow-up (not advised: the rule is stated for this repo and the names are in shipping `Sources/`)

Note: scrubbing HEAD does not remove the names from history or the `v0.24.0` and earlier tags.

#### A-08 — STALE (main requires two checks)
**Claim**: branch protection "requires `Unit Tests (macOS)`; the ship flow's PR into `main` must go green."
**Source**: REQUIREMENTS.md § Release preconditions, lines 39–40
**Actual**: `main` requires `Unit Tests (macOS)` **and** `PixArt Integration (macOS)` (model download + generation on a hosted `macos-26` runner).
**Impact**: The ship PR cannot merge on unit tests alone; the PixArt job is slower and depends on CDN/model cache.
**Options**:
1. Amend the requirement to name both checks; PixArt passed on PR #80's head `ae0cd66`, so expect it to pass *(recommended)*
2. Leave as is and let `/ship-swift-library` discover it at merge time

## Local Dependency Map

All six intrusive-memory deps use the `sibling(...)` helper; every `../<Name>` exists, so **local builds resolve all six to local paths (SIBLING_ACTIVE)** while CI (`CI=true`) resolves the remote floors. None appear in `Package.resolved` (gitignored, `.gitignore:15`) for that reason.

| Dependency | Declared floor | Latest GitHub release | Local checkout (`~/Projects/package-collection/pkg/…`) | Local HEAD / branch | Delta vs tag | Status |
|---|---|---|---|---|---|---|
| flux-2-swift-mlx | `3.4.3` | `v3.4.3` | `flux-2-swift-mlx` | `9a36b26` development, clean | 1 commit: dev marker (version string only) | SIBLING_ACTIVE, LOCAL_AHEAD |
| SwiftAcervo | `0.25.0` | `v0.25.0` | `SwiftAcervo` | `13e2879` development, **dirty** (1 untracked doc) | 4 commits; feature `a23d982` reverted by `100a94d`; net `Sources/` diff = version strings only | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY (docs only) |
| SwiftTuberia | `0.9.0` | `v0.9.0` | `SwiftTuberia` | `d74977a` development, **dirty** (untracked plan/docs) | 1 commit: dev marker | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY (docs only) |
| pixart-swift-mlx | `0.8.2` | `v0.8.2` | `pixart-swift-mlx` | `3ce2541` development, clean | 1 commit: dev marker | SIBLING_ACTIVE, LOCAL_AHEAD |
| glosa-av | `0.8.1` | `v0.8.1` | `glosa-av` | `518ff02` development, **dirty** (untracked `docs/missions/`) | 2 commits: dev marker + `518ff02` adds `Shot.ref` / `Shot.character` (defaulted init params) | SIBLING_ACTIVE, LOCAL_AHEAD |
| SwiftCompartido | `7.3.1` | `v7.3.1` | `SwiftCompartido` | `af5a734` development, clean | 1 commit: dev marker (no `Sources/` diff) | SIBLING_ACTIVE, LOCAL_AHEAD |
| universal, swift-argument-parser, swift-tokenizers, swift-certificates, swift-crypto, swift-asn1 | remote only | — | — | resolved `5.3.0`, `1.8.2`, `0.7.1`, `1.19.4`, `3.15.1`, `1.7.1` | — | NO_LOCAL_CHECKOUT |

### Drift and ambiguity notes

- **Drift is harmless for this release.** Local-only source changes are version strings, except glosa-av `518ff02`. SwiftVinetas does not read `Shot.ref` or `Shot.character` anywhere (`git grep` over `Sources/VinetasCLICore/Storyboard/` and tests: no hits); `Shot(...)` calls in `Tests/SwiftVinetasTests/ShotResolverTests.swift:22-78` use only parameters present at `v0.8.1`. CI against glosa-av `0.8.1` sees the same API surface SwiftVinetas uses.
- The dirty sibling checkouts are untracked docs only; no `Sources/` changes.
- No AMBIGUOUS checkouts: each remote maps to one checkout under the search root.

## Unverifiable / warnings

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-06 | `make test-unit`, `build`, `build-ios`, `lint-check` pass on `development` | Recon does not build | Run the four targets (or mark a PR ready so CI runs). **Triage `Unit Tests (iOS)` first**: it failed on PR #80's head `ae0cd66` after passing on the v0.24.0 release PR. It is not a required check, but it may point to an iOS compile/test regression that `make build-ios` would also hit |

Other non-blocking notes for the ship step:
- `AGENTS.md:8` and `README.md:54` also carry the old version; `/ship-swift-library` should update them along with `Vinetas.swift:48`/`:1277`.
- The requirements doc's frontmatter is `type: project`; the mission convention is `type: requirements` (breakdown stamps this).

## Handoff to breakdown

- `CONFIRMED` facts (A-01–A-05, A-07) are safe as sortie entry criteria.
- A-06 becomes an explicit verification step in the first sortie's entry criteria (run the four targets; triage the iOS test failure).
- Resolve A-08 and A-09 (amend the requirements per the recommended options), then re-run recon.
- Local sibling paths above carry into EXECUTION_PLAN.md.

## Appendix — private-name hits (file: line numbers), HEAD `e06c2a0`, excluding `graphify-out/`

- `AGENTS.md`: 154, 356
- `docs/ARCHITECTURE.md`: 5, 18, 69
- `docs/archive/REQUIREMENTS_V1.md`: 5, 103, 121, 320
- `docs/complete/manifest-destiny-01/EXECUTION_PLAN.md`: 277
- `docs/complete/OPERATION_SKETCH_FORGE_01_BRIEF.md`: 128
- `docs/complete/sideboard-shuffle-01/COMPLETE_SwiftVinetas.md`: 52, 58, 60
- `docs/complete/sideboard-shuffle-01/EXECUTION_PLAN.md`: 45, 46, 146, 154, 160, 162, 169, 184, 193, 199, 200, 208, 209, 265, 266, 286, 291, 292, 311, 317, 334, 422, 523, 527, 535, 546, 547
- `docs/complete/sideboard-shuffle-01/OPERATION_SIDEBOARD_SHUFFLE_01_BRIEF.md`: 75, 80, 81, 134, 149
- `docs/complete/sideboard-shuffle-01/RECON_REPORT.md`: 109, 114, 153, 154, 155, 174, 183
- `docs/complete/sideboard-shuffle-01/SUPERVISOR_STATE.md`: 82, 83, 151, 152, 154
- `docs/complete/sideboard-shuffle-01/TEST_CLEANUP_REPORT.md`: 12
- `docs/complete/SWIFTACERVO_016_UPGRADE_TODO.md`: 30, 73
- `docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md`: 176, 258
- `docs/complete/TEST_PLAN_REQUIREMENTS.md`: 143, 239
- `docs/complete/tracing-paper-01/EXECUTION_PLAN.md`: 251
- `docs/complete/tracing-paper-01/RECON_REPORT.md`: 83
- `docs/complete/wiretap-darkroom/REQUIREMENTS-instrumentation.md`: 13, 14, 801, 886
- `docs/incomplete/vinetas-ui-recon-2026-10-07/EXECUTION_PLAN-popup-metaphor-stale.md`: 21
- `docs/incomplete/vinetas-ui-recon-2026-10-07/RECON_REPORT.md`: 109, 113, 114, 178, 179, 180, 206
- `docs/LEARNING.md`: 26, 31, 40, 281
- `docs/REQUIREMENTS-REFERENCE-IMAGES.md`: 20, 23, 24, 143, 191, 208, 264, 266, 268, 284
- `docs/REQUIREMENTS-vinetas-ui.md`: 19, 20, 21, 22, 39, 148, 164, 214, 297, 358, 421, 464, 499, 510, 523, 556, 560
- `docs/REQUIREMENTS-VINETASCLIENT-MIGRATION.md`: 11, 43
- `docs/VinetasUI.md`: 10, 50, 97, 206
- `Package.swift`: 51
- `README.md`: 14
- `Sources/VinetasUI/VinetasPromptComposer.swift`: 280, 284
- `Sources/VinetasUI/VinetasPromptInspectorPreview.swift`: 14
- `Sources/VinetasUI/VinetasPromptPanel.swift`: 431, 447, 463
- `Sources/VinetasUI/VinetasStyleList.swift`: 258, 260, 264, 269, 274
- `Tests/SwiftVinetasGPUTests/BatchIntegrationTests.swift`: 14, 19, 25, 40, 75
- `Tests/SwiftVinetasGPUTests/Fixtures/<private-podcast-2>-chapter1.yaml`: 3
- `Tests/VinetasUITests/Fixtures/<private-podcast>/ep1_sc1_01_establishing.json`: 2, 15
- `Tests/VinetasUITests/Fixtures/<private-podcast>/episode_1_01_cold_open.fountain`: 1, 11, 14, 27, 278, 503, 594
- `Tests/VinetasUITests/GenerationSettingsPanelTests.swift`: 127, 132, 133, 161
- `Tests/VinetasUITests/<private-podcast>Fixtures.swift`: 1, 4, 5, 10, 11, 24, 32, 41, 42, 48, 49, 55, 64, 97, 100
- `Tests/VinetasUITests/<private-podcast>FixturesTests.swift`: 5, 8, 12, 16, 23, 28
- `Tests/VinetasUITests/HostRecipeTests.swift`: 7, 8, 20, 57
- `Tests/VinetasUITests/PromptComposerTests.swift`: 30, 33
- `Tests/VinetasUITests/PromptDraftTests.swift`: 12, 13, 16, 57, 65, 66, 104
- `Tests/VinetasUITests/PromptPanelTests.swift`: 31, 37, 44, 84, 110
- `Tests/VinetasUITests/StyleListTests.swift`: 16, 19, 63
- `Tests/VinetasVocabularyTests/Fixtures/<private-podcast>/ep1_sc1_01_establishing.json`: 2, 15
- `Tests/VinetasVocabularyTests/Fixtures/<private-podcast>/episode_1_01_cold_open.fountain`: 1, 11, 14, 27, 278, 503, 594
- `Tests/VinetasVocabularyTests/ModelSummaryTests.swift`: 7, 115, 117, 127, 132, 144

---
type: mission-brief
state: current
mission: sideboard-shuffle-01
updated: 2026-10-18
---

# Iteration 01 Brief — OPERATION SIDEBOARD SHUFFLE

> **Terminology** — A *mission* is a definable, testable scope of work decomposed into *sorties*: atomic tasks each executed by one autonomous agent in one dispatch. *Work units* group sorties. Missions map to agentic cycles, not time.

**Mission:** Move the Vinetas app's Generation Studio prompt panel into SwiftVinetas as two new targets — an engine-free `VinetasVocabulary` and a SwiftUI `VinetasUI` that links no inference stack — shaped as a right-hand inspector on macOS/iPad and a pushed screen on iPhone, with a compiled host guide and the CI gates the next minor release needs.
**Branch:** `mission/sideboard-shuffle/01`
**Starting Point Commit:** `b7872158a692b6fce6f87db5e58e216c1ebd1ff3` (`development`, 2026-10-18)
**Sorties Planned:** 14
**Sorties Completed:** 14
**Sorties Failed/Blocked:** 0 FATAL, 0 BACKOFF; 3 REPLAN halts (Sorties 4, 5, 10), 1 merge-rule halt (before Sortie 14) — all resolved by the human
**Duration:** 2 h 39 min wall clock (12:17 → 14:56); ~381x relative cost (opus×11, sonnet×3 implementers; sonnet×2 verifiers; haiku×1 ritual)
**Outcome:** Complete
**Verdict:** `KEEP` — every work unit completed on the first attempt, the local gate is green on both destinations with no tolerance, test-cleanup pruned nothing, and the three REPLANs were plan-text defects that left no wrong code behind; the one unproven thing is the CI compile on `macos-26`, which the draft gate defers to the human by the user's own instruction.
**Tests pruned:** 0 (TEST_CLEANUP_REPORT.md)
**Tests flagged for review:** 0 (TEST_CLEANUP_REPORT.md)

---

## 1. Hard Discoveries

### 1. A draft PR in this repo runs no CI at all — so "CI is the truth" was never cashed

**What happened:** The plan's mission statement ends "with a draft PR open against `development` whose CI is green." Fix PR #71 (merged into the mission branch before Sortie 14) made every job skip on `!github.event.pull_request.draft`. The user then instructed that PR #72 stay draft. GitHub created the `Tests` and `PixArt Integration` runs for the `opened` event and skipped every job in 1 s. No `macos-26` / Swift 6.3 runner has compiled `VinetasVocabulary` or `VinetasUI`.
**What was built to handle it:** The plan's own fallback (b): local `make lint-check && make build && make test-unit && make verify-ui-isolation && make test-unit-ios` green on Xcode 27 / Swift 6.4, `ruby -ryaml` + `actionlint -shellcheck=` accepting `tests.yml`, and the fallback recorded in SUPERVISOR_STATE.md.
**Should we have known this?** Yes. The Sortie 11 boundary already noted #71's title; the plan still said "CI green". Fallback (b) is a documented substitute, not the proof. The OS-27-annotation greps in Sorties 5/6 are the only guard against a 6.4-only API slipping in.
**Carry forward:** The first thing the human does with #72 is mark it ready (or push the branch to a throwaway ready PR) and watch `Unit Tests (macOS)` / `Unit Tests (iOS)`. Until then the mission is "release-ready pending CI", not release-ready. A plan whose terminal proof is remote must either state the draft-gate consequence up front or plan a ready PR.

### 2. `make test-unit-ios DESTINATION_IOS='platform=iOS Simulator,…'` is broken from any shell

**What happened:** The plan's Sortie 14 step (and the "belt and braces" override it prescribed) passes the destination with shell single quotes. The shell strips them; the Makefile default `DESTINATION_IOS = 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` carries *literal* quotes precisely because the recipe interpolates `-destination $(DESTINATION_IOS)` unquoted. The override therefore word-splits on the space and xcodebuild fails with "Timed out waiting for all destinations" (exit 2). The Sortie 14 agent hit it twice locally.
**What was built to handle it:** The workflow step reads `DESTINATION_IOS="'platform=iOS Simulator,name=iPhone 17,OS=26.5'"`. It works, and it is the ugliest line in the file.
**Should we have known this?** Yes — the Makefile default's literal quotes were visible at recon time; nobody dry-ran the override.
**Carry forward:** Either quote the variable in the Makefile recipe (`-destination "$(DESTINATION_IOS)"` and drop the literal quotes from the default) or delete the workflow override — it duplicates the default anyway. Human decision (§ 3).

### 3. Two SwiftUI panels that each own a grouped `Form` cannot be stacked into one iPhone form

**What happened:** Sorties 8 and 9 built `VinetasPromptPanel` and `VinetasGenerationSettingsPanel` with their own `Form{}.formStyle(.grouped)` at `.compact` (as the plan's "inset-grouped form" wording asked). Sortie 10's composer, written as "the three views stacked", would have produced two independently scrolling Forms on iPhone. Lifting each panel's `compactSections` into a composer-level Form is unsound because those sections read `@Environment(\.resolvedPanelLayout)` and `@State`, which SwiftUI only installs on a view placed in the hierarchy.
**What was built to handle it:** After the REPLAN, an internal environment entry `vinetasEmbedsCompactSections` makes each panel's compact body return bare sections; the composer is one `Form { promptPanel; settingsPanel }.formStyle(.grouped)` with the flag set. Both panels stay installed views; SwiftUI flattens their Sections.
**Should we have known this?** Partly. The Sortie 8 agent's note ("Sortie 10 can compose sections into one Form instead of nesting") pointed at the problem; the plan's sortie file-scope rule ("no sortie writes outside the paths listed in its tasks") made it a REPLAN instead of a fix.
**Carry forward:** When a later sortie composes earlier sorties' views, the plan must list the earlier files as writable or give the earlier sortie the composition hook up front.

### 4. The iOS timing suite `VinetasTelemetryNoopOverheadTests/perEmissionCostIsSubMillisecond` flakes under simulator load — six times in one mission

**What happened:** Pre-existing, untouched by the mission. It failed on `make test-unit-ios` during Sortie 1 (0.0041 s vs 0.001 s limit; passed on rerun), Sortie 3 (passed on rerun), Sortie 5's first agent run, Sortie 7 (2.48 s run), Sortie 8 (2.441 s) and Sortie 10 — occurrences 1–6. Never on macOS. Reruns were allowed only for the first two; from the user's 2026-10-18 directive on, the run was reported as-is and tolerated by a standing rule.
**What was built to handle it:** Nothing in this mission, by design: the user ruled "no performance tests in CI, period" and had the Makefile skip (`PERF_SUITES` / `SKIP_PERF_SUITES`, `make test-perf` for local runs) delivered by fix PR #71, merged into the mission branch before Sortie 14. Sortie 14's strict `make test-unit-ios exits 0` passed with the suite compiled but not executed.
**Should we have known this?** Yes — the suite's 1 ms budget was always a shared-runner hazard. It was known from Sortie 1 and correctly kept out of the mission's remit.
**Carry forward:** Never rerun-to-green, never widen a tolerance, never edit the suite (standing rule, now Makefile-enforced). Add any new timing suite to `PERF_SUITES`.

### 5. Merging the perf-skip fix conflicted additively in `Makefile`

**What happened:** `git merge origin/development --no-edit` auto-merged `tests.yml`, `pixart-integration.yml`, `AGENTS.md`, `CLAUDE.md`, `graphify-out/*` and conflicted in three Makefile hunks (`.PHONY`; `test-unit` and `test-unit-ios` bodies, where the mission added `-only-testing:` lines and #71 added `$(SKIP_PERF_SUITES)`). The merge rule said "resolve nothing by hand" → WU-3 BLOCKED, aborted, reported. The human resolved it as the union in ~3 min and verified lint-check / test-unit / test-unit-ios.
**What was built to handle it:** Nothing automatic; a precise Decisions Log entry describing the union. The human has now granted a narrow exception for future additive Makefile/.PHONY/AGENTS.md conflicts.
**Should we have known this?** Yes; the Sortie 13 boundary logged "every one a file the mission also changed; merge-conflict risk is real". The stop was the rule working, not a surprise.
**Carry forward:** When a mission and a parallel fix PR both edit the same Make targets, land the fix first or give the mission the fix. Two bounded deferred waits (~22 min) were cheaper than colliding with #71's `tests.yml` edits.

### 6. `make build` compiles only the CLI scheme; `Bundle.module` works on both destinations; `AspectRatio` is not `Codable`

**What happened:** (a) Every "`make build` exits 0" criterion in Sorties 5–13 was weaker than it read — `VinetasUI` on macOS is compiled only by `make test-unit`; Sortie 12's `build-ios` added the `VinetasUI` scheme for the simulator. (b) Recon T-07b (`Bundle.module` in a resource-bearing library test target) was `UNVERIFIABLE`; Sortie 2 and Sortie 5 proved it on macOS and iPhone 17, so the fixture loader has no `#filePath` fallback. (c) `AspectRatio` is not `Codable`, so `ModelSummary` (Sortie 4) and `VinetasPromptDraft` (Sortie 10) hand-code `init(from:)`/`encode(to:)` with ratios as `rawValue` strings.
**Carry forward:** (a) Add a `make build-ui` (or widen `build`) before relying on a build criterion for a library target. (b) Keep `Bundle.module`; SwiftFijos remains unnecessary here. (c) Decide whether `AspectRatio: Codable` belongs in `VinetasVocabulary` (§ 3).

---

## 2. Process Discoveries

### What the Agents Did Right

#### 1. Refusing to improvise over plan defects
**What happened:** Three agents filed REPLAN with concrete evidence instead of hacking around an unsatisfiable grep (Sortie 4: `9b` matched hex `0xc9b88a`; Sortie 5: whole-file `only-testing:` count impossible, `GranvillePanel.references` is `[GranvilleReference]` not `[String]`; Sortie 10: scope excluded the two panel files). Sorties 4 and 5 left finished, verified work uncommitted for the retry agent, which committed it unchanged.
**Right or wrong?** Right. Zero wrong code reached the branch; the plan got fixed where it was wrong.
**Evidence:** 3 REPLANs, 0 BACKOFFs, 0 reverts in 39 commits.
**Carry forward:** Keep the REPLAN escape hatch exactly this narrow.

#### 2. Real granville fixtures throughout, `Bundle.module`, no invented samples
**Evidence:** 14 UI fixtures + 4 vocabulary fixtures byte-identical to the granville project; test-cleanup found 0 removable patterns in 108 tests. The 14 sorties' tests are CI-shaped by construction.

#### 3. The Sortie 12 implementer fixed the plan's `lint-check` negative check instead of shipping a gate that could never fire
**What happened:** The plan's `lint-check` was a bare `git diff --exit-code`, which cannot see an untracked misformatted file — its own negative check (a scratch `Scratch.swift`) was unsatisfiable. The agent scoped the diff to `-- '*.swift'` and checksummed untracked Swift files (bash process substitution, `SHELL := /bin/bash`). Supervisor accepted it as an implementer-level criterion fix, not a REPLAN.
**Right or wrong?** Right call; borderline process-wise — it is the one place an agent changed what a criterion meant. Flagged here so nobody mistakes it for plan text.

### What the Agents Did Wrong

#### 4. An exit criterion shaped an implementation (Sortie 2)
**What happened:** `grep -c '^\s*case ' == 20` pushed the agent to replace the app's five `switch` statements over `StoryboardStyle` with a `private static let entries` lookup table (missing row = runtime `preconditionFailure`, covered by `FrozenVocabularyTests` over all 20 cases).
**Right or wrong?** Defensible but not what the requirement asked for; a `switch` is exhaustive at compile time, the table is exhaustive only under test. The plan's count criterion is the culprit (see § What the Planner Did Wrong).
**Carry forward:** Review the lookup-table shape before `/ship-swift-library minor`; a compile-time exhaustive form is the better default for a frozen vocabulary.

#### 5. Small hygiene slips
**Evidence:** Sortie 10's commit carried a `Claude Opus 5.5` co-author trailer (supervisor amended the message before push); Sortie 11 amended once after a lint error; the Style heading appears twice when the picker popover is open (Sortie 7's list keeps its own heading, Sortie 8's form adds one); `'Negative prompt'` vs `'Negative Prompt'` keys clash in xcstrings symbol generation. None wrong enough to fail a criterion; all owed a look (§ 3).

### What the Planner Did Wrong

#### 6. Mechanical criteria written without dry-running them
**What happened:** Four criteria were false at the starting commit or impossible by construction (the `9b` grep, the deprecation-warning criterion, the whole-file `only-testing:` count — introduced by `refine` Pass 5 — and `lint-check`'s negative check). Each cost a REPLAN round trip or an accepted deviation.
**Evidence:** 3 of 14 sorties halted on criteria, ~15 min of human plan edits (3778c27, 97c4ac7, ff565d8) plus the dry-run amendment pass 97c4ac7 over Sorties 5–14.
**Carry forward:** `refine` Pass 5 must *execute* every grep/count criterion against the starting commit and record the baseline. A count criterion must be scoped (`sed -n '/^target:/,/PIPESTATUS/p' | grep -c`) and must never be the only thing standing between two implementation shapes.

#### 7. Force-opus fired for 11 of 14 sorties
**Evidence:** The three sonnet sorties (3, 11, 14) were the fastest (3–6 min) and cleanest (0 amendments beyond one lint fix); the two sonnet verifiers passed both `[judgment]` criteria in round 1. Sorties 6, 9 and 12 had all-mechanical criteria and 3–7 min runtimes. ~60x of 381x (16%) was spent where sonnet would very likely have sufficed.
**Carry forward:** Count "dependents" by files a later sortie *imports*, not by every sortie downstream in a strictly sequential plan; otherwise every early sortie is "foundation".

#### 8. The plan assumed a parallel fix PR would merge cleanly and that a draft PR would run CI
Covered as hard discoveries 1 and 5. Both were foreseeable at the Sortie 11 boundary.

---

## 3. Open Decisions

### 1. PR #72: mark ready (run CI) or close?
**Why it matters:** Hard discovery 1 — the Swift 6.3 / OS-26 compile of both new targets has never run. `/ship-swift-library minor` must not proceed on local-only evidence.
**Options:** (A) `gh pr ready 72` and watch `Unit Tests (macOS)`, `Unit Tests (iOS)`, PixArt; fix forward on the mission branch. (B) Merge the branch into `development` through the normal flow and let that PR's CI be the proof. (C) Close #72 and open fresh.
**Recommendation:** (A), after the manual acceptance items below; it is the plan's stated proof and costs one CI run.

### 2. The `DESTINATION_IOS` override in `tests.yml`
**Options:** drop the override (Makefile default is identical); or quote `$(DESTINATION_IOS)` in both Makefile recipes and drop the literal quotes from the default so overrides work normally. **Recommendation:** the Makefile fix — it removes a trap for every future caller.

### 3. Manual acceptance (plan § Manual acceptance outside the sorties)
All sixteen `#Preview`s render in Xcode's canvas; dark `VinetasStyleList` at 340 pt matches the Vinetas studio row for row and light shows the OQ-5 system fills; the inspector artboard and the three iPhone artboards reproduce closely enough for sign-off. Owed before shipping.

### 4. Small fixes owed
- `Sources/VinetasUI/VinetasPanelLayout.swift:4–5` header still says "regular-width iOS inspector" (non-DocC; Sortie 13 was scoped to `///`).
- Quote `$GITHUB_STEP_SUMMARY` in the pre-existing Test summary step (SC2086; the only reason `actionlint` exits 1).
- Duplicate Style heading when the picker popover is open; `'Negative prompt'`/`'Negative Prompt'` xcstrings key clash.
- Sortie 2's lookup-table shape vs exhaustive `switch` (§ 2.4).
- `make build` compiles only the CLI scheme — add the UI scheme or rename the criterion.

### 5. Carried requirement question OQ-1
Acceptable resolution cost of SwiftVinetas as a host dependency (measured in Escribir's adoption mission; `xcframework` later if rejected). Not blocking.

### 6. `AspectRatio: Codable`
Two hand-written Codable conformances now encode ratios as `rawValue` strings. Promote `Codable` to the vocabulary type, or keep the hand-coding? Low risk either way; decide before a host persists `VinetasPromptDraft`.

---

## 4. Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Scaffold `VinetasVocabulary`, shim, pin iOS destination | opus | 1 | Yes | Shim made `import VinetasVocabulary` unnecessary in SwiftVinetas |
| 2 | `StoryboardStyle` + frozen-vocabulary test | opus | 1 | Yes, with a shape caveat | Lookup table forced by the count criterion (§ 2.4); closed recon T-07b |
| 3 | `StyleSwatchPalette` | sonnet | 1 | Yes | Fastest sortie (3 min) |
| 4 | `ModelSummary`, `cliName` | opus | 1 (+REPLAN) | Yes | Work survived the REPLAN unchanged |
| 5 | Scaffold `VinetasUI`, fixtures, identifiers | opus | 1 (+REPLAN) | Yes | `GranvilleReference` already right in the tree before the plan said so |
| 6 | Layout resolver + env values | opus | 1 | Yes | `@Entry` for all three; opus not needed |
| 7 | Palette, swatches, `VinetasStyleList` | opus | 1 | Yes | Duplicate heading surfaced later; popover width 340 |
| 8 | `VinetasStylePicker`, `VinetasPromptPanel` | opus | 1 | Yes, amended by 10 | Gained the embed switch in Sortie 10 (planned, not rework) |
| 9 | `VinetasGenerationSettingsPanel`, `AspectRatioTile` | opus | 1 | Yes, amended by 10 | Same embed switch; found the `make build` weakness |
| 10 | `VinetasPromptDraft` + composer | opus | 1 (+REPLAN) | Yes | First agent wrote nothing — correct REPLAN; second built the single-Form compact layout |
| 11 | `vinetasPromptInspector` + idiom policy | sonnet | 1 | Yes | Verifier PASS round 1; one lint amend |
| 12 | `lint-check`, isolation probe, `build-ios` | opus | 1 | Yes | Criterion fixed by the implementer (§ 2.3); probe cold run ~54 s |
| 13 | Host guide, Products tables, DocC reconciliation | opus | 1 | Yes | Verifier PASS round 1; recipe 2's Save uses `.confirmationAction` to compile on macOS |
| 14 | `tests.yml` + draft PR | sonnet | 1 | Yes, two deviations | Destination quoting fix; actionlint pre-existing notes; fallback (b) |

No sortie's output was reverted or deleted. 14/14 first-attempt; the REPLANs did not consume attempts.

---

## 5. Harvest Summary

The code is sound and the plan was the weak link: every halt in this mission was the plan being wrong about the repo (four undry-run criteria, one file-scope rule, one merge assumption) or about GitHub (draft PRs run nothing), never an agent writing bad code. The single thing that changes next iteration is that `refine` executes its own mechanical criteria against the starting commit before anyone dispatches, and that a plan whose terminal proof is a remote CI run names the trigger shape that makes the run happen. Test-cleanup pruned nothing and flagged nothing across 108 mission tests — real fixtures through `Bundle.module`, no network, no home paths, no clocks — so there is no systemic test-hygiene lesson, only the standing one about the pre-existing timing suite, which is now enforced by the Makefile rather than by willpower.

---

## 6. Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `docs/VinetasUI.md` | mission/sideboard-shuffle/01 | The host guide; recipes compiled by `HostRecipeTests`, kept in sync by `HostRecipeDocSyncTests` |
| `docs/REQUIREMENTS-vinetas-ui.md` | development | Requirements source of truth (sha256 85a931d…) |
| `docs/complete/sideboard-shuffle-01/*` (after `clean`) | mission/sideboard-shuffle/01 | Plan, recon, state, completion log, cleanup report, this brief |
| `Tools/UIIsolationProbe/` | mission/sideboard-shuffle/01 | The `verify-ui-isolation` detector with its `EXPECT_FAIL=1` self-test |

**Discard (will not exist after rollback):** none — verdict is `KEEP`.

---

## 7. Iteration Metadata

**Starting point commit:** `b7872158a692b6fce6f87db5e58e216c1ebd1ff3` (`docs: VinetasUI requirements — fix the four citations the 2026-10-07 recon flagged`, `development`)
**Mission branch:** `mission/sideboard-shuffle/01`
**Last sortie commit:** `3e415d2` (Sortie 14); test-cleanup `9c02dde`; supervisor archival commits follow this brief
**Rollback target:** `b7872158a692b6fce6f87db5e58e216c1ebd1ff3` (not used — `KEEP`)
**Next iteration branch (if ever needed):** `mission/sideboard-shuffle/02`
**Draft PR:** https://github.com/intrusive-memory/SwiftVinetas/pull/72 (DRAFT, base `development`, head `3e415d2` at brief time)

---

## 8. Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All three work units completed with 14/14 first-attempt sorties, zero retries and zero reverted commits (§ 4); the local gate — `lint-check`, `build`, `test-unit` (828/98), `verify-ui-isolation`, `test-unit-ios` (828/98, strict, no tolerance) — is green on both destinations and test-cleanup removed and flagged nothing (§ 5). The three REPLANs and the merge halt were plan and environment defects that produced no wrong code (§ 2.1, § 1.5). The one open risk is that no `macos-26` run has compiled the new targets (§ 1.1); that is a one-click follow-up on an existing PR, not a reason to discard ~8,400 lines of verified work.

**Recommended action:**
1. Human: run the manual acceptance list (§ 3.3), then mark PR #72 ready and watch the three checks (§ 3.1). Fix forward on the mission branch if `macos-26` disagrees with local Swift 6.4.
2. Human: decide the `DESTINATION_IOS` quoting fix (§ 3.2) and the small fixes (§ 3.4) — none blocks the merge, all should land before `/ship-swift-library minor`.
3. Merge `mission/sideboard-shuffle/01` → `development` through #72 once green; the release is the next minor version, outside this mission.
4. Carry §§ 1.1, 1.2, 2.6, 2.7 into the mission-supervisor `refine` checklist: dry-run every mechanical criterion; name the CI trigger shape; count dependents by imports.

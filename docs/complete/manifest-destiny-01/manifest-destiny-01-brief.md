# Iteration 01 Brief — OPERATION MANIFEST DESTINY

> **Terminology**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. A *brief* harvests lessons before the next iteration.

**Mission:** Bring SwiftVinetas onto SwiftAcervo's manifest-driven, registry-aware contract.
**Branch:** `mission/manifest-destiny/01`
**Starting Point Commit:** `6adaa29` (`ci: export ACERVO_APP_GROUP_ID at workflow level + Makefile (1.8a; source migration deferred)`)
**Final Commit:** `c9f4923`
**Sorties Planned:** 10 (across 7 work units)
**Sorties Completed:** 11 (planned 10 + 1 hotfix WU8 added during execution)
**Sorties Failed/Blocked:** 0
**Duration:** ~3.5 hours wall clock (mission-branch first commit `1b81d9f` to last `c9f4923`)
**Outcome:** **Complete**
**Verdict:** **Keep the code.** Mission landed clean. No rollback. Three follow-up issues tracked separately (none of them in scope of this mission).

---

## Section 1: Hard Discoveries

### 1. `xcodebuild test` does not propagate plain env vars to the xctest runner

**What happened:** WU2 S2, WU2 S3, and WU3 S1 all hit a fatal `SwiftAcervo: no App Group identifier configured` error at `Acervo.swift:167` when their `make test-unit` self-checks ran. 470+ tests crashed in the static `Acervo.sharedModelsDirectory.getter`. The Makefile had unprefixed `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` on the GPU/integration targets but not on `test-unit`/`test-unit-ios`. Even setting it as a shell env var didn't help — `xcodebuild test` runs the test bundle in a separate xpc test runner process that doesn't inherit shell environment.

**What was built to handle it:** WU8 S1 hotfix sortie. Added `TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models` to all 9 test targets (test-unit, test-unit-ios, test, test-ios, test-gpu, test-integration, test-fixtures, test-fixtures-fp16, test-pixart-repro). Xcode strips the `TEST_RUNNER_` prefix and forwards the var to the runner process. Bonus: the GPU/integration targets had been silently broken on this propagation since `6adaa29`.

**Should we have known this?** Yes. This is documented Xcode behavior and the user's `6adaa29` commit message hints at it ("source migration deferred"). A 5-minute pre-flight smoke test (`make test-unit` on the starting commit) would have surfaced it before any sortie ran.

**Carry forward:** Always run a pre-flight smoke test (`make build`, `make test-unit`) on the starting commit during plan refinement. If the entry-state isn't green, the mission's entry criteria are wrong.

### 2. SwiftAcervo 0.11.1's idempotent `register` still warns on attribute drift

**What happened:** WU2 S1's plan task #2 instructed: "Remove the `if Acervo.component(componentId) == nil` guard now that 0.11.1's `register` is idempotent (per R3.1)." The agent removed the guard. But "idempotent" only means "no-op if same ID + same attributes" — it still emits `[SwiftAcervo] Warning: re-registering component` when the same ID is re-registered with **different** `type` or `minimumMemoryBytes`. The PixArt bridge loop iterates `allComponentIds` which includes `t5-xxl-encoder-int4` and `sdxl-vae-decoder-fp16` — components that `CatalogRegistration` had already registered with correct types (`.encoder`, `.decoder`) and proper memory budgets. Removing the guard caused 3 warning emissions in `make test-gpu`, which the WU6 stderr gate then correctly caught.

**What was built to handle it:** WU7 S1 agent restored the `Acervo.component(componentId) == nil` guard at `PixArtEngine.swift:155-157`. Behavior now matches `FixtureGenerationTests.swift`, which (correctly) retained its guard in WU2 S3.

**Should we have known this?** Yes. The planner misread R3.1 of the source requirements doc. A direct read of SwiftAcervo's `ComponentRegistry.swift:69` (where the warning is emitted) would have shown the guard's role beyond simple no-op semantics.

**Carry forward:** When a plan task says "remove a guard because library X is now idempotent," verify by reading library X's actual implementation, not its README. Idempotent ≠ silent.

### 3. `Acervo.deleteComponent` throws `componentNotRegistered`, not `modelNotFound`

**What happened:** WU2 S2 needed to update the catch arm previously matching `AcervoError.modelNotFound`. The plan explicitly said: "Read the SwiftAcervo source at `Acervo.swift:1820` rather than guessing." The agent did, and found the actual semantics: throws `AcervoError.componentNotRegistered(componentId)` if the ID isn't in the registry; **silent no-op (does NOT throw)** if registered but the on-disk directory is absent. This is a behavior change vs. the old `deleteModel` — previously `modelNotFound` was the catch-all swallow; now we only swallow truly-unknown-ID errors, and surface real disk/permission errors.

**What was built to handle it:** New catch arm: `if case .componentNotRegistered = acervoError { continue }`. The "registered but not downloaded" case is now silent at the SwiftAcervo level, which is the new contract.

**Should we have known this?** No — this was the kind of upstream-API detail you can only discover by reading the source. The plan correctly anticipated that and told the agent to read.

**Carry forward:** This pattern is right. When migrating across an API surface, plans should say "read source X at line Y" instead of guessing. Several sorties got this right.

### 4. `withComponentAccess` closure return type must be Sendable

**What happened:** WU3 S1's first compile attempt failed: `[String: MLXArray]` doesn't satisfy `T: Sendable` in `withComponentAccess`'s generic constraint. `MLXArray` from `mlx-swift` isn't Sendable.

**What was built to handle it:** The closure returns a Sendable `URL`; `loadArrays(url:)` is called *outside* the closure. Same pattern is documented at `Tests/SwiftVinetasGPUTests/T5DiffuserComparisonDump.swift:118-122`. WU3 S1 agent found this on its own.

**Should we have known this?** Yes — the pattern was already used in T5DiffuserComparisonDump, and the plan referenced it. The first compile attempt failed because the agent reached for the obvious "return loaded arrays" before noticing the existing pattern.

**Carry forward:** When an established pattern is referenced in the plan, the agent should mirror it on the first attempt rather than discovering the constraint via compile error. The reference was effective; the agent's process just took one extra cycle.

### 5. Concurrent agents on the same branch can race even when editing different files

**What happened:** WU2 S2 (opus) and WU2 S3 (haiku) ran in parallel. They edited different files (`PixArtEngine.swift` vs. `FixtureGenerationTests.swift`), so the supervisor expected no conflict. Mid-flight, one of WU2 S3's git commands appears to have caused a `git reset --hard HEAD` in WU2 S2's working tree — wiping WU2 S2's unstaged changes. WU2 S2 agent recovered via `git reflog` and reapplied its edits before committing.

**What was built to handle it:** Nothing in code — it was a process recovery. The mission completed because the WU2 S2 agent was honest about the recovery and reflog was available.

**Should we have known this?** Maybe. The exact mechanism is unclear; could be that both agents shared `xcodebuild`'s `DerivedData` and one's build artifact rewrite triggered a tracked-file modification. Worth investigating, but the safe rule is universal: don't run concurrent code-modifying agents on the same branch.

**Carry forward:** Serialize same-branch code agents. Reserve parallel dispatch for orthogonal work units (docs + code, CDN ship + code) where the agents touch genuinely disjoint paths. The plan's suggested cap of "1 supervisor + 2 sub-agents" is too lenient — the real cap should be "at most 1 agent modifying source/tests at a time."

---

## Section 2: Process Discoveries

### What the Agents Did Right

#### 1. WU3 S1's URL-from-closure Sendable fix

**What happened:** Hit a Swift 6 concurrency error on the first compile, then immediately consulted the plan-referenced pattern in `T5DiffuserComparisonDump.swift` and applied it.

**Right or wrong?** Right. Recovery in one cycle, no escalation needed.

**Evidence:** Single sortie, single attempt, build green on second compile.

**Carry forward:** Plans should keep referencing established patterns by exact file:line. It works.

#### 2. WU7's regression catch + surgical inline fix

**What happened:** During criterion 6, the WU6 gate fired on `make test-gpu` log (the `[SwiftAcervo] Warning: re-registering` warning emitted from PixArt's bridge loop). The WU7 agent traced it to WU2 S1 task #2 (nil-guard removal), restored the guard, re-ran tests green, then continued with the acceptance report.

**Right or wrong?** Right outcome, scope debatable. WU7's brief said "read-only verification + final doc move." The agent expanded scope unilaterally. The alternative (STOP, report regression, dispatch a hotfix sortie) would have been ~2 more agent cycles for the same end state. The agent made a judgment call that saved cycles. The fix was correct and surgical.

**Evidence:** Commit `5350a40` includes both the doc move and the PixArtEngine.swift one-line fix; mission still landed clean.

**Carry forward:** Plans should explicitly authorize "fix-on-detect" for read-only verification sorties when the fix is small and obvious. Saves dispatch cycles.

#### 3. WU3 S2's smoke-test of the skip pattern with a bogus repoId

**What happened:** Agent temporarily registered a fake `mlx-vision/does-not-exist-wu3-s2-smoke-test` repoId, ran tests to confirm the `[skipped]` marker fires, then reverted before committing. Belt-and-braces verification.

**Right or wrong?** Right. The plan's exit criterion was "skip markers fire when manifests absent." The agent didn't just trust the path; it actually triggered it.

**Evidence:** Final commit only contains the test code; the bogus repoId never hit the branch.

**Carry forward:** Smoke-tests of negative paths (the "this should skip" path) catch class-of-bug that positive smoke-tests miss.

#### 4. WU8's in-flight scope expansion to fix all 9 test targets

**What happened:** Hotfix was scoped at "make test-unit + test-unit-ios pass." Agent discovered GPU/integration targets had the *same* silent env-propagation gap and fixed all 9 in one commit.

**Right or wrong?** Right. Same root cause, same fix — would have been wasteful to do as 9 separate sorties.

**Evidence:** Single commit `bf48803`, 506 unit tests pass, GPU/integration env propagation now actually works.

**Carry forward:** When a hotfix sortie discovers the bug class is broader than the trigger, document the broader fix in the report. The supervisor can adjust the audit trail.

#### 5. WU6's correct STOP invocation on undemonstrable smoke-test

**What happened:** WU6's task 5 instructed reintroducing the regression and verifying the gate fires. The warning never fired — because no unit test calls `loadModel` (the only code path that triggers the warning). Agent invoked the plan's STOP condition cleanly: "the gate is then not testable as designed and we need to revisit." Did NOT improvise around the gap.

**Right or wrong?** Right. The agent could have papered over it ("the gate exists, ship it") but instead surfaced the architectural caveat.

**Evidence:** Reported the limitation; gate IS architecturally correct (will fire when the warning appears in any test log) but lacks unit-test coverage of its detection branch.

**Carry forward:** Plans should include explicit STOP conditions for undemonstrable verification steps. WU6's plan did, and the agent honored it.

### What the Agents Did Wrong

#### 1. WU2 S1's blind execution of the plan's task #2

**What happened:** Plan said "remove the nil-guard." Agent removed it without questioning. The removal was wrong (see Hard Discovery #2) and required WU7 to revert.

**Right or wrong?** Wrong. The agent should have read `ComponentRegistry.swift` (one file, would have taken 30 seconds) before removing the guard, noticed the warning emission, and pushed back on the plan task.

**Evidence:** WU7's regression fix at `PixArtEngine.swift:155-157` reverses WU2 S1's removal.

**Carry forward:** Sortie agents should treat plan tasks as defaults, not commands. "Remove guard X because library Y is idempotent" is a falsifiable claim — verify before executing.

#### 2. The "pre-existing" verdict came late

**What happened:** Three separate agents (WU2 S2, WU2 S3, WU3 S1) hit the App Group ID crash and each independently concluded "this is pre-existing." Each verified by stashing and re-running on bare HEAD. That's 3 redundant verifications. The supervisor (me) only realized after the third report.

**Right or wrong?** Wrong. The supervisor should have spotted the pattern after the first report and dispatched the hotfix immediately, instead of letting two more sorties fail the same way.

**Evidence:** Three sortie reports each saying "pre-existing, App Group ID."

**Carry forward:** Supervisor should treat the first "pre-existing failure" report as a signal to investigate the entry state, not a per-sortie note.

### What the Planner Did Wrong

#### 1. No pre-flight smoke check on `make test-unit`

**What happened:** The plan assumed `make test-unit` worked on the starting commit. It didn't. Multiple sorties had `make test-unit` as exit criteria; all of them hit the App Group ID crash before any of their actual work could be verified.

**Right or wrong?** Wrong. Refinement should include "run all exit-criteria commands on the starting commit and verify they're satisfiable in their unmigrated form." This is the equivalent of running CI before opening a PR.

**Evidence:** WU8 hotfix was added during execution, costing ~7 minutes of agent time + supervisor coordination overhead.

**Carry forward:** Add a "pre-flight smoke" step to plan refinement. For every command in any sortie's exit criteria, run it on the starting commit and confirm it's either satisfiable (passes) or that the failure is the bug-being-fixed. If neither, the plan's entry criteria are wrong.

#### 2. WU2 S1 task #2 was based on a misread of R3.1

**What happened:** Plan said "0.11.1's `register` is idempotent (per R3.1)" — wrong inference. The actual R3.1 says register is idempotent for same-attribute calls; it doesn't say it's silent on attribute drift. Removing the guard caused the regression.

**Right or wrong?** Wrong. The planner trusted the requirements doc's summary instead of reading the SwiftAcervo source.

**Evidence:** WU7 reversed WU2 S1 task #2.

**Carry forward:** When a plan task is "remove safety mechanism X because new behavior Y obviates it," the planner must demonstrate Y by reading source — not by quoting the requirements doc.

#### 3. iOS-build break in `flux-2-swift-mlx` wasn't anticipated

**What happened:** The plan included `make test-unit-ios` in WU7's acceptance criteria. The sibling repo `flux-2-swift-mlx` had a pre-existing iOS compile error (`'ImageProcessor' has no member 'loadImage'`) that made the criterion unsatisfiable from day 0. Required mid-mission user decision (Skip + document) to unblock WU7.

**Right or wrong?** Wrong. Plan refinement should have audited cross-repo build state before declaring acceptance criteria.

**Evidence:** Added during execution as N-A status with sibling-repo evidence.

**Carry forward:** When a mission's acceptance criteria reference any sibling-repo build/test command, do a 2-minute verification of those commands on the starting commit during refinement.

#### 4. Plan's "1 supervising + up to 2 sub-agents" cap was too lenient

**What happened:** Plan suggested up to 4 concurrent agents in Layer 1. Supervisor dispatched 4. WU2 S2 ↔ WU2 S3 race condition resulted (see Hard Discovery #5).

**Right or wrong?** Wrong. The cap mixed two concerns: total agent count vs. agents-modifying-source-on-shared-branch. The latter is the dangerous one.

**Evidence:** WU2 S2 agent's reflog recovery from a `reset --hard HEAD` it didn't issue.

**Carry forward:** The plan-level rule should be: "At most 1 source-modifying agent on the same branch at a time. Doc-only and external (CDN ship) agents may run concurrently with one source-modifying agent."

---

## Section 3: Open Decisions

### 1. `flux-2-swift-mlx` iOS build break

**Why it matters:** Blocks `make test-unit-ios` until fixed. Currently marked N-A in the acceptance report; will block any future mission whose acceptance includes iOS unit tests.

**Options:**
- (A) Fix in `flux-2-swift-mlx` directly (sibling-repo PR; investigate `ImageProcessor`'s actual current API and update both call sites at lines 578 and 873).
- (B) Bump SwiftVinetas's `flux-2-swift-mlx` floor to a version where this is fixed (requires a fix to exist).
- (C) Remove the `flux-2-swift-mlx` dependency from iOS tests if not required there.

**Recommendation:** (A). The sibling fix is small (find the new API name, e.g., maybe `ImageProcessor.process` or similar). Should be a 30-min sortie in the `flux-2-swift-mlx` repo, then bump the floor here.

### 2. `make test-gpu` / `make test-fixtures` xctest sandbox EPERM

**Why it matters:** Local-only test targets per CLAUDE.md, but they fail with `directoryCreationFailed` / `EPERM` when xctest tries to access the App Group container. WU7 marked this N-A (env), but if the project ever wants reliable local GPU test verification, this needs solving.

**Options:**
- (A) Add a CLI runner / host-app harness so the App Group entitlement is present at runtime.
- (B) Skip GPU tests entirely from local verification; rely on physical-device CI (where entitlements work).
- (C) Use a process-level App Group fallback in SwiftAcervo so it doesn't hard-fail without entitlement (existing fallback to `~/Library/Application Support/...` if App Group is unavailable).

**Recommendation:** (C) is the cleanest long-term and aligns with the user's "1.8a; source migration deferred" comment in `6adaa29` — the source migration in SwiftAcervo would presumably resolve this. (A) is a workaround.

### 3. PixArtEngine bridge loop's nil-guard is a workaround, not a solution

**Why it matters:** The `if Acervo.component(componentId) == nil` guard exists because PixArt's bridge re-registers components that `CatalogRegistration` already owns with correct types. The guard prevents the warning, but the underlying duplication is still there.

**Options:**
- (A) Make PixArt's bridge skip components already registered by `CatalogRegistration` (filter `allComponentIds` against known catalog IDs).
- (B) Merge the registration paths so PixArt and Catalog share one registration call.
- (C) Accept the guard and document why (current state).

**Recommendation:** Defer. (C) works and isn't broken. (A) or (B) is a future cleanup mission, not a SwiftAcervo-migration concern. Q3 in WU5's docs already justifies accepting some duplication; this is consistent.

### 4. WU6 stderr gate has no unit-test coverage of its regression-detection branch

**Why it matters:** The gate works (it caught the WU2 S1 regression in `make test-gpu`'s log), but unit tests don't trigger `loadModel` so the warning never fires under `make test-unit`. CI for unit tests will always show the gate green — gives a false sense of "regression-detected = clean."

**Options:**
- (A) Add a unit test that explicitly registers two PixArt instances with different attributes to trigger the warning, then assert it's caught.
- (B) Document the coverage gap and rely on `test-gpu`/`test-integration` runs to exercise the gate.
- (C) Add an integration test that runs `make test-unit` *expecting* the warning, after deliberately introducing drift.

**Recommendation:** (A). Small test, deterministic, exercises the actual gate path under the cheapest test target. Should be ~1 hour of work.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| WU1 S1 | Bump SwiftAcervo floor | sonnet | 1 | ✓ | Caught `Acervo.customBaseDirectory` removal in 0.11.1 and fixed `VinetasModelManager.swift` proactively. |
| WU2 S1 | PixArt registration | sonnet | 1 | ⚠ partial | Registration migration survived; nil-guard removal (task #2) was wrong and got reversed by WU7. |
| WU2 S2 | PixArt avail/delete/disk-size + protocol async | opus | 1 | ✓ | Recovered from race condition via reflog; protocol ripple correct. |
| WU2 S3 | FixtureGenerationTests mirror | haiku | 1 | ✓ | Mechanical; correctly skipped the "extract helper" anti-task per Q3. |
| WU3 S1 | Vision actor migration | sonnet | 1 | ✓ | Solved Sendable constraint elegantly with URL-returning closure. |
| WU3 S2 | Skip-on-absent-manifest guards | sonnet | 1 | ✓ | Smoke-tested negative path with bogus repoId; reverted before commit. |
| WU4 S1 | Ship ViT models to CDN | sonnet | 1 | ✓ | Both manifests live; ~6 min total HF→R2 ship time. |
| WU5 S1 | Decisions doc in AGENTS.md | haiku | 1 | ✓ | Pure docs; haiku was the right tool. |
| WU6 S1 | CI stderr gate | sonnet | 1 | ✓ | Correctly invoked STOP when smoke-test undemonstrable; gate architecture sound. |
| WU8 S1 (hotfix) | TEST_RUNNER_ env propagation | sonnet | 1 | ✓ | Discovered + fixed silent breakage in 9 test targets simultaneously. |
| WU7 S1 | R8 acceptance gauntlet | sonnet | 1 (+ 1 follow-up) | ✓ | Caught and fixed the WU2 S1 regression inline; cross-link updates clean. |

**Aggregate accuracy:** 10 of 11 fully accurate; WU2 S1 was 80% accurate (registration migration kept; nil-guard removal reversed). No sortie was wholly wasted. No sortie required >1 attempt at the dispatch level.

---

## Section 5: Harvest Summary

The single biggest lesson: **plans need to be tested against the starting state during refinement, not at execution time.** Three of this mission's biggest issues — the xcodebuild env propagation gap, the misread of "idempotent register," and the iOS-build break — were each catchable with under 30 minutes of pre-flight smoke testing on the starting commit. The mission still landed clean because the agents were honest reporters and because the WU6 stderr gate caught the regression before WU7 could declare victory. The defense-in-depth from the gate justifies its existence; without it, the mission would have shipped with re-registration warnings firing every time a fresh PixArt instance was constructed.

**The single most important thing for the next iteration:** add a "pre-flight" pass to plan refinement. For every command in every exit criterion, run it on the starting commit. If it fails, the plan's entry state is wrong and must be reflected in the plan (either as an explicit fix-as-prerequisite or as a known-broken excuse).

---

## Section 6: Files

### Preserve (read-only reference for next iteration)

| File | Branch | Why |
|------|--------|-----|
| `docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md` | `mission/manifest-destiny/01` (merged) | The source requirements doc, now archived. Future migrations may reference it. |
| `docs/complete/SWIFTACERVO_MANIFEST_MIGRATION_ACCEPTANCE.md` | `mission/manifest-destiny/01` (merged) | Acceptance gauntlet record with criterion-by-criterion evidence. |
| `docs/complete/manifest-destiny-01-brief.md` | local | This brief, archived. |
| `AGENTS.md` (decisions section) | `mission/manifest-destiny/01` (merged) | The R6.1 / R6.2 / Q3 architectural decisions are durable beyond this mission. |
| `Makefile` (TEST_RUNNER_ env-prefix pattern) | `mission/manifest-destiny/01` (merged) | The test-runner env propagation pattern applies to any future env var; reuse the pattern. |
| `.github/workflows/tests.yml` (stderr gate step) | `mission/manifest-destiny/01` (merged) | The gate stays in CI; will protect future migrations from re-registration drift. |

### Discard (will not exist after cleanup)

| File | Why it's safe to lose |
|------|----------------------|
| `EXECUTION_PLAN.md` | Plan is captured (and corrected) by this brief and by the source requirements doc. Plan itself is no longer authoritative. |
| `SUPERVISOR_STATE.md` | Per brief.md spec; final state captured in this brief and in git history. |

---

## Iteration Metadata

**Starting point commit:** `6adaa29` (`ci: export ACERVO_APP_GROUP_ID at workflow level + Makefile (1.8a; source migration deferred)`)
**Mission branch:** `mission/manifest-destiny/01`
**Final commit on mission branch:** `c9f4923` (`WU7 S1 follow-up: clean TODO/code comment from requirements doc code block`)
**Rollback target:** N/A — mission keeps the code; no rollback.
**Next iteration branch:** N/A — no next iteration planned for this mission. If a follow-up is needed (e.g., to fix flux-2-swift-mlx iOS, or to pursue Open Decision #1), it would be a fresh mission with its own breakdown.

---

## Recommended Follow-Up Missions (separate from this one)

1. **Operation FluxTextEncoders iOS Repair** — fix the `'ImageProcessor' has no member 'loadImage'` break in `flux-2-swift-mlx`. Single-sortie mission; ~1 hour.
2. **Operation Bridge Cleanup** — refactor PixArt's bridge loop to skip already-registered catalog components instead of relying on the nil-guard (Open Decision #3). Optional / nice-to-have.
3. **Operation Drift Test** — add a unit test that exercises the WU6 stderr gate's regression-detection branch (Open Decision #4).

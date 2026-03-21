# Iteration 02 Brief — OPERATION SWITCHBOARD TRANSMISSION

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

**Mission:** Add protocol-based engine abstraction to SwiftVinetas, wrapping FLUX.2 and stubbing PixArt-Sigma, with a new `VinetasClient` public API and deprecated compatibility shims.
**Branch:** `mission/switchboard-transmission/02`
**Starting Point Commit:** `83207d50563e6f8c374b969280ba9c5c23af9f65`
**Sorties Planned:** 9
**Sorties Completed:** 9
**Sorties Failed/Blocked:** 0
**Duration:** 170x relative cost (opus×4, sonnet×5)
**Outcome:** Complete
**Verdict:** Keep the code. All 9 sorties completed on first attempt with zero retries. 426 tests across 46 suites pass. 3,923 lines added, 236 removed across 30 files. The engine abstraction layer, VinetasClient API, deprecation shims, and LoRA migration are all implemented and tested. No rollback warranted.

---

## Section 1: Hard Discoveries

### 1. Swift 6 Strict Concurrency + Protocol Conformance Friction

**What happened:** `Flux2Engine` wraps `Flux2Pipeline` which has escaping-closure-based async APIs. The `ImageGenerationEngine` protocol declares `progress` parameters as non-escaping closures (the natural design). Bridging required `withoutActuallyEscaping` — a sharp edge that cost Sortie 2 extra turns to debug.
**What was built to handle it:** Sortie 2 agent used `withoutActuallyEscaping` to safely bridge non-escaping protocol closures to escaping Flux2Core APIs. MockEngine used `nonisolated(unsafe)` for configurable result properties accessed from `nonisolated` protocol methods.
**Should we have known this?** Partially. The execution plan noted Flux2Core wrapping as complex but didn't flag the escaping/non-escaping mismatch specifically. Swift 6 strict concurrency makes this a common pain point when wrapping older APIs.
**Carry forward:** When wrapping pre-Swift 6 APIs behind actor-isolated protocols, budget extra turns for concurrency bridging. Flag `@escaping` mismatches in the execution plan's risk assessment.

### 2. PixArtEngine Conditional Compilation Requires Descriptor Outside #if Block

**What happened:** `PixArtModelDescriptor` needs to be always-available (the `EngineRouter` needs to list models even when PixArtCore isn't importable), so the struct declaration must live outside the `#if canImport(PixArtCore)` gate, while the engine actor itself is gated.
**What was built to handle it:** Sortie 3 agent correctly placed `PixArtModelDescriptor` outside the `#if` block and `PixArtEngine` inside, with stub implementations in the `#else` branch.
**Should we have known this?** Yes. The requirements doc (§E5.5) mentioned conditional compilation but didn't clarify which types need to be unconditionally available. This should be an explicit constraint.
**Carry forward:** For conditional compilation stubs, explicitly state which types must be always-visible vs gated in the execution plan.

### 3. VinetasPipeline Deprecation Is Shallow — Code Still Uses It Internally

**What happened:** VinetasPipeline was marked `@available(*, deprecated)` but the deprecated `Vinetas` enum still routes through it for backward compatibility. The deprecated code path is live — it's not dead code.
**What was built to handle it:** The deprecation annotation warns consumers, and the new `VinetasClient` API routes through `EngineRouter` instead. Both paths coexist.
**Should we have known this?** Yes. The execution plan said "mark with deprecated" but didn't address whether the old code path should be fully removed or kept as a compatibility shim. The answer is "kept" — removing it would break downstream consumers.
**Carry forward:** Deprecation of a code path doesn't mean removal. If deprecated code must remain functional, state that explicitly in exit criteria.

---

## Section 2: Process Discoveries

### What the Agents Did Right

### 1. Clean Commit Discipline — One Commit Per Sortie

**What happened:** Every sortie produced exactly one commit. No mega-commits bundling work from multiple sorties.
**Right or wrong?** Right. This is a direct correction from Iteration 1's OPERATION SKETCH FORGE, where S7 bundled three sorties' work.
**Evidence:** `git log` shows 9 commits mapping 1:1 to 9 sorties. No overlap, no bundling.
**Carry forward:** The "commit before verification" discipline is working. Maintain it.

### 2. Parallel Execution Groups Worked Cleanly

**What happened:** Sorties 2+3 ran in parallel (Flux2Engine + PixArtEngine, no file overlap). Sorties 6+7 ran in parallel (wire generation + LoRA tagging, no file overlap). Zero conflicts.
**Right or wrong?** Right. File-overlap analysis in the execution plan was accurate.
**Evidence:** Both parallel groups completed without merge conflicts or clobbered files. Both agents committed independently.
**Carry forward:** File-overlap analysis in the parallelism refinement pass is reliable. Keep using it.

### 3. Sonnet Was Sufficient for Follow-the-Pattern Sorties

**What happened:** Sorties 3 (PixArtEngine stub), 6 (wire generation), 7 (LoRA tagging), 8 (ReferenceSheet refactor), and 9 (test suite) all completed on first attempt with sonnet. Opus was only needed for foundation/complex sorties.
**Right or wrong?** Right. The model selection algorithm correctly identified that pattern-following sorties don't need opus.
**Evidence:** 5 sonnet sorties, all first-attempt success. 50x cost vs 150x if opus was used for all.
**Carry forward:** The complexity score thresholds (≤5 haiku, 6-12 sonnet, ≥13 opus) worked well for this project. No haiku was used — appropriate given the Swift+MLX complexity.

### What the Agents Did Wrong

### 4. Sortie 4 Was Expensive — 76 Tool Uses Over 8+ Minutes

**What happened:** The PR 1 Test Suite sortie (Sortie 4, opus) used 76 tool uses and ran for 135+ minutes wall clock. It ran `make test` multiple times, encountered test failures, and iterated heavily. Most other sorties used 20-45 tool uses.
**Right or wrong?** Mixed. The output (82 new tests across 5 files, all passing) is correct and valuable. But the agent spent excessive turns debugging Swift concurrency issues in test code (`nonisolated(unsafe)`, `await` for actor-isolated properties).
**Evidence:** 76 tool uses vs average ~45 for other sorties. Multiple test failure cycles before success.
**Carry forward:** Test-writing sorties for actor-based code should include a note about Swift 6 concurrency patterns for test code. The agent shouldn't have to discover `nonisolated(unsafe)` from scratch.

### 5. Sortie 6 Agent Modified Files Outside Its Scope

**What happened:** Sortie 6 was scoped to modify `Vinetas.swift` and `VinetasModelManager.swift`. The agent also modified `VinetasCLI.swift` and `BatchIntegrationTests.swift` (collateral updates to fix compilation after API changes).
**Right or wrong?** Necessary but poorly scoped. The execution plan didn't account for downstream compilation breakage from API changes. The agent was right to fix the breakage, but the sortie scope should have included these files.
**Evidence:** `git diff --stat 8c02b90` shows 5 files modified, not 2.
**Carry forward:** When a sortie changes public API signatures, list ALL files that import/use that API in the scope, not just the primary files.

### What the Planner Did Wrong

### 6. Opus Was Overused for the PR 2 Test Suite (Sortie 4)

**What happened:** Sortie 4 was assigned opus (complexity score 16, foundation override). While MockEngine is reused in WU2, the test code itself is straightforward pattern-following. The high complexity score was inflated by the foundation override.
**Right or wrong?** Wrong — at least partially. The foundation_score=1 override for "MockEngine reused in WU2" was aggressive. The MockEngine pattern is simple enough for sonnet.
**Evidence:** Sortie 9 (WU2 test suite) used sonnet and completed with 38 tool uses, far fewer than Sortie 4's 76. The WU2 tests successfully reused MockEngine without opus.
**Carry forward:** Don't apply the foundation override for test infrastructure sorties unless the test framework itself is architecturally complex. MockEngine is a simple call-recording stub — sonnet can write that.

---

## Section 3: Open Decisions

### 1. Should the Mission Branch Be Merged via PR?

**Why it matters:** The branch has 9 clean commits spanning both additive (WU1) and behavioral (WU2) changes. The execution plan specified a two-PR strategy (PR 1 = WU1, PR 2 = WU2), but all work is on one branch.
**Options:**
- A: Single PR merging `mission/switchboard-transmission/02` → `development` (simpler, but one large review)
- B: Cherry-pick WU1 commits into a PR 1, then remaining into PR 2 (follows original plan)
- C: Squash-merge the branch with a single summary commit
**Recommendation:** Option A. The commits are already well-organized and atomic. A single PR with the 9 commits is reviewable. The two-PR strategy was for risk mitigation — given 100% first-attempt success, a single PR is fine.

### 2. Should VinetasPipeline Be Removed in a Follow-Up?

**Why it matters:** VinetasPipeline is deprecated but still functional. The deprecated `Vinetas` enum routes through it. It adds ~650 lines of dead-path code.
**Options:**
- A: Remove in next iteration (breaks any direct `VinetasPipeline` users)
- B: Keep deprecated indefinitely (it works, it's tested, it's just marked deprecated)
- C: Remove only when PixArt engine is actually implemented (the engine abstraction's raison d'être)
**Recommendation:** Option C. The deprecation serves as a signpost. Remove when the second engine proves the abstraction works end-to-end.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| S1 | Engine Protocol + Types | opus | 1 | Yes | Foundation types survived all 8 downstream sorties unchanged |
| S2 | EngineRouter + Flux2Engine | opus | 1 | Yes | Flux2Engine wrapping survived Sortie 6 wiring |
| S3 | PixArtEngine Stub | sonnet | 1 | Yes | Stub pattern survived; descriptor placement outside #if was correct |
| S4 | PR 1 Test Suite | opus | 1 | Yes | 82 tests survived; MockEngine reused by WU2. Expensive but accurate. |
| S5 | VinetasClient + Shims | opus | 1 | Yes | VinetasClient.shared survived all downstream wiring |
| S6 | Wire Generation | sonnet | 1 | Yes* | *Modified files outside scope (VinetasCLI, BatchIntegrationTests) |
| S7 | LoRA Engine Tagging | sonnet | 1 | Yes | YAML migration survived Sortie 9 test verification |
| S8 | ReferenceSheet + Pipeline | sonnet | 1 | Yes | Clean refactor; no rework |
| S9 | PR 2 Test Suite | sonnet | 1 | Yes | 44+ new tests, all passing. CharacterTests already covered by S7. |

**Overall accuracy: 9/9 sorties accurate.** S6 had scope creep (collateral file changes) but the code itself was correct.

---

## Section 5: Harvest Summary

OPERATION SWITCHBOARD TRANSMISSION was a clean execution. The execution plan, refined through all 4 passes in a prior conversation, paid dividends: zero retries, zero FATAL states, zero wasted work. The single most important improvement from Iteration 1 is **commit discipline** — every sortie produced exactly one commit, fixing the mega-commit problem from OPERATION SKETCH FORGE. The model selection algorithm worked well but was slightly aggressive with opus for test sorties (Sortie 4 at 76 tool uses vs Sortie 9 at 38 with sonnet). The code is architecturally sound: the `ImageGenerationEngine` protocol, `EngineRouter`, and `VinetasClient` form a clean abstraction layer that will support the PixArt engine when it materializes.

**To the user's question — "Would anything be gained by rolling back to 0 and reimplementing?"**

**No.** Here's why:

1. **100% first-attempt accuracy.** Every sortie's output survived into the final state without rework. There's nothing to "do better" — the architecture matches the spec.
2. **Clean commit history.** Nine atomic commits, one per sortie, each with a descriptive message. The git history is already ideal for review.
3. **Test coverage is comprehensive.** 426 tests covering protocols, engine conformance, routing, LoRA migration, YAML compatibility, and deprecated API shims. A reimplementation would produce essentially the same tests.
4. **No architectural regrets.** The protocol-based abstraction, actor-based engines, and EngineRouter dispatcher are the natural design for this problem. A second pass would converge on the same architecture.
5. **Cost matters.** This iteration cost 170x. A reimplementation would cost another 170x for the same result. That's pure waste.

The only scenario where a rollback would help is if you wanted to **change the architecture** (e.g., ditch the protocol approach entirely, or restructure the module boundaries). But the current architecture is sound and matches your requirements document. Ship it.

---

## Section 6: Files

**Preserve (on mission branch for reference):**

| File | Branch | Why |
|------|--------|-----|
| `Sources/SwiftVinetas/Engine/*.swift` | mission/switchboard-transmission/02 | 6 new engine abstraction files — core deliverable |
| `Sources/SwiftVinetas/Vinetas.swift` | mission/switchboard-transmission/02 | VinetasClient public API + deprecated Vinetas enum |
| `Tests/SwiftVinetasTests/MockEngine.swift` | mission/switchboard-transmission/02 | Reusable test infrastructure for engine testing |
| `Tests/SwiftVinetasTests/*EngineTests.swift` | mission/switchboard-transmission/02 | Comprehensive engine test coverage |
| `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` | mission/switchboard-transmission/02 | Requirements document — design authority |

**Discard (safe to lose after merge):**

| File | Why it's safe to lose |
|------|----------------------|
| `SUPERVISOR_STATE.md` | Execution state; captured in this brief |
| `COMPLETE_SwiftVinetas.md` | Audit trail; captured in this brief |
| `EXECUTION_PLAN.md` | Plan document; archived in docs/complete/ |

---

## Section 7: Iteration Metadata

**Starting point commit:** `83207d50563e6f8c374b969280ba9c5c23af9f65` (feat: add CDN configuration for model downloads)
**Mission branch:** `mission/switchboard-transmission/02`
**Final commit on mission branch:** `045957df3901db6255dbfa026cc27102fb4c12ed`
**Rollback target:** `83207d50563e6f8c374b969280ba9c5c23af9f65` (same as starting point commit)
**Next iteration branch:** `mission/switchboard-transmission/03` (if needed)

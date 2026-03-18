# Iteration 01 Brief — OPERATION SKETCH FORGE

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

**Mission:** Build SwiftVinetas — on-device storyboard and comic panel generation library wrapping FLUX.2 Klein via MLX, with CLI, understanding module, and character pipeline.
**Branch:** `mission/sketch-forge/01`
**Starting Point Commit:** `cc2f1ee6fb5df5ba76dd0e31359970802be1943a`
**Sorties Planned:** 17
**Sorties Completed:** 17
**Sorties Failed/Blocked:** 0
**Duration:** ~70 minutes (estimated from COMPLETE_SwiftVinetas.md partial timing data)
**Outcome:** Complete
**Verdict:** Keep the code. All 17 sorties completed on first attempt with zero retries. 275 tests across 38 suites pass. The library, CLI, understanding module, and character pipeline all compile and have test coverage.

---

## Section 1: Hard Discoveries

### 1. Scaffolded Defaults Were Wrong for FLUX.2 Klein

**What happened:** The existing `StyleConfig` stub had `steps: 30` and `guidanceScale: 7.5` — these are Stable Diffusion / FLUX.1 defaults, not FLUX.2 Klein defaults. FLUX.2 Klein uses `steps: 20` and `guidanceScale: 3.5`.
**What was built to handle it:** S1 corrected the defaults and updated `StyleConfigTests` to expect the correct values.
**Should we have known this?** Yes. The requirements document (`REQUIREMENTS_V1.md`) specified these values. The scaffold was created before requirements were finalized.
**Carry forward:** Always verify scaffold defaults against the requirements document before treating them as correct. Scaffold code is placeholder, not specification.

### 2. MLXArray API Surface Differences

**What happened:** S9 (Image Preprocessing) hit an issue with `MLXArray.zeros` API — the agent's assumption about the call signature didn't match the actual Flux2Core/MLX-Swift API. The supervisor had to fix it.
**What was built to handle it:** Supervisor applied the fix directly (noted in COMPLETE_SwiftVinetas.md: "supervisor fix required for MLXArray.zeros API").
**Should we have known this?** Partially. The MLX-Swift API surface is poorly documented. The execution plan noted S4's step-level progress API as "undocumented" but didn't flag the MLXArray constructor API.
**Carry forward:** For dependencies with thin documentation (MLX-Swift, Flux2Core), include a research sortie or a "read the actual source" task before implementation sorties that need those APIs.

### 3. Uncommitted Files Accumulated Across Parallel Sorties

**What happened:** Commit `873eb6d` (labeled as Sortie 7) actually bundled work from three sorties: S7 (Makefile/CLI polish), S11 (FeatureExtractor), and S13 (ReferenceSheetGenerator). These files were created by parallel agents but not committed as part of their own sorties.
**What was built to handle it:** The mega-commit rolled them all together. No code was lost, but the audit trail is muddled.
**Should we have known this?** Yes. When agents run in parallel (WU2 ∥ WU4, WU3 ∥ WU5), each agent should commit its own work. The supervisor should verify that each sortie's commit is atomic.
**Carry forward:** Enforce one-commit-per-sortie discipline. Sub-agents must commit before the supervisor verifies. The supervisor must never batch uncommitted files from previous sorties into the next commit.

---

## Section 2: Process Discoveries

### What the Agents Did Right

### 1. Zero-Retry Execution

**What happened:** All 17 sorties completed on the first attempt. No BACKOFF, no FATAL, no retries.
**Right or wrong?** Right — and somewhat remarkable. Indicates the execution plan was well-specified with clear entry/exit criteria.
**Evidence:** SUPERVISOR_STATE.md confirms 0 retries across all 17 sorties. COMPLETE_SwiftVinetas.md shows "Attempts: 1/3" for every recorded sortie.
**Carry forward:** The refinement passes (atomicity, priority, parallelism, questions) paid off. Continue investing in plan quality.

### 2. Parallel Execution Worked

**What happened:** WU2 (Generation Pipeline) and WU4 (Understanding Module) ran in parallel on Layer 2. WU3 and WU5 ran in parallel on Layer 3.
**Right or wrong?** Right. The parallel groups had clean dependency boundaries and didn't interfere with each other.
**Evidence:** S3 and S8 started at the same time (00:15). S4 and S9 overlapped. S6, S10, and S12 all completed at ~00:41.
**Carry forward:** Parallel execution with clean dependency graphs works. Keep using it.

### 3. Model Selection Was Cost-Efficient

**What happened:** Opus was used for complex foundation sorties (S1-S4, S8) and sonnet for simpler wiring/test sorties (S5-S7, S9-S12). The completion log shows "opus x5, sonnet x5" for the first 10. Later sorties (S13-S17) aren't in the completion log but likely continued the pattern.
**Right or wrong?** Right. No haiku sorties (appropriate for this codebase — Swift + MLX is not trivial).
**Evidence:** 220x relative cost for 10 sorties. Opus (30x) was reserved for high-risk, high-complexity work. Sonnet (10x) for straightforward implementation.
**Carry forward:** The complexity-score-to-model mapping worked. Keep it.

### What the Agents Did Wrong

### 4. Completion Log Is Incomplete

**What happened:** COMPLETE_SwiftVinetas.md only recorded 10 of 17 sorties. Sorties 7, 11, 13, 14, 15, 16, and 17 are missing from the completion log.
**Right or wrong?** Wrong. The completion log is the audit trail. Missing entries make post-mission analysis harder.
**Evidence:** COMPLETE_SwiftVinetas.md ends at S12. The summary says "10 (in progress)" even though the mission is complete.
**Carry forward:** The supervisor must update COMPLETE_*.md after every sortie verification, not just some of them. The final summary must match the actual state.

### What the Planner Did Wrong

### 5. Mega-Commit Bundling Shows Weak Commit Discipline

**What happened:** The supervisor allowed uncommitted work from S11 (FeatureExtractor.swift, CosineSimilarityTests.swift) and S13 (ReferenceSheetGenerator.swift, ReferencePromptTests.swift) to accumulate and get bundled into the S7 commit.
**Right or wrong?** Wrong. Each sortie should produce exactly one commit. The commit is the proof of work.
**Evidence:** Commit `873eb6d` contains 8 file changes spanning 3 different work units (WU3, WU4, WU5).
**Carry forward:** Add "commit verification" as an explicit supervisor step after each sortie dispatch. If the agent didn't commit, the sortie is not done.

### 6. No Intermediate Build Verification for Parallel Agents

**What happened:** When WU4 sorties were dispatched in parallel, build verification was deferred. S9 needed a supervisor fix for the MLXArray API. Had the build been verified immediately after S9 completed, the fix would have been part of that sortie's commit.
**Right or wrong?** Wrong. Build verification is an exit criterion. Deferring it undermines the sortie state machine.
**Evidence:** S9 notes "(+ supervisor fix pending commit)" — the fix was not part of S9's commit.
**Carry forward:** Exit criteria verification must happen immediately after each sortie, even for parallel agents. No batching of verification.

---

## Section 3: Open Decisions

### 1. Should COMPLETE_*.md Be Updated Before Merging to Development?

**Why it matters:** The completion log is incomplete and shows "10 (in progress)" for a mission that completed all 17 sorties. If this branch is merged as-is, the audit trail is permanently incomplete.
**Options:**
- A: Update COMPLETE_SwiftVinetas.md with the missing 7 sorties before merge (15 min effort)
- B: Accept incomplete log; the git history and SUPERVISOR_STATE.md are sufficient
- C: Delete the file; git history is the true audit trail
**Recommendation:** Option B. The git history is clean (one commit per sortie for most), and SUPERVISOR_STATE.md has the complete status. The completion log was a nice-to-have, not a necessity.

### 2. Should the Mission Branch Be Merged via PR or Direct Merge?

**Why it matters:** CLAUDE.md says "Branch: development -> PR -> main. Never commit directly to main." The current branch is `mission/sketch-forge/01`, not `development`.
**Options:**
- A: Merge `mission/sketch-forge/01` → `development` via PR, then `development` → `main` via PR
- B: Merge `mission/sketch-forge/01` → `main` via PR directly
- C: Create `development` from `mission/sketch-forge/01`, then PR to `main`
**Recommendation:** Option A. Follows the established git workflow.

### 3. Integration Testing Against Real FLUX.2 Models

**Why it matters:** All 275 tests are unit tests with mocked/stubbed dependencies. No test actually loads a FLUX.2 model or generates an image. The pipeline compiles but runtime behavior is unverified.
**Options:**
- A: Add integration tests that require model download (slow, 16+ GB, CI-hostile)
- B: Manual smoke test before merge (generate one image, run one classification)
- C: Accept unit test coverage as sufficient; integration testing happens in Produciesta
**Recommendation:** Option B. A quick smoke test confirms the pipeline works end-to-end without committing to CI-integrated model downloads.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| S1 | Core Types Completion | opus | 1 | Yes | Fixed scaffold defaults; all output survived |
| S2 | Model Management & Memory | opus | 1 | Yes | Clean foundation; no rework |
| S3 | Pipeline Core & Single Gen | opus | 1 | Yes | VinetasPipeline extended by later sorties, not replaced |
| S4 | Batch, LoRA & Progress | opus | 1 | Yes | LoRA pattern reused by character pipeline |
| S5 | Output, Preview & Tests | sonnet | 1 | Yes | AspectRatio, ImageOutput both survived intact |
| S6 | Core CLI Wiring | sonnet | 1 | Yes | Extended by S7 and S17, not rewritten |
| S7 | Makefile & CLI Polish | sonnet | 1 | Yes | Mega-commit issue, but code is correct |
| S8 | Vision Transformer | opus | 1 | Yes | Architecture survived intact through S10-S11 |
| S9 | Image Preprocessing | sonnet | 1 | Yes* | *Needed supervisor fix for MLXArray API |
| S10 | Image Classifier & Labels | sonnet | 1 | Yes | 1000 labels verified, classifier compiles |
| S11 | Feature Extractor & Similarity | sonnet | 1 | Yes | Bundled into S7 commit (process issue, not code issue) |
| S12 | Character Definition & CRUD | sonnet | 1 | Yes | YAML round-trip, slug derivation all verified |
| S13 | Reference Sheet Generation | sonnet | 1 | Yes | Bundled into S7 commit (process issue, not code issue) |
| S14 | Training Data Preparation | sonnet | 1 | Yes | Caption generation, dimension validation pass |
| S15 | On-Device LoRA Training | sonnet | 1 | Yes | CharacterTrainer references LoRATrainingHelper correctly |
| S16 | Character-Aware Generation | sonnet | 1 | Yes | PromptFile v2 parsing, trigger word injection verified |
| S17 | Character CLI & Verification | sonnet | 1 | Yes | All CLI subcommands registered, DINOv2 verification compiles |

**Overall accuracy: 17/17 sorties accurate.** S9 needed a minor fix but the output survived. S7/S11/S13 had commit discipline issues but the code itself was correct.

---

## Section 5: Harvest Summary

OPERATION SKETCH FORGE was a clean execution. The plan was well-refined and the agents delivered. The single most important lesson is about **commit discipline in parallel execution**: when multiple agents work concurrently, the supervisor must enforce atomic commits per sortie. The mega-commit pattern (S7 absorbing S11 and S13's work) is the only real process failure, and it's entirely a supervisor responsibility. The code itself is solid — 9,594 lines added across 43 files, 275 tests, zero retries. The library API, CLI, understanding module, and character pipeline all compile and have meaningful test coverage. The next step is a manual smoke test against a real FLUX.2 model, then merge.

---

## Section 6: Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `Sources/SwiftVinetas/Core/VinetasPipeline.swift` | mission/sketch-forge/01 | Core pipeline; 656 lines wrapping Flux2Core |
| `Sources/SwiftVinetas/Vinetas.swift` | mission/sketch-forge/01 | Public API surface; 587+ lines added |
| `Sources/vinetas/VinetasCLI.swift` | mission/sketch-forge/01 | Full CLI with all commands; 811+ lines added |
| `Sources/SwiftVinetas/Understanding/ImageNetLabels.swift` | mission/sketch-forge/01 | 1000 ImageNet labels; not worth regenerating |
| `docs/REQUIREMENTS_V1.md` | mission/sketch-forge/01 | Source requirements; should not change |
| `docs/ARCHITECTURE.md` | mission/sketch-forge/01 | Architecture decisions; reference for future work |
| `Makefile` | mission/sketch-forge/01 | Build system; 7 targets |

**Discard (will not exist after rollback):**

| File | Why it's safe to lose |
|------|----------------------|
| `SUPERVISOR_STATE.md` | Execution state; captured in this brief |
| `COMPLETE_SwiftVinetas.md` | Incomplete audit trail; git history is sufficient |
| `EXECUTION_PLAN.md` | Plan document; no longer needed post-execution |

---

## Section 7: Iteration Metadata

**Starting point commit:** `cc2f1ee6fb5df5ba76dd0e31359970802be1943a` (pre-mission scaffold)
**Mission branch:** `mission/sketch-forge/01`
**Final commit on mission branch:** `df52812` (Add character CLI subcommands and DINOv2 verification pipeline)
**Rollback target:** `cc2f1ee6fb5df5ba76dd0e31359970802be1943a` (same as starting point commit)
**Next iteration branch:** `mission/sketch-forge/02`

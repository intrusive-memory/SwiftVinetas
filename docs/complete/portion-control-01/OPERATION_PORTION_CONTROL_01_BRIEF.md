---
feature_name: OPERATION PORTION CONTROL
mission_branch: mission/portion-control/01
iteration: 1
state: completed
---

# Iteration 01 Brief — Operation Portion Control

**Mission:** Give MLX a real per-process memory ceiling on iOS so it self-throttles during PixArt generation instead of spiking past the jetsam cap and getting OOM-killed.
**Branch:** mission/portion-control/01
**Starting Point Commit:** f62c460 (Mark development as 0.15.2-dev, restore sibling pattern)
**Sorties Planned:** 2
**Sorties Completed:** 2
**Sorties Failed/Blocked:** 0
**Duration:** ~21 min wall clock across both sorties (Sortie 1 ≈19 min incl. fresh dep download; Sortie 2 ≈1.5 min). Cost: 1 sonnet + 1 haiku + 1 haiku cleanup.
**Outcome:** Complete
**Verdict:** `KEEP` — All sorties completed first-attempt with green build/test gates; the single hard discovery (MLX crashes on the iOS Simulator) is already correctly handled by a platform guard, leaving only a documented follow-up coverage gap.
**Tests pruned:** 0
**Tests flagged for review:** 3 (device-only clamp assertions — coverage gap, not a defect)

---

## Section 1: Hard Discoveries

### 1. MLX memory-limit setters crash on the iOS Simulator

**What happened:** Setting `MLX.GPU`/`Memory` `memoryLimit` and `cacheLimit` calls into the Metal C++ runtime (`mlx_set_memory_limit` / `mlx_set_cache_limit`), which constructs a `std::string` from the Metal device name. On the iOS Simulator the default Metal device is nil for this path, producing a `basic_string(const char*)` nullptr crash. This is exactly where `make test-unit-ios` runs.
**What was built to handle it:** The new clamp-assertion tests in `VinetasMemoryTests.swift` are fenced `#if os(iOS) && !targetEnvironment(simulator)`, so they compile everywhere, no-op on the macOS host, and only execute the assignment+assertion path on a real Apple Silicon iOS device. Production code is unaffected — a real device initializes Metal correctly.
**Should we have known this?** Partially. The plan's OQ-3 resolution assumed the iOS Simulator would exercise the clamp ("setting memoryLimit/cacheLimit is a plain static assignment requiring no device or GPU"). That assumption was wrong — the setter is not a plain assignment; it reaches into Metal. A quick check of MLX's `set_memory_limit` implementation would have revealed it.
**Carry forward:** Any test that sets MLX memory/cache limits must be guarded `!targetEnvironment(simulator)`. CI on the simulator can verify the *build* of MLX-memory code but never its *runtime values*; value assertions require a physical-device test lane.

### 2. Pre-existing iOS compile breakage in the GPU test target

**What happened:** Two GPU test files (`AllModelsExampleTests.swift`, `PixArtGarbageReproTests.swift`) used `FileManager.homeDirectoryForCurrentUser`, which does not exist on iOS, so the iOS test target would not compile — independent of this mission's feature. Sortie 1 had to fix this to satisfy its `make test-unit-ios` / `make build` gate.
**What was built to handle it:** Wrapped the `homeDirectoryForCurrentUser` usages in `#if os(macOS)`.
**Should we have known this?** No — it was latent breakage in a target the plan didn't anticipate touching, surfaced only because this mission was the first to drive an iOS build of the test tree.
**Carry forward:** The iOS test target was not previously build-clean. Worth a follow-up to confirm `make test-unit-ios` is wired into CI so this doesn't regress.

---

## Section 2: Process Discoveries

#### What the Agents Did Right
- **Sortie 1 (sonnet) verified the real MLX API instead of trusting the plan's symbol names.** The plan guessed `MLX.Memory.memoryLimit/.cacheLimit/.clearCache()`; the agent was told to confirm against the resolved package and did, producing working code with proper snapshot/restore of the process-global statics in teardown.
- **Sortie 1 correctly diagnosed the simulator crash and chose a guard over a hack.** It did not disable the feature or fake the test; it gated the assertion to where it can legitimately run and documented why.
- **Sortie 2 (haiku) anchored on code structure, not the plan's line numbers,** and landed all four call sites exactly (PixArt configure@214 / release@247 / defer-release@312, Flux2 configure@183).

#### What the Agents Did Wrong
- Nothing material. Sortie 1's scope quietly expanded to include the two GPU-test compile fixes — necessary for the build gate, but it means the mission diff touches files outside the plan's stated edit list. Acceptable, but worth noting the diff is slightly wider than planned.

#### What the Planner Did Wrong
- **OQ-3's core assumption was false.** The plan asserted the simulator could exercise the clamp because the setters are "plain static assignment." They are not. This is the one planning miss, and it cost nothing because the agent caught it — but a future MLX-memory plan should not repeat the "it's just a static, the simulator will run it" assumption.
- **The plan did not anticipate the iOS test target being build-broken.** It scoped only `VinetasMemory` + engine files; the iOS build pulled in GPU test files that didn't compile. Minor, self-healing, but unplanned.

---

## Section 3: Open Decisions

### 1. How do we get runtime coverage of the clamp values?
**Why it matters:** The three `budgetClamp*` assertions never run in CI. We are shipping a memory-ceiling feature whose actual clamp arithmetic (`Int(Double(available) * 0.8)`, 32 MiB cache) is verified only on a developer's physical device, if at all.
**Options:**
- A) Accept the gap; rely on the macOS `processAvailableMemoryBytesIsNilOnMacOS` test + manual device verification. (cheapest)
- B) Add a physical-device test lane to CI (Xcode Cloud / self-hosted). (real coverage, real cost)
- C) Refactor the clamp arithmetic into a pure, device-free function and unit-test *that* on the simulator, leaving only the MLX setter call device-gated. (best ROI — tests the math everywhere, isolates the un-testable Metal call)
**Recommendation:** C. Extract the budget computation from the MLX side-effect so the interesting logic is simulator/host-testable; keep only the actual `MLX` setter behind the device guard.

### 2. Is `make test-unit-ios` in CI?
**Why it matters:** Hard Discovery #2 shows the iOS test target had been silently un-buildable. If CI doesn't run the iOS build, this will rot again.
**Recommendation:** Confirm the iOS unit lane is a required check; if not, add it.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Add iOS MLX budget API to `VinetasMemory` + CI-safe tests | sonnet | 1 | Yes | Survived intact. Correctly chose to verify the MLX API and to device-gate the crash-prone tests. Scope grew by 2 GPU-test compile fixes (justified). |
| 2 | Wire budget into PixArt/Flux2 load/unload/generate | haiku | 1 | Yes | All four call sites correct on first attempt; haiku was the right (cheap) call for a line-anchored, machine-verifiable edit. |

Model selection was accurate: no sortie was upgraded on retry, and the cheap haiku call on the mechanical wiring sortie paid off.

## Section 5: Harvest Summary

The feature shipped cleanly and the API/engine wiring is sound. The one thing that changes for next time: **MLX memory APIs are not simulator-safe and their value-level behavior cannot be asserted in CI without a physical-device lane.** The highest-value follow-up is to extract the budget arithmetic into a pure function so the math is testable on host/simulator, quarantining only the unavoidable Metal setter behind the device guard. Test cleanup pruned nothing (0%) — a healthy signal that the agents wrote CI-safe tests; the only flags are the three intentional device-only assertions, which point at the coverage gap above rather than at sloppy test hygiene.

## Section 6: Files

**Preserve (read-only reference for next iteration):**
| File | Branch | Why |
|------|--------|-----|
| Sources/SwiftVinetas/Core/VinetasMemory.swift | mission/portion-control/01 | The budget API — foundation for the feature. |
| Sources/SwiftVinetas/Engine/PixArtEngine.swift | mission/portion-control/01 | Configure/release wiring. |
| Sources/SwiftVinetas/Engine/Flux2Engine.swift | mission/portion-control/01 | Symmetry configure call. |
| Tests/SwiftVinetasTests/VinetasMemoryTests.swift | mission/portion-control/01 | Clamp tests (1 host-safe, 3 device-only) + the pattern for the proposed pure-function refactor. |
| TEST_CLEANUP_REPORT.md | mission/portion-control/01 | Records the coverage gap. |

**Discard (will not exist after rollback):**
| File | Why it's safe to lose |
|------|----------------------|
| (none — verdict is KEEP; nothing to discard) | — |

## Iteration Metadata

**Starting point commit:** `f62c460` (Mark development as 0.15.2-dev, restore sibling pattern)
**Mission branch:** `mission/portion-control/01`
**Final commit on mission branch:** `8d470a5` (test-cleanup report-only)
**Rollback target:** `f62c460` (same as starting point commit)
**Next iteration branch:** `mission/portion-control/02` (only if a follow-up iteration is opened)

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** Both sorties completed on the first attempt with green `make build`, `make test-unit`, and `make test-unit-ios` gates (Section 4); test-cleanup removed 0% of mission tests (Section 5); and the single hard discovery — MLX crashing on the iOS Simulator (Section 1.1) — was correctly handled in-mission with a platform guard rather than a hack. This meets every `KEEP` signal. The remaining item is a documented coverage gap (Open Decision 1), which is follow-up work, not a reason to discard a sound foundation.

**Recommended action:** Merge the mission branch (`mission/portion-control/01`) into `development` via the normal flow. File two follow-up tickets: (1) extract the budget arithmetic into a pure, simulator-testable function to close the clamp-value coverage gap (Open Decision 1, recommended option C); (2) confirm `make test-unit-ios` is a required CI check (Open Decision 2). Do **not** version-bump or tag here — the requirements doc forbids it; use the normal `ship-swift-library` flow later.

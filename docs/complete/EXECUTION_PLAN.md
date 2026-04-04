---
feature_name: OPERATION PLATOON INSIGNIA
starting_point_commit: 44fcd889bea7dc2b3505be5b233de877ce96cea9
mission_branch: mission/platoon-insignia/02
iteration: 2
---

# EXECUTION_PLAN.md — SwiftVinetas Test Plan Reorganization

**Source**: [docs/TEST_PLAN_REQUIREMENTS.md](docs/TEST_PLAN_REQUIREMENTS.md)
**Status**: REFINED — ready for execution

---

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure. Unlike an agile "sprint" (which maps to time), a mission maps to agentic cycles — which have no defined relationship to time.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return. Has defined objective, machine-verifiable entry/exit criteria, and bounded scope.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|--------------|
| Test Plan Reorganization | `/` (project root) | 5 | 1–4 | none |

This is a single work unit — all changes happen within the same repository and are tightly coupled through the test infrastructure.

---

## Sortie 1: Tag Taxonomy and Shared Test Helpers

**Priority**: 16.0 — Foundation sortie; blocks all 4 downstream sorties. Establishes tags and helpers reused by Sorties 2, 3, 4, and 5.

**Goal**: Establish the foundation that all subsequent integration tests and test plan configuration depend on — new Swift Testing tags and reusable validation helpers.

**Entry criteria**:
- [ ] First sortie — no prerequisites

**Tasks**:
1. Create a shared tag definition file at `Tests/SwiftVinetasGPUTests/TestTags.swift` with the four standardized tags (`.integration`, `.gpu`, `.flux2`, `.pixart`). Remove the existing tag definitions from `BatchIntegrationTests.swift` (currently defined as `extension Tag { @Tag static var integration: Self; @Tag static var gpu: Self }` near the top of that file) so there is one canonical location.
2. Update existing `BatchIntegrationTests.swift` to import tags from the shared file and add `.flux2` tag to FLUX.2-specific tests (the `generateBatchFromFixture` and `cliBatchWritesPNGs` tests that use `VinetasModel.klein4b`).
3. Update existing `ImagePreprocessorTests.swift` to reference the shared `.gpu` tag on the `@Suite` declaration (currently has no tags).
4. Create `Tests/SwiftVinetasGPUTests/IntegrationTestHelpers.swift` with:
   - `assertImageNotGarbage(_ image: CGImage)` — samples pixels at a 5×5 grid across the image, confirms at least 16 distinct RGB values, confirms not all-black/all-white/single-color, confirms non-zero dimensions
   - `assertModelDownloaded(_ model: any ModelDescriptor)` — verifies model files exist on disk via SwiftAcervo's cache API
5. Verify the project compiles with `make build`

**Exit criteria**:
- [ ] `Tests/SwiftVinetasGPUTests/TestTags.swift` exists and contains `@Tag static var integration`, `@Tag static var gpu`, `@Tag static var flux2`, `@Tag static var pixart`
- [ ] `Tests/SwiftVinetasGPUTests/IntegrationTestHelpers.swift` exists and contains `func assertImageNotGarbage` and `func assertModelDownloaded`
- [ ] `grep -c '@Tag static var' Tests/SwiftVinetasGPUTests/BatchIntegrationTests.swift` returns 0 (no tag definitions in that file)
- [ ] `grep -l '.flux2' Tests/SwiftVinetasGPUTests/BatchIntegrationTests.swift` succeeds (`.flux2` tag is referenced)
- [ ] `make build` succeeds with exit code 0
- [ ] `make test-unit` passes with exit code 0 (no regressions)

---

## Sortie 2: Flux2 Integration Tests

**Priority**: 8.75 — Blocks Sortie 4. Standard complexity, well-understood engine.

**Goal**: Create integration tests that validate the full FLUX.2 pipeline — compilation, model download, and non-garbage image generation.

**Entry criteria**:
- [ ] `Tests/SwiftVinetasGPUTests/TestTags.swift` exists (Sortie 1 complete)
- [ ] `Tests/SwiftVinetasGPUTests/IntegrationTestHelpers.swift` exists (Sortie 1 complete)

**Tasks**:
1. Create `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` with a `@Suite("Flux2 Integration Tests", .tags(.integration, .flux2))` declaration.
2. Implement **Checkpoint 1 — Binary Compilation** test: use `Process` to invoke `xcodebuild build -scheme vinetas` and assert exit code 0, confirming the CLI binary compiles with all Metal shader dependencies. Tag: `.tags(.integration, .flux2)`.
3. Implement **Checkpoint 2 — Model Download** test: download `Flux2ModelDescriptor.klein4B` via `VinetasClient.shared`, assert no error, call `assertModelDownloaded` from helpers. Tag: `.tags(.integration, .flux2)`. Time limit: 10 minutes.
4. Implement **Checkpoint 3 — Generation Validation** test: generate a single panel with `Flux2ModelDescriptor.klein4B`, seed 42, prompt `"A red car parked on a cobblestone street"`. Assert non-zero dimensions, call `assertImageNotGarbage`, verify metadata (prompt matches, duration > 0, model ID is `"flux2"`). Tag: `.tags(.integration, .gpu, .flux2)`. Time limit: 5 minutes.
5. Verify the file compiles with `make build`

**Exit criteria**:
- [ ] `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` exists with 3 test methods
- [ ] `grep -c 'assertImageNotGarbage\|assertModelDownloaded' Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` returns ≥ 2 (download test uses `assertModelDownloaded`, generation test uses `assertImageNotGarbage`)
- [ ] Compilation test is tagged `.tags(.integration, .flux2)`, download test is tagged `.tags(.integration, .flux2)`, generation test is tagged `.tags(.integration, .gpu, .flux2)`
- [ ] `make build` succeeds with exit code 0

---

## Sortie 3: PixArt Integration Tests

**Priority**: 9.25 — Blocks Sortie 4. Slightly higher risk due to investigation task, but PixArtEngine is confirmed functional (full `ImageGenerationEngine` implementation with `loadModel`, `generate`, LoRA support, and Acervo downloads).

**Goal**: Create integration tests that validate the full PixArt-Sigma pipeline — compilation, model download, and non-garbage image generation.

**Entry criteria**:
- [ ] `Tests/SwiftVinetasGPUTests/TestTags.swift` exists (Sortie 1 complete)
- [ ] `Tests/SwiftVinetasGPUTests/IntegrationTestHelpers.swift` exists (Sortie 1 complete)

**Tasks**:
1. Confirm `PixArtEngine` is functional by reading `Sources/SwiftVinetas/Engine/PixArtEngine.swift`. **Pre-investigation note**: As of plan refinement, PixArtEngine is confirmed functional — implements `ImageGenerationEngine` protocol with `loadModel`, `generate`, `download`, and LoRA support. The agent should verify this is still true at execution time and proceed accordingly.
2. Create `Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift` with a `@Suite("PixArt Integration Tests", .tags(.integration, .pixart))` declaration.
3. Implement **Checkpoint 1 — Binary Compilation** test: same approach as Flux2 (verifies the full dependency chain compiles, including PixArtBackbone). Tag: `.tags(.integration, .pixart)`.
4. Implement **Checkpoint 2 — Model Download** test: download `PixArtModelDescriptor.sigmaXL` via `VinetasClient.shared`, assert no error, call `assertModelDownloaded`. Tag: `.tags(.integration, .pixart)`. Time limit: 10 minutes.
5. Implement **Checkpoint 3 — Generation Validation** test: generate a single panel with `PixArtModelDescriptor.sigmaXL`, seed 42, prompt `"A red car parked on a cobblestone street"` (same as Flux2 for comparability). Call `assertImageNotGarbage`, verify metadata. Tag: `.tags(.integration, .gpu, .pixart)`. Time limit: 5 minutes.
6. Verify the file compiles with `make build`

**Exit criteria**:
- [ ] `Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift` exists with 3 test methods
- [ ] If PixArtEngine is a stub (unexpected): download and generation tests are `@Test(.disabled(...))` with clear reason string
- [ ] If PixArtEngine is functional (expected): `grep -c 'assertImageNotGarbage\|assertModelDownloaded' Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift` returns ≥ 2
- [ ] Tags match pattern: compilation → `.tags(.integration, .pixart)`, download → `.tags(.integration, .pixart)`, generation → `.tags(.integration, .gpu, .pixart)`
- [ ] `make build` succeeds with exit code 0

---

## Sortie 4: Test Plan Configuration

**Priority**: 9.0 — Blocks Sortie 5. High risk due to unknown `.xctestplan` compatibility with SPM-only projects. Fallback path built in.

**Goal**: Create the three `.xctestplan` files (or equivalent `xcodebuild` filtering configuration) that partition the test suite into Unit, GPU, and Integration subsets.

**Entry criteria**:
- [ ] `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` exists (Sortie 2 complete)
- [ ] `Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift` exists (Sortie 3 complete)

**Tasks**:
1. Investigate `.xctestplan` compatibility with SPM-only projects. Run `xcodebuild test -scheme SwiftVinetas-Package -testPlan /dev/null 2>&1` or equivalent to determine if test plans are supported without a `.xcodeproj`. Document findings.
2. If `.xctestplan` is supported: create `SwiftVinetas-Unit.xctestplan` (JSON format) at project root, targeting `SwiftVinetasTests` only, all tests enabled.
3. If `.xctestplan` is supported: create `SwiftVinetas-GPU.xctestplan` targeting `SwiftVinetasGPUTests`, all tests enabled.
4. If `.xctestplan` is supported: create `SwiftVinetas-Integration.xctestplan` targeting `SwiftVinetasGPUTests`, filtered to include only tests tagged `.integration`.
5. If `.xctestplan` is NOT supported with SPM: define equivalent Makefile-based filtering using `-only-testing:` and `-skip-testing:` flags. Document the approach in a code comment in the Makefile.
6. Verify each plan/filter selects the correct test subset by running `xcodebuild test -scheme SwiftVinetas-Package -testPlan <plan> -dry-run` (if supported) or by running the filter and confirming only expected test targets/classes appear in output.

**Exit criteria**:
- [ ] **Path A** (xctestplan supported): `SwiftVinetas-Unit.xctestplan`, `SwiftVinetas-GPU.xctestplan`, `SwiftVinetas-Integration.xctestplan` exist at project root
- [ ] **Path B** (xctestplan not supported): Makefile contains documented `-only-testing:` / `-skip-testing:` equivalents with inline comments explaining the approach
- [ ] Unit plan/filter selects only `SwiftVinetasTests` target — verified by running `xcodebuild test -scheme SwiftVinetas-Package <plan-or-filter> -dry-run 2>&1 | grep 'Testing'` or equivalent
- [ ] GPU plan/filter selects only `SwiftVinetasGPUTests` target (all tests)
- [ ] Integration plan/filter selects only `.integration`-tagged tests from `SwiftVinetasGPUTests`

---

## Sortie 5: Build System, CI, and Documentation

**Priority**: 3.25 — Terminal sortie, no downstream dependents. Low risk (modifying well-understood files).

**Goal**: Wire the test plans into the Makefile, update CI to use the unit test plan, and update project documentation to reflect the new test infrastructure.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met (test plans/filters configured and validated)
- [ ] Current `Makefile` targets `test-unit`, `test-gpu`, `test`, `test-unit-ios`, `test-ios` exist

**Tasks**:
1. Update `Makefile`: change `test-unit` target to use `-testPlan SwiftVinetas-Unit` (or the equivalent filter from Sortie 4). Change `test-gpu` target to use the GPU plan. Update `test` target to run all three plans sequentially.
2. Add new Makefile target `test-integration` using the integration plan.
3. Update `test-unit-ios` and `test-ios` targets to use the unit plan for iOS Simulator.
4. Update `.github/workflows/tests.yml`: replace `-only-testing:SwiftVinetasTests` with the test plan reference (or equivalent). Verify no GPU or integration tests are referenced in CI.
5. Update `AGENTS.md`: add the new test plan files to the Package Structure section, document the new Makefile targets in the Build System section, and note that GPU/integration tests are local-only.
6. Run `make test-unit` to verify CI-equivalent path still works.
7. Run `make test-gpu` (if on Apple Silicon with models available) to verify GPU path works.

**Exit criteria**:
- [ ] `make test-unit` passes with exit code 0 using the new test plan configuration
- [ ] `grep 'test-integration' Makefile` succeeds (target exists)
- [ ] `grep -E 'testPlan|only-testing.*GPU' Makefile` confirms `test-gpu` uses the GPU plan/filter
- [ ] `grep 'test-integration\|test-gpu' Makefile | grep -c ':'` returns ≥ 2 (both targets have rules)
- [ ] `grep -L 'only-testing:SwiftVinetasTests' .github/workflows/tests.yml` succeeds (old filter removed) OR `grep 'testPlan' .github/workflows/tests.yml` succeeds (new plan added)
- [ ] `grep -c 'gpu\|GPU\|integration\|Integration' .github/workflows/tests.yml` returns 0 (no GPU/integration references in CI)
- [ ] `grep 'xctestplan\|Test Plans\|test-integration' AGENTS.md | head -3` returns matches (docs updated)

---

## Dependency Graph

```
Sortie 1 (Tags + Helpers) [Priority: 16.0]
    ├──► Sortie 2 (Flux2 Integration) [Priority: 8.75]  ──┐
    └──► Sortie 3 (PixArt Integration) [Priority: 9.25] ──┤
                                                            ▼
                                                     Sortie 4 (Test Plans) [Priority: 9.0]
                                                            │
                                                            ▼
                                                     Sortie 5 (Build/CI/Docs) [Priority: 3.25]
```

---

## Parallelism Structure

**Critical Path**: Sortie 1 → Sortie 2 → Sortie 4 → Sortie 5 (4 sorties)

**Parallel Execution Groups**:
- **Group 1** (sequential):
  - Sortie 1 (Agent 1 — **SUPERVISING AGENT**) — has build step
- **Group 2** (can run in parallel):
  - Sortie 2 (Agent 1 — **SUPERVISING AGENT**) — has build step
  - Sortie 3 (Agent 2 — **SUB-AGENT**) — code writing only; build verification by supervising agent after code is complete
- **Group 3** (sequential):
  - Sortie 4 (Agent 1 — **SUPERVISING AGENT**) — has validation/build steps
- **Group 4** (sequential):
  - Sortie 5 (Agent 1 — **SUPERVISING AGENT**) — has build steps

**Agent Constraints**:
- **Supervising agent**: Handles all sorties with `make build`, `make test-unit`, or validation commands
- **Sub-agent (1)**: Handles Sortie 3 code writing (file creation only, no build)

**Parallelism Metrics**:
- Current: 2 sorties can run simultaneously (Sorties 2 + 3)
- Maximum: 2 agents (1 supervising + 1 sub-agent)
- Build constraints: 4 of 5 sorties require build verification by supervising agent

---

## Open Questions (Resolved)

1. **Garbage detection threshold**: Use N ≥ 16 distinct colors sampled from a 5×5 grid. Tune if flaky. **Status**: Decided.
2. **PixArt model availability**: PixArtEngine is **fully functional** — confirmed via source review. Implements `ImageGenerationEngine` protocol with `loadModel`, `generate`, `download`, and LoRA support. `PixArtModelDescriptor.sigmaXL` is defined with 3 Acervo components (t5-xxl-encoder-int4, pixart-sigma-xl-dit-int4, sdxl-vae-decoder-fp16). **Status**: Resolved — all tests should be enabled (not disabled).
3. **Test plan format**: Sortie 4 Task 1 investigates SPM compatibility at execution time. Fallback to `-only-testing:` filters is built into the plan. **Status**: Deferred to execution (investigation required).
4. **Shared prompt fixture**: Use `"A red car parked on a cobblestone street"` inline. No YAML fixture needed. **Status**: Decided.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 5 |
| Parallelizable sorties | 2 (Sorties 2 and 3) |
| Dependency structure | 4 layers (1 → 2∥3 → 4 → 5) |
| Critical path length | 4 sorties |
| Agent allocation | 1 supervising + 1 sub-agent |
| Average sortie size | ~21 turns (budget: 50) |
| Context budget utilization | 30%–52% per sortie |

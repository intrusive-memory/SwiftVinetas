---
feature_name: OPERATION SENTINEL CANVAS
starting_point_commit: 6f64e3575650c0e9d33f83d5585be25501f8bf58
mission_branch: mission/sentinel-canvas/1
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVinetas Test Coverage

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Context: Current State vs. Requirements

This plan was generated after auditing the live codebase against `TESTING_REQUIREMENTS.md`. Most of §4 is already covered. The following sections are **already satisfied** — agents must not re-implement them:

| Section | Status | Covered By |
|---------|--------|-----------|
| §4b Engine Router | DONE | `EngineRouterTests.swift` |
| §4c Engine Descriptors | DONE | `Flux2EngineTests.swift`, `PixArtEngineTests.swift` |
| §4d Generation Request & Style Mapping | DONE | `GenerationRequestTests.swift`, `RequestTranslationTests.swift`, `StyleConfigTests.swift` |
| §4e PromptFile Parsing | DONE | `PromptFileTests.swift` |
| §4f Character Management (slug, LoRAMetadata, CharacterManager I/O) | DONE | `CharacterTests.swift`, `LoRACompatibilityTests.swift` |
| §4g Prompt Composition | DONE | `PromptCompositionTests.swift`, `CharacterPromptTests.swift`, `ReferencePromptTests.swift` |
| §4h LoRA Compatibility | DONE | `LoRACompatibilityTests.swift` |
| §4i Aspect Ratio | DONE | `AspectRatioTests.swift` |
| §4j Memory Validation (.ok/.warning/.insufficient) | DONE | `GenerationRequestTests.swift` |
| §4k Model Manager | DONE | `VinetasModelManagerTests.swift` |
| §4l Image Classification | DONE | `ClassificationTests.swift`, `ImageNetLabelsTests.swift` |
| §4m Image Output | DONE | `ImageOutputTests.swift` |
| §5b Flux2Engine integration (download, generate, non-garbage) | DONE | `Flux2IntegrationTests.swift` |
| §5c PixArtEngine integration (download, generate, feature gate) | DONE | `PixArtIntegrationTests.swift` |
| §5d generateSequence end-to-end (batch fixture) | DONE | `BatchIntegrationTests.swift` |

The plan addresses only the **remaining gaps**.

---

## Codebase Facts (Verified — Do Not Assume)

These facts were verified against the live codebase before refinement. Agents MUST read the referenced files before writing tests to confirm these are still current.

| Fact | Value | Source |
|------|-------|--------|
| `Flux2ModelDescriptor.klein4B.id` | `"flux2-klein-4b"` | `Sources/SwiftVinetas/Engine/Flux2Engine.swift` |
| `VinetasClient.preview()` routes via | `router.engine(forEngineID: "flux2")` then `engine.loadModel(previewModel, ...)` | `Sources/SwiftVinetas/Vinetas.swift` |
| `MockEngine.supports(.loraInference)` | Returns `false` (hardcoded, not driven by `supportedFeatures` property) | `Tests/SwiftVinetasTests/MockEngine.swift` |
| `SwiftVinetasTests` target dependencies | `SwiftVinetas` only — no `vinetas` CLI target | `Package.swift` |
| CLI module `vinetas` importable via `@testable` | **NO** — `vinetas` is an `.executableTarget` and not in `SwiftVinetasTests` dependencies | `Package.swift` |
| `CharacterCommand.Create` options | `@Argument var name`, `@Option var photo`, `@Option var description` — **no** `--trigger-word` option | `Sources/vinetas/VinetasCLI.swift` |
| `VinetasLoRAManager.load(path:scale:on:)` | Validates file exists via `FileManager.default.fileExists` before calling `engine.loadLoRA` — requires a real file or bypass | `Sources/SwiftVinetas/Core/LoRAManager.swift` |
| `.github/workflows/tests.yml` | Already exists with job key `unit-tests`, runner `macos-26`, step `make test-unit` | `.github/workflows/tests.yml` |

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Priority | Dependencies |
|-----------|-----------|---------|-------|----------|-------------|
| A: VinetasClient Unit Tests | `Tests/SwiftVinetasTests/` | 2 | 1 | High (9.5 / 4.5) | none |
| B: VinetasError Descriptions | `Tests/SwiftVinetasTests/` | 1 | 1 | Low (1.5) | none |
| C: CLI Argument Parsing Tests | `Tests/SwiftVinetasTests/` | 2 | 1 | Medium (4.5 / 1.5) | none |
| D: LoRAManager Sequencing Tests | `Tests/SwiftVinetasTests/` | 1 | 1 | Low (1.5) | none |
| E: Concurrent Client Stress Test | `Tests/SwiftVinetasTests/` | 1 | 2 | Medium (3.0) | A |
| F: GPU Determinism & Memory Tests | `Tests/SwiftVinetasGPUTests/` | 1 | 1 | Medium (4.0) | none |
| G: CI Workflow (unit-tests status check) | `.github/workflows/` | 1 | 3 | Low (2.5) | A, B, C, D, E |

Priority scores: `(dependency_depth * 3) + (foundation_score * 2) + (risk_level * 1) + (complexity * 0.5)`

---

## Parallelism Structure

**Critical Path**: A-1 → A-2 → E-1 → G-1 (4 sorties)

**Parallel Execution Groups**:
- **Group 1** (can all start immediately):
  - Work Unit A: Sortie A-1 (Supervising Agent — has `make test-unit` verification)
  - Work Unit B: Sortie B-1 (Sub-agent 1 — code only; supervising agent verifies with `make test-unit`)
  - Work Unit C: Sortie C-1 (Sub-agent 2 — code only; supervising agent verifies)
  - Work Unit D: Sortie D-1 (Sub-agent 3 — code only; supervising agent verifies)
  - Work Unit F: Sortie F-1 (Sub-agent 4 — code only; `make test-gpu` requires local GPU, not CI)
- **Group 2** (after Group 1 prerequisites complete):
  - Work Unit A: Sortie A-2 (after A-1) — Supervising Agent
  - Work Unit C: Sortie C-2 (after C-1) — Sub-agent 2
- **Group 3** (after A-1 and A-2 complete):
  - Work Unit E: Sortie E-1 — Supervising Agent
- **Group 4** (after A+B+C+D+E all complete):
  - Work Unit G: Sortie G-1 — Supervising Agent

**Agent Constraints**:
- **Supervising agent**: Handles all sorties with `make test-unit` or `make test-gpu` build/test steps
- **Sub-agents (up to 4)**: Handle file creation only. Sub-agents must NOT run `make` commands. The supervising agent runs verification after merging sub-agent output.

---

## Work Unit A: VinetasClient Unit Tests

**Goal**: Cover the `VinetasClient` behaviors from §4a that are not yet tested. `LoRACompatibilityTests.swift` already covers the LoRA load/unload path and incompatibility error path via `VinetasClient`. The remaining gaps are: routing to correct engine, whitespace prompt validation, `generateSequence()` callbacks, `preview()` engine routing, `isAvailable()` delegation, and `validateMemory()` delegation.

### Sortie A-1: VinetasClient Core Routing and Validation Tests

**Priority**: 9.5 — Highest in plan. Blocks A-2 and E-1. Establishes test patterns reused across work unit.

**Entry criteria**:
- [ ] First sortie in Work Unit A — no prerequisites
- [ ] `Tests/SwiftVinetasTests/MockEngine.swift` exists and compiles (confirmed)
- [ ] `Sources/SwiftVinetas/Vinetas.swift` is readable for API surface reference

**Tasks**:
1. Create `Tests/SwiftVinetasTests/VinetasClientTests.swift` with `@Suite("VinetasClient")` using `import Testing` and `@testable import SwiftVinetas`. Do NOT import Metal, MLX, CoreML, or Accelerate.
2. Write `@Test func generateRoutesToCorrectEngine()`: construct a `MockEngine` (default `engineID: "mock"`), create a `MockModelDescriptor(id: "mock-model", engineID: "mock")`, wrap both in `EngineRouter(engines: [engine])`, inject into `VinetasClient(router:)`, call `client.generate(prompt: "test", model: mockDescriptor)`, assert `await engine.calls` contains `.loadModel("mock-model")` and `.generate("test")`.
3. Write `@Test func generateWithWhitespaceOnlyPromptThrows()`: call `client.generate(prompt: "   ", model: mockDescriptor)` using `await #expect(throws: VinetasError.self)` to confirm an error is thrown. First check `Vinetas.swift` — if no whitespace guard exists before the engine call, add a guard that trims and checks for empty, throwing `.generationFailed("Prompt must not be empty")`. **Only modify production code if the guard is genuinely absent.**
4. Write `@Test func isAvailableDelegatesToEngine()`: set `engine.isAvailableResult = true` (the `nonisolated(unsafe)` property on MockEngine), call `try await client.isAvailable(mockDescriptor)`, assert result is `true`. Repeat with `false`.
5. Write `@Test func validateMemoryDelegatesToEngine()`: set `engine.validateMemoryResult = .ok`, call `try await client.validateMemory(for: mockDescriptor)`, assert result is `.ok`. Repeat with `.insufficient(required: 16*1_073_741_824, available: 8*1_073_741_824)`.
6. Write `@Test func previewRoutesToFlux2Engine()`: construct a `MockEngine(engineID: "flux2", supportedModels: [Flux2ModelDescriptor.klein4B])`, create `EngineRouter(engines: [flux2Engine])`, inject into `VinetasClient(router:)`, call `client.preview(prompt: "test")`, assert `await flux2Engine.calls` contains `.loadModel("flux2-klein-4b")`. (Verified: `Flux2ModelDescriptor.klein4B.id == "flux2-klein-4b"` and `preview()` calls `engine.loadModel(previewModel, ...)` where `previewModel = Flux2ModelDescriptor.klein4B`.)

**Exit criteria**:
- [ ] `Tests/SwiftVinetasTests/VinetasClientTests.swift` exists
- [ ] `make test-unit` passes with all 5 tests in `VinetasClientTests` green (command: `cd /Users/stovak/Projects/SwiftVinetas && make test-unit`)
- [ ] `grep -E "import (Metal|MLX|CoreML|Accelerate)" Tests/SwiftVinetasTests/VinetasClientTests.swift` returns no output
- [ ] No `run()` calls, no real model downloads in any test

### Sortie A-2: VinetasClient generateSequence Callback Ordering Tests

**Priority**: 4.5 — Unblocks E-1.

**Entry criteria**:
- [ ] Sortie A-1 is COMPLETED (`Tests/SwiftVinetasTests/VinetasClientTests.swift` exists and `make test-unit` passes)

**Tasks**:
1. Add a `@Suite("VinetasClient.generateSequence")` extension (or nested suite) to `VinetasClientTests.swift`.
2. Write `@Test func generateSequenceCallsEngineOncePerPrompt()`: call `client.generateSequence(prompts: ["a", "b", "c"])`, assert `await engine.calls.filter({ if case .generate = $0 { return true }; return false }).count == 3`.
3. Write `@Test func generateSequenceDeliversPanelProgressCallbacks()`: collect `(current, total)` tuples from the `progress:` callback into an array; after completion assert the array equals `[(1,3), (2,3), (3,3)]` in order.
4. Write `@Test func generateSequenceDeliversStepProgressCallbacks()`: configure `MockEngine.generateResult` to fire 4 step callbacks (mock this by providing a custom `stepProgress` handler that the mock fires 4 times — note: `MockEngine.generate(request:stepProgress:)` currently does NOT call `stepProgress`; add `stepProgress?(1, 4, 0.25)` through `stepProgress?(4, 4, 1.0)` calls to `MockEngine.generate()` IF they are absent. Only touch `MockEngine.swift` if the step callbacks are genuinely not fired). Collect `(step, totalSteps)` tuples; assert 4 callbacks arrive per generation with step values 1–4.
5. Write `@Test func generateSequenceWithEmptyPromptsReturnsEmptyArray()`: call `client.generateSequence(prompts: [])`, assert result is `[]` and `await engine.calls` is empty.

**Exit criteria**:
- [ ] `generateSequence` tests added to `VinetasClientTests.swift`
- [ ] `make test-unit` passes with all 4 new tests green
- [ ] Panel progress callback assertion uses `==` comparison on the full ordered array (not just count)
- [ ] Step progress callback assertion verifies step values increment from 1 to 4

---

## Work Unit B: VinetasError Descriptions

**Goal**: Cover §4n — all `VinetasError` cases must have non-nil `localizedDescription` containing contextually relevant information.

### Sortie B-1: VinetasError localizedDescription Parameterized Tests

**Priority**: 1.5

**Entry criteria**:
- [ ] First sortie in Work Unit B — no prerequisites
- [ ] `Sources/SwiftVinetas/Core/VinetasError.swift` is readable (9 enum cases confirmed)

**Tasks**:
1. Create `Tests/SwiftVinetasTests/VinetasErrorTests.swift` with `@Suite("VinetasError")`.
2. For each of the 9 `VinetasError` cases, write a test (parameterized or individual) that constructs the error, asserts `error.localizedDescription != nil`, and asserts the description contains the context-specific value listed below:
   - `.modelNotFound("test-model")` — description contains `"test-model"`
   - `.insufficientMemory(required: 16*1_073_741_824, available: 8*1_073_741_824)` — description contains `"16"` and `"8"` (verified: error formats as GB integers)
   - `.generationFailed("out of memory")` — description contains `"out of memory"`
   - `.invalidPromptFile(URL(fileURLWithPath: "/tmp/bad.yaml"))` — description contains `"/tmp/bad.yaml"` or `"bad.yaml"`
   - `.downloadFailed("network timeout")` — description contains `"network timeout"`
   - `.engineNotFound(engineID: "flux2")` — description contains `"flux2"`
   - `.modelNotSupported(modelID: "flux2-klein-4b", engineID: "pixart-sigma")` — description contains `"flux2-klein-4b"` and `"pixart-sigma"`
   - `.loraIncompatible(loraEngine: "flux2", currentEngine: "pixart-sigma")` — description contains `"flux2"` and `"pixart-sigma"`
   - `.engineFeatureUnsupported(feature: .imageToImage, engineID: "flux2")` — description contains `"flux2"`

**Exit criteria**:
- [ ] `Tests/SwiftVinetasTests/VinetasErrorTests.swift` exists
- [ ] All 9 error cases have at least one test
- [ ] `make test-unit` passes with all `VinetasErrorTests` green
- [ ] Each test asserts both `error.localizedDescription != nil` AND substring presence via `#expect(desc.contains("..."))`

---

## Work Unit C: CLI Argument Parsing Tests

**Goal**: Cover §7 gap #3 — `VinetasCLI` subcommand argument parsing has no tests. Test only argument parsing logic, not `run()` bodies.

**CRITICAL CONSTRAINT — Read Before Starting**: `vinetas` is an `.executableTarget` in `Package.swift` and is NOT a dependency of `SwiftVinetasTests`. `@testable import vinetas` will fail at compile time. The solution is to add `vinetas` as a dependency of `SwiftVinetasTests` in `Package.swift`. However, executable targets cannot be imported as modules in Swift. The agent MUST first verify whether ArgumentParser commands can be parsed when the types are defined in an executable target.

**Recommended approach**: Before writing any tests, check if `VinetasCLI.swift` can be moved to a `VinetasCLICore` library target (shared by `vinetas` executable and `SwiftVinetasTests`), OR confirm that `@testable import` of executables works in Swift 6.2. If neither is viable, pivot to testing the underlying `SwiftVinetas` types that back the CLI options (e.g., `VinetasModel`, `AspectRatio`) rather than the CLI structs themselves.

### Sortie C-1: Core Subcommand Argument Parsing (generate, batch, list, info, preview)

**Priority**: 4.5

**Entry criteria**:
- [ ] First sortie in Work Unit C — no prerequisites
- [ ] `Sources/vinetas/VinetasCLI.swift` is readable for argument definitions
- [ ] `Package.swift` is readable to understand target dependency structure

**Tasks**:
1. Read `Package.swift` and `Sources/vinetas/VinetasCLI.swift`. Determine if `@testable import vinetas` is viable:
   - Option A: If Swift 6.2 allows `@testable import` of executables in SPM test targets with the executable added as a dependency, add `vinetas` to `SwiftVinetasTests` dependencies in `Package.swift` and proceed.
   - Option B: If not viable, create a new `VinetasCLICore` library target in `Package.swift` containing all CLI command structs (moved from `vinetas/VinetasCLI.swift`), make `vinetas` depend on `VinetasCLICore`, add `VinetasCLICore` to `SwiftVinetasTests` dependencies, then write tests against `VinetasCLICore` types.
   - Option C (fallback): If both options are complex or risky, test the `SwiftVinetas` library types used by CLI arguments instead (`AspectRatio.allCases`, `VinetasModel` raw values, etc.) — clearly document this pivot in a code comment in the test file.
2. Create `Tests/SwiftVinetasTests/CLIArgumentTests.swift` using whichever import approach is confirmed viable.
3. Write tests for the `Generate` subcommand (or equivalent logic):
   - Default `model` is `"klein4b"`, `output` is `"panel.png"`, `preview` flag is `false`
   - `--model klein9b` sets `model == "klein9b"`
   - `--output foo.png` sets `output == "foo.png"`
   - `--seed 42` sets `seed == 42`
   - `--steps 20` sets `steps == 20`
   - `--aspect square` sets `aspect == "square"`
   - `--preview` flag sets `preview == true`
4. Write tests for the `Batch` subcommand: positional `promptsFile` argument sets `promptsFile`, `--model` sets model.
5. Write tests for `ListModels` (`list` subcommand): parses with no required arguments.
6. Write tests for `Preview` subcommand: positional `prompt` argument is required, `--output` is optional defaulting to `"preview.png"`.

**Exit criteria**:
- [ ] `Tests/SwiftVinetasTests/CLIArgumentTests.swift` exists
- [ ] Chosen import strategy is documented in a code comment at the top of the file
- [ ] Tests cover: `Generate` (7 assertions), `Batch` (2), `ListModels` (1), `Preview` (2) — or equivalent library-type assertions if pivot taken
- [ ] `make test-unit` passes with all `CLIArgumentTests` green
- [ ] No `run()` methods are called in any test

### Sortie C-2: Character Subcommand Argument Parsing

**Priority**: 1.5

**Entry criteria**:
- [ ] Sortie C-1 is COMPLETED (`CLIArgumentTests.swift` exists and `make test-unit` passes)

**Tasks**:
1. Extend `CLIArgumentTests.swift` with a `@Suite("CLI character subcommand")` (or nested suite).
2. Read `Sources/vinetas/VinetasCLI.swift` § CharacterCommand before writing any test — verify each option/argument exists in the source before asserting on it.
3. Write tests for `CharacterCommand.Create`:
   - Positional `name` argument: `"Detective Vale"` sets `name == "Detective Vale"`
   - `--description "tall detective"` sets `description == "tall detective"`
   - Note: There is NO `--trigger-word` option on `Create`. Do not test for it.
4. Write tests for `CharacterCommand.Delete`:
   - Positional `slug` argument: `"detective-vale"` sets `slug == "detective-vale"`
   - `--force` flag sets `force == true`
5. Write tests for `CharacterCommand.Train`:
   - Positional `slug` argument sets `slug`
   - `--steps 1500` sets `steps == 1500` (default is 1500 — verify in source)
   - `--model klein4b` sets `model == "klein4b"`
6. Write tests for `Classify`: positional `imagePath` argument sets `imagePath`, `--top-k 5` sets `topK == 5` (verify option name in source: it's `topK` with `@Option`).
7. Write tests for `Similarity`: verify argument structure in source before writing tests.

**Exit criteria**:
- [ ] `CharacterCommand.Create`, `.Delete`, `.Train`, `Classify` argument parsing tests exist
- [ ] Each test was written AFTER confirming the option/argument exists in the source
- [ ] `make test-unit` passes with all new tests green
- [ ] Total assertion count across C-1 and C-2: at least 15

---

## Work Unit D: LoRAManager Load/Unload Sequencing Tests

**Goal**: Cover §7 gap #8 — `VinetasLoRAManager` internal sequencing is untested. Since `VinetasLoRAManager.load(path:scale:on:)` validates file existence via `FileManager.default.fileExists`, tests MUST NOT call it with a non-existent path. Instead, tests exercise the `MockEngine`'s `loadLoRA`/`unloadLoRA` call recording directly, which is what `VinetasLoRAManager` delegates to. This is the correct scope: verifying the engine delegation contract.

### Sortie D-1: LoRAManager Sequencing via MockEngine Tracking

**Priority**: 1.5

**Entry criteria**:
- [ ] First sortie in Work Unit D — no prerequisites
- [ ] `Sources/SwiftVinetas/Core/LoRAManager.swift` is readable
- [ ] `Tests/SwiftVinetasTests/MockEngine.swift` is readable

**Tasks**:
1. Read `Sources/SwiftVinetas/Core/LoRAManager.swift` to understand the engine-based API: `VinetasLoRAManager.load(path:scale:on:)` and `VinetasLoRAManager.unload(from:)`.
2. Create `Tests/SwiftVinetasTests/LoRAManagerTests.swift` with `@Suite("LoRAManager")`.
3. Write `@Test func loraLoadCallRecordedOnMockEngine()`: create a `MockEngine`, create a temp directory URL via `FileManager.default.temporaryDirectory`, create a dummy file at that path, call `try await VinetasLoRAManager.load(path: tempFile.path, scale: 0.8, on: engine)`, assert `await engine.calls` contains `.loadLoRA(tempFile.lastPathComponent, 0.8)`. Clean up temp file in `defer`.
4. Write `@Test func loraUnloadCallRecordedOnMockEngine()`: call `await VinetasLoRAManager.unload(from: engine)`, assert `await engine.calls` contains `.unloadLoRA`.
5. Write `@Test func loraLoadFollowedByUnload()`: load (with temp file) then unload, assert `await engine.calls` is `[.loadLoRA(...), .unloadLoRA]` in that order.
6. Write `@Test func loraLoadWithMissingFileThrows()`: call `try await VinetasLoRAManager.load(path: "/nonexistent/path/lora.safetensors", scale: 0.8, on: engine)`, use `await #expect(throws: VinetasError.self)` to confirm `VinetasError.modelNotFound` is thrown. Assert `await engine.calls` is empty (engine was never reached).

**Exit criteria**:
- [ ] `Tests/SwiftVinetasTests/LoRAManagerTests.swift` exists with 4 tests
- [ ] `make test-unit` passes with all `LoRAManagerTests` green
- [ ] Tests confirm load → unload ordering contract via `MockEngine.calls` array
- [ ] Temp file tests use `defer` cleanup — no orphaned files in `/tmp`

---

## Work Unit E: Concurrent Client Stress Test

**Goal**: Cover §7 gap #6 — concurrent `VinetasClient.generateSequence()` calls not tested for actor isolation correctness.

### Sortie E-1: Actor Isolation Stress Test for Concurrent generateSequence

**Priority**: 3.0

**Entry criteria**:
- [ ] Work Unit A (Sorties A-1 and A-2) is COMPLETED — `VinetasClientTests.swift` exists and `make test-unit` passes

**Tasks**:
1. Create `Tests/SwiftVinetasTests/ConcurrentClientTests.swift` with `@Suite("VinetasClient Concurrency")`.
2. Write `@Test func concurrentGenerateSequenceCallsDoNotRace()`: construct two separate `MockEngine` instances and two separate `VinetasClient` instances (each with its own `EngineRouter`). Launch both `generateSequence(prompts: ["a","b","c"])` calls concurrently via `async let`. Assert both complete successfully and return arrays of 3 images each. This verifies actor isolation prevents state leakage between independent clients.
3. Write `@Test func concurrentGenerateCallsOnSameClientAreSerializedByActor()`: construct one `VinetasClient` with one `MockEngine`. Launch 5 concurrent `generate(prompt:model:)` calls via `withThrowingTaskGroup`. Assert all 5 complete without throwing and `await engine.calls.filter({ if case .generate = $0 { return true }; return false }).count == 5`.
4. Add a Swift 6 concurrency comment at the top of the file: `// These tests validate actor isolation on EngineRouter and @unchecked Sendable discipline on MockEngine under Swift 6 strict concurrency.`

**Exit criteria**:
- [ ] `Tests/SwiftVinetasTests/ConcurrentClientTests.swift` exists
- [ ] Both tests compile under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete` is already set in the package)
- [ ] `make test-unit` passes with both tests green
- [ ] No data races: Swift 6 compiler enforces this at compile time for `Sendable` types

---

## Work Unit F: GPU Determinism and Memory Release Tests

**Goal**: Cover §7 gaps #9 and #10 — fixed-seed determinism and memory release measurement are not yet automated in `SwiftVinetasGPUTests`.

### Sortie F-1: Fixed-Seed Determinism and Memory Release GPU Tests

**Priority**: 4.0 — Independent, can run in parallel with Layer 1. Local-only; no CI gate.

**Entry criteria**:
- [ ] First sortie in Work Unit F — no prerequisites
- [ ] `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` is readable as pattern reference
- [ ] Machine has Apple Silicon with 16+ GB RAM and downloaded Klein 4B model weights (local-only test)

**Tasks**:
1. Add a new `@Test` to `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` named `"Checkpoint 4: Fixed seed produces identical pixel output on two consecutive calls"`:
   - Precondition guard: Metal device exists AND `ProcessInfo.processInfo.physicalMemory >= 16 * 1_073_741_824` — use `Issue.record` pattern from existing tests (not silent `return`).
   - Decoration: `.timeLimit(.minutes(6))` (two 180-second generations).
   - Call `VinetasClient.shared.generate(prompt: "a red square on white background", style: StyleConfig(seed: 42), model: Flux2ModelDescriptor.klein4B)` twice. If `StyleConfig` lacks a `seed` property, check `GenerationRequest` and inject seed directly via a test-only router path.
   - Render both `CGImage` results to `CGContext` using `CGColorSpaceCreateDeviceRGB()` and extract byte arrays.
   - Assert `#expect(pixelData1 == pixelData2)`.
   - Tag: `.tags(.gpu, .flux2)`.
2. Add a new `@Test` named `"Checkpoint 5: unloadModel() releases GPU memory"`:
   - Precondition guard: same as above.
   - Decoration: `.timeLimit(.minutes(3))`.
   - Record resident memory before load using `mach_task_basic_info` (via `task_info` syscall) or `ProcessInfo.processInfo.physicalMemory` (note: this is total RAM, not process RSS — use the syscall for RSS). If `mach_task_basic_info` requires a bridging header that doesn't exist, use `engine.isAvailable(Flux2ModelDescriptor.klein4B)` returning `false` after unload as a proxy, and document clearly in a comment why RSS measurement was skipped.
   - Load Klein 4B: `let engine = try await VinetasClient.shared.router.engine(for: Flux2ModelDescriptor.klein4B)`, then `try await engine.loadModel(Flux2ModelDescriptor.klein4B, progress: { _ in })`.
   - Call `await engine.unloadModel()`.
   - Assert the chosen measurable quantity confirms memory was released.
   - Tag: `.tags(.gpu, .flux2)`.
3. Do NOT modify `INTEGRATION_SUITES` in `Makefile` — both tests are added to `Flux2IntegrationTests` which is already listed.

**Exit criteria**:
- [ ] Two new `@Test` functions added to `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift`
- [ ] Both tests have Metal + memory precondition guards using `Issue.record` (not silent skip)
- [ ] Fixed-seed test uses `#expect(pixelData1 == pixelData2)` with rendered byte arrays
- [ ] Memory release test uses a measurable quantity (RSS or engine availability proxy, with comment)
- [ ] `make test-gpu` compiles without errors (runtime execution requires local GPU + model)

---

## Work Unit G: CI Workflow — Required Status Check

**Goal**: Ensure `unit-tests` is a required status check on `main` and `development`. The `.github/workflows/tests.yml` file already exists with the correct job key `unit-tests` on runner `macos-26` running `make test-unit`. This sortie's primary task is verification, not creation.

### Sortie G-1: Verify and Configure CI unit-tests Workflow

**Priority**: 2.5

**Entry criteria**:
- [ ] Work Units A, B, C, D, E are all COMPLETED (all new unit tests pass under `make test-unit`)
- [ ] `make test-unit` passes locally with all new tests included

**Tasks**:
1. Read `.github/workflows/tests.yml`. Confirm: trigger is `pull_request` to `main` and `development`, job key is `unit-tests`, runner is `macos-26`, step runs `make test-unit`. If any of these are incorrect, fix the file. If all are correct, document "no changes needed" in a comment.
2. Run `gh api repos/intrusive-memory/SwiftVinetas/branches/main/protection` to check required status checks. If `unit-tests` is absent from `required_status_checks.contexts`, add it via:
   ```bash
   gh api --method PUT repos/intrusive-memory/SwiftVinetas/branches/main/protection \
     --field required_status_checks[strict]=true \
     --field "required_status_checks[contexts][]=unit-tests" \
     --field enforce_admins=false \
     --field required_pull_request_reviews=null \
     --field restrictions=null
   ```
3. Repeat for `development` branch.
4. Re-run `gh api` checks after update to confirm `unit-tests` appears in `required_status_checks.contexts` for both branches.

**Exit criteria**:
- [ ] `.github/workflows/tests.yml` has job key `unit-tests` running `make test-unit` on `macos-26`
- [ ] `gh api repos/intrusive-memory/SwiftVinetas/branches/main/protection` output contains `"unit-tests"` in `required_status_checks.contexts`
- [ ] `gh api repos/intrusive-memory/SwiftVinetas/branches/development/protection` output contains `"unit-tests"` in `required_status_checks.contexts`
- [ ] No iOS simulator jobs added (out of scope)

---

## Dependency Graph

```
Layer 1 (parallel — all can start immediately):
  A-1 ──► A-2
  B-1
  C-1 ──► C-2
  D-1
  F-1

Layer 2 (after A-1 and A-2 complete):
  E-1

Layer 3 (after A, B, C, D, E all complete):
  G-1
```

Work Units B, C, D, F have no interdependencies and can run in parallel with Work Unit A.
Work Unit E depends on both A-1 and A-2 completing (full Work Unit A).
Work Unit G is the final gate — requires all unit test sorties to pass before wiring CI.

---

## Open Questions & Missing Documentation

### Resolved During Refinement

| Issue | Resolution |
|-------|-----------|
| `Flux2ModelDescriptor.klein4B.id` value | Confirmed `"flux2-klein-4b"` — updated A-1 Task 6 |
| `preview()` routing mechanism | Confirmed via `engine(forEngineID: "flux2")` then `loadModel` — updated A-1 Task 6 |
| `MockEngine.supports(.loraInference)` returns hardcoded `false` | D-1 rewritten to test `VinetasLoRAManager` static methods directly (with temp files) |
| `@testable import vinetas` viability | Flagged as blocking — C-1 has explicit resolution protocol (Options A/B/C) |
| `CharacterCommand.Create` has no `--trigger-word` | C-2 corrected: tests `--description` and `--force` instead |
| `VinetasError` case count mismatch (plan said 7, actual is 9) | B-1 corrected: 9 cases |
| `tests.yml` already exists | G-1 updated: verify-first rather than create-first |

### Requires Agent Investigation at Sortie Start

| Sortie | Question | Investigation Required |
|--------|----------|----------------------|
| C-1 | Is `@testable import vinetas` viable in Swift 6.2 SPM? | Read `Package.swift`, attempt minimal import, choose Option A/B/C |
| A-2, Task 4 | Does `MockEngine.generate()` currently call `stepProgress`? | Read `MockEngine.swift` — if not, patch MockEngine to fire callbacks |
| F-1, Task 2 | Is `mach_task_basic_info` accessible without a bridging header? | Attempt import, fall back to proxy approach if needed |

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 7 (A–G) |
| Total sorties | 9 |
| Critical path | 4 sorties (A-1 → A-2 → E-1 → G-1) |
| New test files | 5 (`VinetasClientTests.swift`, `VinetasErrorTests.swift`, `CLIArgumentTests.swift`, `LoRAManagerTests.swift`, `ConcurrentClientTests.swift`) |
| Modified test files | 1 (`Flux2IntegrationTests.swift` — 2 new GPU tests) |
| CI configuration | Verify existing `tests.yml` + branch protection on main + development |
| Dependency structure | 3 layers (parallel within Layer 1, E depends on A, G gates all) |
| Test target for new files | `SwiftVinetasTests` (CI-safe, no GPU) except F-1 (`SwiftVinetasGPUTests`) |
| Parallelism | 1 supervising agent + up to 4 sub-agents |

---

## Constraints (All Agents Must Observe)

- Use `import Testing` — never `import XCTest`
- Use `#expect()` and `#require()` — never `XCTAssert*`
- Never import `Metal`, `MLX`, `CoreML`, or `Accelerate` in `SwiftVinetasTests` target files
- Use `@testable import SwiftVinetas` for library types
- For CLI types: choose Option A/B/C per Sortie C-1 investigation — do not assume `@testable import vinetas` works
- Use `make test-unit` to verify, never `swift test` or raw `xcodebuild`
- Sub-agents do NOT run `make` commands — only the supervising agent builds and tests
- `MockEngine` at `Tests/SwiftVinetasTests/MockEngine.swift` is the only engine double for unit tests
- Do not call `.run()` on any `ParsableCommand` in CLI tests — parse only
- `VinetasLoRAManager.load(path:scale:on:)` requires a real file path — always use temp files in tests

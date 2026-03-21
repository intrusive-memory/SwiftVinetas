---
feature_name: OPERATION SWITCHBOARD TRANSMISSION
starting_point_commit: 83207d50563e6f8c374b969280ba9c5c23af9f65
mission_branch: mission/switchboard-transmission/02
iteration: 2
---

# EXECUTION_PLAN.md — SwiftVinetas Engine Abstraction Layer

**Source**: [`docs/ENGINE_ABSTRACTION_REQUIREMENTS.md`](docs/ENGINE_ABSTRACTION_REQUIREMENTS.md)
**Scope**: Add protocol-based engine abstraction to SwiftVinetas, wrapping FLUX.2 and stubbing PixArt-Sigma, with a new `VinetasClient` public API and deprecated compatibility shims.

---

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Resolved Design Decisions

| # | Decision |
|---|----------|
| 1 | `ModelDescriptor` → **protocol** (`Sendable`, `Identifiable where ID == String`, no `Hashable`) |
| 2 | `EngineRouter` → **actor** |
| 3 | `preview()` → **FLUX.2-only private fast path** |
| 4 | Public facade → **instance-based `VinetasClient` class** with `.shared` singleton |
| 5 | Model API → **`any ModelDescriptor` primary** parameter type; `VinetasModel` deprecated |
| 6 | LoRA metadata → **`compatibleEngines: [String]`** replaces `model: VinetasModel?` |
| 7 | Internal routing → **ReferenceSheetGenerator and CharacterTrainer route through engine** |
| 8 | PR strategy → **two PRs** (WU1 = additive, WU2 = behavioral) |

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU1: Engine Protocol + Flux2Engine + Router + Tests | `Sources/SwiftVinetas/Engine/` | 4 | 1 | none |
| WU2: VinetasClient + Wiring + Deprecations + LoRA Migration | `Sources/SwiftVinetas/` | 5 | 2 | WU1 |

---

## WU1: Engine Protocol + Flux2Engine + Router + Tests

**Goal**: Pure additive. Create the `Engine/` directory with protocol, types, Flux2Engine, PixArt stub, EngineRouter, and tests. No behavioral changes. All existing tests continue to pass.

**PR target**: PR 1 — Engine Protocol + Types + Flux2Engine + Router + Tests

---

### Sortie 1: Engine Protocol + Supporting Types

**Priority**: 28.0 — highest dependency depth (blocks all 8 downstream sorties) + foundation (establishes types reused everywhere)
**Context Fitness**: ~25 turns (right-sized for 50-turn budget)

**Goal**: Create the foundational protocol and all supporting types that every subsequent sortie depends on.

**Entry criteria**:
- [ ] First sortie — no prerequisites

**Tasks**:
1. Create `Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift` — the `ImageGenerationEngine` protocol definition per E1.1 (engineID, supportedModels, supports, loadModel, unloadModel, generate, loadLoRA, unloadLoRA, download, isAvailable, delete, diskSize, validateMemory)
2. Create `Sources/SwiftVinetas/Engine/ModelDescriptor.swift` — the `ModelDescriptor` protocol (`Sendable`, `Identifiable where ID == String`) with properties: id, displayName, engineID, license, minimumMemoryGB, approximateDownloadSize, defaultSteps, defaultGuidance, supportedAspectRatios, estimatedSecondsPerImage. Include `ModelLicense` enum (apache2, nonCommercial, custom)
3. Create `Sources/SwiftVinetas/Engine/EngineTypes.swift` — `GenerationRequest` (with `GenerationMode`), `GenerationResult`, `DownloadProgress`, `LoadProgress`, `MemoryValidation`, `EngineFeature` per E2
4. Add new error cases to `Sources/SwiftVinetas/Core/VinetasError.swift`: `engineNotFound(engineID:)`, `modelNotSupported(modelID:engineID:)`, `loraIncompatible(loraEngine:currentEngine:)`, `engineFeatureUnsupported(feature:engineID:)` per E9

**Exit criteria**:
- [ ] `make build` succeeds with zero errors
- [ ] File exists: `Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift`
- [ ] File exists: `Sources/SwiftVinetas/Engine/ModelDescriptor.swift`
- [ ] File exists: `Sources/SwiftVinetas/Engine/EngineTypes.swift`
- [ ] `VinetasError` contains case `engineNotFound`

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E1, §E2, §E9
- `Sources/SwiftVinetas/Core/VinetasError.swift` (existing error enum)
- `Sources/SwiftVinetas/Core/AspectRatio.swift` (for `supportedAspectRatios` type)

---

### Sortie 2: EngineRouter + Flux2Engine

**Priority**: 22.85 — high dependency depth (6 downstream) + foundation (pattern for all engines)
**Context Fitness**: ~26 turns (right-sized)
**Parallel**: Can run simultaneously with Sortie 3 (no file overlap)

**Goal**: Implement the engine router and wrap existing Flux2 pipeline in an `ImageGenerationEngine` conformance.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met (protocol + types compile)

**Tasks**:
1. Create `Sources/SwiftVinetas/Engine/EngineRouter.swift` — `actor EngineRouter` initialized with `[any ImageGenerationEngine]`, providing `allModels` (sorted by displayName), `engine(for: any ModelDescriptor)` (lookup by engineID), and `engine(forEngineID: String)` per E3
2. Create `Sources/SwiftVinetas/Engine/Flux2Engine.swift` — `actor Flux2Engine: ImageGenerationEngine` with engineID `"flux2"`, wrapping `Flux2Pipeline` per E4 and E14.2
3. Implement `Flux2ModelDescriptor` as a struct conforming to `ModelDescriptor` with static instances `.klein4B` (id: `"flux2-klein-4b"`, 16 GB, `.ultraMinimal`, 26s) and `.klein9B` (id: `"flux2-klein-9b"`, 24 GB, `.balanced`, 62s)
4. Map `Flux2Engine` methods to existing `Flux2Core` APIs: `generate` → `Flux2Pipeline.generateTextToImageWithResult/generateImageToImageWithResult`, `loadLoRA/unloadLoRA` → pipeline LoRA methods, `download` → `Flux2ModelDownloader`, `validateMemory` → `VinetasMemory`, `isAvailable` → `ModelRegistry.isDownloaded`

**Exit criteria**:
- [ ] `make build` succeeds with zero errors
- [ ] File exists: `Sources/SwiftVinetas/Engine/EngineRouter.swift`
- [ ] File exists: `Sources/SwiftVinetas/Engine/Flux2Engine.swift`
- [ ] `Flux2Engine` conforms to `ImageGenerationEngine` (compilation proves conformance)
- [ ] `EngineRouter` can be initialized with `[Flux2Engine()]`
- [ ] All existing tests still pass (`make test`)

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E3, §E4, §E14.2
- `Sources/SwiftVinetas/Core/VinetasPipeline.swift` (logic to absorb)
- `Sources/SwiftVinetas/Core/VinetasModelManager.swift` (download delegation pattern)
- `Sources/SwiftVinetas/Core/VinetasMemory.swift` (memory validation logic)
- `Sources/SwiftVinetas/Core/LoRAManager.swift` (LoRA delegation pattern)

---

### Sortie 3: PixArtEngine Stub

**Priority**: 19.65 — high dependency depth (6 downstream) via WU1 gate
**Context Fitness**: ~17 turns (right-sized, lighter workload)
**Parallel**: Can run simultaneously with Sortie 2 (no file overlap)

**Goal**: Add the PixArt-Sigma engine stub gated behind conditional compilation.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met (protocol + types compile)

**Tasks**:
1. Create `Sources/SwiftVinetas/Engine/PixArtEngine.swift` — `actor PixArtEngine: ImageGenerationEngine` with engineID `"pixart-sigma"`, gated behind `#if canImport(PixArtCore)` per E5
2. Implement `PixArtModelDescriptor` as a struct conforming to `ModelDescriptor` with static instance `.sigmaXL` (id: `"pixart-sigma-xl"`, 8 GB, Apache 2.0, 20 steps, guidance 4.5, ~10s)
3. Implement stub behavior for when `PixArtCore` is not available: `validateMemory` returns `.insufficient`, `generate` throws `VinetasError.generationFailed`, `download` throws `VinetasError.downloadFailed`, `isAvailable` returns `false`

**Exit criteria**:
- [ ] `make build` succeeds with zero errors
- [ ] File exists: `Sources/SwiftVinetas/Engine/PixArtEngine.swift`
- [ ] `PixArtEngine` conforms to `ImageGenerationEngine` (compilation proves conformance)
- [ ] `PixArtModelDescriptor.sigmaXL.id == "pixart-sigma-xl"`

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E5, §E5.5 (conditional compilation)
- `Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift` (protocol to conform to)
- `Sources/SwiftVinetas/Engine/Flux2Engine.swift` (pattern to follow)

---

### Sortie 4: PR 1 Test Suite

**Priority**: 19.35 — gates WU2 start + foundation (MockEngine reused in WU2 tests)
**Context Fitness**: ~31 turns (right-sized, largest in WU1)

**Goal**: Create MockEngine test infrastructure and all test files for PR 1 engine types.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met (Flux2Engine compiles)
- [ ] Sortie 3 exit criteria met (PixArtEngine compiles)

**Tasks**:
1. Create `Tests/SwiftVinetasTests/MockEngine.swift` — `MockEngine: ImageGenerationEngine` that records all method calls and returns configurable canned results per E12.3
2. Create `Tests/SwiftVinetasTests/EngineRouterTests.swift` — test engine registration, `allModels` aggregation and sorting, `engine(for:)` correct dispatch, unknown engineID throws `engineNotFound`
3. Create `Tests/SwiftVinetasTests/Flux2EngineTests.swift` — test `Flux2ModelDescriptor` properties (id, displayName, engineID, minimumMemoryGB), feature support (textToImage, imageToImage, loraInference, loraTraining), memory validation thresholds
4. Create `Tests/SwiftVinetasTests/PixArtEngineTests.swift` — test `PixArtModelDescriptor.sigmaXL` properties, stub behavior (unavailable state, generate throws, download throws)
5. Create `Tests/SwiftVinetasTests/GenerationRequestTests.swift` — test request construction for textToImage and imageToImage modes, default values, mode variants

**Exit criteria**:
- [ ] `make test` passes — all existing tests PLUS all new tests pass
- [ ] File exists: `Tests/SwiftVinetasTests/MockEngine.swift`
- [ ] File exists: `Tests/SwiftVinetasTests/EngineRouterTests.swift`
- [ ] File exists: `Tests/SwiftVinetasTests/Flux2EngineTests.swift`
- [ ] File exists: `Tests/SwiftVinetasTests/PixArtEngineTests.swift`
- [ ] File exists: `Tests/SwiftVinetasTests/GenerationRequestTests.swift`

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E12
- `Sources/SwiftVinetas/Engine/` (all files — the types being tested)
- `Tests/SwiftVinetasTests/VinetasModelTests.swift` (existing test patterns)
- `Tests/SwiftVinetasTests/VinetasMemoryTests.swift` (existing test patterns)

---

## WU2: VinetasClient + Wiring + Deprecations + LoRA Migration

**Goal**: Behavioral change. `VinetasClient` becomes the primary API, all generation routes through `EngineRouter`, deprecated shims preserve backward compatibility.

**PR target**: PR 2 — VinetasClient + Wiring + Deprecations + LoRA Migration

---

### Sortie 5: VinetasClient + Deprecated Shims + Output Types

**Priority**: 17.15 — foundation for WU2 (VinetasClient is the primary API) + 4 downstream sorties
**Context Fitness**: ~25 turns (right-sized)

**Goal**: Create the new public API class, deprecate the old static enum and model enum, and update output types to use `modelID: String`.

**Entry criteria**:
- [ ] WU1 complete (all engine types, router, Flux2Engine, PixArtEngine compile and pass tests)

**Tasks**:
1. Create `VinetasClient` class in `Sources/SwiftVinetas/Vinetas.swift` — `public final class VinetasClient: Sendable` with `static let shared`, `let router: EngineRouter`, default init (registers Flux2Engine + conditional PixArtEngine), and test init `init(router:)` per E6.1 and E14.1
2. Add convenience model accessors as static properties on `VinetasClient`: `defaultModel`, `klein4B`, `klein9B`, `pixartSigmaXL` per E6.2
3. Deprecate `Vinetas` enum — add `@available(*, deprecated)`, forward all static methods to `VinetasClient.shared` converting `VinetasModel` → `ModelDescriptor` via `.descriptor` per E14.3
4. Deprecate `VinetasModel` enum — add `@available(*, deprecated)`, add `.pixartSigma` case, add `descriptor` computed property bridging to `ModelDescriptor` per E14.3
5. Update `Sources/SwiftVinetas/Core/PanelOutput.swift` — change `model: VinetasModel` to `modelID: String`, add deprecated computed `var model: VinetasModel?` and deprecated init per E14.4
6. Update `Sources/SwiftVinetas/Core/ImageOutput.swift` — change `output.model.rawValue` references to `output.modelID`

**Exit criteria**:
- [ ] `make build` succeeds with zero errors
- [ ] `VinetasClient.shared` compiles and is accessible
- [ ] `VinetasClient(router:)` test initializer compiles
- [ ] `PanelOutput.modelID` is a `String` property
- [ ] `grep -c '@available.*deprecated' Sources/SwiftVinetas/Vinetas.swift` returns ≥ 1 (Vinetas enum deprecated)
- [ ] `grep -c '@available.*deprecated' Sources/SwiftVinetas/Core/PanelOutput.swift` returns ≥ 1 (deprecated model accessor)

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E6, §E14.1, §E14.3, §E14.4
- `Sources/SwiftVinetas/Vinetas.swift` (file to modify)
- `Sources/SwiftVinetas/Core/PanelOutput.swift` (file to modify)
- `Sources/SwiftVinetas/Core/ImageOutput.swift` (file to modify)

---

### Sortie 6: Wire VinetasClient Generation through EngineRouter

**Priority**: 9.0 — standard priority, 2 downstream sorties
**Context Fitness**: ~25 turns (right-sized)
**Parallel**: Can run simultaneously with Sortie 7 (no file overlap)

**Goal**: Connect all `VinetasClient` generation methods to dispatch through the engine router.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met (VinetasClient class exists with router)

**Tasks**:
1. Implement `VinetasClient.generate(prompt:style:model:)` — resolve engine via `router.engine(for:)`, compose prompt (trigger word + style + panel), build `GenerationRequest` from `StyleConfig`, call `engine.generate(request:stepProgress:)`, build `PanelOutput` from `GenerationResult` per E6.1.3
2. Implement `VinetasClient.generateSequence(prompts:referenceImages:style:model:progress:)` — iterate panels calling engine per-panel per E6.1.4
3. Implement character-aware generation — check LoRA compatibility (`compatibleEngines ∋ engineID`), call `engine.loadLoRA(at:scale:)`, generate, then `engine.unloadLoRA()` per E6.1.8
4. Implement `VinetasClient.preview(prompt:)` — FLUX.2-only fast path via `router.engine(forEngineID: "flux2")`, Klein 4B, 4 steps, 512×512 per E6.1.9
5. Refactor `Sources/SwiftVinetas/Core/VinetasModelManager.swift` — route `download`, `isAvailable`, `delete`, `listAllModels` through `VinetasClient.shared.router`, accept `any ModelDescriptor`, keep deprecated sync overloads per E7

**Exit criteria**:
- [ ] `make build` succeeds with zero errors
- [ ] `grep -q 'router.engine' Sources/SwiftVinetas/Vinetas.swift` confirms generate() calls EngineRouter
- [ ] `grep -q 'forEngineID.*flux2' Sources/SwiftVinetas/Vinetas.swift` confirms preview() resolves to "flux2" engine
- [ ] `grep -q 'any ModelDescriptor' Sources/SwiftVinetas/Core/VinetasModelManager.swift` confirms ModelDescriptor parameter type
- [ ] All existing tests still pass (`make test`)

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E6.1, §E7
- `Sources/SwiftVinetas/Vinetas.swift` (VinetasClient to wire)
- `Sources/SwiftVinetas/Core/VinetasPipeline.swift` (existing generation flow to replace)
- `Sources/SwiftVinetas/Core/VinetasModelManager.swift` (file to refactor)
- `Sources/SwiftVinetas/Core/StyleConfig.swift` (prompt composition inputs)

---

### Sortie 7: LoRA Engine Tagging + Character Migration

**Priority**: 5.85 — leaf-adjacent, only Sortie 9 depends on this
**Context Fitness**: ~24 turns (right-sized)
**Parallel**: Can run simultaneously with Sortie 6 (no file overlap)

**Goal**: Replace model-based LoRA metadata with engine-based tagging and add YAML migration.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met (engine types and VinetasClient exist)

**Tasks**:
1. Update `Sources/SwiftVinetas/Character/Character.swift` — replace `model: VinetasModel?` with `compatibleEngines: [String]` in `LoRAMetadata` per E8.1 and E8.2
2. Implement YAML migration in the deserializer: old `model: klein4b` → `compatibleEngines: ["flux2"]`, old `model: klein9b` → `compatibleEngines: ["flux2"]`. New YAML writes `compatible_engines`, never `model` per E8.1.1
3. Update `Sources/SwiftVinetas/Character/CharacterTrainer.swift` — tag trained LoRA with `compatibleEngines: [model.engineID]` per E8.1.3
4. Update `Sources/SwiftVinetas/Core/LoRAManager.swift` — convert to thin router shim; actual LoRA injection delegated to engine via `engine.loadLoRA(at:scale:)` and `engine.unloadLoRA()` per E8

**Exit criteria**:
- [ ] `make build` succeeds
- [ ] `LoRAMetadata` has property `compatibleEngines: [String]` (not `model: VinetasModel?`)
- [ ] YAML containing `model: klein4b` deserializes to `compatibleEngines: ["flux2"]`
- [ ] `CharacterTrainer` writes `compatibleEngines` when saving LoRA metadata

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E8
- `Sources/SwiftVinetas/Character/Character.swift` (file to modify)
- `Sources/SwiftVinetas/Character/CharacterTrainer.swift` (file to modify)
- `Sources/SwiftVinetas/Core/LoRAManager.swift` (file to modify)
- `Tests/SwiftVinetasTests/CharacterTests.swift` (existing tests that may need updating)

---

### Sortie 8: ReferenceSheetGenerator + Pipeline Deprecation + Memory Update

**Priority**: 5.85 — leaf-adjacent, only Sortie 9 depends on this
**Context Fitness**: ~23 turns (right-sized)

**Goal**: Complete internal wiring by routing ReferenceSheetGenerator through the engine and deprecating the old pipeline.

**Entry criteria**:
- [ ] Sortie 6 exit criteria met (VinetasClient generation wired through EngineRouter)

**Tasks**:
1. Refactor `Sources/SwiftVinetas/Character/ReferenceSheetGenerator.swift` — remove duplicated `Flux2Pipeline` setup, route through engine: `router.engine(for:) → engine.loadModel → GenerationRequest(mode: .imageToImage(references:)) → engine.generate` per E6.1 decision 7
2. Deprecate `Sources/SwiftVinetas/Core/VinetasPipeline.swift` — mark with `@available(*, deprecated, message: "Use Flux2Engine via EngineRouter instead")`, logic has moved to `Flux2Engine` per Step 13
3. Add `validate(for model: any ModelDescriptor) -> Bool` method to `Sources/SwiftVinetas/Core/VinetasMemory.swift` per E14 requirements

**Exit criteria**:
- [ ] `make build` succeeds with zero errors
- [ ] `grep -qv 'Flux2Pipeline' Sources/SwiftVinetas/Character/ReferenceSheetGenerator.swift` confirms no direct Flux2Pipeline usage (or grep returns no matches)
- [ ] `grep -q '@available.*deprecated' Sources/SwiftVinetas/Core/VinetasPipeline.swift` confirms deprecation annotation
- [ ] `grep -q 'func validate.*any ModelDescriptor' Sources/SwiftVinetas/Core/VinetasMemory.swift` confirms new method exists

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E4.3, §E6
- `Sources/SwiftVinetas/Character/ReferenceSheetGenerator.swift` (file to refactor)
- `Sources/SwiftVinetas/Core/VinetasPipeline.swift` (file to deprecate)
- `Sources/SwiftVinetas/Core/VinetasMemory.swift` (file to update)
- `Sources/SwiftVinetas/Engine/Flux2Engine.swift` (logic already moved here)

---

### Sortie 9: PR 2 Test Suite

**Priority**: 1.85 — terminal sortie, no downstream dependents
**Context Fitness**: ~25 turns (right-sized)

**Goal**: Create new tests and update existing tests for all PR 2 changes.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met
- [ ] Sortie 6 exit criteria met
- [ ] Sortie 7 exit criteria met
- [ ] Sortie 8 exit criteria met

**Tasks**:
1. Create `Tests/SwiftVinetasTests/LoRACompatibilityTests.swift` — test engine tag matching, YAML migration (old `model` → `compatibleEngines`), incompatible LoRA fallback behavior per E12.1
2. Update `Tests/SwiftVinetasTests/VinetasModelTests.swift` — add coverage for `.pixartSigma` case, `.descriptor` bridge to `ModelDescriptor` per E12.2
3. Update `Tests/SwiftVinetasTests/VinetasModelManagerTests.swift` — test async overloads accepting `any ModelDescriptor`, engine-aware routing per E12.2
4. Update `Tests/SwiftVinetasTests/CharacterTests.swift` — test `compatibleEngines` YAML roundtrip, migration from old `model` field per E12.2

**Exit criteria**:
- [ ] `make test` passes — ALL existing tests PLUS ALL new tests pass
- [ ] File exists: `Tests/SwiftVinetasTests/LoRACompatibilityTests.swift`
- [ ] Zero test failures across entire test suite

**Key references** (agent should read these):
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` §E12
- `Tests/SwiftVinetasTests/CharacterTests.swift` (file to update)
- `Tests/SwiftVinetasTests/VinetasModelTests.swift` (file to update)
- `Tests/SwiftVinetasTests/VinetasModelManagerTests.swift` (file to update)
- `Tests/SwiftVinetasTests/MockEngine.swift` (test infrastructure from WU1)

---

## Parallelism Structure

**Critical Path**: Sortie 1 → Sortie 2 → Sortie 4 → Sortie 5 → Sortie 6 → Sortie 8 → Sortie 9 (7 sorties)

**Parallel Execution Groups**:
- **Group 1** (sequential): Sortie 1 (Agent 1) — foundation, must complete first
- **Group 2** (parallel after Group 1):
  - Sortie 2: EngineRouter + Flux2Engine (Agent 1)
  - Sortie 3: PixArtEngine Stub (Agent 2)
  - No file overlap — creates independent files in `Engine/`
- **Group 3** (sequential after Group 2): Sortie 4 (Agent 1) — tests all engine types
- **Group 4** (sequential, WU2 gate): Sortie 5 (Agent 1) — VinetasClient creation
- **Group 5** (parallel after Group 4):
  - Sortie 6: Wire generation through EngineRouter (Agent 1) — modifies `Vinetas.swift`, `VinetasModelManager.swift`
  - Sortie 7: LoRA engine tagging (Agent 2) — modifies `Character.swift`, `CharacterTrainer.swift`, `LoRAManager.swift`
  - No file overlap — safe to parallelize
- **Group 6** (sequential after Sortie 6): Sortie 8 (Agent 1)
- **Group 7** (sequential after ALL of 5-8): Sortie 9 (Agent 1)

**Agent Constraints**:
- All sorties have `make build` or `make test` exit criteria — builds run in shared working directory
- Parallel pairs (Groups 2, 5) create/modify non-overlapping files, so concurrent background agents are safe
- Maximum simultaneous agents: 2 (1 supervising + 1 sub-agent)

---

## Open Questions & Missing Documentation

No blocking issues found. All design decisions are resolved (see Resolved Design Decisions table). All file references verified as existing. External dependency (`pixart-swift-mlx`) is properly handled via conditional compilation stub.

---

## Dependency Graph

```
WU1 (Layer 1):
  Sortie 1 ──► Sortie 2 ──► Sortie 4
  Sortie 1 ──► Sortie 3 ──► Sortie 4

  (Sorties 2 and 3 can run in PARALLEL after Sortie 1)

WU2 (Layer 2, depends on WU1):
  Sortie 5 ──► Sortie 6 ──► Sortie 8 ──► Sortie 9
  Sortie 5 ──► Sortie 7 ─────────────► Sortie 9

  (Sorties 6 and 7 can run in PARALLEL after Sortie 5)
  (Sortie 8 depends on Sortie 6 only)
  (Sortie 9 depends on ALL of 5-8)
```

---

## File Summary

| Action | Path |
|--------|------|
| CREATE | `Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift` |
| CREATE | `Sources/SwiftVinetas/Engine/ModelDescriptor.swift` |
| CREATE | `Sources/SwiftVinetas/Engine/EngineTypes.swift` |
| CREATE | `Sources/SwiftVinetas/Engine/EngineRouter.swift` |
| CREATE | `Sources/SwiftVinetas/Engine/Flux2Engine.swift` |
| CREATE | `Sources/SwiftVinetas/Engine/PixArtEngine.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/VinetasError.swift` |
| MODIFY | `Sources/SwiftVinetas/Vinetas.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/PanelOutput.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/ImageOutput.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/VinetasModelManager.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/VinetasMemory.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/LoRAManager.swift` |
| MODIFY | `Sources/SwiftVinetas/Core/VinetasPipeline.swift` |
| MODIFY | `Sources/SwiftVinetas/Character/Character.swift` |
| MODIFY | `Sources/SwiftVinetas/Character/CharacterTrainer.swift` |
| MODIFY | `Sources/SwiftVinetas/Character/ReferenceSheetGenerator.swift` |
| CREATE | `Tests/SwiftVinetasTests/MockEngine.swift` |
| CREATE | `Tests/SwiftVinetasTests/EngineRouterTests.swift` |
| CREATE | `Tests/SwiftVinetasTests/Flux2EngineTests.swift` |
| CREATE | `Tests/SwiftVinetasTests/PixArtEngineTests.swift` |
| CREATE | `Tests/SwiftVinetasTests/GenerationRequestTests.swift` |
| CREATE | `Tests/SwiftVinetasTests/LoRACompatibilityTests.swift` |
| MODIFY | `Tests/SwiftVinetasTests/VinetasModelTests.swift` |
| MODIFY | `Tests/SwiftVinetasTests/VinetasModelManagerTests.swift` |
| MODIFY | `Tests/SwiftVinetasTests/CharacterTests.swift` |

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 2 |
| Total sorties | 9 |
| Dependency structure | layers (WU1 → WU2), with parallel opportunities within each WU |
| Files created | 12 |
| Files modified | 14 |
| Parallel sortie pairs | Sorties 2+3 (WU1), Sorties 6+7 (WU2) |
| Critical path length | 7 sorties (1→2→4→5→6→8→9) |
| Average sortie size | ~25 turns (budget: 50) |
| Max simultaneous agents | 2 (1 supervising + 1 sub-agent) |
| Blocking open questions | 0 |

### Refinement Status

| Pass | Status | Changes |
|------|--------|---------|
| 1. Atomicity & Testability | PASS | 0 splits, 0 merges, 3 vague criteria tightened |
| 2. Prioritization | PASS | 0 reordered — existing order matches priority ranking |
| 3. Parallelism | PASS | 2 parallel groups identified, 1 supervising + 1 sub-agent |
| 4. Open Questions & Vague Criteria | PASS | 3 vague exit criteria replaced with grep-verifiable checks, 0 blocking issues |

# SwiftVinetas — Requirements (SwiftTubería Integration)

**Status**: DRAFT — debate and refine before implementation.
**Parent project**: [`PROJECT_PIPELINE.md`](../PROJECT_PIPELINE.md) — Unified MLX Inference Architecture (§5. SwiftVinetas, Wave 4.1–4.2)
**Scope**: How SwiftVinetas's PixArtEngine evolves to sit atop SwiftTubería's composed pipeline, while Flux2Engine remains unchanged wrapping Flux2Pipeline directly.
**Supersedes**: `docs/archive/REQUIREMENTS_V1.md` (v1 requirements, complete)
**Related**: `docs/incomplete/EXECUTION_PLAN.md` (in-progress execution plan for prior architecture)

---

## Motivation

SwiftVinetas already has the right abstraction layer — `ImageGenerationEngine` protocol, `EngineRouter`, `ModelDescriptor`. The problem is what sits below it: each engine (Flux2Engine, PixArtEngine) wraps a monolithic model library and reimplements the translation between the engine protocol and the model's bespoke API.

With SwiftTubería, the layer below the engine becomes uniform. Every engine wraps a `DiffusionPipeline` composed from the appropriate recipe. The engine protocol simplifies because the pipeline handles model loading, memory management, progress reporting, and generation orchestration. The engine becomes a thin adapter that maps Vinetas-specific concepts (StyleConfig, PromptFile, AspectRatio) to pipeline requests.

### What Changes vs What Stays

| Concern | Changes | Stays In Vinetas |
|---|---|---|
| PixArtEngine internals | Wraps `DiffusionPipeline` instead of being a stub | Engine protocol conformance |
| PixArt model loading/downloading | Delegates to SwiftAcervo Component Registry via pipeline | ModelDescriptor declarations |
| PixArt memory validation | Delegates to pipeline's MemoryManager | `validateMemory()` API shape |
| PixArt generation orchestration | Delegates to pipeline's `generate()` | Prompt composition logic |
| Flux2Engine internals | **Unchanged** — continues wrapping `Flux2Pipeline` directly | **Stays** |
| VinetasClient (public API) | Unchanged | **Stays** |
| EngineRouter | Simplified (less state to manage) | **Stays** |
| ImageGenerationEngine protocol | Potentially simplified | **Stays** (or evolves) |
| ModelDescriptor protocol | Unchanged | **Stays** |
| StyleConfig, AspectRatio | Unchanged | **Stays** |
| PromptFile (YAML parsing) | Unchanged | **Stays** |
| Character management | Unchanged | **Stays** |
| VinetasError | Unchanged | **Stays** |

---

## S1. Engine Layer Evolution

### S1.1 Flux2Engine (Unchanged)

`Flux2Engine` remains unchanged. It continues to be an actor that:
1. Manages a `Flux2Pipeline?` instance
2. Translates `GenerationRequest` → Flux2Pipeline method calls
3. Translates `Flux2GenerationResult` → `GenerationResult`
4. Manages model loading/unloading lifecycle
5. Handles LoRA loading via Flux2Pipeline's API
6. Queries download status via Flux2Pipeline's model management

FLUX.2 migration to SwiftTubería is deferred. The existing Flux2Engine and its direct Flux2Pipeline dependency stay as-is.

### S1.2 PixArtEngine Comes Alive

The PixArtEngine stub (`#if canImport(PixArtCore)`) is replaced with a real implementation that:
1. Imports `PixArtBackbone` and `Tubería`
2. Assembles a `DiffusionPipeline` using the PixArt recipe
3. Thin adapter (~50 lines) between `ImageGenerationEngine` protocol and the assembled pipeline

**PixArt becomes the iPad engine.** `EngineRouter` registers only `PixArtEngine` on iPad (where FLUX can't fit in memory) and both engines on macOS. This is the gate that makes SwiftVinetas a macOS + iPad library.

---

## S2. ImageGenerationEngine Protocol

The current protocol is well-designed and largely survives. For PixArtEngine, methods simplify through pipeline delegation. Flux2Engine continues using its current implementation for all methods.

### S2.1 Methods That Simplify

| Method | Current | With Pipeline |
|---|---|---|
| `loadModel(_:progress:)` | Engine manages pipeline lifecycle | Delegates to `pipeline.loadModels(progress:)` |
| `generate(request:stepProgress:)` | Engine calls model-specific generation | Delegates to `pipeline.generate(request:progress:)` |
| `download(_:progress:)` | Engine calls model-specific downloader | Delegates to `Acervo.ensureComponentsReady(ids)` |
| `isAvailable(_:)` | Engine checks model-specific paths | Delegates to `Acervo.isComponentReady(id)` |
| `validateMemory(for:)` | Engine queries model-specific sizes | Delegates to `pipeline.memoryRequirement` |
| `diskSize(of:)` | Engine queries model-specific paths | Delegates to Acervo component metadata |

### S2.2 Methods That Stay

| Method | Why |
|---|---|
| `supports(_:)` | Feature detection is engine/model-specific |
| `loadLoRA(at:scale:)` | LoRA target layers are model-specific |
| `delete(_:)` | May need engine-specific cleanup beyond cache deletion |

### S2.3 New Capabilities Enabled

With the pipeline architecture, engines can expose capabilities that were previously too expensive to implement per-model:

- **Pipeline introspection**: Which components are loaded? Memory usage per component?
- **Component-level progress**: "Loading T5 encoder (1/3)" vs just "Loading model"
- **Cross-engine model sharing**: If PixArt and a future SD model both use SDXL VAE, the loaded VAE can be shared (same component, same weights, loaded once)

---

## S3. ModelDescriptor Protocol

Unchanged. Each engine declares its model descriptors:

- `Flux2ModelDescriptor.klein4B`, `.klein9B` (unchanged — no `componentIds`, uses existing download path)
- `PixArtModelDescriptor.sigmaXL` (new — uses `componentIds` for Acervo integration)
- Future: video model descriptors, audio model descriptors

The descriptor declares the model's memory requirements, download size, default generation parameters, and supported aspect ratios. This is engine-level metadata, not pipeline-level — it stays in Vinetas.

**Bridge to Acervo**: `ModelDescriptor` gains `componentIds: [String]` to connect the consumer-facing model concept to Acervo's component-level download/access system:

```swift
public protocol ModelDescriptor: Sendable, Identifiable where ID == String {
    /// Unique model identifier (e.g., "flux2-klein-4b"). Consumer-facing, distinct from Acervo component IDs.
    var id: String { get }
    /// Display name for UI (e.g., "FLUX.2 Klein 4B").
    var displayName: String { get }
    /// Minimum RAM required to load this model (bytes).
    var minimumMemoryBytes: UInt64 { get }
    /// Total download size across all components (bytes).
    var downloadSizeBytes: UInt64 { get }
    /// Default generation parameters for this model.
    var defaultSteps: Int { get }
    var defaultGuidanceScale: Float { get }
    /// Supported aspect ratios for this model.
    var supportedAspectRatios: [AspectRatio] { get }
    /// Acervo component IDs needed for this model's pipeline.
    var componentIds: [String] { get }
}
```

Example: `PixArtModelDescriptor.sigmaXL.componentIds` → `["pixart-sigma-xl-dit-int4", "t5-xxl-encoder-int4", "sdxl-vae-decoder-fp16"]`. This is distinct from `ModelDescriptor.id` (which identifies the user-facing model, e.g., `"pixart-sigma-xl"`). The two ID spaces serve different layers and are intentionally kept separate.

`Flux2ModelDescriptor` does NOT adopt `componentIds` — it continues using its existing download and availability logic through `Flux2Pipeline`.

---

## S4. VinetasClient (Public API)

**Unchanged.** The public API consumers see the same interface:

```swift
VinetasClient.shared.generate(prompt:style:model:)
VinetasClient.shared.generateSequence(prompts:model:progress:stepProgress:)
VinetasClient.shared.download(model:progress:)
VinetasClient.shared.listModels()
```

The change is entirely below the engine layer. Consumers do not see SwiftTubería.

---

## S5. Prompt Composition

Vinetas's prompt composition logic stays in Vinetas:

```
triggerWord (from LoRA) + stylePrompt (from StyleConfig) + panelPrompt (from user/PromptFile)
    → composed prompt string
    → passed to engine.generate(request:)
```

The engine passes the composed string to the pipeline. The pipeline's TextEncoder tokenizes and encodes it. Neither the pipeline nor the encoder knows about styles, characters, or panels — that's Vinetas's domain.

---

## S5.1 Request Translation (PixArtEngine)

PixArtEngine translates SwiftVinetas's `GenerationRequest` into SwiftTubería's `DiffusionGenerationRequest`. Flux2Engine continues using its existing request translation to `Flux2Pipeline`. The field mapping for PixArtEngine is:

| GenerationRequest (Vinetas) | DiffusionGenerationRequest (Tubería) | Notes |
|---|---|---|
| `prompt` (composed string) | `prompt` | After style + trigger word composition |
| `negativePrompt` | `negativePrompt` | Pass-through, nil if model doesn't use CFG |
| `width`, `height` | `width`, `height` | From `AspectRatio` resolution |
| `steps` | `steps` | From model defaults or user override |
| `guidanceScale` | `guidanceScale` | From model defaults or user override |
| `seed` | `seed` | Pass-through |
| `loRAPath` + `loRAScale` | `loRA: LoRAConfig(localPath:scale:activationKeyword:)` | Engine maps path + scale to LoRAConfig |

Fields NOT in DiffusionGenerationRequest that stay in Vinetas: `style`, `model`, `aspectRatio`, `characters`. These are consumed during prompt composition before the request reaches the pipeline.

---

## S6. Dependency Changes

**Current**:
```
SwiftVinetas
├── flux-2-swift-mlx (Flux2Pipeline, direct dependency)
├── SwiftAcervo (model caching)
├── universal (YAML parsing)
└── swift-argument-parser (CLI)
```

**Target**:
```
SwiftVinetas
├── SwiftTubería/Tubería (pipeline protocols + infrastructure)
├── SwiftTubería/TuberíaCatalog (shared components, if needed directly)
├── flux-2-swift-mlx (unchanged — full library, wraps Flux2Pipeline directly)
├── pixart-swift-mlx/PixArtBackbone (PixArt recipe + backbone)
├── universal (YAML parsing — unchanged)
└── swift-argument-parser (CLI — unchanged)
```

SwiftAcervo arrives transitively via SwiftTubería. PixArt model downloads and availability checks flow through Acervo's Component Registry. The flux-2-swift-mlx dependency is unchanged — Flux2Engine continues wrapping `Flux2Pipeline` directly.

---

## S7. Platform Strategy

### S7.1 macOS
Both Flux2Engine and PixArtEngine registered. User chooses model based on quality/speed/memory tradeoffs.

### S7.2 iPadOS (M-series)
Only PixArtEngine registered (FLUX requires 16+ GB, no iPad qualifies). PixArt's ~2 GB footprint runs comfortably on 8 GB iPads.

### S7.3 Engine Registration

```swift
// In VinetasClient.init()
#if os(macOS)
let engines: [any ImageGenerationEngine] = [Flux2Engine(), PixArtEngine()]
#else
let engines: [any ImageGenerationEngine] = [PixArtEngine()]
#endif
```

Or dynamically based on `MemoryManager.deviceCapability`:
```swift
var engines: [any ImageGenerationEngine] = [PixArtEngine()]
if MemoryManager.shared.deviceCapability.totalMemoryGB >= 16 {
    engines.append(Flux2Engine())
}
```

**Note**: `DeviceCapability.current` is the synchronous accessor (no `await` needed). Use it for engine registration decisions. `MemoryManager.shared.deviceCapability` provides the same value but requires `await` through the actor. For synchronous init contexts like `VinetasClient.init()`, use `DeviceCapability.current.totalMemoryGB` directly.

---

## S8. Future Engine Types

The engine abstraction and SwiftTubería together create a clear path for future modalities:

### S8.1 Video Engine (Future)
```swift
actor VideoEngine: VideoGenerationEngine {
    // Assembles a DiffusionPipeline with temporal backbone + VideoRenderer
    // New protocol: VideoGenerationEngine (extends or parallels ImageGenerationEngine)
}
```

### S8.2 Audio Diffusion Engine (Future)
```swift
actor AudioDiffusionEngine: AudioGenerationEngine {
    // Assembles a DiffusionPipeline with audio backbone + AudioRenderer
    // Distinct from SwiftVoxAlta's TTS — this is for music/SFX generation
}
```

Each new modality needs:
1. A new engine protocol (or a generic `GenerationEngine<Output>`)
2. A backbone plugin package
3. A pipeline recipe using catalog components + the new backbone

The engine layer in Vinetas (or a sibling package) handles the domain-specific orchestration. The pipeline handles the ML inference.

---

## S9. Migration Path

1. **Phase 1 — Add SwiftTubería dependency**: Import Tubería alongside existing flux-2-swift-mlx dependency. Both coexist.

2. **Phase 2 — Implement PixArtEngine**: First engine to use SwiftTubería natively (no legacy code to migrate). Proves the integration pattern.

3. **Phase 3 — iPad deployment**: With PixArtEngine working, enable iPadOS target. Platform-conditional engine registration.

Flux2Engine remains unchanged throughout. FLUX.2 migration to SwiftTubería is deferred.

---

## S10. Testing Strategy

### S10.1 Tests That Stay Unchanged
- VinetasClient public API tests
- PromptFile YAML parsing
- StyleConfig composition
- AspectRatio calculations
- VinetasError coverage
- EngineRouter dispatch logic

### S10.2 Tests That Change
- PixArtEngine tests — replace stub tests with real integration tests
- Model download tests — verify Acervo Component Registry delegation for PixArt models

### S10.3 New Tests
- Pipeline assembly: verify PixArt recipe produces valid pipeline
- Engine-pipeline integration: verify GenerationRequest → pipeline request mapping preserves all parameters (PixArtEngine)
- Platform-conditional registration: verify iPad gets only PixArtEngine
- Cross-engine model listing: verify `listModels()` returns both engine catalogs

### S10.4 Tests That Stay Unchanged
- Flux2Engine tests — Flux2Engine is not modified, existing tests remain as-is

### S10.5 Coverage and CI Stability Requirements

- All new code must achieve **≥90% line coverage** in unit tests. Coverage is measured per-target and enforced in CI.
- **No timed tests**: Tests must not use `sleep()`, `Task.sleep()`, `Thread.sleep()`, fixed-duration `XCTestExpectation` timeouts, or any wall-clock assertions. All asynchronous behavior must be validated via deterministic synchronization (`async`/`await`, `AsyncStream`, fulfilled expectations with immediate triggers).
- **No environment-dependent tests**: Engine adapter tests, pipeline assembly tests, and request/result mapping tests must use mock pipelines and run without real model weights, network access, or GPU. Tests requiring real image generation are integration tests and must be clearly separated (separate test target or `#if INTEGRATION_TESTS` gate).
- **Flaky tests are test failures**: A test that passes intermittently is treated as a failing test until fixed. CI must not use retry-on-failure to mask flakiness.

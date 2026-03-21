# Generation Engine Abstraction — Requirements

**Status**: DRAFT — iterate and refine before implementation.
**Scope**: SwiftVinetas library only. Does not cover Vinetas app UI, flux-2-swift-mlx internals, or new engine packages.

---

## Motivation

SwiftVinetas currently hardcodes its generation pipeline to FLUX.2 Klein models via direct dependency on `Flux2Core`. Adding PixArt-Sigma (and future models) requires an abstraction layer that:

1. Defines a protocol boundary between the orchestrator (SwiftVinetas) and any generation engine
2. Lets the Vinetas app treat all models identically through a single API
3. Keeps engine-specific details (architectures, schedulers, VAE channels, text encoders) below the protocol line
4. Preserves character consistency, LoRA, and prompt composition as orchestrator-level concerns

---

## E1. `ImageGenerationEngine` Protocol

A new protocol that every generation backend must conform to. Lives in `Sources/SwiftVinetas/Engine/`.

### E1.1 Contract

```swift
public protocol ImageGenerationEngine: Sendable {

    // --- Identity ---
    var engineID: String { get }

    // --- Model catalog ---
    var supportedModels: [any ModelDescriptor] { get }

    // --- Capabilities ---
    func supports(_ feature: EngineFeature) -> Bool

    // --- Lifecycle ---
    /// Load a model into memory, ready for generation.
    /// Engines manage their own two-phase loading (text encoder → transformer).
    func loadModel(
        _ model: any ModelDescriptor,
        progress: @Sendable (LoadProgress) -> Void
    ) async throws

    /// Unload the current model, freeing memory.
    func unloadModel() async

    // --- Generation ---
    /// Generate one image from a fully-composed prompt.
    /// The engine receives the final prompt string — it does not know about
    /// characters, trigger words, or style composition.
    func generate(
        request: GenerationRequest,
        stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
    ) async throws -> GenerationResult

    // --- LoRA ---
    /// Load a LoRA adapter. Engine applies it to whichever internal layers
    /// are appropriate for its architecture.
    func loadLoRA(at path: URL, scale: Float) async throws

    /// Remove the currently loaded LoRA adapter.
    func unloadLoRA() async

    // --- Model management ---
    func download(
        _ model: any ModelDescriptor,
        progress: @Sendable (DownloadProgress) -> Void
    ) async throws

    func isAvailable(_ model: any ModelDescriptor) -> Bool
    func delete(_ model: any ModelDescriptor) async throws
    func diskSize(of model: any ModelDescriptor) -> Int64?
    func validateMemory(for model: any ModelDescriptor) -> MemoryValidation
}
```

### E1.2 Non-Goals for the Protocol

The engine does NOT:
- Know about `Character`, trigger words, or prompt composition
- Own image understanding (ViT, DINOv2) — that stays in `Understanding/`
- Parse prompt files — that stays in `Core/PromptFile.swift`
- Manage the CDN base URL — the orchestrator configures that before engine init

### E1.3 Rationale

The protocol intentionally passes a flat `GenerationRequest` with a single composed `prompt: String` rather than structured fields (trigger word, style prompt, panel prompt). This keeps the engine ignorant of upstream prompt semantics. SwiftVinetas composes the prompt, the engine renders it.

---

## E2. Supporting Types

All live in `Sources/SwiftVinetas/Engine/`.

### E2.1 `ModelDescriptor` Protocol

```swift
public protocol ModelDescriptor: Sendable, Identifiable where ID == String {
    var id: String { get }                      // "flux2-klein-4b", "pixart-sigma-xl"
    var displayName: String { get }             // "FLUX.2 Klein 4B", "PixArt-Σ XL"
    var engineID: String { get }                // Routes to correct engine
    var license: ModelLicense { get }
    var minimumMemoryGB: Int { get }
    var approximateDownloadSize: String { get }  // "~11 GB", "~3.6 GB"
    var defaultSteps: Int { get }
    var defaultGuidance: Float { get }
    var supportedAspectRatios: [AspectRatio] { get }
    var estimatedSecondsPerImage: Int { get }
}
```

### E2.2 `EngineFeature`

```swift
public enum EngineFeature: Sendable, Hashable {
    case textToImage
    case imageToImage(maxReferenceImages: Int)
    case loraInference
    case loraTraining
    case promptUpsampling
}
```

### E2.3 `GenerationRequest`

```swift
public struct GenerationRequest: Sendable {
    public var prompt: String
    public var negativePrompt: String?
    public var steps: Int
    public var guidanceScale: Float
    public var seed: UInt64?
    public var width: Int
    public var height: Int
    public var mode: GenerationMode

    public enum GenerationMode: Sendable {
        case textToImage
        case imageToImage(references: [CGImage])
    }
}
```

### E2.4 `GenerationResult`

```swift
public struct GenerationResult: Sendable {
    public var image: CGImage
    public var usedPrompt: String
    public var seed: UInt64
    public var durationSeconds: Double
    public var modelID: String
}
```

### E2.5 Progress and Validation Types

```swift
public struct DownloadProgress: Sendable {
    public var fraction: Double       // 0.0–1.0
    public var message: String
}

public struct LoadProgress: Sendable {
    public var phase: String          // "Loading text encoder", "Loading transformer"
    public var fraction: Double
}

public enum MemoryValidation: Sendable {
    case ok
    case warning(message: String)
    case insufficient(required: UInt64, available: UInt64)
}

public enum ModelLicense: Sendable, Hashable {
    case apache2
    case nonCommercial(details: String)
    case custom(name: String, url: URL?)
}
```

---

## E3. Engine Router

A registry that maps model descriptors to engine instances. Replaces the current hardcoded `VinetasModel → Flux2Pipeline` mapping in `VinetasPipeline.swift`.

### E3.1 Requirements

- E3.1.1: `EngineRouter` is initialized with one or more `ImageGenerationEngine` instances.
- E3.1.2: `allModels` returns every `ModelDescriptor` across all registered engines, sorted by `displayName`.
- E3.1.3: `engine(for:)` returns the engine that owns a given `ModelDescriptor`, looked up by `engineID`.
- E3.1.4: The router is the single point through which `Vinetas.swift` (the public facade) accesses generation.
- E3.1.5: The router is `Sendable` and safe to share across actors.

### E3.2 Location

`Sources/SwiftVinetas/Engine/EngineRouter.swift`

---

## E4. `Flux2Engine` — Wrap Existing Pipeline

An `ImageGenerationEngine` conformance that wraps the existing `Flux2Core` dependency. This is a **refactor of existing code**, not new functionality.

### E4.1 Requirements

- E4.1.1: `Flux2Engine` conforms to `ImageGenerationEngine`.
- E4.1.2: `engineID` is `"flux2"`.
- E4.1.3: `supportedModels` returns descriptors for Klein 4B and Klein 9B (matching current `VinetasModel` cases).
- E4.1.4: `generate(request:stepProgress:)` delegates to `Flux2Pipeline.generateTextToImageWithResult()` and `generateImageToImageWithResult()`, mapping `GenerationRequest` to Flux2Core's API.
- E4.1.5: `loadLoRA`/`unloadLoRA` delegate to the existing `VinetasLoRAManager`.
- E4.1.6: `download` delegates to the existing `Flux2ModelDownloader` via `VinetasModelManager`.
- E4.1.7: `validateMemory` delegates to the existing `VinetasMemory` checks.
- E4.1.8: Quantization selection (`.ultraMinimal` for Klein 4B, `.balanced` for Klein 9B) stays internal to `Flux2Engine` — the protocol caller never sees quantization config.
- E4.1.9: Two-phase loading (text encoder → unload → transformer + VAE) stays internal to `Flux2Engine`.

### E4.2 Location

`Sources/SwiftVinetas/Engine/Flux2Engine.swift`

### E4.3 Migration

The current `VinetasPipeline.swift` becomes a thin internal helper called by `Flux2Engine`, or its logic is inlined into `Flux2Engine` directly. The public API (`Vinetas.swift`) stops calling `VinetasPipeline` and calls `EngineRouter` instead.

---

## E5. `PixArtEngine` — New Backend (Stub + Integration Point)

An `ImageGenerationEngine` conformance for PixArt-Sigma. The actual PixArt inference code will live in a separate package (`pixart-swift-mlx`). SwiftVinetas owns the engine wrapper.

### E5.1 Requirements

- E5.1.1: `PixArtEngine` conforms to `ImageGenerationEngine`.
- E5.1.2: `engineID` is `"pixart-sigma"`.
- E5.1.3: `supportedModels` returns one descriptor: PixArt-Sigma XL-2-1024.
- E5.1.4: `generate(request:stepProgress:)` delegates to the PixArt pipeline from the external package.
- E5.1.5: `loadLoRA`/`unloadLoRA` delegate to PixArt's LoRA injection (DiT linear layers, different targets than FLUX.2).
- E5.1.6: `download` fetches three components: PixArt transformer, SDXL VAE, T5-XXL encoder (int4).
- E5.1.7: `validateMemory` checks for 8 GB minimum (int4 transformer + int4 T5 + SDXL VAE).

### E5.2 PixArt Model Descriptor

```
ID:                    pixart-sigma-xl
Display Name:          PixArt-Σ XL
Engine ID:             pixart-sigma
License:               Apache 2.0
Min Memory:            8 GB
Download Size:         ~3.6 GB (transformer int4 + SDXL VAE + T5-XXL int4)
Default Steps:         20
Default Guidance:      4.5
Estimated Time:        5–15 sec (1024×1024, M2 Max)
Supported Aspect Ratios: all (same set as FLUX.2)
Features:              textToImage, loraInference
```

### E5.3 Location

`Sources/SwiftVinetas/Engine/PixArtEngine.swift`

### E5.4 External Dependency

SwiftVinetas gains a new SPM dependency on `pixart-swift-mlx` (to be created). This is analogous to the existing `flux-2-swift-mlx` dependency. The dependency provides:
- `PixArtPipeline` — text encoding, denoising loop, VAE decode
- `PixArtConfig` — model configuration
- `PixArtModelDownloader` — weight download and caching
- T5 encoder in MLX Swift (int4 quantized)

### E5.5 Conditional Compilation (Optional)

If `pixart-swift-mlx` is not yet available during initial development, `PixArtEngine` can be gated behind a compilation flag or return `.notAvailable` from `validateMemory` for all models. This lets the protocol and router ship before the PixArt backend is ready.

---

## E6. Replace `Vinetas.swift` with `VinetasClient`

The public API moves from a static `Vinetas` enum to an instance-based `VinetasClient` class. Methods accept `any ModelDescriptor` instead of `VinetasModel`. The old `Vinetas` enum becomes a deprecated shim.

### E6.1 Requirements

- E6.1.1: `VinetasClient` is a `public final class: Sendable` with a `shared` singleton and a `router: EngineRouter` actor.
- E6.1.2: `VinetasClient` provides a `defaultModel: any ModelDescriptor` (returns `Flux2ModelDescriptor.klein4B`). All generation methods default to this.
- E6.1.3: `generate(prompt:style:model:)` accepts `any ModelDescriptor`, resolves the engine via `EngineRouter`, composes the prompt, and calls `engine.generate(request:)`.
- E6.1.4: `generateSequence(...)` iterates panels, calling the engine per-panel.
- E6.1.5: `download(model:progress:)` accepts `any ModelDescriptor`, resolves the engine, and delegates.
- E6.1.6: `listModels()` returns `EngineRouter.allModels` mapped to `VinetasModelInfo`.
- E6.1.7: `validateMemory(for:)` delegates to the resolved engine.
- E6.1.8: Character-aware generation composes the trigger word + LoRA at the `VinetasClient` level, calling `engine.loadLoRA(...)` then `engine.generate(...)` then `engine.unloadLoRA()`.
- E6.1.9: `preview(prompt:)` is a FLUX.2-only private fast path — forces Klein 4B, 4 steps, 512×512. Resolves directly to `"flux2"` engine via `router.engine(forEngineID:)`.

### E6.2 Convenience Accessors

All known model descriptors are accessible as static properties on `VinetasClient` for discoverability:

```swift
extension VinetasClient {
    /// The default model for generation. Currently FLUX.2 Klein 4B.
    public static var defaultModel: any ModelDescriptor { Flux2ModelDescriptor.klein4B }

    /// All known model descriptors for code completion / discovery.
    public static var klein4B: any ModelDescriptor { Flux2ModelDescriptor.klein4B }
    public static var klein9B: any ModelDescriptor { Flux2ModelDescriptor.klein9B }
    public static var pixartSigmaXL: any ModelDescriptor { PixArtModelDescriptor.sigmaXL }
}
```

### E6.3 Backward Compatibility

- E6.3.1: The `VinetasModel` enum is **deprecated**. A computed `descriptor` property bridges to `ModelDescriptor`.
- E6.3.2: The `Vinetas` enum is **deprecated**. All static methods forward to `VinetasClient.shared`, converting `VinetasModel` → `ModelDescriptor` via the bridge.
- E6.3.3: `preview(prompt:)` remains FLUX.2-only and does not accept a model parameter.

---

## E7. Refactor `VinetasModelManager`

Currently wraps `Flux2ModelDownloader` directly. Must become engine-aware.

### E7.1 Requirements

- E7.1.1: `download(model:progress:)` resolves the engine from `EngineRouter` and delegates.
- E7.1.2: `isAvailable(_:)` delegates to the resolved engine.
- E7.1.3: `delete(_:)` delegates to the resolved engine.
- E7.1.4: `listAllModels()` returns models from all engines, with download status.
- E7.1.5: `configureCDN(baseURL:)` continues to set `ModelRegistry.cdnBaseURL` for Flux2 and also configures the PixArt engine's CDN if applicable.

### E7.2 Location

Stays at `Sources/SwiftVinetas/Core/VinetasModelManager.swift`. Internal implementation changes; public API stays the same.

---

## E8. LoRA Abstraction

LoRA loading/unloading is currently FLUX.2-specific (`VinetasLoRAManager` calls `Flux2Core` APIs). The engine protocol abstracts this, but the orchestrator needs to know which LoRA formats are compatible with which engines.

### E8.1 Requirements

- E8.1.1: `LoRAMetadata.model: VinetasModel?` is **replaced** by `compatibleEngines: [String]` (engine IDs). Existing `character.yaml` files with `model: klein4b` are migrated during deserialization: `klein4b`/`klein9b` → `["flux2"]`. The `model` field is no longer written.
- E8.1.2: When generating with a character, `VinetasClient` checks that the selected model's engine is in the LoRA's `compatibleEngines` list. If not, generation proceeds without LoRA (prompt-only consistency) and logs a warning.
- E8.1.3: `CharacterTrainer` tags the trained LoRA's `compatibleEngines` with the engine ID of the model it was trained on.
- E8.1.4: LoRA file format remains standard safetensors (`lora_a.weight` / `lora_b.weight`). Engine-specific layer targeting is the engine's responsibility.

### E8.2 `LoRAMetadata` After Migration

```swift
public struct LoRAMetadata: Sendable {
    public var path: String
    public var scale: Float
    public var version: Int
    public var trainedAt: Date?
    public var trainingSteps: Int?
    public var compatibleEngines: [String]  // replaces model: VinetasModel?
}
```

### E8.3 Location

- `Character.swift` — replace `model` with `compatibleEngines` in `LoRAMetadata`, migrate YAML deserialization
- `CharacterTrainer.swift` — tag LoRA with engine ID
- `VinetasLoRAManager.swift` — becomes a thin router; actual injection delegated to engine

---

## E9. Error Handling

### E9.1 New Error Cases

Add to `VinetasError`:

```swift
case engineNotFound(engineID: String)
case modelNotSupported(modelID: String, engineID: String)
case loraIncompatible(loraEngine: String, currentEngine: String)
case engineFeatureUnsupported(feature: EngineFeature, engineID: String)
```

### E9.2 Engine-Level Errors

Each engine may throw its own errors. The protocol requires all throws to be wrapped in `VinetasError.generationFailed(String)` so the orchestrator and app see a uniform error type.

---

## E10. File Structure

After this work, `Sources/SwiftVinetas/` looks like:

```
Sources/SwiftVinetas/
├── Engine/                          # NEW — protocol + implementations
│   ├── ImageGenerationEngine.swift  # Protocol definition
│   ├── ModelDescriptor.swift        # ModelDescriptor protocol + ModelLicense
│   ├── EngineTypes.swift            # GenerationRequest, GenerationResult,
│   │                                  DownloadProgress, LoadProgress,
│   │                                  MemoryValidation, EngineFeature
│   ├── EngineRouter.swift           # Registry mapping engineID → engine
│   ├── Flux2Engine.swift            # ImageGenerationEngine for FLUX.2
│   └── PixArtEngine.swift           # ImageGenerationEngine for PixArt-Σ
├── Character/                       # MODIFIED — LoRA engine tagging
│   ├── Character.swift
│   ├── CharacterManager.swift
│   ├── CharacterTrainer.swift
│   ├── ReferenceSheetGenerator.swift
│   └── TrainingDataPreparer.swift
├── Core/                            # MODIFIED — delegates to EngineRouter
│   ├── AspectRatio.swift
│   ├── ImageOutput.swift
│   ├── LoRAManager.swift
│   ├── PanelOutput.swift
│   ├── PromptFile.swift
│   ├── StyleConfig.swift
│   ├── VinetasError.swift           # MODIFIED — new error cases
│   ├── VinetasMemory.swift
│   ├── VinetasModelInfo.swift
│   ├── VinetasModelManager.swift    # MODIFIED — engine-aware
│   └── VinetasPipeline.swift        # DEPRECATED — logic moves to Flux2Engine
├── Understanding/                   # UNCHANGED
│   └── ...
└── Vinetas.swift                    # MODIFIED — routes through EngineRouter
```

---

## E11. Package.swift Changes

### E11.1 New Dependency

```swift
// When pixart-swift-mlx is ready:
.package(url: "https://github.com/intrusive-memory/pixart-swift-mlx.git", branch: "development"),
```

### E11.2 New Product Dependency in Target

```swift
.target(
    name: "SwiftVinetas",
    dependencies: [
        .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
        .product(name: "FluxTextEncoders", package: "flux-2-swift-mlx"),
        .product(name: "PixArtCore", package: "pixart-swift-mlx"),  // NEW
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "YAML", package: "universal"),
        .product(name: "JSON", package: "universal"),
    ]
)
```

### E11.3 Conditional Dependency (Staging)

Until `pixart-swift-mlx` exists, use a conditional compilation flag:

```swift
#if canImport(PixArtCore)
import PixArtCore
#endif
```

`PixArtEngine` either imports the real package or provides a stub that reports all models as unavailable.

---

## E12. Testing

### E12.1 New Test Files

| File | Tests |
|------|-------|
| `EngineRouterTests.swift` | Router registration, model lookup, unknown engine ID |
| `Flux2EngineTests.swift` | Descriptor properties, feature support, request mapping |
| `PixArtEngineTests.swift` | Descriptor properties, feature support, unavailable stub |
| `GenerationRequestTests.swift` | Request construction, mode variants |
| `LoRACompatibilityTests.swift` | Engine tag matching, incompatible LoRA fallback |

### E12.2 Existing Test Updates

- `VinetasModelTests.swift` — add `.pixartSigma` case coverage
- `VinetasModelManagerTests.swift` — verify engine-aware routing
- `PromptCompositionTests.swift` — unchanged (composition is above engine line)
- `CharacterTests.swift` — add `compatibleEngines` field tests

### E12.3 Testing Strategy

Engine protocol conformance tests use a `MockEngine: ImageGenerationEngine` that records calls and returns canned results. This lets the router, facade, and character logic be tested without loading real models.

---

## E13. Migration Path

Ordered steps to minimize breakage:

1. **Add `Engine/` directory** with protocol, types, and `EngineRouter` (no behavior change yet)
2. **Implement `Flux2Engine`** wrapping existing `VinetasPipeline` code
3. **Wire `EngineRouter`** into `Vinetas.swift` — all existing tests must still pass
4. **Add `VinetasModel.pixartSigma`** case with descriptor
5. **Add `PixArtEngine` stub** (reports unavailable, throws on generate)
6. **Refactor `VinetasModelManager`** to be engine-aware
7. **Add LoRA engine tagging** to `Character` and `CharacterTrainer`
8. **Deprecate `VinetasPipeline.swift`** — mark internal, remove when Flux2Engine is stable
9. **Integrate `pixart-swift-mlx`** when the package is ready — swap stub for real implementation

Steps 1–8 can ship independently of the PixArt backend existing. The abstraction pays for itself by cleaning up the FLUX.2 integration.

---

## E14. Resolved Design Decisions

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | `ModelDescriptor`: protocol or struct? | **Protocol.** | Engines define their own concrete descriptor types (e.g., `Flux2ModelDescriptor`, `PixArtModelDescriptor`). Each can carry engine-specific internal metadata (FLUX.2 has `flux2Model`, `quantizationConfig`; PixArt has different fields). The protocol requires `Sendable` and `Identifiable where ID == String` but does **not** require `Hashable` — `Hashable` breaks existential usage (`[any ModelDescriptor]`). All lookups use the `id` string. |
| 2 | `EngineRouter`: class or actor? | **Actor.** | Engines like `Flux2Engine` own mutable pipeline state and are themselves actors. The router must safely handle concurrent model lookups and engine resolution. Sync query methods on engines (`isAvailable`, `supports`, `validateMemory`, `diskSize`) are `nonisolated` since they only read static/filesystem state. `Flux2Pipeline` from Flux2Core is `@unchecked Sendable` — wrapping it in an actor-based engine serializes access properly. |
| 3 | `preview()`: FLUX.2-only or all engines? | **FLUX.2-only private fast path.** | `preview()` hardcodes Klein 4B, 4 steps, 512×512 for rapid prompt iteration. It does not route through `EngineRouter` — it resolves directly to the `"flux2"` engine. Revisit when PixArt is integrated (PixArt at 8 steps may be fast enough to serve as its own preview). |
| 4 | `Vinetas` facade: static enum or instance? | **Instance-based `VinetasClient` class** with `VinetasClient.shared` default singleton. | `VinetasClient` is a `public final class` (not actor) because: (a) `EngineRouter` is already an actor providing concurrency safety — double actor hops would add overhead; (b) `VinetasClient` has no mutable state, it holds a router and delegates; (c) understanding features (`classify`, `extractFeatures`, `similarity`) continue to use their own actor singletons directly. The existing `Vinetas` enum becomes a deprecated shim forwarding to `VinetasClient.shared`. |
| 5 | Model API parameter type? | **`any ModelDescriptor` is primary.** | All `VinetasClient` methods accept `any ModelDescriptor` with a default of `VinetasClient.defaultModel`. Static properties on `VinetasClient` (`.klein4B`, `.klein9B`, `.pixartSigmaXL`) provide discoverability without needing to know concrete descriptor types. `VinetasModel` enum is deprecated with a `.descriptor` bridge. |
| 6 | `LoRAMetadata.model` or `compatibleEngines`? | **Replace `model: VinetasModel?` with `compatibleEngines: [String]`.** | Keeping both is redundant. YAML migration: old `model: klein4b` deserializes to `compatibleEngines: ["flux2"]`. New files only write `compatible_engines`. |

### E14.1 `VinetasClient` Shape

```swift
public final class VinetasClient: Sendable {
    public static let shared = VinetasClient()
    public let router: EngineRouter

    /// Default init registers all available engines.
    public init() {
        var engines: [any ImageGenerationEngine] = [Flux2Engine()]
        #if canImport(PixArtCore)
        engines.append(PixArtEngine())
        #endif
        self.router = EngineRouter(engines: engines)
    }

    /// Test init accepts a custom router (inject MockEngine, etc.).
    public init(router: EngineRouter) {
        self.router = router
    }

    // All generation methods accept `any ModelDescriptor`:
    public func generate(
        prompt: String,
        style: StyleConfig? = nil,
        model: any ModelDescriptor = VinetasClient.defaultModel
    ) async throws -> CGImage
}

// Convenience model accessors for discoverability
extension VinetasClient {
    public static var defaultModel: any ModelDescriptor { Flux2ModelDescriptor.klein4B }
    public static var klein4B: any ModelDescriptor { Flux2ModelDescriptor.klein4B }
    public static var klein9B: any ModelDescriptor { Flux2ModelDescriptor.klein9B }
    public static var pixartSigmaXL: any ModelDescriptor { PixArtModelDescriptor.sigmaXL }
}
```

### E14.2 `Flux2Engine` Shape

```swift
public actor Flux2Engine: ImageGenerationEngine {
    public let engineID = "flux2"
    private var pipeline: Flux2Pipeline?
    private var loadedModelID: String?

    // Sync queries are nonisolated — read-only filesystem/static checks
    public nonisolated func supports(_ feature: EngineFeature) -> Bool { ... }
    public nonisolated func isAvailable(_ model: any ModelDescriptor) -> Bool { ... }
    public nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation { ... }
    public nonisolated func diskSize(of model: any ModelDescriptor) -> Int64? { ... }

    // Async lifecycle and generation are actor-isolated
    public func loadModel(_ model: any ModelDescriptor, progress: ...) async throws { ... }
    public func unloadModel() async { ... }
    public func generate(request: GenerationRequest, stepProgress: ...) async throws -> GenerationResult { ... }
    public func loadLoRA(at path: URL, scale: Float) async throws { ... }
    public func unloadLoRA() async { ... }
    public func download(_ model: any ModelDescriptor, progress: ...) async throws { ... }
    public func delete(_ model: any ModelDescriptor) async throws { ... }
}
```

### E14.3 Migration of `Vinetas` Enum and `VinetasModel`

Both `Vinetas` and `VinetasModel` are preserved as deprecated compatibility shims:

```swift
@available(*, deprecated, message: "Use VinetasClient.shared instead")
public enum Vinetas: Sendable {
    public static let version = "0.4.0"

    public static func generate(prompt: String, style: StyleConfig? = nil,
                                model: VinetasModel = .klein4b) async throws -> CGImage {
        try await VinetasClient.shared.generate(
            prompt: prompt, style: style, model: model.descriptor
        )
    }
    // ... all other static methods forward to VinetasClient.shared,
    //     converting VinetasModel → ModelDescriptor via .descriptor
}

@available(*, deprecated, message: "Use ModelDescriptor types directly (e.g., VinetasClient.klein4B)")
public enum VinetasModel: String, Sendable, Codable, CaseIterable {
    case klein4b = "klein4b"
    case klein9b = "klein9b"
    case pixartSigma = "pixart-sigma"

    /// Bridge to ModelDescriptor
    public var descriptor: any ModelDescriptor { ... }
}
```

### E14.4 `PanelOutput` Breaking Change

`PanelOutput.model: VinetasModel` becomes `PanelOutput.modelID: String`. A deprecated computed property and deprecated init provide backward compatibility:

```swift
public struct PanelOutput: Sendable {
    public let modelID: String  // was: model: VinetasModel

    @available(*, deprecated, message: "Use modelID instead")
    public var model: VinetasModel? { VinetasModel(rawValue: modelID) }
}
```

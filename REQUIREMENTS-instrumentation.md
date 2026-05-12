# SwiftVinetas — Instrumentation Requirements

**Status:** Draft, awaiting implementation
**Pattern source:** [Vinetas `docs/INSTRUMENTATION_PLAN.md`](https://github.com/intrusive-memory/Vinetas/blob/development/docs/INSTRUMENTATION_PLAN.md) + Produciesta `Docs/TELEMETRY_IMPL_PATTERN.md`
**Host:** Vinetas
**Depends on:** SwiftTuberia ≥ 0.7.0 (for `TuberiaTensorStat`), flux-2-swift-mlx ≥ 3.2.0, pixart-swift-mlx ≥ 0.7.0
**Priority:** **P2 — last to ship.** Sits on top of every other instrumented library; its events correlate the rest.

---

## 1. Why instrument SwiftVinetas

SwiftVinetas is the **orchestration shim** between Vinetas (the app) and the actual diffusion engines (flux-2-swift-mlx, pixart-swift-mlx) running through SwiftTuberia. Its job is engine selection, request validation, model availability, memory pre-validation, and result packaging. It contains **no diffusion math directly** — every numerical operation is delegated.

Its diagnostic value lies entirely in **handoff**:

- **App → engine handoff.** When Vinetas (the app) calls `VinetasClient.shared.generate(prompt:...)`, SwiftVinetas converts that into a `GenerationRequest`, routes through `EngineRouter` to a concrete engine (Flux2Engine or PixArtEngine), and forwards. Every parameter that crosses this boundary must be recorded with full fidelity — this is the "ground truth" for any downstream investigation.
- **Engine selection rationale.** Why was Flux2Engine picked vs PixArtEngine? `EngineRouter.engine(for:)` does the routing; the criteria (memory tier, model.engineID lookup, feature support) must be observable.
- **Memory pre-validation outcome.** `validateMemory(for:)` returns `MemoryValidation` (`EngineTypes.swift:171`). Whether this passed/failed/warned and which thresholds were hit is critical context for "why did generation fail."
- **Engine feature negotiation.** `EngineFeature` (`EngineTypes.swift:188`) describes capabilities (LoRA, ControlNet, etc.). If the caller asked for a feature the engine doesn't have, telemetry records the request *and* the fallback (or the refusal).
- **Concurrency gate.** Flux2Engine refuses concurrent generation (`Flux2Engine.swift:186`). When that throws, telemetry records the attempted-second-call so the caller's contract violation is forensically visible.
- **Image understanding side-channels.** `ImageClassifier`, `FeatureExtractor`, `VisionTransformer` are independent code paths used by Vinetas for image analysis. They get separate, smaller telemetry coverage.
- **Character / LoRA training.** `CharacterTrainer`, `TrainingDataPreparer`, `ReferenceSheetGenerator` are used for fine-tuning. Out of scope for v1 (Vinetas doesn't run training in production).

What it must NOT surface:
- Any tensor stats from inside the actual generation. That work is done by Tuberia, Flux2Core, and PixArtBackbone — duplicating here would be noise.
- The `VinetasModelManager` static methods individually (config loading, CDN URL setup). Once-per-process operations are observed at the host level.
- Internal `Flux2GenerationResult` → `GenerationResult` translation. The fields are 1:1 mapped.

---

## 2. Coexistence with existing surfaces

| Surface | Purpose | Status |
|---|---|---|
| `stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?` callback on `Flux2Engine.generate` / `PixArtEngine.generate` | UI step progress | **Keep as-is.** Vinetas the app already drives this; telemetry events are a parallel channel. |
| `DownloadProgress`, `LoadProgress` callbacks | UI download / load progress | **Keep as-is.** |
| `VinetasError` enum | User-facing errors | **Keep as-is.** Each throw paired with `errorThrown` emit. |
| `DeviceCapability.current.totalMemoryGB` runtime check (`Vinetas.swift:42`) | Engine registration gate | **Keep as-is.** `engineRegistered` event captures the verdict. |
| Engine-level `isGenerating` flag in `Flux2Engine` | Single-flight concurrency gate | **Keep as-is.** `concurrencyGateRejected` event fires when this rejects. |

---

## 3. Public types to add

```
Sources/SwiftVinetas/Telemetry/
  VinetasTelemetryEvent.swift
  VinetasTelemetryReporter.swift
```

`TuberiaTensorStat` is imported from SwiftTuberia for the (rare) cases where Vinetas snapshots a tensor — currently only in the image-understanding code path.

### 3.1 `VinetasTelemetryEvent.swift`

```swift
import Foundation
import Tuberia  // for TuberiaTensorStat

public enum VinetasTelemetryEvent: Sendable {

    // --- Client lifecycle ---
    case clientInitialized(version: String, registeredEngines: [String], deviceMemoryGB: Int, deviceArch: String)
    case engineRegistered(engineID: String, reason: String)        // e.g. "Flux2Engine registered (16+ GB memory)"
    case engineSkipped(engineID: String, reason: String)           // e.g. "Flux2Engine skipped (only 8 GB)"

    // --- Generation request handoff (memory boundary on start/end) ---
    case generationStart(
        runID: UUID,
        prompt: String,
        promptLength: Int,
        engineID: String,
        modelID: String,
        steps: Int,
        guidanceScale: Double,
        seed: UInt64,
        width: Int,
        height: Int,
        mode: GenerationModeTag,
        referenceImageCount: Int,
        loraAttached: Bool,
        loraScale: Double?,
        upsamplePromptRequested: Bool,
        interpretImageCount: Int
    )
    case generationEnd(
        runID: UUID,
        engineID: String,
        modelID: String,
        success: Bool,
        durationSeconds: Double,
        outputDims: [Int]?,
        actualSeed: UInt64?
    )
    // Adapter routes generationStart and generationEnd through captureWithMemorySnapshot.

    // --- Engine routing ---
    case engineSelected(engineID: String, modelID: String, requestedFeature: String?, fallbackUsed: Bool)
    case engineNotFound(modelID: String, requestedEngineID: String)
    case engineFeatureNegotiated(engineID: String, requestedFeatures: [String], supportedFeatures: [String], unsupportedFeatures: [String])

    // --- Memory pre-validation ---
    case memoryValidationStart(modelID: String, engineID: String, estimatedRequiredMB: Double, availableMB: Double)
    case memoryValidationResult(modelID: String, engineID: String, verdict: MemoryVerdict, requiredMB: Double, availableMB: Double)

    // --- Model lifecycle ---
    case modelLoadStart(modelID: String, engineID: String)
    case modelLoadComplete(modelID: String, engineID: String, durationSeconds: Double)
    case modelUnload(modelID: String, engineID: String)
    case modelAvailabilityChecked(modelID: String, available: Bool)
    case modelDeleted(modelID: String)

    // --- Concurrency gate ---
    case concurrencyGateRejected(engineID: String, modelID: String, reason: String)

    // --- LoRA at the engine level ---
    case loraAttachStart(engineID: String, sourceURL: String, scale: Double)
    case loraAttachComplete(engineID: String, sourceURL: String, durationSeconds: Double)

    // --- Image understanding side-channels (used by ImageClassifier/FeatureExtractor) ---
    case classifierForwardStart(imageDims: [Int])
    case classifierForwardComplete(topLabel: String, topScore: Double, top5Labels: [String], top5Scores: [Double], durationSeconds: Double)
    case featureExtractionStart(imageDims: [Int])
    case featureExtractionComplete(featureDim: Int, featureStat: TuberiaTensorStat, durationSeconds: Double)

    // --- Error side-channel ---
    case errorThrown(phase: ErrorPhase, errorDescription: String, runID: UUID?)

    public enum GenerationModeTag: String, Sendable {
        case textToImage
        case imageToImage
        case preview
    }

    public enum MemoryVerdict: String, Sendable {
        case sufficient
        case warningMarginal     // enough to start but close to the line
        case insufficient
        case unavailable         // device query failed
    }

    public enum ErrorPhase: String, Sendable {
        case clientInit
        case engineRouting
        case engineNotFound
        case modelNotSupported
        case modelNotFound
        case modelDownload
        case modelLoad
        case memoryValidation
        case generationFailed
        case generationConcurrency
        case loraAttach
        case classifierForward
        case featureExtraction
        case other
    }
}
```

**On `runID`.** This is the same UUID that Vinetas's app-side `GenerationActor` passes to `GenerationTelemetry.startRun`. SwiftVinetas accepts it via an extension parameter on the generate API (see §4.3) so every event downstream can be correlated to a single user-initiated generation.

### 3.2 `VinetasTelemetryReporter.swift`

```swift
public protocol VinetasTelemetryReporter: Sendable {
    func capture(_ event: VinetasTelemetryEvent) async
}

public struct NoopVinetasTelemetryReporter: VinetasTelemetryReporter {
    public init() {}
    public func capture(_ event: VinetasTelemetryEvent) async {}
}
```

---

## 4. Injection points

### 4.1 `VinetasClient` (the `public final class Sendable`, `Vinetas.swift:24`)

`VinetasClient` is `Sendable` and immutable post-init (its `router` is a `let`). Storing a mutable telemetry reporter requires the `OSAllocatedUnfairLock` pattern:

```swift
import os.lock

public final class VinetasClient: Sendable {
    public let router: EngineRouter
    public static let version = "0.11.0-dev"

    private let _telemetryLock = OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>(initialState: nil)

    public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
        _telemetryLock.withLock { $0 = reporter }
        // Propagate to the router and through to each engine
        await router.setTelemetry(reporter)
    }

    internal func currentTelemetry() -> (any VinetasTelemetryReporter)? {
        _telemetryLock.withLock { $0 }
    }
}
```

### 4.2 `EngineRouter` (actor, `EngineRouter.swift:19`)

```swift
public actor EngineRouter {
    private var telemetry: (any VinetasTelemetryReporter)? = nil

    public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
        self.telemetry = reporter
        for engine in engines {
            await engine.setTelemetry(reporter)  // protocol seam — see §4.3
        }
    }
}
```

### 4.3 `ImageGenerationEngine` protocol extension

A new optional protocol method (defaulted to no-op) added to `ImageGenerationEngine`:

```swift
public protocol ImageGenerationEngine: Sendable {
    // ... existing methods ...

    /// Inject a telemetry reporter. Default implementation is a no-op so engines
    /// that opt out (or live in older binaries) continue to compile.
    func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async
}

extension ImageGenerationEngine {
    public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
        // No-op default — engines override to wire telemetry into their internal pipelines.
    }
}
```

`Flux2Engine` and `PixArtEngine` override this. Inside the override they (a) store the Vinetas reporter locally so they can emit Vinetas-level events about generation, and (b) construct a thin shim that bridges `Flux2TelemetryEvent` / `PixArtTelemetryEvent` events back to the host adapter. The host typically prefers to wire the Flux2 and PixArt reporters directly itself; the Vinetas-level engine just emits Vinetas-level events.

### 4.4 Static `Vinetas` enum entry points

`Vinetas.swift` exposes static convenience entry points (`Vinetas.generate(prompt:)`, etc.). These get a defaulted `telemetry:` parameter:

```swift
public static func generate(
    prompt: String,
    /* ... existing params ... */,
    telemetry: (any VinetasTelemetryReporter)? = nil  // ← added
) async throws -> CGImage
```

If not provided, falls back to `VinetasClient.shared.currentTelemetry()`. This means existing call sites continue to work; instrumented call sites pass an explicit reporter.

### 4.5 Image understanding types

`ImageClassifier` and `FeatureExtractor` are actors (`ImageClassifier.swift`, `FeatureExtractor.swift`). Each gets a `setTelemetry(_:)` setter that stores `(any VinetasTelemetryReporter)?`. The `VinetasClient.setTelemetry` propagation hits them too (extend the propagation logic in §4.1).

---

## 5. Per-event emission spec

| Event | Emission site (file:line) | Notes |
|---|---|---|
| `clientInitialized` | `VinetasClient.init()` end (`Vinetas.swift:51`) | Once per process (singleton). Includes `DeviceCapability.current` snapshot. |
| `engineRegistered` / `engineSkipped` | Inside the engine registration block (`Vinetas.swift:42–48`) | Two events for Flux2Engine (registered or skipped) + one for PixArtEngine (always registered). |
| `generationStart` | `Vinetas.generate(...)` and `Vinetas.preview(...)` entry (`Vinetas.swift:83, 226`) and parallel entries in `Flux2Engine.generate(...)` / `PixArtEngine.generate(...)` (`Flux2Engine.swift:185`) | **Memory snapshot.** The `runID` is either passed in by the caller (preferred — matches the app-side run UUID) or generated. |
| `generationEnd` | Same call sites, success and failure paths via `defer` | **Memory snapshot.** Carries success Bool, durationSeconds. |
| `engineSelected` | After `router.engine(for: model)` returns successfully (`EngineRouter.swift:61`) | Once per generate. |
| `engineNotFound` | Inside `throw VinetasError.engineNotFound` branch (`EngineRouter.swift:63, 76`) | Before throw. |
| `engineFeatureNegotiated` | When the caller passes a `feature:` hint and the engine resolves it | 0–1 per generate. |
| `memoryValidationStart` / `Result` | Around `validateMemory(for:)` (`Vinetas.swift:315`) | One pair per generate. |
| `modelLoadStart` / `Complete` | Around `engine.loadModel(_:progress:)` (`Flux2Engine.swift:131`, `PixArtEngine` equivalent) | One pair per first-time-this-process load. |
| `modelUnload` | Inside `unloadModel()` (`Flux2Engine.swift:172`) | Once per unload. |
| `modelAvailabilityChecked` | Inside `isAvailable(_:)` (`Vinetas.swift:269`) | One per check. |
| `modelDeleted` | Inside `delete(_:)` (`Vinetas.swift:277`) | One per delete. |
| `concurrencyGateRejected` | Inside the `guard !isGenerating else { throw ... }` block (`Flux2Engine.swift:186–189`) | Before throw. |
| `loraAttachStart` / `Complete` | Around `Flux2Engine.loadLoRA(at:scale:)` (`Flux2Engine.swift:263`) | One pair per LoRA attach. |
| `classifierForwardStart` / `Complete` | Around `ImageClassifier.classify(...)` | Used by image-understanding code path only. |
| `featureExtractionStart` / `Complete` | Around `FeatureExtractor.extract(...)` | Used by image-understanding code path only. |
| `errorThrown` | Every `throw VinetasError.…` in `EngineRouter.swift:63, 76`, `Flux2Engine.swift:133, 187, 192, 223, 244, 265, 271, 296, 311, 326`, `Vinetas.swift:85` and equivalents in `PixArtEngine.swift` | Fire immediately before throw. |

### Hot-path discipline

SwiftVinetas does no per-step work. Its events fire at most a few dozen times per generation (start, route, validate, load, end, plus errors). No `TuberiaTensorStat` calls are required on the main generation path — the underlying libraries handle that. The `featureExtractionComplete` event is the one exception (one tensor stat per `extract()` call).

The `OSAllocatedUnfairLock` on `VinetasClient.telemetry` is touched only at run boundaries — negligible cost.

---

## 6. Adapter mapping (Vinetas host side)

`VinetasEngineTelemetryAdapter` at `Vinetas/Telemetry/Adapters/VinetasEngineTelemetryAdapter.swift`:

| Event | Sink phase | Memory snapshot? |
|---|---|---|
| `clientInitialized` | `vinetas_client_init` | no |
| `engineRegistered` / `engineSkipped` | `vinetas_engine_registered_<id>` / `vinetas_engine_skipped_<id>` | no |
| `generationStart` | `vinetas_generation_start` | **yes** (per INSTRUMENTATION_PLAN §3.1) |
| `generationEnd` | `vinetas_generation_end` | **yes** |
| `engineSelected` | `vinetas_engine_selected_<id>` | no |
| `engineNotFound` | `vinetas_engine_not_found` | no |
| `engineFeatureNegotiated` | `vinetas_feature_negotiated` | no |
| `memoryValidationStart` | `vinetas_memval_start` | no |
| `memoryValidationResult` | `vinetas_memval_<verdict>` | no |
| `modelLoadStart` / `Complete` | `vinetas_model_load_start` / `vinetas_model_load_complete` | no (boundary memory event is emitted by flux/pixart's own weightLoadComplete) |
| `modelUnload` | `vinetas_model_unload` | no |
| `modelAvailabilityChecked` | `vinetas_model_available_<bool>` | no |
| `modelDeleted` | `vinetas_model_deleted` | no |
| `concurrencyGateRejected` | `vinetas_concurrency_rejected` | no |
| `loraAttachStart` / `Complete` | `vinetas_lora_attach_start` / `vinetas_lora_attach_complete` | no |
| `classifierForwardStart` / `Complete` | `vinetas_classifier_start` / `vinetas_classifier_complete` | no |
| `featureExtractionStart` / `Complete` | `vinetas_feature_extract_start` / `vinetas_feature_extract_complete` | no |
| `errorThrown` | `vinetas_error_<phase>` | no |

Exhaustive switch.

---

## 7. Tests

Add to `Tests/SwiftVinetasTests/`:

| Test | Purpose |
|---|---|
| `VinetasTelemetryClientInitTests` | Construct `VinetasClient()` through `MockReporter`. Assert `clientInitialized`, plus the correct `engineRegistered`/`engineSkipped` pair based on a mocked `DeviceCapability`. |
| `VinetasTelemetryHandoffTests` | Invoke `Vinetas.generate(prompt: "...", telemetry: mock)` against a mocked engine. Assert `generationStart` carries every field of the request (prompt, dims, seed, steps, guidance) and that the prompt string is verbatim. |
| `VinetasTelemetryEngineRoutingTests` | Build a router with two mock engines, request a model belonging to neither. Assert `engineNotFound` fires **before** the throw and `errorThrown(phase: .engineNotFound, ...)` fires next. |
| `VinetasTelemetryConcurrencyTests` | Call `Flux2Engine.generate(...)` twice concurrently (the second await before the first resolves). Assert `concurrencyGateRejected` fires before the second call throws. |
| `VinetasTelemetryMemoryValidationTests` | Drive `validateMemory` through mocked DeviceCapability for each `MemoryVerdict`. Assert correct verdict in event. |
| `VinetasTelemetryNoopOverheadTests` | 100 generate() calls (with mocked engine) through `nil` and `NoopVinetasTelemetryReporter`. Wall-clock medians within ±2%. |

---

## 8. Out of scope (v1)

- `CharacterTrainer`, `TrainingDataPreparer`, `ReferenceSheetGenerator`. Vinetas the app does not run training in production. Future iteration if/when training ships.
- `LoRAManager` internals. The `loraAttachStart/Complete` event covers what callers need.
- `PromptFile`, `StyleConfig` parsing telemetry. These are one-shot file I/O operations covered implicitly by `generationStart.prompt` being the post-parse value.
- `VisionTransformer` internal layer-by-layer events. `classifierForwardComplete` summarizes the result.
- `AspectRatio` enum parsing. Internal, deterministic, no useful event surface.

---

## 9. Versioning

**Minor** version bump (additive). Pin floor: `0.12.0` post-release. Must ship AFTER all four other intrusive-memory libraries — SwiftVinetas's runtime depends on them and its events reference their event types (indirectly, through the adapter's view in the host).

---

## 10. Implementation checklist

- [ ] Add `Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` per §3.1
- [ ] Add `Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` per §3.2
- [ ] Add `OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>` + `setTelemetry`/`currentTelemetry` to `VinetasClient`
- [ ] Add `setTelemetry(_:)` to `EngineRouter` and propagate to engines
- [ ] Extend `ImageGenerationEngine` protocol with defaulted `setTelemetry(_:)` and override in `Flux2Engine` + `PixArtEngine`
- [ ] Add defaulted `telemetry:` parameter to `Vinetas.generate`, `Vinetas.generateSequence`, `Vinetas.preview`
- [ ] Add `setTelemetry` to `ImageClassifier` and `FeatureExtractor`
- [ ] Wire emission sites per §5; ensure every `throw` is preceded by `errorThrown`
- [ ] Add tests per §7
- [ ] Run baseline overhead test (100 mocked-engine generations, ±2%)
- [ ] Tag release with `MINOR` bump (this is the final library in the instrumentation rollout — ship last)

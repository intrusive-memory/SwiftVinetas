# SwiftVinetas — Instrumentation Requirements

**Status:** Ready for implementation. All dependency floors raised in `bf5b867`.
**Pattern source:** [Vinetas `docs/INSTRUMENTATION_PLAN.md`](https://github.com/intrusive-memory/Vinetas/blob/development/docs/INSTRUMENTATION_PLAN.md) + Produciesta `Docs/TELEMETRY_IMPL_PATTERN.md`
**Host:** Vinetas
**Depends on (all met):** SwiftTuberia ≥ 0.7.0 (for `TuberiaTensorStat`), flux-2-swift-mlx ≥ 3.2.0, pixart-swift-mlx ≥ 0.7.0, SwiftAcervo ≥ 0.13.0.
**Target release:** **0.12.0** (minor bump from current `0.11.0-dev`). Matches the dep cohort, all of which shipped telemetry at their next minor.
**Priority:** **P2 — last to ship.** Sits on top of every other instrumented library; its events correlate the rest at the app-boundary layer.

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

## 2.5 Available dependency telemetry surfaces (host wires these directly)

The four intrusive-memory deps SwiftVinetas pulls in each ship their own reporter protocol + event enum, exported as public symbols:

| Dependency | Reporter protocol | Event enum | Module to import |
|---|---|---|---|
| SwiftTuberia ≥ 0.7.0 | `TuberiaTelemetryReporter` | `TuberiaTelemetryEvent` | `Tuberia` |
| flux-2-swift-mlx ≥ 3.2.0 | `Flux2TelemetryReporter` | `Flux2TelemetryEvent` | `Flux2Core` |
| pixart-swift-mlx ≥ 0.7.0 | `PixArtTelemetryReporter` | `PixArtTelemetryEvent` | `PixArtBackbone` |
| SwiftAcervo ≥ 0.13.0 | `AcervoTelemetryReporter` | `AcervoTelemetryEvent` | `SwiftAcervo` |

Each also exports a `Noop<Lib>TelemetryReporter` value type for tests and the "telemetry-on but doing nothing" overhead baseline. The `TuberiaTensorStat` summary type is re-exported from `Tuberia` and is the canonical Sendable bag for tensor snapshots used across all four event payloads.

**Boundary contract (the part this doc binds to):** The host owns adapter conformance for all five protocols (the four above plus `VinetasTelemetryReporter` from this doc). SwiftVinetas does **not** bridge dep events into its own event surface, and does **not** wrap dep reporters. Each library's events flow to its own host-side adapter (`Flux2TelemetryAdapter`, `TuberiaTelemetryAdapter`, etc. per `Vinetas/Telemetry/Adapters/`). SwiftVinetas's only job is emitting Vinetas-scoped events — see §4.3.

**runID convention.** SwiftVinetas events do not carry a `runID`. The host's `GenerationActor` mints a per-generation UUID, stores it on each adapter via `setRunID(_:)`, and the adapter stamps every forwarded event with the current runID via `GenerationTelemetry.capture(runID:phase:payload:)`. This matches the dep-event enums (none of which carry `runID` either) and avoids duplicating cross-cutting metadata into every payload.

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
    case errorThrown(phase: ErrorPhase, errorDescription: String)

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

**On correlation.** SwiftVinetas events do not carry a `runID`. The host-side `VinetasEngineTelemetryAdapter` holds the current run UUID (updated by `GenerationActor` between runs) and stamps it onto every event it forwards via `GenerationTelemetry.capture(runID:phase:payload:)`. This matches the dep-event enums and is the contract documented in §2.5.

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

`Flux2Engine` and `PixArtEngine` override this. The override **only** stores the Vinetas reporter for engine-scoped Vinetas events that are not naturally covered by dep-level events: `concurrencyGateRejected` (Flux2 only — PixArt's `isGenerating` gate emits the same event but with `engineID = "pixart"`), `loraAttachStart` / `loraAttachComplete`, and `errorThrown(phase:)` for engine-internal throws.

The override does **NOT** bridge `Flux2TelemetryEvent` or `PixArtTelemetryEvent` into `VinetasTelemetryEvent`. The host wires those dep reporters directly via the deps' own `setTelemetry(_:)` seams (see §2.5). Bridging would (a) duplicate every transformer/scheduler/VAE event into the Vinetas surface, polluting the handoff signal §1 calls out as SwiftVinetas's reason to exist, and (b) couple SwiftVinetas's event schema to upstream changes in Flux2/PixArt enums — a maintenance trap.

### 4.4 Static `Vinetas` enum entry points

`Vinetas.swift:412` exposes static convenience entry points (`Vinetas.generate(prompt:)`, `Vinetas.preview(prompt:)`, etc.). These are pure wrappers around `VinetasClient.shared.<method>`. They get **no** new parameters.

Telemetry is wired exactly once per process via `VinetasClient.shared.setTelemetry(reporter)` at app startup (typically from `GenerationActor.init` in the host). The static wrappers inherit that setting transitively. A per-call `telemetry:` parameter was considered and rejected:

- The host's adapter holds the runID and forwards every event through a single sink — there is no consumer that benefits from per-call routing.
- Per-call optionality would force every emission site to accept and thread a reporter argument, doubling the API surface for no observable gain.
- Tests inject reporters by constructing a `VinetasClient(router:)` with a mock router and calling `setTelemetry` directly — same path as production.

### 4.5 Image understanding types

`ImageClassifier` and `FeatureExtractor` are actors (`ImageClassifier.swift`, `FeatureExtractor.swift`). Each gets a `setTelemetry(_:)` setter that stores `(any VinetasTelemetryReporter)?`. The `VinetasClient.setTelemetry` propagation hits them too (extend the propagation logic in §4.1).

---

## 5. Per-event emission spec

**Single-emission rule.** Every event below has exactly one canonical emission site. The previous draft double-counted `generationStart`/`generationEnd` at both `VinetasClient.generate` and `<Engine>.generate` — that produced two events per run for one logical boundary. Resolution: emit at the `VinetasClient` API boundary only (rationale below the table).

| Event | Emission site (file:line) | Notes |
|---|---|---|
| `clientInitialized` | End of `VinetasClient.init()` (`Vinetas.swift:51`) | Once per process (singleton). Includes `DeviceCapability.current` snapshot. |
| `engineRegistered` / `engineSkipped` | Inside the engine-registration block (`Vinetas.swift:45–48`) | One `engineRegistered` for PixArtEngine (always) + one of `engineRegistered`/`engineSkipped` for Flux2Engine depending on the 16 GB gate. |
| `generationStart` | `VinetasClient.generate(...)` entry (`Vinetas.swift:79`, `113`, `167`) and `VinetasClient.preview(...)` entry (`Vinetas.swift:226`) | **Memory snapshot.** `mode` carries `.textToImage`, `.imageToImage`, or `.preview` to disambiguate the four entry points. Do NOT also emit inside `<Engine>.generate`. |
| `generationEnd` | Same four sites; success and failure paths via `defer` | **Memory snapshot.** Carries `success`, `durationSeconds`. |
| `engineSelected` | After `router.engine(for: model)` returns successfully (`EngineRouter.swift:61`) | Once per generate. |
| `engineNotFound` | Inside the `throw VinetasError.engineNotFound` branches (`EngineRouter.swift:63, 76`) | Before throw. |
| `engineFeatureNegotiated` | When a caller passes a `feature:` hint and the engine resolves it (none today; reserved for the LoRA/ControlNet expansion) | 0–1 per generate. |
| `memoryValidationStart` / `Result` | Around `VinetasClient.validateMemory(for:)` (`Vinetas.swift:315`) | One pair per generate. |
| `modelLoadStart` / `Complete` | Around `engine.loadModel(_:progress:)` (`Flux2Engine.swift:128`, `PixArtEngine.swift:128` equivalent — verify on implement) | One pair per first-time-this-process load. |
| `modelUnload` | Inside `Flux2Engine.unloadModel()` (`Flux2Engine.swift:172`) and `PixArtEngine.unloadModel()` equivalent | Once per unload. |
| `modelAvailabilityChecked` | Inside `VinetasClient.isAvailable(_:)` (`Vinetas.swift:269`) | One per check. |
| `modelDeleted` | Inside `VinetasClient.delete(_:)` (`Vinetas.swift:277`) | One per delete. |
| `concurrencyGateRejected` | Inside the `guard !isGenerating else { throw ... }` blocks (`Flux2Engine.swift:186–187`, `PixArtEngine.swift:218–219`) | Before throw. |
| `loraAttachStart` / `Complete` | Around `Flux2Engine.loadLoRA(at:scale:)` (`Flux2Engine.swift:263`) and `PixArtEngine.loadLoRA(at:scale:)` (`PixArtEngine.swift:284`) | One pair per LoRA attach. |
| `classifierForwardStart` / `Complete` | Around `ImageClassifier.classify(...)` | Image-understanding code path only. |
| `featureExtractionStart` / `Complete` | Around `FeatureExtractor.extract(...)` | Image-understanding code path only. |
| `errorThrown` | Every `throw VinetasError.…` site: `EngineRouter.swift:63, 76`; `Flux2Engine.swift:133, 187, 192, 223, 244, 265, 271, 296, 311, 326`; `PixArtEngine.swift:135, 180, 193, 219, 224, 231, 256, 263, 286, 291, 313, 321, 332, 348, 383, 399`; `Vinetas.swift:85` (and other instance/static throws as they grow) | Fire immediately before throw. The `phase:` discriminant matches the enum in §3.1. |

**Why VinetasClient-level emission for `generationStart`/`End`, not engine-level:**
- The host plan's boundary memory phases are `vinetas_generation_start` / `vinetas_generation_end` (host plan §3.1) — defined at the Vinetas API boundary, not the engine boundary.
- `mode: .preview` and `mode: .imageToImage` are VinetasClient-level concepts; the engines don't know which entry point dispatched them.
- The engine boundary is already covered by `Flux2TelemetryEvent.pipelineStart` / `PixArtTelemetryEvent.pipelineStart` flowing through the host's `Flux2TelemetryAdapter` / `PixArtTelemetryAdapter`. A duplicate `generationStart` from inside the engine would just shadow those.
- Tests that drive engines directly with a mock router still exercise `VinetasClient(router:)`, so emission coverage is unchanged.

### Hot-path discipline

SwiftVinetas does no per-step work. Its events fire at most a few dozen times per generation (start, route, validate, load, end, plus errors). No `TuberiaTensorStat` calls are required on the main generation path — the underlying libraries handle that. The `featureExtractionComplete` event is the one exception (one tensor stat per `extract()` call).

The `OSAllocatedUnfairLock` on `VinetasClient.telemetry` is touched only at run boundaries — negligible cost.

---

## 6. Adapter mapping (Vinetas host side)

`VinetasEngineTelemetryAdapter` at `Vinetas/Telemetry/Adapters/VinetasEngineTelemetryAdapter.swift`. The adapter holds the current `runID: UUID` (set by `GenerationActor` between runs via `setRunID(_:)`) and stamps every forwarded event with it through `GenerationTelemetry.capture(runID:phase:payload:)` or `captureWithMemorySnapshot(runID:phase:payload:)`. SwiftVinetas itself never sees the runID — see §2.5.

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
| `VinetasTelemetryClientInitTests` | Build `VinetasClient(router:)` with a mock router, attach `MockReporter` via `setTelemetry`, then assert `clientInitialized` fires once and the correct `engineRegistered`/`engineSkipped` pair fires based on injected `DeviceCapability`. |
| `VinetasTelemetryPropagationTests` | Call `VinetasClient.setTelemetry(reporter)`. Assert the reporter reaches `EngineRouter` (via its actor-internal state), every `ImageGenerationEngine` in the router (via `setTelemetry` override), and `ImageClassifier` / `FeatureExtractor`. Then call `setTelemetry(nil)` and assert teardown. |
| `VinetasTelemetryHandoffTests` | Invoke `VinetasClient.generate(...)` against a mock engine. Assert `generationStart` fires exactly once (no double-emission from the engine), carries every field of the request verbatim (prompt, dims, seed, steps, guidance, mode), and is followed by `generationEnd` with `success: true` and a finite `durationSeconds`. |
| `VinetasTelemetryEngineRoutingTests` | Build a router with two mock engines, request a model belonging to neither. Assert `engineNotFound` fires **before** the throw and `errorThrown(phase: .engineNotFound, ...)` fires next. |
| `VinetasTelemetryConcurrencyTests` | Call `Flux2Engine.generate(...)` twice concurrently (second `await` before the first resolves). Assert `concurrencyGateRejected` fires before the second call throws and that the failing path emits `generationEnd(success: false)`. Repeat for `PixArtEngine`. |
| `VinetasTelemetryMemoryValidationTests` | Drive `validateMemory(for:)` through mocked `DeviceCapability` to produce each `MemoryVerdict`. Assert the correct verdict appears in `memoryValidationResult`. |
| `VinetasTelemetryNoopOverheadTests` | 100 `VinetasClient.generate()` calls (with mocked engine) under three configs: `nil` reporter, `NoopVinetasTelemetryReporter`, and a counting reporter. Assert wall-clock median delta between `nil` and `Noop` within ±2% (the dep convention from `TuberiaTelemetryNoopOverheadTests`). |

---

## 8. Out of scope (v1)

- `CharacterTrainer`, `TrainingDataPreparer`, `ReferenceSheetGenerator`. Vinetas the app does not run training in production. Future iteration if/when training ships.
- `LoRAManager` internals. The `loraAttachStart/Complete` event covers what callers need.
- `PromptFile`, `StyleConfig` parsing telemetry. These are one-shot file I/O operations covered implicitly by `generationStart.prompt` being the post-parse value.
- `VisionTransformer` internal layer-by-layer events. `classifierForwardComplete` summarizes the result.
- `AspectRatio` enum parsing. Internal, deterministic, no useful event surface.

---

## 9. Versioning

**Minor** version bump (additive). Current is `0.11.0-dev`; ship as **`0.12.0`**. The dep cohort already shipped telemetry at their next minor (`flux-2-swift-mlx 3.2.0`, `SwiftAcervo 0.13.0`, `SwiftTuberia 0.7.0`, `pixart-swift-mlx 0.7.0`), and SwiftVinetas's runtime depends on those.

Post-release, the next downstream consumer pin should be `from: "0.12.0"`. The Vinetas host should also bump SwiftVinetas in `Vinetas/Package.swift` (or wherever the SPM dep lives) once `0.12.0` ships, since the host's `VinetasEngineTelemetryAdapter` will fail to compile without the new public types.

---

## 10. Implementation checklist

- [ ] Add `Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` per §3.1 (no `runID` fields)
- [ ] Add `Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` per §3.2 (protocol + `NoopVinetasTelemetryReporter`)
- [ ] Add `OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>` + `setTelemetry(_:)` + `currentTelemetry()` to `VinetasClient` (`Vinetas.swift:22`)
- [ ] Add `setTelemetry(_:)` to `EngineRouter` (actor at `EngineRouter.swift:19`) and propagate to every engine and to `ImageClassifier` / `FeatureExtractor`
- [ ] Extend `ImageGenerationEngine` protocol with defaulted `setTelemetry(_:)`; override in `Flux2Engine` and `PixArtEngine` per §4.3 (engine-scoped events only — no dep-event bridging)
- [ ] Wire emission sites per §5: `generationStart`/`End` at `VinetasClient.generate/preview` only, never inside `<Engine>.generate`
- [ ] Ensure every `throw VinetasError.…` in `EngineRouter.swift`, `Flux2Engine.swift`, `PixArtEngine.swift`, and `Vinetas.swift` is preceded by `errorThrown(phase:errorDescription:)` with the matching `ErrorPhase`
- [ ] Add tests per §7, including the propagation test that asserts `setTelemetry` reaches router → engines → understanding actors
- [ ] Run `VinetasTelemetryNoopOverheadTests` and verify ±2% wall-clock delta between `nil` and `Noop` reporters
- [ ] Bump `VinetasClient.version` from `"0.11.0-dev"` to `"0.12.0"` and tag (final library in the instrumentation rollout — ship last)
- [ ] In a follow-up PR on `Vinetas/`, bump the SwiftVinetas pin to `from: "0.12.0"` and add `VinetasEngineTelemetryAdapter` per host plan §2.1

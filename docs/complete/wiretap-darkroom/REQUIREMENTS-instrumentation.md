# SwiftVinetas — Instrumentation Requirements

**Status:** Ready for implementation. Cross-repo dependency floors raised in `bf5b867` (2026-05-11).
**Scope:** Library + CLI + Integration test. **Single shipping unit.** The three layers ship together so the integration test can validate the library and CLI on every PR.
**Pattern sources:**
- Library shape: [Vinetas `docs/INSTRUMENTATION_PLAN.md`](https://github.com/intrusive-memory/Vinetas/blob/development/docs/INSTRUMENTATION_PLAN.md), Produciesta `Docs/TELEMETRY_IMPL_PATTERN.md`
- CLI shape: [Produciesta `produciesta-cli/GenerateCommand.swift`](/Users/stovak/Projects/Produciesta/produciesta-cli/GenerateCommand.swift) + [`ProduciestaCore/GenerationOrchestrator.swift`](/Users/stovak/Projects/Produciesta/ProduciestaCore/GenerationOrchestrator.swift)
- Integration test shape: existing `make test-integration` target in this repo

**Hosts:** Vinetas (the iOS/macOS app, out of scope for *this* repo's PR but the contract this doc defines), the `vinetas` CLI (in scope), and the integration test target (in scope).

**Depends on (all met):** SwiftTuberia ≥ 0.7.0 (`TuberiaTensorStat`, `TuberiaTelemetryReporter`), flux-2-swift-mlx ≥ 3.2.0 (`Flux2TelemetryReporter`), pixart-swift-mlx ≥ 0.7.0 (`PixArtTelemetryReporter`), SwiftAcervo ≥ 0.13.0 (`AcervoTelemetryReporter`).

**Target release:** `0.12.0` (minor bump from current `0.11.0-dev`). The dep cohort already shipped telemetry at their next minor.

---

## 1. Why instrument SwiftVinetas + CLI + integration test as one unit

SwiftVinetas is the **orchestration shim** between any host (the Vinetas app, the `vinetas` CLI, the integration test) and the concrete diffusion engines (flux-2-swift-mlx, pixart-swift-mlx) running through SwiftTuberia. It contains no diffusion math directly — every numerical operation is delegated. Its diagnostic value lies entirely in **handoff fidelity**: prompt, dims, seed, steps, guidance, engine selection rationale, memory verdict, model lifecycle, concurrency rejections, LoRA attaches, and image-understanding side channels.

Three layers, one mission:

1. **Library layer** (SwiftVinetas) emits `VinetasTelemetryEvent` at every cross-boundary handoff in `VinetasClient`, `EngineRouter`, `Flux2Engine`, `PixArtEngine`, `ImageClassifier`, and `FeatureExtractor`.
2. **CLI host layer** (`VinetasCLICore` + the `vinetas` binary) gains a `--telemetry` flag on generation-producing subcommands. When set, it constructs five adapters (one per reporter protocol) that forward every event from every instrumented library into a single JSONL trace file. The CLI is a thin host — the same role `VinetasEngineTelemetryAdapter` plays in the Vinetas iOS/macOS app.
3. **Integration test layer** is a compiled XCTest that:
   - Drives a real start-to-finish generation against cached model weights.
   - Captures the full five-library trace through the same `--telemetry` path the CLI uses.
   - Asserts trace fidelity (event ordering, presence of required events, runID coherence at the host adapter layer).
   - **Serves as a runnable debugging harness** for the generation function. When a downstream user reports "generation produces garbage with prompt X," the developer runs `make test-telemetry-debug PROMPT="…"` and gets a JSONL trace they can inspect.

Why ship all three together: the library work is unobservable without a host that wires it. The integration test is the cheapest possible host — runnable on every PR, no UI required, no manual steps. Bundling them means a single PR closes the loop: library produces events, CLI wires them, integration test proves they show up.

### What the library must NOT surface

- Any tensor stats from inside the actual generation. That work is done by SwiftTuberia, Flux2Core, and PixArtBackbone — duplicating here would be noise.
- The `VinetasModelManager` static methods individually (config loading, CDN URL setup). Once-per-process operations are observed at the host level.
- Internal `Flux2GenerationResult` → `GenerationResult` translation. The fields are 1:1 mapped.

### What the CLI must NOT do

- Bridge events between libraries. Each adapter is bound to exactly one reporter protocol and writes events for its own library only.
- Filter, sample, or pretty-print. v1 writes every event verbatim. Filtering is a v2 ergonomics improvement.
- Run telemetry on every invocation. Off by default — `--telemetry` is opt-in.

---

## 2. Coexistence with existing surfaces

| Surface | Purpose | Status |
|---|---|---|
| `stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?` callback on `Flux2Engine.generate` / `PixArtEngine.generate` | UI step progress | **Keep as-is.** Telemetry events are a parallel channel. |
| `DownloadProgress`, `LoadProgress` callbacks | UI download / load progress | **Keep as-is.** |
| `VinetasError` enum | User-facing errors | **Keep as-is.** Each throw paired with `errorThrown` emit. |
| `DeviceCapability.current.totalMemoryGB` runtime check (`Vinetas.swift:42`) | Engine registration gate | **Keep as-is.** `engineRegistered` event captures the verdict. |
| Engine-level `isGenerating` flag in `Flux2Engine` and `PixArtEngine` | Single-flight concurrency gate | **Keep as-is.** `concurrencyGateRejected` event fires when this rejects. |
| Existing CLI stderr prologue (`[vinetas] Generating panel...`) | Human-readable progress | **Keep as-is.** Telemetry writes go to a separate JSONL file. |

---

## 3. Available dependency telemetry surfaces

The four intrusive-memory deps SwiftVinetas pulls in each ship their own reporter protocol + event enum, exported as public symbols. The CLI consumes all four directly (the SwiftVinetas library does NOT bridge them):

| Dependency | Reporter protocol | Event enum | Module to import |
|---|---|---|---|
| SwiftTuberia ≥ 0.7.0 | `TuberiaTelemetryReporter` | `TuberiaTelemetryEvent` | `Tuberia` |
| flux-2-swift-mlx ≥ 3.2.0 | `Flux2TelemetryReporter` | `Flux2TelemetryEvent` | `Flux2Core` |
| pixart-swift-mlx ≥ 0.7.0 | `PixArtTelemetryReporter` | `PixArtTelemetryEvent` | `PixArtBackbone` |
| SwiftAcervo ≥ 0.13.0 | `AcervoTelemetryReporter` | `AcervoTelemetryEvent` | `SwiftAcervo` |

Each also exports a `Noop<Lib>TelemetryReporter` value type for tests. The `TuberiaTensorStat` summary type is re-exported from `Tuberia` and is the canonical `Sendable` bag for tensor snapshots used across all four event payloads.

**Boundary contract:** Each host (Vinetas app, `vinetas` CLI, integration test) owns adapter conformance for all five protocols (the four above plus `VinetasTelemetryReporter` from this doc). SwiftVinetas **does not** bridge dep events into its own event surface and **does not** wrap dep reporters. Each library's events flow to its own host-side adapter.

**runID convention:** SwiftVinetas events do not carry a `runID`. The host-side adapter (in the Vinetas app, the CLI's bootstrap, or the integration test setup) holds the current run UUID and stamps every forwarded event with it via the host's own envelope format. This matches the dep-event enums (none of which carry `runID` either) and avoids duplicating cross-cutting metadata into every payload.

---

## 4. Library-side public types

```
Sources/SwiftVinetas/Telemetry/
  VinetasTelemetryEvent.swift
  VinetasTelemetryReporter.swift
```

### 4.1 `VinetasTelemetryEvent.swift`

```swift
import Foundation
import Tuberia  // for TuberiaTensorStat

public enum VinetasTelemetryEvent: Sendable {

    // --- Client lifecycle ---
    case clientInitialized(version: String, registeredEngines: [String], deviceMemoryGB: Int, deviceArch: String)
    case engineRegistered(engineID: String, reason: String)
    case engineSkipped(engineID: String, reason: String)

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

    // --- Image understanding side-channels ---
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
        case warningMarginal
        case insufficient
        case unavailable
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

### 4.2 `VinetasTelemetryReporter.swift`

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

## 5. Library-side injection points

### 5.1 `VinetasClient` (`Vinetas.swift:24`)

`VinetasClient` is `Sendable` and immutable post-init (its `router` is a `let`). Storing a mutable telemetry reporter requires the `OSAllocatedUnfairLock` pattern:

```swift
import os.lock

public final class VinetasClient: Sendable {
    public let router: EngineRouter
    public static let version = "0.11.0-dev"   // bumped to "0.12.0" at release

    private let _telemetryLock = OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>(initialState: nil)

    public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
        _telemetryLock.withLock { $0 = reporter }
        await router.setTelemetry(reporter)
        // Propagate to long-lived ImageClassifier / FeatureExtractor — see §5.5.
    }

    internal func currentTelemetry() -> (any VinetasTelemetryReporter)? {
        _telemetryLock.withLock { $0 }
    }
}
```

### 5.2 `EngineRouter` (actor, `EngineRouter.swift:19`)

```swift
public actor EngineRouter {
    private var telemetry: (any VinetasTelemetryReporter)? = nil

    public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
        self.telemetry = reporter
        for engine in engines {
            await engine.setTelemetry(reporter)
        }
    }
}
```

### 5.3 `ImageGenerationEngine` protocol

```swift
public protocol ImageGenerationEngine: Sendable {
    // ... existing methods ...
    func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async
}

extension ImageGenerationEngine {
    public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
        // No-op default — engines override to wire telemetry into their internal pipelines.
    }
}
```

`Flux2Engine` and `PixArtEngine` override this. The override **only** stores the Vinetas reporter for engine-scoped Vinetas events not naturally covered by dep-level events: `concurrencyGateRejected`, `loraAttachStart` / `loraAttachComplete`, `modelLoadStart` / `Complete`, `modelUnload`, and `errorThrown(phase:)` for engine-internal throws.

The override does **NOT** bridge `Flux2TelemetryEvent` or `PixArtTelemetryEvent` into `VinetasTelemetryEvent`. The host wires those dep reporters directly via the deps' own `setTelemetry(_:)` seams. Bridging would (a) duplicate every transformer/scheduler/VAE event into the Vinetas surface, polluting the handoff signal §1 calls out as SwiftVinetas's reason to exist, and (b) couple SwiftVinetas's event schema to upstream changes in Flux2/PixArt enums.

### 5.4 Static `Vinetas` enum entry points

`Vinetas.swift:412` exposes static convenience entry points (`Vinetas.generate(prompt:)`, `Vinetas.preview(prompt:)`, etc.). These are pure wrappers around `VinetasClient.shared.<method>`. **No new parameters.**

Telemetry is wired exactly once per process via `VinetasClient.shared.setTelemetry(reporter)`. The static wrappers inherit that setting transitively. A per-call `telemetry:` parameter was considered and rejected (doubles API surface, no consumer needs per-call routing).

### 5.5 Image understanding actors

`ImageClassifier` and `FeatureExtractor` are actors. Each gets a `setTelemetry(_:)` setter storing `(any VinetasTelemetryReporter)?`. **`VinetasClient.setTelemetry` must propagate to them as part of §5.1's implementation** — they're not reachable through `EngineRouter`.

Two possible ownership models — the implementing agent picks whichever matches the codebase:
- **Long-lived instances** held by `VinetasClient`: extend `setTelemetry` to await `setTelemetry` on each.
- **On-demand construction** at call sites: add the propagation line at each constructor invocation.

Record the decision in a `// MARK: - Telemetry propagation` comment block at the chosen propagation point.

---

## 6. Per-event emission spec

**Single-emission rule.** Every event has exactly one canonical emission site. `generationStart` / `generationEnd` fire only at the `VinetasClient` API boundary, never inside `<Engine>.generate`. Dep-level pipeline events cover the engine boundary.

| Event | Emission site (file:line) | Notes |
|---|---|---|
| `clientInitialized` | End of `VinetasClient.init()` (`Vinetas.swift:51`) | Once per process (singleton). |
| `engineRegistered` / `engineSkipped` | Engine-registration block (`Vinetas.swift:45–48`) | One per engine. |
| `generationStart` | `VinetasClient.generate(...)` entry (`Vinetas.swift:79, 113, 167`) and `VinetasClient.preview(...)` entry (`Vinetas.swift:226`) | Four sites. `mode:` disambiguates. **Do NOT emit inside `<Engine>.generate`.** |
| `generationEnd` | Same four sites; success + failure paths via `defer` | Use captured-mutable-var idiom: `var success = false; var actualSeed: UInt64? = nil; var outputDims: [Int]? = nil` before the work; mutate on success; defer reads them. |
| `engineSelected` | After `router.engine(for: model)` returns (`EngineRouter.swift:61`) | Once per generate. |
| `engineNotFound` | Inside `throw VinetasError.engineNotFound` branches (`EngineRouter.swift:63, 76`) | Before throw. |
| `engineFeatureNegotiated` | Reserved for future LoRA/ControlNet expansion | None today. |
| `memoryValidationStart` / `Result` | Around `validateMemory(for:)` (`Vinetas.swift:315`) | One pair per generate. |
| `modelLoadStart` / `Complete` | Around `engine.loadModel(_:progress:)` (`Flux2Engine.swift:128`, PixArt equivalent) | One pair per first-time-this-process load. |
| `modelUnload` | Inside `unloadModel()` (`Flux2Engine.swift:172`, PixArt equivalent) | Per unload. |
| `modelAvailabilityChecked` | Inside `isAvailable(_:)` (`Vinetas.swift:269`) | One per check. |
| `modelDeleted` | Inside `delete(_:)` (`Vinetas.swift:277`) | One per delete. |
| `concurrencyGateRejected` | Inside `guard !isGenerating else { throw ... }` (`Flux2Engine.swift:186–187`, `PixArtEngine.swift:218–219`) | Before throw. |
| `loraAttachStart` / `Complete` | Around `loadLoRA(at:scale:)` (`Flux2Engine.swift:263`, `PixArtEngine.swift:284`) | One pair per attach. |
| `classifierForwardStart` / `Complete` | Around `ImageClassifier.classify(...)` | Image-understanding only. |
| `featureExtractionStart` / `Complete` | Around `FeatureExtractor.extract(...)` | Image-understanding only. One `TuberiaTensorStat` per extract — documented exception to hot-path discipline. |
| `errorThrown` | Every `throw VinetasError.…` site | Fire immediately before throw. Enumerated sites: `EngineRouter.swift:63, 76`; `Flux2Engine.swift:133, 187, 192, 223, 244, 265, 271, 296, 311, 326`; `PixArtEngine.swift:135, 180, 193, 219, 224, 231, 256, 263, 286, 291, 313, 321, 332, 348, 383, 399`; `Vinetas.swift:85`. |

### Hot-path discipline

SwiftVinetas does no per-step work. Events fire at most a few dozen times per generation. No `TuberiaTensorStat` calls on the main generation path — `featureExtractionComplete` is the one documented exception. The `OSAllocatedUnfairLock` on `VinetasClient.telemetry` is touched only at run boundaries.

---

## 7. CLI host wiring

### 7.1 The `--telemetry` flag

A single boolean flag, **`--telemetry`**, declared per-subcommand on each of `Generate`, `Batch`, `Preview`, `Classify`, `Features`, `Similarity`. No path argument. Output path is computed by the sink (§7.3).

```swift
@Flag(
    name: .long,
    help: ArgumentHelp(
        "Write a JSONL trace of every library handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
        discussion: """
            Captures events from all instrumented libraries used by this generation:
              - SwiftVinetas    (engine routing, memory verdict, model lifecycle)
              - flux-2-swift-mlx (tokenization, encoding, transformer steps, VAE decode)
              - pixart-swift-mlx (DiT steps, scheduler progress, VAE decode)
              - SwiftTuberia    (pipeline assembly, component load, memory pressure)
              - SwiftAcervo     (component download, cache hit/miss, file access)

            The trace path is printed to stderr after the run completes.

            Example:
              vinetas generate "a cyberpunk diner at dusk" --telemetry
              # → trace at ~/Library/Caches/vinetas/telemetry/2026-05-15T143022.jsonl
        """
    )
)
public var telemetry: Bool = false
```

**Why per-subcommand, not root-level:** the root `VinetasCLI` has `defaultSubcommand: Generate.self`. A root-level `--telemetry` would be consumed by the root before the subcommand dispatch, breaking `vinetas --telemetry "prompt"`. Per-subcommand declaration is six lines of @Flag boilerplate — acceptable.

### 7.2 CLI-side adapter types

```
Sources/VinetasCLICore/Telemetry/
  TelemetryJSONLSink.swift           // Shared sink, one per CLI invocation
  CLITelemetryBootstrap.swift        // Enables/disables the whole stack
  VinetasTelemetryCLIAdapter.swift   // conforms to VinetasTelemetryReporter
  Flux2TelemetryCLIAdapter.swift     // conforms to Flux2TelemetryReporter
  PixArtTelemetryCLIAdapter.swift    // conforms to PixArtTelemetryReporter
  TuberiaTelemetryCLIAdapter.swift   // conforms to TuberiaTelemetryReporter
  AcervoTelemetryCLIAdapter.swift    // conforms to AcervoTelemetryReporter
  VinetasEventEncoding.swift         // Encodable shim for VinetasTelemetryEvent
  Flux2EventEncoding.swift           // Encodable shim for Flux2TelemetryEvent
  PixArtEventEncoding.swift          // Encodable shim for PixArtTelemetryEvent
  TuberiaEventEncoding.swift         // Encodable shim for TuberiaTelemetryEvent
  AcervoEventEncoding.swift          // Encodable shim for AcervoTelemetryEvent
```

Each library's event enum has associated values, so Swift doesn't synthesize `Encodable` automatically. The wrapper flattens each case to a `case: String` discriminant plus the case's named fields. ~500 lines of mechanical encoding across the five wrappers.

### 7.3 `TelemetryJSONLSink`

```swift
public actor TelemetryJSONLSink {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    public let traceURL: URL

    public init(traceURL: URL) throws {
        try FileManager.default.createDirectory(
            at: traceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: traceURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: traceURL)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder.dateEncodingStrategy = .iso8601
        self.traceURL = traceURL
    }

    public func write<P: Encodable>(kind: String, payload: P) async {
        let envelope = TelemetryEnvelope(
            timestamp: Date(),
            kind: kind,
            payload: AnyEncodable(payload)
        )
        guard let data = try? encoder.encode(envelope) else { return }
        fileHandle.write(data)
        fileHandle.write(Data([0x0A]))
    }

    public func close() async {
        try? fileHandle.close()
    }
}
```

**Envelope format** — one JSON object per line:

```json
{"timestamp":"2026-05-15T14:30:22.123Z","kind":"vinetas","payload":{"case":"generationStart","prompt":"a cyberpunk diner","engineID":"flux2","modelID":"flux2-klein-4b","steps":28,"guidanceScale":3.5,"seed":42,"width":1024,"height":1024,"mode":"textToImage"}}
```

The `kind` field disambiguates the source library. A single trace file holds events from all five libraries interleaved in time order. Analysis tools filter by `kind` (`jq 'select(.kind == "flux2")'`).

**Trace path:**
- macOS: `~/Library/Caches/vinetas/telemetry/<ISO8601-no-colons>.jsonl`
- Linux/CI: `$XDG_CACHE_HOME/vinetas/telemetry/...` or `/tmp/vinetas/telemetry/...`
- Tests: override via `TelemetryJSONLSink(traceURL: tempURL)` direct init — no global path.

Colons are stripped from the timestamp because they're forbidden on FAT-formatted volumes some users mount.

### 7.4 Adapter pattern (one per library)

```swift
public struct Flux2TelemetryCLIAdapter: Flux2TelemetryReporter {
    private let sink: TelemetryJSONLSink

    public init(sink: TelemetryJSONLSink) {
        self.sink = sink
    }

    public func capture(_ event: Flux2TelemetryEvent) async {
        await sink.write(kind: "flux2", payload: Flux2EventEncoding(event: event))
    }
}
```

Each adapter is bound to one reporter protocol and one `kind` string. **Why separate adapters and not one mega-reporter:** independent failure modes (one adapter's encoder bug doesn't taint the others) and trace-time auditability (the `kind` field is the adapter's job to set — no internal dispatch logic).

### 7.5 `CLITelemetryBootstrap`

```swift
public struct CLITelemetryBootstrap {
    public let sink: TelemetryJSONLSink
    public let vinetasAdapter: VinetasTelemetryCLIAdapter
    public let flux2Adapter: Flux2TelemetryCLIAdapter
    public let pixartAdapter: PixArtTelemetryCLIAdapter
    public let tuberiaAdapter: TuberiaTelemetryCLIAdapter
    public let acervoAdapter: AcervoTelemetryCLIAdapter

    public static func enable(traceURL: URL? = nil) async throws -> CLITelemetryBootstrap {
        let resolvedURL = traceURL ?? defaultTraceURL()
        let sink = try TelemetryJSONLSink(traceURL: resolvedURL)

        let bootstrap = CLITelemetryBootstrap(
            sink: sink,
            vinetasAdapter: VinetasTelemetryCLIAdapter(sink: sink),
            flux2Adapter: Flux2TelemetryCLIAdapter(sink: sink),
            pixartAdapter: PixArtTelemetryCLIAdapter(sink: sink),
            tuberiaAdapter: TuberiaTelemetryCLIAdapter(sink: sink),
            acervoAdapter: AcervoTelemetryCLIAdapter(sink: sink)
        )

        await VinetasClient.shared.setTelemetry(bootstrap.vinetasAdapter)
        // OQ-1: verify the exact entry point for each dep at impl time.
        await /* Flux2Pipeline | Flux2Provider | similar */ .setTelemetry(bootstrap.flux2Adapter)
        await /* PixArtBackbone equivalent */ .setTelemetry(bootstrap.pixartAdapter)
        await /* Tuberia equivalent */ .setTelemetry(bootstrap.tuberiaAdapter)
        await /* Acervo equivalent */ .setTelemetry(bootstrap.acervoAdapter)

        return bootstrap
    }

    public func finish() async {
        await VinetasClient.shared.setTelemetry(nil)
        await /* … */ .setTelemetry(nil)  // four more nil-tearndowns
        await sink.close()
        stderrPrint("[vinetas] Telemetry trace: \(sink.traceURL.path)")
    }
}

private func defaultTraceURL() -> URL {
    let timestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "")
    return cacheDirectory()
        .appendingPathComponent("telemetry", isDirectory: true)
        .appendingPathComponent("\(timestamp).jsonl")
}
```

The `traceURL: URL? = nil` parameter on `enable(...)` lets the integration test override the path to a temp directory. CLI invocations pass nil and get the default cache path.

### 7.6 Wiring in each subcommand's `run()`

```swift
public func run() async throws {
    let bootstrap: CLITelemetryBootstrap? = telemetry
        ? try await CLITelemetryBootstrap.enable()
        : nil
    defer { Task { await bootstrap?.finish() } }

    // ... existing run() body unchanged ...
}
```

The `defer { Task { ... } }` pattern runs async cleanup from a sync defer. Per-line JSONL flushing means at most one truncated trailing line if the process exits before the Task runs. Acceptable for a CLI.

### 7.7 Subcommand coverage

| Subcommand | `--telemetry` flag | Wiring | Notes |
|---|---|---|---|
| `Generate` | yes | full (all 5 adapters) | Primary use case. |
| `Batch` | yes | full | Per-prompt events from each iteration land in one trace file. |
| `Preview` | yes | full | Trace shows `mode: .preview`. |
| `Classify` | yes | partial (Vinetas adapter only) | No diffusion happens; engine adapters would never fire. |
| `Features` | yes | partial | Same as `Classify`. |
| `Similarity` | yes | partial | Same as `Classify`. |
| `Download` | no | n/a | v2 candidate if anyone asks (`Acervo` adapter only). |
| `ListModels`, `Info` | no | n/a | Read-only metadata. |
| `CharacterCommand` (subcommands) | no | n/a | v2 candidate — reference-sheet generation does invoke engines. |

### 7.8 Package.swift changes

The `VinetasCLICore` target gains four direct dep imports:

```swift
.target(
    name: "VinetasCLICore",
    dependencies: [
        "SwiftVinetas",
        .product(name: "Flux2Core", package: "flux-2-swift-mlx"),       // NEW
        .product(name: "PixArtBackbone", package: "pixart-swift-mlx"),  // NEW
        .product(name: "Tuberia", package: "SwiftTuberia"),             // NEW
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),          // NEW
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ]
)
```

Direct dep imports bypass SwiftVinetas exactly as §3 prescribes. SwiftVinetas already resolves these four deps transitively — lifting them to target-level dependencies doesn't change the version graph.

---

## 8. Integration test (the runnable debugging harness)

This is the keystone deliverable. A compiled XCTest that:

1. Runs a real start-to-finish generation with telemetry enabled.
2. Asserts trace fidelity.
3. **Serves as the debugging tool** developers reach for when "generation does X unexpectedly."

### 8.1 Location and gating

```
Tests/SwiftVinetasIntegrationTests/TelemetryIntegrationTests.swift
```

Goes in the existing integration test target (verify exact target name in `Package.swift` — `make test-integration` already exists per CLAUDE.md). Local-only, never runs in CI.

Gating:
- `XCTSkipUnless(ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil, "needs cached models")` at the top of each test.
- The existing `link-test-models` Makefile target (CLAUDE.md notes it hardlinks weights from the App Group container into `/tmp` and passes the path as `TEST_RUNNER_VINETAS_TEST_MODELS_DIR`) provides the prerequisite.

### 8.2 Required tests

#### Test A: `testEndToEndGenerationProducesCompleteTrace`

```swift
func testEndToEndGenerationProducesCompleteTrace() async throws {
    try XCTSkipUnless(
        ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil,
        "needs cached models — run via `make test-integration`"
    )

    // 1. Set up a sink writing to a temp URL.
    let tempDir = try FileManager.default.url(
        for: .itemReplacementDirectory,
        in: .userDomainMask,
        appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
        create: true
    )
    let traceURL = tempDir.appendingPathComponent("telemetry.jsonl")

    // 2. Enable the full bootstrap (same path the CLI uses).
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: traceURL)
    defer { Task { await bootstrap.finish() } }

    // 3. Drive a real generation. 1 step minimizes runtime while still
    //    exercising the full pipeline. Use the smallest cached model.
    var styleConfig = StyleConfig(steps: 1, guidanceScale: 3.5)
    styleConfig.width = 512
    styleConfig.height = 512
    styleConfig.seed = 42
    _ = try await Vinetas.generate(
        prompt: "telemetry integration test",
        style: styleConfig,
        model: .klein4b
    )

    // 4. Tear down explicitly so writes are flushed.
    await bootstrap.finish()

    // 5. Read the trace and decode each line as a generic envelope.
    let data = try Data(contentsOf: traceURL)
    let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
    XCTAssertGreaterThan(lines.count, 0, "trace must be non-empty")

    struct Envelope: Decodable {
        let timestamp: Date
        let kind: String
        let payload: JSONValue  // recursive JSON decoder
    }
    let envelopes = try lines.map { try JSONDecoder().decode(Envelope.self, from: Data($0)) }

    // 6. Assert presence of every library's events.
    let kinds = Set(envelopes.map(\.kind))
    XCTAssertTrue(kinds.contains("vinetas"))
    XCTAssertTrue(kinds.contains("flux2"))   // klein4b → Flux2Engine
    XCTAssertTrue(kinds.contains("tuberia"))
    XCTAssertTrue(kinds.contains("acervo"))
    // pixart events only present if we'd used a pixart model; not required here.

    // 7. Assert presence of every required vinetas event.
    let vinetasCases = envelopes
        .filter { $0.kind == "vinetas" }
        .compactMap { $0.payload["case"]?.stringValue }
    XCTAssertTrue(vinetasCases.contains("clientInitialized"))
    XCTAssertTrue(vinetasCases.contains("engineRegistered"))
    XCTAssertTrue(vinetasCases.contains("generationStart"))
    XCTAssertTrue(vinetasCases.contains("engineSelected"))
    XCTAssertTrue(vinetasCases.contains("memoryValidationStart"))
    XCTAssertTrue(vinetasCases.contains("memoryValidationResult"))
    XCTAssertTrue(vinetasCases.contains("generationEnd"))

    // 8. Assert ordering invariants.
    let firstGenStart = envelopes.firstIndex {
        $0.kind == "vinetas" && $0.payload["case"]?.stringValue == "generationStart"
    }!
    let firstGenEnd = envelopes.firstIndex {
        $0.kind == "vinetas" && $0.payload["case"]?.stringValue == "generationEnd"
    }!
    XCTAssertLessThan(firstGenStart, firstGenEnd)

    let engineSelected = envelopes.firstIndex {
        $0.kind == "vinetas" && $0.payload["case"]?.stringValue == "engineSelected"
    }!
    XCTAssertLessThan(firstGenStart, engineSelected)

    // 9. Assert generationStart payload carries the request verbatim.
    let startPayload = envelopes[firstGenStart].payload
    XCTAssertEqual(startPayload["prompt"]?.stringValue, "telemetry integration test")
    XCTAssertEqual(startPayload["steps"]?.intValue, 1)
    XCTAssertEqual(startPayload["seed"]?.intValue, 42)
    XCTAssertEqual(startPayload["width"]?.intValue, 512)
    XCTAssertEqual(startPayload["height"]?.intValue, 512)
    XCTAssertEqual(startPayload["mode"]?.stringValue, "textToImage")
    XCTAssertEqual(startPayload["engineID"]?.stringValue, "flux2")

    // 10. Assert generationEnd success.
    let endPayload = envelopes[firstGenEnd].payload
    XCTAssertEqual(endPayload["success"]?.boolValue, true)
    XCTAssertGreaterThan(endPayload["durationSeconds"]?.doubleValue ?? 0, 0)

    // 11. Print trace path for developer inspection.
    print("Telemetry integration trace: \(traceURL.path)")
}
```

#### Test B: `testGenerationFailurePathEmitsErrorThrown`

Drives a deliberately failing generation (e.g., request a model that isn't cached without download) and asserts:
- `errorThrown` event fires with the appropriate `phase:`.
- `generationEnd` fires with `success: false`.
- No partial output — the trace doesn't show pipeline events past the failure point.

#### Test C: `testPixArtEngineRoutingEmitsCorrectEvents`

Same as Test A but with `model: .pixartSigma`. Asserts:
- `kinds` contains `pixart` (not `flux2`).
- `engineSelected.engineID == "pixart"`.
- No `concurrencyGateRejected` events on the happy path.

#### Test D: `testConcurrentGenerationGateEmitsRejection`

Fires two `Vinetas.generate(...)` calls concurrently. Asserts:
- One succeeds, one throws.
- `concurrencyGateRejected` event present in trace.
- The rejected path has `errorThrown(phase: .generationConcurrency, ...)`.

### 8.3 Makefile integration

Add a new target so developers can invoke the integration test as a debug tool. From CLAUDE.md, the existing pattern is `make test-integration` (already documented as local-only with model linking).

```makefile
# Existing target, augmented to include telemetry integration tests
test-integration: link-test-models
	@xcodebuild test \
	  -scheme SwiftVinetas \
	  -destination 'platform=macOS,arch=arm64' \
	  -only-testing:SwiftVinetasIntegrationTests/TelemetryIntegrationTests \
	  TEST_RUNNER_VINETAS_TEST_MODELS_DIR=$(MODELS_DIR)

# NEW — debug-focused: runs one test, opens the trace in the default viewer
test-telemetry-debug: link-test-models
	@xcodebuild test \
	  -scheme SwiftVinetas \
	  -destination 'platform=macOS,arch=arm64' \
	  -only-testing:SwiftVinetasIntegrationTests/TelemetryIntegrationTests/testEndToEndGenerationProducesCompleteTrace \
	  TEST_RUNNER_VINETAS_TEST_MODELS_DIR=$(MODELS_DIR) 2>&1 | tee /tmp/test-telemetry.log
	@grep "Telemetry integration trace:" /tmp/test-telemetry.log | tail -1
```

`make test-telemetry-debug` is the developer's entry point: it runs Test A, prints the trace path, and the developer opens it with `code`, `bbedit`, `jq`, whatever.

### 8.4 What the integration test does NOT do

- It does **not** validate per-event field exhaustiveness. The library-level unit tests (§9.1) cover that. The integration test validates *that the chain works end-to-end*.
- It does **not** assert exact event counts. Different cached model states (cold load vs warm) produce different counts of `modelLoadStart`/`Complete` and `Acervo` cache events. The test asserts presence and ordering, not cardinality.
- It does **not** run on CI. The cost of cached weights + GPU runtime is prohibitive. CI runs the library unit tests; humans run the integration tests pre-merge.

### 8.5 Architectural notes (as-built, v0.12.0)

These notes document deviations discovered during implementation (Sortie 9d) between the original spec assumptions and the actual architecture of the dependency libraries. They are the canonical record so future contributors do not repeat the same assumption.

#### 8.5.1 Tuberia is PixArt-only

`TuberiaTelemetryEvent` events fire from `SwiftTuberia`'s `DiffusionPipeline`, which is instantiated exclusively by `PixArtEngine`. Flux2 has its own independent pipeline and emits `Flux2TelemetryEvent` events directly through `Flux2Core`. It never instantiates `DiffusionPipeline` and therefore never produces `tuberia` events.

The original spec (§8.2 Test A) assumed Tuberia would be shared across both engines. This assumption is not correct as of v0.12.0.

**Consequence for integration tests:** Test A (`testEndToEndGenerationProducesCompleteTrace`, Klein 4B / Flux2) asserts only `{vinetas, flux2}` in the trace kind-set. Test C (`testPixArtEngineRoutingEmitsCorrectEvents`) is where `{vinetas, pixart, tuberia}` coverage lives.

#### 8.5.2 Flux2's model-download path bypasses `AcervoManager`

`Flux2ModelDownloader.download()` calls the **static** `Acervo.ensureAvailable(...)` directly. `CLITelemetryBootstrap` installs the `AcervoTelemetryCLIAdapter` on `AcervoManager.shared`, which is not the code path Flux2's downloader exercises. Only PixArt's download flow routes through `AcervoManager.shared`, so `acervo` events appear in PixArt traces but not in Flux2 traces.

**Consequence for integration tests:** Test A cannot assert `acervo` events for a Klein 4B generation. Test A's kind-set assertion is limited to `{vinetas, flux2}`.

#### 8.5.3 xcodebuild sandbox restriction on Group Containers

`xcodebuild test` (running via the `make test-integration` / `make test-telemetry-debug` Makefile targets) cannot access `~/Library/Group Containers/group.intrusive-memory.models/SharedModels` even when `TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models` is set. The process sandbox (MACF) blocks `fopen()` on files inside App Group containers for test runners that lack the `com.apple.security.application-groups` entitlement.

The workaround already in place (as of `make link-test-models`): model weights are **hardlinked** from the App Group container into `/tmp/vinetas-test-models` (an entitled shell process performs the hardlink; the test runner then opens from `/tmp`). This is the `PIXART_TEST_MODELS` / `TEST_RUNNER_VINETAS_TEST_MODELS_DIR` path the Makefile provides to the test runner.

If `xcrun xctest` is used directly (outside the xcodebuild sandbox), it can open files from the App Group path without this workaround. For CI the restriction is moot since models are not cached there.

---

## 9. Test suite

### 9.1 Library-level unit tests

Add to `Tests/SwiftVinetasTests/`:

| Test | Purpose |
|---|---|
| `Support/MockVinetasReporter.swift` | `final class MockVinetasReporter: VinetasTelemetryReporter, @unchecked Sendable` capturing events under a lock. Also `MockDeviceCapability` stub. |
| `VinetasTelemetryClientInitTests` | `clientInitialized` fires once. Correct `engineRegistered`/`engineSkipped` pair at 16 GB and 8 GB thresholds via mocked `DeviceCapability`. |
| `VinetasTelemetryPropagationTests` | `setTelemetry` reaches `EngineRouter`, every engine, and `ImageClassifier`/`FeatureExtractor`. `setTelemetry(nil)` tears down. |
| `VinetasTelemetryHandoffTests` | `VinetasClient.generate(...)` against a mock engine emits **exactly one** `generationStart` (single-emission rule) carrying every field verbatim. Followed by `generationEnd(success: true, ...)`. |
| `VinetasTelemetryEngineRoutingTests` | Two mock engines, request a model belonging to neither. `engineNotFound` fires before throw; `errorThrown(phase: .engineNotFound)` fires immediately after. |
| `VinetasTelemetryConcurrencyTests` | Two concurrent `Flux2Engine.generate(...)`. `concurrencyGateRejected` fires before second throws; `generationEnd(success: false)` on failing path. Repeat for `PixArtEngine`. |
| `VinetasTelemetryMemoryValidationTests` | Drive `validateMemory(for:)` through mocked `DeviceCapability` for each `MemoryVerdict` case. |
| `VinetasTelemetryNoopOverheadTests` | 100 `generate()` calls under `nil` vs `NoopVinetasTelemetryReporter`. Wall-clock median ±2%. **Gate off CI** with `XCTSkipIf(env CI != nil, "perf — local only")`. |

### 9.2 CLI-level unit tests

Add to `Tests/SwiftVinetasTests/CLITests/` (or whatever directory the existing CLI tests use):

| Test | Purpose |
|---|---|
| `CLITelemetryFlagParsingTests` | `--telemetry` parses to `true` on each in-scope subcommand. Absence parses to `false`. |
| `TelemetryJSONLSinkTests` | Write events of each `kind`, close, read back. Assert one JSON object per line, valid UTF-8, parseable. |
| `CLITelemetryBootstrapTests` | Stub each dep's `setTelemetry(_:)`. Call `enable()` with a temp `traceURL`, assert each stub received the expected adapter. Call `finish()`, assert each stub received nil. |
| `VinetasEventEncodingTests` | For each case of `VinetasTelemetryEvent`, encode → decode → assert round-trip preserves case discriminant and named fields. |
| `Flux2EventEncodingTests` | Same for `Flux2TelemetryEvent`. |
| `PixArtEventEncodingTests` | Same for `PixArtTelemetryEvent`. |
| `TuberiaEventEncodingTests` | Same for `TuberiaTelemetryEvent`. |
| `AcervoEventEncodingTests` | Same for `AcervoTelemetryEvent`. |

### 9.3 Integration tests

Per §8 — `TelemetryIntegrationTests` with four tests (end-to-end, failure path, PixArt routing, concurrency rejection).

---

## 10. Out of scope (v1)

- `CharacterTrainer`, `TrainingDataPreparer`, `ReferenceSheetGenerator`. Vinetas the app does not run training in production.
- `LoRAManager` internals — `loraAttachStart/Complete` covers what callers need.
- `PromptFile` / `StyleConfig` parsing telemetry — covered implicitly by `generationStart.prompt` being the post-parse value.
- `VisionTransformer` internal layer-by-layer events — `classifierForwardComplete` summarizes.
- `AspectRatio` enum parsing — internal, deterministic.
- A `vinetas telemetry analyze` subcommand — defer; `jq` is sufficient until there's a real analysis use case.
- Process-level memory snapshots à la Produciesta's `MemoryTelemetry` — the instrumented libs already snapshot tensors where it matters.
- `--telemetry-level=verbose|errors` filtering. v1 is all-or-nothing.
- Telemetry over network sockets, OTLP, anything fancy. JSONL on disk only.
- Telemetry on `Download`, `ListModels`, `Info`, `CharacterCommand` subcommands.
- Engine-side adapter conformance inside SwiftVinetas. Dep reporters are wired by hosts directly, never bridged through SwiftVinetas.

---

## 11. Versioning

**Minor** version bump (additive). Current `0.11.0-dev` → **`0.12.0`**. Bundle library + CLI + integration test in the same release. Post-release, downstream consumers pin against `from: "0.12.0"`.

No public API changes that break existing callers. `VinetasClient.setTelemetry(_:)` is new; existing code calling `Vinetas.generate(...)` continues to work with telemetry off (the nil reporter is the default).

---

## 12. Sequencing

This is **one mission, one PR cycle**:

1. Branch: `instrumentation/01` off `development`.
2. Implement library types, seams, emission sites (§4–§6).
3. Implement CLI adapters, sink, bootstrap, flag wiring (§7).
4. Implement integration test + Makefile target (§8).
5. All library unit tests, CLI unit tests, integration tests pass locally.
6. PR `instrumentation/01` → `development`. CI runs library + CLI unit tests (integration tests gated off).
7. Manually run `make test-integration` and `make test-telemetry-debug` before approving merge. Attach the trace path output to the PR for the reviewer.
8. Merge `development` → `main`, tag `0.12.0`, GitHub release.

The previous EXECUTION_PLAN at `docs/incomplete/swift-vinetas-instrumentation/EXECUTION_PLAN.md` covers only the library work. It needs a re-refine pass to absorb the CLI sorties and integration test sortie before dispatch. Suggested updated structure:

| Group | Sorties | Agents |
|---|---|---|
| A. Foundation (parallel) | S1 event type, S2 reporter protocol | 2 sub-agents |
| B. Library seam | S3 setTelemetry + propagation | supervisor |
| C. Library emissions (parallel) | S4 Vinetas+Engine, S5 Understanding | supervisor + 1 sub-agent |
| D. CLI infrastructure (parallel) | S6 sink+envelope, S7 five event-encoding shims | supervisor + up to 3 sub-agents |
| E. CLI wiring | S8 bootstrap + per-subcommand flags | supervisor |
| F. Integration test | S9 four tests + Makefile target | supervisor |
| G. Unit tests | S10 library + CLI unit tests | supervisor |

Critical path: A → B → C → D → E → F. ~10 sorties total, up from 6 in the library-only plan.

---

## 13. Implementation checklist

### Library
- [ ] Add `Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` per §4.1 (no `runID` fields).
- [ ] Add `Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` per §4.2.
- [ ] Add `OSAllocatedUnfairLock` + `setTelemetry(_:)` + `currentTelemetry()` to `VinetasClient` (`Vinetas.swift:24`).
- [ ] Add `setTelemetry(_:)` to `EngineRouter` actor and propagate to every engine, `ImageClassifier`, `FeatureExtractor`.
- [ ] Extend `ImageGenerationEngine` protocol with defaulted `setTelemetry(_:)`; override in `Flux2Engine` and `PixArtEngine` (engine-scoped events only — no dep-event bridging).
- [ ] Wire emission sites per §6. `generationStart`/`End` at `VinetasClient.generate/preview` only.
- [ ] Every `throw VinetasError.…` preceded by `errorThrown(phase:errorDescription:)`.

### CLI
- [ ] Add four dep imports to `VinetasCLICore` target (§7.8).
- [ ] Add `Sources/VinetasCLICore/Telemetry/TelemetryJSONLSink.swift` (§7.3).
- [ ] Add five adapter types (§7.4) + five event-encoding shims (§7.2).
- [ ] Add `Sources/VinetasCLICore/Telemetry/CLITelemetryBootstrap.swift` (§7.5).
- [ ] Add `--telemetry` flag to `Generate`, `Batch`, `Preview`, `Classify`, `Features`, `Similarity` (§7.1).
- [ ] Wire `CLITelemetryBootstrap.enable()` / `finish()` in each in-scope subcommand's `run()` (§7.6).

### Integration test
- [ ] Add `Tests/SwiftVinetasIntegrationTests/TelemetryIntegrationTests.swift` with four tests (§8.2).
- [ ] Add `make test-telemetry-debug` Makefile target (§8.3).
- [ ] Verify `make test-integration` includes the new tests.

### Unit tests
- [ ] Library tests per §9.1.
- [ ] CLI tests per §9.2.
- [ ] All tests pass on macOS arm64.

### Release
- [ ] Bump `VinetasClient.version` from `"0.11.0-dev"` to `"0.12.0"` (also update the duplicate at `Vinetas.swift:415`).
- [ ] Tag `0.12.0` on `main`.
- [ ] GitHub release notes mention library + CLI + integration test additions.

---

## 14. Open questions

| ID | Issue | Recommendation |
|---|---|---|
| OQ-1 | Where do the four dep `setTelemetry` entry points actually live? `Flux2Pipeline.setTelemetry` is a guess. | **Verify at impl time.** Each library's `AGENTS.md` or public API docs name the canonical entry point. The Produciesta pattern uses provider-managed reporters (`voxProvider.setTelemetry(...)`) — Vinetas's deps may follow a similar provider-per-instance pattern. The bootstrap stub shows `/* Flux2Pipeline | Flux2Provider | similar */` as a placeholder — implementing agent fills it in. |
| OQ-2 | The `defer { Task { await ... } }` in subcommand `run()` is fire-and-forget. Acceptable for v1? | **Yes.** Per-line flushing means at most one truncated trailing line at process exit. `setTelemetry(nil)` matters only for retain-cycle hygiene; process exit obviates it. The integration test calls `await bootstrap.finish()` explicitly to avoid race conditions in assertions. |
| OQ-3 | Long-lived vs on-demand `ImageClassifier`/`FeatureExtractor` ownership? | **DEFERRED-TO-AGENT** in §5.5. Run the grep, decide, document in `// MARK: - Telemetry propagation`. |
| OQ-4 | Should image-understanding subcommands wire the engine adapters too? | **No** (§7.7). No diffusion happens; engine adapters would never fire. Wiring unused adapters pollutes the bootstrap audit story. |
| OQ-5 | `--telemetry-path PATH` option needed? | **No for v1.** Deterministic cache path is simpler. The integration test bypasses the default via the `traceURL:` parameter on `CLITelemetryBootstrap.enable(traceURL:)`. |
| OQ-6 | `generationEnd` failure-path field sourcing? | **DEFERRED-TO-AGENT.** Captured-mutable-var defer idiom: `var success = false` before the work, mutate on success, defer reads them. |
| OQ-7 | PixArt throw-site enumeration. | **RESOLVED** in §6 (full list provided). |
| OQ-8 | Parallel write conflict between library S4 and S5? | **RESOLVED** by folding propagation hook into the seam sortie (§5.1). S4 (Vinetas+Engine emissions) and S5 (Understanding emissions) operate on disjoint file sets. |

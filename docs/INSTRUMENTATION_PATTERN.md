# Instrumentation Pattern — Library Telemetry Exposed to CLI Hosts

**Status**: canonical pattern, in use across SwiftVinetas, flux-2-swift-mlx, pixart-swift-mlx, SwiftTuberia, SwiftAcervo.
**Surfaced by**: OPERATION WIRETAP DARKROOM (2026-05-15), specifically OQ-1 in `REQUIREMENTS-instrumentation.md`.

This document describes the **dual-seam telemetry pattern** used to instrument a library so that:

1. **Test code** (inside the library, or in adjacent libraries) can install a reporter scoped to one instance and assert events deterministically.
2. **CLI hosts and other process-wide consumers** can install a single reporter once at startup and receive events from every emission site, even when the library's emission types live behind another library's encapsulated state.

Without both seams, the library is either un-testable (only process-wide) or un-host-able from a CLI that can't reach its instances (only instance-bound). This pattern carries both.

---

## TL;DR

Each instrumented library `Foo` ships:

| Surface | Type | Purpose | Example |
|---------|------|---------|---------|
| Event enum | `public enum FooTelemetryEvent: Sendable` | The typed events the library emits | `case generationStart(...)` |
| Reporter protocol | `public protocol FooTelemetryReporter: Sendable` | Single `async` `capture` method | `func capture(_ event: FooTelemetryEvent) async` |
| Noop reporter | `public struct NoopFooTelemetryReporter: FooTelemetryReporter` | Drop-in for tests/disabled-telemetry paths | empty `capture` body |
| Instance-bound seam | method on the event-owning type | Test isolation; instance reporter wins when set | `FooPipeline.setTelemetry(_:)` |
| Process-wide seam | `public enum FooTelemetry { static setReporter / static current }` | CLI bootstrap; fallback for instances with no reporter set | `FooTelemetry.setReporter(adapter)` |
| `effectiveReporter` resolution | `private var effectiveReporter: { instance ?? .current }` | Where each emission site reads from | called at every `capture` site |

The CLI host (or any process-wide consumer) ships, for each library:

| Surface | Purpose |
|---------|---------|
| `FooEventEncoding.swift` | `Encodable` shim flattening each enum case to `{ "case": "<discriminant>", <fields> }` |
| `FooTelemetryCLIAdapter` | Conforms to `FooTelemetryReporter`; writes to a shared `TelemetryJSONLSink` with a fixed `kind` discriminant |
| `CLITelemetryBootstrap` | Constructs sink + adapters; calls each library's process-wide seam to install its adapter; tears down on `finish()` |

The single, interleaved trace at the sink is one JSONL file with `{ "timestamp": …, "kind": "vinetas" | "flux2" | … , "payload": { "case": …, … } }` per line.

---

## The Library Side

### 1. The event enum

```swift
import Foundation

public enum FooTelemetryEvent: Sendable {
    case operationStart(operationID: String, …)
    case operationEnd(operationID: String, success: Bool, …)
    case errorThrown(phase: ErrorPhase, errorDescription: String)
    // … all cases public, all associated values Sendable
    public enum ErrorPhase: String, Sendable {
        case validation, ingest, output
    }
}
```

**Rules:**

- Every case and every associated-value type must be `Sendable`.
- Do NOT add a `runID` field on the cases themselves. Run identifiers belong at the host/sink layer, attached when the event is serialised (see *Envelope* below). This keeps the event enum stable across host designs.
- Add nested enums (like `ErrorPhase`) for any closed set of discriminants — the host's encoder can serialize them as strings.

### 2. The reporter protocol

```swift
public protocol FooTelemetryReporter: Sendable {
    func capture(_ event: FooTelemetryEvent) async
}

public struct NoopFooTelemetryReporter: FooTelemetryReporter {
    public init() {}
    public func capture(_ event: FooTelemetryEvent) async {}
}
```

**Rules:**

- Single `async` method. No throws. Reporters must own their own concurrency model; failures in transport (file I/O, network) must not propagate into the emitting code path.
- `Sendable` lets actors hold reporters as stored properties safely.
- Always ship a `Noop` so consumers can opt out without making the property optional everywhere downstream.

### 3. The instance-bound seam

The type that owns the events (often a pipeline or a manager) exposes a `setTelemetry(_:)` method:

```swift
public actor FooPipeline {
    private var instanceReporter: (any FooTelemetryReporter)?

    public func setTelemetry(_ reporter: (any FooTelemetryReporter)?) async {
        self.instanceReporter = reporter
    }

    private var effectiveReporter: (any FooTelemetryReporter)? {
        instanceReporter ?? FooTelemetry.current
    }

    public func runStuff() async throws {
        await effectiveReporter?.capture(.operationStart(operationID: id))
        // …
    }
}
```

**Rules:**

- The instance reporter takes precedence over the process-wide reporter when both are set. This lets tests install a per-instance reporter and assert on it deterministically without being polluted by an ambient process-wide reporter.
- Every emission site calls `effectiveReporter?.capture(...)` — never `instanceReporter?.capture(...)` directly, never `FooTelemetry.current?.capture(...)` directly. The `effectiveReporter` computed property is the single source of resolution.
- `setTelemetry(_:)` on an actor is `async` because actor-isolated state is being mutated; on a thread-safe class with lock-guarded state it can be sync. Match the type's isolation model.

### 4. The process-wide seam

```swift
import os.lock

public enum FooTelemetry {
    private static let lock = OSAllocatedUnfairLock<(any FooTelemetryReporter)?>(initialState: nil)

    public static func setReporter(_ reporter: (any FooTelemetryReporter)?) {
        lock.withLock { $0 = reporter }
    }

    public static var current: (any FooTelemetryReporter)? {
        lock.withLock { $0 }
    }
}
```

**Rules:**

- Use `OSAllocatedUnfairLock` for the storage (Swift 6 / strict concurrency safe). Avoid `NSLock`, `DispatchQueue`, or `Mutex` unless the repo has an established convention otherwise.
- The namespace type is `enum` (zero-instance) so it cannot be accidentally instantiated. Equivalent: `public struct FooTelemetry` with a private init.
- `setReporter(_:)` is sync. Emission sites consult `current` and then `await` the resulting reporter's `capture` — the async-ness lives in the reporter protocol, not the seam.
- `setReporter(nil)` is the reset signal. The CLI host calls it during `bootstrap.finish()`.
- Multiple processes co-existing on the same machine is not a concern — each process has its own static state.

### 5. Tests of both seams

A library that ships both seams must have unit tests asserting:

1. **Instance-only**: instance reporter set, process-wide unset → events reach the instance reporter.
2. **Process-wide-only**: instance reporter unset, process-wide set → events reach the process-wide reporter.
3. **Both set**: instance reporter set, process-wide set → events reach the instance reporter (instance wins).
4. **Reset**: setting either reporter to `nil` returns to the "no reporter" state without leaking previous emissions.

Pattern:

```swift
final class FooDualSeamTests: XCTestCase {
    override func tearDown() async throws {
        FooTelemetry.setReporter(nil)  // critical: prevent test cross-contamination
    }
    // … four assertions, one per scenario above
}
```

Without the `tearDown`, a process-wide reporter installed by one test leaks into the next test's environment.

---

## The Host (CLI) Side

The host adds one Encodable shim and one adapter per consumed library, plus a single bootstrap that wires everything.

### 6. The Encodable shim

For each library's `*TelemetryEvent`, the host ships an `Encodable` wrapper that flattens the case to a key-value JSON shape with a `"case"` discriminant:

```swift
public struct FooEventCodable: Encodable {
    public let event: FooTelemetryEvent

    enum CodingKeys: String, CodingKey {
        case `case`, operationID, success, errorPhase, errorDescription
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch event {
        case .operationStart(let opID, …):
            try c.encode("operationStart", forKey: .case)
            try c.encode(opID, forKey: .operationID)
        case .operationEnd(let opID, let success, …):
            try c.encode("operationEnd", forKey: .case)
            try c.encode(opID, forKey: .operationID)
            try c.encode(success, forKey: .success)
        // … one branch per case, exhaustive
        }
    }
}
```

**Rules:**

- The shim is `Encodable` only — there's no need to round-trip into a Swift enum at the consumer side. JSON consumers parse the flat shape directly.
- The discriminant key is `"case"`. Other fields sit at the same level (flat, not nested under a `payload`).
- Enumerate every case. Do not use `@unknown default` unless the source enum is in a different module and explicitly `@unknown`-required.
- If a payload field is itself a typed value (e.g. `TuberiaTensorStat`), and that type is already `Codable`, encode it verbatim. Don't re-flatten its fields — let its `encode(to:)` do its job.

### 7. The adapter

```swift
public struct FooTelemetryCLIAdapter: FooTelemetryReporter {
    let sink: TelemetryJSONLSink
    public init(sink: TelemetryJSONLSink) { self.sink = sink }
    public func capture(_ event: FooTelemetryEvent) async {
        try? await sink.write(kind: "foo", payload: FooEventCodable(event: event))
    }
}
```

**Rules:**

- One adapter per library. The `kind` string is the canonical library identifier (`"vinetas"`, `"flux2"`, `"pixart"`, `"tuberia"`, `"acervo"`).
- The adapter swallows transport errors (`try?`). The reporter contract says emissions must not propagate failure.
- The adapter is a `struct` — adapters hold no mutable state, just a reference to the shared sink (which is itself an `actor`).

### 8. The sink and envelope

```swift
public actor TelemetryJSONLSink {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    public init(traceURL: URL) throws { /* open file, configure encoder with ISO8601 dates, sortedKeys, withoutEscapingSlashes */ }
    public func write<P: Encodable>(kind: String, payload: P) async throws {
        let envelope = TelemetryEnvelope(timestamp: Date(), kind: kind, payload: AnyEncodable(payload))
        let data = try encoder.encode(envelope)
        fileHandle.write(data)
        fileHandle.write(Data([0x0A]))
    }
    public func close() async { try? fileHandle.close() }
}

public struct TelemetryEnvelope: Encodable {
    public let timestamp: Date
    public let kind: String
    public let payload: AnyEncodable
}

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    public init<E: Encodable>(_ value: E) { self._encode = value.encode }
    public func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
```

**Rules:**

- One actor wrapping one `FileHandle`. Serialization happens inside the actor; concurrency safety is automatic.
- Per-line flush: write payload bytes, then a `0x0A` newline. No buffering. The integration test depends on each line being readable immediately after the corresponding `capture` resolves.
- The envelope's three fields (`timestamp`, `kind`, `payload`) are the JSONL contract. Do not add or remove fields without updating every consumer of the trace.

### 9. The bootstrap

```swift
public actor CLITelemetryBootstrap {
    let sink: TelemetryJSONLSink
    let vinetasAdapter: VinetasTelemetryCLIAdapter
    let fooAdapter: FooTelemetryCLIAdapter
    // … one adapter per library

    public static func enable(traceURL: URL? = nil) async throws -> CLITelemetryBootstrap {
        let resolved = traceURL ?? defaultTraceURL()
        let sink = try TelemetryJSONLSink(traceURL: resolved)
        let vinetasAdapter = VinetasTelemetryCLIAdapter(sink: sink)
        let fooAdapter = FooTelemetryCLIAdapter(sink: sink)
        // … construct each adapter, then install at each library's seam:
        await VinetasClient.shared.setTelemetry(vinetasAdapter)  // library-A instance-bound seam (works because shared singleton)
        FooTelemetry.setReporter(fooAdapter)                     // library-B process-wide seam
        // …
        return CLITelemetryBootstrap(sink: sink, …)
    }

    public func finish() async {
        await VinetasClient.shared.setTelemetry(nil)
        FooTelemetry.setReporter(nil)
        // …
        await sink.close()
        FileHandle.standardError.write("[host] Telemetry trace: \(sink.traceURL.path)\n".data(using: .utf8)!)
    }
}
```

**Rules:**

- The bootstrap is the only place that knows about all libraries simultaneously. Each library remains ignorant of every other library.
- `enable` constructs all adapters and installs each at the library's correct seam (instance-bound singleton vs. process-wide static). Each library may need a different installation call — that's expected and documented at the bootstrap site, not inside the libraries.
- `finish` is symmetric: uninstall, then close the sink. **Always uninstall before closing** — otherwise a late emission can hit a closed `FileHandle` and crash the process.
- The trace path is printed to stderr (not stdout) so it doesn't pollute the CLI's stdout contract for piping/scripting.
- Subcommands wrap their body with `defer { Task { await bootstrap?.finish() } }`. Fire-and-forget is acceptable because the subcommand process is about to exit anyway.

---

## When to Use Instance-Bound vs. Process-Wide

| Scenario | Use |
|----------|-----|
| Unit test asserts events emitted during one specific call | **Instance-bound** — construct a mock reporter, install it on the instance under test, assert |
| Integration test in another library that wraps this one | **Instance-bound** if the wrapping library exposes the inner instance to test code; **process-wide** if it doesn't |
| CLI host wanting to stream every event to a sink | **Process-wide** — the host typically has no reference to the inner instances |
| Long-running daemon with one global trace destination | **Process-wide** |
| Library code wanting to emit to "whatever reporter the host configured" | The library doesn't choose — it always reads `effectiveReporter`, which automatically picks instance over process-wide |

The pattern of `instance wins when both are set` is deliberate: it lets a test install an instance reporter mid-flight and get clean isolation even when an ambient process-wide reporter is already installed (e.g. by the test harness's bootstrap, or by a sibling test that forgot to tear down).

---

## When *Not* to Add a Process-Wide Seam

A library should add a process-wide seam **only when**:

1. The library has consumers (typically CLI hosts) that can't reach instances of the emission-owning types — because those instances are private to another library, or constructed lazily inside an actor, or there are many of them and one-by-one installation is infeasible.
2. The emission-owning type is in fact a singleton or near-singleton in practice (most pipelines, weight loaders, schedulers). For genuinely-multi-instance types where each instance needs distinct telemetry routing, only the instance-bound seam makes sense.

If neither condition holds, ship only the instance-bound seam. Adding a process-wide seam adds a hidden global, which is a cost — pay it only when there's a concrete consumer that needs it.

---

## Concurrency Notes

- **`OSAllocatedUnfairLock` over the process-wide reporter slot.** Cheap, Sendable, Swift-6-strict-concurrency-safe.
- **The reporter protocol is `async`.** This is the right contract: a sink may need to journal, batch, ship over the network — `async` keeps the emission site honest.
- **Emission sites `await reporter?.capture(...)`.** Not `Task { await … }` — that detaches the emission, breaking event ordering. The only place fire-and-forget is acceptable is inside synchronous `defer` blocks (e.g. for `generationEnd` capture during a `throw`); even there, the Task captures the current state of the local variables, not a snapshot from a later time.
- **The adapter swallows transport errors.** Reporters that fail must not break the emitting code path.

---

## Adoption Checklist for a New Library `Bar`

When introducing this pattern to a library that doesn't have it yet:

- [ ] Add `BarTelemetryEvent` (Sendable, public, every case + associated value Sendable).
- [ ] Add `BarTelemetryReporter` protocol (Sendable, single async `capture`).
- [ ] Add `NoopBarTelemetryReporter`.
- [ ] On the type that owns the emissions, store `instanceReporter`, add `setTelemetry(_:)`, add `effectiveReporter` computed property.
- [ ] Route every emission site through `effectiveReporter?.capture(...)`.
- [ ] If consumers need process-wide installation: add `public enum BarTelemetry` with lock-guarded `setReporter`/`current`.
- [ ] Add unit tests for the four-scenario dual-seam matrix (instance-only, process-only, both, reset).
- [ ] In the host (CLI / SDK / wrapper):
  - [ ] Add `BarEventEncoding.swift` (Encodable shim, exhaustive over the enum cases).
  - [ ] Add `BarTelemetryCLIAdapter`.
  - [ ] Wire the adapter in the bootstrap's `enable` / `finish`.

---

## See Also

- `REQUIREMENTS-instrumentation.md` — the SwiftVinetas-specific spec that catalyzed this pattern.
- `EXECUTION_PLAN.md` — OPERATION WIRETAP DARKROOM, the 11-sortie campaign that established it.
- `Sources/VinetasCLICore/Telemetry/CLITelemetryBootstrap.swift` — the canonical bootstrap implementation.
- Each sibling library's `Telemetry/` directory — concrete realizations of the seams described here.

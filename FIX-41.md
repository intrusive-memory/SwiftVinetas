# FIX-41 — Engine eviction path + cancellation teardown

**Status:** research-backed plan (no code changed). Verified against current source on `development` (SwiftVinetas `0.15.3-dev`).

## Issue

[intrusive-memory/SwiftVinetas#41](https://github.com/intrusive-memory/SwiftVinetas/issues/41) — *"No engine eviction path or cancellation teardown; MLX weights pinned for the process lifetime (cross-platform)."*

- **Gates** [intrusive-memory/Vinetas#92](https://github.com/intrusive-memory/Vinetas/issues/92) (macOS 4K generation) — without an eviction path the resident weights leave no headroom for the larger working set at 4K.
- **Overlaps** Vinetas#82 (app lifecycle wiring of unload/evict) and Vinetas#56 (memory-pressure response).
- Related to the macOS Guideline 4 "runs/responds very slowly" rejection (build 187): MLX cache is uncapped on macOS, so the resident footprint never shrinks.

## Root cause — the retain chain

A single hard reference chain keeps every loaded model's MLX weights resident for the entire process lifetime, with no API to break it and no cancellation cleanup.

1. **`VinetasClient.shared` is a process-lifetime singleton holding a `let router`.**
   `Sources/SwiftVinetas/Vinetas.swift:42` — `public static let shared = VinetasClient()`
   `Sources/SwiftVinetas/Vinetas.swift:45` — `public let router: EngineRouter`

2. **`EngineRouter` holds its engines in `let` properties, set once in `init`, with no eviction surface.**
   `Sources/SwiftVinetas/Engine/EngineRouter.swift:22` — `private let enginesByID: [String: any ImageGenerationEngine]`
   `Sources/SwiftVinetas/Engine/EngineRouter.swift:25` — `private let engines: [any ImageGenerationEngine]`
   `Sources/SwiftVinetas/Engine/EngineRouter.swift:38-45` — `init(engines:)` builds the map once.
   The only members are lookup (`engine(for:)` :66, `engine(forEngineID:)` :92) and telemetry fan-out (`setTelemetry(_:)` :112). There is **no** eviction / release / unload fan-out.

3. **Each engine caches its assembled pipeline (which owns the weights) in a `private var`.**
   `Sources/SwiftVinetas/Engine/Flux2Engine.swift:94` — `private var pipeline: Flux2Pipeline?`
   `Sources/SwiftVinetas/Engine/PixArtEngine.swift:95` — `private var pipeline: PixArtPipeline?`
   Both are populated by `loadModel(_:progress:)` (Flux2 :192, PixArt :232) and held until the next `loadModel` (each calls `await unloadModel()` first — Flux2 :162, PixArt :162).

   Net chain: `VinetasClient.shared → router → engine → pipeline → MLX weights`, alive for the process lifetime.

4. **`unloadModel()` exists and is correct, but is effectively unreachable from the public API.**
   It is part of the protocol: `Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift:48` — `func unloadModel() async`.
   - `PixArtEngine.unloadModel()` `:243-255` — `await pipeline.unloadModels()`, then `VinetasMemory.releaseMLXCache()`, then nils `pipeline` / `loadedModelID` / `activeLoRAConfig`, then emits `.modelUnload`.
   - `Flux2Engine.unloadModel()` `:203-213` — `await pipeline.clearAll()`, then nils `pipeline` / `loadedModelID`, then emits `.modelUnload`. (Note: Flux2's unload relies on `clearAll()` to flush the MLX cache; it does **not** call `releaseMLXCache()` directly, unlike PixArt — see "Risks".)

   The only way to reach it today is `await client.router.engine(...).unloadModel()`. The only callers are tests: `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift:276` and `Tests/SwiftVinetasTests/PixArtEngineTests.swift:312`. **`VinetasClient` exposes no unload/evict/cancel convenience.**

5. **Zero cancellation handling anywhere in the generate path.**
   `grep` for `isCancelled` / `checkCancellation` / `withTaskCancellationHandler` / `CancellationError` across `Sources/SwiftVinetas/Engine` and `Vinetas.swift` returns **nothing**. The engines guard concurrency with an `isGenerating` flag (Flux2 :105/:252, PixArt :109/:310) and reset it via `defer { isGenerating = false }`, but a consumer that cancels its generation `Task` leaves `engine.pipeline` (and its weights) fully resident. PixArt has `defer { VinetasMemory.releaseMLXCache() }` in `generate` (`PixArtEngine.swift:312`) so it flushes the cache on *any* exit including cancellation throw; Flux2 has **no** equivalent — a cancelled Flux2 generation leaves the cache un-flushed.

6. **`VinetasMemory` MLX throttle is iOS-only; macOS gets no cap.**
   `Sources/SwiftVinetas/Core/VinetasMemory.swift:133-143` — `configureMLXBudgetForCurrentProcess(...)` sets `Memory.memoryLimit` / `Memory.cacheLimit` **only inside `#if os(iOS)`**. On macOS the whole body is compiled out (no-op). There is a setter path but **no queryable getter** — only `releaseMLXCache()` (`:150-152`, calls `Memory.clearCache()`, cross-platform). MLX exposes `Memory.cacheLimit` / `Memory.memoryLimit` (settable) plus `activeMemory` / `cacheMemory` / `snapshot()` for observability, but none are surfaced here.

## Proposed API surface

Add an explicit eviction fan-out to `EngineRouter`, and convenience methods on `VinetasClient`. All additive; nothing existing changes signature.

### `EngineRouter` (actor) — fan-out methods

```swift
// EngineRouter.swift — new methods on the actor

/// Unload every registered engine's resident model, freeing all MLX weights.
/// Fans out to each engine's `unloadModel()` (already part of the protocol).
public func unloadAllEngines() async {
  for engine in engines {
    await engine.unloadModel()
  }
}

/// Unload a single engine by ID. No-op if the ID is unknown (eviction is
/// best-effort; an absent engine is already "unloaded").
public func evictEngine(forEngineID engineID: String) async {
  await enginesByID[engineID]?.unloadModel()
}
```

`engines` / `enginesByID` stay `let`; we are not removing engines from the registry, only releasing the weights each one holds. The engine instances are cheap (no weights until `loadModel`), so keeping them registered for the next `loadModel` is correct and avoids re-registration churn. Because `EngineRouter` is an `actor`, the iteration is serialized and `Sendable`-safe; each `unloadModel()` is itself actor-isolated on its engine.

### `VinetasClient` (Sendable final class) — public convenience

```swift
// Vinetas.swift — new extension on VinetasClient

extension VinetasClient {

  /// Release all resident model weights across every registered engine.
  /// Safe to call repeatedly; engines with nothing loaded are no-ops.
  /// After this, the next generate/preview pays the model-reload cost.
  public func unloadAll() async {
    await router.unloadAllEngines()
    await currentTelemetry()?.capture(/* see Observability */)
  }

  /// Evict a single engine's resident weights by engine ID
  /// (e.g. "flux2", "pixart-sigma").
  public func evictEngine(forEngineID engineID: String) async {
    await router.evictEngine(forEngineID: engineID)
  }
}
```

Notes:
- `VinetasClient` is a `Sendable final class` whose only mutable state is the lock-guarded telemetry reporter (`Vinetas.swift:67`); these methods touch only the actor-isolated router, so no new locking is needed.
- Keep the surface minimal: `unloadAll()` covers the common "app is backgrounding / under pressure" case; `evictEngine(forEngineID:)` covers the rarer "free the big Flux2 engine but keep PixArt warm" case.

## Cancellation teardown

Today a cancelled generation `Task` unwinds through the `defer { isGenerating = false }` but leaves the pipeline resident. PixArt already flushes the cache on exit (`defer { VinetasMemory.releaseMLXCache() }`, `PixArtEngine.swift:312`); Flux2 does not. We add `withTaskCancellationHandler` around the inner pipeline call in **both** engines' `generate(request:stepProgress:)` so cancellation deterministically flushes the MLX cache.

Sketch (Flux2, mirrors into PixArt):

```swift
// inside generate(...), wrapping the pipeline.generate* call:
isGenerating = true
defer { isGenerating = false }

let flux2Result = try await withTaskCancellationHandler {
  try await pipeline.generateTextToImageWithResult(/* … */)
} onCancel: {
  // Runs synchronously on cancellation; must be nonisolated + Sendable-safe.
  // Memory.clearCache() is a global MLX call, safe off the actor.
  VinetasMemory.releaseMLXCache()
}
```

`VinetasMemory.releaseMLXCache()` is a static `enum` call wrapping `Memory.clearCache()` — it is `Sendable`, non-actor-isolated, and already documented safe on both platforms, so it is legal inside the synchronous `onCancel` closure. The underlying pipeline call must itself honor cancellation for the inner work to stop promptly; if it doesn't, the handler still fires when the awaited task is cancelled and flushes the cache once the call returns/throws.

**Flush vs. full unload on cancel — recommendation: flush only.** Dropping the whole pipeline (`unloadModel()`) on every cancel reclaims the most RAM but forces a full multi-component reload (text encoder + transformer + VAE) on the very next generate — expensive and user-visible, and a rapid Generate→Cancel→Generate toggle (the documented single-flight UX) would thrash reloads. Flushing the cache reclaims the transient working-set buffers (the part that actually spikes during diffusion) while keeping the loaded weights warm. Reserve full unload for the explicit `unloadAll()` / `evictEngine()` path and for OS memory-pressure events (consumer-driven). Do **not** call `unloadModel()` from inside `onCancel`: it is `async` and actor-isolated on the engine, which the synchronous `onCancel` closure cannot await — a flush is the right granularity here anyway.

Also fold the existing PixArt `defer { VinetasMemory.releaseMLXCache() }` into this same structure for symmetry, or leave it — it already covers cancel; the Flux2 gap is the real fix.

## macOS cache-limit decision

`configureMLXBudgetForCurrentProcess()` is currently a no-op on macOS (`VinetasMemory.swift:138-142`, `#if os(iOS)`). Two options:

- **(A) Keep iOS-only.** Lowest risk; macOS MLX behaves as today (unbounded cache).
- **(B) Set a loose macOS `cacheLimit`.** Add a macOS branch that sets `Memory.cacheLimit` to a generous fraction of physical RAM (no `memoryLimit` — macOS has no jetsam cap and a hard memory limit risks OOM-aborting valid large generations).

**Recommendation: (B), loose cap.** The macOS GL4 rejection symptom ("loads, refreshes, runs or responds very slowly") is consistent with an ever-growing MLX buffer cache pinning RAM and pushing the system into memory compression/swap during gallery scroll and repeated generations. An *uncapped* cache only ever grows; a generous `cacheLimit` lets MLX recycle buffers under its own budget instead of holding everything. Make it loose (e.g. proportional to `systemMemoryGB`, not the 32 MiB iOS value) so it doesn't throttle throughput on high-RAM Macs, and gate it behind the existing function so call sites (`Flux2Engine.swift:183`, `PixArtEngine.swift:214`) need no change. Treat the exact fraction as tunable and verify against the 4K working set for Vinetas#92 before shipping.

```swift
#if os(iOS)
  // …existing iOS body…
#else
  // macOS: no jetsam cap → set only a loose cache ceiling, never memoryLimit.
  let total = VinetasMemory.systemMemoryBytes
  Memory.cacheLimit = Int(Double(total) * 0.5)   // tune; do NOT set memoryLimit
#endif
```

## Observability

Surface read-only MLX state so consumers (and the GL4 perf work) can log the effective throttle. Add to `VinetasMemory`:

```swift
/// The current MLX buffer-cache ceiling in bytes (0 means "unbounded" pre-config).
public static var currentCacheLimit: Int { Memory.cacheLimit }

/// A snapshot of MLX memory counters (active / cache / peak) for logging.
public static func snapshot() -> Memory.Snapshot { Memory.snapshot() }
```

(Exact MLX `Memory` member names to be confirmed against the pinned MLX version; `cacheLimit` is already used as a setter at `:141`, so the getter is the same property.) Optionally emit a telemetry event from `unloadAll()` carrying `currentCacheLimit` before/after, so the throttle's effect is visible in instrumentation.

## Consumer wiring (context — app work, tracked in Vinetas#82)

The Vinetas app calls the new API on lifecycle transitions. Brief, illustrative call sites:

- **iOS background** — in the scene/app `.background` phase: `await VinetasClient.shared.unloadAll()` (or evict just Flux2 to keep PixArt warm).
- **iOS memory warning** — on `UIApplication.didReceiveMemoryWarningNotification` / `.memoryWarning` scene phase: `await VinetasClient.shared.unloadAll()` (overlaps Vinetas#56).
- **macOS** — no system memory-warning notification today; wire eviction to explicit user action (e.g. "Unload models" menu / on window close of the generation surface) and rely on the loose `cacheLimit` (option B) for steady-state pressure. This is the main macOS lever for the GL4 fix.
- **Single-flight cancel** — the app already toggles Generate→Cancel; cancellation teardown is handled inside the engine (above), so the app needs no extra call there.

## Risks

- **Reload latency after eviction.** A full `unloadAll()` forces the next generate to reload all components (Flux2: text encoder + transformer + VAE). Mitigate by preferring cache-flush-on-cancel (keeps weights warm) and reserving full unload for genuine pressure/background transitions.
- **Double-unload safety.** Both engines' `unloadModel()` are idempotent — they guard on `if let pipeline` and nil everything; PixArt's "no-op when nothing loaded" is already asserted (`PixArtEngineTests.swift:308`). `unloadAllEngines()` over a fully-unloaded set is therefore safe to call repeatedly.
- **Flux2 cache-flush asymmetry.** Flux2's `unloadModel()` flushes via `pipeline.clearAll()` (`:206`) but does **not** call `releaseMLXCache()` directly; PixArt does (`:247`). After the cancellation change, confirm Flux2's cancel path flushes the cache (the new `onCancel` does this) and decide whether to also add `VinetasMemory.releaseMLXCache()` to `Flux2Engine.unloadModel()` for parity.
- **Actor reentrancy.** `unloadModel()` is actor-isolated; calling `unloadAll()` mid-generation will suspend behind the in-flight `generate` on the same engine actor (it cannot interleave with the synchronous portions). It will run *after* the current generate's awaited work yields — acceptable, but note that `unloadAll()` does not *cancel* in-flight work; pair it with Task cancellation if the consumer wants immediate teardown.
- **macOS `cacheLimit` tuning.** Too-tight a cap throttles throughput; the recommendation deliberately keeps it loose and flags it for measurement against the 4K working set.

## Test plan

Unit (no GPU — `SwiftVinetasTests`, using `MockEngine` which already records `.unloadModel`, `MockEngine.swift:74/:179`):
- `unloadAll()` fans out: build a router with two `MockEngine`s, load both, call `client.unloadAll()`, assert each mock recorded `.unloadModel`.
- `evictEngine(forEngineID:)`: assert only the targeted mock recorded `.unloadModel`; unknown ID is a no-op (no throw, no recorded call).
- Idempotency: call `unloadAll()` twice; second call still safe, mocks record a second `.unloadModel` without error.

Cancellation teardown (mock-level, no GPU):
- Add a `MockEngine.generate` that suspends until cancelled and exposes a "cache flushed" flag; wrap with the same `withTaskCancellationHandler` shape; cancel the Task; assert the flush ran and `isGenerating` was reset.

GPU (`SwiftVinetasGPUTests`, hardware-gated like the existing `unloadModelReleasesMemory` at `Flux2IntegrationTests.swift:253`):
- Load Klein 4B, start a generate, cancel the Task, then assert (proxy, as the existing test does) that a subsequent operation reflects a flushed/teardown state.
- Asserting the MLX cache was flushed: read `VinetasMemory.currentCacheLimit` / `snapshot()` (new getters) before and after; assert `cacheMemory` dropped after cancel/unload. Where a hard counter is unavailable, keep the existing proxy assertion (engine refuses to generate after `unloadModel()`).

## Sequencing

1. **Lands first (independent, low-risk):** `EngineRouter.unloadAllEngines()` + `evictEngine(forEngineID:)` and the `VinetasClient.unloadAll()` / `evictEngine(...)` convenience, with the mock-based unit tests. This alone unblocks Vinetas#82 app wiring and gives a manual macOS lever.
2. **Independent:** Observability getters (`currentCacheLimit`, `snapshot()`) — tiny, can land with (1) or separately.
3. **Independent:** macOS loose `cacheLimit` in `configureMLXBudgetForCurrentProcess()` — measurement-gated; directly targets the GL4 symptom and Vinetas#92 headroom.
4. **After (1):** Cancellation teardown (`withTaskCancellationHandler` in both engines' `generate`), since it benefits from the eviction primitives being in place and shares the flush helper.

Items (1)–(3) have no ordering dependency among themselves; (4) is best after (1).

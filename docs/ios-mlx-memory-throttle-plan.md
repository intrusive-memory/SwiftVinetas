# iOS MLX Memory Throttle — Plan to Stop Jetsam OOM Kills

> **Status:** Plan only. No code written yet. Handoff to implementing agent.
> **Repo of record for the fix:** SwiftVinetas (this repo), branch `development`.
> **Consuming app:** `Vinetas` / `VinetasIOS` (separate repo at `~/Projects/Vinetas`).
> **Platform scope:** iOS only (`#if os(iOS)`). macOS is intentionally untouched.

## Problem

On iOS the app is terminated by jetsam for exceeding its per-process memory
limit during PixArt image generation. It happens during/around model load and
diffusion — fast enough that no low-memory warning is delivered before the kill.

## Root cause (verified)

SwiftVinetas **never sets any MLX memory limit**. Confirmed by:

```
grep -rn "cacheLimit\|memoryLimit\|MLX.Memory\|withWiredLimit\|os_proc_available_memory" Sources/
# → no matches in the engine layer
```

So MLX runs with its documented defaults (see mlx-swift `Source/MLX/Memory.swift`):

- `MLX.Memory.memoryLimit` defaults to **1.5× the device's recommended max
  working set size**.
- `MLX.Memory.cacheLimit` defaults to the memory limit — an effectively
  unbounded Metal buffer cache.

On iOS, "1.5× recommended working set" is **larger than the jetsam per-process
cap**. When `PixArtEngine.loadModel` materializes the weights and the diffusion
buffer cache grows, MLX allocates straight past the cap and the process is
killed.

Two things this is **not**:

- **Not** a CPU-thread concurrency problem. Throttling worker threads will not
  cap the footprint; the spike is GPU/Metal buffer growth under a too-high
  ceiling.
- **Not** an entitlements problem (at least not in the dev build). Both
  `com.apple.developer.kernel.increased-memory-limit` and
  `com.apple.developer.kernel.extended-virtual-addressing` are present in
  `VinetasIOS.entitlements` and were confirmed embedded in a signed dev archive
  via `codesign -d --entitlements :- VinetasIOS.app`. **Still to verify:** the
  distribution (TestFlight/App Store) build signed by Xcode Cloud — see
  "Prerequisite check" below.

### Why physicalMemory checks don't help

Every existing memory check (app `MemoryValidator`, library `VinetasMemory`,
`PixArtEngine.validateMemory`) compares **total physical RAM**
(`ProcessInfo.processInfo.physicalMemory`) against the model's
`minimumMemoryGB` (a device-class gate — PixArt is 8). The jetsam cap is a
**per-process** limit far below physical RAM, so these checks pass on devices
that then get killed. The correct per-process signal is
`os_proc_available_memory()` (iOS/iPadOS only; not native macOS).

## The fix

Give MLX a real ceiling derived from the live per-process budget, so it
self-throttles instead of spiking. MLX's own mechanism for this is back-pressure:
per its docs, when `memoryLimit` is exceeded, **"calls to malloc will wait on
scheduled tasks"** — that is the throttle.

Two knobs (both `public static var` on `MLX.Memory`):

1. **`memoryLimit`** — clamp to the per-process budget so allocation
   back-pressures rather than overshooting the jetsam cap.
2. **`cacheLimit`** — set small so freed buffers return to the OS instead of
   inflating the resident footprint. MLX docs note tiny caches (e.g. 2 MB)
   "perform just as well" for many workloads.

Plus `MLX.Memory.clearCache()` at unload / after generation / on memory warning.

## Concrete changes

### 1. New helper in `Sources/SwiftVinetas/Core/VinetasMemory.swift`

Add a budget-configuration API to the existing `VinetasMemory` enum. Keep the
"available bytes" injectable so it is unit-testable without a device (mirrors
the existing `validate(for:availableMemoryBytes:)` seam).

```swift
#if os(iOS)
import os   // os_proc_available_memory
#endif
import MLX

extension VinetasMemory {

    /// Bytes the current process may still allocate before hitting its limit.
    /// On macOS there is no per-process jetsam cap, so this returns nil.
    public static var processAvailableMemoryBytes: UInt64? {
        #if os(iOS)
        let available = os_proc_available_memory()   // 0 if already over limit
        return available > 0 ? UInt64(available) : nil
        #else
        return nil
        #endif
    }

    /// Clamp MLX's global memory + cache limits to the current process budget
    /// so weight load / diffusion can't spike past the jetsam cap.
    /// No-op on macOS (virtual memory + swap; no per-process cap).
    ///
    /// - Parameters:
    ///   - availableBytes: per-process headroom; defaults to a live reading.
    ///     Injectable for tests.
    ///   - safetyFraction: fraction of the budget to hand MLX (headroom for
    ///     non-MLX allocations). Start at 0.8; tune on device.
    ///   - cacheLimitBytes: MLX buffer cache cap. Start at 32 MB; tune.
    public static func configureMLXBudgetForCurrentProcess(
        availableBytes: UInt64? = processAvailableMemoryBytes,
        safetyFraction: Double = 0.8,
        cacheLimitBytes: Int = 32 * 1_048_576
    ) {
        #if os(iOS)
        guard let available = availableBytes, available > 0 else { return }
        MLX.Memory.memoryLimit = Int(Double(available) * safetyFraction)
        MLX.Memory.cacheLimit  = cacheLimitBytes
        #endif
    }

    /// Release MLX's cached Metal buffers back to the OS.
    public static func releaseMLXCache() {
        MLX.Memory.clearCache()
    }
}
```

Notes:
- `import MLX` is already used elsewhere in this module
  (`Sources/SwiftVinetas/Understanding/*.swift`), so it is available here.
- `os_proc_available_memory()` returns `0` if the process is already over its
  limit → we bail and leave MLX defaults (nothing useful to set).

### 2. Wire into the PixArt load path — `Sources/SwiftVinetas/Engine/PixArtEngine.swift`

Current line references (verify before editing — file may have drifted):

- `loadModel(...)` at **line 142**; `newPipeline.loadModels { … }` at **line 214**.
- `unloadModel()` at **line 240** (`pipeline.unloadModels()` at 243).
- `generate(...)` at **line 255**.

Changes:

- In `loadModel`, **before** `newPipeline.loadModels { … }`:
  `VinetasMemory.configureMLXBudgetForCurrentProcess()` — idempotent, cheap,
  re-reads the live budget on each load.
- In `unloadModel`, after `pipeline.unloadModels()`:
  `VinetasMemory.releaseMLXCache()`.
- In `generate`, add `defer { VinetasMemory.releaseMLXCache() }` (or release
  after the diffusion result returns) so a multi-image session does not
  accumulate cache.

### 3. (Symmetry) `Sources/SwiftVinetas/Engine/Flux2Engine.swift`

Mirror the `configureMLXBudgetForCurrentProcess()` call before its load. The
clamp is `#if os(iOS)`-only, and Flux2 is macOS-only in this app, so this is a
no-op on the real Flux path — included only so the engines behave identically
if Flux ever runs on iOS.

### 4. App-side memory-warning hookup (Vinetas app repo — one change)

`VinetasIOS/AppLifecycleManager.swift` already observes
`UIApplication.didReceiveMemoryWarningNotification` and cancels generation
(`handleMemoryWarning()`). Add a call to `VinetasMemory.releaseMLXCache()`
there (directly, or via a thin `VinetasClient` passthrough if the app should
not import the engine module directly) so a warning sheds the cache
immediately. This is the **only** change in the app repo.

## Prerequisite check (do this first — cheap, possibly decisive)

Confirm the increased-memory-limit entitlement survives **distribution**
signing, not just the dev build:

```bash
# dev archive (already verified present):
codesign -d --entitlements :- "<VinetasIOS.app>" 2>/dev/null \
  | grep -A1 -E "increased-memory-limit|extended-virtual-addressing"

# distribution build (the one actually getting killed): download the .ipa from
# App Store Connect / Xcode Cloud, then:
unzip App.ipa -d out
codesign -d --entitlements :- out/Payload/VinetasIOS.app 2>/dev/null \
  | grep -A1 -E "increased-memory-limit|extended-virtual-addressing"
```

If the distribution build is **missing** the entitlement, the per-process cap
is far lower than expected and the clamp would be sizing to an artificially tiny
budget — fix the signing/profile first.

## Verification

- **Unit (CI-safe, no GPU):** test `configureMLXBudgetForCurrentProcess(availableBytes:safetyFraction:cacheLimitBytes:)`
  sets `MLX.Memory.memoryLimit` and `cacheLimit` to the expected values for an
  injected `availableBytes`. (Reading back the MLX statics is fine; restore them
  in teardown since they are process-global.)
- **On device (the real proof):** build VinetasIOS to a 16 GB iPad, generate
  with PixArt, watch `MLX.Memory.snapshot()` / `peakMemory` (already exposed)
  and Instruments → Allocations. Confirm peak stays under the budget and no
  jetsam.
- **Confirm kills stop:** use Apple's Jetsam event reports
  (developer.apple.com → "Identifying high-memory use with jetsam event
  reports").
- **Tuning:** sweep `safetyFraction` (0.8 start) and `cacheLimitBytes` (32 MB
  start). Lower cache = lower footprint, possibly slower; measure peak vs.
  throughput.

## Risks / caveats

- **Back-pressure can stall** if the working set genuinely cannot fit even
  throttled. If measured PixArt peak exceeds an 8 GB iPad's per-process budget
  no matter what, that device cannot run it and should be gated out (separate
  decision). Today the iOS launch gate is `physicalMemory >= 15 GB`
  (`VinetasIOSApp.swift`), so only 16 GB devices run at all — the throttle
  should suffice there.
- **Global state:** `MLX.Memory.memoryLimit`/`cacheLimit` are process-global
  statics shared with any other MLX work in-process (e.g. `Understanding/*`
  vision models). Setting per-load is fine (idempotent); just be aware the
  clamp is process-wide (which is correct, since the jetsam budget is too).

## Workflow / handoff notes

- Implement on SwiftVinetas `development`. Per project convention, library
  changes flow through the local-sibling-checkout dev cycle; the Vinetas app
  consumes this via its sibling path until a SwiftVinetas release is tagged.
- Do **not** bump versions or tag from this work directly — follow the repo's
  normal ship-swift-library flow when ready.
- Keep the change `#if os(iOS)`-fenced; do not alter macOS memory behavior.

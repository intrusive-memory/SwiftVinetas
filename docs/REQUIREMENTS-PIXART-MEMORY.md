---
type: project
title: "SwiftVinetas — PixArt iOS Peak-Memory: Consumer & Profiling Requirements"
date: 2026-07-10
status: "ACTIVE — profiling harness DONE; consumer sorties pending SwiftTuberia release"
master_index: "/Users/stovak/Projects/REQUIREMENTS.md"
companion: "../SwiftTuberia/REQUIREMENTS-PIXART-MEMORY.md"
---

# SwiftVinetas — PixArt iOS Peak-Memory: Consumer & Profiling Requirements

**Mission**: Measure the PixArt-Sigma iOS peak-memory problem, then consume the SwiftTuberia
fix that resolves it. SwiftVinetas does **not** own the pipeline memory behavior — that lives
in the `SwiftTuberia` dependency (`DiffusionPipeline`); see
`../SwiftTuberia/REQUIREMENTS-PIXART-MEMORY.md`. This repo's responsibilities are: (1) a
jetsam-survivable profiler to establish before/after baselines, (2) bumping the SwiftTuberia
floor once the fix ships, and (3) encoding the new per-phase footprint telemetry.

**Background**: PixArt OOM-kills on iPad while the larger FLUX.2 succeeds, because
`DiffusionPipeline` keeps the ~1.2 GB int4 T5-XXL encoder resident through the denoise loop.
`PixArtEngine` (this repo) only orchestrates load/generate/unload — it cannot fix the resident
set on its own.

---

## Status Snapshot (2026-07-10)

| # | Area | Status | Evidence / Target |
|---|---|---|---|
| 1 | Jetsam-survivable memory profiler (library) | ✅ DONE | `Sources/SwiftVinetas/Core/VinetasMemoryProfiler.swift` |
| 2 | PixArt profiling driver test + Makefile target | ✅ DONE | `Tests/SwiftVinetasGPUTests/PixArtMemoryProfileTests.swift`; `make profile-pixart-memory` |
| 3 | Bump SwiftTuberia floor to the fixed release | ✅ DONE | REQ-VIN-01 — `Package.swift` floored `SwiftTuberia` at `0.7.9` (REQ-MEM-01 fix) |
| 4 | Encode new per-phase `physFootprint` Tuberia events | ❌ TODO | REQ-VIN-02 — `Sources/VinetasCLICore/Telemetry/TuberiaEventEncoding.swift` |
| 5 | Telemetry integration test asserting the encode→denoise drop | ❌ TODO | REQ-VIN-03 — `Tests/.../TelemetryIntegrationTests` |
| 6 | Device-tier memory config for PixArtEngine (parity with Flux2) | ❌ TODO | REQ-VIN-04 — `Sources/SwiftVinetas/Engine/PixArtEngine.swift:290` |
| 7 | Align SwiftVinetas memory gate with per-process jetsam budget | ❌ TODO | REQ-VIN-05 — `PixArtEngine.validateMemory:679`, `VinetasMemory.validate:36` |

REQ-VIN-01/02/03 are **blocked on the SwiftTuberia release** (companion REQ-MEM-01/04).
REQ-VIN-04/05 are **independent** of the Tuberia work and can land now. The profiler
(items 1–2) is complete and usable now for the macOS/device baseline.

---

## Completed Work (this session)

### REQ-VIN-P0: Jetsam-Survivable Memory Profiler — ✅ DONE

**Files**:
- `Sources/SwiftVinetas/Core/VinetasMemoryProfiler.swift`
- `Tests/SwiftVinetasGPUTests/PixArtMemoryProfileTests.swift`
- `Makefile` (`profile-pixart-memory` target)

Samples `phys_footprint` (Jetsam's watched value) + `os_proc_available_memory()` (per-process
budget) every 50 ms, stamped with a caller phase (`load:<component>` → `generate:encode` →
`denoise:N` → `generate:decode`). Every sample is emitted via `os_log`
(subsystem `productions.intrusive-memory.vinetas`, category `memprofile`) so the timeline
**survives a jetsam kill** and is retrievable from the paired Mac; a fsync'd CSV is written in
parallel. Installs a `DispatchSourceMemoryPressure` to capture warning/critical before the kill.
Intentionally has **no MLX import** so it builds/type-checks standalone. Verified via
`xcrun swiftc -typecheck` for macOS26 and iOS26 (full test-target build requires the Metal
toolchain, which must run on a developer machine).

**On-device capture** (this repo is a library; running XCTest on a physical iPad needs a signed
test host + on-device weights — prefer calling the profiler from the host app's generation
entry point):
```
log stream --device --predicate 'subsystem == "productions.intrusive-memory.vinetas"' --style compact
# or after a kill:
log collect --device --last 10m --output pixart.logarchive
log show pixart.logarchive --predicate 'category == "memprofile"' --style compact
```

---

## Outstanding Work (Ordered — blocked on SwiftTuberia release)

### REQ-VIN-01: Bump the SwiftTuberia Dependency Floor to the Fixed Release

**Priority**: 🔴 CRITICAL — without it, the app still ships the OOM'ing pipeline.

**Files**: `Package.swift:97-99` (currently `sibling("SwiftTuberia", …, from: "0.7.8")`).

**Work**:
1. After SwiftTuberia tags the release carrying REQ-MEM-01 (and ideally 02–04), bump the
   `from:` floor to that version.
2. Re-resolve, re-run `make test-gpu` (PixArt path) locally to confirm generation still produces
   correct output on the phased-load pipeline.
3. Update AGENTS.md / changelog with the floor bump rationale (PixArt iOS OOM fix).

**Exit**: `Package.resolved` pins the fixed SwiftTuberia; PixArt output tests pass.

---

### REQ-VIN-02: Encode the New Per-Phase `physFootprint` Tuberia Events

**Priority**: 🟢 MEDIUM — depends on SwiftTuberia REQ-MEM-04 adding the field.

**Files**:
- `Sources/VinetasCLICore/Telemetry/TuberiaEventEncoding.swift` (pipeline event encoding;
  `pipelineConfigured` already carries `peakMemoryBytes`/`phasedMemoryBytes` ~:38-51).
- Mirror the pattern in `Sources/VinetasCLICore/Telemetry/Flux2EventEncoding.swift` (the
  `physFootprint` coding key, `encodeIfPresent`, ~:42-171).

**Work**:
1. When SwiftTuberia REQ-MEM-04 adds `physFootprint` to weight-load/encode/denoise/decode
   events, add matching `CodingKeys` and `encodeIfPresent(physFootprint, …)` in the Tuberia
   adapter, exactly as `Flux2EventEncoding` does.
2. Keep the field optional so older Tuberia releases still encode cleanly.

**Exit**: A Tuberia telemetry trace round-trips the per-phase footprint series through the
Vinetas encoding surface.

---

### REQ-VIN-03: Telemetry Integration Test — Assert the Encode→Denoise Footprint Drop

**Priority**: 🟢 MEDIUM — regression guard for the fix.

**Files**: `Tests/SwiftVinetasTests/.../TelemetryIntegrationTests` (see existing
`testPixArtEngineRoutingEmitsCorrectEvents`, invoked by `make test-telemetry-debug`).

**Work**:
1. Add a test that runs a PixArt generation and, from the emitted per-phase `physFootprint`
   series (REQ-VIN-02) or the external profiler, asserts resident footprint at the first denoise
   step is materially lower (≥ ~800 MB drop) than at encode — proving the T5 was freed.
2. Gate to model-presence (`XCTSkipUnless` / `.enabled(if:)`) so it is CI-safe.

**Exit**: The test fails on a pre-fix (un-freed encoder) pipeline and passes on the fixed one.

---

### REQ-VIN-04: Device-Tier Memory Config for `PixArtEngine` (Parity With Flux2)

**Priority**: 🔵 HIGH — independent of the Tuberia release. Even with the T5 unload, an 8 GB
iPad may stay marginal without tier-aware settings.

**Files**: `Sources/SwiftVinetas/Engine/PixArtEngine.swift:290` (only calls
`configureMLXBudgetForCurrentProcess()`); contrast `Sources/SwiftVinetas/Engine/Flux2Engine.swift:245`
(`MemoryOptimizationConfig.recommended(forRAMGB:)`).

**Current state**: `PixArtEngine.loadModel` applies only the flat iOS budget (32 MiB cache
limit). `Flux2Engine` additionally routes iPad / low-RAM devices to an optimization profile
(eval frequency, clear-on-eval, and lower working set). PixArt has no equivalent — every device
gets the same settings.

**Work**:
1. Give `PixArtEngine` a device-tier-aware configuration analogous to Flux2's, derived from
   `VinetasMemory.systemMemoryGB` / `DeviceCapability`.
2. If the underlying knobs (e.g. `clearCacheEveryNSteps`, phased-load toggle) live in SwiftTuberia
   (REQ-MEM-02), consume them through whatever public surface Tuberia exposes — coordinate the API
   so the tier *decision* can live here while the *mechanism* lives in Tuberia. If Tuberia derives
   the tier internally, this reduces to selecting resolution/step defaults per tier.

**Exit**: PixArt on a constrained tier runs with tighter settings than on a high-RAM Mac; no
regression on high-RAM.

---

### REQ-VIN-05: Align the SwiftVinetas Memory Gate With the Per-Process Jetsam Budget

**Priority**: 🔵 HIGH — independent of Tuberia. Mirrors companion REQ-MEM-03 on the consumer side.

**Files**: `Sources/SwiftVinetas/Engine/PixArtEngine.swift:679` (`validateMemory` reads
`VinetasMemory.systemMemoryBytes`); `Sources/SwiftVinetas/Core/VinetasMemory.swift:36-39`
(`validate` checks physical RAM vs `minimumMemoryGB`); `processAvailableMemoryBytes` already
exists at `:107`.

**Current state**: SwiftVinetas has its *own* pre-generation gate (separate from Tuberia's) that
validates against **physical** memory, not the per-process jetsam budget. On iOS this can pass on
a big iPad while the process is still jetsam-killed — the same defect as REQ-MEM-03, one layer up.
The Vinetas app's `IOS-RESOURCE-AUDIT.md` already flags this "wrong `physicalMemory`-based check."

**Work**:
1. On iOS, gate `VinetasMemory.validate` / `PixArtEngine.validateMemory` against
   `processAvailableMemoryBytes` (`:107`) rather than `systemMemoryBytes`. Keep physical RAM on
   macOS (no per-process cap).
2. Ensure the `.insufficient(required:available:)` result reports the jetsam-relevant available
   value so the app's `MemoryValidator` surfaces an honest verdict (app REQ-APP-05).

**Exit**: A unit test with a stubbed low per-process budget returns `.insufficient` on iOS; a
high budget passes. The gate no longer keys off device RAM on iOS.

---

## Cross-References

- Upstream fix (load-bearing): `../SwiftTuberia/REQUIREMENTS-PIXART-MEMORY.md` (REQ-MEM-01..04).
- Root cause + profiler notes: agent memory `pixart-ios-oom-root-cause`, `pixart-memory-profiler`.
- Parity reference: `../flux-2-swift-mlx` (`Flux2Pipeline.unloadTextEncoder`,
  `Flux2EventEncoding` physFootprint).

## Definition of Done (Master Acceptance)

1. Profiler establishes a documented before-baseline (peak ~1.66 GB, T5 resident through loop).
2. SwiftTuberia fix is consumed via REQ-VIN-01; PixArt generates on the target iPad without OOM.
3. Per-phase footprint telemetry flows through the Vinetas encoding surface (REQ-VIN-02).
4. A regression test guards the encode→denoise drop (REQ-VIN-03).

## History

| Date | Change |
|---|---|
| 2026-07-10 | File created. Profiler + driver test + Makefile target landed (REQ-VIN-P0 DONE). Consumer sorties (REQ-VIN-01..03) blocked on the SwiftTuberia release. |

---
mission: swift-vinetas-instrumentation
source_requirements: ../../../REQUIREMENTS-instrumentation.md
scope: single-repo (SwiftVinetas)
branch: instrumentation/01
refined: true
refine_passes: [atomicity, priority, parallelism, questions, spec-resync]
state: incomplete
---

# EXECUTION_PLAN.md — SwiftVinetas Instrumentation

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Overview

Instrument SwiftVinetas — the orchestration shim sitting between any host (Vinetas app, the `vinetas` CLI, tests) and the concrete diffusion engines (`Flux2Engine`, `PixArtEngine`) — so that every cross-boundary handoff emits a `VinetasTelemetryEvent`. SwiftVinetas does no numerical work; its telemetry value is **handoff fidelity**: the prompt, dims, seed, steps, guidance, engine selection rationale, memory verdict, model lifecycle, concurrency rejections, LoRA attaches, and image-understanding side channels.

**Source of truth:** [REQUIREMENTS-instrumentation.md](../../../REQUIREMENTS-instrumentation.md). All §-references in this plan resolve there.

**Ship order:** Last in the cross-repo cohort. Prerequisite pin floors (SwiftTuberia ≥ 0.7.0, flux-2-swift-mlx ≥ 3.2.0, pixart-swift-mlx ≥ 0.7.0, SwiftAcervo ≥ 0.13.0) were raised in commit `bf5b867`. The cross-repo gate is already clear.

### What changed since the prior refine

This plan was re-refined on 2026-05-15 against the spec tightening in commit `6e149af`. Material changes from the previous draft:

- **Dropped runID from every event.** §3.1 no longer carries `runID` on `generationStart`/`End`/`errorThrown`. The host-side adapter (`VinetasEngineTelemetryAdapter`) holds the runID and stamps every forwarded event via `GenerationTelemetry.capture(runID:phase:payload:)`. SwiftVinetas itself never sees a runID.
- **Dropped per-call `telemetry:` parameter on the static `Vinetas` API.** §4.4 explicitly rejects it. Telemetry is wired once per process via `VinetasClient.shared.setTelemetry(reporter)`; static wrappers inherit transitively.
- **Single-emission rule.** §5 now emits `generationStart`/`End` *only* at `VinetasClient.generate/preview`, never inside `<Engine>.generate`. Dep-level events (`Flux2TelemetryEvent.pipelineStart`, etc.) cover the engine boundary.
- **Removed S4 and S8** from the previous plan. S4's "runID plumbing into Vinetas.generate" became a no-op once the spec dropped runID parameters. S8's "runID coherence E2E" makes no sense when SwiftVinetas has no runID to cohere. Both deleted.
- **OQ-8 folded into S3.** Propagation to `ImageClassifier` / `FeatureExtractor` is now part of the seam sortie, eliminating the parallel-write conflict on `Vinetas.swift`.
- **Added a propagation test** (§7) that verifies `setTelemetry` reaches router → engines → understanding actors → nil-teardown.

### Repo-local execution rules

- Working directory for every sortie: `/Users/stovak/Projects/SwiftVinetas`.
- Branch: `instrumentation/01`. All sorties commit to this branch. One PR per repo against `development` at the end (`development` is this repo's default, not `main`).
- Per CLAUDE.md: **never** `swift build` / `swift test`. Use XcodeBuildMCP tools (`swift_package_build`, `swift_package_test`) locally. Prefer Makefile targets when they exist (`make build`, `make test-unit`).
- Tests run on macOS arm64. iOS unit tests should pass too (the Telemetry module is pure Swift). GPU/integration tests stay local-only.
- Final release: bump `VinetasClient.version` from `"0.11.0-dev"` to `"0.12.0"` and tag (§9).

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|--------------|
| swift-vinetas-instrumentation | `/Users/stovak/Projects/SwiftVinetas` | 6 | 0 | Pin floors already published (cleared in `bf5b867`) |

Single work unit. Layer 0 within this repo — sortie ordering is the dependency graph here.

---

## Parallelism Structure

**Critical Path** (length 4):

```
S1 (or S2) ──► S3 ──► S4 ──► S6
```

**Parallel Execution Groups**:

- **Group A — Foundation (parallel)**:
  - S1 (event type) — Sub-agent 1
  - S2 (reporter protocol + Noop) — Sub-agent 2
  - Supervising agent runs `swift_package_build` after both finish.
- **Group B — Seam + propagation (sequential)**:
  - S3 (engine setTelemetry seam, VinetasClient/EngineRouter wiring, understanding-actor propagation) — Supervising agent (multi-file, build-verified).
- **Group C — Emissions (parallel)**:
  - S4 (Vinetas + Engine emission sites) — Supervising agent.
  - S5 (Understanding emissions) — Sub-agent 3. Touches only `Sources/SwiftVinetas/Understanding/*` — no file overlap with S4.
  - Supervising agent runs `swift_package_build` after both finish.
- **Group D — Tests (sequential)**:
  - S6 (test suite) — Supervising agent.

**Agent allocation**: 1 supervising agent + up to 3 sub-agents (sergeant principle).

**Build constraint**: sub-agents never run builds. Supervising agent runs `swift_package_build` after each parallel group.

---

## Sortie dependency graph

```
S1 (event type) ──┐
                  ├──► S3 (seam + propagation) ──► S4 (emission sites) ──► S6 (tests)
S2 (reporter)  ───┘                                S5 (understanding) ───►
                                                   (parallel with S4)
```

---

## Sortie 1: Telemetry event type

**Priority**: 21 — Foundation type required by every downstream sortie.

**Agent role**: Sub-agent 1 (foundation, no build operations).

**Entry criteria:**
- [ ] Branch `instrumentation/01` checked out.
- [ ] `Package.resolved` shows SwiftTuberia ≥ 0.7.0 (the version that vends `TuberiaTensorStat`). Verify: `grep -A1 SwiftTuberia Package.resolved | grep version` shows a 0.7.x or higher line.

**Tasks:**
1. Create `Sources/SwiftVinetas/Telemetry/` directory.
2. Implement `Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` **verbatim** from REQUIREMENTS §3.1: `public enum VinetasTelemetryEvent: Sendable` with every case as listed. **No `runID` fields anywhere** — the spec is explicit.
3. Add the three nested enums verbatim: `GenerationModeTag`, `MemoryVerdict`, `ErrorPhase` (14 cases).
4. `import Foundation` and `import Tuberia` (for `TuberiaTensorStat` in `featureExtractionComplete`).

**Exit criteria** (all machine-verifiable):
- [ ] `swift_package_build` succeeds on macOS arm64 (run by supervising agent after Group A).
- [ ] `grep -c "case generationStart" Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` returns `1`.
- [ ] **No-runID check**: `grep -n "runID" Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` returns ZERO lines. (The previous draft of this plan demanded the opposite — the new spec inverts it.)
- [ ] `grep -c "case errorThrown" Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` returns `1`, and the same case carries exactly two parameters: `phase: ErrorPhase, errorDescription: String`.
- [ ] All 14 `ErrorPhase` cases present: count matches the §3.1 list.
- [ ] All 4 `MemoryVerdict` cases present: `grep -E "case (sufficient|warningMarginal|insufficient|unavailable)" Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift | wc -l` returns `4`.

---

## Sortie 2: Reporter protocol + Noop default

**Priority**: 21 — Foundation protocol. Parallelizable with S1.

**Agent role**: Sub-agent 2 (foundation, no build operations).

**Entry criteria:**
- [ ] Branch `instrumentation/01` checked out. Parallelizable with S1.

**Tasks:**
1. Implement `Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` verbatim from REQUIREMENTS §3.2.
2. Declare `public protocol VinetasTelemetryReporter: Sendable` with one method: `func capture(_ event: VinetasTelemetryEvent) async`.
3. Declare `public struct NoopVinetasTelemetryReporter: VinetasTelemetryReporter` with `public init()` and a no-op `capture`.
4. Confirm no other public symbols are added — §3 is exhaustive for v1.

**Exit criteria** (all machine-verifiable):
- [ ] `swift_package_build` succeeds (run by supervising agent after Group A).
- [ ] `grep -c "public protocol VinetasTelemetryReporter: Sendable" Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` returns `1`.
- [ ] `grep -c "public struct NoopVinetasTelemetryReporter" Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` returns `1`.

---

## Sortie 3: setTelemetry seam + full propagation

**Priority**: 19 — Establishes the propagation backbone every emission later relies on. OQ-8 resolution lives here (propagation extends to understanding actors).

**Agent role**: Supervising agent (multi-file edits + build verification).

**Entry criteria:**
- [ ] S1 COMPLETED.
- [ ] S2 COMPLETED.

**Tasks:**
1. Extend the `ImageGenerationEngine` protocol (`Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift`) per REQUIREMENTS §4.3: add `func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async` plus a defaulted no-op extension. **Additive only** — do not touch other methods.
2. Add `import os.lock`, the `private let _telemetryLock = OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>(initialState: nil)` property, `public func setTelemetry(_:) async`, and `internal func currentTelemetry() -> (any VinetasTelemetryReporter)?` to `VinetasClient` (`Sources/SwiftVinetas/Vinetas.swift`) per REQUIREMENTS §4.1.
3. Inside `VinetasClient.setTelemetry`, after writing through the lock, propagate to:
   - `await router.setTelemetry(reporter)` (covers all engines via the router actor).
   - **All long-lived `ImageClassifier` and `FeatureExtractor` instances held by the client.** First, audit ownership: `grep -n "ImageClassifier\|FeatureExtractor" Sources/SwiftVinetas/Vinetas.swift Sources/SwiftVinetas/Core/*.swift`. If `VinetasClient` holds long-lived instances, await `setTelemetry` on each. If they are constructed on-demand at each call site, document that propagation happens at construction time and add the line at each constructor invocation. Record the decision in a `// MARK: - Telemetry propagation` comment block.
4. Add the actor `EngineRouter` (`Sources/SwiftVinetas/Engine/EngineRouter.swift`) properties + method per REQUIREMENTS §4.2: `private var telemetry: (any VinetasTelemetryReporter)? = nil`, and `public func setTelemetry(_:)` that stores it and iterates `for engine in engines { await engine.setTelemetry(reporter) }`.
5. Override `setTelemetry(_:)` in `Flux2Engine` and `PixArtEngine` to store the reporter locally. Use an `OSAllocatedUnfairLock` or actor-isolated mutable property — whichever matches the existing concurrency model of each engine. **Do not wire any emissions yet** — that is Sortie 4.
6. Add `setTelemetry(_:)` to `ImageClassifier` (`Sources/SwiftVinetas/Understanding/ImageClassifier.swift`) and `FeatureExtractor` (`Sources/SwiftVinetas/Understanding/FeatureExtractor.swift`). Both are actors; a plain `var telemetry: (any VinetasTelemetryReporter)?` is sufficient.

**Exit criteria** (all machine-verifiable):
- [ ] `swift_package_build` succeeds.
- [ ] `grep -c "func setTelemetry" Sources/SwiftVinetas/Engine/ImageGenerationEngine.swift` returns at least `2` (protocol requirement + default extension).
- [ ] `grep -c "OSAllocatedUnfairLock" Sources/SwiftVinetas/Vinetas.swift` returns at least `1`.
- [ ] `grep -c "func setTelemetry" Sources/SwiftVinetas/Engine/Flux2Engine.swift Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns at least `2`.
- [ ] `grep -c "func setTelemetry" Sources/SwiftVinetas/Understanding/ImageClassifier.swift Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` returns at least `2`.
- [ ] `grep -c "await router.setTelemetry" Sources/SwiftVinetas/Vinetas.swift` returns at least `1`.
- [ ] `grep -c "await engine.setTelemetry" Sources/SwiftVinetas/Engine/EngineRouter.swift` returns at least `1`.
- [ ] `// MARK: - Telemetry propagation` comment block exists at the chosen propagation point.
- [ ] **No emissions yet**: `grep -nE "\.capture\(.*VinetasTelemetryEvent\." Sources/SwiftVinetas/` returns ZERO lines (S4 owns that).

---

## Sortie 4: Vinetas + Engine emission sites

**Priority**: 14 — High mechanical complexity (every emission site in §5 except understanding). No novel risk once S3 lands.

**Agent role**: Supervising agent. Parallelizable with S5 (disjoint file sets).

**Entry criteria:**
- [ ] S3 COMPLETED. (`grep -c "func setTelemetry" Sources/SwiftVinetas/Engine/Flux2Engine.swift` ≥ 1, etc.)

**Tasks:**

Wire emissions per REQUIREMENTS §5. **The single-emission rule is binding** — `generationStart`/`End` fire only at `VinetasClient.generate/preview` entry, never inside `<Engine>.generate`.

1. `Sources/SwiftVinetas/Vinetas.swift`:
   - `clientInitialized` at the end of `VinetasClient.init()` (§5 row 1, currently `Vinetas.swift:51`).
   - `engineRegistered` / `engineSkipped` inside the engine-registration block (§5 row 2, `Vinetas.swift:45–48`). One `engineRegistered` for PixArtEngine (always); one `engineRegistered` *or* `engineSkipped` for Flux2Engine depending on the 16 GB gate.
   - `generationStart` at the entry of `VinetasClient.generate(...)` and `VinetasClient.preview(...)` (§5 row 3, four sites: `Vinetas.swift:79, 113, 167, 226`). The `mode:` field disambiguates: `.textToImage`, `.imageToImage`, or `.preview`. Resolve the reporter via `currentTelemetry()`.
   - `generationEnd` via `defer` in the same four sites — success and failure paths. Use the captured-mutable-var idiom: `var success = false; var actualSeed: UInt64? = nil; var outputDims: [Int]? = nil` before the work; mutate on success; the defer reads them.
   - `memoryValidationStart` / `memoryValidationResult` around `VinetasClient.validateMemory(for:)` (§5 row 8, `Vinetas.swift:315`).
   - `modelAvailabilityChecked` inside `VinetasClient.isAvailable(_:)` (§5 row 11, `Vinetas.swift:269`).
   - `modelDeleted` inside `VinetasClient.delete(_:)` (§5 row 12, `Vinetas.swift:277`).
   - `errorThrown(phase:errorDescription:)` immediately before every `throw VinetasError.…` in the file (§5 errorThrown row: `Vinetas.swift:85` and any other instance/static throws).

2. `Sources/SwiftVinetas/Engine/EngineRouter.swift`:
   - `engineSelected` after `engine(for: model)` returns successfully (§5 row 5, `EngineRouter.swift:61`).
   - `engineNotFound` inside both `throw VinetasError.engineNotFound` branches (§5 row 6, `EngineRouter.swift:63, 76`), before the throw.
   - `errorThrown(phase: .engineNotFound, ...)` immediately after `engineNotFound`, before the throw.
   - `engineFeatureNegotiated` — reserve the call site as a comment; no callers pass `feature:` today (§5 row 7).

3. `Sources/SwiftVinetas/Engine/Flux2Engine.swift`:
   - **Do NOT emit `generationStart`/`End`.** Single-emission rule — those live on `VinetasClient`.
   - `modelLoadStart` / `modelLoadComplete` around `loadModel(_:progress:)` (§5 row 9, `Flux2Engine.swift:128`).
   - `modelUnload` inside `unloadModel()` (§5 row 10, `Flux2Engine.swift:172`).
   - `concurrencyGateRejected` inside `guard !isGenerating else { throw … }` (§5 row 13, `Flux2Engine.swift:186–187`), before the throw.
   - `loraAttachStart` / `loraAttachComplete` around `loadLoRA(at:scale:)` (§5 row 14, `Flux2Engine.swift:263`).
   - `errorThrown` before every `throw VinetasError.…` enumerated in §5 (`Flux2Engine.swift:133, 187, 192, 223, 244, 265, 271, 296, 311, 326`).

4. `Sources/SwiftVinetas/Engine/PixArtEngine.swift`:
   - **Do NOT emit `generationStart`/`End`.** Single-emission rule.
   - `modelLoadStart` / `modelLoadComplete` around `loadModel(_:progress:)` (§5 row 9, verify the actual line on implement).
   - `modelUnload` inside `unloadModel()` (§5 row 10).
   - `concurrencyGateRejected` inside the `isGenerating` guard (§5 row 13, `PixArtEngine.swift:218–219`).
   - `loraAttachStart` / `loraAttachComplete` around `loadLoRA(at:scale:)` (§5 row 14, `PixArtEngine.swift:284`).
   - `errorThrown` before every `throw VinetasError.…` enumerated in §5 (`PixArtEngine.swift:135, 180, 193, 219, 224, 231, 256, 263, 286, 291, 313, 321, 332, 348, 383, 399`).

5. At each emission site in engine files, resolve the active reporter via the engine's stored reporter (set in S3). At `VinetasClient`-level emission sites, use `currentTelemetry()`.

**Exit criteria** (all machine-verifiable):
- [ ] `swift_package_build` succeeds.
- [ ] **Single-emission rule**: `grep -c "\.generationStart(\|\.generationEnd(" Sources/SwiftVinetas/Engine/Flux2Engine.swift Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns ZERO. (The previous draft demanded the opposite — inverted by the May-14 spec.)
- [ ] **Four-site generationStart**: `grep -c "\.generationStart(" Sources/SwiftVinetas/Vinetas.swift` returns at least `4`.
- [ ] **Error coverage audit**: Every `throw VinetasError.` line in `Vinetas.swift`, `Engine/EngineRouter.swift`, `Engine/Flux2Engine.swift`, `Engine/PixArtEngine.swift` is preceded within 10 lines by an `errorThrown(` emit. Verify by inline check: `paste <(grep -n "throw VinetasError" <files>) <(grep -n "errorThrown(" <files>)` shows pairing.
- [ ] **Forbidden site**: `grep -c "VinetasTelemetryEvent" Sources/SwiftVinetas/Core/VinetasModelManager.swift 2>/dev/null` returns `0` (REQUIREMENTS §1 forbids).
- [ ] **No tensor stats in this sortie**: `grep -c "TuberiaTensorStat" Sources/SwiftVinetas/Vinetas.swift Sources/SwiftVinetas/Engine/Flux2Engine.swift Sources/SwiftVinetas/Engine/PixArtEngine.swift` returns `0` (tensor stats live in Tuberia/Flux2Core/PixArtBackbone, not here).
- [ ] **No runID synthesis**: `grep -nE "UUID\(\)" Sources/SwiftVinetas/Vinetas.swift Sources/SwiftVinetas/Engine/` returns ZERO lines (the library never mints a UUID).

---

## Sortie 5: Image-understanding telemetry

**Priority**: 8 — Side-channel work; isolated from generation path. Parallelizable with S4.

**Agent role**: Sub-agent 3 (no build operations). Touches only `Sources/SwiftVinetas/Understanding/*`. No overlap with S4's file set.

**Entry criteria:**
- [ ] S3 COMPLETED. Parallelizable with S4.

**Tasks:**
1. Wire emissions in `Sources/SwiftVinetas/Understanding/ImageClassifier.swift`:
   - `classifierForwardStart(imageDims:)` immediately before `classify(...)` does its forward pass.
   - `classifierForwardComplete(topLabel:topScore:top5Labels:top5Scores:durationSeconds:)` on the success return.
   - `errorThrown(phase: .classifierForward, ...)` before any throw.
2. Wire emissions in `Sources/SwiftVinetas/Understanding/FeatureExtractor.swift`:
   - `featureExtractionStart(imageDims:)` immediately before `extract(...)` does its forward pass.
   - `featureExtractionComplete(featureDim:featureStat:durationSeconds:)` on the success return. The `featureStat: TuberiaTensorStat` is the documented exception per §5 hot-path discipline — one stat per `extract()` call.
   - `errorThrown(phase: .featureExtraction, ...)` before any throw.
3. Resolve the reporter via the actor-local `telemetry` property added in S3.

**Exit criteria** (all machine-verifiable):
- [ ] `swift_package_build` succeeds (run by supervising agent after Group C).
- [ ] `grep -c "classifierForwardStart\|classifierForwardComplete" Sources/SwiftVinetas/Understanding/ImageClassifier.swift` returns at least `2`.
- [ ] `grep -c "featureExtractionStart\|featureExtractionComplete" Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` returns at least `2`.
- [ ] `grep -c "TuberiaTensorStat" Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` returns at least `1` (the allowed per-extract stat).
- [ ] `grep -c "TuberiaTensorStat" Sources/SwiftVinetas/Understanding/ImageClassifier.swift` returns `0` (classifier carries label scores, not tensor stats).

---

## Sortie 6: Test suite

**Priority**: 5 — Verification of all prior work. Final library-side sortie.

**Agent role**: Supervising agent (must run `swift_package_test` to verify).

**Entry criteria:**
- [ ] S4 COMPLETED.
- [ ] S5 COMPLETED.

**Tasks:**

Add to `Tests/SwiftVinetasTests/`. Test names match REQUIREMENTS §7.

1. `Tests/SwiftVinetasTests/Support/MockVinetasReporter.swift` — `final class MockVinetasReporter: VinetasTelemetryReporter, @unchecked Sendable` capturing `[VinetasTelemetryEvent]` under a lock, with `func events() -> [VinetasTelemetryEvent]`. Also stub `MockDeviceCapability` used by the client-init test.

2. `VinetasTelemetryClientInitTests` — build `VinetasClient(router:)` with a mock router; attach `MockVinetasReporter` via `setTelemetry`; assert `clientInitialized` fires once and the correct `engineRegistered`/`engineSkipped` pair fires at the 16 GB and 8 GB thresholds.

3. `VinetasTelemetryPropagationTests` — call `VinetasClient.setTelemetry(reporter)`. Assert the reporter reaches `EngineRouter` (via its actor-internal state), every `ImageGenerationEngine` in the router, and `ImageClassifier` / `FeatureExtractor`. Then call `setTelemetry(nil)` and assert teardown. **This is the test §7 added in the May-14 spec tightening.**

4. `VinetasTelemetryHandoffTests` — invoke `VinetasClient.generate(prompt: "verbatim test prompt", style:, model:)` against a mock engine. Assert:
   - `generationStart` fires **exactly once** (no double-emission from the engine — this verifies the single-emission rule).
   - It carries every field of the request verbatim (prompt, dims, seed, steps, guidance, mode).
   - Followed by `generationEnd(success: true, durationSeconds: finite)`.

5. `VinetasTelemetryEngineRoutingTests` — build a router with two mock engines, request a model belonging to neither. Assert order: `engineNotFound` fires **before** the throw; `errorThrown(phase: .engineNotFound, ...)` fires immediately after.

6. `VinetasTelemetryConcurrencyTests` — two concurrent `Flux2Engine.generate(...)` calls; assert `concurrencyGateRejected` fires before the second throws and `generationEnd(success: false)` is emitted on the failing path. Repeat for `PixArtEngine`.

7. `VinetasTelemetryMemoryValidationTests` — drive `validateMemory(for:)` through mocked `DeviceCapability` to produce each of the four `MemoryVerdict` cases. Assert the correct verdict in `memoryValidationResult`.

8. `VinetasTelemetryNoopOverheadTests` — 100 `VinetasClient.generate()` calls against a mocked engine under three configs: `nil` reporter, `NoopVinetasTelemetryReporter`, and a counting reporter. Wall-clock median delta between `nil` and `Noop` within ±2%. **Gate off CI**: `try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "perf test — local only")` (host plan risk #10: flaky perf gates).

**Exit criteria** (all machine-verifiable):
- [ ] `make test-unit` (or `swift_package_test` if Makefile is unavailable) passes all seven test files on macOS arm64.
- [ ] `find Tests/SwiftVinetasTests -name "VinetasTelemetry*Tests.swift" | wc -l` returns `7`.
- [ ] `find Tests/SwiftVinetasTests/Support -name "MockVinetasReporter.swift" | wc -l` returns `1`.
- [ ] `grep -c "XCTSkipIf.*CI" Tests/SwiftVinetasTests/VinetasTelemetryNoopOverheadTests.swift` returns at least `1`.
- [ ] `VinetasTelemetryPropagationTests` is in the suite (catches the May-14 spec addition).

---

## Release sortie (post-merge, manual — not part of autonomous execution)

After the PR for `instrumentation/01` merges to `development` and then to `main`:

- [ ] Bump `VinetasClient.version` (currently appears at `Vinetas.swift:31` and `Vinetas.swift:415` — keep both in sync) from `"0.11.0-dev"` to `"0.12.0"`.
- [ ] Tag `0.12.0` on `main`.
- [ ] Create a GitHub release.
- [ ] Downstream consumers (the Vinetas host app, the `vinetas` CLI's host-wiring follow-up) pin against `from: "0.12.0"`.

Handled by `/ship-swift-library`; not orchestrated by this plan.

---

## Open Questions & Missing Documentation

### Resolved

| ID | Sortie | Issue Type | Description | Status |
|----|--------|-----------|-------------|--------|
| OQ-1 | (was S4) | runID nil-handling | What happens when `runID == nil`? | **OBSOLETE.** The spec dropped runID from SwiftVinetas events entirely. The library no longer accepts a runID parameter. The question disappears. |
| OQ-2 | (was S4) | Direct-to-engine runID synthesis | Does the adapter synthesize a UUID? | **OBSOLETE.** Same reason. Engines may synthesize their own runIDs for their own telemetry — that's their concern, not ours. |
| OQ-3 | S3 | Understanding actor ownership | Long-lived vs. on-demand `ImageClassifier`/`FeatureExtractor`? | **DEFERRED-TO-AGENT** in S3 task 3. Run the grep, decide, document in `// MARK: - Telemetry propagation`. |
| OQ-4 | S5 | Image-understanding correlation | How does the host correlate a classifier event back to a generation? | **RESOLVED-FOR-V1.** Side-channel events have no runID by design (§1). Host-side log-stitching handles correlation via temporal proximity. Future iteration item. |
| OQ-5 | S4 | PixArt throw-site enumeration | Spec previously didn't list lines. | **RESOLVED.** The May-14 spec enumerates PixArt throw sites explicitly: `PixArtEngine.swift:135, 180, 193, 219, 224, 231, 256, 263, 286, 291, 313, 321, 332, 348, 383, 399`. |
| OQ-6 | S4 | `generationEnd` failure-path fields | Where do `success`, `outputDims`, `actualSeed` come from on throw? | **DEFERRED-TO-AGENT** in S4 task 1. Standard captured-mutable-var defer idiom — `var success = false` before the work, mutate on success, defer reads them. |
| OQ-7 | (was S8) | Fixture model for E2E test | Which model is small enough for CI? | **OBSOLETE.** S8 was deleted. No E2E coherence test in this plan. |
| OQ-8 | (was S5/S6) | Parallel write conflict on `Vinetas.swift` | S5 and S6 both edited `Vinetas.swift`. | **RESOLVED-BY-RESEQUENCE.** Propagation hook moved into S3. S4 and S5 now operate on disjoint file sets. |

### Blocking Issues

None.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 6 (down from 8) |
| Critical sorties | 0 (runID-correctness risk is gone with runID itself) |
| Parallelizable pairs | S1 ‖ S2 (foundation), S4 ‖ S5 (emissions) |
| Critical path length | 4 sorties (down from 6) |
| Maximum simultaneous agents | 1 supervising + 3 sub-agents |
| Average estimated sortie size | ~18 turns (~36% of 50-turn budget) |
| Dependency structure | DAG (see graph above) |
| Cross-repo gating | Already cleared (`bf5b867` raised all four pin floors) |
| Final deliverable | One PR on `instrumentation/01` + `0.12.0` tag on `main` |

### Pass results (this re-refine)

| Pass | Verdict | Notes |
|------|---------|-------|
| 0. Spec resync | ✓ | Plan now matches REQUIREMENTS-instrumentation.md as of `6e149af`. S4 (was: runID plumbing) and S8 (was: runID coherence) deleted. OQ-1/2/7 marked obsolete. |
| 1. Atomicity & testability | ✓ | All sorties within budget. S4 still the heaviest (~25 turns) — accepted because splitting by file would re-introduce the propagation-correctness risk the seam in S3 specifically guards against. |
| 2. Prioritization | ✓ | Dependency order matches priority order. No reorder needed. |
| 3. Parallelism | ✓ | S1‖S2 and S4‖S5 verified disjoint. No file overlap. |
| 4. Open questions | ✓ | 6 of 8 resolved (4 in-plan, 2 deferred-to-agent), 2 obsolete. 0 blocking. |

**Next step**: dispatch with `/mission-supervisor start /Users/stovak/Projects/SwiftVinetas/docs/incomplete/swift-vinetas-instrumentation/EXECUTION_PLAN.md`.

After this mission ships, the follow-up work is:
- **CLI host wiring** (currently undocumented). The `vinetas` CLI (`Sources/vinetas/`, `Sources/VinetasCLICore/`) is a host of SwiftVinetas. It currently performs zero telemetry wiring. Once `0.12.0` ships, a follow-on REQUIREMENTS doc should specify: a JSONL/stderr reporter implementation for each of the 5 reporter protocols (`VinetasTelemetryReporter`, `Flux2TelemetryReporter`, `PixArtTelemetryReporter`, `TuberiaTelemetryReporter`, `AcervoTelemetryReporter`), a `--telemetry-jsonl PATH` flag on the `Generate`/`Batch`/`Preview` subcommands, and the once-per-process wiring call (`VinetasClient.shared.setTelemetry(...)` + each dep's `setTelemetry`) in the subcommand startup path.

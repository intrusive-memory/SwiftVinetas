---
feature_name: OPERATION WIRETAP DARKROOM
mission_branch: mission/wiretap-darkroom/01
starting_point_commit: 6e149af541a9c24911242328504349c0204f794f
iteration: 1
state: complete
updated: 2026-05-15
---

# EXECUTION_PLAN.md — SwiftVinetas Instrumentation

**Source requirements**: `REQUIREMENTS-instrumentation.md`
**Target release**: our next minor release version (current `0.11.0-dev`)
**Shipping unit**: Library + CLI + Integration test, one PR cycle.

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Brief

Instrument SwiftVinetas across three layers in a single shipping unit:

1. **Library** — emit `VinetasTelemetryEvent` at every cross-boundary handoff in `VinetasClient`, `EngineRouter`, `Flux2Engine`, `PixArtEngine`, `ImageClassifier`, `FeatureExtractor`.
2. **CLI host** — `--telemetry` flag on generation-producing subcommands; five host-side adapters (Vinetas + four deps) writing one interleaved JSONL trace.
3. **Integration test** — compiled XCTest harness that drives a real generation, captures the five-library trace, asserts fidelity, and doubles as `make test-telemetry-debug` for developer use.

The library is unobservable without a host; the integration test is the cheapest possible host. Bundling all three in one PR is the requirement.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|--------------|
| swift-vinetas-instrumentation | (project root) | 10 | 1–7 | none |

Single work unit per requirements §1 ("Single shipping unit") and §12 ("one mission, one PR cycle"). The Layer column on each sortie below carries the dependency gating.

---

## Sorties

### Sortie 1: VinetasTelemetryEvent

**Layer**: 1
**Parallel with**: Sortie 2
**Priority**: 27.5 — root foundation type; transitively blocks 9 sorties (S2 references it forward only by name, but every other sortie needs the concrete cases).

**Entry criteria**:
- [ ] First-layer sortie — no prerequisites.
- [ ] Current branch is the mission branch.

**Tasks**:
1. Create `Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift` with the public `VinetasTelemetryEvent` enum exactly as specified in REQUIREMENTS §4.1 (all cases, all associated values, all nested enums: `GenerationModeTag`, `MemoryVerdict`, `ErrorPhase`).
2. Import `Foundation` and `Tuberia` (for `TuberiaTensorStat`) at the top of the file.
3. Conform `VinetasTelemetryEvent` and every nested enum to `Sendable`.
4. Do NOT add a `runID` field on any case (per REQUIREMENTS §3 runID convention).

**Exit criteria**:
- [ ] `xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS,arch=arm64'` succeeds.
- [ ] File exists at `Sources/SwiftVinetas/Telemetry/VinetasTelemetryEvent.swift`.
- [ ] All nine enum cases listed in REQUIREMENTS §4.1 are present (verify by grep for `case clientInitialized`, `case generationStart`, `case generationEnd`, `case engineSelected`, `case memoryValidationStart`, `case modelLoadStart`, `case concurrencyGateRejected`, `case classifierForwardStart`, `case errorThrown`).
- [ ] Build emits zero new warnings.

---

### Sortie 2: VinetasTelemetryReporter

**Layer**: 1
**Parallel with**: Sortie 1
**Priority**: 24.5 — protocol contract; blocks S3 directly and 7 downstream sorties transitively.

**Entry criteria**:
- [ ] First-layer sortie — no prerequisites.

**Tasks**:
1. Create `Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift` with the `VinetasTelemetryReporter` protocol exactly as specified in REQUIREMENTS §4.2.
2. The protocol requires a single async method: `func capture(_ event: VinetasTelemetryEvent) async`.
3. Conform the protocol to `Sendable`.
4. Add `public struct NoopVinetasTelemetryReporter: VinetasTelemetryReporter` with a public empty initializer and a no-op `capture(_:)`.

**Exit criteria**:
- [ ] `xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS,arch=arm64'` succeeds (Sortie 1's event type may not yet exist; reference it forward by name — Swift module compilation resolves order-independently).
- [ ] File exists at `Sources/SwiftVinetas/Telemetry/VinetasTelemetryReporter.swift`.
- [ ] `NoopVinetasTelemetryReporter` builds and is reachable from outside the module.

---

### Sortie 3: Library setTelemetry seam + propagation

**Layer**: 2
**Depends on**: Sortie 1, Sortie 2.
**Priority**: 23.5 — locked-seam foundation reused by every emission sortie; risk elevated by lock + cross-actor propagation. Establishes the §5.5 ownership decision that S5 inherits.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED.
- [ ] Sortie 2 COMPLETED.
- [ ] `VinetasTelemetryEvent` and `VinetasTelemetryReporter` build successfully.

**Tasks**:
1. Add `import os.lock` and an `OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>` to `VinetasClient` in `Sources/SwiftVinetas/Vinetas.swift` per REQUIREMENTS §5.1.
2. Add `public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async` on `VinetasClient` that stores the reporter under the lock and propagates to `router`.
3. Add `internal func currentTelemetry() -> (any VinetasTelemetryReporter)?` returning the locked value.
4. Add `setTelemetry(_:)` to `EngineRouter` actor (`Sources/SwiftVinetas/EngineRouter.swift`); store privately and `await engine.setTelemetry(reporter)` on each registered engine.
5. Extend the `ImageGenerationEngine` protocol with `func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async` and provide a default no-op implementation.
6. Override `setTelemetry(_:)` in `Flux2Engine` and `PixArtEngine` to store the reporter privately (no dep-event bridging — see REQUIREMENTS §5.3).
7. Decide ownership model for `ImageClassifier` and `FeatureExtractor` (REQUIREMENTS §5.5 — long-lived vs on-demand). Document the choice in a `// MARK: - Telemetry propagation` comment block at the chosen propagation point. Wire propagation accordingly so `VinetasClient.setTelemetry` reaches both actors.

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] `grep -n "OSAllocatedUnfairLock" Sources/SwiftVinetas/Vinetas.swift` returns at least one hit.
- [ ] `grep -rn "setTelemetry" Sources/SwiftVinetas/` shows method on `VinetasClient`, `EngineRouter`, `ImageGenerationEngine`, `Flux2Engine`, `PixArtEngine`, `ImageClassifier`, `FeatureExtractor`.
- [ ] `grep -n "MARK: - Telemetry propagation" Sources/SwiftVinetas/` returns at least one hit documenting the ownership decision.
- [ ] `VinetasClient.shared.setTelemetry(NoopVinetasTelemetryReporter())` compiles in a scratch test.

---

### Sortie 4: Vinetas + Engine emission sites

**Layer**: 3
**Parallel with**: Sortie 5
**Depends on**: Sortie 3.
**Priority**: 15.0 — broadest-blast-radius emission sortie (~30+ sites across 4 files); high complexity, no downstream blocking after S8/S10 are unblocked. Single-emission rule discipline drives risk.

**Entry criteria**:
- [ ] Sortie 3 COMPLETED.
- [ ] `make build` is green.

**Tasks**:
1. Emit `clientInitialized` at the end of `VinetasClient.init()` (`Vinetas.swift:51`); emit `engineRegistered` / `engineSkipped` per engine in the registration block (`Vinetas.swift:45–48`).
2. Emit `generationStart` at the four `VinetasClient.generate` / `VinetasClient.preview` entry points (`Vinetas.swift:79, 113, 167, 226`). Disambiguate via `mode:`. Do NOT emit inside `<Engine>.generate`.
3. Emit `generationEnd` at the same four sites in both success and failure paths using the captured-mutable-var + `defer` idiom (REQUIREMENTS §6 / OQ-6).
4. Emit `engineSelected` after `router.engine(for:)` returns (`EngineRouter.swift:61`). Emit `engineNotFound` before each `throw VinetasError.engineNotFound` (`EngineRouter.swift:63, 76`).
5. Emit `memoryValidationStart` / `memoryValidationResult` pair around `validateMemory(for:)` (`Vinetas.swift:315`).
6. Emit `modelLoadStart` / `modelLoadComplete` around `engine.loadModel(_:progress:)` (`Flux2Engine.swift:128` and PixArt equivalent). Emit `modelUnload` inside each engine's `unloadModel()`. Emit `modelAvailabilityChecked` in `isAvailable(_:)` (`Vinetas.swift:269`) and `modelDeleted` in `delete(_:)` (`Vinetas.swift:277`).
7. Emit `concurrencyGateRejected` immediately before the `throw` in each engine's single-flight guard (`Flux2Engine.swift:186–187`, `PixArtEngine.swift:218–219`).
8. Emit `loraAttachStart` / `loraAttachComplete` around `loadLoRA(at:scale:)` in both engines.
9. Emit `errorThrown(phase:errorDescription:)` immediately before EVERY `throw VinetasError.…` site enumerated in REQUIREMENTS §6 (full list provided there: `EngineRouter.swift:63, 76`; `Flux2Engine.swift:133, 187, 192, 223, 244, 265, 271, 296, 311, 326`; `PixArtEngine.swift:135, 180, 193, 219, 224, 231, 256, 263, 286, 291, 313, 321, 332, 348, 383, 399`; `Vinetas.swift:85`).
10. Respect the **single-emission rule** — every event has exactly one canonical site (REQUIREMENTS §6).

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] `grep -rn "capture(.clientInitialized" Sources/SwiftVinetas/` returns exactly one match.
- [ ] `grep -rn "capture(.generationStart" Sources/SwiftVinetas/` returns exactly four matches (the four entry points).
- [ ] `grep -rn "capture(.generationEnd" Sources/SwiftVinetas/` returns exactly four matches.
- [ ] `grep -rn "capture(.concurrencyGateRejected" Sources/SwiftVinetas/` returns exactly two matches (Flux2 + PixArt).
- [ ] `grep -rn "capture(.errorThrown" Sources/SwiftVinetas/` returns a count ≥ the number of throw sites enumerated in REQUIREMENTS §6 (≥ 27).
- [ ] No `TuberiaTensorStat` invocation on a non-image-understanding path (`grep -rn "TuberiaTensorStat" Sources/SwiftVinetas/` shows hits only in `ImageClassifier`/`FeatureExtractor`-adjacent files plus the event type).

---

### Sortie 5: Image-understanding emission sites

**Layer**: 3
**Parallel with**: Sortie 4
**Depends on**: Sortie 3.
**Priority**: 10.5 — disjoint file set from S4 (ImageClassifier + FeatureExtractor only); the one documented `TuberiaTensorStat` invocation is the entire image-understanding telemetry contract.

**Entry criteria**:
- [ ] Sortie 3 COMPLETED.
- [ ] `make build` is green.

**Tasks**:
1. Emit `classifierForwardStart` / `classifierForwardComplete` around the forward pass inside `ImageClassifier.classify(...)`.
2. Emit `featureExtractionStart` / `featureExtractionComplete` around `FeatureExtractor.extract(...)`. Compute exactly one `TuberiaTensorStat` per extract (REQUIREMENTS §6 documented exception to hot-path discipline).
3. Emit `errorThrown(phase: .classifierForward, …)` and `errorThrown(phase: .featureExtraction, …)` before any throw inside these actors.
4. Confirm propagation from `VinetasClient.setTelemetry` reaches both actors (the ownership choice was made in Sortie 3); add a regression-resistance comment if the propagation path is non-obvious.

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] `grep -rn "capture(.classifierForwardStart" Sources/SwiftVinetas/` returns exactly one match; same for `classifierForwardComplete`.
- [ ] `grep -rn "capture(.featureExtractionStart" Sources/SwiftVinetas/` returns exactly one match; same for `featureExtractionComplete`.
- [ ] `grep -rn "TuberiaTensorStat" Sources/SwiftVinetas/FeatureExtractor` shows the one stat invocation.

---

### Sortie 6: TelemetryJSONLSink + envelope

**Layer**: 4
**Parallel with**: Sortie 7
**Depends on**: Sortie 1 (for `VinetasTelemetryEvent` reference only — does not need Sortie 3/4/5 to compile).
**Priority**: 11.5 — CLI-side foundation; pulls four dep imports into `VinetasCLICore` (Package.swift surface change) and establishes per-line JSONL flush contract that the integration test depends on.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED.
- [ ] `make build` is green.

**Tasks**:
1. Add the four dep imports listed in REQUIREMENTS §7.8 to the `VinetasCLICore` target in `Package.swift`: `Flux2Core`, `PixArtBackbone`, `Tuberia`, `SwiftAcervo`.
2. Create `Sources/VinetasCLICore/Telemetry/TelemetryJSONLSink.swift` exactly as specified in REQUIREMENTS §7.3: actor wrapping a `FileHandle`, ISO8601 + sortedKeys + withoutEscapingSlashes encoder, public `init(traceURL:)`, public `write<P: Encodable>(kind:payload:)`, public `close()`.
3. Define the `TelemetryEnvelope` struct (`timestamp: Date`, `kind: String`, `payload: AnyEncodable`) and the `AnyEncodable` shim. Place them adjacent to the sink or in a shared support file under `Sources/VinetasCLICore/Telemetry/`.
4. Implement `defaultTraceURL()` per REQUIREMENTS §7.5 with colons stripped from the timestamp and a cache-directory base (`~/Library/Caches/vinetas/telemetry/` on macOS; `$XDG_CACHE_HOME` fallback for Linux/CI).
5. Per-line flush behaviour: write payload then newline (`0x0A`) each call. No buffering.

**Exit criteria**:
- [ ] `make build` succeeds (CLI target now imports the four dep products).
- [ ] `grep -n "Flux2Core" Package.swift && grep -n "PixArtBackbone" Package.swift && grep -n "Tuberia" Package.swift && grep -n "SwiftAcervo" Package.swift` all return hits under the `VinetasCLICore` target.
- [ ] File `Sources/VinetasCLICore/Telemetry/TelemetryJSONLSink.swift` exists; `TelemetryJSONLSink` is an `actor`.
- [ ] Writing one envelope to a temp file then reading it back yields a single line of valid JSON containing `timestamp`, `kind`, `payload`.

---

### Sortie 7: Five event-encoding shims

**Layer**: 4
**Parallel with**: Sortie 6
**Depends on**: Sortie 1.
**Priority**: 9.5 — five mechanical Encodable wrappers; risk lives in covering every case of every dep's event enum, not in algorithmic complexity.

**Entry criteria**:
- [ ] Sortie 1 COMPLETED.
- [ ] `make build` is green.

**Tasks**:
1. Create `Sources/VinetasCLICore/Telemetry/VinetasEventEncoding.swift` — `Encodable` wrapper that flattens each `VinetasTelemetryEvent` case to `{ "case": "<discriminant>", <named fields> }`. Cover every case enumerated in REQUIREMENTS §4.1.
2. Create `Sources/VinetasCLICore/Telemetry/Flux2EventEncoding.swift` — same pattern for `Flux2TelemetryEvent` (import `Flux2Core`).
3. Create `Sources/VinetasCLICore/Telemetry/PixArtEventEncoding.swift` — same pattern for `PixArtTelemetryEvent` (import `PixArtBackbone`).
4. Create `Sources/VinetasCLICore/Telemetry/TuberiaEventEncoding.swift` — same pattern for `TuberiaTelemetryEvent` (import `Tuberia`).
5. Create `Sources/VinetasCLICore/Telemetry/AcervoEventEncoding.swift` — same pattern for `AcervoTelemetryEvent` (import `SwiftAcervo`).
6. For tensor-stat-bearing payloads (e.g. `featureStat: TuberiaTensorStat`), encode the stat's `Sendable` fields verbatim — do NOT add new fields.

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] Five files exist under `Sources/VinetasCLICore/Telemetry/*EventEncoding.swift`.
- [ ] For each library, encoding one representative case and re-decoding via `JSONSerialization` yields a dictionary containing the `case` discriminant key.
- [ ] No `Encodable` synthesis errors at build time.

---

### Sortie 8: CLI bootstrap + per-subcommand `--telemetry` flag wiring

**Layer**: 5
**Depends on**: Sortie 3, Sortie 6, Sortie 7. (Sortie 3 supplies `VinetasClient.setTelemetry`; Sorties 6 & 7 supply the sink and encoders. Sorties 4 & 5 must also have COMPLETED so the wired adapters actually see events — verify both before dispatch.)
**Priority**: 13.0 — the assembly point where library, sink, encoders, and CLI converge; resolves OQ-1 (per-dep `setTelemetry` entry-point discovery) inline; borderline-large sortie kept atomic because partial wiring is unobservable.

**Entry criteria**:
- [ ] Sortie 3 COMPLETED.
- [ ] Sortie 4 COMPLETED.
- [ ] Sortie 5 COMPLETED.
- [ ] Sortie 6 COMPLETED.
- [ ] Sortie 7 COMPLETED.
- [ ] `make build` is green.

**Tasks**:
1. Create the five adapter types per REQUIREMENTS §7.4 in `Sources/VinetasCLICore/Telemetry/`: `VinetasTelemetryCLIAdapter`, `Flux2TelemetryCLIAdapter`, `PixArtTelemetryCLIAdapter`, `TuberiaTelemetryCLIAdapter`, `AcervoTelemetryCLIAdapter`. Each conforms to its dep's reporter protocol and writes to the shared `TelemetryJSONLSink` with a fixed `kind` string.
2. Create `Sources/VinetasCLICore/Telemetry/CLITelemetryBootstrap.swift` per REQUIREMENTS §7.5: holds the sink + five adapters, exposes `static func enable(traceURL: URL? = nil) async throws -> CLITelemetryBootstrap` and `func finish() async`.
3. Inside `enable(...)`: construct the sink, construct each adapter, then call `setTelemetry(_:)` on each of the five host roots. **Resolve OQ-1**: determine the actual entry points for `Flux2Core`, `PixArtBackbone`, `Tuberia`, `SwiftAcervo` by reading each package's public API / `AGENTS.md`; replace the placeholders shown in §7.5. Document the chosen entry points in a comment.
4. `finish()`: call `setTelemetry(nil)` on all five host roots, then `await sink.close()`, then print the trace path to stderr.
5. Add `@Flag(name: .long, …) public var telemetry: Bool = false` to each of: `Generate`, `Batch`, `Preview`, `Classify`, `Features`, `Similarity` subcommands. Use the help text and discussion exactly as shown in REQUIREMENTS §7.1.
6. In each in-scope subcommand's `run()`, wrap the existing body with the `defer { Task { await bootstrap?.finish() } }` pattern from REQUIREMENTS §7.6. For `Classify`, `Features`, `Similarity`: wire only the Vinetas adapter (partial wiring — REQUIREMENTS §7.7); for `Generate`, `Batch`, `Preview`: full five-adapter wiring.
7. Add `Download`, `ListModels`, `Info`, `CharacterCommand` subcommands to the explicit out-of-scope list — do NOT add `--telemetry` to them.

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] `vinetas generate --help` shows the `--telemetry` flag with the expected discussion text.
- [ ] `vinetas batch --help`, `vinetas preview --help`, `vinetas classify --help`, `vinetas features --help`, `vinetas similarity --help` all show `--telemetry`.
- [ ] `vinetas download --help` does NOT show `--telemetry`; same for `list-models`, `info`, and any `character` subcommand.
- [ ] `CLITelemetryBootstrap.enable()` compiles with no `/* ... */` placeholder comments referencing the OQ-1 question.
- [ ] Running `vinetas generate "smoke test" --telemetry` against a missing-model error path still writes at least one envelope to the configured trace path and prints `[vinetas] Telemetry trace: …` to stderr.

---

### Sortie 9: Integration test + Makefile target

**Layer**: 6
**Depends on**: Sortie 8.
**Priority**: 4.5 — terminal-leaf sortie (no downstream blocks); high risk because it drives a real generation against on-disk models and is the canonical fidelity assertion for the whole mission.

**Entry criteria**:
- [ ] Sortie 8 COMPLETED.
- [ ] `make build` is green.
- [ ] `VINETAS_TEST_MODELS_DIR` is available on the developer machine via `make link-test-models`.

**Tasks**:
1. Create `Tests/SwiftVinetasIntegrationTests/TelemetryIntegrationTests.swift`. Confirm the integration test target name in `Package.swift` before writing (verify against `make test-integration`).
2. Implement Test A: `testEndToEndGenerationProducesCompleteTrace` per REQUIREMENTS §8.2 — bootstrap → run real `Vinetas.generate` with `model: .klein4b`, 1 step, 512×512, seed 42 → assert non-empty trace, kind set contains `vinetas`/`flux2`/`tuberia`/`acervo`, required `vinetas` cases present, `generationStart` precedes `generationEnd` and `engineSelected`, payload field round-trip for prompt/steps/seed/width/height/mode/engineID, `generationEnd.success == true`. Print the trace path at the end.
3. Implement Test B: `testGenerationFailurePathEmitsErrorThrown` — drive a deliberately failing generation (e.g. request an uncached model with downloads disabled) and assert presence of `errorThrown` with the expected `phase:` plus `generationEnd(success: false)`.
4. Implement Test C: `testPixArtEngineRoutingEmitsCorrectEvents` — same shape as Test A but `model: .pixartSigma`; assert `kinds` contains `pixart`, `engineSelected.engineID == "pixart"`, and no `concurrencyGateRejected` on happy path.
5. Implement Test D: `testConcurrentGenerationGateEmitsRejection` — two concurrent `Vinetas.generate(...)`; assert exactly one succeeds, one throws, `concurrencyGateRejected` appears, and the rejected path emits `errorThrown(phase: .generationConcurrency)`.
6. Gate every test with `XCTSkipUnless(ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil, "…")`.
7. Augment the existing `test-integration` Makefile target so it includes the new tests; add the new `test-telemetry-debug` target per REQUIREMENTS §8.3 (single-test invocation, pipes log to `/tmp/test-telemetry.log`, greps trace path).

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] File `Tests/SwiftVinetasIntegrationTests/TelemetryIntegrationTests.swift` exists and declares exactly four `func test…` methods.
- [ ] `grep -n "test-telemetry-debug" Makefile` returns a hit.
- [ ] `make test-telemetry-debug` runs to completion, prints `Telemetry integration trace: …`, and the trace file at that path is non-empty and JSONL-valid (`jq -c . < $TRACE | wc -l > 0`).
- [ ] `make test-integration` runs and all four telemetry tests pass.

---

### Sortie 10: Library unit tests + version bump

**Layer**: 7
**Parallel with**: Sortie 11 (dependency-wise; both build, so still sequential under build constraint — see Parallelism Structure below)
**Depends on**: Sortie 4, Sortie 5.
**Priority**: 3.5 — terminal-leaf; mechanical mock + 7 test files plus the version-bump capstone that ships the release.

**Entry criteria**:
- [ ] Sortie 4 COMPLETED.
- [ ] Sortie 5 COMPLETED.

**Tasks**:
1. Create the eight library test files under `Tests/SwiftVinetasTests/` per REQUIREMENTS §9.1:
   - `Support/MockVinetasReporter.swift` — `final class`, `@unchecked Sendable`, lock-guarded event buffer.
   - `VinetasTelemetryClientInitTests.swift`
   - `VinetasTelemetryPropagationTests.swift`
   - `VinetasTelemetryHandoffTests.swift`
   - `VinetasTelemetryEngineRoutingTests.swift`
   - `VinetasTelemetryConcurrencyTests.swift`
   - `VinetasTelemetryMemoryValidationTests.swift`
   - `VinetasTelemetryNoopOverheadTests.swift` — gate the perf test off CI via `XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, …)`.
2. **Bump `VinetasClient.version`** from `"0.11.0-dev"` to the next minor release version string (the version determined for this mission's target release). Also update the duplicate string at `Vinetas.swift:415`.

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] All eight library test files listed in REQUIREMENTS §9.1 exist under `Tests/SwiftVinetasTests/`.
- [ ] `grep -n "VinetasClient.version" Sources/SwiftVinetas/Vinetas.swift` shows the bumped version string at both locations (no `-dev` suffix on the release line).
- [ ] `make test-unit` passes locally on macOS arm64.
- [ ] `CI=1 make test-unit` passes — the noop-overhead test is correctly skipped.

---

### Sortie 12 (DEFERRED — late addition, post-mission, rollback candidate)

**Layer**: 8 (after all v0.12.0 work lands)
**Status**: QUEUED — not part of the original 11-sortie plan. Added post-S9 validation per user directive (2026-05-15). Will be evaluated independently after the mission completes; subject to full rollback if the architectural change proves destabilizing.

**Goal**: Resolve the two architectural mismatches that S9 validation surfaced (and that S9d documented in REQUIREMENTS §8.2's architectural notes):

1. **Flux2 doesn't use SwiftTuberia's `DiffusionPipeline`.** Today, only PixArt rides Tuberia, so `tuberia` events never fire on Flux2 generations. The original spec assumed Tuberia would be shared infrastructure.
2. **Flux2's model downloads bypass `AcervoManager`.** `Flux2ModelDownloader.download()` calls the static `Acervo.ensureAvailable()` (no reporter installed there). Only PixArt's downloads route through `AcervoManager.shared`, which is where the CLI bootstrap installs the Acervo adapter.

**Resolution options** (to be chosen at dispatch time):

| Option | Scope | Trade-off |
|--------|-------|-----------|
| A. Route Flux2 through Tuberia + AcervoManager | flux-2-swift-mlx refactor; possibly new SwiftTuberia + SwiftAcervo releases | Cleanest fit with the original mission framing; biggest blast radius. |
| B. Add a telemetry hook to the static `Acervo.ensureAvailable` path | SwiftAcervo additive change + release; small SwiftVinetas update | Resolves Flux2-acervo gap without touching Flux2. Tuberia gap remains. |
| C. Accept the architectural truth permanently | Documentation only (already done in S9d) | No code change; mission's PR ships the truthful kind-set assertions and architectural notes. Closes the loop. |

**Acceptance criteria** (whichever option is chosen): a Klein 4B generation produces traces whose kind-set extends to include the kinds the chosen option targets. Integration Test A's kind-set assertion gets widened correspondingly.

**Rollback plan**: if this sortie destabilizes Flux2 generation, revert the touching commits on a per-library basis. The mission's v0.12.0 release does NOT depend on this sortie landing — S9d's relaxed assertions plus the architectural notes are sufficient for ship.

---

### Sortie 11: CLI unit tests

**Layer**: 7
**Parallel with**: Sortie 10 (dependency-wise)
**Depends on**: Sortie 8.
**Priority**: 3.0 — terminal-leaf; eight CLI test files validating sink, bootstrap, flag parsing, and the five event encoders.

**Entry criteria**:
- [ ] Sortie 8 COMPLETED.

**Tasks**:
1. Create the eight CLI test files under the CLI test directory (verify the actual path in `Package.swift`; the requirements default is `Tests/SwiftVinetasTests/CLITests/`) per REQUIREMENTS §9.2:
   - `CLITelemetryFlagParsingTests.swift`
   - `TelemetryJSONLSinkTests.swift`
   - `CLITelemetryBootstrapTests.swift`
   - `VinetasEventEncodingTests.swift`
   - `Flux2EventEncodingTests.swift`
   - `PixArtEventEncodingTests.swift`
   - `TuberiaEventEncodingTests.swift`
   - `AcervoEventEncodingTests.swift`
2. Each encoding test must round-trip at least one representative case per dep and assert the `case` discriminant is present.

**Exit criteria**:
- [ ] `make build` succeeds.
- [ ] All eight CLI test files listed in REQUIREMENTS §9.2 exist.
- [ ] `make test-unit` passes locally on macOS arm64.
- [ ] `CI=1 make test-unit` passes.

---

## Dependency Graph

```
Layer 1 (parallel):    S1 ──┐
                       S2 ──┤
                            │
Layer 2:                    └─► S3 ──┐
                                     │
Layer 3 (parallel):                  ├─► S4 ──┐
                                     └─► S5 ──┤
                                              │
Layer 4 (parallel):    S1 ──► S6 ──┐          │
                       S1 ──► S7 ──┤          │
                                   │          │
Layer 5:                           └──────────┴─► S8 ──┐
                                                       │
Layer 6:                                               ├─► S9
                                                       │
Layer 7 (parallel):    S4,S5 ──► S10                   │
                                                       │
                                                       └─► S11
```

S6 and S7 are independent of S3–S5 for compilation, so they can start as soon as S1 is done — Layer 4 can begin in parallel with Layer 2/3 work. S10 (library tests) depends only on S4+S5 and is independent of the CLI path (S6–S8), so it can start as soon as Layer 3 finishes. S11 (CLI tests) requires S8. The Layer numbers above are dependency depth, not strict wall-clock ordering.

---

## Parallelism Structure

**Critical path**: S1 → S3 → S4 → S8 → S9 (5 sorties).

**Parallel-eligible dependency groups**:

| Group | Sorties | Notes |
|-------|---------|-------|
| Layer 1 | S1 ‖ S2 | Forward-name resolution lets these compile independently |
| Layer 3 | S4 ‖ S5 | Disjoint file sets (S4 = Vinetas + engines; S5 = ImageClassifier + FeatureExtractor) |
| Layer 4 | S6 ‖ S7 | Both depend only on S1; both create files in distinct paths under `Sources/VinetasCLICore/Telemetry/` |
| Layer 7 | S10 ‖ S11 | Library tests vs CLI tests — disjoint test directories |

### Agent allocation: **1 supervising agent, 0 sub-agents**

**Critical observation**: Every sortie in this plan has an `xcodebuild` / `make build` verification as an exit criterion. Under the build constraint (REQUIREMENTS: Metal shaders for MLX, no `swift build`/`swift test`), **all 11 sorties must run on the supervising agent**. Sub-agent fan-out is not available for this mission.

**Implication for execution**: The "parallel-eligible" groups above describe dependency-graph parallelism only — they let the supervisor pick the next ready sortie freely, but each sortie still runs sequentially on the supervising agent. There is no wall-clock speedup from fanning out.

**Build-constrained sorties (all of them)**:

| Sortie | Build verification | Agent |
|--------|-------------------|-------|
| S1, S2 | `xcodebuild build -scheme SwiftVinetas …` | Supervising |
| S3–S11 | `make build` (plus `make test-unit`, `make test-integration`, `make test-telemetry-debug`) | Supervising |

**Missed parallelism opportunities**: None addressable within the constraints of this plan. The only way to introduce sub-agent parallelism would be to relax the build verification (e.g., let S1/S2 ship without a build check, deferring verification to S3), which would weaken the testability contract. Not recommended.

---

## Open Questions & Missing Documentation

All open questions raised during requirements drafting are resolved or have documented in-sortie resolution strategies. The table below maps each OQ from REQUIREMENTS §14 to its disposition in this plan.

| OQ | Source | Disposition | Sortie |
|----|--------|-------------|--------|
| OQ-1 | Per-dep `setTelemetry` entry points | **DEFERRED-TO-AGENT** — resolved during S8 by reading each dep's `AGENTS.md` / public API. Exit criterion forbids `/* ... */` placeholder comments referencing OQ-1. | S8 |
| OQ-2 | Fire-and-forget `defer { Task { … } }` in CLI subcommand `run()` | RESOLVED in requirements (acceptable for v1). | S8 |
| OQ-3 | `ImageClassifier`/`FeatureExtractor` ownership (long-lived vs on-demand) | **DEFERRED-TO-AGENT** — resolved in S3, documented in `// MARK: - Telemetry propagation` block. S5 inherits the decision. | S3 (decide) / S5 (inherit) |
| OQ-4 | Image-understanding subcommands wiring engine adapters | RESOLVED — partial wiring only (Vinetas adapter); enforced by S8 exit criteria differentiating `Classify`/`Features`/`Similarity` from `Generate`/`Batch`/`Preview`. | S8 |
| OQ-5 | `--telemetry-path PATH` option | RESOLVED — not in v1; integration test bypasses default via `traceURL:` parameter. | (Out of scope) |
| OQ-6 | `generationEnd` failure-path field sourcing | **DEFERRED-TO-AGENT** — captured-mutable-var + `defer` idiom; resolved in S4. | S4 |
| OQ-7 | PixArt throw-site enumeration | RESOLVED — full list in REQUIREMENTS §6. | S4 |
| OQ-8 | Parallel write conflict between library S4 and S5 | RESOLVED — propagation hook folded into S3; S4 and S5 operate on disjoint file sets. | S3 / S4 / S5 |

**No blocking open questions remain.** Every DEFERRED-TO-AGENT item has:
- A specific sortie to which it is assigned,
- A documented resolution strategy (where to look, what to grep, what to write),
- A machine-verifiable exit criterion that proves the resolution shipped.

**Vague criteria audit**: All 11 sortie exit criterion sets were reviewed; no "works correctly", "properly handles", "is complete", or unnamed-test-pass criteria remain. Every exit criterion is one of: `make build` / `xcodebuild …` / `grep -n …` / `make test-unit` / `make test-integration` / `make test-telemetry-debug` / file-exists check / specific `jq` invocation / specific CLI invocation with named flag output.

**Missing documentation audit**: No sortie references a file that does not (or will not by then) exist. The integration test references `VINETAS_TEST_MODELS_DIR` which is created by `make link-test-models` (existing infrastructure per project CLAUDE.md).

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 11 |
| Layers | 7 |
| Dependency structure | Layered with parallel-eligible groups at L1, L3, L4, L7 |
| Parallel-eligible groups | S1‖S2, S4‖S5, S6‖S7, S10‖S11 (dependency-graph; sequential under build constraint) |
| Critical path | S1 → S3 → S4 → S8 → S9 (5 sorties) |
| Agent allocation | 1 supervising agent, 0 sub-agents (every sortie has a build verification) |
| Open questions blocking execution | 0 |
| DEFERRED-TO-AGENT items | 3 (OQ-1 in S8, OQ-3 in S3, OQ-6 in S4) — all with documented resolution strategies |

---

## Refinement Verdict

✓ **Plan is ready to execute.**

| Pass | Status | Changes |
|------|--------|---------|
| 1. Atomicity & Testability | ✓ PASS | 1 oversized sortie split (S10 → S10 + S11); all exit criteria machine-verifiable |
| 2. Prioritization | ✓ PASS | Priority scores annotated on all 11 sorties; layer order matches priority order, no reorder needed |
| 3. Parallelism | ✓ PASS | Critical path = 5; 4 dependency-parallel groups; explicit finding that build constraint forces single-agent sequential execution |
| 4. Open Questions & Vague Criteria | ✓ PASS | 8 OQs from REQUIREMENTS §14 each mapped to disposition; 3 DEFERRED-TO-AGENT items have in-sortie resolution strategies and verifiable exits; no vague criteria found |

**Next step**: `/mission-supervisor start EXECUTION_PLAN.md`

---

## Out of Scope (v1)

Per REQUIREMENTS §10:
- `CharacterTrainer`, `TrainingDataPreparer`, `ReferenceSheetGenerator`.
- `LoRAManager` internals (covered transitively).
- `PromptFile` / `StyleConfig` parsing telemetry.
- `VisionTransformer` internal layer events.
- `AspectRatio` parsing.
- `vinetas telemetry analyze` subcommand.
- Process-level memory snapshots.
- `--telemetry-level` filtering.
- Network sinks (OTLP, sockets).
- Telemetry on `Download`, `ListModels`, `Info`, `CharacterCommand`.
- Engine-side adapter conformance inside SwiftVinetas (deps wire directly to hosts).

---
mission: OPERATION WIRETAP DARKROOM
branch: mission/wiretap-darkroom/01
iteration: 1
starting_commit: 6e149af
final_commit: 98a8126
state: complete
updated: 2026-05-15
---

# OPERATION WIRETAP DARKROOM — Iteration 01 Brief

**Date**: 2026-05-15
**Branch**: `mission/wiretap-darkroom/01`
**Verdict**: see §8.

---

## 1. Mission Summary

OPERATION WIRETAP DARKROOM was a single-PR campaign to add end-to-end telemetry instrumentation to SwiftVinetas: event types and reporter protocol in the library, five per-library CLI adapters and a JSONL sink in the CLI layer, and a four-test XCTest integration harness that runs real generations against cached models. The mission simultaneously shipped process-wide telemetry seams in three sibling libraries (Flux2Core v3.2.1, PixArtBackbone v0.7.1, Tuberia v0.7.1) so that the CLI bootstrap could install reporters across the full dependency tree with a single call to each library's static `setReporter`. SwiftVinetas's version moved from `0.11.0-dev` to `0.12.0`. The headline result: 696 CI-passing unit tests (up from 554 pre-mission), a fully wired `--telemetry` flag on six generation subcommands, and a canonical `docs/INSTRUMENTATION_PATTERN.md` that documents the dual-seam pattern now shared across all five instrumented libraries.

---

## 2. Scope vs. Delivery

### Original 11 sorties

| Sortie | Delivered | Notes |
|--------|-----------|-------|
| S1 — VinetasTelemetryEvent | Clean | All 23 cases including the 9 required; all nested enums; Sendable throughout. |
| S2 — VinetasTelemetryReporter | Clean | Protocol, Noop implementation, public init. |
| S3 — setTelemetry seam + propagation | Clean | OQ-3 resolved: classifier/extractor are `.shared` singletons; OSAllocatedUnfairLock in place; MARK block documents the ownership decision. |
| S4 — Vinetas + Engine emission sites | Clean | All five emission-count exit criteria passed (1/4/4/2/34). OQ-6 resolved with captured-mutable-var + defer + fire-and-forget Task pattern. |
| S5 — Image-understanding emissions | Clean | 4/4/4/4 counts; one TuberiaTensorStat per extract; 8 errorThrown added. Disjoint file set from S4. |
| S6 — TelemetryJSONLSink + envelope | Clean | Public actor sink, ISO8601+sortedKeys+withoutEscapingSlashes encoder, AnyEncodable shim, four dep imports on VinetasCLICore. |
| S7 — Five event-encoding shims | Clean | 80 cases across five Encodable wrappers, all hand-rolled, no @unknown default escape hatch needed. |
| S8 — CLI bootstrap + `--telemetry` wiring | Partial on first attempt, completed via S8b | Initial delivery wired Vinetas + Acervo fully; Flux2 only via static weight-loader path; PixArt and Tuberia unwired (instance-bound APIs not reachable from the CLI). Escalated; S8b added after sibling-library process-wide seams landed. |
| S9 — Integration test + Makefile target | Partial on first attempt, completed via S9b/S9c/S9d | Tests B/C passed immediately; Tests A/D required Klein 4B via the Acervo slug directory layout (S9b fix), a canonical `isModelAvailable` API (S9c), and an event-ordering bug fix plus Test A scope relaxation (S9d). |
| S10 — Library unit tests + version bump | Clean | 8 library test files; version 0.11.0-dev → 0.12.0; 554 tests passing at this point. |
| S11 — CLI unit tests | Clean | 8 CLI test files; +142 tests bringing total to 696. |

### Inline additions (mid-flight)

**S8b — Bootstrap full seam wiring**: Added after OQ-1 escalation revealed that Flux2, PixArt, and Tuberia expose only instance-bound reporters reachable exclusively via process-wide static seams that did not yet exist. Three sibling-library sortie agents implemented the process-wide seams, then S8b updated `CLITelemetryBootstrap` to call `Flux2Telemetry.setReporter`, `PixArtTelemetry.setReporter`, and `TuberiaTelemetry.setReporter`. This addition was architectural necessity, not scope creep — the original spec listed OQ-1 as "DEFERRED-TO-AGENT" and the resolution required work the agent could not do unilaterally.

**S9b — SwiftAcervo path-pattern alignment**: Integration Test A could not locate Klein 4B weights because `isComponentReady` path resolution did not match SwiftAcervo's actual slug-based directory layout. This fix aligned the path pattern with SwiftAcervo's and VoxAlta's conventions. Flagged that Flux2 components are not registered with `AcervoManager.shared.ComponentRegistry` (PixArt does this in `loadModel`; Flux2 should but does not). Deferred as a follow-up item.

**S9c — Consolidate isAvailable API**: Added after S9b surfaced two divergent `isAvailable` overloads and a `ModelDescriptor.id` slug-vs-HF-repo mismatch that prevented a single canonical entry point. Delivered `isModelAvailable(_ modelId: String)` and deprecated the two typed overloads with `renamed:` annotations. The descriptor-typed overload still routes engine-locally for correctness; closing the gap requires adding `var modelId: String { get }` to the `ModelDescriptor` protocol (flagged for follow-up).

**S9d — Ordering fix + Test A scope relaxation + REQUIREMENTS §8.5**: Integration Test A revealed that `engineSelected` was being emitted inside `EngineRouter.engine(for:)` rather than in `VinetasClient.generate()` after `generationStart`. This violated the spec's ordering assertion. S9d moved the emission to the correct site, relaxed Test A's kind-set assertions from `{vinetas, flux2, tuberia, acervo}` to `{vinetas, flux2}` (the architectural truth), and added REQUIREMENTS §8.5 documenting the Tuberia-is-PixArt-only and Flux2-bypasses-AcervoManager facts. Also documented the xcodebuild sandbox restriction on Group Containers in a MARK block in `TelemetryIntegrationTests.swift`.

### Deferred items

**S12 — Resolve Flux2 architectural mismatches (Tuberia + Acervo)**: Queued, not dispatched. Three resolution options (A: route Flux2 through Tuberia + AcervoManager; B: add telemetry hook to the static Acervo path; C: accept the architectural truth permanently, documentation only) are documented in `EXECUTION_PLAN.md`. The mission's v0.12.0 release does NOT depend on S12. All integration tests assert what is actually true as of v0.12.0.

### Sibling-library work

Three external releases landed as prerequisites for S8b's full bootstrap wiring:

- **Flux2Core v3.2.1** — added `public enum Flux2Telemetry` with `OSAllocatedUnfairLock`-backed `setReporter`/`current` process-wide seam.
- **PixArtBackbone v0.7.1** — same pattern; CI flaky-test fix also landed during ship (cross-test contamination on a process-wide reporter count assertion; core invariant preserved).
- **Tuberia v0.7.1** — same pattern; note that a force-push to `development` was required to recover from a mid-flight merge ordering issue on the Tuberia ship. Functionally clean.

SwiftAcervo remained at v0.13.0 — its process-wide seam was already in place.

---

## 3. Sortie Accuracy Assessment

**Model selection — planned sorties**: The two foundation sorties (S1, S2) used sonnet and completed in one attempt with scores of 9 and 12 respectively — appropriate for mechanical-spec work. S3 (cross-actor lock + propagation, OQ-3) and S4 (30+ emission sites, OQ-6) both used opus, both completed in one attempt; these were the correct overrides. S5 (disjoint ImageClassifier/FeatureExtractor file set, straightforward after S3 decided ownership) used sonnet and completed cleanly — the downgrade was justified. S6 and S7 (sink + five encoders) used sonnet; both clean. S8 used opus at score 25 — justified given OQ-1's open-endedness and the convergence-point complexity, and the first attempt delivered partial correctness that was honestly escalated rather than silently cutting corners. S10 and S11 used sonnet for the terminal test-writing sorties; both clean. Overhead scores were well-calibrated throughout.

**Model selection — inline additions**: S8b was a targeted continuation of S8's OQ-1 resolution after sibling library work completed. S9b and S9c were debugging sorties (path resolution and API consolidation) where sonnet sufficed for finding and applying targeted fixes. S9d involved a genuine logic bug (event ordering at the wrong call site) plus documentation writing — sonnet was used and managed it in one attempt. The inline additions accurately reveal that the original plan slightly underestimated the integration complexity at Test A (Flux2/Klein 4B path resolution, Acervo component registry, event ordering) but overestimated nothing. No mid-flight scope was added by user preference; every addition was driven by a concrete failure during validation.

---

## 4. Architectural Findings

**Tuberia is PixArt-only**: The original specification (REQUIREMENTS §8.2, Test A) assumed a five-library trace `{vinetas, flux2, pixart, tuberia, acervo}` would be possible for any generation. The actual architecture: `TuberiaTelemetryEvent` events fire from `SwiftTuberia`'s `DiffusionPipeline`, which is instantiated exclusively by `PixArtEngine`. Flux2 has an independent pipeline and emits `Flux2TelemetryEvent` directly through `Flux2Core`. A Klein 4B (Flux2) generation produces `{vinetas, flux2}` only; a PixArt generation produces `{vinetas, pixart, tuberia}`. This is now documented in REQUIREMENTS §8.5.1 and correctly reflected in the integration tests.

**Flux2 bypasses AcervoManager**: `Flux2ModelDownloader.download()` calls the static `Acervo.ensureAvailable(...)` directly. `CLITelemetryBootstrap` installs the `AcervoTelemetryCLIAdapter` on `AcervoManager.shared`, which is not the code path Flux2's downloader exercises. Only PixArt's download flow routes through `AcervoManager.shared`, so `acervo` events appear in PixArt traces but not in Flux2 traces on a warm-cache run. Documented in REQUIREMENTS §8.5.2.

**The `engineSelected` ordering bug**: `engineSelected` was being emitted inside `EngineRouter.engine(for:)` — that is, inside the router actor, before control returned to `VinetasClient.generate()`. The ordering assertion in Test A (`generationStart < engineSelected`) was therefore failing because both events could appear in either order depending on scheduler interleaving. S9d moved the emission to `VinetasClient.generate()` immediately after `router.engine(for:)` returns, making it strictly post-`generationStart`. This was a real logic bug, not a test spec issue.

**xcodebuild sandbox restriction on Group Containers**: `xcodebuild test` (via `make test-integration`) cannot open files inside `~/Library/Group Containers/...` because the test runner subprocess lacks the `com.apple.security.application-groups` entitlement. The existing `make link-test-models` hardlink workaround (an entitled shell process performs the hardlink into `/tmp`) is the correct resolution. This is documented in `TelemetryIntegrationTests.swift`'s `// MARK: - xcodebuild sandbox investigation` block and is harmless on CI (where no models are cached at all).

**Flux2 not registered with AcervoManager.ComponentRegistry**: PixArt calls `AcervoManager.shared.register(component:)` in its `loadModel` implementation, which is how the Acervo telemetry adapter receives component-ready events. Flux2 does not do this. Flagged by S9b as a follow-up item; not a blocker for v0.12.0.

**`VINETAS_TEST_MODELS_DIR` is a skip gate, not a path override**: The environment variable functions as an `XCTSkipUnless` gate — if it is not set, all integration tests skip cleanly. However it does not actually override the model search path inside the test body. The real path override is the hardlink from `make link-test-models` writing to the path that Acervo's slug resolution expects. This distinction matters for any future work that wants to point the tests at a different model cache; the current gating variable would need to be wired to an actual path injection to accomplish that.

---

## 5. Lessons Learned

- **Verify cross-library architectural assumptions before writing integration tests against them.** The five-library trace assumption in §8.2 was plausible given the requirements' stated dependencies but incorrect. Had Test A's kind-set assertion been validated against a real Klein 4B trace before the sortie was dispatched, S9b/S9c/S9d might have been unnecessary or at least scoped tighter.

- **Process-wide telemetry seams (the dual-seam pattern) require coordinated changes across library + host; they cannot be done host-side alone.** OQ-1's escalation and the sibling-library parallel work were structurally unavoidable. The plan correctly identified OQ-1 as a DEFERRED-TO-AGENT risk; the plan could have additionally identified that if the sibling libraries lacked process-wide seams, the mission would need to ship them first. This is a refinement checklist item for future cross-library instrumentation missions.

- **The `defer { Task { await ... } }` fire-and-forget pattern for async teardown introduces test scheduler-drain requirements.** Counting tests that assert on event totals must drain the cooperative scheduler before asserting. The correct idiom is `await Task.yield()` (typically twice) — not `sleep`, not `DispatchSemaphore`. Five test files use this correctly; the pattern is documented in `TEST_CLEANUP_REPORT.md`.

- **Force-pushing a library's `development` branch to recover from a mid-flight release-PR merge ordering issue is functional but leaves a confusing history.** The Tuberia ship required this. A cleaner procedure would be: (1) always merge release PRs with a merge commit rather than squash, so the history is auditable, and (2) if a force-push is needed, note it in the SUPERVISOR_STATE decisions log with the reason.

- **The Acervo slug-directory layout is a cross-library convention that SwiftVinetas code must respect.** S9b's fix aligned `isComponentReady` path resolution with the SwiftAcervo / VoxAlta pattern. Future work that touches model discovery should read SwiftAcervo's path conventions first.

- **CI flaky tests in sibling libraries can surface during a ship even when the test was unrelated to the mission's changes.** The PixArt ship required a fix for a cross-test contamination on a process-wide reporter count assertion. This was not introduced by OPERATION WIRETAP DARKROOM's changes but was exposed by them. The fix preserved the core invariant and landed cleanly.

---

## 6. Test Cleanup Outcome

The test-cleanup agent audited all 20 new test files added during the mission (7 library tests, 4 integration tests including support infrastructure, and 11 CLI tests) and found zero tests requiring prune or flagging. All 696 tests pass under both `make test-unit` and `CI=1 make test-unit`. No hardcoded absolute paths, unmocked network calls, sleep-based timing, unseeded randomness, or Date races were found. The integration tests in `TelemetryIntegrationTests.swift` gate correctly on `VINETAS_TEST_MODELS_DIR` via `XCTSkipUnless` — on CI machines where this variable is absent, all four tests skip cleanly and do not fail the build. The performance tests in `VinetasTelemetryNoopOverheadTests` gate on the `CI` environment variable using the `withKnownIssue` Swift Testing pattern, which records the skipped state without failing the build. The `Task.yield()` scheduler-drain idiom used in five test files is deterministic and CI-appropriate.

---

## 7. Deferred Follow-Ups

**S12 — Flux2 architectural alignment (Tuberia + Acervo)**: Resolve the two gaps documented in REQUIREMENTS §8.5 — Flux2 does not use Tuberia's `DiffusionPipeline`, and Flux2's download path bypasses `AcervoManager`. Three options (A: route Flux2 through Tuberia + AcervoManager; B: add telemetry hook to the static Acervo path; C: accept the truth permanently) are detailed in `EXECUTION_PLAN.md` §Sortie 12. Estimated scope: Option A is a cross-library refactor touching flux-2-swift-mlx and potentially SwiftTuberia + SwiftAcervo (large); Option B is a SwiftAcervo additive change + release (medium); Option C is documentation only (trivial, already partially done by S9d). Look at: `EXECUTION_PLAN.md` §Sortie 12 for the decision matrix.

**Flux2 component registration with AcervoManager.ComponentRegistry**: `Flux2Engine.loadModel` should call `AcervoManager.shared.register(component:)` analogously to what `PixArtEngine.loadModel` does, so Acervo telemetry events fire on Flux2 model loads. Flagged by S9b. Look at: `Sources/SwiftVinetas/Flux2Engine.swift` `loadModel` method vs. `Sources/SwiftVinetas/PixArtEngine.swift` `loadModel` for the pattern to mirror. Estimated scope: small, contained to one method in Flux2Engine.

**`VINETAS_TEST_MODELS_DIR` dead-code cleanup or real path injection**: The environment variable currently functions as a skip gate only. If integration tests should ever be runnable against a custom model cache (not the hardlinked `/tmp` directory), the variable would need to be plumbed into Acervo's path resolution. Look at: `Tests/SwiftVinetasIntegrationTests/TelemetryIntegrationTests.swift` and the `make link-test-models` Makefile target. Estimated scope: small to medium depending on whether Acervo exposes a path override API.

**`ModelDescriptor.id` slug-vs-HF-repo discrepancy**: `ModelDescriptor.id` is a short slug (e.g. `"klein4b"`) rather than a HuggingFace repository string. This prevented `isModelAvailable(_:)` from accepting a `ModelDescriptor` directly and routing to the same code path as the string-based variant. Adding `var modelId: String { get }` to the `ModelDescriptor` protocol (or an equivalent canonical ID accessor) would close this gap and allow the deprecated typed `isAvailable` overloads to be removed entirely. Look at: `Sources/SwiftVinetas/ModelDescriptor.swift` and `Sources/SwiftVinetas/Vinetas.swift` around the `isModelAvailable` implementation added in S9c (commit `a2af4a5`). Flagged by S9c. Estimated scope: small.

---

## 8. Rollback Verdict

The shipped work stands on its own without S12. REQUIREMENTS §8.5 documents the architectural truth as of v0.12.0, and every integration test asserts that truth rather than the originally assumed five-library trace. There is no gap between what the tests claim and what the code actually does. S12 is explicitly labelled QUEUED and not part of the v0.12.0 release; its absence does not leave the library in an inconsistent state.

No landed commit should be reverted. The `engineSelected` ordering fix in S9d corrected a real bug (emission at the wrong call site); the S9b Acervo path alignment corrected a path resolution error; the S9c API consolidation removed duplication and added deprecation annotations with `renamed:` guidance. All three are improvements that should stay. The sibling library releases (Flux2Core v3.2.1, PixArtBackbone v0.7.1, Tuberia v0.7.1) are live and adopted by the Package.swift floor bumps in commit `958d2a7` — rolling them back would break the bootstrap wiring.

The mission's v0.12.0 state is internally consistent. 696 tests pass under both local and CI conditions. The library layer emits events at canonical single-emission sites. The CLI layer installs all five adapters via the dual-seam bootstrap. The integration test layer proves the chain works end-to-end for both Flux2 and PixArt generations. The three sibling library releases carry coherent process-wide seams that the pattern document describes. The version string at both locations in `Vinetas.swift` reads `"0.12.0"` with no `-dev` suffix.

**Verdict: KEEP**

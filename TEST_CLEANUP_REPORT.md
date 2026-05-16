---
mission: OPERATION WIRETAP DARKROOM
branch: mission/wiretap-darkroom/01
baseline_commit: 6e149af
cleanup_date: 2026-05-15
---

# TEST_CLEANUP_REPORT — OPERATION WIRETAP DARKROOM

## Summary

| Metric | Count |
|--------|-------|
| New test files added in mission | 20 |
| Existing test files modified | 0 |
| Tests in suite before mission | ~628 (estimated baseline) |
| Tests in suite after mission | 696 |
| Tests pruned | **0** |
| Tests flagged for user review | **0** |

All 696 unit tests pass under both `make test-unit` and `CI=1 make test-unit`. No CI-failure patterns were found requiring deletion. No files required modification.

---

## Per-File Findings

### Category key
- (a) Hardcoded absolute paths  
- (b) Unmocked network calls  
- (c) Sleep-based timing  
- (d) Unseeded randomness  
- (e) Date/time races  
- (f) Local-env-only dependencies without clean skip  
- (g) Performance tests not gated off CI

---

### S10 — Library Telemetry Unit Tests

#### `Tests/SwiftVinetasTests/VinetasTelemetryClientInitTests.swift`
**Status: KEEP**
- (a) No hardcoded paths.
- (b) No network calls.
- (c) No sleep.
- (d) No unseeded randomness.
- (e) No `Date()` usage.
- (f) No env-gated logic.
- (g) No `measure { }` blocks.

#### `Tests/SwiftVinetasTests/VinetasTelemetryConcurrencyTests.swift`
**Status: KEEP**
- (a–e) Clean.
- (f) No env-gating; tests use a purpose-built `ConcurrencyGateMockEngine` actor that simulates concurrency without GPU or model loading. CI-safe.
- (g) No measure blocks.
- Infrastructure note: Uses `Task.yield()` (×2) to drain fire-and-forget defer Tasks before asserting event counts. This is the correct scheduler-drain idiom for Swift concurrency tests and is not a timing race — it cooperatively advances the scheduler within the same async context.

#### `Tests/SwiftVinetasTests/VinetasTelemetryEngineRoutingTests.swift`
**Status: KEEP**
- (a–g) All clean. Pure mock-based routing tests with no external dependencies.

#### `Tests/SwiftVinetasTests/VinetasTelemetryHandoffTests.swift`
**Status: KEEP**
- (a–g) All clean. Uses MockEngine and failure-path generation to avoid GPU. `Task.yield()` used appropriately to drain deferred generationEnd Tasks.

#### `Tests/SwiftVinetasTests/VinetasTelemetryMemoryValidationTests.swift`
**Status: KEEP**
- (a–g) All clean. `available > 0` assertion reflects live system memory but is not a race condition — system RAM is non-zero by definition on any machine that can run tests.

#### `Tests/SwiftVinetasTests/VinetasTelemetryNoopOverheadTests.swift`
**Status: KEEP — with informational note**
- (a–e) Clean.
- (f) Uses `ProcessInfo.processInfo.environment["CI"] != nil` gate correctly. When `CI` is set, tests enter `guard !isCI else { withKnownIssue { Issue.record(...) }; return }`. This uses the `withKnownIssue` Swift Testing pattern, which records a known issue without failing the build. This is the correct pattern per project policy.
- (g) No `measure { }` blocks; custom wall-clock measurement via `ContinuousClock`.
- Informational flag (NOT a prune target): The 5× ratio threshold in `noopReporterOverheadIsNegligible` and the sub-millisecond threshold in `perEmissionCostIsSubMillisecond` are both CI-gated — neither executes on CI runners. On local machines with Apple Silicon, these thresholds are very conservative and should not flake. No action needed.
- The third test (`skipGateIsCorrectlyConditioned`) always passes in all environments and is a documentation/contract test — intentional.

#### `Tests/SwiftVinetasTests/VinetasTelemetryPropagationTests.swift`
**Status: KEEP**
- (a–g) All clean. `Task.yield()` (×2) used in `reporterSwapPropagatesNewReporter` to drain fire-and-forget defer Tasks before capturing `firstCount`. Documented in the test comment. Correct pattern.

---

### S9 — Integration Tests

#### `Tests/SwiftVinetasTests/TelemetryIntegrationTests.swift`
**Status: KEEP — intentionally excluded from prune scope per assignment**
- (a) `~/Library/Group Containers/...` appears in a block comment (lines 10–35) documenting the xcodebuild sandbox investigation. No code references this path. Not a CI-failure pattern.
- (b–e) Clean.
- (f) All 4 test methods gate on `ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil` via `try XCTSkipUnless(...)`. This is the correct skip mechanism — CI does not set this var, so all 4 tests skip cleanly. Local machines with `make link-test-models` can run them.
- (g) No measure blocks.
- The xcodebuild sandbox issue (documented in `// MARK: - xcodebuild sandbox investigation`) is a known-and-documented concern, not a CI-failure pattern. The `make link-test-models` hardlink workaround is the official resolution.

#### `Tests/SwiftVinetasTests/Support/MockVinetasReporter.swift`
**Status: KEEP** — Test infrastructure (not a test suite). No CI-failure patterns. Thread-safe event collection via `NSLock`.

---

### S11 — CLI Unit Tests

#### `Tests/SwiftVinetasTests/CLITests/AcervoEventEncodingTests.swift`
**Status: KEEP**
- (b) URL strings (`https://cdn.example.com/...`) appear exclusively in struct initializer arguments and `#expect` assertion strings — fixture data, not network calls. `URLSession`/`URLRequest` are absent. Clean.
- (a, c–g) Clean.

#### `Tests/SwiftVinetasTests/CLITests/CLITelemetryBootstrapSmokeTest.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/CLITelemetryBootstrapTests.swift`
**Status: KEEP**
- Uses `FileManager.default.temporaryDirectory` for trace file URLs — acceptable (resolves to `/var/folders/...` or `/tmp`). All trace URLs have `defer { try? FileManager.default.removeItem(at: url) }` teardown blocks. No hardcoded paths, no network, no sleep.
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/CLITelemetryFlagParsingTests.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/EventEncodingSmokeTest.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/Flux2EventEncodingTests.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/PixArtEventEncodingTests.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/TelemetryJSONLSinkSmokeTest.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/TelemetryJSONLSinkTests.swift`
**Status: KEEP**
- Uses `FileManager.default.temporaryDirectory` — acceptable. Proper teardown via `defer`.
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/TuberiaEventEncodingTests.swift`
**Status: KEEP**
- (a–g) All clean.

#### `Tests/SwiftVinetasTests/CLITests/VinetasEventEncodingTests.swift`
**Status: KEEP**
- (a–g) All clean.

---

## Test Infrastructure Findings

**`Task.yield()` usage:** Five test files (`VinetasTelemetryPropagationTests`, `VinetasTelemetryHandoffTests`, `VinetasTelemetryConcurrencyTests`, and indirectly via `VinetasTelemetryEngineRoutingTests`) use `await Task.yield()` (typically ×2) to drain fire-and-forget `defer { Task { await reporter?.capture(.generationEnd) } }` closures before asserting event counts. This is a well-understood Swift concurrency pattern for draining cooperative scheduler queues in tests. It is not a timing race — it is a deterministic cooperative yield. The pattern is sound and CI-safe.

**`withKnownIssue` usage:** `VinetasTelemetryNoopOverheadTests` uses `withKnownIssue { Issue.record(...) }` inside a CI guard. This records the skipped state without causing build failure. Per project policy, this is the approved pattern for performance-test CI gates.

**Concurrency test robustness:** `VinetasTelemetryConcurrencyTests` guards `concurrencyGateRejectedPrecedesError` and `rejectedConcurrentGenerateEmitsFailureEnd` against the case where Swift's scheduler does not interleave the two Tasks (sequential execution). These guards return early or skip the assertion — they do not fail. This is defensive and CI-appropriate.

---

## Build and Test Results

| Target | Result |
|--------|--------|
| `make build` | **SUCCEEDED** |
| `make test-unit` | **696 tests passed** |
| `CI=1 make test-unit` | **696 tests passed** |

---

## Verdict

**Zero tests pruned. Zero tests flagged for deletion.** The mission's test suite is CI-clean as delivered. All env-gated tests use correct skip mechanisms (`XCTSkipUnless`, `withKnownIssue`). No hardcoded paths, network calls, sleep-based timing, unseeded randomness, or Date races were found in any mission-added test file.

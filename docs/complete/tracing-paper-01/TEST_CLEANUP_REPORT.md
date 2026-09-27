---
type: test-cleanup-report
state: completed
mission: tracing-paper-01
updated: 2026-09-27
---

# Test Cleanup Report — OPERATION TRACING PAPER

Scope: the 19 test files listed for this sortie, diffed against `3863974..HEAD`
(only mission-added/changed code was evaluated — pre-mission code in
modified files was left alone). `Tests/SwiftVinetasTests/MockEngine.swift`
is a test double and was not touched.

## Removed

None. No test in scope matched a high-confidence CI-failure pattern
(hardcoded local paths, unmocked network, local-only services, unmet
env-var gates, unisolated `~/Library`/`~/.config` writes, sub-100ms sleep
timing, unfrozen `Date()` assertions, unordered-collection-order
assertions, unseeded randomness, already-flaky skips, empty tests, or
duplicates).

Every mission-added test routes through the `CLIEnvironment` seam to a
`MockEngine` (no real router/network), uses
`FileManager.default.temporaryDirectory` + `UUID()` for isolated scratch
space with `defer`-based cleanup, and captures stdio through the
lock-guarded `StdioCapture`/`CLIEnvironment.stderrDescriptor` seam rather
than raw `dup2` on fd 2 — exactly the pattern the mission's own comments
say was hardened against the fd-2 race. No deletions or commit were made.

## Flagged for Review

| File:test | Concern | Recommended action |
|---|---|---|
| `Tests/SwiftVinetasTests/InfoPrintIODirTests.swift` — all 4 tests (`resolvesAndCreatesDirectory`, `sitsAlongsideSharedModels`, `idempotent`, `commandPrintsPathAlone`) | Borderline pattern 5 (user-profile path without isolation), not high-confidence delete. All four are gated `.enabled(if: Acervo.resolvedSharedModelsDirectory != nil)`. On CI, `make test-unit` (and the `tests.yml` job) export `ACERVO_APP_GROUP_ID=group.intrusive-memory.models`. `Acervo.resolvedAppGroupIdentifier` reads that env var directly (no entitlement needed), and on an unsandboxed macOS process `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil`, so `Acervo+PathResolution.swift` falls back to `~/Library/Group Containers/<group-id>/SharedModels` under the runner's real home directory — so the gate resolves **true** on CI, not just on developer machines. `Info.resolveIODirectory()` then does a real `createDirectory(withIntermediateDirectories: true)` into that runner-home path (sibling `vinetas-io`, not inside a test-scoped temp dir). Verified locally: this run's log shows the suite executing for real and creating that directory (`Info --print-io-dir` suite passed, `resolveIODirectory returns a path ending in /vinetas-io and creates it` passed) rather than being skipped. This will very likely keep *passing* in CI (an ephemeral runner's own user owns its home directory, so the `mkdir -p` has no permission obstacle) — so it is not a high-confidence CI failure — but it is a real, non-isolated write into the runner's user profile, shared state that isn't scoped per-test, and it silently depends on macOS's unsandboxed-process fallback path continuing to resolve instead of failing closed. | Leave running for now (it is not currently breaking CI), but consider adding a dependency-injectable root to `Info.resolveIODirectory(fileManager:)` (it already takes an injected `FileManager`) so tests can point it at an isolated temp directory instead of the real App Group path, the way `CharacterManager(baseDirectory:)` does elsewhere in this mission's other new tests. |
| `Tests/SwiftVinetasTests/ReferenceImageTests.swift` — `decodesHEIC` | Conditional skip: `.enabled(if: ReferenceImageTests.heicEncoderAvailable, "no HEIC encoder on this runner")`. Checked and confirmed CI-safe — it's a real capability probe (`CGImageDestinationCopyTypeIdentifiers()` contains `"public.heic"`) with a documented skip reason, not an unconditional or environment-var-based skip; a runner without the encoder skips cleanly instead of failing. | No action needed; informational only. |

## Build Verification

Ran `make test-unit` (xcodebuild, scheme `SwiftVinetas-Package`,
`-only-testing:SwiftVinetasTests`) with no changes made to the test suite:

```
Test run with 874 tests in 101 suites passed after 0.399 seconds with 4 known issues.
** TEST SUCCEEDED **
```

The 4 "known issues" are pre-existing, out-of-scope `skip-on-absent`
guards in `VisionActorManifestTests.swift` (unpublished vision-model
manifests), unrelated to this mission's test files.

No deletions were made, so no commit was created.

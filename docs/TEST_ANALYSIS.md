---
type: doc
---

# Test Analysis Report

**Repository**: SwiftVinetas
**Branch**: `fix/test-audit-findings` (off `feature/cli-pro-entitlement-gate`)
**Date**: 2026-07-26
**Test scheme**: `SwiftVinetas-Package` — `make test-unit` (`-only-testing:SwiftVinetasTests`)
**Tests considered**: 69 files, ~95 suites, ~938 test functions across `SwiftVinetasTests` (58 files) and `SwiftVinetasGPUTests` (11 files)

## Executive summary

| Pass | Findings | Highest priority item |
|------|----------|------------------------|
| 1. High-repetition tests | 1 | Duplicate LoRA-compatibility test in one file |
| 2. Superfluous tests | 2 | 4 tests asserting a **re-implementation** of production logic |
| 3. Coverage gaps | 13 files | `StoryboardCommand.swift` at **0%** — shipping in PR #61 |
| 4. Flaky-in-CI predictions | 0 | No findings |
| 5. Performance gating | 0 | GPU/timeLimit suites correctly excluded from the unit lane |

This suite is in noticeably better shape than its size suggests. Passes 4 and 5 are **empty**: no real-time sleeps used as barriers, no wall-clock assertions, no network in correctness tests, no shared mutable state, and the long-running GPU work (timeLimits up to 45 minutes) is cleanly separated into `SwiftVinetasGPUTests`, which `make test-unit` excludes via `-only-testing:SwiftVinetasTests`.

The problems are all in the *value* of certain tests rather than their reliability. The worst is a suite that tests a copy of the code instead of the code. The most consequential is coverage: `StoryboardCommand.swift` — the feature being shipped in PR #61 — had **zero** line coverage, and writing the missing tests immediately surfaced a real bug.

Unlike the sibling Vinetas repo, coverage **works here**, so Pass 3 has real numbers.

> `make lint` (`swift format -i -r .`) was run first per the audit procedure. It made **no changes** — the tree was already formatted. The 8 files showing as modified are a pre-existing, uncommitted work-in-progress deleting `VinetasModel.estimatedSecondsPerImage`; not mine, left untouched.

---

## Pass 1 — High-repetition tests

### Copy-paste patterns

- `Tests/SwiftVinetasTests/LoRACompatibilityTests.swift:12` and `:257` — two tests both titled *"LoRA with matching engine is compatible"* (`loraWithMatchingEngineIsCompatible`, `matchingEngineLoRAIsCompatible`), asserting the same thing about the same input. See Pass 2 — the second is the worse of the two and has been rewritten.
  - **Action**: taken. Consolidated into tests that call the production API.

### High-iteration loops

**No findings.** `ImageNetLabelsTests.swift:70` loops `0..<1000`, but ImageNet-1K genuinely has 1000 classes and the test asserts each label is non-empty. That is coverage of a real invariant, not a stress loop.

### False positive, recorded so it is not re-flagged

`CLIArgumentTests.swift:35` and `:83` share the title *"--model klein9b sets model to klein9b"*, but they live in different suites and parse different subcommands (`Generate` vs `Batch`). Legitimate; only the display title is ambiguous.

---

## Pass 2 — Superfluous tests

### 1. Tests that assert against a re-implementation — **the significant finding**

`Tests/SwiftVinetasTests/LoRACompatibilityTests.swift` — 20 tests, of which **4 inlined the compatibility rule and asserted against their own copy**:

```swift
// Simulate the isLoRACompatible logic from VinetasClient:
let compatible: Bool
if lora.compatibleEngines.isEmpty { compatible = true }
else { compatible = lora.compatibleEngines.contains(engineID) }
#expect(compatible == true)
```

The comment at `:245` was explicit about it. The cause: `Vinetas.isLoRACompatible(lora:engineID:)` was **`private`** (`Sources/SwiftVinetas/Vinetas.swift:904`), so the tests could not reach it. The consequence: **the production rule had no coverage at all**. Inverting the `isEmpty` branch — which would silently disable every legacy LoRA, or enable every incompatible one — would not have failed a single test in a 398-line suite named after that exact behaviour.

- **Action**: taken. `LoRAMetadata.isCompatible(with:)` is now a public method holding the single definition of the rule; `Vinetas.isLoRACompatible` delegates to it; the four tests call it. Added a multi-engine case that the inlined versions never covered.

### 2. Permanently disabled tests

`Tests/SwiftVinetasTests/PixArtEngineTests.swift:135` and `:290` were `.disabled("Fails when model is already downloaded on dev machine")` — blanket, unconditional. They assert the *not-downloaded* code path, so they fail on a developer machine that has PixArt cached. But that also meant they **never ran in CI**, where the model is absent and they would have given real signal.

- **Action**: taken. Both now use `.disabled(if: PixArtEngineTests.modelIsDownloaded, …)`, gating on the actual precondition. They run in CI and skip locally, which is the inverse of the previous behaviour and the correct one.

### Not found, worth stating

No tautologies, no framework re-tests, no trivial getter/setter coverage. The `#expect(x.version == N)` matches are schema-version round-trips on parsed prompt/LoRA files, not library-version-string assertions — legitimate.

---

## Pass 3 — Coverage gaps

Measured with `xcodebuild test -scheme SwiftVinetas-Package -only-testing:SwiftVinetasTests -enableCodeCoverage YES`, then `xcrun xccov view --report --json`. Unlike the Vinetas app repo, this works.

**Target totals**: `SwiftVinetas` **38.3%** (1925/5025), `VinetasCLICore` **53.7%** (1319/2456).

Load-bearing files under 45% with 60+ executable lines:

| Target | File | Line coverage | Why it matters |
|---|---|---|---|
| VinetasCLICore | `Storyboard/StoryboardCommand.swift` | **0.0%** (221) | **Shipping in PR #61.** Its helpers were tested; the planning step was not. |
| SwiftVinetas | `VinetasMemoryProfiler.swift` | 0.0% (294) | Diagnostics; low risk, but 294 uncovered lines |
| SwiftVinetas | `VisionTransformer.swift` | 0.0% (79) | Backs `classify`; needs a model |
| SwiftVinetas | `VinetasPipeline.swift` | 1.9% (577) | Core generation orchestration; GPU-bound |
| SwiftVinetas | `ImageClassifier.swift` | 3.0% (164) | Public API (`classify`) |
| VinetasCLICore | `Entitlement/ProGate.swift` | **4.0%** (75) | **New in PR #61.** See note below. |
| SwiftVinetas | `PixArtEngine.swift` | 8.6% (608) | Engine; GPU-bound |
| SwiftVinetas | `FeatureExtractor.swift` | 14.8% (162) | Public API (`features`, `similarity`) |
| SwiftVinetas | `ImagePreprocessor.swift` | 15.6% (147) | Pure, CPU-only — **cheap to test, no excuse** |
| SwiftVinetas | `ReferenceSheetGenerator.swift` | 15.8% (95) | Character workflow |
| VinetasCLICore | `VinetasCLICore.swift` | 18.7% (936) | All command `run()` bodies |
| SwiftVinetas | `CharacterTrainer.swift` | 27.1% (140) | LoRA training |
| SwiftVinetas | `Flux2Engine.swift` | 33.1% (616) | Engine; GPU-bound |

Much of this is honest: engines and pipelines need a GPU and multi-gigabyte weights, and that work lives in `SwiftVinetasGPUTests` by design. The genuinely actionable entries are the ones that are **pure and CPU-only**:

- **`StoryboardCommand.swift` (0%)** — addressed. See below.
- **`ImagePreprocessor.swift` (15.6%)** — resize/normalise/tensor-layout logic, testable with a synthetic image and no model. The best remaining coverage-per-effort in the repo.
- **`ProGate.swift` (4%)** — my own new file. `SignedTransaction` verification is well covered by 15 tests, but `ProGate.status()` and `requireAccess(to:)` are not, because they read a fixed path derived from `Acervo.sharedModelsDirectory` with no injection seam. Worth adding a `markerURL` override so the policy layer (wrong product, wrong bundle, revoked, absent) can be tested without touching the real container. **Not done here** — it is a production API change and this branch is already carrying a bug fix.

### Writing the missing StoryboardCommand tests found a bug

`Tests/SwiftVinetasTests/StoryboardPlanTests.swift` (new, 16 tests) covers `resolvePlan` and `outputURL`. One failed immediately:

```
Expectation failed: cmd.outputURL(for: plan, in: dir).path == "/panels/sc01_02.png"
  → "/private/tmp/sc01_02.png"
```

`outputURL` decided "is this path absolute?" by checking `URL(fileURLWithPath: output).path.hasPrefix("/")`. But that initializer resolves a *relative* path against the process's current directory, so the resulting URL is always absolute and the check was always true. A `<shot output="panel.png"/>` therefore wrote to the CWD and **silently ignored `--output-dir`**. Under the sandboxed CLI shipped inside `Vinetas.app` the CWD is not writable, so this would not merely misplace the panel — it would fail the write.

- **Action**: fixed. The check now tests the raw string.

---

## Pass 4 — Flaky-in-CI predictions

**No findings.**

Everything the pattern scan surfaced turned out to be correct on inspection:

- `CancellationTeardownTests.swift:30,49` and `MockEngine.swift:232` — `Task.sleep` inside **mock generators**, simulating in-flight work so cancellation has something to cancel. That is the fixture, not a barrier.
- `/tmp/...` strings in `ImageOutputTests` and `TrainingDataTests` are **path values stored in metadata and asserted on**, never written to disk.
- The 30 `UUID()` / `Date()` occurrences are identifier and timestamp construction, not assertion inputs.
- No `URLSession` or live URLs in the unit suite.
- Only 3 `.enabled(if:)` / `.disabled(if:)` gates, all deliberate.

---

## Pass 5 — Performance test gating

**No findings.** The separation is clean:

- `make test-unit` runs `-only-testing:SwiftVinetasTests`, so nothing in `SwiftVinetasGPUTests` enters the main CI lane. `tests.yml` calls exactly that target.
- The long `.timeLimit` suites all live in `SwiftVinetasGPUTests`: `PixArtGarbageReproTests` (45 min), `PixArtMemoryProfileTests` (15 min), `PixArtIntegrationTests` (10/5 min), `BatchIntegrationTests` (10 min).
- `pixart-integration.yml` is a separate workflow scoped to `-only-testing:SwiftVinetasGPUTests/PixArtIntegrationTests`, so the 45-minute repro suite runs nowhere in CI — correct, it is a debugging tool.

**Inverse problem**: none. The Makefile's `test-gpu`, `test-integration`, and `profile-pixart-memory` targets are deliberately local-only.

---

## Consolidated action items

### Done on this branch
- `LoRAMetadata.isCompatible(with:)` extracted as the single definition of the rule; 4 tests now exercise production code instead of a copy, plus a new multi-engine case (Pass 2.1).
- `PixArtEngineTests` blanket `.disabled` → `.disabled(if: modelIsDownloaded, …)`, so both tests run in CI where they are meaningful (Pass 2.2).
- `StoryboardPlanTests.swift` added — 16 tests over `resolvePlan` / `outputURL`, taking `StoryboardCommand.swift` from 0% (Pass 3).
- **Bug fix**: `outputURL` no longer resolves relative `output` values against the process CWD, which silently defeated `--output-dir` (Pass 3).

### Recommended next
- Add a `markerURL` injection seam to `ProGate` so the entitlement *policy* (absent / wrong product / wrong bundle / revoked) is testable without the real App Group container. Currently 4% covered.
- Test `ImagePreprocessor.swift` (15.6%, pure CPU) — the best coverage-per-effort left.
- Consider whether `VinetasMemoryProfiler.swift` (294 lines, 0%) should be tested or is acceptable as diagnostics-only.

### Decide
- The uncommitted `estimatedSecondsPerImage` deletion has been sitting in the working tree across this whole audit. Land it or drop it; leaving it makes every future `git status` ambiguous.

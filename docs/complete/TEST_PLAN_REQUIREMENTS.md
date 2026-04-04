# Test Plan Reorganization — Requirements

**Status**: DRAFT — review and refine before implementation.
**Scope**: SwiftVinetas test infrastructure. Does not cover app-level tests or CI runner hardware.

---

## Motivation

The current test infrastructure has two test targets (`SwiftVinetasTests`, `SwiftVinetasGPUTests`) but no Xcode test plans. Tests that require GPU hardware are separated by target but not formally excluded from CI via test plan configuration. Adding PixArt-Sigma integration coverage and formalizing GPU isolation requires proper `.xctestplan` files so that:

1. CI runs only tests that can pass without a GPU or downloaded models
2. GPU-dependent tests are explicitly grouped and skippable via test plan selection
3. Integration tests for both FLUX.2 and PixArt-Sigma validate the full pipeline (compile → download → generate)
4. Local developers can run the right test subset with a single `make` target

---

## Current State

| Aspect | Status |
|--------|--------|
| Unit tests (CPU-only) | 25 files in `SwiftVinetasTests/`, ~523 `@Test` definitions |
| GPU tests | 2 files in `SwiftVinetasGPUTests/` (`BatchIntegrationTests`, `ImagePreprocessorTests`) |
| Test plans (`.xctestplan`) | None — filtering done via `-only-testing:` flags in Makefile |
| CI workflow | Runs `make test-unit` only (macOS); no test plan selection |
| PixArt integration tests | None — only unit-level `PixArtModelDescriptor` and `PixArtEngine` mock tests exist |
| Engine coverage | FLUX.2 has full integration tests; PixArt-Sigma has zero integration tests |

---

## T1. GPU Test Plan

A dedicated `.xctestplan` that collects all tests requiring Apple Silicon GPU, Metal, or MLX runtime. These tests never run in CI.

### T1.1 Scope

- All tests in `SwiftVinetasGPUTests` target
- Any future test tagged with `.tags(.gpu)`
- Includes: `ImagePreprocessorTests`, `BatchIntegrationTests`, and the new integration tests defined in T3

### T1.2 File

- `SwiftVinetas-GPU.xctestplan` at the project root
- Configured with `SwiftVinetasGPUTests` as the sole test target
- All tests enabled (no skips within this plan)

### T1.3 Makefile Integration

- `make test-gpu` uses this test plan: `-testPlan SwiftVinetas-GPU`
- Replaces current `-only-testing:SwiftVinetasGPUTests` flag

---

## T2. Integration Test Plan

A dedicated `.xctestplan` for integration tests that validate the full pipeline from compilation through model download to image generation. Separate from the GPU plan because integration tests are a longer-running subset with network and disk requirements.

### T2.1 Scope

- Tests tagged with `.tags(.integration)`
- Covers both FLUX.2 and PixArt-Sigma engines
- Requires: network access (model download), Apple Silicon GPU, ~10 GB disk (both models)
- Expected runtime: 5–15 minutes depending on hardware and cache state

### T2.2 File

- `SwiftVinetas-Integration.xctestplan` at the project root
- Test target: `SwiftVinetasGPUTests`
- Filtered to include only tests tagged `.integration`

### T2.3 Makefile Integration

- New target: `make test-integration` using `-testPlan SwiftVinetas-Integration`
- Distinct from `make test-gpu` (which includes all GPU tests, not just integration)

---

## T3. Integration Tests for Both Engines

New integration tests that validate the full pipeline for each supported engine. Both FLUX.2 and PixArt-Sigma must cover the same three checkpoints.

### T3.1 Checkpoint 1 — Binary Compilation

Verify that the `vinetas` CLI binary compiles successfully and is executable.

- Build the `vinetas` scheme via `xcodebuild`
- Confirm the binary exists and is a valid Mach-O executable
- This test can run without GPU (build only), but lives in the integration plan because it validates the full dependency chain including Metal shaders

### T3.2 Checkpoint 2 — Model Download

Verify that each engine's model can be downloaded (or confirmed cached) via the public API.

**FLUX.2:**
- Download `Flux2ModelDescriptor.klein4B` via `VinetasClient`
- Confirm download completes without error
- Confirm model files exist on disk via SwiftAcervo

**PixArt-Sigma:**
- Download `PixArtModelDescriptor.sigmaXL` via `VinetasClient`
- Confirm download completes without error
- Confirm model files exist on disk via SwiftAcervo

**Shared requirements:**
- Tag: `.tags(.integration)`
- Time limit: 10 minutes (first download may be slow)
- Must be idempotent — if model is already cached, test passes quickly

### T3.3 Checkpoint 3 — Non-Empty / Non-Garbage Generation

Verify that each engine generates a valid, non-trivial storyboard panel from a text prompt.

**FLUX.2:**
- Generate a single panel using `Flux2ModelDescriptor.klein4B` with a deterministic seed
- Verify the output `CGImage` has non-zero dimensions
- Verify the image is not all-black, all-white, or single-color (basic garbage detection)
- Verify pixel variance exceeds a minimum threshold (image has actual content, not noise-free solid fill)
- Verify output metadata: prompt matches input, duration > 0, model ID correct

**PixArt-Sigma:**
- Generate a single panel using `PixArtModelDescriptor.sigmaXL` with a deterministic seed
- Same validation as FLUX.2: non-zero dimensions, not single-color, variance threshold, metadata
- Use the same text prompt as the FLUX.2 test for comparability

**Shared requirements:**
- Tag: `.tags(.integration, .gpu)`
- Time limit: 5 minutes per engine
- Prompt: A simple, concrete scene (e.g., `"A red car parked on a cobblestone street"`) — avoids abstract prompts that might produce ambiguous output
- Garbage detection heuristic: sample pixels at grid points across the image; confirm at least N distinct RGB values exist (threshold TBD during implementation, suggest N ≥ 16)

### T3.4 Test Structure

All new integration tests live in `Tests/SwiftVinetasGPUTests/`:

```
Tests/SwiftVinetasGPUTests/
├── BatchIntegrationTests.swift          # Existing FLUX.2 batch tests
├── Flux2IntegrationTests.swift          # NEW: T3.1–T3.3 for FLUX.2
├── PixArtIntegrationTests.swift         # NEW: T3.1–T3.3 for PixArt-Sigma
├── ImagePreprocessorTests.swift         # Existing GPU tests
└── Fixtures/
    └── yntswyd-chapter1.yaml            # Existing fixture
```

### T3.5 Shared Helpers

Extract a reusable `IntegrationTestHelpers.swift` in `SwiftVinetasGPUTests/`:

- `assertImageNotGarbage(_ image: CGImage)` — validates non-empty, non-solid, sufficient variance
- `assertModelDownloaded(_ model: any ModelDescriptor)` — validates model files on disk
- Keeps individual test files focused on engine-specific logic

---

## T4. Unit Test Plan

Formalize the existing unit test configuration as an explicit `.xctestplan` for consistency and CI clarity.

### T4.1 File

- `SwiftVinetas-Unit.xctestplan` at the project root
- Test target: `SwiftVinetasTests` only
- All tests enabled

### T4.2 CI Integration

- CI workflow (`.github/workflows/tests.yml`) switches from `-only-testing:` to `-testPlan SwiftVinetas-Unit`
- No behavioral change — same tests run, but now driven by test plan

### T4.3 Makefile Integration

- `make test-unit` uses `-testPlan SwiftVinetas-Unit`
- `make test` runs all three plans sequentially (unit → GPU → integration) for comprehensive local runs

---

## T5. Tag Taxonomy

Standardize Swift Testing tags across the project.

### T5.1 Tags

```swift
extension Tag {
    @Tag static var integration: Self   // Existing — full pipeline tests
    @Tag static var gpu: Self           // Existing — requires Apple Silicon GPU
    @Tag static var flux2: Self         // NEW — FLUX.2 engine specific
    @Tag static var pixart: Self        // NEW — PixArt-Sigma engine specific
}
```

### T5.2 Usage

- Compilation-only tests: `.tags(.integration)`
- Model download tests: `.tags(.integration, .flux2)` or `.tags(.integration, .pixart)`
- Generation tests: `.tags(.integration, .gpu, .flux2)` or `.tags(.integration, .gpu, .pixart)`
- `ImagePreprocessorTests`: `.tags(.gpu)` (GPU but not integration)

---

## T6. Updated Makefile Targets

| Target | Test Plan | Runs in CI | Description |
|--------|-----------|------------|-------------|
| `make test-unit` | `SwiftVinetas-Unit` | Yes | CPU-only unit tests |
| `make test-gpu` | `SwiftVinetas-GPU` | No | All GPU-dependent tests |
| `make test-integration` | `SwiftVinetas-Integration` | No | Full pipeline: compile → download → generate |
| `make test` | All three plans | No | Complete local test run |
| `make test-unit-ios` | `SwiftVinetas-Unit` | Yes | iOS Simulator unit tests |
| `make test-ios` | `SwiftVinetas-Unit` | Yes | iOS Simulator (unit only — GPU tests skip on simulator) |

---

## T7. CI Workflow Updates

### T7.1 Test Plan Reference

Update `.github/workflows/tests.yml` to use `-testPlan SwiftVinetas-Unit` instead of `-only-testing:SwiftVinetasTests`.

### T7.2 No GPU Tests in CI

GPU and integration test plans are never referenced in CI. Document this in `AGENTS.md` under the build system section.

### T7.3 AGENTS.md Updates

Update the package structure section to reflect the new test plan files and the `Tests/SwiftVinetasGPUTests/` additions.

---

## Open Questions

1. **Garbage detection threshold**: What pixel variance / distinct-color-count is sufficient to distinguish real generation output from degenerate output? Needs empirical tuning during implementation.

2. **PixArt model availability**: Is PixArt-Sigma's model download path fully wired through `VinetasClient`? If `PixArtEngine` is still a stub, T3.2 and T3.3 for PixArt will need engine completion first.

3. **Test plan format**: Should test plans use Xcode's JSON-based `.xctestplan` format (requires Xcode project) or rely on `xcodebuild -only-testing:` with tag filters? SPM-only projects may need the latter approach — verify compatibility.

4. **Shared prompt fixture**: Should the integration test prompt for T3.3 be a hardcoded string or a small YAML fixture file (like the existing `yntswyd-chapter1.yaml`)?

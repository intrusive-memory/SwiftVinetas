# Testing Requirements: SwiftVinetas

This document defines the testing standard for the `SwiftVinetas` package. It describes which behaviors must be covered, how the two test targets are structured, what runs on CI vs locally, and where the current gaps are.

---

## 1. Test Targets

| Target | CI | Local | Requires |
|---|---|---|---|
| **SwiftVinetasTests** | Yes | Yes | Nothing (no GPU, no downloads) |
| **SwiftVinetasGPUTests** | No | Yes | Apple Silicon, 16 GB RAM, downloaded model weights |

`SwiftVinetasTests` must never import Metal, MLX, or call any function that touches the GPU or filesystem (beyond temp directories). `SwiftVinetasGPUTests` contains all tests that require actual model weights.

---

## 2. CI Configuration

### Runners and Destinations

| Platform | Runner | Destination |
|---|---|---|
| macOS | `macos-26` (Apple Silicon, arm64) | `platform=macOS,arch=arm64` |

iOS testing is out of scope for this package (SwiftVinetas is a library; the app-level iOS integration tests live in the Vinetas Xcode project).

### Required Status Check (must pass before merge to `main` or `development`)

- `unit-tests`

### Build and Test Commands

```bash
# Unit tests only (CI)
make test-unit

# GPU integration tests (local, requires models)
make test-gpu
```

The `Makefile` encodes the correct scheme, destination, and flags. Do not call `xcodebuild` directly.

### Timeout

30 minutes maximum for the `unit-tests` CI job. Individual unit tests must complete in under 1 second. Any test exceeding 5 seconds on CI belongs in `SwiftVinetasGPUTests`.

---

## 3. Test Framework

All tests use **Swift Testing** (`import Testing`), not XCTest. Swift 6 strict concurrency is enforced.

```swift
import Testing
@testable import SwiftVinetas

@Suite("EngineRouter") struct EngineRouterTests {
    @Test func routerFindsRegisteredEngineByModelID() async throws { ... }
}
```

Use `#expect()` and `#require()` — not `XCTAssert*`.

---

## 4. What Must Be Tested in CI (SwiftVinetasTests)

### 4a. VinetasClient Integration — currently missing, highest priority

`VinetasClient` must be tested using `MockEngine`. The mock engine already exists; the client-level tests do not.

- `VinetasClient.generate(prompt:style:model:)` routes to the correct engine
- `VinetasClient.generate()` with whitespace-only prompt throws `VinetasError.generationFailed`
- `VinetasClient.generateSequence(prompts:...)` calls the engine once per prompt
- `VinetasClient.generateSequence()` delivers panel-level and step-level progress callbacks in order
- `VinetasClient.preview()` always routes to `Flux2Engine` (Klein 4B), ignoring the `model` parameter
- `VinetasClient.generate(character:)` injects the character's trigger word into the prompt before calling the engine
- `VinetasClient.generate(character:)` loads the character's LoRA before generation and unloads it after
- `VinetasClient.generate(character:)` with a LoRA incompatible with the requested engine throws `VinetasError.loraIncompatible`
- `VinetasClient.isAvailable(_:)` delegates to the correct engine's `isAvailable`
- `VinetasClient.validateMemory(for:)` delegates to the correct engine

### 4b. Engine Router

- `EngineRouter` with no registered engines throws `.engineNotFound` for any model
- `EngineRouter` with two engines for the same model ID resolves to the first-registered
- `EngineRouter` aggregates model catalogs from all registered engines, deduplicating by ID
- `EngineRouter` is Sendable (compile-time; no test needed)

### 4c. Engine Descriptors

- `Flux2ModelDescriptor.klein4B`: ID, display name, memory requirement (16 GB), license, estimated time
- `Flux2ModelDescriptor.klein9B`: ID, display name, memory requirement (24 GB)
- `PixArtModelDescriptor.sigmaXL`: ID, display name, memory requirement (8 GB), guidance default (4.5)
- All model descriptor IDs are unique across the full catalog
- `Flux2Engine.supportedModels` contains exactly klein4B and klein9B
- `PixArtEngine.supportedModels` contains exactly sigmaXL

### 4d. Generation Request and Style Mapping

- `StyleConfig` → `GenerationRequest` mapping preserves all fields (prompt, negative prompt, steps, guidance, seed, dimensions)
- `StyleConfig` with nil seed maps to `GenerationRequest.seed == nil`
- `StyleConfig` with nil negative prompt maps to `GenerationRequest.negativePrompt == nil`
- `GenerationRequest` defaults: `mode == .textToImage`, seed is nil (randomized)
- `GenerationMode.imageToImage` requires a non-empty `referenceImages` array

### 4e. PromptFile Parsing

- v1 YAML parses to correct `PromptFile` with all panels
- v2 YAML parses with character references resolved
- Missing required `panels` key throws `VinetasError.invalidPromptFile`
- Invalid YAML (not a mapping at root) throws `VinetasError.invalidPromptFile`
- Per-panel style override supersedes project-level style
- Panel with no explicit steps inherits project default steps
- Empty panels array is valid (produces zero panels)

### 4f. Character Management

- `Character.deriveSlug(from:)` lowercases, strips non-alphanumeric, replaces spaces with hyphens
- `Character.deriveSlug(from:)` collapses consecutive hyphens to one
- `LoRAMetadata` with `compatibleEngines == nil` is compatible with all engines (legacy behavior)
- `LoRAMetadata` migration: `"klein4b"` → `"flux2"`, `"klein9b"` → `"flux2"`
- `CharacterManager.createCharacter(_:)` creates the expected directory structure (source/, references/, training/, lora/)
- `CharacterManager.loadCharacter(slug:)` returns `nil` for unknown slug
- `CharacterManager.deleteCharacter(_:)` removes directory and all contents

### 4g. Prompt Composition

- Character prompt = trigger word + style prompt + panel prompt (in that order)
- Style prompt of `nil` omits the style segment (no double space)
- Trigger word of `nil` is omitted without leaving a leading space
- `PromptComposer` trims leading and trailing whitespace from the final prompt

### 4h. LoRA Compatibility

- `LoRAMetadata` tagged `["flux2"]` is compatible with `Flux2Engine` and incompatible with `PixArtEngine`
- `LoRAMetadata` tagged `["pixart-sigma"]` is compatible with `PixArtEngine` and incompatible with `Flux2Engine`
- `LoRAMetadata` tagged `["flux2", "pixart-sigma"]` is compatible with both
- Untagged `LoRAMetadata` (nil engines) is compatible with all engines

### 4i. Aspect Ratio

- `AspectRatio.square` → 1024×1024
- `AspectRatio.wide` → 1024×576
- `AspectRatio.portrait` → 576×1024
- `AspectRatio.panel` → 512×768
- All cases produce dimensions that are multiples of 16 (MLX latent alignment requirement)
- `AspectRatio.styleConfig(for:)` propagates correct width/height

### 4j. Memory Validation

- `MemoryValidation.ok` when available >= model requirement
- `MemoryValidation.warning` when available is between 90% and 100% of requirement
- `MemoryValidation.insufficient` when available < 90% of requirement
- `VinetasMemory.physicalMemoryBytes` returns a non-zero value on Apple Silicon

### 4k. Model Manager

- `VinetasModelManager` returns App Group container path when entitlement is available
- `VinetasModelManager` falls back to `Application Support` when App Group is unavailable
- Path does not include trailing slash
- Platform (macOS vs iOS) selects the correct base directory

### 4l. Image Classification

- `Classification` instances sort by confidence descending
- `ImageNetLabels.label(at:)` returns non-nil for indices 0–999
- `ImageNetLabels.label(at:)` returns `nil` for index 1000

### 4m. Image Output

- `ImageOutput.writePNG(image:to:)` produces a file with valid PNG magic bytes
- `ImageOutput.writeJPEG(image:to:quality:)` produces a file with valid JPEG magic bytes (`FF D8`)
- Writing to a non-existent parent directory throws
- Writing to a read-only directory throws

### 4n. Errors

All `VinetasError` cases must have non-nil `localizedDescription` containing context relevant to the error (model ID, engine ID, file path, etc.).

---

## 5. What Must Be Tested Locally (SwiftVinetasGPUTests)

### 5a. Precondition Checks

All GPU tests must fail with a clear message when preconditions are unmet — do not return silently.

```swift
@Test func klein4BGeneration() async throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
        Issue.record("No Metal GPU — Klein 4B requires Apple Silicon")
        return
    }
    let required: UInt64 = 16 * 1_073_741_824
    guard ProcessInfo.processInfo.physicalMemory >= required else {
        Issue.record("Insufficient memory: 16 GB required for Klein 4B")
        return
    }
    // test body
}
```

### 5b. Flux2Engine — real weights

- `Flux2Engine.loadModel(.klein4B)` completes without error on 16 GB+ machine
- Load phase callbacks fire: `.downloading`, `.loading`, `.ready` (in that order)
- `generate(request:)` with 4 steps produces a non-nil `CGImage` at the requested dimensions
- Output image pixel values are finite (no all-black, no all-white artifacts for a non-trivial prompt)
- Fixed seed produces identical output on two consecutive calls
- `Flux2Engine.unloadModel()` releases GPU memory (measured via `MemoryManager`)
- LoRA loading succeeds; generation with LoRA differs from generation without (pixel-level diff)
- Cancellation during generation does not crash and does not leave the engine in a broken state

### 5c. PixArtEngine — real weights

- `PixArtEngine.loadModel(.sigmaXL)` completes on 8 GB+ machine
- `generate(request:)` with 10 steps produces a non-nil `CGImage` at 512×512
- `PixArtEngine.supports(.imageToImage)` returns `false`; requesting image-to-image throws `.engineFeatureUnsupported`

### 5d. VinetasClient — end-to-end

- `VinetasClient.shared.generate(prompt:)` with a downloaded Klein 4B produces a `CGImage`
- `VinetasClient.shared.generateSequence(prompts:)` with three prompts produces three `CGImage` values
- `VinetasClient.shared.preview(prompt:)` completes in under 30 seconds (4-step fast path)

### 5e. Timeout Values

| Test | Local Timeout |
|---|---|
| Model load (Klein 4B) | 120 seconds |
| Single generation (4 steps, 512×512) | 180 seconds |
| `generateSequence` (3 panels, 4 steps each) | 480 seconds |
| PixArt load + generate | 300 seconds |

---

## 6. Mock Infrastructure

### MockEngine (already exists at `Tests/SwiftVinetasTests/MockEngine.swift`)

Use `MockEngine` for all `SwiftVinetasTests` tests that exercise routing or client orchestration. The mock must:

- Implement `ImageGenerationEngine` fully
- Return a synthetic `CGImage` (64×64 white square) by default
- Fire `stepProgress` callbacks `simulatedSteps` times (default: 4)
- Accept an `errorToThrow` property for error-path tests
- Track `loadCallCount`, `generateCallCount`, `loraLoadPath`, `loraUnloaded`

```swift
final class MockEngine: ImageGenerationEngine, @unchecked Sendable {
    let engineID: String
    let supportedModels: [any ModelDescriptor]
    var simulatedSteps: Int = 4
    var errorToThrow: Error? = nil
    var loadCallCount = 0
    var generateCallCount = 0
    var loraLoadPath: String? = nil
    var loraUnloaded = false
    ...
}
```

### TestImage

```swift
enum TestImage {
    static func make(width: Int = 64, height: Int = 64) -> CGImage { ... }
}
```

Synthesizes a valid `CGImage` without bundled resources using `CGContext`.

---

## 7. Coverage Gaps (Priority Order)

| Priority | Gap | Resolution |
|---|---|---|
| 1 | No `VinetasClient` unit tests — client orchestration untested | Add in `SwiftVinetasTests` with `MockEngine` |
| 2 | `Flux2Engine` and `PixArtEngine` lifecycle not unit-tested | Add with mocked `Flux2Pipeline` / `TuberiaEngine` |
| 3 | CLI argument parsing (`VinetasCLI`) has no tests | Add unit tests for each subcommand |
| 4 | `CharacterManager` file I/O not exhaustively tested | Add with temp directories |
| 5 | `VinetasError` descriptions not tested for all cases | Add parameterized tests |
| 6 | Concurrent `VinetasClient.generateSequence()` calls not tested | Add actor isolation stress test |
| 7 | `ImageClassifier` error paths (missing weights, invalid file) not tested | Add unit tests with mock filesystem |
| 8 | `LoRAManager` load/unload sequencing not tested | Add with `MockEngine` tracking |
| 9 | GPU tests: fixed-seed determinism not automated | Add to `SwiftVinetasGPUTests` |
| 10 | GPU tests: memory release after `unloadModel()` not measured | Add with `MemoryManager` snapshot delta |

---

## 8. What is Out of Scope

- App-level UI testing — that lives in `VinetasIOSUITests` and `VinetasUITests` in the Vinetas Xcode project
- `SwiftAcervo` download behavior — tested in that package's own test suite
- `flux-2-swift-mlx` transformer correctness — tested in that package's own GPU test suite
- LoRA training correctness — training pipeline validation is not in scope for SwiftVinetas tests; it belongs in the training scripts

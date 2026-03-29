# SwiftVinetas - AI Agent Instructions

**Version**: 0.7.2
**Purpose**: Guide AI agents working on SwiftVinetas
**Audience**: Claude Code, Gemini, and other AI development assistants

## Product Overview

**SwiftVinetas** — On-device storyboard and comic panel generation from text prompts using FLUX.2 Klein models via MLX on Apple Silicon.

**Platforms**: macOS 26.0+ (Apple Silicon), iOS 26.0+.

## Architecture

- **Library**: `SwiftVinetas` wraps `Flux2Core` (from flux-2-swift-mlx) via an engine abstraction layer
- **Engine Layer**: `ImageGenerationEngine` protocol + `EngineRouter` dispatcher — supports multiple backends
- **Engines**: `Flux2Engine` (wraps Flux2Core), `PixArtEngine` (wraps PixArtBackbone via SwiftTubería pipeline)
- **Public API**: `VinetasClient` (instance-based, `.shared` singleton) — replaces deprecated static `Vinetas` enum
- **CLI**: `vinetas` for testing and standalone use
- **Models**: FLUX.2 Klein 4B (fast, default) and Klein 9B (quality), extensible via `ModelDescriptor` protocol
- **Style**: LoRA adapters in safetensors format, tagged with `compatibleEngines: [String]`
- **Prompt files**: YAML parsed via `marcprux/universal`
- **Model cache**: App Group container (`group.intrusive-memory.models`) via SwiftAcervo, with Application Support fallback — sandbox-safe on all platforms

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full design decisions.
See [docs/REQUIREMENTS_V1.md](docs/REQUIREMENTS_V1.md) for prioritized requirements.
See [docs/LEARNING.md](docs/LEARNING.md) for research findings.

## Build System

**CRITICAL**: Always use `xcodebuild` or Makefile targets. NEVER use `swift build` or `swift test` — Metal shaders required by MLX won't compile.

```bash
# Using Makefile (preferred)
make build          # Debug build + copy to ./bin/vinetas
make test           # Run all macOS tests
make test-unit      # macOS unit tests only (no GPU) — CI-safe
make test-gpu       # GPU tests only (requires Apple Silicon + downloaded model) — local only
make test-integration  # Integration tests: model download + image generation — local only
make test-ios       # Run all iOS Simulator tests
make test-unit-ios  # iOS unit tests only (no GPU)
make build-ios      # Build library for iOS Simulator
make release        # Release build
make install        # Release build + copy to ./bin/vinetas

# NOTE: test-gpu and test-integration are LOCAL-ONLY targets.
# They require Apple Silicon hardware and pre-downloaded model weights.
# These targets are NEVER run in CI (GitHub Actions uses make test-unit only).

# Using xcodebuild directly
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS,arch=arm64'
xcodebuild build -scheme SwiftVinetas -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
```

## Key Types

```swift
// Primary API (v0.5.0+, updated v0.7.2) — instance-based
let client = VinetasClient.shared
client.generate(prompt:style:model:)               // Single panel (routes through EngineRouter)
client.generateSequence(prompts:referenceImages:style:model:progress:)  // Multi-panel
client.generate(prompt:character:style:model:)     // Character-aware (LoRA compatibility check)
client.preview(prompt:)                            // FLUX.2-only fast path (Klein 4B, 4 steps, 512x512)

// Engine Abstraction
ImageGenerationEngine  // Protocol: generate, loadModel, loadLoRA, download, validateMemory
EngineRouter           // Actor: dispatches to registered engines by model's engineID
Flux2Engine            // Actor: wraps Flux2Pipeline, engineID "flux2"
PixArtEngine           // Actor: wraps DiffusionPipeline via PixArtBackbone, engineID "pixart-sigma"
ModelDescriptor        // Protocol: id, displayName, engineID, minimumMemoryGB, etc.
Flux2ModelDescriptor   // .klein4B ("flux2-klein-4b"), .klein9B ("flux2-klein-9b")
PixArtModelDescriptor  // .sigmaXL ("pixart-sigma-xl"), 8 GB minimum, Apache 2.0

// Deprecated API (still functional, forwards to VinetasClient.shared)
Vinetas                // @available(*, deprecated) — static enum, use VinetasClient instead
VinetasModel           // @available(*, deprecated) — use ModelDescriptor types directly

// Configuration & Output
StyleConfig         // steps, guidance, seed, dimensions, style/negative prompts
PanelOutput         // CGImage + metadata (prompt, seed, duration, modelID: String)
VinetasError        // modelNotFound, insufficientMemory, generationFailed, engineNotFound, etc.
GenerationRequest   // mode (.textToImage / .imageToImage), prompt, steps, guidance
GenerationResult    // image, seed, duration
```

## Dependencies

| Package | Import | Purpose |
|---------|--------|---------|
| flux-2-swift-mlx | `Flux2Core`, `FluxTextEncoders` | FLUX.2 pipeline (MIT) |
| SwiftTubería | `Tuberia`, `TuberiaCatalog` | Componentized diffusion pipeline protocols |
| pixart-swift-mlx | `PixArtBackbone` | PixArt-Sigma DiT model plugin |
| SwiftAcervo | `SwiftAcervo` | Model download/cache |
| Universal | `YAML`, `JSON` | Prompt file parsing |
| swift-argument-parser | `ArgumentParser` | CLI (vinetas target only) |

**Rejected**: `mzbac/flux.swift` — GPL-3.0 license incompatible with Produciesta.

## Underlying Flux2Core API

The library wraps `Flux2Pipeline`. Key patterns:

```swift
let pipeline = try await Flux2Pipeline(model: .klein4b, quantization: .balanced)
try await pipeline.loadModels(progressCallback: { progress in ... })

// Text-to-image
let result = try await pipeline.generateTextToImageWithResult(prompt: "...", height: 1024, width: 1024)

// Image-to-image with references (up to 3)
let result = try await pipeline.generateImageToImageWithResult(prompt: "...", images: [refImage], strength: 0.7)

// LoRA
pipeline.loadLoRA(LoRAConfig(filePath: "style.safetensors", scale: 0.8))
pipeline.unloadAllLoRAs()
```

## Package Structure

```
SwiftVinetas/
├── Sources/
│   ├── SwiftVinetas/           # Library
│   │   ├── Vinetas.swift       # VinetasClient (primary API) + deprecated Vinetas enum
│   │   ├── Core/               # StyleConfig, VinetasError, PanelOutput, Pipeline, Memory
│   │   ├── Engine/             # Engine abstraction layer (v0.5.0+)
│   │   │   ├── ImageGenerationEngine.swift  # Protocol
│   │   │   ├── ModelDescriptor.swift        # Protocol + ModelLicense
│   │   │   ├── EngineTypes.swift            # GenerationRequest, GenerationResult, etc.
│   │   │   ├── EngineRouter.swift           # Actor dispatcher
│   │   │   ├── Flux2Engine.swift            # FLUX.2 conformance
│   │   │   └── PixArtEngine.swift           # PixArt-Sigma conformance
│   │   ├── Character/          # Character pipeline, LoRA training
│   │   └── Understanding/      # ViT-B/16, DINOv2, image preprocessing
│   └── vinetas/                # CLI
│       └── VinetasCLI.swift
├── Tests/
│   ├── SwiftVinetasTests/
│   └── SwiftVinetasGPUTests/
│       ├── TestTags.swift                   # Shared tag taxonomy (.integration, .gpu, .flux2, .pixart)
│       ├── IntegrationTestHelpers.swift     # assertImageNotGarbage, assertModelDownloaded
│       ├── Flux2IntegrationTests.swift      # FLUX.2 pipeline: compile, download, generate
│       ├── PixArtIntegrationTests.swift     # PixArt-Sigma pipeline: compile, download, generate
│       ├── BatchIntegrationTests.swift      # Batch generation integration tests
│       └── ImagePreprocessorTests.swift     # GPU-accelerated image preprocessing tests
├── docs/
│   ├── LEARNING.md
│   ├── ARCHITECTURE.md
│   ├── REQUIREMENTS_V1.md
│   └── ENGINE_ABSTRACTION_REQUIREMENTS.md
└── .github/workflows/tests.yml
```

## Git Workflow

- Branch: `development` -> PR -> `main`
- Never commit directly to `main`
- CI: Unit tests (macOS + iOS) must pass before merge to main
- Required status checks: "Unit Tests (macOS)", "Unit Tests (iOS Simulator)"

## Platform Constraints

- **macOS 26.0+** — never add `@available` for older versions
- **iOS 26.0+** — supported via MLX on iOS
- **Apple Silicon ONLY** — M-series / A-series chips required (MLX/Metal)

## Memory Constraints

- PixArt-Sigma XL int4: 8 GB minimum (works on all iPads and most Macs)
- Klein 4B int4: 16 GB minimum
- Klein 9B qint8: 24 GB minimum
- Always validate memory before loading models
- VAE must stay at bf16/fp16 (never quantize)

## Critical Rules for AI Agents

1. NEVER use `swift build` or `swift test` — use `xcodebuild` or `make` targets
2. NEVER commit directly to `main` — always PR from `development`
3. NEVER add `@available` for macOS versions older than 26.0 or iOS versions older than 26.0
4. ALWAYS validate memory before loading models
5. ALWAYS read files before editing
6. NEVER create files unless necessary
7. Follow agent-specific instructions — see [CLAUDE.md](CLAUDE.md) or [GEMINI.md](GEMINI.md)

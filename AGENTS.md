# SwiftVinetas - AI Agent Instructions

**Version**: 0.3.0
**Purpose**: Guide AI agents working on SwiftVinetas
**Audience**: Claude Code, Gemini, and other AI development assistants

## Product Overview

**SwiftVinetas** — On-device storyboard and comic panel generation from text prompts using FLUX.2 Klein models via MLX on Apple Silicon.

**Platforms**: macOS 26.0+ (Apple Silicon only). No iOS support (MLX is macOS-only).

## Architecture

- **Library**: `SwiftVinetas` wraps `Flux2Core` (from flux-2-swift-mlx) for image generation
- **CLI**: `vinetas` for testing and standalone use
- **Models**: FLUX.2 Klein 4B (fast, default) and Klein 9B (quality)
- **Style**: LoRA adapters in safetensors format, single LoRA per generation
- **Prompt files**: YAML parsed via `marcprux/universal`
- **Model cache**: `~/Library/SharedModels/` via SwiftAcervo

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full design decisions.
See [docs/REQUIREMENTS_V1.md](docs/REQUIREMENTS_V1.md) for prioritized requirements.
See [docs/LEARNING.md](docs/LEARNING.md) for research findings.

## Build System

**CRITICAL**: Always use `xcodebuild` or Makefile targets. NEVER use `swift build` or `swift test` — Metal shaders required by MLX won't compile.

```bash
# Using Makefile (preferred)
make build          # Debug build + copy to ./bin/vinetas
make test           # Run all tests
make test-unit      # Unit tests only (no GPU)
make release        # Release build
make install        # Release build + copy to ./bin/vinetas

# Using xcodebuild directly
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'
xcodebuild build -scheme vinetas -destination 'platform=macOS'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'
```

## Key Types

```swift
// Public API (static)
Vinetas.version                                     // "0.3.0"
Vinetas.generate(prompt:style:model:)               // Single panel
Vinetas.generateSequence(prompts:referenceImages:style:model:progress:)  // Multi-panel
Vinetas.generateFromFile(_:model:progress:)         // From YAML prompt file
Vinetas.generate(prompt:character:style:model:)     // Character-aware
Vinetas.preview(prompt:)                            // Fast 512x512 preview
Vinetas.classify(image:topK:)                       // ViT-B/16 classification
Vinetas.extractFeatures(from:)                      // DINOv2 feature extraction
Vinetas.similarity(between:and:)                    // Cosine similarity
Vinetas.verifyCharacter(_:threshold:)               // Character consistency check

// Configuration
StyleConfig         // steps, guidance, seed, dimensions, style/negative prompts
VinetasModel        // .klein4b, .klein9b
PanelOutput         // CGImage + metadata (prompt, seed, duration, dimensions)
VinetasError        // modelNotFound, insufficientMemory, generationFailed, invalidPromptFile, downloadFailed
```

## Dependencies

| Package | Import | Purpose |
|---------|--------|---------|
| flux-2-swift-mlx | `Flux2Core`, `FluxTextEncoders` | FLUX.2 pipeline (MIT) |
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
│   │   ├── Vinetas.swift       # Public API (static) + version
│   │   ├── Core/               # StyleConfig, VinetasError, PanelOutput, Pipeline
│   │   ├── Character/          # Character pipeline, LoRA training
│   │   └── Understanding/      # ViT-B/16, DINOv2, image preprocessing
│   └── vinetas/                # CLI
│       └── VinetasCLI.swift
├── Tests/
│   └── SwiftVinetasTests/
├── docs/
│   ├── LEARNING.md
│   ├── ARCHITECTURE.md
│   └── REQUIREMENTS_V1.md
└── .github/workflows/tests.yml
```

## Git Workflow

- Branch: `development` -> PR -> `main`
- Never commit directly to `main`
- CI: Unit Tests must pass before merge to main
- Required status check: "Unit Tests"

## Platform Constraints

- **macOS 26.0+ ONLY** — never add `@available` for older versions
- **Apple Silicon ONLY** — M1/M2/M3/M4/M5 required (MLX/Metal)
- **No iOS** — MLX does not support iOS; do not add iOS platform targets

## Memory Constraints

- Klein 4B int4: 16 GB minimum
- Klein 9B qint8: 24 GB minimum
- Always validate memory before loading models
- VAE must stay at bf16 (never quantize)

## Critical Rules for AI Agents

1. NEVER use `swift build` or `swift test` — use `xcodebuild` or `make` targets
2. NEVER commit directly to `main` — always PR from `development`
3. NEVER add iOS platform targets — MLX is macOS-only
4. NEVER add `@available` for macOS versions older than 26.0
5. ALWAYS validate memory before loading models
6. ALWAYS read files before editing
7. NEVER create files unless necessary
8. Follow agent-specific instructions — see [CLAUDE.md](CLAUDE.md) or [GEMINI.md](GEMINI.md)

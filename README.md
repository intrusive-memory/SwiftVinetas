# SwiftVinetas

**Viñetas Gráficas** — On-device storyboard and comic panel generation from text prompts via FLUX.2 on Apple Silicon.

Part of the [intrusive-memory](https://github.com/intrusive-memory) ecosystem.

## Overview

SwiftVinetas generates sequential visual panels from text descriptions using FLUX.2 Klein models running entirely on-device via MLX. It ships as both a Swift library (for integration into [Produciesta](https://produciesta.app)) and a standalone `vinetas` CLI.

### Key Features

- **Engine Abstraction** — Protocol-based `ImageGenerationEngine` with `EngineRouter` dispatcher, supporting multiple backends
- **FLUX.2 Klein 4B/9B** — Fast generation (~26s/panel on Klein 4B) with 16 GB minimum RAM
- **PixArt-Sigma XL** — Real engine implementation via SwiftTubería pipeline (8 GB minimum, ~10s/image)
- **LoRA support** — Load style adapters in safetensors format with engine-tagged compatibility
- **Multi-image conditioning** — Up to 3 reference images for character consistency across panels
- **YAML prompt files** — Batch-generate panel sequences from structured prompt definitions
- **Memory-aware** — Automatically selects quantization and loading strategy based on available RAM
- **On-device only** — No cloud, no API keys, everything runs locally on Apple Silicon

## Requirements

| | Minimum | Recommended |
|---|---|---|
| **macOS** | 26.0 | 26.0+ |
| **Swift** | 6.2 | 6.2+ |
| **Hardware** | Apple Silicon (M1+) | M3 Pro or later |
| **RAM** | 16 GB (Klein 4B, int4) | 32 GB (Klein 9B, qint8) |

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftVinetas.git", from: "0.10.1")
]
```

Then add `"SwiftVinetas"` to your target's dependencies.

### CLI (from source)

```bash
git clone https://github.com/intrusive-memory/SwiftVinetas.git
cd SwiftVinetas
xcodebuild build -scheme vinetas -destination 'platform=macOS' -configuration Release
```

## Usage

### Library

```swift
import SwiftVinetas

// Generate a single panel (VinetasClient API)
let client = VinetasClient.shared
let image = try await client.generate(prompt: "A detective in a rain-soaked alley at night")

// With style configuration and model selection
let image = try await client.generate(
    prompt: "A detective in a rain-soaked alley at night",
    style: StyleConfig(stylePrompt: "noir comic, heavy inks, dramatic shadows"),
    model: VinetasClient.klein4B
)

// Fast preview (FLUX.2-only, 512x512, 4 steps)
let preview = try await client.preview(prompt: "A detective in a rain-soaked alley")

// Multi-panel sequence with character reference images
let panels = try await client.generateSequence(
    prompts: ["Vale enters the bar", "Vale orders a drink", "Vale spots the stranger"],
    referenceImages: [valeRefImage],
    style: StyleConfig(stylePrompt: "noir comic")
)
```

### CLI

```bash
# Generate a single panel
vinetas generate "A detective in a rain-soaked alley" --output panel.png

# Batch generate from prompt file
vinetas batch scene.yaml --output-dir ./panels/

# With LoRA style
vinetas generate "A detective" --lora comic-style.safetensors --lora-scale 0.8

# Model management
vinetas download --model klein4b
vinetas list
```

### YAML Prompt File Format

```yaml
version: 1
project:
  title: "Scene 5 - The Confrontation"
  style:
    prompt: "noir comic book style, heavy inks, dramatic shadows"
    negative: "blurry, low quality, photorealistic"
    steps: 20
    guidance: 3.5
    width: 1024
    height: 1024

panels:
  - prompt: "Wide establishing shot of a rain-soaked city at night."
    seed: 42
  - prompt: "Close-up of a detective lighting a cigarette under a streetlamp."
  - prompt: "Over-the-shoulder shot looking down a dark alley."
    width: 1536
    height: 640
```

## Models

| Model | Parameters | int4 Size | RAM Required | Speed |
|-------|-----------|-----------|-------------|-------|
| **PixArt-Sigma XL** | 0.6B | ~3.6 GB | 8 GB | ~10s/image |
| **Klein 4B** (default) | 4B | ~2.1 GB | 16 GB | ~26s/image |
| **Klein 9B** | 9B | ~4.9 GB | 24 GB | ~62s/image |

Models are downloaded from HuggingFace on first use and cached in the App Group container (`group.intrusive-memory.models`) or `Application Support/SwiftAcervo/SharedModels/` as fallback. All paths are sandbox-safe for App Store distribution.

## Dependencies

| Package | License | Purpose |
|---------|---------|---------|
| [flux-2-swift-mlx](https://github.com/VincentGourbin/flux-2-swift-mlx) | MIT | FLUX.2 inference pipeline |
| [SwiftTubería](https://github.com/intrusive-memory/SwiftTuberia) | MIT | Componentized diffusion pipeline protocols |
| [pixart-swift-mlx](https://github.com/intrusive-memory/pixart-swift-mlx) | MIT | PixArt-Sigma DiT model plugin |
| [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) | MIT | Model download and cache management |
| [Universal](https://github.com/marcprux/universal) | Apache-2.0 | YAML prompt file parsing |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | CLI argument parsing |

## Development

```bash
# Build library
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'

# Build CLI
xcodebuild build -scheme vinetas -destination 'platform=macOS'

# Run tests
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'
```

### Branch Workflow

- `development` — active development
- `main` — stable releases (PRs require passing CI)

## Documentation

- [Learning Document](docs/LEARNING.md) — Research findings on MLX, FLUX, and the image generation ecosystem
- [Architecture](docs/ARCHITECTURE.md) — Technical design decisions and component architecture
- [V1 Library Requirements](docs/V1_REQUIREMENTS.md) — Prioritized library feature requirements
- [GUI Requirements](docs/GUI_REQUIREMENTS.md) — Host-app/GUI requirements
- [Engine Abstraction Requirements](docs/ENGINE_ABSTRACTION_REQUIREMENTS.md) — Engine protocol and multi-backend design

## Status

**v0.10.1** — Release tooling: new `release.yml` workflow builds + uploads the canonical tarball and dispatches the Homebrew formula update on `release: published`; Makefile install/release targets reorganized so `make dist` is CI-reproducible; release upload step now passes `GITHUB_TOKEN` explicitly.

**v0.10.0** — FLUX.2 re-enabled (upstream tokenizer-collision fix); MLX reentrancy guard + memory/clock/seed hardening; PixArt garbage-image fix (now requires native 1024×1024); local sibling overrides in `Package.swift` for non-CI dev; configurable fixture prompt via `make test-fixtures PROMPT="..."`; new fixture/repro tooling. Dependency floors: flux-2-swift-mlx 3.0.1, SwiftAcervo 0.8.4, SwiftTubería 0.6.0, pixart-swift-mlx 0.5.1.

**v0.9.1** — Flux2 MACF bypass fix via SwiftTubería 0.3.5; CLI bug fixes; cross-model test suite.

**v0.9.0** — Comprehensive test suite: `VinetasCLICore` library target, unit tests for client routing, error types, CLI argument parsing, LoRA sequencing, and actor isolation; expanded GPU tests for fixed-seed determinism and memory release.

**v0.8.4** — Fix `isAvailable` always returning false on fresh app launch; bump SwiftTubería minimum to 0.2.7; add `lint` Makefile target.

**v0.8.3** — Bump SwiftTubería minimum to 0.2.6, which fixes the compiled silu op in the SDXL VAE decoder.

**v0.8.2** — Fix PixArt component registration bridge to `ComponentRegistry` so `AcervoManager.withModelAccess` can resolve short component IDs to their HuggingFace repo paths.

**v0.8.1** — Bump SwiftAcervo minimum requirement to 0.5.5 for bugfix compatibility.

**v0.8.0** — Pin all dependencies to version ranges instead of branch refs for reproducible builds.

**v0.7.3** — Fix PixArt model download: pass empty files array to Acervo and add debug logging for download operations.

**v0.7.2** — Dependency resolution fixes: all intrusive-memory dependencies now resolve from `main` branches, swift-transformers updated to 1.x across the dependency graph.

**v0.7.1** — Sandbox-safe model storage for App Store distribution. All model downloads now use App Group container with Application Support fallback. `VinetasModelManager.configureStorage()` API for path configuration. CharacterManager updated to use Application Support.

**v0.7.0** — Real PixArtEngine implementation via SwiftTubería/PixArtBackbone, runtime memory-gated engine registration, dedicated GPU test target, remote dependency URLs.

**v0.5.0** — Engine abstraction layer with `ImageGenerationEngine` protocol, `EngineRouter` dispatcher, `VinetasClient` public API, LoRA engine tagging, and deprecated compatibility shims.

**v0.4.0** — iOS 26 platform support. Core generation pipeline, character-aware generation with LoRA training, image classification (ViT-B/16), feature extraction (DINOv2), and CLI.

## License

MIT

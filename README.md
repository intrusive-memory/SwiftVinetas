# SwiftVinetas

**Viñetas Gráficas** — On-device storyboard and comic panel generation from text prompts via FLUX.2 on Apple Silicon.

Part of the [intrusive-memory](https://github.com/intrusive-memory) ecosystem.

## Overview

SwiftVinetas generates sequential visual panels from text descriptions using FLUX.2 Klein models running entirely on-device via MLX. It ships as both a Swift library (for integration into [Produciesta](https://produciesta.app)) and a standalone `vinetas` CLI.

### Key Features

- **FLUX.2 Klein 4B/9B** — Fast generation (~26s/panel on Klein 4B) with 16 GB minimum RAM
- **LoRA support** — Load style adapters in safetensors format with configurable scale
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
    .package(url: "https://github.com/intrusive-memory/SwiftVinetas.git", branch: "main")
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

// Generate a single panel
let image = try await Vinetas.generate("A detective in a rain-soaked alley at night")

// With style configuration
let image = try await Vinetas.generate(
    "A detective in a rain-soaked alley at night",
    style: StyleConfig(stylePrompt: "noir comic, heavy inks, dramatic shadows"),
    model: .klein4b
)

// Batch from YAML prompt file
let panels = try await Vinetas.generateFromFile(
    URL(fileURLWithPath: "scene.yaml"),
    progress: { current, total in print("Panel \(current)/\(total)") }
)

// With character reference images
let panels = try await Vinetas.generateSequence(
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
| **Klein 4B** (default) | 4B | ~2.1 GB | 16 GB | ~26s/image |
| **Klein 9B** | 9B | ~4.9 GB | 24 GB | ~62s/image |

Models are downloaded from HuggingFace on first use and cached at `~/Library/SharedModels/`.

## Dependencies

| Package | License | Purpose |
|---------|---------|---------|
| [flux-2-swift-mlx](https://github.com/VincentGourbin/flux-2-swift-mlx) | MIT | FLUX.2 inference pipeline |
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
- [Requirements v1.0](docs/REQUIREMENTS_V1.md) — Prioritized feature requirements

## Status

**Pre-release / Active Development** — Project scaffold and dependencies are in place. Core generation pipeline is not yet implemented.

## License

MIT

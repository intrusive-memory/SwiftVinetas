# SwiftVinetas — Architecture Planning Document

## Overview

SwiftVinetas is a Swift library + CLI for generating storyboard panels and comic art from text prompts, running entirely on-device via MLX on Apple Silicon. It will integrate into Produciesta as a library and ship as a standalone `vinetas` CLI for testing and standalone use.

---

## Architectural Decisions

### AD-1: MLX via flux-2-swift-mlx, not Core ML

**Decision**: Use MLX (via VincentGourbin/flux-2-swift-mlx SPM package) as the inference backend.

**Rationale**:
- FLUX models are not available via Core ML and Apple has shown no intent to add them
- flux-2-swift-mlx is an active MIT-licensed SPM package with FLUX.2 Klein 4B/9B support, LoRA loading + training, multi-image conditioning, and int4/qint8/bf16 quantization
- **mzbac/flux.swift was considered but rejected due to GPL-3.0 license** — copyleft is incompatible with Produciesta's licensing
- MLX loads weights directly — no model conversion pipeline needed
- Unified memory model eliminates CPU↔GPU transfer overhead
- FLUX.2 Klein 4B (2.1 GB transformer at int4) is dramatically faster and lighter than FLUX.1's 12B

**Trade-off**: No iOS/iPadOS support. MLX is macOS-only. If iOS is needed later, we would need a Core ML port or to wait for Apple to bring MLX to iOS. flux-2-swift-mlx is newer (7 stars, single maintainer) — we accept this risk because it's MIT-licensed and we can fork if needed.

**Dependencies**:
- `flux-2-swift-mlx` (FLUX.2 pipeline, LoRA, quantization — includes mlx-swift transitively)
- `SwiftAcervo` (model management)
- `marcprux/universal` (YAML prompt file parsing)

### AD-2: FLUX.2 Klein 4B as Primary Model

**Decision**: Target FLUX.2 Klein 4B as the primary generation model, with Klein 9B as a quality option.

**Rationale** (verified):
- Klein 4B generates at **~26s/image** (1024x1024) — 2-3x faster than FLUX.1 4-bit
- Transformer is only **2.1 GB at int4** — fits comfortably in 16 GB RAM
- Multi-image conditioning supports **up to 3 reference images** for character consistency
- Single text encoder (Qwen3 4B) instead of CLIP + T5 simplifies the pipeline
- flux-2-swift-mlx API: `Flux2Pipeline(model: .klein4b)` with `generateImageToImage(prompt:, images:, strength:)`

**Quality tier**: Klein 9B (~62s, 4.9 GB int4) for final renders, Klein 4B for iteration/preview.

**Not using**: FLUX.1 Kontext (requires GPL-licensed flux.swift). FLUX.2's native multi-image conditioning provides similar character consistency via the MIT-licensed package.

### AD-3: LoRA-Based Style System

**Decision**: Style is controlled via LoRA adapters in safetensors format, not full model fine-tunes.

**Rationale** (verified):
- LoRAs are 50-200 MB vs multi-GB for full models
- flux-2-swift-mlx supports LoRA loading with configurable scale, auto-detects Diffusers and BFL format layouts
- flux-2-swift-mlx includes **built-in LoRA training** (text-to-image and image-to-image training, gradient checkpointing)
- Existing comic LoRAs available (Retro Comic Flux, Storyboarding v2.0) — format compatibility with FLUX.2 LoRAs TBD
- Custom LoRA training feasible on-device via the library itself

**Limitation** (verified): Neither flux.swift nor flux-2-swift-mlx supports multi-LoRA composition at runtime. To combine style + character, LoRA weights must be **pre-merged** before inference. This is acceptable for v1.0.

**LoRA categories**:
- **Style LoRA**: Art style (e.g., noir comic, manga, watercolor storyboard)
- **Character LoRA**: Per-character appearance consistency
- **Combined LoRA**: Pre-merged style + character for production use

### AD-4: Prompt File Format (YAML via Universal)

**Decision**: Prompts are defined in a structured YAML file, parsed via `marcprux/universal`.

**Rationale**:
- Plain text (one prompt per line) is too limited for production use
- Need to associate per-panel metadata: style overrides, character references, composition hints, output dimensions
- YAML is human-friendly for authoring (comments, multiline, no quotes required)
- Can be generated from `.fountain` screenplay files in Produciesta
- `marcprux/universal` is zero-dependency, Apache-2.0, cross-platform, supports JSON/YAML/XML/Plist
- Codable integration via JSON intermediary: `try MyType(json: YAML.parse(data).json())`

**Format** (see detailed spec in Requirements):

```yaml
project:
  title: "Scene 5 - The Confrontation"
  style: "noir-comic"
  characters:
    - name: "Detective Vale"
      references: ["characters/vale-sheet.png"]
      lora: "loras/vale-v2.safetensors"
    - name: "The Stranger"
      references: ["characters/stranger-sheet.png"]

panels:
  - prompt: "Detective Vale stands in a rain-soaked alley, trench coat collar up, hand on holstered gun. Low angle, dramatic shadows."
    aspect: "16:9"
    seed: 42
  - prompt: "Close-up of The Stranger's face half-lit by a neon sign. Smirking. Rain on glasses."
    aspect: "1:1"
  - prompt: "Wide shot of both characters facing each other across the alley. Tension. Steam rising from a grate."
    aspect: "21:9"
```

### AD-5: Wrapping Flux2Pipeline

**Decision**: SwiftVinetas wraps `Flux2Pipeline` from flux-2-swift-mlx rather than building a custom pipeline.

**Rationale** (verified):
- flux-2-swift-mlx already handles: model loading, quantization, text encoding, diffusion, VAE decode, LoRA, memory optimization
- The `Flux2Pipeline` API is clean and async-native with progress callbacks
- We add value at the orchestration layer: prompt file parsing, batch sequencing, character reference management, output formatting
- Klein 4B fits in 16 GB without needing sequential component loading tricks

```
┌──────────────────────────────────────────────────────┐
│                  SwiftVinetas                          │
│                                                       │
│  ┌──────────┐   ┌───────────────┐   ┌──────────────┐ │
│  │PromptFile│   │ Flux2Pipeline  │   │ Output       │ │
│  │ Parser   │──▶│ (flux-2-swift) │──▶│ Writer       │ │
│  │ (YAML)   │   │ Klein 4B/9B    │   │ (PNG+meta)   │ │
│  └──────────┘   └───────────────┘   └──────────────┘ │
│       ▲               ▲                   │           │
│       │               │                   ▼           │
│  ┌──────────┐   ┌───────────┐      ┌───────────┐     │
│  │Character │   │LoRA       │      │ Batch     │     │
│  │References│   │(safetensors)│      │ Sequencer │     │
│  └──────────┘   └───────────┘      └───────────┘     │
└──────────────────────────────────────────────────────┘
```

### AD-6: Model Management via SwiftAcervo

**Decision**: All models (base, LoRAs, character references) managed through SwiftAcervo's shared cache.

**Rationale**:
- Consistent with SwiftBruja, mlx-audio-swift, and rest of ecosystem
- Models stored at `~/Library/SharedModels/<namespace>_<repo>/`
- Automatic download from HuggingFace on first use
- LoRAs stored alongside base models or in project-local directories

**Storage layout** (verified — SwiftAcervo is fully model-type-agnostic):
```
~/Library/SharedModels/
├── black-forest-labs_FLUX.2-klein-4B/ # Primary model
├── black-forest-labs_FLUX.2-klein-9B/ # Quality model
├── renderartist_retrocomicflux/       # Style LoRA
└── custom_vale-character-v2/          # Character LoRA
```

**Note**: flux-2-swift-mlx downloads models via its own HuggingFace integration (swift-transformers Hub). We may need to either: (a) configure its `modelsDirectory` to point at `~/Library/SharedModels/`, or (b) use SwiftAcervo for download and point flux-2-swift-mlx at the cached path. The library's v2.1.0 added custom `modelsDirectory` support for this use case.

---

## Component Architecture

### Library Layer (`SwiftVinetas`)

```
SwiftVinetas/
├── Vinetas.swift                  # Public API (static, like Bruja)
├── Core/
│   ├── StyleConfig.swift          # Style parameters (steps, guidance, seed, dimensions)
│   ├── VinetasError.swift         # Error types
│   ├── VinetasPipeline.swift      # Wraps Flux2Pipeline, orchestrates generation
│   ├── VinetasModelManager.swift  # SwiftAcervo + Flux2Pipeline model directory integration
│   ├── VinetasMemory.swift        # Memory checks (Klein 4B=16GB, 9B=24GB thresholds)
│   ├── PromptFile.swift           # YAML prompt file parser (via Universal)
│   ├── CharacterSheet.swift       # Character reference images (up to 3 per generation)
│   └── PanelOutput.swift          # Output types (CGImage → PNG data, metadata, timing)
└── LoRA/
    ├── LoRAManager.swift          # Load LoRA safetensors, configure scale
    └── LoRAConfig.swift           # Maps to flux-2-swift-mlx's LoRAConfig
```

Note: No separate Pipeline/ layer needed — flux-2-swift-mlx handles text encoding, diffusion, VAE decode, and scheduling internally via `Flux2Pipeline`.

### CLI Layer (`vinetas`)

```
vinetas/
├── VinetasCLI.swift               # Root command
├── Commands/
│   ├── Generate.swift             # Single panel from prompt
│   ├── Batch.swift                # Sequence from prompt file
│   ├── Preview.swift              # Fast preview (Schnell, 2 steps)
│   ├── Download.swift             # Download/manage models
│   ├── ListModels.swift           # Show cached models
│   ├── Train.swift                # LoRA training (future, wraps SimpleTuner)
│   └── Info.swift                 # Model info + memory estimate
```

### Public API

```swift
// One-liner (like Bruja)
let image = try await Vinetas.generate("A noir detective in a rainy alley")

// With style
let image = try await Vinetas.generate(
    "A noir detective in a rainy alley",
    style: StyleConfig(stylePrompt: "comic book, heavy inks"),
    model: .klein4b
)

// Batch from prompt file
let panels = try await Vinetas.generateFromFile(
    URL(fileURLWithPath: "scene5.yaml"),
    progress: { panel, total in
        print("Panel \(panel)/\(total)")
    }
)

// With character reference images (up to 3, via FLUX.2 image-to-image)
let panels = try await Vinetas.generateSequence(
    prompts: ["Vale enters the bar", "Vale sits at the counter", "Vale orders a drink"],
    referenceImages: [valeRefImage],  // CGImage references for consistency
    style: StyleConfig(stylePrompt: "noir comic")
)

// Model management
try await Vinetas.download(model: .klein4b)
let models = try Vinetas.listModels()
let memOK = try Vinetas.validateMemory(for: .klein4b)
```

Underlying flux-2-swift-mlx API (what we wrap):
```swift
let pipeline = try await Flux2Pipeline(model: .klein4b, quantization: .balanced)
try await pipeline.loadModels(progressCallback: { progress in ... })
pipeline.loadLoRA(LoRAConfig(filePath: "style.safetensors", scale: 0.8))
let result = try await pipeline.generateTextToImageWithResult(prompt: "...", height: 1024, width: 1024)
// or with reference images:
let result = try await pipeline.generateImageToImageWithResult(prompt: "...", images: [refImage], strength: 0.7)
```

---

## Data Flow

### Single Panel Generation (Text-to-Image)

```
Input: prompt string + StyleConfig + optional LoRA
  │
  ▼
┌─ SwiftVinetas Orchestration ─────────────────┐
│  1. Validate memory for selected model         │
│  2. Initialize Flux2Pipeline(model: .klein4b)  │
│  3. Load models (download on first use)        │
│  4. Optionally load LoRA adapter               │
└──────────────────────────────────────────────┘
  │
  ▼
┌─ Flux2Pipeline.generateTextToImage ──────────┐
│  (handled internally by flux-2-swift-mlx)      │
│  1. Text encoding via Qwen3 (single encoder)   │
│  2. Diffusion: 8 double + 48 single stream     │
│  3. VAE decode → CGImage                       │
│  4. Progress callback per step                 │
└──────────────────────────────────────────────┘
  │
  ▼
┌─ Output ─────────────────────────────────────┐
│  1. CGImage → PNG Data                         │
│  2. Write to file + metadata sidecar           │
│  3. Return PanelOutput                         │
└──────────────────────────────────────────────┘
```

### Batch Generation with Character Consistency

Using FLUX.2's multi-image conditioning (up to 3 reference images):

```
1. Parse YAML prompt file → [PanelSpec]
2. Load character reference images as CGImage array
3. For each panel:
   a. Compose prompt: panel prompt + style prompt
   b. Call pipeline.generateImageToImage(prompt:, images: refs, strength:)
   c. Optionally add generated panel to reference set for next panel
4. Output: [PanelOutput] with sequential naming (panel-001.png, panel-002.png, ...)
```

---

## Memory Management Strategy

### Model Selection by RAM (Verified)

| Available RAM | Model | Quantization | Gen Time |
|--------------|-------|-------------|----------|
| 64 GB+ | Klein 9B | bf16 | Fast |
| 32 GB | Klein 9B | qint8 | ~62s |
| 24 GB | Klein 4B | bf16 | ~26s |
| 16 GB | Klein 4B | int4 | ~26s |
| < 16 GB | Error: insufficient memory | — | — |

### Component Memory Budget (FLUX.2 Klein 4B, int4)

| Component | Size |
|-----------|------|
| Transformer (4B params) | ~2.1 GB |
| Qwen3 text encoder (4B) | ~2-4 GB |
| VAE | ~3 GB |
| Working memory | ~2-4 GB |
| **Total** | **~10-14 GB** |

Note: flux-2-swift-mlx handles memory optimization internally (LRU RoPE caching, spatial tiling VAE, fused Metal kernels). We don't need to manually manage sequential component loading for Klein 4B.

---

## LoRA Model

```swift
// flux-2-swift-mlx LoRA API (verified)
pipeline.loadLoRA(LoRAConfig(
    filePath: "/path/to/style.safetensors",  // or HuggingFace repo ID
    scale: 0.8,
    activationKeyword: "comic_style",        // prepended to prompts
    schedulerOverrides: SchedulerOverrides(numSteps: 20, guidance: 3.5)
))

// Unload when switching styles
pipeline.unloadLoRA(name: "style")
pipeline.unloadAllLoRAs()
```

**Single LoRA per generation** (verified limitation). For combined style + character, pre-merge weights offline using the library's batch weight merging feature, or apply sequentially (load style → generate → unload → load character → generate).

---

## Future Architecture (Post-1.0)

### ControlNet Integration
- Depth maps for camera angle consistency
- Pose conditioning for character positioning
- Canny edge for preserving sketch layouts

### On-Device LoRA Training
- flux-2-swift-mlx already includes LoRA training (text-to-image and image-to-image)
- `vinetas train --style ./my-art-samples/` workflow
- Gradient checkpointing reduces training memory by ~50%
- Character LoRA from reference images

### Klein 9B as Quality Tier
- Klein 9B (~62s) for final renders when quality > speed
- Klein 4B (~26s) remains the default for iteration

### Page Composition
- Panel layout engine (grid, manga, webtoon formats)
- Speech bubble placement
- Export to PDF/CBZ

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| flux-2-swift-mlx discontinued (single maintainer) | High | Medium | Fork + maintain (MIT license); our wrapper is thin |
| FLUX.2 LoRA ecosystem immature (most LoRAs are for FLUX.1) | Medium | High | Test FLUX.1 LoRA compatibility; train custom LoRAs using built-in training |
| Character consistency insufficient with 3-ref limit | Medium | Medium | Per-character LoRAs as fallback; chain panels as refs |
| 16 GB not enough for Klein 4B + working memory | Low | Low | Verified: Klein 4B int4 transformer is only 2.1 GB |
| No iOS support | Low | N/A | macOS-only scope; Core ML port as separate effort if needed |
| mlx-swift version conflicts with SwiftBruja | Medium | Medium | SwiftBruja uses >= 0.21.0, flux-2 uses >= 0.30.2; should resolve to 0.30.x+ |
| Universal package YAML parsing edge cases | Low | Low | Fallback to JSON prompt files if needed |

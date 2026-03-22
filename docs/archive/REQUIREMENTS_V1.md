# SwiftVinetas v1.0 — Requirements

## Product Vision

Generate sequences of visually consistent storyboard panels and comic art from text prompts, running entirely on-device on Apple Silicon via MLX. Delivered as a Swift library (for Produciesta integration) and a standalone CLI (for testing and independent use).

---

## Platform Requirements

| Requirement | Spec |
|------------|------|
| macOS | 26.0+ |
| Swift | 6.2+ |
| Hardware | Apple Silicon (M1 or later) |
| Minimum RAM | 16 GB (4-bit quantization) |
| Recommended RAM | 32 GB (8-bit quantization) |
| iOS/iPadOS | **Not in scope** (MLX is macOS-only) |

---

## P0 — Must Have for 1.0

### P0.1: Single Panel Generation

Generate one image from a text prompt with configurable style parameters.

- Accept a text prompt string and return PNG image data
- Configurable: inference steps, guidance scale, seed, output dimensions, negative prompt
- Default model: FLUX.2 Klein 4B int4 (fastest, lowest memory — ~26s/image, 16GB minimum)
- Output formats: PNG data (`Data`), write to file path
- Report generation metadata: duration, model used, seed, dimensions

**Acceptance**: `vinetas generate "A detective in a rainy alley" --output panel.png` produces a coherent image.

### P0.2: Batch Generation from Prompt File

Generate a sequence of panels from a structured prompt file.

- Parse YAML prompt file with project metadata and panel array
- Generate panels sequentially, writing to numbered output files
- Report progress (panel N of M, estimated time remaining)
- Support `--output-dir` for output directory

**Prompt file format (v1)**:

```yaml
version: 1
project:
  title: "Scene Title"
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

**Acceptance**: `vinetas batch scene5.yaml --output-dir ./panels/` generates N panels matching the prompt file.

### P0.3: Model Management

Download, cache, list, and validate models via SwiftAcervo.

- Download models from HuggingFace to `~/Library/SharedModels/`
- List cached models with size and download date
- Validate memory before loading (pre-flight check)
- Support at minimum: FLUX.2 Klein 4B (default), FLUX.2 Klein 9B (quality)
- Models stored via SwiftAcervo at `~/Library/SharedModels/` or flux-2-swift-mlx's configured modelsDirectory

**CLI commands**:
```
vinetas download --model klein4b
vinetas download --model klein9b
vinetas list
vinetas info --model klein4b
```

**Acceptance**: Models download, cache correctly, survive app restarts, and are discoverable by `list`.

### P0.4: Memory-Aware Pipeline

Adapt loading strategy based on available system memory.

- Pre-flight memory validation: refuse to start if model won't fit
- Sequential component loading on 16 GB systems (text encoders → unload → transformer → unload → VAE)
- Resident components on 64 GB+ systems
- Report memory strategy to user: `[SwiftVinetas] Loading strategy: sequential (16 GB available)`

**Acceptance**: Generation succeeds on 16 GB M1/M2 with 4-bit model without swap thrashing.

### P0.5: Library API

Expose a clean public API for Produciesta integration.

```swift
// Minimal: generate one panel
let png: Data = try await Vinetas.generate("prompt")

// With config
let png: Data = try await Vinetas.generate("prompt", style: config, model: modelId)

// Batch from file
let panels: [PanelOutput] = try await Vinetas.generateFromFile(url)

// Model management
try await Vinetas.download(model: modelId)
let models: [VinetasModelInfo] = try Vinetas.listModels()
let ok: Bool = try Vinetas.validateMemory(for: modelId)
```

**Acceptance**: SwiftVinetas can be added as a dependency to Produciesta's Package.swift and all public API compiles.

### P0.6: Error Handling

Structured errors for all failure modes.

- `modelNotFound` — model not downloaded
- `insufficientMemory` — not enough RAM for selected model/quantization
- `generationFailed` — inference error (bad weights, corrupted model, etc.)
- `invalidPromptFile` — prompt file parse failure
- `downloadFailed` — network/HuggingFace error

**Acceptance**: Every error case produces a human-readable message with actionable guidance.

---

## P1 — Should Have for 1.0

### P1.1: Style LoRA Support

Load and apply style LoRA adapters during generation.

- Load LoRA from local safetensors file
- Apply with configurable scale (0.0-1.0) and optional activation keyword
- Specify in prompt file or CLI flag: `--lora path/to/comic-style.safetensors --lora-scale 0.8`
- Auto-detects Diffusers and BFL LoRA formats (via flux-2-swift-mlx)
- Single LoRA per generation (verified limitation); pre-merge for combined styles

**Acceptance**: Generating with a comic-style LoRA produces visibly different style than base model.

### P1.2: FLUX.2 Klein 9B Model Support

Support the higher-quality Klein 9B model alongside Klein 4B.

- Klein 9B: ~62s/image, 4.9 GB int4, higher quality
- Klein 4B: ~26s/image, 2.1 GB int4, faster (default)
- Model selection via CLI flag or prompt file
- Requires 24 GB RAM minimum for Klein 9B at qint8

**Acceptance**: Klein 9B produces noticeably higher quality output than Klein 4B at the cost of longer generation time.

### P1.3: Seed Reproducibility

Deterministic generation from a given seed.

- Same prompt + seed + config = identical output
- Seeds recorded in output metadata
- Random seed used if not specified, reported in output for reproduction

**Acceptance**: Running the same command with `--seed 42` twice produces byte-identical PNGs.

### P1.4: Progress Reporting

Real-time progress during generation.

- Report current diffusion step out of total (e.g., "Step 12/20")
- Estimate time remaining based on elapsed steps
- Library: progress callback `(Int, Int, TimeInterval) -> Void`
- CLI: printed to stderr

**Acceptance**: User sees step-by-step progress during generation.

### P1.5: Preview Mode

Fast, low-quality preview for iteration.

- Use Klein 4B with reduced steps regardless of prompt file config
- Reduced resolution (512x512)
- `vinetas preview "prompt"` or `vinetas batch scene.yaml --preview`

**Acceptance**: Preview generates in <15s on M3 Pro, giving a rough sense of composition and content.

---

## P2 — Nice to Have for 1.0

### P2.1: Multi-Image Character Consistency

Character consistency via FLUX.2's multi-image conditioning.

- Load up to 3 character reference images per generation
- Pass as image-to-image conditioning via `Flux2Pipeline.generateImageToImage()`
- Define characters in prompt file with reference image paths
- Chain generated panels as additional references for subsequent panels

**Acceptance**: Generating 3 panels of "Vale" using reference images produces a recognizably consistent character.

### P2.2: Aspect Ratio Presets

Named presets for common panel aspect ratios.

| Preset | Ratio | Resolution |
|--------|-------|-----------|
| `square` | 1:1 | 1024x1024 |
| `wide` | 16:9 | 1344x768 |
| `ultrawide` | 21:9 | 1536x640 |
| `portrait` | 9:16 | 768x1344 |
| `panel` | 3:2 | 1216x832 |
| `strip` | 4:1 | 2048x512 |

**Acceptance**: `--aspect wide` produces 1344x768 output.

### P2.3: Output Metadata Sidecar

Write generation metadata alongside each output image.

```json
{
  "prompt": "A detective in a rainy alley",
  "model": "mzbac/flux1.schnell.4bit.mlx",
  "seed": 42,
  "steps": 4,
  "guidance": 0.0,
  "width": 1024,
  "height": 1024,
  "duration_seconds": 12.3,
  "loras": [
    {"path": "retrocomicflux", "scale": 0.8}
  ],
  "generated_at": "2026-03-09T14:30:00Z"
}
```

**Acceptance**: Each `panel-001.png` has a corresponding `panel-001.json` sidecar.

### P2.4: Makefile

Standard Makefile matching the project convention.

- `make build` — debug build via xcodebuild
- `make release` — release build
- `make test` — run tests
- `make install` — build + copy to `./bin/vinetas`
- `make clean` — clean build artifacts
- `make resolve` — resolve SPM dependencies
- `make help` — list targets

**Acceptance**: `make build && make test` succeeds.

---

## P3 — Post-1.0 Roadmap

These are explicitly **out of scope** for 1.0 but inform the architecture.

| Feature | Description |
|---------|-------------|
| **ControlNet** | Depth/pose/canny conditioning for composition control |
| **On-Device LoRA Training** | `vinetas train` using flux-2-swift-mlx's built-in training (text-to-image + image-to-image) |
| **FLUX.2 Dev 32B** | Full 32B model for maximum quality (requires 32GB+ RAM, ~35 min/image) |
| **Page Layout Engine** | Compose panels into comic pages (grid, manga, webtoon formats) |
| **Speech Bubbles** | Overlay text/dialog on panels |
| **PDF/CBZ Export** | Package pages into distributable formats |
| **Interactive Mode** | Generate → review → regenerate individual panels |
| **img2img** | Use sketch/rough layout as input, generate refined panel |
| **Upscaling** | Post-generation resolution enhancement (SeedVR2) |
| **CI/CD** | GitHub Actions with macOS-26 runner, branch protection |

---

## Quality Attributes

### Performance Targets (Based on Verified Benchmarks)

| Scenario | Target | Hardware |
|----------|--------|----------|
| Single panel (Klein 4B, int4) | < 30 seconds | M3/M4 Pro |
| Single panel (Klein 4B, int4) | < 15 seconds | M4 Max |
| Single panel (Klein 9B, qint8) | < 75 seconds | M3/M4 Pro |
| 6-panel batch (Klein 4B) | < 3 minutes | M3/M4 Pro |
| 6-panel batch (Klein 4B) | < 2 minutes | M4 Max |
| Model download (first time) | Progress reported | Any |
| Second generation (model cached) | < 3s overhead | Any |

### Reliability

- Never crash on insufficient memory — always pre-validate and report error
- Prompt file parsing errors report line number and field
- Network failures during download are retryable
- Partial batch generation saves completed panels (don't lose work)

### Usability

- Zero-config first run: `vinetas generate "prompt"` auto-downloads default model
- CLI help text for every command and flag
- Library requires one import and one function call for basic use
- Prompt file format documented with examples

---

## Dependencies (Verified)

| Package | Version | License | Purpose |
|---------|---------|---------|---------|
| `VincentGourbin/flux-2-swift-mlx` | ≥ 2.1.0 | MIT | FLUX.2 pipeline, LoRA, quantization (brings mlx-swift ≥ 0.30.2 transitively) |
| `intrusive-memory/SwiftAcervo` | main | MIT | Model download/cache/discovery |
| `apple/swift-argument-parser` | ≥ 1.3.0 | Apache-2.0 | CLI parsing |
| `marcprux/universal` | ≥ 5.3.0 | Apache-2.0 | YAML prompt file parsing |

**Rejected**: `mzbac/flux.swift` — GPL-3.0 license incompatible with Produciesta.

---

## Test Strategy

### Unit Tests
- `StyleConfig` serialization round-trip
- Prompt file parsing (valid, invalid, missing fields, overrides)
- Memory estimation for different model sizes
- LoRA config validation
- Aspect ratio preset resolution calculation

### Integration Tests
- Download a model, verify it exists in SharedModels
- Generate a single panel with Schnell, verify PNG output is valid
- Generate a batch from prompt file, verify correct number of outputs
- LoRA loading and generation with style adapter

### Manual Validation
- Visual quality review of generated panels
- Character consistency across batch (Kontext)
- Style LoRA comparison (with vs without)
- Memory usage monitoring on 16 GB vs 32 GB systems

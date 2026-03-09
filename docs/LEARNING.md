# SwiftVinetas — Learning Document

> Viñetas Gráficas: On-device storyboard and comic panel generation from text prompts.

This document captures everything we learned researching the image generation landscape for Apple Silicon, as of March 2026.

---

## 1. The MLX Swift Ecosystem for Image Generation

### What Exists Today

| Project | Language | Models | Status | iOS? |
|---------|----------|--------|--------|------|
| **ml-explore/mlx-swift-examples** (StableDiffusion) | Swift | SD 2.1, SDXL Turbo | Active, official | Yes |
| **mzbac/flux.swift** | Swift (SPM) | FLUX.1 schnell/dev/Kontext | Active (v0.1.7, Jul 2025) | No |
| **VincentGourbin/flux-2-swift-mlx** | Swift | FLUX.2 Dev 32B, Klein 4B/9B | Active (v2.1.0, Feb 2026) | No |
| **argmaxinc/DiffusionKit** | Swift + Python | FLUX.1, SD3 | Stale (Dec 2024) | No |
| **apple/ml-stable-diffusion** | Swift (Core ML) | SD 2.1, SDXL, SD3 | Maintenance mode | Yes |
| **GuernikaKit** | Swift (Core ML) | SD 1.x/2.x/SDXL | Abandoned (Jun 2023) | Yes |

### Key Takeaway

There is **no single Swift package** covering FLUX.1 + FLUX.2 + SD3. The ecosystem is fragmented. After verification, the two viable options are:

- **mzbac/flux.swift** — most mature FLUX.1 package (schnell/dev/Kontext), LoRA, 4/8-bit. **BUT: GPL-3.0 license (copyleft) — cannot be linked into Produciesta without making the entire app GPL.**
- **VincentGourbin/flux-2-swift-mlx** — FLUX.2 Klein 4B/9B/Dev, LoRA loading + training, multi-image refs. **MIT license. This is our choice.**

### Licensing (Verified)

| Package | License | Produciesta-compatible? |
|---------|---------|------------------------|
| flux.swift | **GPL-3.0** | No — copyleft infects the whole app |
| flux-2-swift-mlx | **MIT** | Yes |
| mlx-swift | MIT | Yes |
| SwiftAcervo | MIT | Yes |

### Critical Platform Limitation

**MLX does not run on iOS/iPadOS.** It is macOS-only. If we ever need iPhone/iPad support, Core ML is the only path (or a custom Metal engine like Draw Things uses). For Produciesta on macOS, MLX is the right choice.

---

## 2. Model Landscape

### FLUX Family

**FLUX.1 (Aug 2024, Black Forest Labs)**
- 12B parameter rectified flow transformer
- Two text encoders: CLIP ViT-L (235M) + T5-XXL (4.7B)
- 16-channel VAE (4x more detail than SDXL's 4-channel)
- 19 double-stream + 38 single-stream transformer blocks
- Variants: **schnell** (4 steps, fast), **dev** (20-50 steps, quality), **Kontext** (multi-reference editing)

**FLUX.2 (Jan 2026)**
- 32B parameters (up from 12B)
- Single text encoder: Mistral Small 3.1 (24B VLM) replaces CLIP + T5
- 8 double-stream + 48 single-stream blocks
- Multi-reference support (up to 10 images)
- 4MP output resolution
- **Klein** variants: 4B and 9B, designed for consumer hardware
- Klein 4B at int4 fits in 16GB RAM

**FLUX.1 Kontext** — The most relevant model for our use case:
- Processes multiple reference images simultaneously
- Creates "identity vectors" from facial geometry
- 0.908 AuraFace similarity score across editing steps
- Zero-training character consistency

### Memory Requirements (FLUX.1, 12B)

| Quantization | Model Size | Minimum RAM | Gen Time (M3 Max) |
|-------------|-----------|------------|-------------------|
| FP16 | ~23 GB | 32 GB+ | ~105s |
| 8-bit | ~16 GB | 24 GB | ~90s |
| 4-bit | ~6-9 GB | 16 GB | ~60-85s |

### FLUX.2 Klein Memory (with on-the-fly quantization)

| Model | int4 | qint8 | bf16 |
|-------|------|-------|------|
| Klein 4B | 16 GB | 16 GB | 24 GB |
| Klein 9B | 16 GB | 24 GB | 32 GB |
| Dev 32B | 32 GB | 96 GB | 96 GB |

### Quantization Rules

- **Transformer and T5**: Can be aggressively quantized (4-bit/8-bit)
- **VAE**: Must stay at bf16 — visible degradation if quantized
- **CLIP**: Small enough that quantization saves little
- 8-bit is the quality sweet spot; 4-bit shows **no additional speed gain** over 8-bit on Apple Silicon (confirmed by mflux author), just lower memory

### Pre-Quantized Models on HuggingFace

| Model | Quant | Size |
|-------|-------|------|
| `mzbac/flux1.schnell.4bit.mlx` | 4-bit | ~6.7 GB |
| `mzbac/flux1.dev.4bit.mlx` | 4-bit | ~9.2 GB |
| `mzbac/flux1.kontext.4bit.mlx` | 4-bit | ~9.2 GB |
| `mzbac/flux1.kontext.8bit.mlx` | 8-bit | ~17 GB |
| `argmaxinc/mlx-FLUX.1-schnell-4bit-quantized` | 4-bit | 7.03 GB |

---

## 3. Character Consistency Techniques

This is the hardest problem in sequential image generation and the most critical for comics/storyboards.

### Approaches Ranked by Practicality

| Technique | Training? | Quality | Multi-Character | Notes |
|---|---|---|---|---|
| **FLUX Kontext** | None | Excellent | Yes (10 refs) | Best zero-training option |
| **Per-character LoRA** | 30-40 min each | Excellent | Via composition | Best for recurring characters |
| **IP-Adapter FaceID Plus** | None | Very Good | Limited | Face-only consistency |
| **StoryDiffusion** | None (zero-shot) | Good | Yes | NeurIPS 2024, pluggable |
| **CharCom** | Minimal (rank-4) | Very Good | Excellent | Composable adapters |
| **StoryMaker** | None | Very Good | Yes | Face + clothes + body |
| **CharForge** | Single image, 30-40 min | Good | Via multiple LoRAs | One ref → consistent character |

### Key Research Papers

- **StoryDiffusion** (NeurIPS 2024): "Consistent Self-Attention" — zero-shot, hot-pluggable into any SD/SDXL model
- **StoryMaker**: Preserves clothing, hairstyles, body using Positional-aware Perceiver Resampler with segmentation masks
- **CharCom** (ACM Multimedia Asia 2025): Composable rank-4 LoRA adapters per character
- **CharaConsist**: Point-tracking attention + adaptive token merge for action variations

### Recommended Strategy

1. Use **FLUX.1 Kontext** with 3-5 reference images per character stored as "character sheets"
2. For long-running series, train **per-character LoRAs** via CharForge or SimpleTuner
3. Use **ControlNet (depth + pose)** for consistent camera angles and composition

---

## 4. Comic/Storyboard-Specific LoRAs

### Available FLUX LoRAs

| LoRA | Trigger Words | Notes |
|------|--------------|-------|
| **Retro Comic Flux v2.0** | `c0m1c`, `comic book panel` | Public domain trained, well-documented |
| **Storyboarding v2.0** | `storyboarding` | Film/animation pre-production style |
| **Comic Style v1.0** | varies | Updated Aug 2025 |
| **Comic Book Illustration v1.0** | varies | Verified Jan 2025 |
| **Epic Storytelling Cinematic Comic Art** | varies | Dual-use: comic + storyboard |

The **Storyboarding v2.0** LoRA is most directly relevant — just prefix prompts with "storyboarding" to get film pre-production frames.

### Style Fine-Tuning on Apple Silicon

| Method | VRAM | Time | Output Size | Quality |
|--------|------|------|------------|---------|
| Full DreamBooth | 24-48 GB | Hours | Full model | Best |
| LoRA | 8-48 GB | 1-2 hours | 50-200 MB | Very Good |
| QLoRA (4-bit) | ~9 GB | ~41 min | 50-200 MB | Good |

**SimpleTuner** has the best Mac support: works on M2 Pro 32GB (minimum), M3/M4 Max 64GB+ recommended. FLUX LoRA training takes 8-12 hours on Mac.

**Important**: `bitsandbytes`, QLoRA, and DeepSpeed are NOT available on M-series Macs. Use Optimum-Quanto instead.

---

## 5. Composition and Layout Control

### ControlNet for FLUX

- **Canny edge**: Preserves structural outlines
- **Depth maps**: Camera perspective and spatial structure
- **OpenPose**: Character pose control
- **FLUX.1-dev-ControlNet-Union-Pro-2.0**: Unified model for Canny + Depth + Pose + Soft Edge simultaneously

### Comic Layout Tools

- **ComfyUI PanelForge**: Nodes for panel layout, speech bubbles, sequential art workflow
- **Komiko**: Infinite canvas, character database (10K characters), 90%+ visual consistency, manga/webtoon/Western layouts

### Layout Pipeline

1. Write panel descriptions (text prompts)
2. Generate rough layout sketches (or use Storyboarding LoRA)
3. Extract ControlNet conditioning from sketches
4. Generate final panels with FLUX + character LoRAs + ControlNet
5. Composite into page layout
6. Add speech bubbles and text

---

## 6. Performance Benchmarks

### FLUX on Apple Silicon

| Hardware | Model | Config | Time |
|----------|-------|--------|------|
| M4 Max 128GB | FLUX.1 Schnell | 2 steps, FP16 | ~19s |
| M4 Max | FLUX.1 Dev | Metal FlashAttention | ~85s |
| M4 Pro 64GB | FLUX.1 Schnell | 2 steps, FP16 | ~35s |
| M3 Max | FLUX.1 Dev | Metal FlashAttention | ~105s |
| M2 Max 32GB | FLUX.1 Schnell | 8-bit | ~70s |
| M1 Pro 32GB | FLUX.1 Schnell | 8-bit | ~160s |

### Realistic Per-Panel Estimates (1024x1024)

| Hardware | Optimized Config | Time/Panel |
|----------|-----------------|------------|
| M4 Max | FLUX Schnell 4-bit, 2 steps | ~10-12s |
| M4 Max | FLUX.2 Klein 4B | ~5-15s (est.) |
| M3 Pro/M2 Pro | FLUX Schnell quantized | ~30-50s |
| M1 Pro/Max | Any quantized | ~60-120s |

**For a 6-panel page**: 1-2 minutes on M4 Max, 3-5 minutes on M3/M2.

### M5 is a Generational Leap

Apple's M5 Neural Accelerators deliver 3.8-4.6x speedup over M4 for diffusion workloads via MLX. FLUX images under 1 minute on M5 iPad (if MLX gets iOS support).

---

## 7. Existing Apps and Approaches

### Draw Things (Reference Implementation)

The gold standard for on-device image generation. Uses a **custom inference engine** (libnnc/ccv + s4nnc) with Metal FlashAttention — NOT Core ML or MLX. 25% faster than mflux, 94% faster than GGUF implementations. Supports FLUX inference AND LoRA fine-tuning. Free but closed-source (only Metal FlashAttention shaders are MIT-licensed).

### Core ML vs MLX Decision

| Dimension | Core ML | MLX |
|-----------|---------|-----|
| iOS support | Yes | **No** |
| FLUX support | No | Yes |
| Model flexibility | Requires conversion | Load safetensors directly |
| Neural Engine | Yes | No (GPU only) |
| New model speed | Slow (conversion needed) | Fast |
| Quantization | 1/2/4/6/8-bit palettization | 4/8-bit on-the-fly |

**Verdict**: MLX for macOS, Core ML only if iOS needed. MLX wins for new model support and flexibility.

---

## 8. FLUX Pipeline Architecture (Technical)

### Forward Pass

1. Tokenize through CLIP + T5
2. Encode: CLIP → 768-dim pooled; T5 → 4096-dim sequence
3. Project both into shared 3072-dim space
4. Generate noise latents: `(B, 16, H/8, W/8)`
5. Create timestep + guidance embeddings (256-dim sinusoidal → MLP → 3072-dim)
6. Apply N-dimensional RoPE (4 dims: timestep, height, width, channel)
7. **19 DoubleStreamBlocks**: Parallel image/text streams, joint attention via Q/K/V concatenation
8. Concatenate image + text tokens
9. **38 SingleStreamBlocks**: Unified joint processing
10. Discard text tokens, keep image tokens
11. Adaptive LayerNorm + linear projection
12. Scheduler step (Euler flow matching)
13. Repeat 7-12 for N steps
14. VAE decode: unscale latents → conv decoder → RGB [-1,1] → [0,255] → PNG

### Scheduler

FLUX uses **FlowMatchEulerDiscreteScheduler** — fundamentally different from DDPM/DDIM/DPM++. The model predicts a constant-speed linear path between noise and data (rectified flow matching). DPM++ and similar schedulers will NOT work with FLUX.

- schnell: 4 steps, guidance_scale=0.0
- dev: 20-50 steps, guidance_scale=3.5

### LoRA Integration

LoRA targets attention projections: `to_k`, `to_q`, `to_v`, `to_out.0` across all 57 transformer blocks. With rank=4: 4.7M trainable parameters out of 11.9B total (0.04%).

Can be loaded dynamically (swap at runtime), merged/fused (max inference speed), or composed (multi-LoRA with per-adapter weights).

---

## 9. Verified Assumptions (March 2026)

### flux.swift (mzbac/flux.swift) — Verified, but GPL blocks us
- Kontext: **fully supported** since v0.1.6 (KontextImageToImageGenerator protocol)
- LoRA: safetensors only, single LoRA at a time (fused into weights), **no multi-LoRA composition**
- Models: schnell, dev, Kontext (pre-quantized 4-bit/8-bit on HuggingFace)
- SPM library product: `FluxSwift`
- mlx-swift pinned to 0.25.x (upToNextMinor)
- **License: GPL-3.0** — showstopper for Produciesta integration
- Single maintainer, last push Aug 2025

### flux-2-swift-mlx (VincentGourbin) — Verified, our primary choice
- SPM library products: **`Flux2Core`** + **`FluxTextEncoders`** (proper library, not just CLI)
- Klein 4B: **~26s/image**, transformer only 2.1 GB int4, **16 GB minimum RAM**
- LoRA: safetensors, auto-detects Diffusers and BFL formats, **loading AND training built-in**
- Multi-image conditioning: **up to 3 reference images** (image-to-image)
- mlx-swift >= 0.30.2
- macOS 14.0+, Swift 6.0
- **License: MIT** — fully compatible
- Active: v2.1.0 (Feb 2026), last commit Mar 5, 2026
- Risk: 7 stars, single maintainer

### SwiftAcervo — Verified, works as-is
- **Completely model-type-agnostic** — no LLM-specific logic
- File validation: only checks `config.json` (universal HuggingFace convention)
- Consumer specifies file list (like SwiftBruja's LLMModelFiles)
- Streaming downloads with 256KB buffered writes, progress reporting
- No size limits, no resume for partial single files
- Storage: `~/Library/SharedModels/{org}_{repo}/` — confirmed generic

### YAML Parsing — Universal package
- Using `marcprux/universal` (Apache-2.0, zero dependencies)
- Supports JSON, YAML, XML, Plist
- Codable via JSON intermediary: `try MyType(json: YAML.parse(data).json())`
- SPM: `.package(url: "https://github.com/marcprux/universal.git", from: "5.3.0")`

## 10. Key Decisions (Updated After Verification)

1. **Swift package**: **flux-2-swift-mlx** (MIT, active, Klein 4B is fast + small)
2. **Model choice**: FLUX.2 Klein 4B as primary (26s, 16GB), Klein 9B for quality, image-to-image with up to 3 refs for character consistency
3. **Platform**: macOS only (MLX limitation). iOS would require Core ML port
4. **Style system**: LoRA-based (safetensors), single LoRA per generation (can pre-merge for composition)
5. **YAML parsing**: marcprux/universal
6. **Memory target**: 16GB minimum (int4 Klein 4B), 32GB recommended (qint8 Klein 9B)
7. **Performance target**: <30s/panel on M3/M4 Pro, <15s on M4 Max

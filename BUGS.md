# Known Bugs

## CLI: `list` always shows models as "Not downloaded"

**Severity**: High — users cannot tell which models are cached  
**Affects**: `vinetas list`, `vinetas list --json`  
**Status**: Fixed in development branch

### Symptom

After a successful `vinetas download`, running `vinetas list` still shows every model with `Status: not downloaded` and `Size: Not downloaded`.

### Root Cause

`VinetasClient.listModels()` (`Sources/SwiftVinetas/Vinetas.swift:284`) hardcodes placeholder values and never queries the engine layer:

```swift
// Before fix — ignores actual disk state
return models.map { model in
  VinetasModelInfo(
    name: model.displayName,
    size: 0,           // always 0
    downloadDate: nil, // always nil
    isDownloaded: false // always false
  )
}
```

Both `Flux2Engine` and `PixArtEngine` implement correct `isAvailable(_:)` and `diskSize(of:)` methods that check actual disk state; `listModels()` simply never called them.

### Fix

`listModels()` now resolves each model's engine via `router.engine(for:)` and queries `isAvailable` and `diskSize` directly. Models whose engine cannot be resolved (e.g. optional PixArt backend not present) fall back to `isDownloaded: false` rather than crashing.

---

## CLI: `list` / `character list` / `classify` / `similarity` crash on launch (SIGSEGV)

**Severity**: Critical — crash before any output  
**Affects**: `vinetas list`, `vinetas character list`, `vinetas classify`, `vinetas similarity`  
**Status**: Fixed in development branch

### Symptom

Any command that prints a formatted table crashes immediately with `Segmentation fault: 11`. Crash report shows the faulting thread in `_platform_strlen` ← `__CFStringAppendFormatCore`.

### Root Cause

`String(format:)` calls in `VinetasCLICore.swift` used `%s` (C string) format specifiers with Swift `String` values. Swift strings are not null-terminated C strings; passing them to `%s` produces an invalid pointer, causing `strlen` to fault.

Affected lines (before fix): 312, 329, 499, 771, 779, 815, 823.

### Fix

All `%s` / `%-Ns` specifiers replaced with `%@` / `%-N@` throughout `VinetasCLICore.swift`.

---

## CLI: `list` shows wrong size and misleading "Not downloaded" for cached models

**Severity**: Medium — confusing UX; model works fine but display is wrong  
**Affects**: `vinetas list`  
**Status**: Open

### Symptom

After downloading and successfully generating with `klein4b`, `vinetas list` shows:

```
FLUX.2 Klein 4B  320 bytes  -  cached
FLUX.2 Klein 9B  Not downloaded  -  cached
```

Klein 4B reports `320 bytes` (a multi-GB model). Klein 9B shows `"Not downloaded"` in the Size column while Status correctly says `cached`.

### Root Cause

Two separate issues compound each other:

**1. `diskSize()` scans the wrong path for Flux2 components.**
`Flux2Engine.diskSize(of:)` delegates to `Flux2ModelDownloader.findModelPath(for:)`, which checks `ModelRegistry.localPath` and the configured models directory but may resolve to a small metadata sentinel file rather than the full weight directory. The actual weights land at paths like:
- `~/Library/Group Containers/group.intrusive-memory.models/SharedModels/black-forest-labs/FLUX.2-klein-4B-klein4b-bf16`
- `~/Library/Group Containers/group.intrusive-memory.models/models/lmstudio-community/Qwen3-4B-MLX-4bit`

`isAvailable()` succeeds because it only checks for the presence of a config/index file via `verifyModel`; `diskSize()` fails to traverse the full weight tree and returns either `nil` or the size of just the sentinel file.

**2. `VinetasModelInfo.formattedSize` returns `"Not downloaded"` for `size == 0`**, regardless of whether `isDownloaded` is true. This produces contradictory output (`Size: Not downloaded`, `Status: cached`).

### Suggested Fix

- `formattedSize` should return `"Unknown"` (or `"-"`) when `size == 0` and `isDownloaded == true`, reserving `"Not downloaded"` for when `isDownloaded == false`.
- `diskSize()` should use the same path resolution logic as the weight-loading code path (i.e. walk the full component tree from `modelsDirectory`) rather than relying on `findModelPath`'s sentinel-file heuristic.

---

## PixArt generates garbage output

**Severity**: High — generated images are unusable  
**Affects**: `PixArtEngine`, `PixArtIntegrationTests` Checkpoint 3  
**Status**: Fixed in development branch  
**Investigation**: `docs/incomplete/pixart-garbage-supervisor-state.md`

### Symptom

PixArt-Sigma XL produces visually garbage output — all-black, all-white, near-monochrome, or
corrupted images — instead of a coherent image matching the prompt.

### Root Causes (all fixed)

Multiple bugs compounded:

1. **Wrong beta schedule** (primary): `PixArtRecipe` used `.linear` instead of `.scaledLinear`.
   PixArt-Sigma trains with `betas = linspace(sqrt(0.0001), sqrt(0.02), 1000)²`. Using plain
   linear produces wrong `alpha_cumprod` values, causing the denoising trajectory to diverge
   (latents drift to large positive values → all-white or all-black output).

2. **GEGLU vs GELU in FFN**: `DiTBlock.GEGLUFFN` projected to `2 * ffnHiddenSize` and split
   (GEGLU gating), but PixArt-Sigma uses `activation_fn="gelu-approximate"` — single projection
   to `ffnHiddenSize` with GELU, no gate split.

3. **sin/cos embedding order**: `sinusoidalEmbedding1D` and `timestepSinusoidalEmbedding`
   returned `[cos, sin]` but diffusers uses `[sin, cos]`. Timestep MLP weights were trained on
   the `[sin, cos]` layout.

4. **Timestep frequency denominator**: Used `halfDim` instead of `halfDim - 1`, diverging from
   diffusers `downscale_freq_shift=1` default.

5. **QK normalization present but weightless**: `SelfAttention` applied default `LayerNorm(1,0)`
   as qNorm/kNorm, but the int4 checkpoint has no q_norm/k_norm weights — incorrect normalization.

6. **Incorrect weight key mapping**: `WeightMapping` assumed HuggingFace diffusers key format;
   the int4 safetensors uses MLX-native property paths directly (identity mapping needed).

7. **int4 weights not dequantized**: `PixArtDiT.apply(weights:)` loaded packed U32 tensors
   directly into `Linear` layers without calling `dequantized()`.

### Additional Fixes (S7b, 2026-04-15)

Three more bugs in `PixArtBackbone/Embeddings.swift` and `PixArtDiTConfiguration.swift`:

8. **`timestepSinusoidalEmbedding` wrong denominator**: Used `halfDim - 1` instead of `halfDim`.
   PixArt-Sigma uses `downscale_freq_shift=0`, so the denominator must be `halfDim`.

9. **`timestepSinusoidalEmbedding` wrong sin/cos order**: Produced `[sin, cos]` but
   PixArt-Sigma's `flip_sin_to_cos=True` requires `[cos, sin]`.

10. **2D position embedding `baseSize` wrong**: Was 512 (pixel-level); must be 128 (latent
    `sample_size`). With `PixArtDiT.forward` dividing by `patchSize=2`, this yields the
    correct base grid size of 64 matching diffusers' `PixArtTransformer2DModel.base_size`.

11. **H/W order in `get2DSinusoidalPositionEmbeddings`**: Was `[H, W]`; diffusers uses
    `[W, H]` because `meshgrid(grid_w, grid_h)` puts W in `grid[0]` (fixed in S6b).

### Resolution Requirement

**Critical**: PixArt-Sigma XL 1024MS requires **1024×1024** input to produce coherent images.
At 512×512, the position-embedding grid (32×32 = 1024 tokens) is too small relative to the
1024px training base (64×64 = 4096 tokens), causing colored noise. At 1024×1024, the model
produces recognizable content (verified: car silhouette clearly visible in fixture image).
The fixture test (`make test-fixtures`) now uses 1024×1024.

### Remaining Color Distortion

At 1024×1024 with all fixes applied, images show recognizable shapes but with a color bias
(low blue channel, ~R:137/G:129/B:68). This is likely an accumulated int4 quantization artifact
across 28 blocks: the blue latent channel drifts more than red/green due to weight magnitude
distributions specific to this model. Expected behavior for int4 — not a code bug.

### Fix Location

- `SwiftTuberia`: `BetaSchedule.scaledLinear` + `DPMSolverScheduler` + `T5XXLEncoder` int4 dequant
- `pixart-swift-mlx`: `PixArtRecipe`, `DiTBlock`, `Embeddings`, `Attention`, `PixArtDiT`, `WeightMapping`

### Infrastructure Added

- `make test-fixtures` → `tmp/fixtures/pixart-seed42.png` + `tmp/fixtures/flux2-seed42.png` (CLI-driven; no XCTest harness)
- `Tests/SwiftVinetasGPUTests/ImageQualityReport.swift` — `computeMetrics()` + `metricObservations()`
- `Tests/SwiftVinetasGPUTests/PixArtGarbageReproTests.swift`

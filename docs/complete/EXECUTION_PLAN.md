---
feature_name: OPERATION SKETCH FORGE
starting_point_commit: cc2f1ee6fb5df5ba76dd0e31359970802be1943a
mission_branch: mission/sketch-forge/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftVinetas

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Source Document

- **Requirements**: `docs/REQUIREMENTS_V1.md` (P0–P2 in scope; P3 explicitly out of scope)
- **Architecture**: `docs/ARCHITECTURE.md`
- **Existing scaffold**: Package.swift, stub types (Vinetas.swift, StyleConfig.swift, VinetasError.swift, PanelOutput.swift), stub CLI (VinetasCLI.swift), one test (StyleConfigTests.swift)

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|--------------|
| WU1: Core Types & Model Management | `Sources/SwiftVinetas/Core/` | 2 | 1 | none |
| WU2: Generation Pipeline | `Sources/SwiftVinetas/` | 3 | 2 | WU1 |
| WU3: CLI Implementation | `Sources/vinetas/` | 2 | 3 | WU2 |
| WU4: Understanding Module | `Sources/SwiftVinetas/Understanding/` | 4 | 2 | WU1 |
| WU5: Character Pipeline | `Sources/SwiftVinetas/Character/` | 6 | 3 | WU2, WU4 (sortie 6 only) |

---

## WU1: Core Types & Model Management

Completes the foundation types and adds model management + memory validation. Everything else depends on this.

### Sortie 1: Core Types Completion

**Priority**: 52.0 — Blocks all 16 downstream sorties; establishes foundation types reused by every work unit

**Entry criteria**:
- [ ] First sortie — no prerequisites

**Tasks**:
1. Update `StyleConfig.swift` defaults to match FLUX.2 Klein: `steps: 20`, `guidanceScale: 3.5` (current values are 30 and 7.5, which are FLUX.1/SD defaults)
2. Update `StyleConfigTests.swift` to expect the corrected defaults
3. Create `Sources/SwiftVinetas/Core/PromptFile.swift` — Codable struct parsing the YAML prompt file format v1 (project metadata with style config + panels array with per-panel overrides). Use `YAML` and `JSON` imports from Universal. Handle style inheritance: panel inherits project-level style, overrides with per-panel values.
4. Extend `VinetasModel` with computed properties: `huggingFaceRepo: String`, `minimumMemoryGB: Int`, `quantization: String`, `estimatedSecondsPerImage: Int` based on the model spec table in requirements
5. Create `Tests/SwiftVinetasTests/PromptFileTests.swift` — test valid YAML parsing, invalid YAML (error case), missing required fields, per-panel dimension overrides, style inheritance from project to panel
6. Create `Tests/SwiftVinetasTests/VinetasModelTests.swift` — test model metadata properties, CaseIterable conformance

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `StyleConfig()` default `steps` is 20 and `guidanceScale` is 3.5
- [ ] `PromptFile` successfully decodes a valid YAML string containing project metadata and 3 panels
- [ ] `VinetasModel.klein4b.minimumMemoryGB` returns 16

### Sortie 2: Model Management & Memory Validation

**Priority**: 51.25 — Blocks 15 downstream sorties; external API risk (SwiftAcervo integration)

**Entry criteria**:
- [ ] Sortie 1 exit criteria met (core types compile and test)

**Tasks**:
1. Create `Sources/SwiftVinetas/Core/VinetasModelManager.swift` — wraps SwiftAcervo's `Acervo` for FLUX.2 model download, caching at `~/Library/SharedModels/`, listing cached models with size and download date, and validating model files exist
2. Create `Sources/SwiftVinetas/Core/VinetasMemory.swift` — pre-flight memory validation. Query system physical memory via `ProcessInfo.processInfo.physicalMemory`. Compare against model requirements (Klein 4B int4: 16 GB, Klein 9B qint8: 24 GB). Return `Bool` for pass/fail and the loading strategy string ("sequential" for 16 GB, "resident" for 64 GB+)
3. Add public API methods to `Vinetas.swift`: `download(model:) async throws`, `listModels() throws -> [VinetasModelInfo]`, `validateMemory(for:) throws -> Bool`. Define `VinetasModelInfo` struct (name, size, downloadDate, isDownloaded)
4. Create `Tests/SwiftVinetasTests/VinetasMemoryTests.swift` — test memory estimation for Klein 4B (16 GB threshold), Klein 9B (24 GB threshold), test loading strategy selection
5. Create `Tests/SwiftVinetasTests/VinetasModelManagerTests.swift` — test model info struct properties, test listModels returns empty when no models cached

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `Vinetas.validateMemory(for: .klein4b)` compiles and returns a Bool
- [ ] `Vinetas.listModels()` compiles and returns `[VinetasModelInfo]`
- [ ] `Vinetas.download(model:)` compiles (may not actually download in test — SwiftAcervo dependency)
- [ ] `VinetasMemory` correctly identifies 16 GB as sufficient for Klein 4B and insufficient for Klein 9B qint8

---

## WU2: Generation Pipeline

Wires the FLUX.2 pipeline for actual image generation. Implements P0.1, P0.2, P0.4, P0.5, P1.1, P1.3, P1.4, P1.5.

### Sortie 3: Pipeline Core & Single Panel Generation

**Priority**: 42.0 — Blocks 12 downstream sorties; high risk (Flux2Pipeline integration)

**Entry criteria**:
- [ ] WU1 Sortie 2 exit criteria met (model management and memory validation available)

**Tasks**:
1. Create `Sources/SwiftVinetas/Core/VinetasPipeline.swift` — wraps `Flux2Pipeline` from Flux2Core. Manages lifecycle: init with model selection → memory validation → loadModels() → generate → return result. Reports loading strategy to stderr: `[SwiftVinetas] Loading strategy: sequential (16 GB available)`
2. Implement `Vinetas.generate(prompt:style:model:) async throws -> CGImage` — creates VinetasPipeline, validates memory, calls `pipeline.generateTextToImageWithResult(prompt:height:width:)`, constructs PanelOutput. Composes prompt by prepending style prompt to panel prompt.
3. Handle seed: if `style.seed` is set, pass to pipeline; if nil, generate random seed via `UInt64.random(in:)` and record in PanelOutput for reproducibility
4. Implement memory-aware loading: on systems with <32 GB, log sequential strategy; on 64 GB+, log resident strategy. The actual sequential loading is handled by Flux2Pipeline internally.
5. Return `CGImage` from the pipeline result, populate `PanelOutput` with all metadata (prompt, seed, duration measured via `ContinuousClock`, model, dimensions)

**Exit criteria**:
- [ ] `xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'` succeeds
- [ ] `Vinetas.generate(prompt:style:model:)` compiles and returns `CGImage`
- [ ] `VinetasPipeline` source calls `VinetasMemory` (or equivalent memory validation) before calling `loadModels()` — verify: `grep -q 'validateMemory\|VinetasMemory\|physicalMemory' Sources/SwiftVinetas/Core/VinetasPipeline.swift`
- [ ] `Vinetas.generate()` populates `PanelOutput.seed` in both code paths: when `style.seed` is provided (use it) and when it is nil (generate via `UInt64.random(in:)`)

### Sortie 4: Batch Generation, LoRA & Progress

**Priority**: 32.0 — Blocks 9 downstream sorties; establishes LoRA pattern used by character pipeline

**Entry criteria**:
- [ ] Sortie 3 exit criteria met (single generation works)

**Tasks**:
1. Implement `Vinetas.generateFromFile(_:model:progress:) async throws -> [PanelOutput]` — parse PromptFile from YAML URL, iterate panels sequentially, call pipeline for each, report progress callback with `(currentPanel, totalPanels)`, write to numbered output files if outputDir is provided
2. Implement `Vinetas.generateSequence(prompts:referenceImages:style:model:progress:) async throws -> [CGImage]` — batch from array of prompts. If referenceImages provided, use `pipeline.generateImageToImageWithResult(prompt:images:strength:)` for character consistency
3. Create `Sources/SwiftVinetas/Core/LoRAManager.swift` — load LoRA safetensors via `pipeline.loadLoRA(LoRAConfig(...))`, unload via `pipeline.unloadAllLoRAs()`. Support configurable scale (0.0-1.0) and optional activation keyword. Auto-detect Diffusers/BFL format.
4. Add LoRA parameters to `StyleConfig`: optional `loraPath: String?` and `loraScale: Float?`
5. Wire progress reporting: expose Flux2Pipeline's step-level callback as `(currentStep: Int, totalSteps: Int, elapsed: TimeInterval)` via a progress closure parameter on generate methods. Note: check Flux2Core's actual API for step-level callbacks and adapt accordingly.

**Exit criteria**:
- [ ] `xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'` succeeds
- [ ] `Vinetas.generateFromFile(_:)` compiles and accepts a URL to a YAML prompt file
- [ ] `Vinetas.generateSequence(prompts:referenceImages:)` compiles with optional reference images
- [ ] `LoRAManager` can load a LoRA config with path and scale
- [ ] `Vinetas.generateFromFile` and `Vinetas.generateSequence` each have a `progress` parameter in their signature

### Sortie 5: Output Formatting, Preview & Tests

**Priority**: 28.25 — Blocks 8 downstream sorties; establishes output patterns for CLI and character pipeline

**Entry criteria**:
- [ ] Sortie 4 exit criteria met (batch generation and LoRA compile)

**Tasks**:
1. Create `Sources/SwiftVinetas/Core/ImageOutput.swift` — `CGImage` → PNG `Data` conversion via `CGImageDestination`. Write PNG to file path. Write metadata sidecar JSON alongside PNG (prompt, model, seed, steps, guidance, dimensions, duration, LoRA info, timestamp).
2. Implement preview mode: add `Vinetas.preview(prompt:) async throws -> CGImage` — forces Klein 4B, 4 steps, 512x512, returns fast low-quality result for iteration. Add `PreviewConfig` or use `StyleConfig` with reduced parameters.
3. Aspect ratio presets: create `AspectRatio` enum with cases `.square` (1024x1024), `.wide` (1344x768), `.ultrawide` (1536x640), `.portrait` (768x1344), `.panel` (1216x832), `.strip` (2048x512). Each case provides `(width: Int, height: Int)`.
4. Create `Tests/SwiftVinetasTests/AspectRatioTests.swift` — test all preset resolutions
5. Create `Tests/SwiftVinetasTests/ImageOutputTests.swift` — test PNG data creation from a minimal CGImage, test metadata sidecar JSON structure
6. Create `Tests/SwiftVinetasTests/PromptCompositionTests.swift` — test style prompt + panel prompt composition, test LoRA activation keyword injection

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `AspectRatio.wide.width` returns 1344 and `.wide.height` returns 768
- [ ] `ImageOutput.writePNG(image:to:)` compiles and writes a PNG file
- [ ] `ImageOutput.writeMetadata(for:to:)` compiles and writes a JSON sidecar
- [ ] Preview mode generates at 512x512 with 4 steps

---

## WU3: CLI Implementation

Wires all CLI commands to the library. Implements remaining P0, P1, and P2 CLI requirements.

### Sortie 6: Core CLI Wiring

**Priority**: 4.75 — Blocks only S7; thin wiring layer over library API

**Entry criteria**:
- [ ] WU2 Sortie 5 exit criteria met (generation pipeline, output, preview all compile)

**Tasks**:
1. Update `Generate` command in `VinetasCLI.swift`: call `Vinetas.generate()` async, write PNG via `ImageOutput.writePNG()`, write metadata sidecar, print generation metadata to stderr (duration, model, seed, dimensions). Add `--steps`, `--guidance`, `--width`, `--height`, `--negative` options.
2. Update `Batch` command: call `Vinetas.generateFromFile()`, write numbered panels (`panel-001.png`, `panel-002.png`, ...) to `--output-dir`, report progress on stderr (`Panel 2/6, Step 12/20, ~30s remaining`)
3. Update `Download` command: call `Vinetas.download(model:)` async with progress reporting
4. Update `ListModels` command: call `Vinetas.listModels()`, format as table (name, size, date, status)
5. Add `Info` command: display model details (name, HuggingFace repo, size, memory requirement, estimated generation time)
6. Add `Preview` command: call `Vinetas.preview(prompt:)`, write to output path. OR add `--preview` flag to `Generate` and `Batch`.

**Exit criteria**:
- [ ] `xcodebuild build -scheme vinetas -destination 'platform=macOS'` succeeds
- [ ] All CLI commands (`generate`, `batch`, `download`, `list`, `info`, `preview`) are registered in `VinetasCLI.configuration.subcommands`
- [ ] `Generate` command accepts `--style`, `--output`, `--model`, `--lora`, `--lora-scale`, `--seed`, `--steps`, `--guidance`, `--width`, `--height`, `--negative`
- [ ] `Batch` command accepts `--output-dir`, `--model`, `--preview`
- [ ] `grep -c 'subcommands' Sources/vinetas/VinetasCLI.swift` confirms subcommand registration exists

### Sortie 7: Makefile & CLI Polish

**Priority**: 1.75 — Terminal sortie; no downstream dependents

**Entry criteria**:
- [ ] Sortie 6 exit criteria met (all CLI commands compile)

**Tasks**:
1. Create `Makefile` with targets: `build` (debug via xcodebuild), `release` (release build), `test` (run tests), `install` (build + copy to `./bin/vinetas`), `clean` (clean build artifacts), `resolve` (resolve SPM dependencies), `help` (list targets)
2. Add `--aspect` option to `Generate` and `Batch` commands: accepts preset name (square, wide, ultrawide, portrait, panel, strip) and maps to dimensions via `AspectRatio`
3. Ensure all error cases produce human-readable messages with actionable guidance (per P0.6) — verify `VinetasError.errorDescription` covers all cases with specific recovery instructions
4. Add `--json` flag to `ListModels` for machine-readable output
5. Ensure `Generate` command calls `Vinetas.download(model:)` before generation if model is not cached (zero-config first run per Usability requirements) — verify by reading source that the download-if-missing path exists in the Generate command's `run()` method

**Exit criteria**:
- [ ] `make build` succeeds
- [ ] `make test` succeeds
- [ ] `make help` lists all available targets
- [ ] `Makefile` exists at project root with all 7 required targets (`build`, `release`, `test`, `install`, `clean`, `resolve`, `help`)
- [ ] `grep -q 'aspect' Sources/vinetas/VinetasCLI.swift` confirms `--aspect` option exists

---

## WU4: Understanding Module

Implements P2.5 (ViT-B/16 classification, DINOv2 feature extraction, cosine similarity). Runs in parallel with WU2 since it only depends on WU1.

### Sortie 8: Vision Transformer Architecture

**Priority**: 21.0 — Blocks 5 downstream sorties; high risk (MLXNN model implementation)

**Entry criteria**:
- [ ] WU1 Sortie 2 exit criteria met (core types and model management available)

**Tasks**:
1. Create `Sources/SwiftVinetas/Understanding/EncoderBlock.swift` — MLXNN Module: pre-norm LayerNorm → MultiHeadAttention (12 heads, 768-d) → residual → LayerNorm → MLP (768 → 3072 → 768, GELU) → residual
2. Create `Sources/SwiftVinetas/Understanding/VisionTransformer.swift` — MLXNN Module: `Conv2d(3, 768, kernel=16, stride=16)` patch embedding, learnable CLS token parameter, positional embedding parameter `[1, 197, 768]`, 12 `EncoderBlock` layers via Sequential, final LayerNorm, optional `Linear(768, numClasses)` classification head (Identity when numClasses=0)
3. Create `Sources/SwiftVinetas/Understanding/Classification.swift` — `@frozen public struct Classification: Sendable { public let label: String; public let confidence: Float }`. Add Codable conformance.
4. Create `Tests/SwiftVinetasTests/ClassificationTests.swift` — test Sendable conformance (assign across actors), test Codable round-trip, test sorting by confidence

**Exit criteria**:
- [ ] `xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'` succeeds
- [ ] `VisionTransformer` struct conforms to MLXNN `Module` protocol
- [ ] `EncoderBlock` has `attention` (MultiHeadAttention), `mlp`, and two `LayerNorm` properties
- [ ] `Classification` is `@frozen`, `Sendable`, and `Codable`
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes Classification tests

### Sortie 9: Image Preprocessing

**Priority**: 16.75 — Blocks 3 downstream sorties; preprocessing foundation for both classifier and feature extractor

**Entry criteria**:
- [ ] Sortie 8 exit criteria met (VisionTransformer compiles)

**Tasks**:
1. Create `Sources/SwiftVinetas/Understanding/ImagePreprocessor.swift` — struct with configurable parameters: `inputSize: Int`, `cropRatio: Float`, `interpolation: Interpolation` (bilinear/bicubic), `mean: [Float]`, `std: [Float]`
2. Implement `preprocess(image: CGImage) -> MLXArray`: resize shortest edge to `ceil(inputSize / cropRatio)` using bicubic interpolation → center crop to `inputSize x inputSize` → convert to float32 [0,1] → normalize with ImageNet mean=[0.485, 0.456, 0.406] and std=[0.229, 0.224, 0.225] → NHWC format `[1, H, W, 3]`
3. Define `PreprocessingConfig` with static presets: `.vitB16` (input 224, bicubic), `.dinov2B14` (input 518, bicubic)
4. Create `Tests/SwiftVinetasTests/ImagePreprocessorTests.swift` — test output shape is `[1, 224, 224, 3]` for ViT config, `[1, 518, 518, 3]` for DINOv2 config. Test value range after normalization (not all zeros, values in expected range). Use a synthetic solid-color CGImage as test input.

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `ImagePreprocessor(config: .vitB16).preprocess(image:)` returns MLXArray with shape `[1, 224, 224, 3]`
- [ ] `ImagePreprocessor(config: .dinov2B14).preprocess(image:)` returns MLXArray with shape `[1, 518, 518, 3]`

### Sortie 10: Image Classifier & Labels

**Priority**: 9.0 — Blocks S17 (character verification); establishes classification API

**Entry criteria**:
- [ ] Sortie 9 exit criteria met (preprocessing produces correct tensor shapes)

**Tasks**:
1. Create `Sources/SwiftVinetas/Understanding/ImageNetLabels.swift` — static array of 1000 ImageNet-1K class labels. Verify 1000 entries, no duplicates.
2. Create `Sources/SwiftVinetas/Understanding/ImageClassifier.swift` — loads ViT-B/16 weights from `mlx-vision/vit_base_patch16_224-mlxim` via SwiftAcervo, preprocesses input, runs forward pass, returns top-K `[Classification]` with softmax confidence scores
3. Add public API to `Vinetas.swift`: `classify(image:) async throws -> [Classification]`, `classify(file:) async throws -> [Classification]`
4. Create `Tests/SwiftVinetasTests/ImageNetLabelsTests.swift` — test 1000 entries, no duplicates

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `Vinetas.classify(image:)` compiles and returns `[Classification]`
- [ ] ImageNet labels array has exactly 1000 entries with no duplicates
- [ ] `ImageClassifier` references `VisionTransformer` and `ImagePreprocessor`

### Sortie 11: Feature Extractor & Similarity

**Priority**: 8.0 — Blocks S17 (character verification); establishes feature extraction + similarity scoring used by character pipeline

**Entry criteria**:
- [ ] Sortie 10 exit criteria met (classifier compiles, ImageNet labels verified)

**Tasks**:
1. Create `Sources/SwiftVinetas/Understanding/FeatureExtractor.swift` — loads DINOv2 weights from `mlx-vision/vit_base_patch14_518.dinov2-mlxim`, uses VisionTransformer with `numClasses: 0`, extracts CLS token as 768-d `[Float]` array. Implement `cosineSimilarity(_:_:) -> Float` as a standalone function.
2. Add public API to `Vinetas.swift`: `extractFeatures(from: CGImage) async throws -> [Float]`, `extractFeatures(from: URL) async throws -> [Float]`, `similarity(between:and:) async throws -> Float`
3. Add understanding models to `VinetasModel` or `VinetasModelManager` so they can be downloaded via SwiftAcervo: `vit-b16` and `dinov2-b14`
4. Create `Tests/SwiftVinetasTests/CosineSimilarityTests.swift` — test identical vectors return 1.0, orthogonal vectors return 0.0, opposite vectors return -1.0

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `Vinetas.extractFeatures(from:)` compiles and returns `[Float]`
- [ ] `Vinetas.similarity(between:and:)` compiles and returns `Float`
- [ ] `cosineSimilarity([1,0,0], [1,0,0])` returns 1.0 (unit test)
- [ ] `cosineSimilarity([1,0,0], [0,1,0])` returns 0.0 (unit test)

---

## WU5: Character Pipeline

Implements P2.6 (actor photo → reference sheets → LoRA training → consistent storyboard generation). This is the largest work unit with the most sorties.

### Sortie 12: Character Definition & CRUD

**Priority**: 20.25 — Blocks 5 downstream sorties; establishes Character model reused by all character pipeline sorties

**Entry criteria**:
- [ ] WU2 Sortie 5 exit criteria met (generation pipeline compiles and outputs work)

**Tasks**:
1. Create `Sources/SwiftVinetas/Character/Character.swift` — struct with properties: `name: String`, `slug: String`, `triggerWord: String`, `created: Date`, `sourcePhotos: [String]`, `description: String`, `lora: LoRAMetadata?`. Add YAML serialization (encode/decode `character.yaml` via Universal).
2. Define `LoRAMetadata` struct: `path: String`, `scale: Float`, `version: Int`, `trainedAt: Date?`, `trainingSteps: Int?`, `model: VinetasModel?`
3. Create `Sources/SwiftVinetas/Character/CharacterManager.swift` — manages `~/Library/SwiftVinetas/characters/<slug>/` directory tree. Methods: `createCharacter(name:photo:slug:description:)`, `listCharacters()`, `loadCharacter(slug:)`, `deleteCharacter(slug:)`. Creates subdirectories: `source/`, `references/`, `training/`, `lora/`.
4. Derive `triggerWord` from slug: `"sks_\(slug)"` (e.g., `sks_vale`)
5. Derive `slug` from name if not provided: lowercased, spaces replaced with hyphens, non-alphanumeric stripped
6. Add public API to `Vinetas.swift`: `createCharacter(name:photo:slug:)`, `listCharacters()`, `loadCharacter(slug:)`
7. Create `Tests/SwiftVinetasTests/CharacterTests.swift` — test YAML round-trip, slug derivation from name, trigger word derivation, directory structure creation (using temp directory)

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `Character` struct YAML output contains keys: `name`, `slug`, `trigger_word`, `created`, `source_photos`
- [ ] `CharacterManager.createCharacter()` creates the expected directory tree (source/, references/, training/, lora/)
- [ ] Slug "Detective Vale" → "detective-vale", trigger word → "sks_detective-vale"
- [ ] `Vinetas.createCharacter(name:photo:slug:)` compiles

### Sortie 13: Reference Sheet Generation

**Priority**: 18.25 — Blocks 4 downstream sorties; high risk (img2img prompt engineering)

**Entry criteria**:
- [ ] Sortie 12 exit criteria met (Character struct and CharacterManager work)

**Tasks**:
1. Create `Sources/SwiftVinetas/Character/ReferenceSheetGenerator.swift` — generates 4 pencil sketch reference views (front, left, right, back) from a source photograph using `Flux2Pipeline.generateImageToImageWithResult()`
2. Define `ReferenceView` enum: `.front`, `.left`, `.right`, `.back` with computed `promptSuffix: String` for each view (e.g., "front view, facing camera")
3. Compose view-specific prompts: `"pencil sketch, [view suffix], [trigger_word] [description], clean lines, white background"`
4. Configurable `strength` parameter (default 0.65) controlling fidelity to source vs. stylization
5. Save generated images to `characters/<slug>/references/{front,left,right,back}.png` at 1024x1024
6. Add `Vinetas.generateReferenceSheets(for:views:strength:model:progress:)` to public API
7. Create `Tests/SwiftVinetasTests/ReferencePromptTests.swift` — test prompt composition for each view contains the view suffix, trigger word, and "pencil sketch"

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `ReferenceSheetGenerator` compiles with `Flux2Pipeline` dependency
- [ ] Prompt for `.front` view contains "front view, facing camera" and the trigger word
- [ ] Prompt for `.back` view contains "back view, facing away" and the trigger word
- [ ] `Vinetas.generateReferenceSheets(for:views:strength:model:progress:)` compiles
- [ ] Default strength is 0.65

### Sortie 14: Training Data Preparation

**Priority**: 12.0 — Blocks 3 downstream sorties; file I/O + image processing

**Entry criteria**:
- [ ] Sortie 13 exit criteria met (reference sheets can be generated)

**Tasks**:
1. Create `Sources/SwiftVinetas/Character/TrainingDataPreparer.swift` — assembles training dataset from reference sheets with auto-generated captions
2. For each reference image in `references/`, create paired `training/{name}.png` and `training/{name}.txt`
3. Auto-generate caption format: `"sks_vale, male 40s angular jaw short dark hair, front view"` — trigger word + character description + view
4. Optionally include source photos (copy to training/ with captions)
5. Resize all images to dimensions divisible by 16 (VAE requirement)
6. Add `Vinetas.prepareTrainingData(for:includeSourcePhotos:)` to public API
7. Create `Tests/SwiftVinetasTests/TrainingDataTests.swift` — test caption generation contains trigger word, test image dimensions are divisible by 16 after resize

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] Every generated caption contains the character's trigger word
- [ ] Image dimensions after resize are divisible by 16
- [ ] Training data pairs: each `.png` has a corresponding `.txt` file with the same base name
- [ ] `Vinetas.prepareTrainingData(for:includeSourcePhotos:)` compiles

### Sortie 15: On-Device LoRA Training

**Priority**: 12.25 — Blocks 2 downstream sorties; complex training pipeline integration

**Entry criteria**:
- [ ] Sortie 14 exit criteria met (training data can be prepared)

**Tasks**:
1. Create `Sources/SwiftVinetas/Character/CharacterTrainer.swift` — wraps `LoRATrainingHelper` from Flux2Core for character LoRA training
2. Define `TrainingConfig` struct with defaults: `rank: 48`, `learningRate: 0.001`, `steps: 1500`, `batchSize: 1`, `weightDecay: 0.00015`, `gradientCheckpointing: true`, `quantization: .nf4`
3. Implement memory-optimized data preparation: encode images with VAE → unload → encode text → load transformer (via `prepareTrainingDataMemoryOptimized()` if available in Flux2Core)
4. Pre-flight memory validation: Klein 4B nf4 requires 8 GB min, int4 requires 16 GB
5. Progress reporting: current step, loss value, estimated time remaining via callback `(step: Int, totalSteps: Int, loss: Float) -> Void`
6. Save output to `characters/<slug>/lora/<slug>-v<N>.safetensors` with auto-incrementing version
7. Update `character.yaml` with LoRA metadata on successful completion
8. Add `Vinetas.trainCharacterLoRA(for:config:model:progress:) async throws -> URL` to public API

**Exit criteria**:
- [ ] `xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'` succeeds
- [ ] `CharacterTrainer` references `LoRATrainingHelper` from Flux2Core — verify: `grep -q 'LoRATrainingHelper' Sources/SwiftVinetas/Character/CharacterTrainer.swift`
- [ ] `TrainingConfig` default values match spec: rank 48, lr 0.001, steps 1500, gradient checkpointing true
- [ ] `Vinetas.trainCharacterLoRA(for:config:model:progress:)` compiles and returns `URL`
- [ ] Pre-flight memory check refuses training on systems with < 8 GB for Klein 4B nf4

### Sortie 16: Character-Aware Generation

**Priority**: 6.0 — Blocks 1 downstream sortie; integration of LoRA + trigger word into generation

**Entry criteria**:
- [ ] Sortie 15 exit criteria met (LoRA training compiles)

**Tasks**:
1. Extend `VinetasPipeline` to support character-aware generation: load character's LoRA before generation, inject trigger word at the start of the prompt
2. Support character reference images from `references/` as additional img2img conditioning alongside the LoRA
3. Extend `PromptFile` to support v2 format: add optional `characters` array at project level (each with `slug`), add optional `character: String` per panel referencing a character slug
4. Add `Vinetas.generate(prompt:character:style:model:) async throws -> CGImage` to public API — loads character LoRA, prepends trigger word, generates
5. Create `Tests/SwiftVinetasTests/CharacterPromptTests.swift` — test trigger word is prepended to prompt, test PromptFile v2 parsing with characters section

**Exit criteria**:
- [ ] `xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'` passes all tests
- [ ] `Vinetas.generate(prompt:character:style:model:)` compiles
- [ ] Trigger word `sks_vale` is prepended to prompt when character is provided
- [ ] PromptFile v2 with `characters:` section parses correctly
- [ ] Panel with `character: vale` associates with the correct character slug

### Sortie 17: Character CLI & Quality Verification

**Priority**: 3.0 — Terminal sortie; final CLI wiring + quality verification integration

**Entry criteria**:
- [ ] Sortie 16 exit criteria met (character-aware generation compiles)
- [ ] WU4 Sortie 11 exit criteria met (DINOv2 feature extraction available — for verification only; CLI commands can be stubbed if WU4 is not yet complete)

**Tasks**:
1. Add `Character` subcommand group to `VinetasCLI.swift` with subcommands: `create`, `list`, `info`, `delete`, `reference`, `prepare`, `train`, `verify`
2. Wire `character create "Name" --photo photo.jpg` to `Vinetas.createCharacter()`
3. Wire `character reference <slug>` to `Vinetas.generateReferenceSheets()` with `--views`, `--strength`, `--lora`, `--regenerate` options
4. Wire `character prepare <slug>` to `Vinetas.prepareTrainingData()` with `--include-source` flag
5. Wire `character train <slug>` to `Vinetas.trainCharacterLoRA()` with `--steps`, `--rank`, `--model`, `--resume` options
6. Wire `character verify <slug>` to DINOv2 similarity scoring (via `Vinetas.verifyCharacter()`): compute pairwise similarity of reference sheets, warn if any pair < 0.6. Add `Vinetas.verifyCharacter(_:threshold:) async throws -> VerificationReport`.
7. Add `classify`, `features`, `similarity` subcommands to CLI for Understanding module

**Exit criteria**:
- [ ] `xcodebuild build -scheme vinetas -destination 'platform=macOS'` succeeds
- [ ] `vinetas character --help` lists all character subcommands (create, list, info, delete, reference, prepare, train, verify)
- [ ] `vinetas classify --help`, `vinetas features --help`, `vinetas similarity --help` all produce help text
- [ ] All character CLI commands are registered in the subcommand configuration
- [ ] `Vinetas.verifyCharacter(_:threshold:)` compiles and returns `VerificationReport`

---

## Parallelism Structure

**Critical Path**: S1 → S2 → S3 → S4 → S5 → S12 → S13 → S14 → S15 → S16 → S17 (length: 11 sorties)

**Parallel Execution Groups**:
- **Group 1** (Layer 1 — sequential):
  - WU1: S1 → S2 (Agent 1 — supervising agent)
- **Group 2** (Layer 2 — can run in parallel after Group 1):
  - WU2: S3 → S4 → S5 (Agent 1 — **SUPERVISING AGENT ONLY**, has build/test steps)
  - WU4: S8 → S9 → S10 → S11 (Agent 2 — sub-agent creates files, supervising agent verifies builds)
- **Group 3** (Layer 3 — can run in parallel after their dependencies):
  - WU3: S6 → S7 (depends on WU2 complete) — Agent 1 or Agent 2
  - WU5: S12 → S13 → S14 → S15 → S16 (depends on WU2 complete) — Agent 1 or Agent 2
  - WU5 S17 (depends on WU5 S16 AND WU4 S11) — Agent 1

**Agent Constraints**:
- **Supervising agent**: Handles all sorties with build/compile/test verification steps
- **Sub-agents (up to 1)**: Can create source files for WU4 in parallel while supervising agent works on WU2; supervising agent verifies builds afterward

---

## Open Questions & Missing Documentation

### Resolved Items (addressed during refinement)

| Sortie | Issue Type | Original | Resolution |
|--------|-----------|----------|------------|
| S3 | Vague criterion | "wraps Flux2Pipeline with memory validation" | Replaced with grep-verifiable check for memory validation call |
| S3 | Vague criterion | "Seed is always recorded" | Replaced with specific dual-path verification (user seed vs random) |
| S7 | External dep | "auto-downloads default model" needs network | Changed to code-review: verify download-if-missing path exists in source |
| S4 | External dep | Flux2Pipeline step-level progress API undocumented | Added note: "check Flux2Core's actual API and adapt accordingly" |

### No Blocking Issues

All open questions have been resolved or have documented fallback approaches. Plan is ready for execution.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 5 |
| Total sorties | 17 |
| Dependency structure | 3 layers (WU1 → WU2/WU4 → WU3/WU5) |
| Critical path length | 11 sorties |
| Parallel opportunities | WU2 ∥ WU4 (Layer 2); WU3 ∥ WU5 (Layer 3) |
| Agent allocation | 1 supervising + 1 sub-agent |
| Existing scaffold reuse | Package.swift, 5 stub source files, 1 test file |
| Average sortie size | 23 turns (budget: 50) |

### Dependency Graph

```
Layer 1:  [WU1: Core Types & Model Management]
              │
         ┌────┴────┐
Layer 2:  [WU2: Generation]  [WU4: Understanding]
              │                    │
         ┌────┴────┐              │
Layer 3:  [WU3: CLI]  [WU5: Character Pipeline]──┘
```

### Priority Mapping

| Requirement | Sortie(s) |
|-------------|-----------|
| P0.1 Single Panel | S3, S5 |
| P0.2 Batch Generation | S4, S5 |
| P0.3 Model Management | S2 |
| P0.4 Memory-Aware Pipeline | S2, S3 |
| P0.5 Library API | S3, S4, S5, S10, S11, S12-S17 |
| P0.6 Error Handling | S1 (existing), S7 |
| P1.1 LoRA Support | S4 |
| P1.2 Klein 9B | S1 (model metadata), S2 (memory thresholds) |
| P1.3 Seed Reproducibility | S3 |
| P1.4 Progress Reporting | S4, S6 |
| P1.5 Preview Mode | S5, S6 |
| P2.1 Multi-Image Consistency | S4 (via generateSequence referenceImages) |
| P2.2 Aspect Ratio Presets | S5, S7 |
| P2.3 Metadata Sidecar | S5, S6 |
| P2.4 Makefile | S7 |
| P2.5 Understanding | S8, S9, S10, S11 |
| P2.6 Character Pipeline | S12, S13, S14, S15, S16, S17 |

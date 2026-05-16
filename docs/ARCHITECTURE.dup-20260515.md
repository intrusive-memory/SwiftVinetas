# SwiftVinetas — Architecture (Ecosystem Interface Reference)

**Companion to**: [`REQUIREMENTS.md`](REQUIREMENTS.md)
**Role in ecosystem**: Consumer layer. Translates domain concepts (styles, characters, prompts) into pipeline requests. Shields consumers from SwiftTubería internals.

---

## Dependency Position

```
SwiftVinetas
├──▶ SwiftTubería/Tubería          (DiffusionPipeline, MemoryRequirement, DeviceCapability)
├──▶ SwiftTubería/TuberíaCatalog   (shared components via PixArtRecipe)
├──▶ pixart-swift-mlx/PixArtBackbone (PixArtRecipe, PixArtDiT)
├──▶ flux-2-swift-mlx              (Flux2Pipeline — unchanged, direct dependency)
├──▶ universal                     (YAML parsing — unchanged)
└──▶ swift-argument-parser         (CLI — unchanged)
```

SwiftAcervo arrives transitively via SwiftTubería. Consumers of SwiftVinetas never see SwiftTubería.

---

## Engine Architecture

```
                    VinetasClient (public API)
                         │
                    EngineRouter
                    ╱           ╲
          PixArtEngine         Flux2Engine
          (NEW — pipeline)     (UNCHANGED — wraps Flux2Pipeline)
               │
        DiffusionPipeline<
          T5XXLEncoder,
          DPMSolverScheduler,
          PixArtDiT,
          SDXLVAEDecoder,
          ImageRenderer
        >
```

### Engine Registration (Runtime)

```swift
var engines: [any ImageGenerationEngine] = [PixArtEngine()]
if DeviceCapability.current.totalMemoryGB >= 16 {
    engines.append(Flux2Engine())
}
```

- **macOS (16+ GB)**: Both engines
- **macOS (8 GB)**: PixArt only
- **iPadOS (M-series)**: PixArt only

---

## PixArtEngine (~50 lines)

### Request Translation

| GenerationRequest (Vinetas) | DiffusionGenerationRequest (Tubería) |
|---|---|
| `prompt` (after style + trigger composition) | `prompt` |
| `negativePrompt` | `negativePrompt` |
| `width`, `height` (from AspectRatio) | `width`, `height` |
| `steps` (model default or override) | `steps` |
| `guidanceScale` (model default or override) | `guidanceScale` |
| `seed` | `seed` |
| `loRAPath` + `loRAScale` | `loRA: LoRAConfig(localPath:, scale:, activationKeyword:)` |

**Fields consumed by Vinetas before reaching pipeline**: `style`, `model`, `aspectRatio`, `characters` (used in prompt composition).

### Method Delegation

| ImageGenerationEngine Method | PixArtEngine Implementation |
|---|---|
| `loadModel(_:progress:)` | `pipeline.loadModels(progress:)` |
| `generate(request:stepProgress:)` | `pipeline.generate(request:progress:)` |
| `download(_:progress:)` | `Acervo.ensureComponentsReady(descriptor.componentIds)` |
| `isAvailable(_:)` | `descriptor.componentIds.allSatisfy { Acervo.isComponentReady($0) }` |
| `validateMemory(for:)` | `pipeline.memoryRequirement` vs `MemoryManager` |
| `diskSize(of:)` | Acervo component metadata |

### Flux2Engine (Unchanged)

Continues wrapping `Flux2Pipeline` directly. No SwiftTubería dependency. No `componentIds`. Uses its own download and availability logic.

---

## ModelDescriptor Protocol

```swift
protocol ModelDescriptor: Sendable, Identifiable where ID == String {
    var id: String { get }                    // Consumer-facing: "pixart-sigma-xl"
    var displayName: String { get }           // "PixArt-Sigma XL"
    var minimumMemoryBytes: UInt64 { get }
    var downloadSizeBytes: UInt64 { get }
    var defaultSteps: Int { get }
    var defaultGuidanceScale: Float { get }
    var supportedAspectRatios: [AspectRatio] { get }
    var componentIds: [String] { get }        // Bridge to Acervo (default: [])
}
```

### Ecosystem Instances

| Descriptor | componentIds | Engine |
|---|---|---|
| `PixArtModelDescriptor.sigmaXL` | `["pixart-sigma-xl-dit-int4", "t5-xxl-encoder-int4", "sdxl-vae-decoder-fp16"]` | PixArtEngine |
| `Flux2ModelDescriptor.klein4B` | `[]` (default — uses Flux2Pipeline's own download) | Flux2Engine |
| `Flux2ModelDescriptor.klein9B` | `[]` | Flux2Engine |

---

## Public API (Unchanged)

```swift
VinetasClient.shared.generate(prompt:style:model:)
VinetasClient.shared.generateSequence(prompts:model:progress:stepProgress:)
VinetasClient.shared.download(model:progress:)
VinetasClient.shared.listModels()
```

Consumers see zero behavioral change. The pipeline is entirely below the engine layer.

---

## Prompt Composition Flow (Stays in Vinetas)

```
triggerWord (from LoRA)
    + stylePrompt (from StyleConfig)
    + panelPrompt (from user/PromptFile)
    = composed prompt string
    → passed to engine.generate(request:)
    → engine passes to pipeline.generate(prompt:)
    → pipeline passes to TextEncoder.encode(text:)
```

Neither the pipeline nor the encoder knows about styles, characters, or panels.

---

## Data Flow: VinetasClient → CGImage

```
User: "A wizard reading a book" + comicBook style + charDesign

VinetasClient
    ├── Compose prompt: "comic book style, A wizard reading a book, ..."
    ├── Select engine via EngineRouter
    └── engine.generate(GenerationRequest)
              │
         PixArtEngine
              ├── Translate to DiffusionGenerationRequest
              └── pipeline.generate(request:)
                        │
                   DiffusionPipeline
                        ├── T5XXLEncoder.encode("comic book style, A wizard reading a book, ...")
                        ├── 20x PixArtDiT.forward() + DPMSolverScheduler.step()
                        ├── SDXLVAEDecoder.decode(latents)
                        └── ImageRenderer.render(decoded)
                              │
                              ▼
                         RenderedOutput.image(CGImage)
                              │
                   ← DiffusionGenerationResult
              │
         ← GenerationResult (Vinetas type, adds model metadata)
    │
User receives CGImage
```

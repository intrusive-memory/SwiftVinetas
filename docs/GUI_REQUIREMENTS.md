# VinetasApp — GUI Requirements

## Overview

A native macOS/iPadOS app for on-device storyboard and comic panel generation, powered by SwiftVinetas and FLUX.2 Klein models via MLX. Distributed on the Mac App Store (and potentially iPad App Store for high-memory iPad Pros).

Separate repo: `VinetasApp` (or similar). Depends on `SwiftVinetas` as a Swift package.

---

## 1. Platform & Hardware

### 1.1 Primary Platform
- **macOS 26.0+**, Apple Silicon only (M1/M2/M3/M4/M5)
- Minimum 16 GB unified memory (Klein 4B)
- Recommended 24 GB+ (Klein 9B support)

### 1.2 Stretch Goal
- **iPadOS 26.0+**, M4/M5 iPad Pro with 16 GB RAM (1TB/2TB storage configs)
- Klein 4B only on iPad (12 GB models cannot run FLUX.2)
- Requires upstream `flux-2-swift-mlx` to add iPadOS platform support

### 1.3 Pre-Flight Validation
- On launch, detect available memory and GPU capabilities
- Disable unavailable models (grey out Klein 9B if < 24 GB)
- Show clear messaging: "This device has 16 GB — Klein 4B available, Klein 9B requires 24 GB+"

---

## 2. App Architecture

### 2.1 Structure
- SwiftUI app (universal: macOS + iPadOS)
- `SwiftVinetas` imported as SPM dependency (library only, not CLI)
- MVVM or Observation framework (`@Observable` view models)
- Swift concurrency throughout (async/await, actors for pipeline state)

### 2.2 Sandboxing & App Store
- App Sandbox enabled (required for Mac App Store)
- User-selected file access for importing/exporting images
- Model cache in app container (`~/Library/Containers/...`) or shared via App Group
- No network access required after initial model download
- Entitlements: increased memory limit (`com.apple.developer.kernel.increased-memory-limit`) for iPad

### 2.3 Model Storage
- First launch: prompt user to download Klein 4B (~2.5 GB)
- Optional Klein 9B download from settings
- Show download progress with pause/resume
- Display cache size and offer "Delete Model" in settings
- Consider whether SwiftAcervo's `~/Library/SharedModels/` works inside sandbox, or if models need to live in the app container

---

## 3. Core Screens

### 3.1 Generation Studio (Main View)

The primary workspace. Two-column layout on Mac, adaptive on iPad.

#### Left Panel — Input
- **Prompt text editor** with multi-line support
  - Syntax hints or auto-complete for style keywords (stretch goal)
  - Character count / token estimate
- **Style controls**
  - Style prompt field (e.g., "noir comic book, high contrast")
  - Negative prompt field (collapsible, advanced)
- **Generation settings** (collapsible section)
  - Model picker: Klein 4B / Klein 9B (disabled if insufficient memory)
  - Aspect ratio picker: Square, Wide, Ultrawide, Portrait, Panel, Strip (visual previews)
  - Steps slider (1–50, default per model)
  - Guidance scale slider (1.0–20.0)
  - Seed field (optional, for reproducibility) with "randomize" toggle
  - Width/Height override (advanced, hidden by default)
- **LoRA style selector**
  - Browse imported .safetensors files
  - LoRA scale slider (0.0–1.0, default 0.8)
  - "Import LoRA..." button
- **Character selector** (if characters exist)
  - Thumbnail grid of available characters
  - Selected character injects trigger word + LoRA automatically
- **Reference images** (for image-to-image)
  - Drop zone for up to 3 reference images
  - Strength slider (0.0–1.0, default 0.7)
- **Generate button** (prominent)
  - "Preview" secondary button (fast: 4 steps, 512×512)

#### Right Panel — Canvas / Output
- **Live generation progress**
  - Step counter: "Step 12/28"
  - Progress bar with estimated time remaining
  - Optional: show intermediate denoising steps as they complete
- **Generated image display**
  - Full-resolution preview with zoom/pan
  - Metadata overlay (seed, model, duration, dimensions)
- **Action bar**
  - Save as PNG / JPEG / TIFF
  - Copy to clipboard
  - Send to Photos
  - "Use as Reference" (feeds back into reference images)
  - "Regenerate" (same prompt, new seed)
  - "Variations" (same seed ±1, ±2 — batch of 4)
  - Share sheet

### 3.2 Storyboard / Batch View

For generating multi-panel sequences from prompt files or manual panel lists.

- **Panel list** (left sidebar or top strip)
  - Ordered list of panels, each with its own prompt
  - Add / remove / reorder panels (drag & drop)
  - Per-panel style override (optional)
  - Per-panel character assignment
- **Storyboard canvas** (main area)
  - Grid or filmstrip layout showing all generated panels
  - Click panel to edit prompt or regenerate
  - Visual indicators: generated, pending, failed
- **Batch controls**
  - "Generate All" — sequential generation with progress
  - "Generate Selected" — only checked panels
  - Import prompt file (YAML, PromptFile v1/v2 format)
  - Export storyboard (PDF, image sequence, or prompt file)

### 3.3 Character Manager

Manage characters for consistent multi-panel generation.

- **Character list** with thumbnails
- **Create character flow**
  1. Name + description
  2. Import source photo(s)
  3. Generate reference sheets (front/left/right/back views)
  4. Review reference quality
  5. Prepare training data
  6. Train LoRA (with progress — this takes a while)
  7. Verify consistency (DINOv2 similarity scores)
- **Character detail view**
  - Source photos gallery
  - Reference sheets gallery
  - LoRA versions (with dates, training params)
  - Verification report (pass/fail, similarity scores)
  - "Test Generate" — quick generation with this character's LoRA
- **Delete character** with confirmation

### 3.4 Gallery / History

Browse previously generated images.

- **Grid view** of all generated images, sorted by date
- **Filter by**: project, character, model, date range
- **Image detail**: full metadata (prompt, style, model, seed, duration, dimensions)
- **Batch actions**: delete, export, organize into projects
- **Persistence**: Core Data or SwiftData for metadata, images on disk

### 3.5 Settings

- **Models**
  - Download / delete Klein 4B, Klein 9B
  - Cache size display
  - Model storage location (if outside sandbox)
- **Defaults**
  - Default model
  - Default aspect ratio
  - Default steps / guidance
  - Default style prompt
- **LoRA Library**
  - Import / remove .safetensors files
  - Preview thumbnails for each LoRA style
- **Performance**
  - Memory usage display (current / available)
  - Loading strategy info (sequential / balanced / resident)
  - Thermal state indicator
- **Export**
  - Default export format (PNG / JPEG / TIFF)
  - Default export quality (for JPEG)
  - Default export location
- **About**
  - Version, credits, licenses (MLX, FLUX.2 Klein, etc.)

---

## 4. Key Interactions

### 4.1 Generation Flow
1. User enters prompt (and optionally style, character, references)
2. User clicks "Generate" (or ⌘↩)
3. App validates memory availability
4. If model not loaded, show "Loading model..." with progress
5. Generation begins — show step progress and ETA
6. On completion, image appears in canvas with slide-in animation
7. Image auto-saved to gallery history
8. User can iterate: edit prompt, regenerate, create variations

### 4.2 Preview Flow
1. User clicks "Preview" (or ⌘⇧↩)
2. Always uses Klein 4B, 4 steps, 512×512
3. Completes in ~5 seconds
4. Shows low-fi preview for prompt validation
5. "Upgrade to Full" button regenerates at full quality

### 4.3 Drag & Drop
- Drop images onto reference zone → sets as reference for img2img
- Drop .safetensors file → imports to LoRA library
- Drop .yaml file → opens in Storyboard view
- Drag generated image out → exports as PNG

### 4.4 Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| ⌘↩ | Generate |
| ⌘⇧↩ | Preview (fast) |
| ⌘S | Save current image |
| ⌘C | Copy image to clipboard |
| ⌘N | New prompt (clear inputs) |
| ⌘⇧N | New panel (in storyboard mode) |
| ⌘1 | Switch to Studio view |
| ⌘2 | Switch to Storyboard view |
| ⌘3 | Switch to Characters view |
| ⌘4 | Switch to Gallery view |
| ⌘, | Settings |
| Space | Toggle image zoom (fit ↔ actual size) |

---

## 5. Data Model

### 5.1 Persistence
- **SwiftData** for metadata (prompts, settings, history)
- **File system** for generated images (organized by date/project)
- **UserDefaults** for preferences and defaults

### 5.2 Key Entities
```
Project
  - id: UUID
  - name: String
  - created: Date
  - panels: [Panel]

Panel
  - id: UUID
  - prompt: String
  - stylePrompt: String?
  - negativePrompt: String?
  - model: VinetasModel
  - aspectRatio: AspectRatio
  - steps: Int
  - guidance: Float
  - seed: UInt64?
  - characterSlug: String?
  - loraPath: String?
  - loraScale: Float
  - referenceImages: [URL]
  - generatedImage: URL?
  - generationDuration: TimeInterval?
  - generatedAt: Date?
  - status: PanelStatus (.pending, .generating, .completed, .failed)

GenerationRecord
  - id: UUID
  - panel: Panel
  - imagePath: URL
  - seed: UInt64
  - model: VinetasModel
  - duration: TimeInterval
  - width: Int
  - height: Int
  - createdAt: Date
```

---

## 6. App Store Considerations

### 6.1 Content Policy
- FLUX.2 Klein can generate any content — App Store requires content moderation
- Options:
  - Client-side NSFW classifier (e.g., NudeNet or similar CoreML model) as post-generation filter
  - Prompt keyword blocklist
  - Age rating: 12+ minimum (AI-generated imagery)
- Document content policy clearly in App Store description

### 6.2 Model Download Size
- App binary itself is small (UI + SwiftVinetas library)
- Models downloaded on-demand after install (~2.5 GB for Klein 4B)
- Clearly communicate download requirement on first launch
- Consider App Store review implications: reviewer needs Apple Silicon Mac

### 6.3 Pricing
- TBD: one-time purchase, free with IAP for Klein 9B, or subscription
- No server costs (fully on-device) — one-time purchase is natural fit

### 6.4 Privacy
- **No data leaves the device** — major selling point
- No analytics, no telemetry, no cloud processing
- Privacy nutrition label: "Data Not Collected"

---

## 7. Non-Functional Requirements

### 7.1 Performance
- Klein 4B generation: < 30 seconds on M3 Pro (target)
- Preview generation: < 8 seconds
- Model loading (cold start): < 15 seconds
- UI must remain responsive during generation (all work on background actors)
- Memory pressure handling: release model from memory if system requests it

### 7.2 Reliability
- Graceful handling of memory pressure / thermal throttling
- Generation cancellation (user can abort mid-generation)
- Crash recovery: restore last session state
- Model integrity validation (checksum on download)

### 7.3 Accessibility
- Full VoiceOver support
- Dynamic Type for all text
- High Contrast mode support
- Reduce Motion: disable animations
- Image descriptions: auto-generate alt text from prompt

### 7.4 Localization
- English first
- Localization-ready (all strings in .xcstrings)
- RTL layout support

---

## 8. Risks & Open Questions

### 8.1 Risks
1. **flux-2-swift-mlx iPadOS support** — upstream package may not declare iPadOS platform yet; may need fork or PR
2. **App Sandbox + model cache** — SwiftAcervo uses `~/Library/SharedModels/`; sandboxed apps can't access this. Need to either: use app container storage, or request a temp exception entitlement
3. **App Store review** — reviewer may not have Apple Silicon Mac; need to provide video demo
4. **Content moderation** — Apple may require NSFW filtering; need to evaluate classifiers
5. **Model size** — 2.5 GB download on first launch may deter users; need excellent onboarding UX
6. **iPad thermal throttling** — sustained GPU load on iPad may throttle after a few generations

### 8.2 Open Questions
1. App name: "Vinetas"? "Vinetas Studio"? Something else? (trademark search needed)
2. Pricing model: one-time purchase vs. free + IAP?
3. Should the app support exporting prompt files for CLI users?
4. Should there be a "Projects" concept for organizing related storyboards?
5. Is visionOS worth targeting? (MLX supports it, spatial canvas could be compelling)
6. Should we include the image classification/similarity tools from SwiftVinetas, or keep the app focused on generation?

---

## 9. MVP Scope (v1.0)

For initial App Store submission, focus on:

1. **Generation Studio** — single image generation with full controls
2. **Gallery** — history of generated images with metadata
3. **Settings** — model management, defaults
4. **Model download** — onboarding flow for Klein 4B

### Deferred to v1.1+
- Storyboard / batch view
- Character manager (create, train LoRA, verify)
- LoRA import and management
- Image-to-image with references
- iPad support
- Projects / organization

---

## 10. Tech Stack Summary

| Layer | Technology |
|-------|-----------|
| UI Framework | SwiftUI |
| State Management | Observation framework (`@Observable`) |
| Data Persistence | SwiftData |
| Image Generation | SwiftVinetas → flux-2-swift-mlx → MLX |
| Model Management | SwiftAcervo (or custom for sandbox) |
| Image I/O | CoreGraphics, ImageIO, Photos framework |
| File Access | FileManager + Security-scoped bookmarks |
| Distribution | Mac App Store (+ iPad App Store stretch) |

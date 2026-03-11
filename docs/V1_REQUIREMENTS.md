# VinetasApp v1.0 — Detailed Requirements

**Status**: DRAFT — review and refine before implementation planning.

---

## R1. Platform & Distribution

- R1.1: macOS 26.0+, Apple Silicon only (M1/M2/M3/M4/M5)
- R1.2: Distributed via Mac App Store
- R1.3: App Sandbox enabled
- R1.4: Minimum 16 GB unified memory required
- R1.5: Separate repository (`VinetasApp` or TBD name)
- R1.6: SwiftVinetas imported as SPM dependency (library target only)
- R1.7: Swift 6.2+, SwiftUI app lifecycle

---

## R2. First Launch & Onboarding

- R2.1: On first launch, show a welcome screen explaining the app requires a one-time download of its generation engine (~2.5 GB)
- R2.2: Check system memory and confirm compatibility (16 GB+)
- R2.3: If system has < 16 GB, show an error explaining the hardware requirement and exit gracefully
- R2.4: Show a "Set Up" / "Download" button with estimated size and estimated time
- R2.5: Download progress bar with percentage, bytes downloaded/total, and download speed
- R2.6: Download must be resumable (if user quits and relaunches, pick up where it left off)
- R2.7: On download completion, transition to the Generation Studio
- R2.8: If download fails, show error with retry button and guidance (check network, disk space)
- R2.9: Styles that require the higher-quality engine trigger an additional download prompt on first use (~5 GB), presented as: "This style requires additional data for best results. [Download] [Use standard quality]"
- R2.10: No model names or technical jargon in any onboarding or download UI

**Open question**: Where do models live? SwiftAcervo uses `~/Library/SharedModels/` which is outside the sandbox. Options:
  - (a) Store in app container (`~/Library/Containers/<bundle-id>/`)
  - (b) Request a temporary sandbox exception for `~/Library/SharedModels/`
  - (c) Let user pick a folder via Open Panel and use security-scoped bookmarks

---

## R3. Window & Navigation

- R3.1: Single-window app with a toolbar at the top
- R3.2: Toolbar contains navigation tabs: **Studio**, **Gallery**, **Settings**
- R3.3: Window is resizable with a minimum size of 900×600
- R3.4: Window title shows the app name; no document-based architecture in v1
- R3.5: Remember window position and size across launches
- R3.6: Support macOS full-screen mode

**Open question**: Should this be a sidebar-based NavigationSplitView or a tab-based toolbar? Sidebar feels heavier for 3 sections. Toolbar tabs (like Xcode's organizer) may be cleaner.

---

## R4. Storyboard Styles

The primary creative choice. Each style is a curated preset that bundles a style prompt, negative prompt, steps, guidance scale, and a suggested aspect ratio. The user picks a visual style and then adjusts individual parameters if they want to.

The model (Klein 4B vs 9B) and seed are **not user-facing concepts**. The app selects the best model for each style automatically and manages seeds internally. Users never see model names or seed values as input controls.

### R4.1 Built-in Styles

Each style ships with the app. Stored as bundled data (JSON or code), not user-editable in v1.

Every style defines:
- **Name**: Display name
- **Description**: One-line explanation of the look
- **Thumbnail**: Example image showing the style (bundled asset, not generated at runtime)
- **Style prompt**: The `stylePrompt` string prepended to every generation
- **Negative prompt**: The `negativePrompt` string
- **Model** (internal): Which model produces the best results for this style — never shown to the user
- **Steps**: Default inference steps tuned for this style
- **Guidance scale**: Default guidance tuned for this style
- **Suggested aspect ratio**: The aspect ratio that works best with this style (user can override)

#### Styles:

| # | Style Name | Description | Steps | Guidance | Suggested Aspect |
|---|-----------|-------------|-------|----------|-----------------|
| 1 | **Comic Book** | Bold outlines, flat colors, classic comic panel look | 20 | 3.5 | Panel (1216×832) |
| 2 | **Gritty Noir** | High-contrast black & white, heavy shadows, gritty crime noir style | 25 | 4.0 | Wide (1344×768) |
| 3 | **Cinematic Storyboard** | Loose pencil sketches on white, film preproduction boards | 18 | 3.0 | Wide (1344×768) |
| 4 | **Manga** | Japanese manga style, screentones, dynamic angles, B&W ink | 22 | 3.5 | Portrait (768×1344) |
| 5 | **Watercolor Concept** | Soft washes, painterly edges, concept art feel | 28 | 4.5 | Square (1024×1024) |
| 6 | **Graphic Novel** | Detailed, painted panels, European BD / Moebius-influenced | 30 | 5.0 | Panel (1216×832) |
| 7 | **Animated** | Clean lines, vibrant colors, Pixar/Disney preproduction style | 20 | 3.5 | Wide (1344×768) |
| 8 | **Thumbnail Rough** | Quick gestural sketches, stick figures, blocking-only | 8 | 2.0 | Wide (1344×768) |

### R4.2 Style Selection UI

- R4.2.1: Style picker displayed as a horizontal scrolling strip of thumbnail cards at the top of the left panel
- R4.2.2: Each card shows: thumbnail image, style name, one-line description
- R4.2.3: Selected style has a highlighted border / selection ring
- R4.2.4: Selecting a style populates all generation settings (style prompt, negative prompt, steps, guidance, aspect ratio) with that style's defaults
- R4.2.5: User can modify any setting after selecting a style — changes are per-session overrides, not saved back to the style
- R4.2.6: If the selected style's internal model requires an additional download, show an inline prompt: "This style requires additional data to produce the best results. [Download (~5 GB)] [Use standard quality instead]"
- R4.2.7: No model names (Klein 4B, Klein 9B) appear anywhere in the user-facing UI — these are implementation details
- R4.2.8: A "Modified" badge appears on the style card when user has changed any setting from the style's defaults
- R4.2.9: "Reset to Style Defaults" button appears when settings are modified

### R4.3 Style Data Structure

```swift
struct StoryboardStyle: Identifiable, Codable {
    let id: String                    // e.g., "gritty-noir"
    let name: String                  // e.g., "Gritty Noir"
    let description: String           // e.g., "High-contrast B&W, heavy shadows"
    let thumbnailAsset: String        // Bundle asset name
    let stylePrompt: String           // Maps to StyleConfig.stylePrompt
    let negativePrompt: String?       // Maps to StyleConfig.negativePrompt
    let steps: Int                    // Maps to StyleConfig.steps
    let guidanceScale: Float          // Maps to StyleConfig.guidanceScale
    let suggestedAspectRatio: String  // "square", "wide", etc.

    // Internal only — never exposed in UI
    let internalModel: String         // "klein4b" or "klein9b"
    let requiresAdditionalDownload: Bool  // true if internalModel is 9B
}
```

---

## R5. Generation Studio

The main view. User picks a style, enters a prompt, adjusts settings, generates an image.

### R5.1 Layout

- R5.1.1: Two-column layout — input panel on the left, canvas on the right
- R5.1.2: Left panel has a fixed width (300–400pt) with the right panel filling remaining space
- R5.1.3: Divider between panels is draggable to resize
- R5.1.4: On narrow windows (< 1000pt), left panel collapses to a sheet/popover triggered by a toolbar button

### R5.2 Left Panel — Top to Bottom

The left panel contains all user inputs in this order:

#### 1. Style Picker (R4.2)
Horizontal scrolling strip at the top.

#### 2. Prompt Input

- R5.2.1: **Prompt** — multi-line text editor, minimum 3 lines visible, grows to ~8 lines
- R5.2.2: Placeholder text: "Describe what you want to see..."
- R5.2.3: This is the per-panel prompt. The style prompt is prepended automatically during generation.

#### 3. Style Prompt (editable)

- R5.2.4: **Style prompt** — single-line TextField, pre-populated from selected style
- R5.2.5: Label: "Style Prompt" with a subtle note: "Prepended to your prompt"
- R5.2.6: User can edit this to tweak the style without changing the base style selection
- R5.2.7: Editing this marks the style as "Modified"

#### 4. Negative Prompt

- R5.2.8: **Negative prompt** — single-line TextField, pre-populated from selected style
- R5.2.9: Hidden by default behind a disclosure triangle "Negative Prompt"
- R5.2.10: Placeholder: "Things to avoid in the image"
- R5.2.11: Editing this marks the style as "Modified"

#### 5. Aspect Ratio

- R5.2.12: **Aspect ratio picker** — grid of visual shape thumbnails (2×3 grid or horizontal strip)
- R5.2.13: Pre-selected to the style's suggested aspect ratio
- R5.2.14: Six options with labels:
  - Square (1024×1024)
  - Wide (1344×768)
  - Ultrawide (1536×640)
  - Portrait (768×1344)
  - Panel (1216×832)
  - Strip (2048×512)
- R5.2.15: Selecting an aspect ratio sets width and height automatically
- R5.2.16: Changing from the style's suggestion marks the style as "Modified"

#### 6. Generation Parameters (collapsible "Advanced" section)

- R5.2.17: **Steps slider** — range 1–50, pre-populated from style
- R5.2.18: Show numeric value next to slider; allow direct text entry in the numeric label
- R5.2.19: **Guidance scale slider** — range 1.0–20.0, step 0.5, pre-populated from style
- R5.2.20: Show numeric value next to slider; allow direct text entry in the numeric label
- R5.2.21: **Width field** — integer, pre-populated from aspect ratio, must be multiple of 64
- R5.2.22: **Height field** — integer, pre-populated from aspect ratio, must be multiple of 64
- R5.2.23: Editing width/height directly clears the aspect ratio selection (shows "Custom")
- R5.2.24: Width/height snap to nearest multiple of 64 on focus loss
- R5.2.25: Changing steps, guidance, width, or height from style defaults marks as "Modified"
- R5.2.26: **No seed control** — seed is managed automatically by the app; the user does not select or enter seeds

#### 7. Generate Actions

- R5.2.29: **"Generate" button** — large, prominent, primary style, full width of left panel
- R5.2.30: Keyboard shortcut: ⌘↩
- R5.2.31: Button disabled when prompt is empty
- R5.2.32: Button disabled while generation is in progress
- R5.2.33: While generating, button text changes to "Cancel" with a stop icon
- R5.2.34: Clicking "Cancel" aborts the current generation (if supported by SwiftVinetas)
- R5.2.35: **"Preview" button** — secondary style, below Generate
- R5.2.36: Keyboard shortcut: ⌘⇧↩
- R5.2.37: Preview always uses the fast engine, 4 steps, 512×512 regardless of style/settings
- R5.2.38: Preview completes in ~5 seconds; useful for validating prompt composition

### R5.3 Right Panel — Canvas

- R5.3.1: **Empty state** — centered placeholder: "Enter a prompt and click Generate" with subtle icon
- R5.3.2: **During generation** — progress indicator:
  - Circular or linear progress bar
  - "Step 12 of 28" text
  - Elapsed time
  - Estimated time remaining (based on avg step duration so far)
- R5.3.3: **Generated image** — centered, scaled to fit canvas while maintaining aspect ratio
- R5.3.4: Click-to-zoom: toggle between fit-to-canvas and actual-size (1:1 pixels)
- R5.3.5: In actual-size mode, image is scrollable/pannable
- R5.3.6: Keyboard shortcut: Space to toggle zoom
- R5.3.7: **Metadata bar** below image: style name, dimensions, generation time
- R5.3.8: Seed is stored internally in the generation record for reproducibility but is not displayed in the metadata bar

### R5.4 Image Actions

Action bar below/above the canvas after an image is generated.

- R5.4.1: **Save** (⌘S) — save to disk; show save panel with default filename `vinetas-<timestamp>.png`
- R5.4.2: **Copy** (⌘C) — copy image to system clipboard
- R5.4.3: **Share** — macOS share sheet (AirDrop, Messages, Mail, etc.)
- R5.4.4: **Regenerate** — re-run with same prompt and settings but a new random seed
- R5.4.5: **Save to Photos** — add to system Photos library (requires permission)
- R5.4.6: **Drag out** — user can drag the generated image from the canvas to Finder or other apps

**Open question**: Should "Variations" (generate 4 images at seed ±1, ±2) be in v1, or deferred?

---

## R6. Gallery

Browse and manage all previously generated images.

### R6.1 Layout

- R6.1.1: Grid of image thumbnails, 3–6 columns depending on window width
- R6.1.2: Each thumbnail shows the image scaled to fill a square cell
- R6.1.3: Hover over a thumbnail to see the prompt as a tooltip
- R6.1.4: Thumbnails sorted by generation date, newest first

### R6.2 Image Detail

- R6.2.1: Clicking a thumbnail opens a detail view (inline expansion, sheet, or full-canvas view)
- R6.2.2: Detail view shows: full image, prompt, style name, style prompt, negative prompt, dimensions, steps, guidance, generation time, date
- R6.2.3: From detail view: Save, Copy, Share, Delete, "Open in Studio"
- R6.2.4: "Open in Studio" loads the style, prompt, and all settings back into the Studio for re-generation or iteration

### R6.3 Management

- R6.3.1: Multi-select thumbnails (⌘-click or ⇧-click)
- R6.3.2: Batch delete with confirmation ("Delete 5 images?")
- R6.3.3: Batch export — save selected images to a folder

### R6.4 Persistence

- R6.4.1: Store generation metadata in SwiftData
- R6.4.2: Store generated images as PNG files in the app's container
- R6.4.3: Thumbnail cache for fast gallery loading (smaller ~256px versions)
- R6.4.4: Gallery loads and scrolls smoothly with hundreds of images (lazy loading)

**Open question**: Should there be search/filter in v1 (by prompt text, style, date range)? Or is chronological scroll sufficient for launch?

---

## R7. Settings

### R7.1 Storage

- R7.1.1: Show total storage used by generation engine data (models) and generated images, without exposing model names
- R7.1.2: "Manage Storage" section showing: "Generation Engine: X.X GB", "Generated Images: X.X GB"
- R7.1.3: "Clear Engine Data" button to delete downloaded model files (with confirmation warning that styles requiring additional data will need to re-download)
- R7.1.4: Download progress for any pending model downloads (triggered from style selection, not from settings)

### R7.2 Defaults

- R7.2.1: Default style picker (which style is selected when Studio opens)
- R7.2.2: "Reset to Defaults" button

### R7.3 Export

- R7.3.1: Default image format picker: PNG (lossless) / JPEG / HEIC
- R7.3.2: JPEG/HEIC quality slider (0.0–1.0) — only visible when JPEG or HEIC selected
- R7.3.3: Default save location (folder picker with security-scoped bookmark)

### R7.4 System Info

- R7.4.1: Display: chip name (e.g., "Apple M4 Pro"), total unified memory
- R7.4.2: Display which styles are available on this hardware (styles requiring 9B are unavailable on < 24 GB machines, with a note: "Some styles require 24 GB or more")
- R7.4.3: Storage location on disk

### R7.5 About

- R7.5.1: App version and build number
- R7.5.2: Credits: SwiftVinetas, MLX, FLUX.2 Klein, and other dependencies
- R7.5.3: Link to licenses
- R7.5.4: Link to support / feedback

---

## R8. State Management & Architecture

- R8.1: SwiftUI with `@Observable` view models (Observation framework)
- R8.2: `GenerationViewModel` — owns selected style, prompt, all settings, generation state, current image
- R8.3: `GalleryViewModel` — queries SwiftData for generation records, manages selection
- R8.4: `SettingsViewModel` — reads/writes UserDefaults, manages model downloads
- R8.5: `StyleManager` — loads built-in styles, resolves style + user overrides into a `StyleConfig`
- R8.6: `ModelManager` actor — wraps `Vinetas.download()`, `Vinetas.listModels()`, `Vinetas.validateMemory()`; serializes model operations
- R8.7: All generation work runs on a background Task; UI never blocks
- R8.8: Generation progress callbacks update published properties on `@MainActor`
- R8.9: App state (current prompt, selected style, setting overrides) persisted so it survives quit/relaunch

---

## R9. Data Model (SwiftData)

```
@Model GenerationRecord
  - id: UUID
  - prompt: String                  // The user's prompt text
  - styleId: String                 // e.g., "gritty-noir"
  - styleName: String               // e.g., "Gritty Noir" (denormalized for display)
  - stylePrompt: String             // The actual style prompt used (may differ from style default)
  - negativePrompt: String?         // The actual negative prompt used
  - steps: Int                      // Inference steps used
  - guidanceScale: Float            // Guidance scale used
  - width: Int                      // Output width in pixels
  - height: Int                     // Output height in pixels
  - durationSeconds: Double         // How long generation took
  - imagePath: String               // relative path within app container
  - thumbnailPath: String           // relative path to thumbnail
  - createdAt: Date

  // Internal fields — stored for reproducibility but not displayed in UI
  - seed: UInt64                    // Auto-generated seed (not user-facing)
  - modelName: String               // "klein4b" or "klein9b" (not user-facing)
```

- R9.1: Automatic thumbnail generation on save (256×256, JPEG)
- R9.2: Cascade delete: deleting a GenerationRecord also deletes the image and thumbnail files
- R9.3: Index on `createdAt` for sorted gallery queries
- R9.4: Store the full resolved style prompt (not just the style ID) so the record is self-contained even if styles change in future app updates

---

## R10. Generation Flow — How Style Becomes an Image

This documents the data flow from UI to SwiftVinetas API:

1. User selects a `StoryboardStyle` (e.g., "Gritty Noir")
2. Style's defaults populate: stylePrompt, negativePrompt, steps, guidanceScale, suggestedAspectRatio → width/height
3. User enters a prompt (e.g., "A detective crouches behind a dumpster in a rain-soaked alley")
4. User optionally modifies style prompt, negative prompt, aspect ratio, steps, or guidance
5. User clicks "Generate"
6. App resolves final `StyleConfig`:
   ```
   StyleConfig(
       stylePrompt: <stylePrompt field value>,
       negativePrompt: <negativePrompt field value or nil>,
       steps: <steps slider value>,
       guidanceScale: <guidance slider value>,
       seed: nil,        // always random — managed by app
       width: <width value>,
       height: <height value>
   )
   ```
7. App determines model internally from style's `internalModel` — if not downloaded, either trigger download or fall back to standard quality
8. App calls `Vinetas.generate(prompt:style:model:)` with the user's prompt, resolved StyleConfig, and internally-selected model
9. SwiftVinetas prepends `stylePrompt` to `prompt` internally: `"<stylePrompt>, <userPrompt>"`
10. Generation runs; progress callbacks update the UI
11. On completion, image + metadata (including the auto-generated seed) saved to SwiftData and displayed on canvas
12. Seed is recorded in the `GenerationRecord` for internal reproducibility but not shown to the user

---

## R11. Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| ⌘↩ | Generate | Studio |
| ⌘⇧↩ | Preview | Studio |
| ⌘S | Save current image | Studio |
| ⌘C | Copy image to clipboard | Studio / Gallery detail |
| ⌘N | Clear prompt and reset style to defaults | Studio |
| ⌘, | Open Settings | Global |
| ⌘⌫ | Delete selected images | Gallery |
| Space | Toggle image zoom | Studio |
| ⌘1 | Switch to Studio | Global |
| ⌘2 | Switch to Gallery | Global |
| ⌘3 | Switch to Settings | Global |
| Escape | Cancel generation | Studio (during generation) |

---

## R12. Error Handling

- R12.1: **Insufficient memory** — alert with explanation and suggestion to close other apps
- R12.2: **Additional data needed** — inline message: "This style requires additional data. [Download Now]" (triggered when style needs 9B engine)
- R12.3: **Generation failed** — alert with error message from `VinetasError.generationFailed`; offer "Try Again"
- R12.4: **Download failed** — alert with retry button; preserve download progress if possible
- R12.5: **Disk full** — alert when saving images or downloading models
- R12.6: **Invalid dimensions** — if user enters width/height not divisible by 64, snap to nearest valid value with a brief toast
- R12.7: All errors presented as non-modal alerts (not blocking the main window)

---

## R13. Performance Requirements

- R13.1: App launch to Studio view: < 2 seconds (model NOT loaded)
- R13.2: Model loading (cold start, first generation): < 15 seconds
- R13.3: Klein 4B generation at 1024×1024, 20 steps: < 30 seconds on M3 Pro
- R13.4: Preview generation: < 8 seconds
- R13.5: Gallery scrolling: 60 fps with 500+ images (lazy loading + thumbnail cache)
- R13.6: UI remains responsive at all times during generation (no main thread blocking)
- R13.7: Memory: app should not exceed model memory + 500 MB for UI/overhead
- R13.8: Style switching is instant (no engine reload unless the new style uses a different internal model than the previous one)

---

## R14. App Store Requirements

### R14.1 Content Moderation

- R14.1.1: FLUX.2 Klein is uncensored — Apple requires age-appropriate content
- R14.1.2: Age rating: 17+ (unrestricted web access equivalent, since user controls prompts)
- R14.1.3: App Store description must disclose AI-generated content capability

**Open question**: Does Apple require active content filtering for generative AI apps, or is a 17+ rating sufficient? This needs research with current App Store Review Guidelines (section 4.7 on generative AI). A client-side NSFW classifier adds significant complexity.

### R14.2 Privacy

- R14.2.1: No data collected — everything runs on-device
- R14.2.2: Privacy nutrition label: "Data Not Collected"
- R14.2.3: No analytics, telemetry, or crash reporting in v1
- R14.2.4: Network access only for model download (from HuggingFace)

### R14.3 Review Considerations

- R14.3.1: App review requires Apple Silicon Mac — prepare a video walkthrough for review notes
- R14.3.2: Include demo prompt + suggested style in review notes so reviewer can test
- R14.3.3: Handle the case where reviewer's Mac has < 16 GB gracefully (clear error, not crash)

---

## R15. Accessibility

- R15.1: Full VoiceOver support for all interactive elements
- R15.2: Generated images get accessibility label from their prompt text
- R15.3: Progress announcements during generation ("Generation started", "Step 10 of 20", "Generation complete")
- R15.4: All controls labeled with accessibility identifiers
- R15.5: Dynamic Type support for all text
- R15.6: High Contrast mode: ensure all controls visible
- R15.7: Reduce Motion: disable any animations (image transitions, progress animations)
- R15.8: Style thumbnails have accessibility labels with style name and description

---

## R16. Out of Scope for v1.0 (Deferred)

These are explicitly NOT in v1. Listed here to prevent scope creep.

- R16.1: ~~Storyboard / batch multi-panel generation~~
- R16.2: ~~Character creation, LoRA training, reference sheets~~
- R16.3: ~~Custom LoRA import and management~~
- R16.4: ~~Image-to-image generation with reference images~~
- R16.5: ~~iPad / iPadOS support~~
- R16.6: ~~Projects / folders for organizing generations~~
- R16.7: ~~Prompt file (YAML) import/export~~
- R16.8: ~~Localization (English only in v1)~~
- R16.9: ~~Variations (batch seed ±1/±2 generation)~~
- R16.10: ~~visionOS support~~
- R16.11: ~~In-app image editing or post-processing~~
- R16.12: ~~Prompt history / suggestions / autocomplete~~
- R16.13: ~~User-created custom styles~~
- R16.14: ~~Style marketplace or sharing~~

---

## R17. Open Questions Summary

Decisions needed before implementation:

1. **App name**: "Vinetas"? "Vinetas Studio"? Something else? Trademark search needed.
2. **Model storage location**: App container vs. shared location vs. user-selected folder? (see R2 notes)
3. **Navigation style**: Toolbar tabs vs. sidebar? (see R3 notes)
4. **Cancellation support**: Does `Vinetas.generate()` / Flux2Pipeline support Task cancellation? Determines Cancel button behavior. (see R5.2.34)
5. **Content moderation**: Is 17+ rating sufficient, or does Apple require active NSFW filtering? (see R14.1 notes)
6. **Gallery search/filter**: Include in v1, or is chronological scroll enough? (see R6.4 notes)
7. **Variations**: Include seed-adjacent batch generation in v1? (see R5.4 notes)
8. **Pricing**: One-time purchase? Free + IAP for premium styles? Subscription?
9. **Bundle ID / signing team**: What Apple Developer account / team to use?
10. **Style thumbnails**: Generate real example images for each style as bundled assets? Or use placeholder art for v1?
11. **Memory-gated styles**: Styles using the 9B engine need 24 GB. Should these styles be hidden on 16 GB machines, or shown with an "unavailable on this hardware" state?

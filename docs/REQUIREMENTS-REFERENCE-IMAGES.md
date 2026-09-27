---
type: doc
state: incomplete
updated: 2026-09-26
---

# REQUIREMENTS: reference images for `vinetas generate`

> Status: **Requirements, locked for review.** No implementation yet. This
> document is grounded in a codebase audit (2026-09-26) of `SwiftVinetas`
> (development @ `37f70c9`, 0.20.0-dev), `flux-2-swift-mlx` (3.4.2), and the
> signed CLI in `apps/Vinetas`. Line references are current as of that audit.

## 1. Goal

Let a caller pass **one or more existing images** to `vinetas generate` so the
new image keeps the **same subject**: the same person from new angles, in a
new pose, or as a reference sheet.

The driving consumer is **Personaje** (`apps/Personaje`), the character-creation
app. After a character's portrait is selected, every later visual step
(turnaround, face sheet, expressions, wardrobe) must be generated *from* that
portrait. Text alone can't hold a likeness: in the Personaje pilot, hair, age
and piercings drifted between seeds of the same prompt. Today Personaje's only
alternatives are cloud providers (OpenAI edits, Gemini), which send the
character off-device.

Success looks like this, run from any working directory:

```bash
vinetas generate "Character turnaround sheet: front, three-quarter, side, back…" \
  --reference - --width 2048 --height 1024 -o - < portrait.png > turnaround.png
```

## 2. What already exists (≈80% of the engine work)

Reference conditioning is **implemented below the CLI**. Nothing reachable
from `generate` uses it.

- **Flux2Core** has real FLUX.2 multi-reference conditioning, public:
  `Flux2Pipeline.generateImageToImage(prompt:images:…)` and
  `generateImageToImageWithResult(…)`, with `[CGImage]` and `[Data]` variants
  (`flux-2-swift-mlx/Sources/Flux2Core/Pipeline/Flux2Pipeline.swift:824, 870,
  948, 994`).
  - It isn't SD-style img2img. The output starts from pure noise. Each
    reference is VAE-encoded, packed, and appended to the token sequence with
    its own time coordinate (:1353-1409, `encodeReferenceImages` :2172-2297).
    **There is no strength/denoise parameter** (Flux2App says so explicitly:
    `Sources/Flux2App/Views/ImageToImageView.swift:240`).
  - It works the same way for every upstream Klein variant and Dev. There are
    GPU tests and examples for Klein 4B (`Tests/Flux2GPUTests/Flux2CoreGPUTests.swift:270-291`;
    `docs/examples/flux2-klein-4b/README.md`).
  - The public API enforces **1–3 references** (`Flux2Pipeline.swift:838, 962`).
    Model metadata says Klein can take 4 and Dev 6 (`Flux2Config.swift:165-170`).
    There's a device-tier cap (16 GB iPad = 2, 8 GB = 1; `Flux2Config.swift:178-191`),
    but nothing calls it.
  - Each reference is downscaled to ≤ 1024² pixels and snapped to multiples of
    32 (:2208-2229).
- **SwiftVinetas** already has the request plumbing:
  - `GenerationRequest.mode` is `.textToImage` or `.imageToImage(references: [CGImage])`
    (`Sources/SwiftVinetas/Engine/EngineTypes.swift:72-78`).
  - `Flux2Engine` maps it to `generateImageToImageWithResult`
    (`Engine/Flux2Engine.swift:371-401`), and `PixArtEngine` rejects it
    (`PixArtEngine.swift:166, 363-372`).
  - `EngineFeature.imageToImage(maxReferenceImages:)` exists
    (`EngineTypes.swift:194`), but `Flux2Engine.supports` returns `true`
    whatever the count (`Flux2Engine.swift:168-169`).
  - `VinetasClient.generateSequence(prompts:referenceImages:…)` is the only
    public API that already passes references (`Vinetas.swift:326-437`).
  - Telemetry already has `mode: .imageToImage` and `referenceImageCount`
    (`Telemetry/VinetasTelemetryEvent.swift:24, 82`).

**What's missing:**
- no reference input on `generate`, `batch` or `storyboard`, or on the
  single-image `VinetasClient.generate` API, which hard-codes `.textToImage`
  (`Vinetas.swift:273`)
- no count validation
- no way to get a reference file into the sandboxed CLI reliably
- no record of references in the sidecar

**Prior art:**
- `apps/Vinetas/docs/incomplete/FEAT-SEQUENCE.md:126-142, 190-193` covers
  cross-panel consistency via references and reference-slot priority, for the
  app.
- `docs/ARCHITECTURE.md:37-43, 208-228` plans up to 3 references, using a
  `strength:` argument that doesn't exist.
- `docs/GUI_REQUIREMENTS.md:81-99` plans a drop zone.
- `docs/V1_REQUIREMENTS.md:462` defers reference images from app v1 (R16.4).

This document covers the **CLI and library** path. The app GUI is out of scope
(§8).

## 3. Requirements: reference input

- **RI-1. `--reference <path>` on `generate`.** Repeatable, short form `-r`.
  **Order is priority**: the first reference is the primary identity source.
  It's passed to the engine in the given order, with no reordering or
  de-duplication.
- **RI-2. Readable formats.** PNG, JPEG and HEIC, anything ImageIO decodes to a
  `CGImage`. The file must exist, be non-empty and decode. Otherwise the command
  fails **before loading a model**, with an error naming the file and the
  reason.
- **RI-3. Stdin reference.** `--reference -` reads one image's bytes from stdin.
  At most one reference may be `-`. This is the sandbox-safe path: an inherited
  file descriptor needs no file entitlement (see RI-9).
- **RI-4. Count validation, before model load.**
  - Each engine advertises its real maximum through
    `EngineFeature.imageToImage(maxReferenceImages:)`.
  - The effective limit is the **minimum** of the Flux2Core public API limit
    (currently 3), the model's `maxReferenceImages`, and the device-tier cap
    (`Flux2Config.swift:178-191`).
  - Going over the limit is an error that states it ("klein4b on this device
    accepts at most 3 reference images; got 4"). It never surfaces as Flux2Core's
    generic "Provide 1-3 reference images."
- **RI-5. Unsupported engine is an error.** `--reference` with `pixart-sigma`,
  or any engine without `.imageToImage`, fails before download or load. It
  **never** silently falls back to text-to-image.
- **RI-6. Output size.** `--width/--height/--aspect` keep their meaning, and
  output size is never inferred from a reference. (Flux2Core would follow the
  first reference when width/height are nil; SwiftVinetas always passes
  explicit sizes, and that stays.)
- **RI-7. Downscaling is reported.** When a reference is larger than
  Flux2Core's limit, the original and effective pixel sizes are recorded in the
  sidecar (RI-12), and a one-line notice goes to stderr.
- **RI-8. No strength parameter.** FLUX.2 conditioning has no strength or
  denoise control, so `generate` doesn't add one. The existing dead
  `character reference --strength` (`VinetasCLICore.swift:764`; never placed
  on the request, `ReferenceSheetGenerator.swift:131-138`) is **deprecated**:
  a warning now, removal in the next minor release.

## 4. Requirements: sandbox-safe I/O

The signed CLI (`apps/Vinetas/VinetasCLI`) runs in the App Sandbox with the
entitlements app-sandbox, App Group `group.intrusive-memory.models`,
network.client and `files.user-selected.read-write`. It has **no Downloads
entitlement**, so writes to `~/Downloads` are refused on some machines, and a
CLI has no powerbox, so `files.user-selected` grants nothing. The only file
locations it can rely on are the App Group container and inherited file
descriptors.

- **RI-9. Streams, not paths.** `--reference -` (RI-3) and `-o -` (RI-10) let a
  caller in any directory use the CLI with no staging and no new entitlement.
  This is the preferred integration path for Personaje.
- **RI-10. `-o -` writes the PNG to stdout.** Only PNG bytes may reach stdout.
  Today `-o -` creates a file literally named `-` in the sandbox container
  (`VinetasCLICore.swift:36-37, 175`).
- **RI-11. All logs go to stderr.** The CLI already uses `stderrPrint` for its
  own progress. But `Flux2Debug.log` uses `print()` and is on by default
  (`flux-2-swift-mlx/Sources/Flux2Core/Utils/Flux2Debug.swift:9, 39-54`), and
  Flux2Core has about 118 other bare `print(` calls, plus one in
  `PixArtEngine.swift:589`. All of them must go to stderr. This needs a change
  in **flux-2-swift-mlx**, and RI-10 depends on it. Acceptance: with `-o -`,
  stdout starts with the PNG signature and contains nothing else.
- **RI-11b. Staging directory for path-based callers.** For callers that can't
  use streams, document one staging location inside the App Group container
  (`<group container>/vinetas-io/`), with a `--print-io-dir` diagnostic. The
  `vinetas-cli` skill's claim of a Downloads entitlement is wrong and must be
  corrected to match.

## 5. Requirements: provenance

A generated image must be **exactly reproducible from its recorded metadata**.
Today it isn't, even for text-to-image.

- **RI-12. Sidecar and embedded metadata.** The metadata
  (`ImageOutput.PanelMetadata`, `Core/ImageOutput.swift:53-106`) records:
  - `mode` (`textToImage` or `imageToImage`), `engine`, and `model`
  - `references`: for each reference in order, the source (path as given, or
    `"stdin"`), `sha256` of the bytes, and the original and effective pixel
    sizes
  - `prompt` (the user's), `style`, **and** `composedPrompt` (what the engine
    actually received; `composePrompt`, `Vinetas.swift:850-855`)
  - `negative`, and `negativeApplied` (RI-14)
  - the **actual** seed used. Today it's `styleConfig.seed ?? 0`, so a random
    seed is lost; this requires the client to return the seed with the image.
  - steps, guidance, the **effective** width and height (after clamping,
    `Vinetas.swift:877-898`), the real `durationSeconds` (hard-coded 0 at
    `VinetasCLICore.swift:209`), and LoRAs **actually applied** (RI-15)

  The same JSON is **embedded in the PNG** as an `iTXt` chunk (keyword
  `vinetas`), so metadata survives `-o -` and any copy or rename. The `.json`
  sidecar is still written when `-o` is a path.
- **RI-13. `batch` and `storyboard` record what they used.** `batch` writes the
  defaults instead of the steps and guidance it used (`VinetasCLICore.swift:337-338`),
  and `storyboard` writes no metadata at all (`StoryboardCommand.swift:135`).
  Both must follow RI-12.

## 6. Requirements: options that are silently ignored today

These aren't about references, but they break the "what you asked for is what
you got" contract that reference generation depends on. The Personaje pilot
unknowingly relied on both.

- **RI-14. `--negative` on FLUX.**
  - `Flux2Engine.generate` never passes `request.negativePrompt`
    (`Flux2Engine.swift:345-356, 376-388`), and Flux2Core has no
    negative-prompt parameter. Klein is guidance-distilled, so a true negative
    prompt may not be meaningful.
  - Requirement: when the engine doesn't apply negatives, `--negative` prints a
    stderr warning and the metadata records `negativeApplied: false`.
  - Implementing negatives for FLUX is **out of scope** here (Q3).
- **RI-15. `--lora` on `generate`.** `VinetasClient.generate(prompt:style:model:)`
  never reads `style.loraPath`. Only the deprecated `VinetasPipeline` does
  (`Core/VinetasPipeline.swift:9, 395, 555`).
  - Requirement: `--lora` is applied via `engine.loadLoRA(at:scale:)`, or the
    command fails.
  - The metadata stops recording LoRAs that weren't applied.
  - `--lora` combined with `--reference` must work, because Personaje's
    long-term path is a character LoRA plus a reference image.

## 7. Requirements: library API

- **RI-16. Single-image client API.** `VinetasClient` gains a public
  single-image method that takes references and returns the image **plus** the
  metadata of RI-12 (at least the actual seed, effective size and the flags
  that were applied). `generate(prompt:style:model:)` keeps working as the
  no-reference case.
- **RI-17. One validation path.** The CLI, `generateSequence`,
  `ReferenceSheetGenerator` and the new API all go through the same
  count/engine/format validation (RI-2, RI-4, RI-5).

## 8. Out of scope

- The Vinetas app GUI: the drop zone, "Use as Reference", Repertorio/Ficha
  (`FEAT-SEQUENCE.md`, `GUI_REQUIREMENTS.md`).
- References in `batch` YAML and in GLOSA `<shot>` (`reference=`). This is a
  follow-up once `generate` is settled; the schema belongs in glosa-av.
- Masks, inpainting, and Kontext-style editing (`ARCHITECTURE.md:43`: Kontext
  deliberately unused).
- Real negative prompts on FLUX (RI-14 only makes the gap visible).
- LoRA *training* (`CharacterTrainer.swift:124-134` always throws, although
  `Flux2Engine.supports(.loraTraining)` returns `true`; that's a separate bug).
- Raising Flux2Core's public 3-reference limit.

## 9. Where the work lands

| Repo | Work |
|------|------|
| `SwiftVinetas` | RI-1–RI-8, RI-10, RI-12–RI-17: `VinetasCLICore`, `VinetasClient`, `Flux2Engine.supports`, `ImageOutput` |
| `flux-2-swift-mlx` | RI-11: logs to stderr. Optionally expose the device-tier cap publicly for RI-4. |
| `apps/Vinetas` | Bump the SwiftVinetas pin (0.20.0 today). The signed `VinetasCLIMain` must expose the new flags. It has **no `storyboard` subcommand** either, so check that its command list matches `VinetasCLICore`. |
| `vinetas-cli` skill | Correct the sandbox guidance (RI-11b) and document `--reference` and streams. |

## 10. Testing

- **Unit (CI):**
  - argument parsing: repeated `-r`, one `-`, and two `-` rejected
  - validation errors for missing, empty, undecodable, too many references, and
    PixArt with references, all raised **before** model load (assert no load
    call)
  - the metadata schema, including the `iTXt` round-trip
  - `negativeApplied` and applied-LoRA reporting
- **Stream purity (CI, no model):** with a stub engine, `-o -` produces stdout
  that starts with the PNG signature and holds nothing else. Logs appear on
  stderr.
- **GPU (local / model-gated, never a CI gate):** Klein 4B with 1 and with 3
  references produces an image at the requested size. The metadata records the
  references' sha256. Rerunning with the recorded seed and references gives a
  byte-identical image.
- **Likeness check (informational):** a `similarity` (DINOv2) score between
  the reference and output is logged in the GPU test. It's a trend to watch,
  not a pass/fail gate.

## 11. Acceptance: the Personaje case

With the Personaje pilot's selected portrait (`apps/Personaje/docs/pilot/ARCHER/images/portrait-v3-photo-s133.png`):

1. `generate --reference - -o -` run from the Personaje repo, with no staging,
   returns a valid PNG on stdout whose embedded metadata names the reference by
   sha256.
2. A turnaround prompt with that reference produces four views that a human
   judges to be the same person as the portrait (hair, beard, tattoos).
3. Regenerating from the embedded metadata reproduces the image exactly.

## 12. Open questions / decisions to lock

| # | Question | Recommendation |
|---|----------|----------------|
| Q1 | Expose 3 references (Flux2Core's public limit) or Klein's metadata limit of 4? | **3.** Raising it is a Flux2Core change, out of scope (§8). |
| Q2 | Metadata transport with `-o -`: embedded PNG chunk, or a separate `--metadata -` stream? | **Embedded `iTXt`.** One stream, and it survives copies. |
| Q3 | `--negative` on FLUX: warn, error, or implement? | **Warn plus `negativeApplied: false`.** Erroring would break existing GLOSA storyboards that carry negatives. |
| Q4 | Add a Downloads (or other file) entitlement to the signed CLI? | **No.** Streams plus the App Group staging dir cover every caller without widening the sandbox. |
| Q5 | Should `--reference` accept a Vinetas character slug (`character reference` output) as well as files? | Defer. Files and stdin first; slugs belong with the `batch`/`<shot>` follow-up. |
| Q6 | Is fixing `--lora` (RI-15) in this release or a separate one? | **This release.** LoRA plus reference is Personaje's long-term path, and the metadata can't be trusted until it's fixed. |

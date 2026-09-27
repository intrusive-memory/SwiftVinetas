---
type: recon-report
state: completed
requirements_file: docs/REQUIREMENTS-REFERENCE-IMAGES.md
requirements_sha256: c29ed576507ba8909bad8bc0f8cc5b1da0a6cd4110544400856404e9bd7ae317
project_head: e51077e2391081634712b910beab5b31fcaaad6d
search_root: ~/Projects
generated: 2026-09-26
verdict: CLEAR
accept_risk: true
mission: tracing-paper-01
updated: 2026-09-27
---

# RECON_REPORT.md — SwiftVinetas (reference images for `vinetas generate`)

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**CLEAR (accept-risk)** — 38 assumptions checked, 36 confirmed, 2 blocking by the letter of the gate (A-06 `REFUTED`, A-18 `STALE`). Neither one is a premise a sortie builds on. Both were carried into `EXECUTION_PLAN.md` as Open Questions (OQ-1, OQ-2) instead of stopping, so `refine-blockers` will still surface them for a decision.

**Scope override (user directive, 2026-09-26):** memory gating has been removed from SwiftVinetas and must not come back. RI-4's device-tier cap (`Flux2Config.maxReferenceImages(forTier:)` / `MemoryTier`) is **excluded**. The effective reference limit is `min(3, model.maxReferenceImages)`.

## Assumption Findings

### Locus `repo` — SwiftVinetas @ `e51077e`

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| A-01 | A-API | `GenerationMode` `.textToImage` / `.imageToImage(references: [CGImage])` | CONFIRMED | `Sources/SwiftVinetas/Engine/EngineTypes.swift:72-78` |
| A-02 | A-BEHAVIOR | Flux2Engine maps i2i → `generateImageToImageWithResult` | CONFIRMED | `Engine/Flux2Engine.swift:371-401` (call at :376) |
| A-03 | A-BEHAVIOR | PixArtEngine rejects i2i | CONFIRMED | `Engine/PixArtEngine.swift:166-167, 363-372` (throws `VinetasError.engineFeatureUnsupported`) |
| A-04 | A-API | `EngineFeature.imageToImage(maxReferenceImages:)` | CONFIRMED | `EngineTypes.swift:194` |
| A-05 | A-BEHAVIOR | `Flux2Engine.supports` true regardless of count | CONFIRMED | `Flux2Engine.swift:168-169` |
| A-06 | A-INVARIANT | `generateSequence(prompts:referenceImages:…)` is the *only* public API passing references | **REFUTED** | `Vinetas.swift:1410-1459`: public `Vinetas.generateReferenceSheets(for:views:strength:model:progress:)` also passes references, through `ReferenceSheetGenerator.swift:137` |
| A-07 | A-API | Telemetry `imageToImage` + `referenceImageCount` | CONFIRMED | `Telemetry/VinetasTelemetryEvent.swift:24, 82` |
| A-08 | A-BEHAVIOR | `VinetasClient.generate(prompt:style:model:) -> CGImage` hard-codes `.textToImage` and never reads `loraPath` | CONFIRMED | `Vinetas.swift:214-218, 270-274` |
| A-09 | A-INVARIANT | No reference option on `generate`/`batch`/`storyboard` | CONFIRMED | `VinetasCLICore.swift:23-345`; `Storyboard/StoryboardCommand.swift` |
| A-10 | A-BEHAVIOR | `character reference --strength` is never applied | CONFIRMED | `VinetasCLICore.swift:764-765, 802`; `Character/ReferenceSheetGenerator.swift:90-138` |
| A-11 | A-BEHAVIOR | `-o -` writes a file literally named `-` | CONFIRMED | `VinetasCLICore.swift:36-37, 175` |
| A-12 | A-BEHAVIOR | CLI progress uses `stderrPrint`; `PixArtEngine.swift:589` has a bare `print(` | CONFIRMED | 66 bare `print(`: 63 in `VinetasCLICore.swift` (report/table output), 1 `StoryboardCommand.swift:84`, 1 `Core/VinetasMemoryProfiler.swift`, 1 `PixArtEngine.swift:589` |
| A-13 | A-DATA | `ImageOutput.PanelMetadata` | CONFIRMED | `Core/ImageOutput.swift:54-108`. Fields: `prompt, model, seed, steps, guidance, width, height, durationSeconds, loras, generatedAt`. Sidecar is `<png>.json` (`:172-183`). Nothing is embedded in the PNG (`:14-49`, nil properties) |
| A-14 | A-BEHAVIOR | seed `styleConfig.seed ?? 0`, `durationSeconds: 0` | CONFIRMED | `VinetasCLICore.swift:204, 209` |
| A-15 | A-API | `composePrompt` and the clamp | CONFIRMED | `Vinetas.swift:850-855`; `ResolutionClamp.clampedDimensions` at `:887` inside `buildRequest` `:877-898` |
| A-16 | A-BEHAVIOR | batch writes default steps/guidance; storyboard writes no metadata | CONFIRMED | `VinetasCLICore.swift:337-338`; `StoryboardCommand.swift:135` |
| A-17 | A-BEHAVIOR | Flux2Engine never passes `negativePrompt` | CONFIRMED | `Flux2Engine.swift:344-356, 375-388` |
| A-18 | A-API | `VinetasPipeline` reads `loraPath` at `:9, 395, 555`; `loadLoRA(at:scale:)` exists | **STALE** (citations only) | Protocol `ImageGenerationEngine.swift:74` and impl `Flux2Engine.swift:417` exist. `loraPath` reads are at `VinetasPipeline.swift:496, 554, 572, 574`; `:395`/`:555` call `VinetasLoRAManager.loadIfConfigured(style:on:)` |
| A-19 | A-CONFIG | Makefile `build/test-unit/test-gpu/lint`; test targets | CONFIRMED | `Makefile:68, 86, 125, 199, 308`; `Package.swift` test targets |
| A-20 | A-API | Engine seam for stub-engine tests | CONFIRMED (partial) | `EngineRouter.swift:38` `init(engines:)`; `Vinetas.swift:157-159` `VinetasClient.init(router:)`; `Tests/SwiftVinetasTests/MockEngine.swift`. **Gap:** CLI commands go through `VinetasClient.shared` (`Vinetas.swift:42, 126`), so there is no hook to drive `Generate.run()` against a mock |
| A-21 | A-API | Engine result carries the actual seed | CONFIRMED | `EngineTypes.swift:84-121` `GenerationResult.seed` (`:93`); set at `Flux2Engine.swift:409` |
| A-22 | A-API | Engine feature for negative-prompt support | CONFIRMED absent | `EngineTypes.swift:188-206`: `EngineFeature` has no negative-prompt case |

### Locus `dep:intrusive-memory/flux-2-swift-mlx` — resolved copy `.build/checkouts/flux-2-swift-mlx` @ `857dd73` (v3.4.2, == pin)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| F-01 | A-API | Public `generateImageToImage[WithResult]` with `[CGImage]`/`[Data]` | CONFIRMED | `Flux2Core/Pipeline/Flux2Pipeline.swift:824, 870, 948, 994` |
| F-02 | A-BEHAVIOR | Enforces 1–3 refs | CONFIRMED | `:838-844, 962-968`: `Flux2Error.invalidConfiguration("Provide 1-3 reference images")` |
| F-03 | A-API | No strength/denoise param | CONFIRMED | signatures `:948, 994`; `strength: 1.0` fixed and internal (`:1409, :1894`) |
| F-04 | A-DATA | `maxReferenceImages` Klein 4, Dev 6, public | CONFIRMED | `Configuration/Flux2Config.swift:165-170` |
| F-05 | A-API | Device-tier cap, uncalled | CONFIRMED — **excluded by user directive** | `Flux2Config.swift:178-191` |
| F-06 | A-BEHAVIOR | Refs downscaled to ≤1024², snapped to 32 | CONFIRMED | `:2204-2233` inside `private encodeReferenceImages` (`:2172`). The effective size is **not observable** to callers, so SwiftVinetas must reproduce the math for RI-7 |
| F-07 | A-BEHAVIOR | nil width/height follows first reference | CONFIRMED | `:847-849` |
| F-08 | A-BEHAVIOR | `Flux2Debug.log` → `print`, on by default; ~118 bare prints | CONFIRMED | `Utils/Flux2Debug.swift:9, 39-56`. 118 in Flux2Core, 233 total. `Flux2Debug.enabled` is a public switch, but nothing can redirect the output |
| F-09 | A-API | No negative-prompt param | CONFIRMED | `grep negativePrompt Sources/Flux2Core` → none |
| F-10 | A-API | Result type contents | CONFIRMED | `:43-63` `Flux2GenerationResult{image, usedPrompt, wasUpsampled, originalPrompt}`. There is no seed field, but SwiftVinetas already resolves the seed itself (A-21) |
| F-11 | A-API | LoRA + i2i combinable | CONFIRMED | `:635` public `loadLoRA`, merged into the weights; generation paths have no guard against combining |

### Locus `repo:apps/Vinetas` @ `main` + `skill:vinetas-cli` (`~/.claude/skills` repo)

| ID | Kind | Claim | Verdict | Evidence |
|----|------|-------|---------|----------|
| V-01 | A-CONFIG | Signed CLI entitlements: sandbox, App Group, network.client, user-selected r/w; no Downloads | CONFIRMED | `apps/Vinetas/VinetasCLI/VinetasCLI.entitlements` |
| V-02 | A-API | `VinetasCLIMain` reuses `VinetasCLICore` and has no `storyboard` | CONFIRMED | `VinetasCLI/VinetasCLIMain.swift:20-42` |
| V-03 | A-DATA | App pins SwiftVinetas 0.20.0 | CONFIRMED | workspace `Package.resolved`; pbxproj `minimumVersion = 0.20.0` |
| V-04 | A-DATA | `vinetas-cli` skill wrongly claims a Downloads entitlement | CONFIRMED | `~/.claude/skills/vinetas-cli/SKILL.md:65` claims `files.downloads.read-write`, which is absent per V-01 |
| V-05 | A-FILE | `FEAT-SEQUENCE.md:126-142` prior art | CONFIRMED | `apps/Vinetas/docs/incomplete/FEAT-SEQUENCE.md:126-142` |
| V-06 | A-FILE | Personaje pilot portrait exists | CONFIRMED | `ls ~/Projects/apps/Personaje/docs/pilot/ARCHER/images/portrait-v3-photo-s133.png` |
| V-07 | A-API | App Group container path API exists | CONFIRMED | `.build/checkouts/SwiftAcervo/Sources/SwiftAcervo/Acervo+PathResolution.swift:153` `Acervo.sharedModelsDirectory` (App Group resolution in same file) |

### Blocking findings (carried as Open Questions via accept-risk)

#### A-06 — REFUTED
**Claim**: "`VinetasClient.generateSequence(prompts:referenceImages:…)` is the only public API that already passes references" (requirements §2, lines 68-69)
**Found**: public `Vinetas.generateReferenceSheets(…)` (`Vinetas.swift:1410-1459`) → `ReferenceSheetGenerator.generate` builds `.imageToImage(references: [sourceImage])` (`ReferenceSheetGenerator.swift:137`).
**Impact**: None on scope. RI-17 already routes `ReferenceSheetGenerator` through the shared validation, so this reference path was already in the requirements. Carried as **OQ-1**.

#### A-18 — STALE (line citations)
**Claim**: `VinetasPipeline` reads `loraPath` at `:9, 395, 555`.
**Actual**: reads are at `:496, 554, 572, 574`. The reusable entry point is `VinetasLoRAManager.loadIfConfigured(style:on:)`. The engine API (`loadLoRA(at:scale:)`) is confirmed.
**Impact**: None on scope. Sorties cite the corrected lines. Carried as **OQ-2**.

## Local Dependency Map

Sibling pattern is **active** locally (`Package.swift` `sibling(...)`; `CI` unset). Every intrusive-memory dependency resolves to `../<Name>`, and each of those checkouts is ahead of its pin. **Local builds compile against source that CI does not.** All flux claims above were verified against the pinned `.build/checkouts` copy.

| Dependency | Declared | Resolved (Package.resolved) | Local checkout | Local HEAD | Status |
|------------|----------|-----------------------------|----------------|-----------|--------|
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.2` | 3.4.2 (`857dd73`) | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | `0a00d01` (+5) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` | 0.25.0 (`87ec22c`) | `~/Projects/package-collection/pkg/SwiftAcervo` | `13e2879` (+4, dirty) | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` | 0.9.0 (`22c5d70`) | `~/Projects/package-collection/pkg/SwiftTuberia` | `d74977a` (+1, dirty) | SIBLING_ACTIVE, LOCAL_AHEAD, LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.1` | 0.8.1 (`e8cf968`) | `~/Projects/package-collection/pkg/pixart-swift-mlx` | `ad32b31` (+2) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/glosa-av | `from: 0.8.0` | 0.8.0 (`6b24e1b`) | `~/Projects/package-collection/pkg/glosa-av` | `aaa9476` (+2) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | `from: 7.2.4` | 7.2.4 (`2a45c5c`) | `~/Projects/package-collection/pkg/SwiftCompartido` | `388a269` (+2) | SIBLING_ACTIVE, LOCAL_AHEAD |
| marcprux/universal | `from: 5.3.0` | 5.3.0 | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | 1.8.2 | — | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor 0.7.1` | 0.7.1 | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-certificates / swift-crypto / swift-asn1 | `from: 1.0.0/3.0.0/1.0.0` | 1.19.4 / 3.15.1 / 1.7.1 | — | — | NO_LOCAL_CHECKOUT |

### Drift and ambiguity notes

- **flux-2-swift-mlx +5**: `40661d4` turns the RAM-tier *image-size* check into an advisory log (v3.4.3, unreleased). It doesn't touch reference-image code, `Flux2Config`, or print behaviour, so no verdict changes.
- **SwiftAcervo / SwiftTuberia are dirty.** Nothing in this mission rests on their uncommitted state. Sortie agents must not edit them.
- No `AMBIGUOUS` checkouts.

## Unverifiable

_None._

## Handoff to breakdown

- `CONFIRMED` facts are safe as sortie entry criteria without re-checking.
- A-06 → OQ-1, A-18 → OQ-2 (accept-risk).
- F-05 excluded by user directive (no memory gating).
- F-06: the effective reference size must be reproduced in SwiftVinetas. A-20: the CLI needs an injectable client seam before stream-purity tests can run in CI.

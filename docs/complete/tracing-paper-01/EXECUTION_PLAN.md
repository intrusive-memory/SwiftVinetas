---
type: execution-plan
requirements_file: docs/REQUIREMENTS-REFERENCE-IMAGES.md
recon_report: RECON_REPORT.md
refined: 2026-09-26
feature_name: OPERATION TRACING PAPER
starting_point_commit: 3863974b7299fda04b933ce471f17d6ec3e6cfa6
original_starting_point_commit: e51077e2391081634712b910beab5b31fcaaad6d
mission_branch: mission/tracing-paper/01
iteration: 1
state: completed
mission: tracing-paper-01
updated: 2026-09-27
---

# EXECUTION_PLAN.md — SwiftVinetas: reference images for `vinetas generate`

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Mission Scope

Implements RI-1 – RI-17 of `docs/REQUIREMENTS-REFERENCE-IMAGES.md`, with these decisions applied:

- **No memory gating (user directive, 2026-09-26).** RI-4's device-tier cap is dropped. The effective reference limit is `min(3, model.maxReferenceImages)`. No sortie may call `Flux2Config.maxReferenceImages(forTier:)` or `MemoryTier`, or add any RAM/device check.
- **RI-11 (flux-2-swift-mlx prints → stderr) runs first, as WU-0**, in a git worktree of flux-2-swift-mlx. It is merged into flux `development` by the flux session `vinetas-2b`, which is holding its flux release for it. SwiftVinetas also keeps its own CLI stdout guard (Sortie 9), because SwiftAcervo (11) and SwiftTuberia (3) still have bare `print(` calls on the generate path.
- **Out of scope; follow-ups after release:** the `apps/Vinetas` version bump and `VinetasCLIMain` command list, and the `vinetas-cli` skill correction.
- **The requirements' §12 decisions are locked as recommended:**
  - Q1: 3 references.
  - Q2: embedded `iTXt` metadata; no `--metadata -`.
  - Q3: `--negative` on FLUX warns and records `negativeApplied: false`.
  - Q4: no new entitlement.
  - Q5: no character-slug references.
  - Q6: `--lora` is fixed in this release.

- **Mid-mission rebase (user decision, 2026-09-27).** When `vinetas-2b` ships SwiftVinetas 0.20.1 (squash `development` → `main`, rebase and force-push `development`), the supervisor commits Sortie 15's work, then rebases `mission/tracing-paper/01` onto the new `origin/development`. `starting_point_commit` is re-baselined to that new base, and every completed sortie's `git diff <starting_point_commit>` exit check is re-run against it.

Build and test only through Makefile targets / XcodeBuildMCP (`make build`, `make test-unit`, `make test-gpu`). **Never** `swift build` / `swift test`.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU-0 Flux logs → stderr | `~/Projects/package-collection/pkg/flux-2-swift-mlx` (worktree only) | 2 (S1–S2) | 0 | none |
| WU-1 Library | `Sources/SwiftVinetas`, `Tests/SwiftVinetasTests` | 6 (S3–S8) | 0 | none (parallel with WU-0; different repo) |
| WU-2 CLI | `Sources/VinetasCLICore`, `Tests/SwiftVinetasTests`, `README.md`, `docs/` | 6 (S9–S14) | 1 | WU-1 |
| WU-3 GPU validation | `Tests/SwiftVinetasGPUTests` | 1 (S15) | 2 | WU-2 |
| WU-4 Flux floor bump | `Package.swift`, `Package.resolved`, `Tests/SwiftVinetasTests` | 1 (S16, deferred) | 1 | WU-0 + flux release tagged by `vinetas-2b` |

---

## WU-0 Flux logs → stderr (flux-2-swift-mlx, worktree)

**Conflict-avoidance constraints (agreed with `vinetas-2b`, 2026-09-26), for both sorties:**
- **Never** edit, stash, check out, reset or push in `~/Projects/package-collection/pkg/flux-2-swift-mlx` itself. Another session's agent is actively committing there.
- **Edit no existing call sites.** In particular, leave `Configuration/QuantizationConfig.swift`, `Pipeline/Flux2Pipeline.swift` and the loading/quantization path alone.
- **Add no tests to `Tests/Flux2CoreTests`.** Behavioural verification happens in SwiftVinetas (Sortie 16).

### Sortie 1: Add module-level stderr `print` shadows to Flux2Core and FluxTextEncoders

**Priority**: 13.5 — longest external lead time: a peer session is holding a release for it, and Sortie 2 and Sortie 16 depend on it.

**Entry criteria**:
- [ ] First sortie — no prerequisites. Dispatched first, concurrently with Sortie 3.
- [ ] The supervisor has created the worktree before dispatch: `git -C ~/Projects/package-collection/pkg/flux-2-swift-mlx worktree add -b fix/logs-to-stderr <scratchpad>/flux-stderr development`. The agent works **only** in `<scratchpad>/flux-stderr`.
- [ ] RECON F-08: `Flux2Debug.log` calls `print` (`Sources/Flux2Core/Utils/Flux2Debug.swift:39-56`); there are ~118 bare `print(` calls in Flux2Core, plus more in FluxTextEncoders.

**Tasks**:
1. Add `Sources/Flux2Core/Utils/StderrPrint.swift`. It declares module-internal `func print(_ items: Any..., separator: String = " ", terminator: String = "\n")`, which joins `items.map { "\($0)" }` with `separator`, appends `terminator`, and writes the UTF-8 bytes to `FileHandle.standardError`. Module-scope functions shadow `Swift.print`, so every existing call, `Flux2Debug.log` included, goes to stderr with **no call-site edits**. Add a header comment explaining the shadowing and why (stdout is reserved for data, e.g. `vinetas generate -o -`).
2. Add an identical `Sources/FluxTextEncoders/Utils/StderrPrint.swift` (create `Utils/` if absent). Leave `Sources/Flux2App` untouched.
3. Run `grep -rn 'print(' Sources/Flux2Core Sources/FluxTextEncoders | grep -v 'Flux2Debug\|StderrPrint'` and inspect the output for any call that emits machine-readable data meant for stdout (e.g. JSON/CSV). If one exists, change only that call to `Swift.print` and name it in the commit message. If none exists, state "none found" in the sortie report.
4. `make build`, `make test-core`, `make test-fte` in the worktree. Commit on `fix/logs-to-stderr` with message `fix: route Flux2Core and FluxTextEncoders logging to stderr`.

**Exit criteria**:
- [ ] `git -C <scratchpad>/flux-stderr diff --stat development..fix/logs-to-stderr` lists exactly the two new `StderrPrint.swift` files, plus any call site named under task 3.
- [ ] `grep -c 'FileHandle.standardError' <scratchpad>/flux-stderr/Sources/Flux2Core/Utils/StderrPrint.swift <scratchpad>/flux-stderr/Sources/FluxTextEncoders/Utils/StderrPrint.swift` returns ≥ 1 for each file.
- [ ] `make build`, `make test-core` and `make test-fte` exit 0 in the worktree.
- [ ] [judgment] The shadow's output matches `Swift.print` byte for byte for the same arguments: items joined by `separator`, then `terminator`, with the defaults `" "` and `"\n"`.

### Sortie 2: Rebase `fix/logs-to-stderr` onto the peer's pushed `development`

> **SUPERSEDED (user decision, 2026-09-27).** `vinetas-2b` cherry-picked Sortie 1's commit as `025ecad` into flux PR #40, released as flux-2-swift-mlx 3.4.3 by squash merge. The rebase, push and merge below are no longer performed. **Replacement exit criteria (checked by the supervisor, no agent dispatch):**
> - [ ] Flux tag `v3.4.3` (or `3.4.3`) exists on `origin`.
> - [ ] `git -C ~/Projects/package-collection/pkg/flux-2-swift-mlx cat-file -e <tag>:Sources/Flux2Core/Utils/StderrPrint.swift` and `…:Sources/FluxTextEncoders/Utils/StderrPrint.swift` both exit 0 (after a read-only `git fetch --tags origin`).
> - [ ] Then the supervisor runs `git worktree remove` on the scratchpad worktree and deletes the local `fix/logs-to-stderr` branch (never pushed).
>
> WU-0 is `COMPLETED` when these hold. The original text is kept below for the record.

**Priority**: 9.0 — gates the flux release and Sortie 16.

**Entry criteria**:
- [ ] Sortie 1 `COMPLETED`.
- [ ] **Deferred until** `vinetas-2b` has messaged `swiftvinetas-e8` that its agent's commits are pushed to `origin/development`. Waiting does not escalate to FATAL.

**Tasks**:
1. In the worktree: `git fetch origin`, then `git rebase origin/development`.
2. Resolve conflicts, if any, by keeping the peer's changes and re-adding only the two `StderrPrint.swift` files.
3. `make build`, `make test-core`, `make test-fte` in the worktree.
4. `git push -u origin fix/logs-to-stderr` (the branch only; never `development`).

**Exit criteria**:
- [ ] `git -C <scratchpad>/flux-stderr merge-base --is-ancestor origin/development fix/logs-to-stderr` exits 0.
- [ ] `git diff --stat origin/development..fix/logs-to-stderr` shows only the Sortie 1 files.
- [ ] `make build`, `make test-core` and `make test-fte` exit 0 after the rebase.
- [ ] `git ls-remote origin fix/logs-to-stderr` returns the local branch tip SHA.

**Merge (supervisor, not the sortie agent)**: the supervisor messages `vinetas-2b` that the branch is green and rebased, and `vinetas-2b` merges it into `development` before resuming its flux release. The supervisor then runs `git worktree remove`. WU-0 is `COMPLETED` only when `git -C ~/Projects/package-collection/pkg/flux-2-swift-mlx merge-base --is-ancestor fix/logs-to-stderr origin/development` exits 0.

---

## WU-1 Library

### Sortie 3: Reference image loading and effective-size math

**Priority**: 26.5 — foundation type used by 12 later sorties.

**Entry criteria**:
- [ ] First SwiftVinetas sortie — no prerequisites. `make build` succeeds on the mission branch.
- [ ] Read-only reference: `.build/checkouts/flux-2-swift-mlx/Sources/Flux2Core/Pipeline/Flux2Pipeline.swift:2204-2233` (pinned v3.4.2 downscale/snap-to-32 logic — RECON F-06).

**Tasks**:
1. Create `Sources/SwiftVinetas/Reference/ReferenceImage.swift` with public `struct ReferenceImage: Sendable`:
   - `source: ReferenceSource` (`.file(path: String)` / `.stdin`)
   - `sha256: String` (lowercase hex of the raw bytes)
   - `image: CGImage`
   - `originalSize` and `effectiveSize` (`width`/`height` `Int`s)
2. Add `ReferenceImage.load(path:)` and `ReferenceImage.load(data:source:)`. They decode with `CGImageSourceCreateWithData`, which covers PNG/JPEG/HEIC. Add `VinetasError` cases `referenceNotFound(path:)`, `referenceEmpty(source:)` and `referenceUndecodable(source:)`; each `errorDescription` contains the path, or `stdin`, plus the reason.
3. Add `static func flux2EffectiveSize(width:height:) -> (width: Int, height: Int)`, reproducing the Flux2Core math exactly. Give it a doc comment citing the pinned flux file:line.
4. SHA-256 via `CryptoKit` (no new package dependency).
5. Write `Tests/SwiftVinetasTests/ReferenceImageTests.swift` with fixtures generated in-test:
   - Decode PNG, JPEG and HEIC. The HEIC test is `.enabled(if: CGImageDestinationCopyTypeIdentifiers() contains "public.heic")`, so a runner without an HEVC encoder skips it instead of failing.
   - Missing file, zero-byte file and garbage bytes. Assert each error message contains the path.
   - sha256 of `"abc"`, `ba7816bf…15ad`.
   - Effective size for 512², 1024², 2048×1024, 3000×2000 and 1000×1000, with expected values computed from the flux formula.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0, and the log shows ≥ 9 `ReferenceImageTests` passing, with the HEIC test passing or skipped.
- [ ] `grep -rn "MemoryTier\|forTier" Sources/` returns no matches.

### Sortie 4: Engine reference limits and the shared validator

**Priority**: 22.0 — blocks every validation path (RI-4, RI-5, RI-17).

**Entry criteria**:
- [ ] Sortie 3 `COMPLETED`.
- [ ] RECON A-04/A-05 (`EngineTypes.swift:194`, `Flux2Engine.swift:168-169`) and F-02/F-04 (`Flux2Pipeline.swift:838-844`, `Flux2Config.swift:165-170`) are ground truth.

**Tasks**:
1. Add to `ImageGenerationEngine` (`Engine/ImageGenerationEngine.swift`) `func maxReferenceImages(for model: any ModelDescriptor) -> Int`, with a protocol-extension default of `0`.
   - `PixArtEngine` returns 0.
   - `Flux2Engine` returns `min(3, <Flux2Model for descriptor>.maxReferenceImages)`.
   - **No memory/device-tier input.**
2. `Flux2Engine.supports(.imageToImage(maxReferenceImages: n))` returns `n <= 3` instead of `true`.
3. Create `Sources/SwiftVinetas/Reference/ReferenceValidator.swift` with `static func validate(referenceCount: Int, engine: any ImageGenerationEngine, model: any ModelDescriptor) throws`. It is a no-op for 0 references. It throws:
   - `VinetasError.referencesUnsupported(engineID:)` when the max is 0.
   - `VinetasError.tooManyReferences(model:max:got:)` when the count is over the max, with `errorDescription` exactly `"<model.id> accepts at most <max> reference images; got <n>"`.
4. Make the max reference count configurable on `Tests/SwiftVinetasTests/MockEngine.swift` (default 0), and add `loadModelCallCount` / `generateCallCount` if they don't exist.
5. Write `Tests/SwiftVinetasTests/ReferenceValidatorTests.swift` covering:
   - PixArt with 1 reference → `referencesUnsupported`
   - Klein 4B with 3 → passes
   - Klein 4B with 4 → `tooManyReferences`, asserting the exact message
   - 0 references → passes
   - mock with max 1 and 2 references → `tooManyReferences`

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, and the log shows ≥ 5 `ReferenceValidatorTests` passing.
- [ ] `grep -n "case .imageToImage: true" Sources/SwiftVinetas/Engine/Flux2Engine.swift` returns no match.
- [ ] `git diff <starting_point_commit> -- Sources | grep -E "^\+.*(MemoryTier|forTier|physicalMemory)"` returns no match.

### Sortie 5: Provenance metadata schema and PNG iTXt embedding

**Priority**: 17.5 — the metadata type is consumed by Sorties 6, 11, 12 and 15.

**Entry criteria**:
- [ ] Sortie 3 `COMPLETED` (uses `ReferenceImage`).
- [ ] RECON A-13: `Core/ImageOutput.swift:54-108` holds the current fields (`prompt, model, seed, steps, guidance, width, height, durationSeconds, loras, generatedAt`), the sidecar is `<png>.json` (`:172-183`), and `pngData` embeds nothing (`:14-49`).

**Tasks**:
1. Extend `ImageOutput.PanelMetadata` with **optional** fields:
   - `mode` (`"textToImage"`/`"imageToImage"`)
   - `engine`
   - `references: [ReferenceRecord]?`, where each record has `source`, `sha256`, `originalWidth`, `originalHeight`, `effectiveWidth`, `effectiveHeight`
   - `style`
   - `composedPrompt`
   - `negative`
   - `negativeApplied: Bool?`

   Existing field names are unchanged. Document `loras` as *applied* LoRAs.
2. Add `ImageOutput.pngData(image:metadata:) -> Data`. It encodes the PNG and inserts one uncompressed `iTXt` chunk before `IEND`: keyword `vinetas`, compression flag 0, empty language and translated keyword, and the metadata JSON encoded with `.sortedKeys` as the text. Implement a CRC-32 (ISO-HDLC polynomial) in-repo.
3. Add `ImageOutput.readEmbeddedMetadata(from: Data) -> PanelMetadata?`.
4. `ImageOutput.writePanel(...)` writes the embedded PNG **and** the `.json` sidecar, with byte-identical JSON.
5. Write `Tests/SwiftVinetasTests/PanelMetadataTests.swift` covering:
   - an iTXt round-trip with equal structs
   - `CGImageSourceCreateWithData` still decodes the output
   - the first 8 bytes are the PNG signature
   - a literal JSON fixture string in the `development` format (no new fields) decodes
   - sidecar bytes equal the embedded JSON bytes
   - the CRC-32 of `"123456789"` is `0xCBF43926`

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, and the log shows ≥ 6 `PanelMetadataTests` passing.
- [ ] `grep -n 'vinetas\\\\0\|"vinetas"' Tests/SwiftVinetasTests/PanelMetadataTests.swift` matches an assertion on the chunk keyword.

### Sortie 6: Single-image client API — references, actual seed, metadata, negative reporting

**Priority**: 19.0 — the API every CLI sortie builds on (RI-12, RI-14, RI-16).

**Entry criteria**:
- [ ] Sorties 4 and 5 `COMPLETED`.
- [ ] RECON ground truth:
  - A-08: `Vinetas.swift:214-274`; `generate(prompt:style:model:) -> CGImage` hard-codes `.textToImage` at `:273`.
  - A-15: `composePrompt` `:850-855`; clamp `:887` in `buildRequest` `:877-898`.
  - A-21: `GenerationResult.seed`, `EngineTypes.swift:93`.
  - A-17: Flux2 drops `negativePrompt`.
  - A-22: no negative-prompt `EngineFeature`.

**Tasks**:
1. Add `EngineFeature.negativePrompt`.
   - `Flux2Engine.supports` returns `false`.
   - For `PixArtEngine.supports`, read `PixArtEngine.swift` and return `true` only if `request.negativePrompt` is passed into the PixArt pipeline. Cite the line in the sortie report.
2. Create `Sources/SwiftVinetas/PanelRequest.swift` with:
   - public `struct PanelRequest`: `prompt: String`, `style: StyleConfig`, `model: any ModelDescriptor`, `references: [ReferenceImage]`
   - public `struct GeneratedPanel`: `image: CGImage`, `metadata: ImageOutput.PanelMetadata`
3. Add `public func generate(_ request: PanelRequest) async throws -> GeneratedPanel` to `VinetasClient`:
   - Resolve the engine.
   - Run `ReferenceValidator` **before** `loadModel`.
   - Map non-empty references to `.imageToImage(references:)`; never fall back to t2i.
   - Fill the metadata: actual seed from `GenerationResult.seed`; effective clamped width/height; `composedPrompt`; `prompt`; `style`; `negative` and `negativeApplied`; `references` records; `mode`; `engine`; `model`; steps; guidance; `durationSeconds` measured with `ContinuousClock`; and `loras: []` (Sortie 7 fills it).
4. Reimplement `generate(prompt:style:model:) -> CGImage` as a wrapper returning `try await generate(PanelRequest(... references: [])).image`.
5. Write `Tests/SwiftVinetasTests/PanelRequestTests.swift` (`MockEngine`) covering:
   - a nil style seed makes `metadata.seed` equal the mock's returned seed
   - a mock with max 0 plus a reference throws, with `loadModelCallCount == 0` and `generateCallCount == 0`
   - too many references throws before load, with the counts at 0
   - `negativeApplied == false` when the mock lacks `.negativePrompt` and `negative` is set
   - the effective size equals the clamped size
   - the wrapper returns an image

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, and the log shows ≥ 6 `PanelRequestTests` passing.
- [ ] `grep -n "func generate(_ request: PanelRequest)" Sources/SwiftVinetas/Vinetas.swift` matches once.
- [ ] Within `generate(prompt:style:model:)`, `buildRequest(` no longer appears: check with `awk '/func generate\(prompt:/,/^  }/' Sources/SwiftVinetas/Vinetas.swift | grep -c "buildRequest("`, which should print `0`.

### Sortie 7: Apply `style.loraPath` in the single-image API (RI-15)

**Priority**: 12.0 — Personaje's long-term path is LoRA plus reference; the metadata is untrustworthy until it's fixed.

**Entry criteria**:
- [ ] Sortie 6 `COMPLETED`.
- [ ] RECON A-18 (corrected): the engine exposes `loadLoRA(at:scale:)` (`ImageGenerationEngine.swift:74`, `Flux2Engine.swift:417`). Reusable helper: `VinetasLoRAManager.loadIfConfigured(style:on:)` (used at `Core/VinetasPipeline.swift:395, 555`; reads `loraPath` at `:496, 554, 572, 574`). F-11: Flux2Core merges LoRA weights at load, with no guard against combining with i2i.

**Tasks**:
1. In `generate(_ request: PanelRequest)`, after `loadModel` and before `engine.generate`:
   - If `style.loraPath != nil`, throw `VinetasError.engineFeatureUnsupported(feature: .loraInference, ...)` when the engine doesn't support `.loraInference`.
   - Otherwise apply the LoRA via `VinetasLoRAManager.loadIfConfigured(style:on:)`, or `engine.loadLoRA(at:scale:)` directly if the helper doesn't fit.
   - A load failure propagates as a thrown error.
2. Record the applied LoRA(s) in `metadata.loras` (path and scale), **only** after a successful load.
3. Tests (`MockEngine`, with `.loraInference` configurable and a `loadLoRACallCount`):
   - a LoRA is applied and recorded
   - LoRA plus 1 reference is applied and recorded, with mode `imageToImage`
   - an engine without `.loraInference` plus `loraPath` throws, and `generateCallCount == 0`
   - a mock `loadLoRA` failure throws, and `metadata` is never produced
   - no `loraPath` gives `loras == []`

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, with 5 new LoRA tests passing.
- [ ] `awk '/func generate\(_ request: PanelRequest\)/,/^  }/' Sources/SwiftVinetas/Vinetas.swift | grep -c "loraPath\|loadIfConfigured\|loadLoRA"` prints ≥ 1.

### Sortie 8: Route existing reference paths through the validator; deprecate `strength`

**Priority**: 10.5 — fixes two live bugs (RI-2 and RI-5 on reference sheets) and completes RI-17.

**Entry criteria**:
- [ ] Sorties 3 and 4 `COMPLETED`.
- [ ] Code facts from OQ-1 research (2026-09-26, `e51077e`):
  - `Vinetas.generateReferenceSheets(for:views:strength:model:progress:)` is on the deprecated `Vinetas` enum (`Vinetas.swift:935-936, 1410-1459`). It always passes **exactly one** reference (`sourcePhotos.first`) and decodes it PNG-only via `CGImage(pngDataProviderSource:)` (`:1433-1448`).
  - `VinetasModel` includes `.pixartSigma` (`Vinetas.swift:1562-1565`). PixArt reference sheets **load the model** before throwing (`ReferenceSheetGenerator.swift:101-110, 142`).
  - `ReferenceSheetGenerator.generate` hard-codes `VinetasClient.shared.router` (`:101`).
  - `defaultStrength` and the doc comments at `ReferenceSheetGenerator.swift:41-46, 85` wrongly claim strength preserves structure.
  - `ReferencePromptTests.swift:193-194, 217-231` pin `defaultStrength == 0.65` and the 5-argument signature.
  - `generateSequence` (`Vinetas.swift:326-437`) uses the instance `router`, and emits `generationStart` (`:381-400`) before `router.engine`/`loadModel` (`:401-410`).

**Tasks**:
1. `generateSequence`: when `referenceImages` is non-empty, resolve the engine and run `ReferenceValidator` **before** the `generationStart` capture and `loadModel`.
2. `ReferenceSheetGenerator.generate`: add an internal `router: EngineRouter = VinetasClient.shared.router` parameter, and run `ReferenceValidator` (count 1) before `engine.loadModel`.
3. `Vinetas.generateReferenceSheets`: replace the PNG-only decode with `ReferenceImage.load(path:)`.
4. Deprecate `strength` without making the overloads ambiguous:
   - The new primary overload is `generateReferenceSheets(for:views:model:progress:)`, with defaults.
   - The 5-argument overload gets a **required** `strength: Float` (no default) and `@available(*, deprecated, message: "FLUX.2 reference conditioning has no strength control; removed in the next minor release.")`, and forwards to the new overload.
   - Deprecate `ReferenceSheetGenerator.defaultStrength` and correct its doc comments.
5. Tests (`MockEngine`):
   - `generateSequence` with too many references throws, with load and generate counts at 0
   - `ReferenceSheetGenerator.generate` with an injected router whose mock has max 0 throws `referencesUnsupported`, with the load count at 0
   - a JPEG source photo in a temp character directory loads via `ReferenceImage.load(path:)`
   - `ReferencePromptTests.swift` is not modified

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, including `ReferencePromptTests`.
- [ ] `git diff <starting_point_commit> -- Tests/SwiftVinetasTests/ReferencePromptTests.swift` is empty.
- [ ] `grep -rn "ReferenceValidator.validate" Sources/SwiftVinetas | wc -l` prints ≥ 3.
- [ ] `grep -c "pngDataProviderSource" Sources/SwiftVinetas/Vinetas.swift` is lower than on `<starting_point_commit>`, and `awk '/func generateReferenceSheets/,/^  }/' Sources/SwiftVinetas/Vinetas.swift | grep -c pngDataProviderSource` prints `0`.
- [ ] `grep -n "VinetasClient.shared.router" Sources/SwiftVinetas/Character/ReferenceSheetGenerator.swift` matches only the default-argument line.

---

## WU-2 CLI

### Sortie 9: CLI client-injection seam and stdout guard

**Priority**: 16.5 — every CLI test (Sorties 10–13) depends on the seam.

**Entry criteria**:
- [ ] WU-1 `COMPLETED` (Sorties 3–8).
- [ ] RECON A-20: CLI commands reach `VinetasClient.shared` (`Vinetas.swift:42, 126`) through the deprecated `Vinetas` enum, so there is no mock hook.

**Tasks**:
1. Add `Sources/VinetasCLICore/CLIEnvironment.swift` with `enum CLIEnvironment { @TaskLocal static var client: VinetasClient = .shared }`. Route `Generate`, `Batch`, `Storyboard` and `Character.Reference` generation calls through `CLIEnvironment.client`. Leave download calls as they are, but make them skippable in tests via `@TaskLocal static var skipDownload = false`.
2. Add `Sources/VinetasCLICore/StdoutGuard.swift`:
   - `begin()`: `fflush(stdout)`, save `dup(1)`, then `dup2(2, 1)`.
   - `write(_ data: Data)`: writes all bytes to the saved fd, looping on partial writes.
   - `end()`: `fflush(stdout)`, then `dup2(saved, 1)` and `close(saved)`.
3. Write `Tests/SwiftVinetasTests/StdoutGuardTests.swift`, marked `.serialized`. Swap fds 1 and 2 for `pipe()`s around the test, then assert:
   - after `begin()`, `print("x")` bytes arrive on the stderr pipe
   - `write(Data([0x89]))` arrives on the stdout pipe
   - after `end()`, stdout is restored

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, and the log shows ≥ 3 `StdoutGuardTests` passing.
- [ ] `grep -rn "Vinetas\.generate\|VinetasClient.shared" Sources/VinetasCLICore` matches no generation call outside `CLIEnvironment.swift`.

### Sortie 10: `generate --reference` / `-r` input and pre-load validation (RI-1 – RI-5)

**Priority**: 14.0

**Entry criteria**:
- [ ] Sortie 9 `COMPLETED`.

**Tasks**:
1. Add `@Option(name: [.customShort("r"), .customLong("reference")], help: …) var references: [String] = []` to `Generate`. Order is preserved, with no dedup.
2. In `validate()`, more than one `-` throws `ValidationError("only one --reference may read from stdin")`.
3. In `run()`, **before** `Vinetas.download` or any engine call:
   - Load each reference, using `ReferenceImage.load(path:)` for paths and `FileHandle.standardInput.readDataToEndOfFile()` → `ReferenceImage.load(data:source: .stdin)` for `-`.
   - Resolve the engine and run `ReferenceValidator`.
4. Build a `PanelRequest` with the references and call `CLIEnvironment.client.generate(_:)`.
5. For each reference with `originalSize != effectiveSize`, write one stderr line: `note: reference <n> (<source>) downscaled <w>×<h> → <w'>×<h'>`.
6. CLI tests (`CLIEnvironment` + `MockEngine`, `skipDownload`):
   - `-r a -r b` parses in order
   - `-r -` parses
   - `-r - -r -` is rejected
   - missing, empty and undecodable files each fail
   - 4 refs against a mock with max 3 fails
   - a mock with max 0 plus 1 ref fails
   - each failure asserts `loadModelCallCount == 0`
   - a 2048² reference produces the downscale note on stderr

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, with ≥ 9 new CLI tests passing.
- [ ] `./bin/vinetas generate --help` after `make build` (or the Debug product path) prints a line containing `-r, --reference`.

### Sortie 11: `generate` output — `-o -`, embedded metadata, warnings, real duration (RI-10, RI-12, RI-14)

**Priority**: 13.5

**Entry criteria**:
- [ ] Sortie 10 `COMPLETED`.
- [ ] RECON A-11 (`VinetasCLICore.swift:36-37, 175`) and A-14 (`:204, :209`).

**Tasks**:
1. When `output == "-"`:
   - Call `StdoutGuard.begin()` as the first statement of `run()`.
   - Write `ImageOutput.pngData(image:metadata:)` via `StdoutGuard.write`.
   - Write no sidecar and create no file named `-`.
2. When `output` is a path, write via `ImageOutput.writePanel` using `GeneratedPanel.metadata` (embedded plus sidecar). Remove the hand-built metadata that sets `seed ?? 0` and `durationSeconds: 0`.
3. When `--negative` is set and `metadata.negativeApplied == false`, write to stderr: `warning: <engine> does not apply negative prompts; --negative ignored`.
4. `--lora` flows into `style.loraPath`. A LoRA failure exits nonzero (via Sortie 7).
5. **Stream-purity test** (CI, `MockEngine` that calls `print("MOCK-LOG")` inside `generate`), marked `.serialized`. Redirect fd 1 and fd 2 to pipes and run `Generate` with `-r <tmp png> -o -`. Assert:
   - stdout starts with `89 50 4E 47 0D 0A 1A 0A`
   - stdout ends exactly at the `IEND` chunk's CRC
   - stdout decodes via `CGImageSourceCreateWithData`
   - `readEmbeddedMetadata` returns the reference's sha256
   - stderr contains `MOCK-LOG`
6. Test that a path output writes `x.png` and `x.json`, and the JSON's `durationSeconds > 0` and `seed` equal the mock's seed.

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, including the stream-purity test.
- [ ] `grep -n "styleConfig.seed ?? 0\|durationSeconds: 0" Sources/VinetasCLICore/VinetasCLICore.swift` returns no match.

### Sortie 12: `batch` and `storyboard` record what they used (RI-13)

**Priority**: 8.0

**Entry criteria**:
- [ ] Sortie 11 `COMPLETED`.
- [ ] RECON A-16: `VinetasCLICore.swift:337-338` writes a default `StyleConfig`; `StoryboardCommand.swift:135` calls only `writePNG`.

**Tasks**:
1. `batch`: generate each item via `CLIEnvironment.client.generate(PanelRequest)` and write with `ImageOutput.writePanel` from `GeneratedPanel.metadata`.
2. `storyboard`: the same for each panel.
3. `StoryboardCommand.swift:84`: if the bare `print(` is progress output, change it to `stderrPrint`. If it is the command's result output, keep it and note that in the sortie report.
4. Tests (`MockEngine`, `skipDownload`):
   - a batch YAML item with `steps: 7, guidance: 2.5` writes a sidecar recording `7` and `2.5`
   - a one-panel storyboard writes `.png` plus `.json`, and the PNG has an embedded `vinetas` iTXt

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, with the new tests passing.
- [ ] `grep -n "StyleConfig(width: output.width, height: output.height)" Sources/VinetasCLICore/VinetasCLICore.swift` returns no match.
- [ ] `grep -n "writePNG(image:" Sources/VinetasCLICore/Storyboard/StoryboardCommand.swift` returns no match.

### Sortie 13: Harden `character reference` — pre-download validation and the `--strength` warning (RI-5, RI-8)

**Priority**: 7.5

**Entry criteria**:
- [ ] Sorties 8 and 9 `COMPLETED`.
- [ ] `Character.Reference.run()` (`VinetasCLICore.swift:770-809`) downloads at `:792-797` before calling `Vinetas.generateReferenceSheets` at `:799`. `--model` parses silently via `VinetasModel(rawValue:) ?? .klein4b` (`:771`).

**Tasks**:
1. Before `Vinetas.download`, resolve the engine for `vinetasModel.descriptor` and run `ReferenceValidator` (count 1). `--model pixart-sigma` fails with no download and no load.
2. An unknown `--model` value throws `ValidationError("Unknown model '<value>'. Valid: klein4b, klein9b")` instead of silently falling back to klein4b.
3. When `--strength` is passed explicitly, write this to stderr: `warning: --strength has no effect and will be removed in the next minor release`. Make the option `Float?` so explicit use is detectable. Call the non-deprecated library overload.
4. Tests (`CLIEnvironment`, `skipDownload`, `MockEngine`):
   - `--model pixart-sigma` throws, and the download-attempt counter and `loadModelCallCount` are both 0
   - `--model bogus` throws
   - `--strength 0.5` emits the warning
   - no `--strength` emits no warning

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0, with 4 new tests passing.
- [ ] `grep -n "?? .klein4b" Sources/VinetasCLICore/VinetasCLICore.swift` returns no match inside `Reference`.

### Sortie 14: `info --print-io-dir` and documentation (RI-11b, docs)

**Priority**: 5.0 — leaf; runs last in WU-2 so the docs describe the finished CLI.

**Entry criteria**:
- [ ] Sorties 11, 12 and 13 `COMPLETED`.
- [ ] RECON V-07: `Acervo.sharedModelsDirectory` (`.build/checkouts/SwiftAcervo/Sources/SwiftAcervo/Acervo+PathResolution.swift:153`) resolves inside the App Group container (resolution logic at `:131-136`).
- [ ] Decision: the flag lives on the `Info` subcommand in `VinetasCLICore`, because the root `vinetas` command has `defaultSubcommand: Generate.self` (`Sources/vinetas/VinetasCLI.swift:34`). The signed `VinetasCLIMain` has its own root but reuses `Info` (RECON V-02), so the flag reaches both.

**Tasks**:
1. Add a `--print-io-dir` flag to `Info`. It derives `<App Group container>/vinetas-io/` from the Acervo path resolution: the container root, meaning the parent directory the App Group resolves to, **not** the models subdirectory. It creates the directory if missing, prints the absolute path alone on stdout, and exits 0.
2. Update `README.md` with a "Reference images and streams" section covering:
   - `-r/--reference` (order is priority, 1–3 refs, PNG/JPEG/HEIC)
   - `-r -` and `-o -`
   - the embedded `vinetas` iTXt metadata, with the sidecar still written for path outputs
   - `vinetas info --print-io-dir`
   - sandbox guidance: no Downloads entitlement, so use streams or the staging dir
3. Update the CLI reference under `docs/`. Find it with `grep -rln "vinetas generate" docs/*.md`; if none exists, add `docs/CLI_REFERENCE.md`. Cover the same content, plus the `--negative` warning and `character reference --strength` deprecation.
4. Test: `Info --print-io-dir` output ends with `/vinetas-io` (with or without a trailing slash) and the directory exists afterwards. Use a temp directory via Acervo's test override env var if one exists; otherwise the real container is acceptable locally, and the test is gated with `.enabled(if:)` on the container being resolvable.

**Exit criteria**:
- [ ] `make build` and `make test-unit` exit 0.
- [ ] `grep -c "\-\-reference" README.md` prints ≥ 1, and `grep -c "print-io-dir" README.md` prints ≥ 1.
- [ ] `grep -rn "files.downloads\|write to ~/Downloads" README.md docs/*.md` returns no match.

---

## WU-3 GPU validation (local only — never a CI gate)

### Sortie 15: Klein 4B reference-generation GPU tests

**Priority**: 4.5 — leaf; final acceptance evidence (§10 GPU, §11).

**Entry criteria**:
- [ ] WU-2 `COMPLETED`.
- [ ] Klein 4B weights are cached (`make link-test-models` exits 0). If not, the sortie is deferred, not failed.
- [ ] Determinism facts (OQ-6 research, 2026-09-26):
  - `Flux2Engine` always passes an explicit seed (`Flux2Engine.swift:323, 383`).
  - Flux2Core seeds the global `MLXRandom` (`.build/checkouts/flux-2-swift-mlx/Sources/Flux2Core/Pipeline/Flux2Pipeline.swift:1103-1106`; `LatentUtils.swift:33, 61`).
  - `make test-gpu` runs `-parallel-testing-enabled NO` (`Makefile:199-205`).
  - CI never runs this suite (`tests.yml` has no GPU target; `pixart-integration.yml:131` is restricted to `PixArtIntegrationTests`).

**Tasks**:
1. Add `Tests/SwiftVinetasGPUTests/ReferenceGenerationGPUTests.swift` as its **own** `.serialized` suite, gated on Klein 4B presence.
2. Klein 4B with 1 reference and with 3 references, at 1024×512 and 4 steps, each produce an image of exactly 1024×512.
3. The metadata records each reference's sha256 in order, plus the actual seed.
4. **Reproducibility, made to work rather than loosened:**
   - Read the embedded metadata from the first output via `readEmbeddedMetadata`.
   - Rebuild a `PanelRequest` from it: prompt, style, model, seed, steps, guidance, effective size and the same reference files.
   - Regenerate in the **same process with the same loaded engine**.
   - Render both `CGImage`s into identical 8-bit RGBA `CGContext`s and assert the byte buffers are equal. PNG file bytes differ by design (`generatedAt`, `durationSeconds`).
   - On a mismatch, log the first differing offset and the count of differing bytes.
5. Log a DINOv2 `similarity` score between the reference and the output. It is informational only, with no assertion.

**Exit criteria**:
- [ ] `make test-gpu`'s log shows `Suite "Reference Generation GPU Tests" passed` with all 3 cases executed (not skipped), including the reproducibility case, and introduces no new failures in other GPU suites. *(Amended 2026-09-27 per REPLAN: `make test-gpu` as a whole exits non-zero from pre-existing failures — Klein 9B not cached, BatchIntegrationTests 600 s timeouts, stale `modelID == "flux2"` assertion, nested-xcodebuild Checkpoint 1, noir color-count check — which surfaced once `link-test-models` could load Klein. Repairing/gating those suites is a post-mission follow-up.)*
- [ ] `make test-unit` exits 0, and the log contains no `ReferenceGenerationGPUTests`.
- [ ] `grep -n "ReferenceGenerationGPUTests" .github/workflows/*.yml` returns no match.

---

## WU-4 Flux floor bump (deferred)

### Sortie 16: Raise the flux-2-swift-mlx floor to the release that carries WU-0

> **REDUCED (user decision, 2026-09-27).** SwiftVinetas 0.20.1 (shipped by `vinetas-2b`) raises the flux floor to 3.4.3, and the following `-dev` commit restores `sibling(...)` with `from: "3.4.3"`. After the mission branch is rebased onto that `origin/development`, this sortie only adds the regression test. **Replacement definition:**
> - Entry: WU-0 `COMPLETED`; mission branch rebased onto post-0.20.1 `origin/development`; `grep -n '3.4.3' Package.swift` matches the flux dependency; no other SwiftVinetas sortie running.
> - Task: add `Tests/SwiftVinetasTests/Flux2StderrTests.swift` (`.serialized`): `Flux2Debug.log("probe")` (with `Flux2Debug` enabled) writes 0 bytes to stdout. Capture only via the existing async `StdioCapture` helper — never swap fds 1/2 any other way. Do not edit `Package.swift` or `Package.resolved`.
> - Exit: `make build` and `make test-unit` exit 0, including `Flux2StderrTests`; `git diff <new base> -- Package.swift Package.resolved` is empty.
>
> The original text is kept below for the record.

**Priority**: 6.0 — makes stdout purity hold for CI builds, not just local sibling builds.

**Entry criteria**:
- [ ] WU-0 `COMPLETED`.
- [ ] **Deferred until** `gh release list -R intrusive-memory/flux-2-swift-mlx` shows a release whose tag contains the `fix/logs-to-stderr` tip (`git -C ~/Projects/package-collection/pkg/flux-2-swift-mlx merge-base --is-ancestor <tip> <tag>`). This is flux's next patch release version; `vinetas-2b` tags it. Waiting does not escalate to FATAL.
- [ ] No other SwiftVinetas sortie is `RUNNING` (this sortie touches `Package.swift`/`Package.resolved`).

**Tasks**:
1. `Package.swift`: raise the flux `sibling(...)` `from:` to that release, and extend the comment above it with one line naming the stderr fix.
2. `make resolve`, then `make build`.
3. Add `Tests/SwiftVinetasTests/Flux2StderrTests.swift` (`.serialized`): with fd 1 redirected to a pipe, `Flux2Debug.log("probe")` writes 0 bytes to stdout.

**Exit criteria**:
- [ ] The flux-2-swift-mlx pin in `Package.resolved` equals the new release version.
- [ ] `grep -rln 'FileHandle.standardError' .build/checkouts/flux-2-swift-mlx/Sources/Flux2Core/Utils/StderrPrint.swift` matches.
- [ ] `make build` and `make test-unit` exit 0, including `Flux2StderrTests`.

---

## Priority Order

| Sortie | Name | Priority | Change |
|--------|------|----------|--------|
| 1 | Flux stderr shadows | 13.5 | was Sortie 0, task 1–4 |
| 2 | Flux rebase onto peer push | 9.0 | split from old Sortie 0 (deferred wait) |
| 3 | ReferenceImage | 26.5 | was 1 |
| 4 | Validator | 22.0 | was 2 |
| 5 | Metadata + iTXt | 17.5 | was 3 |
| 6 | Client API | 19.0 | split from old 4 |
| 7 | LoRA in client API | 12.0 | split from old 4 |
| 8 | Existing paths + strength | 10.5 | was 5 |
| 9 | CLI seam + StdoutGuard | 16.5 | was 6 |
| 10 | `--reference` | 14.0 | was 7 |
| 11 | `-o -` output | 13.5 | was 8 |
| 12 | batch/storyboard | 8.0 | was 9 |
| 13 | `character reference` hardening | 7.5 | split from old 10 |
| 14 | `--print-io-dir` + docs | 5.0 | split from old 10 |
| 15 | GPU tests | 4.5 | was 11 |
| 16 | Flux floor bump | 6.0 | was 12 |

The hard constraints (dependencies, layers) leave the scores' ordering intact within each work unit. Sortie 6 (19.0) scores above Sortie 5 (17.5), but it depends on Sortie 5, so it stays after it.

## Parallelism Structure

**Critical path**: S3 → S4 → S6 → S7 → S9 → S10 → S11 → S12 → S14 → S15 (10 sorties). S5 and S8 sit off the critical path but are serialized with it (see the build constraint below).

**Build constraint**: every SwiftVinetas sortie runs `make build`/`make test-unit` against the same `DerivedData` and `Package.resolved`. **SwiftVinetas sorties therefore run strictly one at a time.** Parallelism exists only across repositories, where the flux worktree has its own build directory.

**Parallel execution groups**:
- **Group A** (dispatch together at `start`):
  - WU-0 Sortie 1 (Agent 1, flux worktree, builds in the worktree)
  - WU-1 Sortie 3 (Agent 2, SwiftVinetas)
- **Group B**: WU-1 Sorties 4 → 5 → 6 → 7 → 8, sequential on Agent 2's lane. WU-0 Sortie 2 is dispatched whenever `vinetas-2b` signals its push, independently of this lane.
- **Group C**: WU-2 Sorties 9 → 14, sequential.
- **Group D**: WU-3 Sortie 15.
- **Deferred lane**: WU-4 Sortie 16. It fires when the flux release exists, and is dispatched only between SwiftVinetas sorties (never concurrently with one).

**Agent constraints**: at most 2 concurrent sortie agents, one per repository. Every sortie builds, so none can be delegated to a no-build sub-agent. The supervisor coordinates the flux merge with `vinetas-2b` itself.

**Missed opportunities (rejected)**: S5 (metadata) and S4 (validator) are logically independent, and so are S9 (CLI seam) and WU-1. Running them concurrently in one working tree would collide on DerivedData and on the `MockEngine.swift` edits. Worktree-per-sortie was rejected: sibling-pattern path resolution (`../<Name>`) breaks when the package moves out of `pkg/`.

---

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them (WU-0 edits only its own worktree). -->

Sibling pattern is active: local builds compile against the `../<Name>` checkouts, which are ahead of their pins. To confirm a Flux2Core API, read `.build/checkouts/flux-2-swift-mlx` (pinned 3.4.2), **not** the sibling.

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| intrusive-memory/flux-2-swift-mlx | 3.4.2 (`857dd73`) | `~/Projects/package-collection/pkg/flux-2-swift-mlx` | SIBLING_ACTIVE, LOCAL_AHEAD (+6), LOCAL_DIRTY (peer session) |
| intrusive-memory/SwiftAcervo | 0.25.0 (`87ec22c`) | `~/Projects/package-collection/pkg/SwiftAcervo` | SIBLING_ACTIVE, LOCAL_AHEAD (+4), LOCAL_DIRTY |
| intrusive-memory/SwiftTuberia | 0.9.0 (`22c5d70`) | `~/Projects/package-collection/pkg/SwiftTuberia` | SIBLING_ACTIVE, LOCAL_AHEAD (+1), LOCAL_DIRTY |
| intrusive-memory/pixart-swift-mlx | 0.8.1 (`e8cf968`) | `~/Projects/package-collection/pkg/pixart-swift-mlx` | SIBLING_ACTIVE, LOCAL_AHEAD (+2) |
| intrusive-memory/glosa-av | 0.8.0 (`6b24e1b`) | `~/Projects/package-collection/pkg/glosa-av` | SIBLING_ACTIVE, LOCAL_AHEAD (+2) |
| intrusive-memory/SwiftCompartido | 7.2.4 (`2a45c5c`) | `~/Projects/package-collection/pkg/SwiftCompartido` | SIBLING_ACTIVE, LOCAL_AHEAD (+2) |
| marcprux/universal, apple/swift-argument-parser, DePasqualeOrg/swift-tokenizers, apple/swift-certificates, swift-crypto, swift-asn1 | per Package.resolved | — | NO_LOCAL_CHECKOUT |

**Caution for every SwiftVinetas sortie**: local builds use the peer's in-flight flux `development` through the sibling. A local build break that originates in `../flux-2-swift-mlx` is **not** this mission's defect. Report it as `REPLAN` evidence rather than editing flux.

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). Each entry MUST be resolved before refinement can proceed past Pass 1. -->

### Resolved decisions (2026-09-26)

| OQ | Decision | Source |
|----|----------|--------|
| OQ-1 | Researched rather than accepted as written. The plan was partly wrong, so the old Sortie 5 was rewritten as Sortie 8 and Sortie 13 was added. Findings: PixArt reference sheets load the model before failing; the source-photo decode is PNG-only; a hard-coded shared router blocks mocks; a naive deprecation overload would be ambiguous; the CLI downloads before validating | user: "do not accept — research" |
| OQ-2 | Accept the corrected LoRA citations | user |
| OQ-3 | Flux change first, in a worktree (WU-0); `StdoutGuard` kept | user |
| OQ-4 | App version bump, app CLI command list, and skill fix are post-release follow-ups | user |
| OQ-5 | Lock §12 Q1–Q6 as recommended | user: "accept 4" |
| OQ-6 | Not flaky in CI (never runs there). Made to work: same-process rerun from embedded metadata, comparing pixel buffers, not PNG bytes | user |

## Open Questions & Missing Documentation (Pass 5)

_No unresolved items._ Everything Pass 5 found was fixed in place:

| Sortie | Issue type | Fix |
|--------|-----------|-----|
| 1 (old 0) | Vague criterion ("smoke run shows stderr") | Replaced with a file/grep check, a `[judgment]` on byte-exact formatting, and a behavioural test moved to Sortie 16 (the peer forbade flux tests) |
| 1 (old 0) | Sortie spanned an external wait | Split: the wait is now deferred Sortie 2 |
| 3 | `[judgment]` on error messages | Rewritten as test assertions (message contains the path) |
| 3 | HEIC encode may be unavailable on CI VMs | HEIC test gated on encoder availability |
| 5 | `[judgment]` on backward decoding | Rewritten as a fixture-string test |
| 9 | "`@TaskLocal` (or equivalent)" undecided | Decided: `@TaskLocal`, plus a `skipDownload` hook |
| 14 | "root or `generate`" undecided | Decided: `info --print-io-dir`. The root has `defaultSubcommand: Generate` and the signed CLI has its own root |
| 14 | Docs target undefined | Rule: the existing `docs/*.md` that mentions `vinetas generate`, otherwise a new `docs/CLI_REFERENCE.md` |
| 16 | `make resolve` unverified | Confirmed present in the Makefile target list |

## Summary

| Metric | Value |
|--------|-------|
| Work units | 5 |
| Total sorties | 16 (2 deferred on external signals: S2, S16) |
| Open questions | 0 open, 6 resolved |
| Dependencies mapped | 12 |
| Dependency structure | WU-0 ∥ WU-1 → WU-2 → WU-3; WU-4 deferred on the flux release |
| Max concurrent agents | 2 (one per repository) |

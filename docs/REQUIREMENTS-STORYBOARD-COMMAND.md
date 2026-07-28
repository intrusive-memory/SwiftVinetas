---
type: doc
state: incomplete
updated: 2026-07-12
---

# REQUIREMENTS: `vinetas storyboard` — screenplay → panels via glosa-av `<shot>`

> Status: **Scoping / design.** No implementation yet. This document is grounded
> in a codebase audit (2026-07-12) of `SwiftVinetas`, `glosa-av` (`GlosaCore`),
> `glosa-tools`, and `SwiftCompartido`. Line references are current as of that
> audit.

## 1. Goal

Add a new `vinetas storyboard` subcommand that takes a **screenplay file** as
input, parses it with **glosa-av (`GlosaCore`)** to extract the `<shot>`
directives, folds the "empty-prompt = defaults" convention into a set of
**effective shots**, and generates one panel per renderable shot through the
existing Vinetas generation engine.

This is the **"downstream Vinetas orchestrator"** that `GlosaCore`'s `Shot` type
already documents as the intended consumer of its parse-and-carry output
(`glosa-av/Sources/GlosaCore/Shot.swift:1-35`).

## 2. Prior art — this is NOT already scoped

- `apps/Vinetas/docs/incomplete/FEAT-SEQUENCE.md` is a **different, adjacent**
  feature: cross-panel *consistency* via a `Repertorio`/`Ficha` SwiftData asset
  library and FLUX.2 reference conditioning. It never mentions screenplays or
  `<shot>` parsing. No overlap in scope; they may share a seam later (a shot
  referencing a Ficha), but that is explicitly out of scope for v1 here.
- No `storyboard` command, and no glosa dependency, exists in `SwiftVinetas`
  today (`grep` of `Package.swift` → none).

## 3. The contract (what glosa-av already gives us)

`GlosaCore` is **parse-and-carry**. It emits every `<shot>` in `documentIndex`
order and does **not** compute effective shots — folding defaults is *our* job.

- `Shot` (`glosa-av/Sources/GlosaCore/Shot.swift`) carries the full
  `vinetas generate` option set: `prompt, style, model, aspect, width, height,
  steps, guidance, seed, negative, lora, loraScale, output, preview, telemetry`,
  plus `documentIndex`. `model`/`aspect` are **raw strings** (GlosaCore does not
  map them onto Vinetas enums; its validator only *warns* on unrecognized
  values).
- Shots surface on `CompilationResult.shots` and `GlosaScriptAnnotation.shots`
  and `GlosaScore.shots`, all in ascending `documentIndex` order
  (`CompilationResult.swift:142`).
- **Field parity with `Generate` is exact.** `Shot`'s attributes were
  deliberately mirrored from `Generate`
  (`SwiftVinetas/Sources/VinetasCLICore/VinetasCLICore.swift:23-117`). Every
  `Shot` field maps 1:1 onto a `Generate` option — see §7.

### 3.1 The defaults convention (the core logic we must implement)

Per `Shot.swift:17-35`:

- A `<shot>` **with a non-empty `prompt`** → renders a panel. For any attribute
  it does **not** set, it inherits the current active default. Its own set
  attributes win per-attribute.
- A `<shot>` **with an empty `prompt`** → renders **nothing**. Instead each
  attribute it names **replaces** that entry in the active default set, going
  forward in `documentIndex` order.
- Defaults accumulate: later empty-prompt shots update individual entries; they
  do not reset the whole set.

This is a left-fold over `shots` sorted by `documentIndex`, carrying a mutable
"active defaults" dictionary of the non-prompt attributes.

**Edge cases to pin down (see §11):**
- Does `seed` participate in defaults like every other attribute? (Recommended:
  **yes** — treat uniformly. A defaulted seed means a whole run is reproducible
  from one declaration. Setting seed as a default and then not overriding it
  yields identical seeds across panels, which is a user choice, not a bug.)
- `style` and `negative` as defaults: **yes**, uniform treatment.
- An empty-prompt shot that sets **no** attributes: a no-op (or clears nothing).
  Treat as no-op.

## 4. Ingestion path (file → notes → shots)

`GlosaCore.parseFountainWithDiagnostics(notes: [String])` takes an **already-
extracted** array of `[[ ]]` note strings — it does **not** read a screenplay
file. The reference implementation for turning a file into that note stream is
`glosa-tools`' `extractNotesAndDialogue(from:)`
(`glosa-tools/Sources/glosa/CompileCommand.swift:106`), which uses
**`SwiftCompartido.GuionParsedElementCollection(file:)`**.

`GuionParsedElementCollection(file:)`
(`SwiftCompartido/Sources/SwiftCompartido/Sendable/GuionParsedScreenplay.swift:180`)
handles all three formats we need:
- `.fountain` — Fountain text
- `.highland` — Highland bundle (ZIP or plain text)
- `.fdx` — Final Draft XML

Note stream = the collection's `.comment` elements (which hold `[[ ]]` note text
without brackets), in document order. For shots specifically we do **not** need
the dialogue-line association (`<shot>` is a standalone block event keyed only by
its position among notes), so the minimal path is:

1. `GuionParsedElementCollection(file:)` → screenplay elements.
2. Collect `.comment` element texts (and, to match glosa-tools exactly, the
   dialogue raw texts) in document order → `[String]` notes.
3. `GlosaParser().parseFountainWithDiagnostics(notes:)` →
   `(score: GlosaScore, diagnostics:)` → use `score.shots` + `diagnostics`.
   (For FDX, `parseFDXWithDiagnostics(data:)` is the parallel entry point.)

**Recommendation:** reuse `SwiftCompartido` + `GlosaCore` rather than hand-
rolling a `[[ ]]` regex scanner. Rationale in §6.

## 5. Command surface

```
vinetas storyboard <screenplay> [options]
```

- `<screenplay>` (positional, required) — path to a `.fountain`, `.highland`, or
  `.fdx` file.
- `--output-dir <dir>` (default `./storyboard`) — directory for generated panels.
- `--model <m>` — **fleet-level default model** applied to shots that declare no
  model and inherit no default. Default `klein4b`. (A shot's own `model`, or an
  active default, still wins.)
- `--dry-run` — parse, fold defaults, and print the resolved effective-shot plan
  (index, prompt, resolved model/aspect/seed/…) **without** generating. Critical
  for authoring/debugging screenplays.
- `--continue-on-error` — keep going if a single panel fails (default: **stop**
  on first failure, so a 40-panel run doesn't silently drop panels).
- `--telemetry` — same JSONL trace flag as `generate`/`batch`; forwarded per
  panel.
- Standard fleet overrides may be reconsidered later; keep v1 minimal.

### 5.1 Behavior

1. Parse screenplay → shots + diagnostics.
2. Surface `GlosaCore` diagnostics (warnings on unrecognized `model`/`aspect`,
   etc.) to stderr up front.
3. Fold defaults (§3.1) → ordered list of **effective renderable shots** (those
   with a non-empty prompt).
4. If `--dry-run`: print the plan and exit 0.
5. Validate each effective shot's `model`/`aspect` against Vinetas vocab
   (`VinetasModel`: `klein4b`, `klein9b`, `pixart-sigma`; `AspectRatio`
   cases). Decide per §11 whether an unknown value is a hard error or a warn-and-
   fall-back-to-fleet-default.
6. Download required model weights (union of models across the plan) before
   iterating, mirroring `batch`.
7. Generate each panel in order via the **in-process** engine path (§7), writing
   outputs per §8, printing `Panel N/total` progress to stderr.

## 6. Where the code lives + dependencies

**Recommendation: implement in `VinetasCLICore`** (the shared subcommand library
in `SwiftVinetas`), so the command is automatically available in both the
`vinetas` executable and the `apps/Vinetas` host (which re-exports
`VinetasCLICore` subcommands — `apps/Vinetas/VinetasCLI/VinetasCLIMain.swift`).

New dependencies for `SwiftVinetas`:
- **`glosa-av` (`GlosaCore`)** — the `<shot>` parser. Foundation-only leaf, no
  heavy transitive weight.
- **`SwiftCompartido`** (`GuionParsedElementCollection`) — robust screenplay file
  parsing across `.fountain`/`.highland`/`.fdx`.

Both are already sibling packages in the collection and both are what
`glosa-tools` uses, so this keeps a **single source of truth** for
screenplay→notes extraction.

### Rejected alternatives

- **Shell out to `vinetas generate` from glosa-tools.** Avoids adding deps to
  SwiftVinetas but introduces a subprocess boundary, requires the `vinetas`
  binary on PATH, and re-pays model load per panel. Worse for a 40-panel run.
  Rejected.
- **Hand-rolled `[[ ]]` regex note scanner** to avoid the `SwiftCompartido` dep.
  Fragile against FDX, Highland ZIP bundles, boneyard, title pages. The parser
  already exists and is battle-tested. Rejected for v1; keep as a fallback only
  if the `SwiftCompartido` dep proves problematic.

## 7. `Shot` → generation mapping (1:1)

Map each **effective** shot onto the same in-process path `Generate.run` uses
(build a `StyleConfig` + model + aspect and call the engine router). Do **not**
route through `PromptFile`/`batch` — `Panel` is lossy (no per-panel model, steps,
guidance, negative, lora — see `PromptFile.swift:68`).

| `Shot` field | `Generate` / engine target | Notes |
|---|---|---|
| `prompt` | prompt argument | empty → not a render (sets defaults) |
| `style` | `StyleConfig.stylePrompt` | |
| `model` | `VinetasModel(rawValue:)` | validate; §11 for unknown |
| `aspect` | `AspectRatio(rawValue:)` | validate; explicit w/h wins |
| `width`/`height` | `StyleConfig` dims | override aspect |
| `steps` | `StyleConfig.steps` | |
| `guidance` | `StyleConfig.guidanceScale` | **`Double`→`Float` cast** |
| `seed` | `StyleConfig.seed` | both `UInt64`; PixArt truncates to `UInt32` |
| `negative` | `StyleConfig.negativePrompt` | |
| `lora` | LoRA path | |
| `loraScale` | LoRA scale | **`Double`→`Float` cast** |
| `output` | per-shot output path | see §8 for precedence |
| `preview` | preview flag | FLUX/Klein4b-only; §11 |
| `telemetry` | telemetry flag | prefer the fleet `--telemetry`; see §11 |

**Refactor opportunity:** extract the `Shot`/args → `StyleConfig` + model +
aspect resolution out of `Generate.run` into a shared helper so `generate` and
`storyboard` share one mapping and can't drift.

## 8. Output naming

- If a shot sets `output`, honor it (relative paths resolved under
  `--output-dir`).
- Otherwise auto-name sequentially: `panel-001.png`, `panel-002.png`, … indexed
  over **effective** (renderable) shots, matching `batch`'s convention
  (`VinetasCLICore.swift:331-338`).
- Print each written filename + the seed actually used (as `batch` does), so runs
  are reproducible.

## 9. Diagnostics & validation

- Print `GlosaCore` diagnostics (parse warnings) before generating.
- Unknown `model`/`aspect` on a shot: **decision needed** (§11). Recommended:
  **warn + fall back to fleet default**, so one typo in a 40-shot script doesn't
  abort the whole run — but make it loud.
- Empty screenplay / zero `<shot>` directives: exit 0 with a clear "no shots
  found" message (not an error).
- `--preview` combined with a non-klein4b shot model: mirror `Generate.run`'s
  existing `ValidationError` (`VinetasCLICore.swift:131`).

## 10. Testing

- **Unit (CI-safe, no GPU):** the defaults-folding fold is pure logic and must be
  unit-tested hard — empty-prompt sets defaults; later prompt inherits; per-
  attribute override wins; later empty-prompt updates one entry; seed handling;
  no-op empty shot.
- **Unit:** screenplay → shots extraction on small `.fountain` and `.fdx`
  fixtures (assert count, order, carried attributes). Highland ZIP fixture if
  cheap.
- **Unit:** `--dry-run` plan output is stable/snapshot-tested.
- **Integration (local only, GPU):** end-to-end small screenplay → N panel files
  on disk, gated behind the existing `test-integration` model-presence pattern.
- Add fixtures under `Tests/.../Fixtures/` (a couple of hand-authored
  screenplays with `[[<shot .../>]]` notes, including the defaults convention).

## 11. Open questions / decisions to lock

1. **Unknown `model`/`aspect` on a shot** — hard error vs. warn-and-fall-back?
   *(Recommend: warn + fall back to fleet default, loudly.)*
2. **`seed` in the defaults set** — treated uniformly like other attrs?
   *(Recommend: yes.)*
3. **`telemetry`/`preview` as per-shot attributes** — honor per-shot, or ignore
   the shot-level flags and let the fleet `--telemetry`/`--preview` govern?
   *(Recommend: fleet-level governs; ignore per-shot `telemetry`; honor per-shot
   `preview` only if it doesn't conflict with the shot's model.)*
4. **`output` collisions** — if two shots set the same `output`, later
   overwrites? *(Recommend: warn on collision, still write.)*
5. **Failure policy default** — stop-on-first vs. continue. *(Recommend: stop by
   default, `--continue-on-error` to opt out; print a summary of
   succeeded/failed at the end.)*
6. **FDX vs Fountain note-stream parity** — confirm `.comment` extraction from
   `GuionParsedElementCollection` yields the same shot stream for an FDX file as
   `parseFDXWithDiagnostics(data:)` would. May need the FDX path
   (`parseFDXWithDiagnostics`) instead of the Fountain-notes path for `.fdx`
   inputs. **Verify during implementation.**
7. **Command name** — `storyboard` (chosen) vs `render`/`shots`. `storyboard`
   reads best against the app's storyboard framing.

## 12. Rough task breakdown

1. Add `glosa-av`/`GlosaCore` + `SwiftCompartido` deps to `SwiftVinetas`
   (sibling-aware, per the project's `sibling()` Package.swift pattern).
2. Screenplay → notes/shots ingestion helper (reuse glosa-tools'
   `extractNotesAndDialogue` shape; support `.fountain`/`.highland`/`.fdx`).
3. Pure **defaults-folding** function `[Shot] → [EffectiveShot]` + exhaustive
   unit tests.
4. Extract shared `Shot`/args → `StyleConfig`+model+aspect mapping helper out of
   `Generate.run`.
5. `Storyboard: AsyncParsableCommand` in `VinetasCLICore` (parse → diagnostics →
   fold → dry-run → validate → download → generate loop → write).
6. Register `Storyboard` in the `vinetas` subcommand list
   (`SwiftVinetas/Sources/vinetas/VinetasCLI.swift`) and confirm it surfaces in
   `apps/Vinetas`.
7. Fixtures + unit + integration tests; Makefile wiring if needed.
8. Docs: README/AGENTS `vinetas storyboard` usage; cross-link the glosa `<shot>`
   authoring convention.

---
type: project
title: SwiftVinetas — storyboard shots on GLOSA notation 2.0, render records, cloud vocabulary
updated: 2026-10-20
state: draft
depends_on:
  - glosa-av 0.9.0 (GLOSA notation 2.0: JSON shots, Shot.effective, Shot.renderDigest)
  - SwiftVinetas 0.25.0 released first (docs/missions/release-0.25)
---

# SwiftVinetas — storyboard shots, render records, cloud vocabulary

Five changes so that a screenplay's GLOSA shots, the images rendered from them, and any
editor showing them agree on one shot shape and can tell when an image is out of date.

## 1. Read shots through GlosaCore 0.9.0

- Raise the glosa-av floor to `0.9.0` (`Package.swift`, sibling pattern).
- `vinetas storyboard` (`Sources/VinetasCLICore/Storyboard/`) reads notation 2.0 JSON
  shots and notation 1.0 tags through `GlosaParser`; it does not parse notes itself.
- **Behaviour change to note in the CHANGELOG:** `ShotResolver` today inherits `output`
  from defaults shots (`ShotResolver.swift:79`); GlosaCore's fold does not (an inherited
  `output` makes every later panel overwrite one file).
- **Replace `ShotResolver`'s fold** (`ShotResolver.swift:31` `resolve`, `:64` `merge`)
  with `Shot.effective(given:)` / `GlosaScore.effectiveShots` from GlosaCore, so the
  fold is identical everywhere. Keep `ShotResolver` only if something else still needs
  it; otherwise delete it with its tests.

## 2. `ref` and `character` in storyboards

- Each effective shot's `ref` entries become the panel's references, in order; its
  `character` becomes `PanelRequest.character` (loaded via `CharacterManager`).
- **Reference name resolution**, documented in `docs/CLI_REFERENCE.md`, first match
  wins:
  1. an absolute path;
  2. a path relative to the **project root** (the nearest ancestor of the screenplay
     holding `PROJECT.md`), else the screenplay's folder;
  3. `characters/<NAME>/` in the project root — the first image among `portrait.*`,
     `ref-portrait.*`, then any image in that folder, alphabetically;
  4. a Vinetas character with that slug (its reference images).
  
  An unresolved name fails that panel with a message naming the entry and the places
  searched; `--continue-on-error` continues.
- Reference count over the model's `maxReferenceImages` fails the panel before any
  vendor call, with the existing errors: `referencesUnsupported` when the model accepts
  none (the BFL and Stability models, `maxReferenceImages` 0 — `ReferenceValidator.swift:25`),
  `tooManyReferences` when it accepts some but fewer than given.

## 3. Output resolution

A relative `output` resolves against the project root, else the screenplay's folder —
**never the process's current directory** (today: `StoryboardCommand.swift:263–278`
resolves it under `--output-dir`, which defaults to `./storyboard` in the CWD).
`--output-dir` keeps placing shots that have no `output`. Absolute paths unchanged.
The current resolution moved away from the CWD because the **sandboxed** CLI cannot write
there (comment in `outputURL`); the project root must be checked the same way — the
signed CLI in the app bundle can write only where it has been granted access. If it
cannot, the panel fails with a message naming the path and the remedy, rather than
silently falling back to the CWD.

## 4. The render record

`PanelMetadata` (`Core/ImageOutput.swift:60`) gains
`glosa: { notation: String, digest: String, shot: <shot object> }` — the notation
version, `Shot.renderDigest`, and the **effective shot as authored**, encoded with
GlosaCore's bare-object codec (`Shot.schemaJSON()` / `Shot(schemaJSON:)`, glosa-av 0.9.0)
— schema form, unknown keys at the top level, no `documentIndex`. Not the synthesized
`Codable` form. Written by:

- `vinetas storyboard`, for every panel;
- `vinetas generate --shot-json <file|->`: a bare shot object (schema 2.0, decoded with
  `Shot(schemaJSONData:)`) supplies the generation parameters and is recorded; explicit flags may not be combined with it;
- `VinetasClient.generate(_:…)` when the `PanelRequest` carries a `shot` (new optional
  field), so host apps record it too.

A storyboard manifest built from these sidecars uses the same `shot` object, so a
consumer never translates between shapes. Existing sidecars without `glosa` keep
decoding.

## 5. Vocabulary and prompt panel

- **`VinetasVocabulary.ModelSummary`** gains every `CloudModelDescriptor`
  (`Cloud/CloudModelDescriptor.swift`: `openai-gpt-image-2.5-flare`,
  `openai-gpt-image-2.5-sunburst`, `google-nano-banana-2.1`,
  `google-gemini-3.1-flash-image`, `google-gemini-3-pro-image`, `bfl-flux-2-pro`,
  `bfl-flux-2-flex`, `stability-core`, `stability-ultra`) with `isCloud: Bool` and
  `maxReferenceImages: Int`, as plain values — so a host that links only
  `VinetasVocabulary`/`VinetasUI` gets them without networking or MLX. Core already maps
  descriptors to summaries (`ModelDescriptor.summary`, `ModelDescriptor.swift:71`), but
  `VinetasVocabulary` cannot import `CloudModelDescriptor`, so its list is **maintained
  by hand**; a test in `SwiftVinetasTests` asserts it equals the core mapping.
- **`VinetasUI.VinetasPromptDraft`** gains `references: [String]` and `character:
  String?` (Codable, defaulted). The composer gains a References row (ordered list, add /
  remove / reorder, capped at the selected model's limit, disabled at 0) and a Character
  row, both behind `showsReferenceControls: Bool = false` so existing hosts are
  unchanged; and a `statusSection` view slot for host-supplied content.
- Keep `VinetasVocabulary` and `VinetasUI` free of `SwiftVinetas` core, MLX and
  networking (existing package rule).

## Tests

- Storyboard: a synthetic notation 2.0 fixture and its 1.0 twin produce identical panel
  plans; defaults fold via GlosaCore; `ref` names resolve by each rule; unresolved name
  error text; output resolution for project-root, document-folder and absolute paths.
- Record: sidecar `glosa.digest == Shot.renderDigest` for the same effective shot, for a
  local engine and a stubbed-HTTP cloud engine; old sidecars decode.
- `--shot-json` happy path and conflict with explicit flags.
- Vocabulary sync test; VinetasUI draft Codable round-trip with and without the new
  fields; composer hides the new rows by default.
- No private screenplays or characters in fixtures.

## Release

Minor release after this mission; update `docs/CLI_REFERENCE.md` and the README.

## Notes from recon (2026-10-20)

- Local builds resolve every intrusive-memory sibling from its local checkout
  (`Package.resolved` has no pins for them), so this machine compiles glosa-av's
  unreleased `development`. CI resolves released tags. Do not start this mission until
  glosa-av 0.9.0 is **tagged**, or CI will build different source from local.

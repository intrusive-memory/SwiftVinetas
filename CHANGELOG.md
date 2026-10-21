# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.26.0] - 2026-10-20

### Changed

- **SwiftCompartido floor raised to 7.4.0.** Fountain notes may now span lines and contain `]`, so `vinetas storyboard` reads GLOSA notation 2.0 shots written in their canonical multi-line form, including `ref` arrays. Earlier SwiftCompartido versions silently dropped them.
- glosa-av floor raised to 0.9.0; the core `SwiftVinetas` target now links `GlosaCore`
  (`VinetasVocabulary` and `VinetasUI` still do not).
- `vinetas storyboard` folds shots with `GlosaScore.effectiveShots`, so the fold is the same
  everywhere. Notation 2.0 JSON shots and notation 1.0 tags are both read through `GlosaParser`.
  Three behaviour changes follow from it:
  - `output` is no longer inherited from a defaults shot (an inherited `output` made every later
    panel overwrite one file).
  - `ref`, `character` and `caption` are now honoured; they were silently dropped before.
  - A whitespace-only `prompt` is now a per-panel error (it obeys `--continue-on-error`); it used
    to be treated as a defaults shot.
- A relative `output` in a storyboard now resolves against the project root (the nearest
  ancestor of the screenplay holding `PROJECT.md`), else the screenplay's folder. It never
  resolves against the current directory and is no longer placed under `--output-dir`.
  `--output-dir` still places shots that have no `output`. If the target folder is not writable
  (for example, in the sandboxed app CLI) the panel fails with the path and the remedy instead of
  falling back to the current directory.
- `vinetas generate`: `Generate.model` and `Generate.loraScale` are now optional on the public CLI
  struct (so `--shot-json` can detect explicit flags). Runtime defaults (`klein4b`, `0.8`) are
  unchanged.
- Source compatibility: `VinetasPromptComposer` is now generic,
  `VinetasPromptComposer<StatusSection: View>`. Call sites that use the existing initializer are
  unchanged, but code that names the type explicitly (stored properties, type annotations) must
  now write `VinetasPromptComposer<EmptyView>`.

### Added

- `PanelMetadata.glosa` (`notation`, `digest`, `shot`): the render record of a panel made from a
  GLOSA shot. `shot` is the effective shot as a bare schema JSON object (decode with
  `Shot(schemaJSONData:)` or `GlosaRecord.decodedShot()`). Written for every storyboard panel, by
  `vinetas generate --shot-json`, and by `VinetasClient.generate` when `PanelRequest.shot` is set.
  Sidecars written before this release still decode. glosa-av writes seeds above 2^53-1 as
  decimal strings.
- `PanelRequest.shot` (optional).
- `vinetas generate --shot-json <file|->`: a bare GLOSA 2.0 shot object supplies the generation
  parameters. It cannot be combined with the prompt argument or other generation flags.
- Storyboard `ref` and `character`: `ref` entries resolve by four rules (absolute path, project
  root / screenplay folder, `characters/<NAME>/` in the project root, Vinetas character slug) and
  become the panel's references; `character` is loaded through `CharacterManager`. A reference
  count over the model's limit fails the panel with `referencesUnsupported` or
  `tooManyReferences` before any vendor call.
- `ModelSummary`: the nine cloud models, `isCloud`, `maxReferenceImages`, `ModelSummary.cloud` and
  `ModelSummary.allIncludingCloud`. `ModelSummary.all` is unchanged (on-device models only);
  `named(cli:)` searches all of them. New `Flux2ModelDescriptor.engineMaxReferenceImages`.
- `VinetasPromptDraft.references` and `VinetasPromptDraft.character` (Codable, defaulted).
- `VinetasPromptComposer`: `showsReferenceControls` (default `false`, so existing hosts are
  unchanged) and a `statusSection` view builder.

### Removed

- `ShotResolver` and its tests; the fold now lives in GlosaCore.

### Known issues

- glosa-av follow-up: a whitespace-only `prompt` should be treated as empty upstream. Until then
  `vinetas storyboard` reports it as a per-panel error.

[Unreleased]: https://github.com/intrusive-memory/SwiftVinetas/compare/v0.26.0...HEAD
[0.26.0]: https://github.com/intrusive-memory/SwiftVinetas/compare/v0.25.0...v0.26.0

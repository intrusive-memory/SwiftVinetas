---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 070c05dd876806c2735675fa9ea0172198516b124adb7da25f1434d5d51daf5e
project_head: d3afaf8
search_root: ~/Projects
generated: 2026-10-20
verdict: BLOCKED
---

# RECON_REPORT.md — SwiftVinetas: storyboard shots, render records, cloud vocabulary

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**BLOCKED** — 31 assumptions checked, 23 confirmed, 8 blocking (7 expected upstream-dependency blocks, 1 requirement error), 0 unverifiable.

This is the second recon. The revised requirements fixed the first run's requirement error (A-14, now CONFIRMED), and its four new presuppositions (A-27 to A-30) all hold. The upstream blocks are unchanged: glosa-av 0.9.0 (campaign mission A) and SwiftVinetas 0.25.0 (mission R) do not exist yet. One new requirement error surfaced (A-31). Neither this requirement nor the glosa-av notation-2 requirement provides a way to encode or decode the bare `shot` object in schema form, and the render record and `--shot-json` both depend on one.

The first report's counts were wrong. It said "19 confirmed, 7 blocking", but its own table had 18 confirmed and 8 blocking (A-06 to A-12 plus A-14). The findings themselves were right.

The hub verified everything directly (no spokes), read-only. Repo claims were checked against the `development` checkout at `d3afaf8`. HEAD moved from `e06c2a0` by docs-only commits, and no manifest or lock file changed. Dependency claims were checked against glosa-av's tag `v0.8.1` and its local HEAD `eed3dc9`. Planned upstream APIs were checked against glosa-av `docs/missions/notation-2/REQUIREMENTS.md`, the working copy revised today.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-DEP | glosa-av is a dependency via the sibling pattern; floor to be raised | repo | CONFIRMED | `Package.swift:130-133` `sibling("glosa-av", …, from: "0.8.1")`; `GlosaCore` linked into VinetasCLICore `Package.swift:209` |
| A-02 | A-FILE | `vinetas storyboard` lives in `Sources/VinetasCLICore/Storyboard/` | repo | CONFIRMED | Folder holds `StoryboardCommand.swift`, `ScreenplayShots.swift`, `ShotResolver.swift` |
| A-03 | A-API | `ShotResolver.resolve` at `:31`, `merge` at `:64` | repo | CONFIRMED | `ShotResolver.swift:31` `public static func resolve(_ shots: [Shot]) -> [Shot]`; `:64` `static func merge(base: Shot, override: Shot) -> Shot` |
| A-04 | A-INVARIANT | Only the storyboard command (and tests) need `ShotResolver` | repo | CONFIRMED | Sole source caller `StoryboardCommand.swift:65`; tests `ShotResolverTests.swift`, `ScreenplayShotsTests.swift:67,90`; comment-only mention `StoryboardPlanTests.swift:10` |
| A-05 | A-BEHAVIOR | Storyboard reads shots through `GlosaParser`, does not parse notes itself | repo | CONFIRMED | `ScreenplayShots.swift:24` `GlosaParser()`; `:30` `parseFDXWithDiagnostics`; `:37` `parseFountainWithDiagnostics`; `extractNotes` `:48` only collects note text |
| A-06 | A-API | `Shot.effective(given:)` exists in GlosaCore | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | `grep -rn 'func effective' Sources` → none at `v0.8.1` or `eed3dc9`. Planned: notation-2 REQUIREMENTS § 2 item 4 (`Shot.effective(given defaults: [Shot]) -> Shot`), so the name matches |
| A-07 | A-API | `GlosaScore.effectiveShots` exists | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | Absent; planned § 2 item 5 |
| A-08 | A-API | `Shot.renderDigest` exists | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | `grep -rn renderDigest Sources` → none; planned § 2 item 6 |
| A-09 | A-DATA | Notation 2.0 JSON shots, `GlosaVersion.notation`, shot schema with unknown keys | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | Absent; planned § 2 items 1–3 (`GlosaVersion.notation`, `schemas/shot.schema.json`, `Shot.extraAttributes`) |
| A-10 | A-API | `Shot.ref` / `Shot.character` exist | dep:intrusive-memory/glosa-av | CONFIRMED_LOCAL_ONLY (expected — mission A) | Local `eed3dc9` `Shot.swift:120` `public var ref: [String]?`, `:125` `public var character: String?`; `git show v0.8.1:Sources/GlosaCore/Shot.swift` has neither |
| A-11 | A-DEP | glosa-av 0.9.0 is released | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | Newest tag `v0.8.1`; `development` is 3 commits past it |
| A-12 | A-CONFIG | SwiftVinetas 0.25.0 released first (mission R) | repo | REFUTED (expected — mission R) | `git tag --sort=-v:refname` → `v0.24.0` newest |
| A-13 | A-API | `PanelRequest` has `character` and ordered references | repo | CONFIRMED | `Sources/SwiftVinetas/PanelRequest.swift:22` `references: [ReferenceImage]`, `:30` `character: Character?`; no `shot` field yet (new work) |
| A-14 | A-BEHAVIOR | Over-limit references fail before any vendor call: `referencesUnsupported` at limit 0 (BFL, Stability), `tooManyReferences` otherwise; `ReferenceValidator.swift:25` | repo | CONFIRMED | `Reference/ReferenceValidator.swift:25` `guard max > 0`, `:26` throws `referencesUnsupported`, `:29` `tooManyReferences`; called pre-dispatch `Vinetas.swift:500`; storyboard goes through it via `CLIEnvironment.client.generate` `StoryboardCommand.swift:130`. BFL/Stability descriptors (`CloudModelDescriptor.swift:195-258`) omit `maxReferenceImages`, so they take the default 0 (`:69`) |
| A-15 | A-BEHAVIOR | `StoryboardCommand.swift:263–278` resolves relative `output` under `--output-dir`, default `./storyboard` in the CWD | repo | CONFIRMED | `:263-278` doc + `outputURL(for:in:)` (ends `:278`); `:273-275` `hasPrefix("/")` else `outputDir.appendingPathComponent(output)`; default `:25`; CWD-relative `URL(fileURLWithPath: outputDir)` `:93` |
| A-16 | A-DATA | `PanelMetadata` at `Core/ImageOutput.swift:60`; old sidecars keep decoding | repo | CONFIRMED | `:60` `public struct PanelMetadata: Codable, Sendable, Equatable`; `:57-59` later fields optional so older files decode |
| A-17 | A-API | `CloudModelDescriptor` has exactly the 9 listed ids and `maxReferenceImages` | repo | CONFIRMED | `CloudModelDescriptor.swift:105,122,144,161,178,196,212,229,245`; `:42` `maxReferenceImages: Int`; `:260` `all` |
| A-18 | A-API | `VinetasVocabulary.ModelSummary` exists, lacks cloud models, `isCloud`, `maxReferenceImages` | repo | CONFIRMED | `Sources/VinetasVocabulary/ModelSummary.swift:20`; `:220` `all = [klein4B, pixartSigmaXL]`; no `isCloud` / `maxReferenceImages` |
| A-19 | A-API | `VinetasPromptDraft` is Codable and tolerant of missing keys | repo | CONFIRMED | `VinetasPromptDraft.swift:29`; `init(from:)` `:127` with `decodeIfPresent` (`:130-133`) |
| A-20 | A-API | A prompt composer view exists in VinetasUI | repo | CONFIRMED | `VinetasPromptComposer.swift:34`, init `:116`; no `showsReferenceControls` / `statusSection` yet (new work) |
| A-21 | A-INVARIANT | VinetasVocabulary / VinetasUI free of core, MLX, networking | repo | CONFIRMED | `Package.swift:170` VinetasVocabulary has no deps; `:176-177` VinetasUI → `["VinetasVocabulary"]`; imports in both are only `Foundation`, `SwiftUI`, `VinetasVocabulary` |
| A-22 | A-API | `CharacterManager` loads by slug and exposes reference images | repo | CONFIRMED | `CharacterManager.swift:19`; `:151` `loadCharacter(slug:)`; `:66` `referenceImageURLs(for:)` |
| A-23 | A-API | `--continue-on-error` exists and continues past a failed panel | repo | CONFIRMED | `StoryboardCommand.swift:43-44`; catch `:136-144` |
| A-24 | A-API | `VinetasClient.generate(_ PanelRequest, …)` exists | repo | CONFIRMED | `Vinetas.swift:39` `public final class VinetasClient`; `:269` `public func generate(` (PanelRequest overload) |
| A-25 | A-API | `vinetas generate` exists (to gain `--shot-json`) | repo | CONFIRMED | `VinetasCLICore.swift:45` `public struct Generate`; `--reference` `:113-124`, `--character` `:139` |
| A-26 | A-FILE | `docs/CLI_REFERENCE.md` documents `vinetas storyboard` | repo | CONFIRMED | `docs/CLI_REFERENCE.md:293` |
| A-27 | A-API | Core maps descriptors to summaries via `ModelDescriptor.summary`, `ModelDescriptor.swift:71` | repo | CONFIRMED | `Engine/ModelDescriptor.swift:57` `extension ModelDescriptor`; `:71` `public var summary: ModelSummary`; `:72` `self as? CloudModelDescriptor` (capability flags, engine name, subtitle) |
| A-28 | A-CONFIG | A test in `SwiftVinetasTests` can see both the core mapping and VinetasVocabulary's list | repo | CONFIRMED | Test target deps `Package.swift:232-235` (`SwiftVinetas`, `VinetasCLICore`); `Sources/SwiftVinetas/VinetasVocabularyExports.swift:6` `@_exported import VinetasVocabulary`; precedent `Tests/SwiftVinetasTests/ModelSummaryRoundTripTests.swift:14,19` already asserts `descriptor.summary == ModelSummary.x` |
| A-29 | A-BEHAVIOR | The `outputURL` comment records that the sandboxed CLI cannot write to the CWD | repo | CONFIRMED | `StoryboardCommand.swift:266-272` ("Under the sandboxed CLI shipped in the app bundle that is not merely wrong, it is unwritable") |
| A-30 | A-CONFIG | The CLI in the app bundle is sandboxed (writes only where granted) | repo (consuming app) | CONFIRMED | App repo `VinetasCLI/VinetasCLI.entitlements`: `com.apple.security.app-sandbox` true, `files.user-selected.read-write` true. SwiftVinetas' own `cli.entitlements` has app groups only and no sandbox key, so the unsandboxed dev CLI won't reproduce the failure |
| A-31 | A-API | GlosaCore can encode the effective shot as a bare `shot` object in its shot schema (unknown keys included), and decode one (`--shot-json`) | dep:intrusive-memory/glosa-av (planned API) | REFUTED (requirement error) | No such API in the notation-2 plan. § 2 item 7 `Shot.serialize()` emits the **note** form `[[ {"shot": {…}} ]]`, not a bare object. `Shot` is synthesized `Codable` (`Shot.swift:47`), which encodes `documentIndex` (`:51`), so after item 3 it will also nest unknown keys under `extraAttributes` instead of flattening them as the schema (`additionalProperties: true`) requires. The parser reads notes, not bare objects |

### Blocking findings

#### (a) Expected upstream-dependency blocks

**A-06, A-07, A-08, A-09, A-10, A-11: glosa-av 0.9.0 (mission A) is neither built nor released.** `Shot.effective(given:)`, `GlosaScore.effectiveShots`, `Shot.renderDigest`, JSON shots, `GlosaVersion.notation` and the shot schema don't exist anywhere yet. `Shot.ref`/`character` exist only in the unreleased local checkout. Every name this requirement uses matches the revised notation-2 plan.
**Options**:
1. Wait for mission A to tag glosa-av 0.9.0, then re-run recon *(recommended)*
2. Re-run with `--accept-risk` and gate every dependent sortie on the tag

**A-12: SwiftVinetas 0.25.0 (mission R) is not released.** The newest tag is `v0.24.0`.
**Options**:
1. Wait for mission R to ship 0.25.0, then re-run recon *(recommended)*

#### (b) Requirement errors

#### A-31 — REFUTED: no bare shot-object codec, here or upstream
**Claim**: "`PanelMetadata` gains `glosa: { …, shot: <shot object> }` … the effective shot as authored, encoded in GlosaCore's shot schema (unknown keys included)", and "`vinetas generate --shot-json <file|->`: a shot object (schema 2.0)". Source: REQUIREMENTS.md § 4, lines 60–67. A storyboard manifest uses "the same `shot` object" (lines 71–72).
**Found**: The glosa-av notation-2 plan offers `Shot.serialize()` (note form, wrapped in `[[ {"shot": …} ]]`), the note parser, and `extraAttributes` as a separate field. Nothing produces or accepts the bare schema object. The synthesized `Codable` is not schema form: it carries `documentIndex` and would nest unknown keys.
**Impact**: Mission A won't supply what this requirement needs, so waiting for A doesn't clear this block. Without a stated codec, a sortie would invent one in SwiftVinetas, and then "one shot shape everywhere" depends on two encoders agreeing.
**Options**:
1. Add a bare-object codec to mission A's API, e.g. `Shot.jsonObject() -> GlosaJSONValue` / `Shot(jsonObject:)`, validated against `schemas/shot.schema.json` with unknown keys flattened, and have this requirement name it. *(recommended: it keeps the one schema in one place)*
2. Have this requirement say SwiftVinetas derives the object by unwrapping `Shot.serialize()` and parses `--shot-json` by wrapping input in `{"shot": …}` for the note parser. This works but depends on the note form's text layout.

## Local Dependency Map

`Package.resolved` has **no pins** for any intrusive-memory dependency. Every sibling directory exists, so this machine builds all six from `../<name>`. CI resolves remote `upToNextMajor` ranges with no lock entry, which makes them effectively `UNPINNED` there.

| Dependency | Declared | Resolved (this machine) | Local checkout | Local HEAD | Status |
|------------|----------|-------------------------|----------------|-----------|--------|
| intrusive-memory/glosa-av | `from: 0.8.1` | `../glosa-av` (path) | `~/Projects/package-collection/pkg/glosa-av` (`development`) | `eed3dc9`, 3 ahead of `v0.8.1`; dirty (2 docs files only) | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | `from: 7.3.1` | path | `…/pkg/SwiftCompartido` | `af5a734`, 1 ahead of `v7.3.1` | SIBLING_ACTIVE |
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.3` | path | `…/pkg/flux-2-swift-mlx` | `9a36b26`, 1 ahead of `v3.4.3` | SIBLING_ACTIVE |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` | path | `…/pkg/SwiftAcervo` | `13e2879`, 4 ahead of `v0.25.0`; untracked docs only | SIBLING_ACTIVE |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` | path | `…/pkg/SwiftTuberia` | `d74977a`, 1 ahead of `v0.9.0`; untracked docs only | SIBLING_ACTIVE |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.2` | path | `…/pkg/pixart-swift-mlx` | `3ce2541`, 1 ahead of `v0.8.2` | SIBLING_ACTIVE |
| marcprux/universal | `from: 5.3.0` | `5.3.0` (`7919463ce636`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | `1.8.2` (`6a52f3251125`) | — | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor 0.7.1` | `0.7.1` (`e4e01cb59fb7`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-certificates / swift-crypto / swift-asn1 | `1.0.0` / `3.0.0` / `1.0.0` | `1.19.4` / `3.15.1` / `1.7.1` | — | — | NO_LOCAL_CHECKOUT |

`.build/checkouts/glosa-av` is at `92e81cb` (`v0.8.1`). That is a stale remote-resolution copy, not the source this machine compiles. glosa-av has one authoritative checkout, so there is no ambiguity.

### Drift and ambiguity notes

- **glosa-av is sibling-active and ahead of its tag.** Local builds see `Shot.ref`/`character`, and CI against `v0.8.1` doesn't. Don't start any sortie that touches GlosaCore until 0.9.0 is tagged and the floor is raised.
- The dirty working trees in glosa-av, SwiftAcervo and SwiftTuberia hold documentation only, with no source changes, so no verdict depends on them.

## Notable surprises (non-blocking)

- **Folding `output` will change behavior.** Today `ShotResolver.swift:79` inherits `output` from defaults (`override.output ?? base.output`). The planned `Shot.effective` will **not** inherit `output` (notation-2 § 2 item 4). After the switch, a storyboard whose defaults set `output` no longer sends every panel to one file. That is the intended fix, but it is a visible change: name it in the CHANGELOG and assert it in the 2.0/1.0 twin-fixture test.
- **Sandbox testing is app-side only.** The project-root writability check (§ 3) can only fail for real under the app's sandboxed CLI (A-30). SwiftVinetas' own `cli.entitlements` isn't sandboxed, so a package test can't reproduce the denial. Plan the check as an injectable writability probe that is unit-tested with a stub.
- **The sync test has a template.** `ModelSummaryRoundTripTests.swift` already checks the local descriptors against `ModelSummary`. The cloud sync test (A-28) extends it, and `summary` (`ModelDescriptor.swift:71-89`) has to gain `isCloud` / `maxReferenceImages`.
- **Deleting `ShotResolver` means editing three test files.** Its asserts live in `ShotResolverTests.swift` and in `ScreenplayShotsTests.swift:67,90`, and there is a comment reference in `StoryboardPlanTests.swift:10`.

## Unverifiable

None.

## Handoff to breakdown

- `CONFIRMED` facts are safe as sortie entry criteria without re-checking.
- Before breakdown: resolve A-31 (preferably by amending mission A's API and naming that API here), wait for glosa-av 0.9.0 and SwiftVinetas 0.25.0, then re-run recon. A-06 to A-12 should then come back CONFIRMED against the tags, not the sibling checkout.
- Local paths: glosa-av `~/Projects/package-collection/pkg/glosa-av`; SwiftVinetas `~/Projects/package-collection/pkg/SwiftVinetas`.

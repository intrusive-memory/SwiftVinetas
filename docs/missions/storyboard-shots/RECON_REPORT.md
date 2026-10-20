---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 1e41ed8bdaaf33956e2fdcab0ba40c4a5607b6ea8bf2d71cb17ba2f469e00f22
project_head: e06c2a0
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

**BLOCKED** — 26 assumptions checked, 19 confirmed, 7 blocking (6 expected upstream-dependency blocks, 1 requirement error), 0 unverifiable.

Most of the block is expected: the mission depends on glosa-av 0.9.0 (campaign mission A) and on SwiftVinetas 0.25.0 being released first (mission R). Neither exists yet. Every presupposition about existing SwiftVinetas code holds except one point of wording about which reference error fires (A-14).

Verification was done by the hub directly (no spokes), read-only, against the `development` checkout at `e06c2a0` for repo claims, and against glosa-av at both its local HEAD and its tag `v0.8.1` for dependency claims.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-DEP | glosa-av is a dependency via the sibling pattern, floor to be raised from the current one | repo | CONFIRMED | `Package.swift:130-133` `sibling("glosa-av", …, from: "0.8.1")`; GlosaCore linked into VinetasCLICore `Package.swift:209` |
| A-02 | A-FILE | `vinetas storyboard` lives in `Sources/VinetasCLICore/Storyboard/` | repo | CONFIRMED | `StoryboardCommand.swift`, `ScreenplayShots.swift`, `ShotResolver.swift` in that folder |
| A-03 | A-API | `ShotResolver.resolve` at `:31`, `merge` at `:64` | repo | CONFIRMED | `ShotResolver.swift:31` `public static func resolve(_ shots: [Shot]) -> [Shot]`; `:64` `static func merge(base:override:)` |
| A-04 | A-INVARIANT | Only the storyboard command (and its tests) need `ShotResolver` | repo | CONFIRMED | Sole source caller `StoryboardCommand.swift:65`; tests `Tests/SwiftVinetasTests/ShotResolverTests.swift`, `ScreenplayShotsTests.swift:67,90` |
| A-05 | A-BEHAVIOR | Storyboard reads shots through `GlosaParser` and does not parse notes itself | repo | CONFIRMED | `ScreenplayShots.swift:24` `GlosaParser()`; `:30` `parseFDXWithDiagnostics`; `:37` `parseFountainWithDiagnostics`. `extractNotes` (`:48-62`) only builds the `[[ ]]` note stream from SwiftCompartido elements, no tag parsing |
| A-06 | A-API | `Shot.effective(given:)` exists in GlosaCore | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | Absent at `v0.8.1` and at local HEAD `518ff02`; `grep -rn effective Sources` hits only `ScoreResolver.swift:267` (unrelated). `Shot.swift:32` still says GlosaCore "does not compute effective shots" |
| A-07 | A-API | `GlosaScore.effectiveShots` exists | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | Same search; absent in `Sources/GlosaCore/GlosaScore.swift` |
| A-08 | A-API | `Shot.renderDigest` exists | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | `grep -rn renderDigest Sources` → no hits |
| A-09 | A-DATA | Notation 2.0 JSON shots, GlosaCore shot schema with unknown keys preserved, `GlosaVersion.notation` | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | No JSON shot parsing or shot schema at `v0.8.1` or local HEAD; specified as new work in glosa-av `docs/missions/notation-2/REQUIREMENTS.md` |
| A-10 | A-API | `Shot.ref` / `Shot.character` exist | dep:intrusive-memory/glosa-av | CONFIRMED_LOCAL_ONLY (expected — mission A) | Local HEAD `518ff02` `Shot.swift:120` `public var ref: [String]?`, `:125` `public var character: String?`; `git show v0.8.1:Sources/GlosaCore/Shot.swift` has neither. Mission A's 0.9.0 includes them (notation-2 REQUIREMENTS line 79) |
| A-11 | A-DEP | glosa-av 0.9.0 is released | dep:intrusive-memory/glosa-av | REFUTED (expected — mission A) | Latest tag `v0.8.1`; local `development` is 2 commits past it |
| A-12 | A-CONFIG | SwiftVinetas 0.25.0 is released first (mission R) | repo | REFUTED (expected — mission R) | `git tag --sort=-v:refname` → `v0.24.0` newest |
| A-13 | A-API | `PanelRequest` has `character` and ordered references | repo | CONFIRMED | `PanelRequest.swift:22` `references: [ReferenceImage]`, `:30` `character: Character?`; no `shot` field yet (the new work) |
| A-14 | A-BEHAVIOR | Reference count over `maxReferenceImages` fails before any vendor call with the existing `tooManyReferences` | repo | STALE | Fails before vendor call: `Vinetas.swift:500` `ReferenceValidator.validate` precedes engine dispatch; `CloudImageEngine.swift:116-124` also guards. But when the limit is **0**, the error is `referencesUnsupported` (`ReferenceValidator.swift:25-26`; cloud path throws `CloudEngineError.unsupportedFeature`, `CloudImageEngine.swift:119-120`). The four `bfl-*` / `stability-*` models take the default `maxReferenceImages: 0` (`CloudModelDescriptor.swift:69`) |
| A-15 | A-BEHAVIOR | Output resolution at `StoryboardCommand.swift:263–277` puts relative `output` under `--output-dir`, which defaults to `./storyboard` in the CWD | repo | CONFIRMED | `:263-278` `outputURL(for:in:)` → `outputDir.appendingPathComponent(output)` for non-`/` paths; `:25` default `"./storyboard"`; `:93` `URL(fileURLWithPath: outputDir)` (CWD-relative). Range is off by one line at the end, not material |
| A-16 | A-DATA | `PanelMetadata` at `Core/ImageOutput.swift:60`, Codable, older sidecars keep decoding | repo | CONFIRMED | `ImageOutput.swift:60` `public struct PanelMetadata: Codable, Sendable, Equatable`; doc `:55-59` "every field added after the original schema is optional and omitted when nil" |
| A-17 | A-API | `CloudModelDescriptor` with the 9 listed ids and `maxReferenceImages` | repo | CONFIRMED | `CloudModelDescriptor.swift:105,122,144,161,178,196,212,229,245` (exactly the 9 ids); `:42` `maxReferenceImages: Int`; `:260` `static let all` |
| A-18 | A-API | `VinetasVocabulary.ModelSummary` exists and lacks cloud models, `isCloud`, `maxReferenceImages` | repo | CONFIRMED | `ModelSummary.swift:20`; `:220` `all = [klein4B, pixartSigmaXL]`; no `isCloud`/`maxReferenceImages` fields |
| A-19 | A-API | `VinetasUI.VinetasPromptDraft` is Codable and tolerant of missing keys | repo | CONFIRMED | `VinetasPromptDraft.swift:29`; custom `init(from:)` `:127-152` uses `decodeIfPresent` throughout |
| A-20 | A-API | A prompt composer view exists in VinetasUI | repo | CONFIRMED | `VinetasPromptComposer.swift:34` `public struct VinetasPromptComposer: View`, init `:116`; no `showsReferenceControls` / `statusSection` yet (the new work) |
| A-21 | A-INVARIANT | VinetasVocabulary and VinetasUI do not link SwiftVinetas core, MLX or networking | repo | CONFIRMED | `Package.swift` `VinetasVocabulary` target has no dependencies; `VinetasUI` depends only on `VinetasVocabulary`; imports across both are only `Foundation`, `SwiftUI`, `VinetasVocabulary` |
| A-22 | A-API | `CharacterManager` loads a character by slug and exposes its reference images | repo | CONFIRMED | `CharacterManager.swift:19` struct; `:151` `loadCharacter(slug:)`; `:66` `referenceImageURLs(for:)` |
| A-23 | A-API | `--continue-on-error` exists and continues past a failed panel | repo | CONFIRMED | `StoryboardCommand.swift:43`; catch block `:140-147` |
| A-24 | A-API | `VinetasClient.generate(_ PanelRequest, …)` exists | repo | CONFIRMED | `Vinetas.swift:39` `public final class VinetasClient`; `:269` `public func generate(_ request: PanelRequest, characters:stepProgress:)` |
| A-25 | A-API | `vinetas generate` exists (to gain `--shot-json`) | repo | CONFIRMED | `VinetasCLICore.swift:45` `public struct Generate`; `--reference` `:124`, `--character` `:139` |
| A-26 | A-FILE | `docs/CLI_REFERENCE.md` documents `vinetas storyboard` | repo | CONFIRMED | `docs/CLI_REFERENCE.md:293` `## \`vinetas storyboard\`` |

### Blocking findings

#### (a) Expected upstream-dependency blocks

A-06, A-07, A-08, A-09, A-10, A-11 — glosa-av 0.9.0 (mission A) not built or released. `Shot.effective(given:)`, `GlosaScore.effectiveShots`, `Shot.renderDigest`, JSON shots and the shot schema are absent everywhere. `Shot.ref`/`character` exist only in the unreleased local checkout.
**Options**:
1. Wait for mission A (glosa-av 0.9.0) to release, then re-run recon *(recommended)*
2. Re-run with `--accept-risk` and gate every dependent sortie on the release

A-12 — SwiftVinetas 0.25.0 (mission R) not released; newest tag `v0.24.0`.
**Options**:
1. Wait for mission R to ship 0.25.0, then re-run recon *(recommended)*

#### (b) Requirement errors

#### A-14 — STALE
**Claim**: "Reference count over the model's `maxReferenceImages` fails the panel before any vendor call (existing `tooManyReferences`)." (REQUIREMENTS.md § 2, lines 41–42)
**Found**: Pre-vendor validation exists (`Vinetas.swift:500`), but the error is `tooManyReferences` only when the limit is above 0. At 0 (`bfl-flux-2-pro`, `bfl-flux-2-flex`, `stability-core`, `stability-ultra`) it is `referencesUnsupported` (`ReferenceValidator.swift:25-26`).
**Impact**: A sortie that asserts `tooManyReferences` for a shot with `ref` on a BFL/Stability model fails its own test.
**Options**:
1. Amend the requirement: "fails with the existing `tooManyReferences`, or `referencesUnsupported` when the model takes none" *(recommended)*
2. Make the storyboard map both to one message (new behavior, so it needs a stated requirement)

## Local Dependency Map

`Package.resolved` holds **no pins** for any intrusive-memory dependency. Every sibling directory exists, so this machine builds all six from `../<name>` paths. CI (`CI=true`) resolves remote `upToNextMajor` ranges with no lock entry, so they are effectively `UNPINNED` there.

| Dependency | Declared | Resolved (this machine) | Local checkout | Local HEAD | Status |
|------------|----------|-------------------------|----------------|-----------|--------|
| intrusive-memory/glosa-av | `from: 0.8.1` | `../glosa-av` (path) | `~/Projects/package-collection/pkg/glosa-av` (`development`) | `518ff02`, 2 ahead of `v0.8.1` | SIBLING_ACTIVE, LOCAL_AHEAD |
| intrusive-memory/SwiftCompartido | `from: 7.3.1` | `../SwiftCompartido` (path) | `~/Projects/package-collection/pkg/SwiftCompartido` | `af5a734`, 1 ahead of `v7.3.1` (version-mark commit) | SIBLING_ACTIVE |
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.3` | path | `…/pkg/flux-2-swift-mlx` | `9a36b26`, 1 ahead of `v3.4.3` | SIBLING_ACTIVE |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` | path | `…/pkg/SwiftAcervo` | `13e2879`, 4 ahead of `v0.25.0` | SIBLING_ACTIVE |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` | path | `…/pkg/SwiftTuberia` | `d74977a`, 1 ahead of `v0.9.0` | SIBLING_ACTIVE |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.2` | path | `…/pkg/pixart-swift-mlx` | `3ce2541`, 1 ahead of `v0.8.2` | SIBLING_ACTIVE |
| marcprux/universal | `from: 5.3.0` | `5.3.0` (`7919463ce636`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | `1.8.2` (`6a52f3251125`) | — | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor 0.7.1` | `0.7.1` (`e4e01cb59fb7`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-certificates / swift-crypto / swift-asn1 | `1.0.0` / `3.0.0` / `1.0.0` | `1.19.4` / `3.15.1` / `1.7.1` | — | — | NO_LOCAL_CHECKOUT |

`.build/checkouts/glosa-av` sits at `92e81cb` (`v0.8.1`), so it is a stale remote-resolution copy, not the source this machine compiles. glosa-av has exactly one authoritative checkout (no ambiguity).

### Drift and ambiguity notes

- **glosa-av is sibling-active and ahead of its tag.** Local builds already see `Shot.ref`/`character`; CI against `v0.8.1` does not. Do not start the `ref`/`character` sorties until 0.9.0 is tagged and the floor is raised. Otherwise they compile here and fail in CI.
- **The Package.swift floor bump is the mission's own first step** (§ 1). It cannot land until A-11 clears.

## Notable surprises (non-blocking)

- **`ModelDescriptor.summary` already maps a `CloudModelDescriptor` to a `ModelSummary`** (`Engine/ModelDescriptor.swift:71-89`), carrying the capability flags, engine name and subtitle. So hosts that link SwiftVinetas already get cloud summaries. The gap is only the static `ModelSummary.all` in VinetasVocabulary. `CloudModelDescriptor` lives in SwiftVinetas core and VinetasVocabulary cannot import it, so "derived from `CloudModelDescriptor`" has to mean a hand-mirrored list in VinetasVocabulary plus a sync test in `SwiftVinetasTests`, which links both. The new `isCloud` / `maxReferenceImages` fields also need to flow through `summary`.
- `ShotResolver`'s only non-test caller is the storyboard command, so the requirement's "otherwise delete it with its tests" path applies. That includes the `ShotResolver` assertions inside `ScreenplayShotsTests.swift`, not just `ShotResolverTests.swift`.
- The current `outputURL` comment (`StoryboardCommand.swift:266-272`) records a deliberate move *away* from CWD resolution toward `--output-dir` because the sandboxed CLI cannot write to the CWD. The new project-root rule must keep the sandbox in mind: the project root has to be writable under the shipped CLI's entitlements.

## Unverifiable

None.

## Handoff to breakdown

- `CONFIRMED` facts are safe as sortie entry criteria without re-checking.
- Re-run recon once glosa-av 0.9.0 is tagged and SwiftVinetas 0.25.0 is released. A-06 through A-12 should then flip to CONFIRMED against the tag, not the sibling checkout.
- Fix the A-14 wording in REQUIREMENTS.md § 2 before breakdown.
- Local paths: glosa-av `~/Projects/package-collection/pkg/glosa-av`; SwiftVinetas `~/Projects/package-collection/pkg/SwiftVinetas`.

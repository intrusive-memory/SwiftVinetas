---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: c9b6c256be1fdbaf4047689ddfbb2241c953d324d2075b07f17aea8ba7c33aee
project_head: 238abc8
search_root: ~/Projects
generated: 2026-10-20
verdict: CLEAR
---

# RECON_REPORT.md — SwiftVinetas: storyboard shots, render records, cloud vocabulary

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**CLEAR** — 35 assumptions checked, 35 confirmed, 0 blocking, 0 unverifiable.

**Pass 4 (2026-10-20, re-run by `breakdown`).** REQUIREMENTS.md was amended after pass 3: § 1 now decides A-32 (option 1 — the core `SwiftVinetas` target links `GlosaCore`) and lists the three fold behaviour changes; § 4 names the raw `schemaJSONData()` embedding. A-32 is therefore a deliverable, not a premise. New claims A-34 and A-35 were verified. Nothing in any manifest or lock file moved since pass 3 (`project_head` still `238abc8`); glosa-av `development` (`7459eb8`) still differs from `v0.9.0` (`ac24606`) only in `GlosaVersion.swift:3`.

Pass 3 text follows.

This is the third recon. Both upstream gates have shipped: glosa-av is tagged `v0.9.0`
(`ac24606`) and SwiftVinetas is tagged `v0.25.0` (`4d7dc4a`). Every glosa-av API this
requirement names exists at the `v0.9.0` tag with the shape the requirement uses, so the
earlier upstream blocks (A-06 to A-12) and the earlier codec error (A-31) are all cleared.

One new requirement error remains (A-32). § 4 has `VinetasClient.generate` record a GLOSA
shot carried on `PanelRequest`. Both types live in the core `SwiftVinetas` target, and that
target does not link GlosaCore. Only `VinetasCLICore` does.

The hub verified everything directly, read-only, with no spokes. SwiftVinetas claims were
checked on `development` at `238abc8` (`0.25.0-dev`). glosa-av claims were checked with
`git show v0.9.0:<path>`, not against the working tree.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-DEP | glosa-av is a sibling-pattern dependency whose floor is to be raised to 0.9.0 | repo | CONFIRMED | `Package.swift:130-133` `sibling("glosa-av", …, from: "0.8.1")`. The floor is still 0.8.1, so raising it is a deliverable of this mission. `GlosaCore` is linked into VinetasCLICore at `Package.swift:209` |
| A-02 | A-FILE | `vinetas storyboard` lives in `Sources/VinetasCLICore/Storyboard/` | repo | CONFIRMED | The folder holds `StoryboardCommand.swift`, `ScreenplayShots.swift` and `ShotResolver.swift`; `commandName: "storyboard"` is at `StoryboardCommand.swift:15` |
| A-03 | A-API | `ShotResolver.resolve` is at `:31` and `merge` at `:64` | repo | CONFIRMED | `ShotResolver.swift:31` `public static func resolve(_ shots: [Shot]) -> [Shot]`; `:64` `static func merge(base: Shot, override: Shot) -> Shot` |
| A-04 | A-INVARIANT | Only the storyboard command and its tests need `ShotResolver` | repo | CONFIRMED | The only source caller is `StoryboardCommand.swift:65`, plus a doc comment at `:10`. Tests: `ShotResolverTests.swift`, `ScreenplayShotsTests.swift:67,90`, and a comment at `StoryboardPlanTests.swift:10` |
| A-05 | A-BEHAVIOR | Storyboard reads shots through `GlosaParser` and does not parse notes itself; at 0.9.0 the same entry points read 2.0 JSON and 1.0 tags | repo + dep | CONFIRMED | SwiftVinetas calls GlosaParser at `ScreenplayShots.swift:24,30,37` (`parseFDXWithDiagnostics`, `parseFountainWithDiagnostics`). In glosa-av v0.9.0, `GlosaParser.swift:92-93` routes block candidates to `readBlockDirectiveNote` (`GlosaParser+BlockJSON.swift:56`), and `:222-234` still parses 1.0 `<shot/>` tags, adding an info-level `.deprecatedTagDirective` diagnostic |
| A-06 | A-API | `Shot.effective(given:)` | dep:intrusive-memory/glosa-av@v0.9.0 | CONFIRMED | `Shot+Effective.swift:24` `public func effective(given defaults: [Shot]) -> Shot` |
| A-07 | A-API | `GlosaScore.effectiveShots` | dep@v0.9.0 | CONFIRMED | `Shot+Effective.swift:61` `extension GlosaScore`; `:68` `public var effectiveShots: [Shot]` |
| A-08 | A-API | `Shot.renderDigest` | dep@v0.9.0 | CONFIRMED | `Shot+Digest.swift:43` `public var renderDigest: String`. It is the SHA-256 of the JCS form of `schemaJSON()` minus `caption`, `output`, `preview` and `telemetry` (`:10`) |
| A-09 | A-DATA | Notation 2.0 JSON shots, `GlosaVersion.notation`, and a shot schema with unknown keys | dep@v0.9.0 | CONFIRMED | `GlosaVersion.swift:8` `public static let notation = "2.0"`; `Sources/GlosaCore/schemas/shot.schema.json`; `Shot.swift:138` `public var extraAttributes: [GlosaJSONMember]`; JSON `{"shot": …}` notes are read at `GlosaParser+BlockJSON.swift:56-105` |
| A-10 | A-API | `Shot.ref` and `Shot.character` | dep@v0.9.0 | CONFIRMED | `Shot.swift:123` `public var ref: [String]?`; `:128` `public var character: String?` |
| A-11 | A-DEP | glosa-av 0.9.0 is released | dep | CONFIRMED | Tag `v0.9.0` resolves to commit `ac24606` ("Release v0.9.0: GLOSA notation 2.0 (JSON block directives) (#25)") |
| A-12 | A-CONFIG | SwiftVinetas 0.25.0 is released first | repo | CONFIRMED | Tag `v0.25.0` resolves to `4d7dc4a`; `development` HEAD is `238abc8` "Mark development as 0.25.0-dev, restore sibling pattern" |
| A-13 | A-API | `PanelRequest` has a `character` and ordered references | repo | CONFIRMED | `PanelRequest.swift:22` `references: [ReferenceImage]`; `:30` `character: Character?`. There is no `shot` field yet; adding one is new work |
| A-14 | A-BEHAVIOR | Over-limit references fail before any vendor call: `referencesUnsupported` when the limit is 0, `tooManyReferences` otherwise | repo | CONFIRMED | `ReferenceValidator.swift:25` `guard max > 0`; `:26` and `:29` throw. It runs before dispatch at `Vinetas.swift:500` and `:623`. The BFL and Stability descriptors (`CloudModelDescriptor.swift:196-258`) set no `maxReferenceImages`, so they get the default 0 (`:69`) |
| A-15 | A-BEHAVIOR | Storyboard resolves a relative `output` under `--output-dir`, which defaults to `./storyboard` in the CWD | repo | CONFIRMED | `StoryboardCommand.swift:265` `outputURL(for:in:)`; `:273-275` checks `hasPrefix("/")` and otherwise calls `outputDir.appendingPathComponent(output)`; the default is set at `:25`; `:93` builds the CWD-relative `URL(fileURLWithPath: outputDir)` |
| A-16 | A-DATA | `PanelMetadata` is at `Core/ImageOutput.swift:60`, and old sidecars keep decoding | repo | CONFIRMED | `:60` `public struct PanelMetadata: Codable, Sendable, Equatable`; the doc comment at `:59` says older versions still decode; the reader is at `:411` |
| A-17 | A-API | `CloudModelDescriptor` has exactly the 9 listed ids and a `maxReferenceImages` property | repo | CONFIRMED | `CloudModelDescriptor.swift:105,122,144,161,178,196,212,229,245`; `:42` `maxReferenceImages: Int`; `:260` `all` |
| A-18 | A-API | `VinetasVocabulary.ModelSummary` exists and lacks the cloud models, `isCloud` and `maxReferenceImages` | repo | CONFIRMED | `ModelSummary.swift:20`; `:220` `all = [klein4B, pixartSigmaXL]`; neither `isCloud` nor `maxReferenceImages` appears in the file |
| A-19 | A-API | `VinetasPromptDraft` is Codable and tolerates missing keys | repo | CONFIRMED | `VinetasPromptDraft.swift:29`; `init(from:)` at `:127` uses `decodeIfPresent` (`:130-151`) |
| A-20 | A-API | VinetasUI has a prompt composer view | repo | CONFIRMED | `VinetasPromptComposer.swift:34`, init at `:116`. `showsReferenceControls` and `statusSection` don't exist yet (new work) |
| A-21 | A-INVARIANT | VinetasVocabulary and VinetasUI are free of core, MLX and networking | repo | CONFIRMED | `Package.swift:170` gives VinetasVocabulary no dependencies; `:177` gives VinetasUI only `["VinetasVocabulary"]`. The only imports in either target are `Foundation`, `SwiftUI` and `VinetasVocabulary` |
| A-22 | A-API | `CharacterManager` loads a character by slug and exposes its reference images | repo | CONFIRMED | `CharacterManager.swift:19`; `:151` `loadCharacter(slug:)`; `:66` `referenceImageURLs(for:)` |
| A-23 | A-API | `--continue-on-error` exists | repo | CONFIRMED | `StoryboardCommand.swift:43` `continueOnError`; the catch path is at `:138` |
| A-24 | A-API | `VinetasClient.generate(_ PanelRequest, …)` exists and builds `PanelMetadata` | repo | CONFIRMED | `Vinetas.swift:39` class; `:269-273` `public func generate(_ request: PanelRequest, characters:stepProgress:)`; metadata is built at `:410` |
| A-25 | A-API | `vinetas generate` exists (to gain `--shot-json`) | repo | CONFIRMED | `VinetasCLICore.swift:45` `public struct Generate`; `--reference` at `:113-124`; `--character` near `:129`; the sidecar is written at `:363` |
| A-26 | A-FILE | `docs/CLI_REFERENCE.md` documents `vinetas storyboard` | repo | CONFIRMED | `docs/CLI_REFERENCE.md:293` |
| A-27 | A-API | Core maps descriptors to summaries via `ModelDescriptor.summary` at `ModelDescriptor.swift:71` | repo | CONFIRMED | `Engine/ModelDescriptor.swift:57` extension; `:71` `public var summary: ModelSummary`; `:72` `self as? CloudModelDescriptor` |
| A-28 | A-CONFIG | A test in `SwiftVinetasTests` can see both the core mapping and VinetasVocabulary | repo | CONFIRMED | Test target dependencies are at `Package.swift:230-235`; `VinetasVocabularyExports.swift:6` `@_exported import VinetasVocabulary`. Precedent: `ModelSummaryRoundTripTests.swift:14,19,24` |
| A-29 | A-BEHAVIOR | The `outputURL` comment records that the sandboxed CLI cannot write to the CWD | repo | CONFIRMED | `StoryboardCommand.swift:266-272` ("…it is unwritable") |
| A-30 | A-CONFIG | The CLI shipped in the app bundle is sandboxed | consuming app (read-only) | CONFIRMED | App repo `VinetasCLI/VinetasCLI.entitlements:5-6` has `com.apple.security.app-sandbox` set to true. SwiftVinetas' own `cli.entitlements` has no sandbox key |
| A-31 | A-API | A bare-object codec exists: `Shot.schemaJSON()`, `Shot(schemaJSON:)` and `Shot(schemaJSONData:)` | dep@v0.9.0 | CONFIRMED | `Shot+Schema.swift:233` `public func schemaJSON() -> GlosaJSONValue`; `:262` `schemaJSONData() -> Data`; `:276` `public init(schemaJSON: GlosaJSONValue, documentIndex: Int = 0) throws(GlosaSchemaError)`; `:311` `public init(schemaJSONData: Data, documentIndex: Int = 0) throws(GlosaSchemaError)`. The requirement's spelling leaves out the defaulted `documentIndex:`, which is a valid call. Unknown keys go at the top level, with no `documentIndex` (`:224-231`) |
| A-32 | A-DEP | The core `SwiftVinetas` target can carry a GlosaCore `Shot` on `PanelRequest` and compute `renderDigest` in `VinetasClient.generate` | repo | CONFIRMED (pass 4: now a stated deliverable, § 1 — core gains `.product(name: "GlosaCore", package: "glosa-av")`; glosa-av v0.9.0 `Package.swift` has `dependencies: []` and platforms macOS/iOS 26) — pass 3 text: REFUTED | The core target's dependencies (`Package.swift:183-195`) do not include GlosaCore. GlosaCore is linked only into VinetasCLICore (`:209`), and `import GlosaCore` appears only in the three `Storyboard/` files. `PanelRequest` (`PanelRequest.swift:10`) and the metadata builder (`Vinetas.swift:410`) are both in core |
| A-33 | A-BEHAVIOR | `ShotResolver` inherits `output` from defaults shots (`:79`), and GlosaCore's fold does not | repo + dep | CONFIRMED | `ShotResolver.swift:79` `output: override.output ?? base.output`. At v0.9.0, `Shot+Effective.swift:14-16,26` says `caption` and `output` are never inherited |
| A-34 | A-INVARIANT | Linking GlosaCore into core introduces no type-name collision | repo + dep@v0.9.0 | CONFIRMED | GlosaCore v0.9.0 public types (`git grep '^public (struct\|enum\|class\|protocol\|typealias\|actor)' v0.9.0 -- Sources`: Breath…Shot, 37 names) — none is declared anywhere in SwiftVinetas `Sources/` outside the storyboard files that already import GlosaCore |
| A-35 | A-BEHAVIOR | `ShotResolver` treats a whitespace-only prompt as defaults; GlosaCore only an empty one | repo + dep@v0.9.0 | CONFIRMED | `ShotResolver.swift:56-57` `trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`; v0.9.0 `Shot+Effective.swift:75` `shot.prompt.isEmpty`. Also `merge` (`:64-83`) drops `caption`, `ref`, `character`, `extraAttributes` |

### Blocking findings

#### (a) Upstream-dependency blocks

None. glosa-av v0.9.0 and SwiftVinetas v0.25.0 are both tagged, and every glosa-av name the requirement uses matches v0.9.0 exactly.

#### (b) Requirement errors

None as of pass 4 — A-32 was resolved by amending § 1 with option 1. Pass 3 record kept below for the audit trail.

#### A-32: REFUTED. The core target has no GlosaCore dependency

**Claim**: In § 4 (lines 61–79), the render record is written by "`VinetasClient.generate(_:…)` when the `PanelRequest` carries a `shot` (new optional field)". `PanelMetadata` (core) also gains `glosa: { notation, digest, shot }`, with the digest computed by `Shot.renderDigest`.
**Found**: `PanelRequest`, `PanelMetadata` and `VinetasClient` are all in the `SwiftVinetas` target. That target's dependency list (`Package.swift:183-195`) has no `GlosaCore`. Only `VinetasCLICore` links it (`:209`).
**Impact**: The requirement never says which way this goes. A sortie would have to decide the core library's dependency graph on its own, and that graph is what host apps link. Either they get GlosaCore in core, or core gets an opaque shot type that has to stay in sync with GlosaCore.
**Options**:
1. State that the `SwiftVinetas` core target gains `.product(name: "GlosaCore", package: "glosa-av")`. Then `PanelRequest.shot: Shot?` holds the real type and core computes `renderDigest` itself. GlosaCore has no package dependencies (glosa-av `Package.swift:14,19`), imports only Foundation and CryptoKit, and targets the same platforms (macOS/iOS 26). VinetasVocabulary and VinetasUI stay GlosaCore-free. *(recommended: it keeps one encoder and one digest)*
2. State that `PanelRequest` carries a caller-built record (`notation`, `digest`, and the shot as `schemaJSONData()` bytes), and that core stores it without interpreting it. Core stays GlosaCore-free, but every host has to compute the digest correctly.

## Local Dependency Map

`Package.resolved` is gitignored (`.gitignore:15`) and has **no pins** for any
intrusive-memory dependency. Every `../<name>` sibling exists, so this machine builds all six
from local paths. CI (`CI=true`) resolves the remote `upToNextMajor` ranges with no lock entry,
which leaves them effectively `UNPINNED` there. With the floor still at `0.8.1`, CI would
probably pick up 0.9.0 anyway, since it is the newest tag below 1.0. That is not a guarantee,
which is why raising the floor (A-01) is in scope.

| Dependency | Declared | Resolved (this machine) | Local checkout | Local HEAD | Status |
|------------|----------|-------------------------|----------------|-----------|--------|
| intrusive-memory/glosa-av | `from: 0.8.1` | `../glosa-av` (path) | `~/Projects/package-collection/pkg/glosa-av` (`development`, clean) | `7459eb8`, 1 commit ahead of `v0.9.0` | SIBLING_ACTIVE, LOCAL_AHEAD (source-equivalent; see below) |
| intrusive-memory/SwiftCompartido | `from: 7.3.1` | path | `…/pkg/SwiftCompartido` | `af5a734`, 1 ahead of `v7.3.1` | SIBLING_ACTIVE |
| intrusive-memory/flux-2-swift-mlx | `from: 3.4.3` | path | `…/pkg/flux-2-swift-mlx` | `9a36b26`, 1 ahead of `v3.4.3` | SIBLING_ACTIVE |
| intrusive-memory/SwiftAcervo | `from: 0.25.0` | path | `…/pkg/SwiftAcervo` | `13e2879`, 4 ahead of `v0.25.0`; 1 untracked non-source file | SIBLING_ACTIVE |
| intrusive-memory/SwiftTuberia | `from: 0.9.0` | path | `…/pkg/SwiftTuberia` | `d74977a`, 1 ahead of `v0.9.0`; 2 untracked non-source files | SIBLING_ACTIVE |
| intrusive-memory/pixart-swift-mlx | `from: 0.8.2` | path | `…/pkg/pixart-swift-mlx` | `3ce2541`, 1 ahead of `v0.8.2` | SIBLING_ACTIVE |
| marcprux/universal | `from: 5.3.0` | `5.3.0` (`7919463ce636`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | `1.8.2` (`6a52f3251125`) | — | — | NO_LOCAL_CHECKOUT |
| DePasqualeOrg/swift-tokenizers | `upToNextMinor 0.7.1` | `0.7.1` (`e4e01cb59fb7`) | — | — | NO_LOCAL_CHECKOUT |
| apple/swift-certificates / swift-crypto / swift-asn1 | `1.0.0` / `3.0.0` / `1.0.0` | `1.19.4` / `3.15.1` / `1.7.1` | — | — | NO_LOCAL_CHECKOUT |

### Drift and ambiguity notes

- **Local glosa-av `development` matches `v0.9.0` for everything this mission uses.**
  `git diff v0.9.0 HEAD -- Sources` changes a single line: `GlosaVersion.swift:3`
  `version = "0.9.0"` becomes `"0.9.0-dev"`. `GlosaVersion.notation`, `Shot.swift`,
  `Shot+Effective.swift`, `Shot+Digest.swift`, `Shot+Schema.swift`, `GlosaJSON.swift`, the
  parser files and `schemas/shot.schema.json` are byte-identical to the tag. Don't record or
  assert `GlosaVersion.version` in sidecars or tests, because it differs between local and CI.
  Use `GlosaVersion.notation`.
- `.build/checkouts/glosa-av` is at `92e81cb` (`v0.8.1`). It is a stale copy left over from a
  remote resolution, not what this machine compiles.
- glosa-av and SwiftVinetas each have exactly one authoritative checkout, so nothing is ambiguous.
- The sibling checkouts that are ahead of their tags differ only in Package.swift and non-source
  files. No verdict depends on them.

## Notable surprises (non-blocking; carry into breakdown)

- **`GlosaJSONValue`'s `Codable` is not the schema form.** `GlosaJSON.swift:9-14,49-58` encodes
  objects as `{"object": [{"key": …, "value": …}]}`. If `PanelMetadata` gets a
  `shot: GlosaJSONValue` field with synthesized `Codable`, the sidecar will contain that wrapper,
  not the bare schema object § 4 requires. The plan needs an explicit bridge, either a custom
  `encode`/`init(from:)` or a JSON value type that encodes objects as keyed containers. It also
  needs a test that the sidecar's `glosa.shot` decodes through `Shot(schemaJSONData:)`.
- **The fold change goes beyond `output`.** `ShotResolver.merge` (`:64-83`) rebuilds `Shot`
  without `caption`, `ref`, `character` or `extraAttributes`. Today every panel's caption,
  ref and character are silently dropped. `effective(given:)` keeps the shot's own
  caption and output and folds ref, character and extras. Also, `ShotResolver.isDefaultsShot`
  treats a **whitespace-only** prompt as a defaults shot (`ShotResolver.swift:56-57`), while
  `GlosaScore.effectiveShots` tests `prompt.isEmpty` (v0.9.0 `Shot+Effective.swift:75`)
  The parser doesn't trim prompts, so a `prompt=" "` shot becomes a blank-prompt panel.
  All three changes belong in the CHANGELOG and in the 2.0/1.0 twin-fixture test.
- **The `--shot-json` decode is typed-throws.** Both initializers throw `GlosaSchemaError`
  (`.invalidJSON` comes with line and column), so the CLI should report `error.message`.
- **Sandbox writability can only be tested in the app.** The unsandboxed dev CLI can't reproduce
  the denial (A-30), so plan the project-root check as an injectable writability probe and
  test it with a stub.
- **The sync test has a template.** `ModelSummaryRoundTripTests.swift` already compares
  descriptors with summaries. `summary` (`ModelDescriptor.swift:71`) has to gain `isCloud`
  and `maxReferenceImages`.
- **Deleting `ShotResolver` means editing three test files:** `ShotResolverTests.swift`,
  `ScreenplayShotsTests.swift:67,90`, and a comment at `StoryboardPlanTests.swift:10`.

## Unverifiable

None.

## Handoff to breakdown

- `CONFIRMED` facts can be used as sortie entry criteria without re-checking.
- A-32 is resolved (core links GlosaCore). Breakdown may proceed.
- Sortie agents verifying glosa-av should read `git show v0.9.0:<path>`. The local checkout
  is equivalent except for `GlosaVersion.version`.
- Local paths: glosa-av `~/Projects/package-collection/pkg/glosa-av`; SwiftVinetas
  `~/Projects/package-collection/pkg/SwiftVinetas`.

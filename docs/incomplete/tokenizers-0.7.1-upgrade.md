---
title: swift-tokenizers 0.5.0 → 0.7.1 Upgrade
state: incomplete
created: 2026-06-18
updated: 2026-06-18
owner: tom
---

# swift-tokenizers 0.5.0 → 0.7.1 Upgrade

## Goal

Move the `intrusive-memory` diffusion stack off the frozen `swift-tokenizers`
0.5.x line and onto **0.7.1** to pick up the upstream tokenizer-speed work.
The freeze was a build-system workaround, not a feature decision, so the
upgrade is unblocked the moment we confirm the Xcode artifactbundle fix holds
in our toolchain.

## Why we froze at 0.5.0

The pin is a **build-system blocker, not an API choice.** swift-tokenizers
`0.6.0` swapped the Rust backend from an XCFramework to a **UniFFI
artifactbundle**, and its generated module map did not expose
`RustBuffer` / `RustCallStatus` / `ForeignBytes` to the `TokenizersFFI`
target when consumed via `xcodebuild` (it built fine under `swift build`,
which this stack never uses — Metal shaders required by MLX won't compile
under SwiftPM directly).

All four repos in our graph carry `.upToNextMinor(from: "0.5.0")` to dodge
that. `pixart-swift-mlx` and `SwiftVinetas` carry it as a **constraint-only**
pin (they never `import Tokenizers`); they only need the floor bumped so
transitive resolution stays aligned.

## The unblock

Upstream `0.6.3` ships *"Fixes for Xcode build with artifact bundle"* — the
exact failure mode. `0.7.1` carries that fix forward.

- `0.7.1` requires **Swift 6.2, macOS 14+ / iOS 17+**. Every sibling is
  macOS 26 / iOS 26 on Swift 6.2, so platform floors are non-issues.
- The Rust backend is now a **remote, checksummed artifactbundle download**
  (`TokenizersRust-0.7.1.artifactbundle.zip`). That means network access at
  *resolution* time — a CI consideration. Upstream provides a
  `TOKENIZERS_RUST_LOCAL_ARTIFACTBUNDLE_PATH` env override for offline /
  pinned-mirror workflows.

## Dependency graph & who touches the API

| Repo | Role | Tokenizer API usage |
|---|---|---|
| **flux-2-swift-mlx** | direct consumer | **Heavy** — ~25 call sites in `FluxTextEncoders` |
| **SwiftTuberia** | direct consumer | **Light** — 2 call sites in `TuberiaCatalog/T5XXLEncoder` |
| **pixart-swift-mlx** | constraint-only pin | none (no `import Tokenizers`) |
| **SwiftVinetas** (this repo) | constraint-only pin | none |
| SwiftAcervo | not involved | — |

Code work lives in **flux** and **Tuberia**. pixart and SwiftVinetas are
pin-only bumps.

## The breaking API change (introduced in 0.6.0)

The `Tokenizer` protocol became **typed-throwing** (`throws(TokenizerError)`)
and some convenience overloads were re-shaped. In 0.7.1:

- `encode(text:addSpecialTokens:)` — labeled `text:`, **throws**
- `decode(tokenIds:skipSpecialTokens:)` and `decode(tokenIds:)` — labeled
  `tokenIds:`, **throws**
- `bosTokenId` / `eosTokenId` — still present, non-throwing `Int?` ✅
- `AutoTokenizer.from(directory:)` — unchanged (`async throws`) ✅

This bites two ways in our consumers:

1. **Add `try`** to every `encode` / `decode` call.
2. **Relabel first arg** — our code currently calls
   `tokenizer.encode("…", addSpecialTokens:)` and
   `tokenizer.decode(tokens, skipSpecialTokens:)` with *unlabeled* first args
   (0.5.0 signatures). 0.7.1 wants `text:` / `tokenIds:`.

## Per-repo work breakdown

### 1. flux-2-swift-mlx — the real work

Call sites needing `try` + relabel:

- `Sources/FluxTextEncoders/FluxTextEncoders.swift`: 462, 466, 537, 827, 835, 932, 940
- `Sources/FluxTextEncoders/Embeddings/EmbeddingExtractor.swift`: 119
- `Sources/FluxTextEncoders/Embeddings/KleinEmbeddingExtractor.swift`: 68, 179
- `Sources/FluxTextEncoders/Generation/Qwen3Generator.swift`: 59, 113, 143, 151, 197, 240, 269, 277
- `Sources/FluxTextEncoders/Generation/MistralGenerator.swift`: 166, 198, 210, 298, 330, 342
- `Sources/FluxTextEncoders/Tokenizer/TekkenTokenizer.swift`: 275, 402, 480

**Design decision:** `TekkenTokenizer` wraps swift-tokenizers behind its own
*non-throwing* methods (`decode(tokenIds:) -> String`, the `encode` path).
Each wrapper must either become `throws` (propagating to callers) or absorb
the error internally (`try?` + fallback). Prefer propagation where the caller
already has an error path; use `try?` only where a fallback already exists.

Plus: bump flux's own tokenizers pin to `.upToNextMinor(from: "0.7.1")`.

### 2. SwiftTuberia — small

- `Sources/TuberiaCatalog/Encoders/T5XXLEncoder.swift:154` — `tok.encode(text:)`
  needs `try`; enclosing `tokenizeWithRealTokenizer(...)` is currently
  non-throwing, so make it `throws` (and propagate up through `tokenize`/
  `encode`) **or** catch locally and fall back to placeholder tokenization
  (a fallback already exists for the nil-tokenizer case — reuse it).
- `AutoTokenizer.from(directory:)` at line 65 is already inside `do/catch`. ✅
- Bump pin.

### 3. pixart-swift-mlx — pin-only

- Bump `.upToNextMinor(from: "0.5.0")` → `0.7.1`, update the stale comment.

### 4. SwiftVinetas (this repo) — pin-only + integration

- Bump tokenizers pin → `0.7.1`, update comment.
- Bump the four sibling floors once each is released.
- Full `make test` (unit + GPU + integration) as the integration gate.

## Release ordering (sibling pattern)

Bottom-up; each tagged before the next consumes it. flux and Tuberia are
independent and can proceed in parallel.

1. **flux-2-swift-mlx** — migrate, build under `xcodebuild`, tag a release.
2. **SwiftTuberia** — migrate, tag.
3. **pixart-swift-mlx** — bump pin to match, tag.
4. **SwiftVinetas** — bump all sibling floors + tokenizers pin, verify
   `make test`.

Each release step uses the `/toggle-sibling-libraries` flip
(sibling-dev → remote-pin) at tag time per the standard release convention.

## Primary risk — validate before committing the chain

The 0.6.3 fix was flagged upstream as *possibly working around an Xcode bug*.
Before touching four repos, run a **build-viability spike**: bump only flux to
0.7.1 and run `make build` (xcodebuild, `Flux2Swift-Package` scheme).

Interpretation of the spike:

- **Fails inside `TokenizersFFI` / `RustBuffer` / module map** → the blocker
  is NOT fixed for our toolchain. Stop; the upgrade stays frozen regardless of
  speed wins.
- **Gets past `TokenizersFFI`, fails only in `FluxTextEncoders`** on
  `try`/label errors → the FFI blocker IS resolved. Proceed with the
  mechanical migration above.

Secondary risk: the remote artifactbundle download at resolution time. Confirm
CI can reach the GitHub release asset, or wire up
`TOKENIZERS_RUST_LOCAL_ARTIFACTBUNDLE_PATH` against a mirror.

## Effort estimate

~30 mechanical call-site edits across 2 repos, 4 coordinated releases, gated
on one build-viability spike. The spike is the go/no-go decision point;
everything downstream is low-risk once it passes.

## Status / log

- 2026-06-18 — Doc created. Flux build-viability spike kicked off on branch
  `spike/tokenizers-0.7.1` in `../flux-2-swift-mlx`.
- 2026-06-18 — **SPIKE RESULT: GO.** The FFI/module-map blocker is resolved
  in our toolchain.
  - Bumping flux's pin alone failed at *resolution* (not build): sibling
    SwiftTuberia still pins `0.5.x`, so root-wants-`0.7.1` conflicts. This is
    the expected multi-repo coordination wall, not an FFI failure — it
    confirms the release ordering above is mandatory (every consumer must
    move together).
  - Isolated scratch package (`/tmp/tok-spike`, swift-tokenizers `0.7.1`
    only, calling `encode`/`decode`) built **`BUILD SUCCEEDED`** under
    xcodebuild on macOS arm64. `TokenizersFFI` compiled, emitted its
    `.modulemap`, and linked the Rust backend. **Zero**
    `RustBuffer`/`RustCallStatus`/`ForeignBytes`/module-map errors — the
    exact 0.6.0 failure symbols. The remote artifactbundle downloaded and
    resolved cleanly.
  - Decision: proceed with the mechanical migration. Recommended kickoff —
    bump SwiftTuberia's pin + migrate its 2 call sites first (smallest), then
    flux (~25 sites), then pixart + SwiftVinetas pin bumps.

### Cleanup / loose ends
- `../flux-2-swift-mlx` is on branch `spike/tokenizers-0.7.1` with the pin
  bumped (no code migrated yet). Keep as the flux migration branch, or revert
  the pin if pausing.
- Scratch package lives at `/tmp/tok-spike` (disposable).

---
type: project
title: SwiftVinetas 0.25.0 — release cloud reference images and prompt bundles
updated: 2026-10-20
state: draft
kind: release
---

# SwiftVinetas 0.25.0 — release what is on `development`

Ship the work merged in PR #80 as a published release. No new features: this mission
verifies the branch is releasable and runs `/ship-swift-library minor`.

## What is being released (on `development`, `e06c2a0`)

- Cloud reference images: OpenAI (`/v1/images/edits`, multipart, up to 10) and Gemini
  (Interactions API image blocks, up to 10, or 6 for Gemini 3 Pro);
  `CloudModelDescriptor.maxReferenceImages`; references re-encoded to ≤ 1536 px JPEG.
- `PromptBundle`: style, frame size, aspect label and orientation, character and
  reference instructions rendered into the vendor prompt; recorded in `PanelMetadata`.
- `PanelRequest.character`, `VinetasClient.prepare(_:characters:)`, `PreparedPanel`.
- CLI: `vinetas generate --character`, `--dry-run` (JSON report),
  per-model reference help; `list --json` reports `maxReferenceImages`; the negative
  prompt note for vendors without a native field.
- `docs/CLI_REFERENCE.md` updated for all of the above.

## Release preconditions (to be verified at recon)

1. `development` is ahead of `main` by exactly the PR #80 commits plus the dev marker
   (`95b5e87`, `d7246ba`, `ae0cd66`, `e06c2a0`).
2. The version strings (`Vinetas.swift:48`, `:1277`) read `0.24.0-dev` although 0.24.0
   is already released — the dev marker should have been the next version. The release
   sets them to `0.25.0`, and updates the stale versions in `AGENTS.md` and
   `README.md`.
3. Every `sibling(...)` dependency in `Package.swift` has a published release at or above
   its `from:` floor, so `/toggle-sibling-libraries` can flip to remote-only; no
   `siblingBranch(...)` pin is in use.
4. `make test-unit`, `make build`, `make build-ios`, `make lint-check` pass on
   `development`.
5. GitHub branch protection on `main` requires **`Unit Tests (macOS)` and `PixArt
   Integration (macOS)`**; the ship flow's PR into `main` must be green on both.
6. **`Unit Tests (iOS)` is triaged before shipping.** It is not a required check, but it
   failed on PR #80's head (`ae0cd66`) after passing on the 0.24.0 release PR. Either
   fix it in a small PR to `development` first, or record why it is unrelated.
7. **PR #80 adds no private app or podcast names** (verified by recon). The repository
   already contains such names and fixtures from earlier releases; removing them is a
   separate mission (see below), not part of this release.

## Steps

`/ship-swift-library minor` → version `0.25.0`, PR `development` → `main`, merge on green,
tag `v0.25.0`, GitHub release with notes from the list above, then `/branch-hygiene`
(development marked `0.25.1-dev` or `0.26.0-dev`, sibling pattern restored). Then
`/update-package-library update --only intrusive-memory/SwiftVinetas` in
`package-collection`.

## Non-goals

Any code change beyond version strings and the sibling flip.

## Known issue carried forward (separate mission)

Recon found the public repository already contains private app names (≈200 lines across
≈45 tracked files) and test fixtures copied from a private screenplay project. They have
been public since earlier tags. Removing them — and deciding whether history needs
rewriting — is its own mission; this release neither adds to nor fixes it.

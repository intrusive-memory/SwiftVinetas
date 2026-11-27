---
type: execution-plan
state: ready
feature_name: OPERATION ROLL CALL
starting_point_commit: 8893496005989fcfdc1108595482a8ccbb7016f4
mission_branch: mission/roll-call/01
iteration: 1
requirements_file: REQUIREMENTS-CLOUD-MODEL-DISCOVERY.md
recon_report: RECON_REPORT.md
---

# EXECUTION_PLAN.md — Cloud model discovery (Vinetas 1.2.0)

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Scope

The 1.2.0 scope in `REQUIREMENTS-CLOUD-MODEL-DISCOVERY.md` § 8.1. Everything listed
there under "In 1.2.1" is out of this mission: R-5a's warning, R-12, R-14 to R-17,
R-20, V-4, V-3's Refresh button, Escribir (§7.2) and `vinetas-skills` (§7.3).

**Rules for every sortie:**

- Never run `swift build` or `swift test`. SwiftVinetas: use `make` targets
  (`make build`, `make test-unit`, `make lint-check`). Vinetas app: use the Xcode
  MCP (`BuildProject`, `RunSomeTests`), or `xcodebuild` where it can't reach.
- Tests that reach a vendor use `StubURLProtocol` (`Tests/SwiftVinetasTests/CloudEngineTests.swift:17`),
  never the network. No test reads a real key.
- Never print, log or write an API key. Read keys only through the existing key stores.
- Commit on the sortie's branch; never push to `development` or `main` directly.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU-A SwiftVinetas | `~/Projects/package-collection/pkg/SwiftVinetas` | 9 (S1–S6, S10–S12) | 0 | none |
| WU-C Privacy page | `~/Projects/websites/vinetas.github.io` | 1 (S9) | 0 | none |
| WU-B Vinetas app | `~/Projects/apps/Vinetas` | 4 (S7, S8, S13, S14) | 1 | WU-A released (our next minor release of SwiftVinetas); S14 has none |

Human gates between layers (not sorties):

- **G-1, after S1:** merge the model-table PR into `development`, then release it as our next patch release of SwiftVinetas (`/ship-swift-library patch`; a human merges into `main`).
- **G-2a, after S12 (added 2026-11-27):** run the live acceptance suite
  (`make test-cloud-models`, requirements § 8.2 B; paid, about $1, your keys) and
  commit `docs/cloud-model-acceptance.md`. If a check fails, fix the descriptor on
  the mission branch before G-2.
- **G-2, after S6 and S10–S12 and G-2a:** merge the second discovery PR into `development`, then release our next minor release of SwiftVinetas (`/ship-swift-library minor`). **Held** until S10–S12 land, so 0.28.0 ships smart expiry and the rejected-key rule.
- **G-3, after S8 and S13 (S14 merged):** the Vinetas development → main PR (TestFlight), then requirements § 8 step 3: the real-key smoke test including a rejected key and AC-9, privacy PR vinetas.github.io#21 merged and live, the App Store description in both metadata files. Then tag `1.2.0-rc7`.

### Tracking

Progress is tracked in GitHub, not in this file: **intrusive-memory/Vinetas#186** (tracking issue), with one sub-issue per open sortie and gate across all three repos, linked by blocked-by dependencies. Gates: G-2a SwiftVinetas#108, G-2 SwiftVinetas#109, G-3 Vinetas#185, privacy page vinetas.github.io#22. A sortie agent works only in its own repo and closes its issue through its PR.

### Amendment, 2026-11-27

Requirements amended after WU-A finished (R-7a smart expiry, R-8a rejected key, V-4a
greyed row, R-22 App Store text, § 8.2 acceptance tests). New sorties S10–S14. WU-A is
reopened on the same mission branch: merge `origin/development` first (PR #104 is
merged), then S10 → S11 → S12, and S12 opens the second PR.

---

## WU-A — SwiftVinetas

All WU-A sorties commit on the mission branch `mission/roll-call/01` (off `development`; it also carries these mission docs).
S1 ends with a PR from it into `development` (G-1). After G-1's release, merge `origin/development` into the mission branch, then S2–S6 continue on it; S6 opens the second PR.

### Sortie 1: Refresh the built-in cloud model table (D-6)

**Priority**: 1 of 9 — blocks every WU-A sortie through G-1; vendor-facing. Builds: yes (runs `make`).

**Entry criteria**:
- [ ] First sortie — no prerequisites. Recon A-01 to A-03 confirm `CloudModelDescriptor` (`Sources/SwiftVinetas/Cloud/CloudModelDescriptor.swift`), `ModelSummary.cloud` (`Sources/VinetasVocabulary/ModelSummary.swift:451`) and the parity test (`Tests/SwiftVinetasTests/ModelSummaryRoundTripTests.swift:24`, asserts `count == 9`).
- [x] OQ-1 is answered.

**Tasks**:
1. From the vendors' current API docs, record each new model's capabilities: sizes or aspect ratios, steps, guidance, seed, negative prompt, reference-image limit, pricing hint. Models: `gpt-image-2.6-flare`, `gpt-image-2.6-sunburst`, `gemini-3.1-flash-lite-image`. Put the sources in a comment above each descriptor.
2. Add a `CloudModelDescriptor` constant for each, following the existing 2.5 and Gemini constants, and add it to `CloudProvider.models`: `gpt-image-2.6-flare` and `gpt-image-2.6-sunburst` before their 2.5 counterparts, `gemini-3.1-flash-lite-image` right after `gemini-3.1-flash-image`. Don't change the default model (OQ-1).
3. Add the matching `ModelSummary.cloud` entries and update the parity test's count.
4. Update any other test or doc that hard-codes the cloud model count or list (grep `count == 9`, `gpt-image-2.5`, `gemini-3.1-flash-image` in `Tests/` and `docs/`).
5. Add a CHANGELOG entry under the unreleased heading.
6. Push `mission/roll-call/01` and open a ready PR into `development` with `/create-pull-request`, then enable auto-merge (`gh pr merge <n> --auto --merge`). This is G-1's PR.

**Exit criteria**:
- [ ] `make build` exits 0.
- [ ] `make test-unit` exits 0, including `testVocabularyCloudSummariesEqualCoreMapping` with the new count.
- [ ] `make lint-check` exits 0.
- [ ] `grep -c 'vendorModelID: "gpt-image-2.6-flare"\|vendorModelID: "gpt-image-2.6-sunburst"\|vendorModelID: "gemini-3.1-flash-lite-image"' Sources/SwiftVinetas/Cloud/CloudModelDescriptor.swift` prints 3.
- [ ] [judgment] Each new descriptor's capability flags are backed by a cited vendor doc URL in its comment; none are copied from a sibling model without a source.
- [ ] `gh pr view --json baseRefName,isDraft,autoMergeRequest` shows `development`, `false`, and a non-null auto-merge request.

### Sortie 2: Classify vendor errors (R-10, R-10a, R-11, key rejection)

**Priority**: 2 — defines the public error cases S3–S8 depend on. Builds: yes.

**Entry criteria**:
- [ ] G-1 done: S1 merged and released; `origin/development` merged into `mission/roll-call/01`.
- [x] OQ-2 is answered.
- [ ] Recon A-07, A-08, A-16 hold: `CloudHTTP.perform` (`CloudHTTP.swift:63–88`), the 9 `CloudEngineError` cases, and the two exhaustive switches (`CloudEngineError.swift:69`, `Sources/VinetasCLICore/CLIModel.swift:225`).

**Tasks**:
1. Add `CloudEngineError.modelUnavailable(provider:modelID:reason:)` and `CloudEngineError.keyRejected(provider:reason:)` with a public `KeyRejectionReason` enum (`expired`, `invalid`, `notPermitted`) (OQ-2), both with plain-language descriptions that name the vendor's console (R-11).
2. Add an internal per-vendor classifier that `CloudHTTP.perform` calls on a non-2xx response before falling back to `httpStatus`:
   - OpenAI: `400` with `error.param == "model"`, or `404 model_not_found` → `modelUnavailable`; a `403` about organisation verification → `modelUnavailable` with that reason; `401` → key rejected, keeping `expired_secret_key` apart from `invalid_api_key`.
   - Google: `404` with `error.code == "not_found"` (flat body on `/interactions`) or `status == "NOT_FOUND"` → `modelUnavailable`; `400` with reason `API_KEY_INVALID` → key rejected.
   - BFL: `404` → `modelUnavailable`; `401`/`403` → key rejected.
   - Stability: `404` → `modelUnavailable`; `401` → key rejected; `403` unchanged (moderation).
3. Update both exhaustive switches. CLI exit codes: `modelUnavailable` → 69; `keyRejected` → 78 (`EX_CONFIG`, the same as a missing key).
4. Tests with `StubURLProtocol`, one per row above, using the response bodies recorded in requirements § 10.1. Include the negative case: OpenAI `400` with `param == "size"` stays `httpStatus`.

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] `grep -n 'case modelUnavailable' Sources/SwiftVinetas/Cloud/CloudEngineError.swift` finds one line.
- [ ] The new tests are in `Tests/SwiftVinetasTests/` and there are at least 9 of them (`grep -c '@Test' <file>` on the new suite).
- [ ] `grep -rn 'API_KEY_INVALID' Sources/SwiftVinetas/Cloud` finds the Google classifier.
- [ ] `grep -n 'case keyRejected' Sources/SwiftVinetas/Cloud/CloudEngineError.swift` finds one line, and `grep -n 'keyRejected' Sources/VinetasCLICore/CLIModel.swift` shows it mapped to 78.

### Sortie 3: Vendor listing calls (R-3, R-6, R-9, R-9a)

**Priority**: 3 — external APIs; feeds S4–S5. Builds: yes.

**Entry criteria**:
- [ ] Sortie 2 exit criteria met.
- [ ] Recon A-06 and A-09 hold: `CloudProviderClient` is internal (`CloudHTTP.swift:18–26`); adapters take `apiKey` and `URLSession` per call.

**Tasks**:
1. Add an internal `CloudVendorListing` value: vendor model IDs plus optional shutdown dates by vendor ID.
2. Add `listAvailableModels(apiKey:session:) async throws -> CloudVendorListing` to `CloudProviderClient`:
   - OpenAI: one `GET https://api.openai.com/v1/models`; parse `data[].id` and `shutdown_date`.
   - Google: `GET /v1beta/models?pageSize=1000`, following `nextPageToken`; strip the `models/` prefix.
   - BFL: `GET https://api.bfl.ai/v1/credits` (`x-key`); success means the key works, with no IDs (R-9).
   - Stability: `GET https://api.stability.ai/v1/user/balance` (Bearer); same.
   All go through `CloudHTTP.perform`, so Sortie 2's classifier applies.
3. Add the vendor-ID match on `CloudModelDescriptor` (R-3): `vendorModelID` plus an optional alias list, matched exactly. Add the OpenAI dated snapshot IDs seen in recon (`gpt-image-2.5-flare-2026-09-08`, `gpt-image-2.5-sunburst-2026-09-08`) as aliases.
4. Stub tests per vendor: a two-page Google listing, an OpenAI listing with a past and a future `shutdown_date`, the BFL and Stability balance success, and a rejected key on each.

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] `grep -c 'func listAvailableModels' Sources/SwiftVinetas/Cloud/*.swift` totals 5 (protocol plus 4 adapters).
- [ ] The Google paging test asserts that two requests were made and the second carries `pageToken`.

### Sortie 4: Snapshot type and persistence (R-5, R-7 persistence, D-4)

**Priority**: 4 — public types reused by S5–S8. Builds: yes.

**Entry criteria**:
- [ ] Sortie 3 exit criteria met.
- [x] OQ-3 is answered.
- [ ] Recon A-13 holds: SwiftVinetas has no App Group helper; the App Group is reached through SwiftAcervo (`Acervo.sharedModelsDirectory`).

**Tasks**:
1. Add public `CloudAvailabilitySnapshot` (`Codable`, `Sendable`, `Equatable`) with the R-5 fields: `provider`, `status` (`.available`, `.noKey`, `.keyRejected(reason:)`, `.unreachable`, `.unsupported`), `modelIDs` (our IDs), `checkedAt`, `keyFingerprint`, `shutdownDates` (our IDs).
2. Add the key fingerprint: a salted SHA-256 prefix (CryptoKit), with a salt generated once and stored beside the snapshots. The key itself is never stored.
3. Add an internal `CloudAvailabilityStore` that reads and writes one JSON file per provider in `<App Group container>/vinetas-cloud-availability/` (App Group ID from SwiftAcervo, as `resolveIODirectory()` does at `VinetasCLICore.swift:976`); when the container is unavailable, `<Caches>/io.intrusive-memory.Vinetas/cloud-availability/` (OQ-3). The directory is injectable; tests always pass a temp directory.
4. Add the derived rule from R-5a: a model whose shutdown date is today or earlier is unavailable, even if listed.
5. Tests: encode/decode round trip; fingerprint stability and change; the store's read/write in a temp directory; the App Group → Caches fallback (an injected container lookup that returns nil); the past-shutdown rule with an injected clock.

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] `grep -rn 'apiKey' Sources/SwiftVinetas/Cloud/CloudAvailability*.swift` shows the key used only as fingerprint input, never in a stored property.
- [ ] [judgment] No code path writes the key or any part of it except the salted hash prefix.

### Sortie 5: The availability service (R-4, R-7, R-8, R-19, R-21)

**Priority**: 5 — concurrency (single-flight) is the riskiest code. Builds: yes. Model: opus.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met.
- [ ] Recon A-05 and A-10 hold: `VinetasClient` is a `final class … Sendable` with `static let shared` (`Vinetas.swift:39`); keys resolve through `ChainedAPIKeyStore.default`.

**Tasks**:
1. Add public actor `CloudModelAvailability` with `snapshot(for:)`, `refresh(_:force:)`, `availableModels()`, `isAvailable(_ modelID:)` and `nonisolated var updates: AsyncStream<CloudAvailabilitySnapshot>`.
2. Cache rules: fresh for 24 hours; stale at once when the key fingerprint changes or the key is added or removed. No key means `.noKey` and no network call.
3. On failure keep the last good snapshot with status `.unreachable` and its original `checkedAt` (R-8). With no earlier snapshot, every known model counts as available, marked not checked (D-2).
4. Single-flight: concurrent `refresh` calls for one provider share one task (R-21).
5. Expose it as `VinetasClient.cloudAvailability`, built with the same key store and session as the cloud engines.
6. Tests: fresh cache makes no request; stale cache does; key change invalidates; failure keeps the last snapshot; two concurrent refreshes make one request; `updates` yields after a refresh.

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] The single-flight test asserts exactly one stubbed request for two concurrent `refresh` calls.
- [ ] `grep -n 'cloudAvailability' Sources/SwiftVinetas/Vinetas.swift` finds the public property.

### Sortie 6: Generation-time invalidation and release prep (R-10, R-18, R-22)

**Priority**: 6 — closes WU-A; gate G-2 follows. Builds: yes.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met.

**Tasks**:
1. When `CloudImageEngine.generate` throws `modelUnavailable`, tell `CloudModelAvailability` to drop that model from the provider's snapshot and publish on `updates`. When it throws the key-rejected case, mark the snapshot `.keyRejected`.
2. Test: a stubbed generation returning OpenAI's `400 param: "model"` removes the model from `availableModels()` and yields one update.
3. Test (R-18): across every listing and generation stub, the key appears only in the auth header of a request to its own vendor's host.
4. Document the API in `AGENTS.md` (cloud section) and the CHANGELOG.
5. Open a ready PR from `mission/roll-call/01` into `development` with `/create-pull-request`, and enable auto-merge.

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] `gh pr view --json baseRefName,isDraft` shows `development` and `false`.
- [ ] `gh pr checks` shows no failing check (passing or pending only).
- [ ] `gh pr view --json autoMergeRequest` is non-null.

### Sortie 10: Smart cache expiry (R-7a)

**Issue**: intrusive-memory/SwiftVinetas#105

**Priority**: 10 — first of the amendment; changes the snapshot file, which S11 and WU-B read. Builds: yes. Model: opus (file format change shared across processes and versions).

**Entry criteria**:
- [ ] S6 merged (PR #104, `764b8dc`); `origin/development` merged into `mission/roll-call/01`.
- [ ] `CloudAvailabilityStore.schemaVersion == 1` and `CloudAvailabilitySnapshot.mapping(of:provider:)` maps vendor IDs at write time (`CloudModelAvailability.swift:299`).

**Tasks**:
1. Add `vendorModelIDs: Set<String>` (the raw IDs the vendor returned) and `catalogDigest: String` to `CloudAvailabilitySnapshot`, encoded with `decodeIfPresent` like `keyFingerprint`.
2. Add a `catalogDigest(for: CloudProvider)` that hashes the provider's known models: each `id`, `vendorModelID` and sorted `vendorAliases`, the models sorted by `id`, SHA-256, first 16 hex characters. Computed from `CloudProvider.models`, never hand-maintained.
3. Bump `CloudAvailabilityStore.schemaVersion` to 2. A file with another version is ignored and **not deleted** (an older process may still read it).
4. On read, when the snapshot's `catalogDigest` differs from the reader's, re-map `vendorModelIDs` through the reader's own `mapping(of:provider:)` for `modelIDs` and `shutdownDates`, and mark the snapshot stale so the next `refresh` makes a network call.
5. Add `CloudAvailabilityStore.minimumCheckedAt: Date` (start it at `.distantPast`); a snapshot with `checkedAt` before it is stale.
6. Tests (temp directory, `StubURLProtocol`):
   - a different digest makes the snapshot stale
   - a v1 file is ignored and left on disk
   - re-mapping from `vendorModelIDs` exposes a newly added known model with no request
   - re-mapping drops a model the reader doesn't know
   - `minimumCheckedAt` expires an older snapshot
   - adding an alias to a descriptor changes the digest

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] `grep -n 'schemaVersion = 2' Sources/SwiftVinetas/Cloud/CloudAvailabilityStore.swift` finds the line.
- [ ] `grep -c 'catalogDigest\|vendorModelIDs' Sources/SwiftVinetas/Cloud/CloudAvailabilitySnapshot.swift` is at least 4.
- [ ] [judgment] Nothing in the digest is hand-maintained: adding a descriptor to `CloudProvider.models` changes it with no other edit.

### Sortie 11: A rejected key offers no models (R-8a)

**Issue**: intrusive-memory/SwiftVinetas#106

**Priority**: 11 — WU-B's greyed row (S13) reads this. Builds: yes. Model: sonnet.

**Entry criteria**:
- [ ] Sortie 10 exit criteria met.
- [ ] S6 already writes `.keyRejected` on generation (`CloudModelAvailability.swift:267–280`) and on the check (`:307`).

**Tasks**:
1. Confirm, and enforce where missing, that every `.keyRejected` snapshot has empty `modelIDs` and `shutdownDates`. A `.keyRejected` result always replaces the last good snapshot (R-8 keeps it only for `.unreachable`).
2. `availableModels()` and `isAvailable(_:)` return nothing for a `.keyRejected` provider.
3. Fix the known race from S6 (Decisions Log): an in-flight listing that started before a generation-time invalidation (`modelUnavailable` or `keyRejected`) must not overwrite it. Give each provider an invalidation counter: a listing records it at start and discards its result if it changed. The next trigger checks again.
4. Tests:
   - a `.keyRejected` check after an `.available` snapshot leaves no available models
   - a generation-time `keyRejected` (Google `400 API_KEY_INVALID`) empties the provider at once and yields one update
   - the race: start a stubbed listing that blocks, invalidate, release the listing, and assert the invalidation holds
   - saving a new key (fingerprint change) clears `.keyRejected` on the next refresh

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0.
- [ ] The race test is deterministic (uses a continuation or semaphore in the stub, no sleeps).

### Sortie 12: New-model acceptance tests (requirements § 8.2 A and B)

**Issue**: intrusive-memory/SwiftVinetas#107

**Priority**: 12 — closes the amendment's WU-A work; G-2a and G-2 follow. Builds: yes. Model: sonnet.

**Entry criteria**:
- [ ] Sortie 11 exit criteria met.
- [ ] `make help` lists no `test-cloud-models` target yet.

**Tasks**:
1. Offline (AC-1 to AC-3), in `Tests/SwiftVinetasTests/`, run by `make test-unit`: request-body golden tests through the real adapters with `StubURLProtocol`, for `gpt-image-2.6-flare`, `gpt-image-2.6-sunburst` and `gemini-3.1-flash-lite-image`:
   - the model field
   - the size for each supported ratio, within the vendor's documented rules
   - no unsupported parameter is sent
   - `maxReferenceImages` references build; one more is refused before any request
   - the 4:1 strip is refused
   Write them table-driven over `CloudModelDescriptor.all`, so later models are covered automatically.
2. Live (AC-4 to AC-7): a separate test target or test plan, skipped unless `VINETAS_LIVE_CLOUD_TESTS=1`, that reads keys only through `ChainedAPIKeyStore.default`. Add `make test-cloud-models` (modelled on `test-integration`), excluded from `test-unit`, `test` and every workflow under `.github/`. It writes its results table to `docs/cloud-model-acceptance.md`.
3. Add `docs/cloud-model-acceptance.md` with the table header, `type: report` frontmatter and no results. The supervisor fills it at G-2a.
4. CHANGELOG entries for S10–S12. Open a ready PR from `mission/roll-call/01` into `development` with `/create-pull-request` and enable auto-merge.

**Exit criteria**:
- [ ] `make build`, `make test-unit` and `make lint-check` exit 0, with no network access.
- [ ] `make help` lists `test-cloud-models`; `grep -rn 'test-cloud-models\|VINETAS_LIVE_CLOUD_TESTS' .github/` finds nothing.
- [ ] No test file contains a literal key or reads a key outside `ChainedAPIKeyStore`.
- [ ] `gh pr view --json baseRefName,isDraft,autoMergeRequest` shows `development`, `false`, non-null.
- [ ] The sortie makes **no** paid call; the live suite is run at G-2a only.

---

## WU-C — Privacy page (vinetas.github.io)

### Sortie 9: Say that Vinetas checks which models a key can use (R-22)

**Priority**: runs in parallel with S1 — no build, docs only. Model: haiku.

**Entry criteria**:
- [ ] First sortie — no prerequisites. Recon A-43: `privacy.md:25,27,40` in `~/Projects/websites/vinetas.github.io` (`origin/main`).

**Tasks**:
1. On a branch off `origin/main`, add one sentence near `privacy.md:25`: once a key is added, Vinetas sends that key, and nothing you wrote, to its vendor to check which models it can use, about once a day.
2. Keep the existing lines 27 and 40 consistent with it.
3. Open a PR. Don't merge: the site's `main` is deployed.

**Exit criteria**:
- [ ] `git diff origin/main -- privacy.md` shows only the added sentence and any wording it forced.
- [ ] A PR is open against the site's default branch.

---

## WU-B — Vinetas app

Branch: `feature/cloud-model-availability` off `origin/development`. The local checkout is
on `release/1.2.0`; switch only after confirming it is clean.

### Sortie 7: Registry and refresh triggers (V-1, V-2, V-3 without the button)

**Issue**: intrusive-memory/Vinetas#181

**Priority**: 7 — after G-2. Builds: yes (Xcode MCP).

**Entry criteria**:
- [ ] G-2 done: our next minor release of SwiftVinetas is tagged and published.
- [ ] Recon A-20, A-28, A-30, A-31 hold: `CloudProviderRegistry` (`Vinetas/Cloud/CloudProviderRegistry.swift`, `@Observable @MainActor`); key save/remove in `SettingsCloudTab.swift:102,118`; SwiftVinetas requirement `upToNextMajorVersion` `0.27.1` (`project.pbxproj:1581–1585`).

**Tasks**:
1. Raise the SwiftVinetas minimum version in `project.pbxproj` to the new minor and update `Package.resolved`.
2. Add `availableCloudModelIDs: Set<String>` to `CloudProviderRegistry`: released, keyed and available in the latest snapshot. Filter its `availableModels` on it.
3. Subscribe to `VinetasClient.shared.cloudAvailability.updates`. Refresh each configured provider at launch (respecting the cache), and force a refresh in `setAPIKey` and `removeAPIKey`.
4. Under `--uitesting`, use a stub availability that reports every keyed model available, so the UI tests don't touch the network.
5. Extend `CloudProviderRegistryTests` (`VinetasTests/CloudEngineTests.swift:95–160`): the filter, refresh on key change, and an unavailable model dropping out.

**Exit criteria**:
- [ ] Both schemes (macOS and iOS) build with the Xcode MCP `BuildProject`.
- [ ] `RunSomeTests` for `CloudProviderRegistryTests` passes, with the new tests included.
- [ ] `grep -n 'availableCloudModelIDs' Vinetas/Cloud/CloudProviderRegistry.swift` finds the property.

### Sortie 8: Studio pickers, fallback and notice (V-5, V-6, V-7)

**Issue**: intrusive-memory/Vinetas#182

**Priority**: 8 — last; gate G-3 follows. Builds: yes (Xcode MCP).

**Entry criteria**:
- [ ] Sortie 7 exit criteria met.
- [ ] Recon A-22, A-23, A-24, A-25 hold: `GenerationViewModel.applyCloudProviders` (`GenerationViewModel.swift:204–213`) switches silently; `cloudModels` (`:158`) filters by `configuredCloudProviders`; `AppDefaults.resolveDefaultModel` (`AppDefaults.swift:120–139`); gallery lookups use `AvailableModel.byID`.

**Tasks**:
1. Change `applyCloudProviders` to take the registry's `availableCloudModelIDs` too. Update its call sites in both `GenerationStudioView.swift` files (`.task` and `.onChange`, macOS `:127,134`, iOS `:87,93`) to pass it and to react when it changes.
2. Filter `GenerationViewModel.cloudModels` on the available IDs.
3. When the selected cloud model is dropped, for a removed key or an unavailable model, switch to the first model in the filtered `cloudModels` list for the same provider, else the first available cloud model, else the default local model, and show a one-line notice: "<model> isn't available for your key; switched to <model>." Use the same placement in both apps.
4. `AppDefaults.resolveDefaultModel` skips an unavailable cloud model.
5. Confirm the gallery and record details still show a dropped model's name (V-6): add one test that a record whose model ID is not in `availableCloudModelIDs` still resolves its display name through `AvailableModel.byID`.
6. Tests: selection fallback with the notice for both causes; `resolveDefaultModel` skipping; extend `hiddenVendorSelectionFallsBackThroughApplyCloudProviders`.

**Exit criteria**:
- [ ] Both schemes build with `BuildProject`.
- [ ] `RunSomeTests` for the changed and new test suites passes.
- [ ] `RunAllTests` on the macOS scheme passes.
- [ ] [judgment] The notice text is the same in both apps and names both models.
- [ ] A ready PR into `development` is open, with auto-merge on.

### Sortie 13: Greyed-out rejected key in Settings (V-4a, R-8a)

**Issue**: intrusive-memory/Vinetas#183

**Priority**: 13 — after S8, on the same branch; G-3 follows. Builds: yes (Xcode MCP).

**Entry criteria**:
- [ ] Sortie 8 exit criteria met (its PR may still be open; S13 commits on the same branch before it merges, or on a follow-up branch off `development` after).
- [ ] The SwiftVinetas floor already includes S11 (0.28.0).

**Tasks**:
1. `CloudProviderRegistry` publishes each released provider's latest snapshot status (`availabilityStatus(for:)` or a dictionary), fed from `cloudAvailability.updates`.
2. In `SettingsCloudTab.swift` (macOS and iPad), a provider whose status is `.keyRejected` is drawn greyed out (secondary foreground), with one line: "Key expired" or "Key not valid" (from the reason). Its models are listed greyed out under it. Replace and Remove stay enabled.
3. Confirm the studio pickers and the Defaults tab offer none of that provider's models (they already filter on `availableCloudModelIDs`; add the assertion).
4. Tests: a stubbed `.keyRejected` snapshot greys the row, shows the reason, and removes the provider's models from `cloudModels` and `availableModels`; a forced refresh after a new key restores them.

**Exit criteria**:
- [ ] Both schemes build with `BuildProject`.
- [ ] `RunSomeTests` for the new tests passes.
- [ ] [judgment] `RenderPreview` (or a screenshot) of Settings → Cloud Engines with one rejected and one working key shows the rejected row greyed with its reason, on macOS and iPad.
- [ ] A ready PR into `development` is open, with auto-merge on.

### Sortie 14: App Store description says the key is checked (R-22)

**Issue**: intrusive-memory/Vinetas#184

**Priority**: runs any time, in parallel with WU-A — no build, metadata only. Model: haiku.

**Entry criteria**:
- [ ] First sortie of its branch. Both `metadata-ios/version/1.2.0/en-US.json` and `metadata-mac/version/1.2.0/en-US.json` contain "nothing is sent until you add a key".

**Tasks**:
1. Branch `docs/app-store-key-check` off `origin/development` in a separate worktree (the local checkout is on `release/1.2.0` and is used by WU-B; don't switch it).
2. In both files' `description`, replace the paragraph under "BRING YOUR OWN CLOUD ENGINE (OPTIONAL)" with the text in requirements R-22, exactly. Change nothing else.
3. Validate both files with `python3 -m json.tool`, and check the description stays under App Store Connect's 4,000-character limit.
4. Open a ready PR into `development` and enable auto-merge.

**Exit criteria**:
- [ ] `grep -c 'nothing is sent until you add a key'` in both files prints 0; `grep -c 'sending only the key, never your prompts'` prints 1 in each.
- [ ] Both files parse as JSON and each `description` is at most 4,000 characters.
- [ ] `git diff origin/development --stat` touches only the two metadata files.
- [ ] A ready PR into `development` is open, with auto-merge on.

---

## Parallelism Structure

**Critical path**: S1 → G-1 → S2 → S3 → S4 → S5 → S6 → S10 → S11 → S12 → G-2a → G-2 → S7 → S8 → S13 → G-3 (12 sorties, 4 human gates).

**Parallel groups**:
- **Group 1**: S1 (WU-A, builds) and S9 (WU-C, no build) at the same time.
- **Group 2**: S2 → S6, then S10 → S12, in sequence. They share files (`CloudHTTP.swift`, `CloudEngineError.swift`, `CloudModelAvailability.swift`), so they can't run in parallel.
- **Group 3**: S7 → S8 → S13 in sequence, after G-2.
- **Group 4**: S14 (no build, its own worktree) at any time; dispatch it alongside S10.

**Agent constraints**: at most one building sortie at a time (S9 is the only one without a build). The human gates, not agent count, limit how fast this goes.

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

| Dependency | Consumer | Resolved version | Local checkout | Status |
|------------|----------|------------------|----------------|--------|
| intrusive-memory/SwiftVinetas | Vinetas | 0.27.1 (`87d7945`) | `~/Projects/package-collection/pkg/SwiftVinetas` | LOCAL_AHEAD (version string only) |
| intrusive-memory/SwiftVinetas | Escribir | 0.26.0 (`07b3e61`) | same | LOCAL_AHEAD (out of scope) |
| intrusive-memory/SwiftAcervo | both | 0.25.0 (`87ec22c`) | — | not checked |

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). Each entry MUST be resolved before refinement can proceed past Pass 1. -->

### OQ-1: New models' order, and the live smoke test
**Affects**: Sortie 1
**Question**: Where do the three new models go in the pickers, and may Sortie 1 make one paid generation per new model with your keys to confirm it works?
**Source**: requirements § 9 D-6 ("needs only a live smoke test per model")
**Why blocking**: Sortie 1's order and its proof that each model works both depend on it.
**Recommendation**: Put each new model before the model it supersedes (2.6 before 2.5; Flash Lite after Flash), and keep the default model unchanged. Approve three generations at the smallest size, about $0.10 in total.
**Rationale**: The vendors now recommend the newer IDs. Keeping the default avoids changing what existing users get without notice.
**Resolution (2026-11-26)**: Accepted. Smoke test done: one generation each for `gpt-image-2.6-flare`, `gpt-image-2.6-sunburst` (OpenAI `/v1/images/generations`, 1024x1024, PNG) and `gemini-3.1-flash-lite-image` (Google `/v1beta/interactions`, 1:1, 1K, JPEG) returned 200 with a decodable image, using the adapters' request bodies. Sortie 1 makes no paid calls.

### OQ-2: How a rejected key surfaces at generation
**Affects**: Sortie 2 (and Sortie 6)
**Question**: Add a `CloudEngineError.keyRejected(provider:reason:)` case, and which CLI exit code does it map to?
**Source**: requirements § 8.1 ("Google's `400 API_KEY_INVALID` is a key error on the generation path"), R-5
**Why blocking**: The new case and its exit code are public API, and Sortie 2's tests assert them.
**Recommendation**: Add `keyRejected(provider:reason:)`, with reason `expired` / `invalid` / `notPermitted`, and map it to exit 78 (`EX_CONFIG`), the same as a missing key.
**Rationale**: For a user, a rejected key is the same as a missing one: fix it in Settings. Exit 69 stays for vendor-side failures.
**Resolution (2026-11-26)**: Accepted: `keyRejected(provider:reason:)`, reasons `expired` / `invalid` / `notPermitted`, CLI exit 78.

### OQ-3: Where snapshots live when the App Group isn't available
**Affects**: Sortie 4
**Question**: D-4 puts snapshots in `group.intrusive-memory.models`. What happens in a process without that entitlement (unsigned dev builds, tests)?
**Source**: requirements § 9 D-4; recon A-13
**Why blocking**: Sortie 4's store needs one defined fallback.
**Recommendation**: Use `<App Group container>/vinetas-cloud-availability/`, resolved through SwiftAcervo's App Group ID. Without the container, fall back to `Caches/io.intrusive-memory.Vinetas/cloud-availability/`. Tests always inject a temp directory.
**Rationale**: It follows the CLI's existing `vinetas-io` pattern (`VinetasCLICore.swift:976`), and a cache that can't reach the group still works, just unshared.
**Resolution (2026-11-26)**: Recommendation adopted (not separately addressed; reversible before Sortie 4).

### Non-blocking (from recon § Unverifiable)
- U-1 (OpenAI unverified organisations), U-2 (Google region and tier), U-3 (BFL and Stability removed-model responses) don't block 1.2.0. Sortie 2's classifier handles each as far as the vendor docs say.

## Summary

| Metric | Value |
|--------|-------|
| Work units | 3 |
| Total sorties | 14 (S10–S14 added 2026-11-27) |
| Open questions | 0 (OQ-1 to OQ-3 resolved 2026-11-26) |
| Dependencies mapped | 3 |
| Dependency structure | layers: WU-A and WU-C (layer 0) → G-2 → WU-B (layer 1) |

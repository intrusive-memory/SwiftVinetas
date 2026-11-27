---
type: requirements
state: ready
updated: 2026-11-26
---

# Requirements — Discover which cloud models a key can use

> Status: **decided (§9); 1.2.0 scope in §8.1. Blocks Vinetas 1.2.0.** 1.2.0 introduces
> cloud engines, so it must not ship a picker that lists models a key can't use.
> `1.2.0-rc6` (App Store build 340) is superseded and must not be submitted; this
> work ships as `1.2.0-rc7` or later. Most of the change lands in SwiftVinetas; the
> Vinetas app follows once a SwiftVinetas release is tagged, and Escribir and
> `vinetas-skills` follow on their own schedules (§8).

## 1. Problem

Every cloud model Vinetas offers is hard-coded:

- `CloudProvider.models` (`Sources/SwiftVinetas/Cloud/CloudProvider.swift`) maps each
  vendor to a fixed list of `CloudModelDescriptor` constants, and
  `CloudModelDescriptor.all` flattens it.
- `ModelSummary.cloud` (`Sources/VinetasVocabulary/ModelSummary.swift`) is a second,
  hand-maintained copy for modules that link no networking. A test keeps the two in step.
- The Vinetas app offers a vendor's whole list as soon as a key is saved
  (`CloudProviderRegistry.availableModels`). It only checks whether a key exists.

No code asks a vendor which models the key can actually use. So:

- **A retired model stays in every picker** until a new SwiftVinetas release, a
  dependency update and an App Store release reach users. Selecting it fails with a
  raw vendor HTTP error. This nearly happened with OpenAI's `gpt-image-1`, retired
  2026-10-23 and replaced by #151 just before 1.2.0.
- **A model the key can't use** (an unverified OpenAI organisation, a region or tier
  limit, a preview model) is offered anyway, and fails the same way.
- **A key that has been revoked** looks configured until the first generation.

## 2. Goal

Each cloud model is offered **only when the vendor confirms the user's key can use
it right now**, as far as that vendor's API can tell us (§4). Models the vendor
doesn't confirm are hidden from pickers but still resolve, so history, saved
defaults and screenplay shot notes that name them keep working.

### Non-goals

- **Adding models Vinetas has no adapter details for.** A model Vinetas offers needs
  known capabilities: steps, guidance, seed, negative prompt, aspect ratios, size
  rules and the reference-image limit. A vendor's model list doesn't provide them
  (§4). The built-in table stays the source of capabilities; discovery only *filters*
  it. Showing unknown vendor models is a separate decision (§9, D-1).
- **Changing the consent rule.** Prompts still need the one-time, per-vendor consent
  (App Review guideline 5.1.2(i)). Discovery sends only the key, never user content (§6.4).
- **Changing which vendors the app offers.** `CloudProviderRegistry.releasedProviders`
  stays the app's vendor gate. Discovery works inside it.

## 3. Terms

| Term | Meaning |
|---|---|
| **Known model** | A `CloudModelDescriptor` built into SwiftVinetas, with its capabilities. |
| **Available model** | A known model the vendor confirmed for this key at the last check. |
| **Availability check** | One call per vendor that lists or probes the models a key can use (§4). |
| **Snapshot** | The result of the last check for one vendor and one key: the available model IDs, when it was checked, and its status (§5.2). |

## 4. What each vendor's API can tell us

Checked against each vendor's API docs on 2026-11-26. "Unconfirmed" means the docs
don't say; recon must verify it with a real key before implementation (§10).

| Vendor | How to check | What it tells us | Gaps |
|---|---|---|---|
| **OpenAI** | `GET https://api.openai.com/v1/models` (Bearer key) returns `data[]` of `{id, created, owned_by, shutdown_date}`. `GET /v1/models/{id}` returns one. | Whether our ID is listed, and a **`shutdown_date`** (a date, or null). This is the only machine-readable retirement signal of the four vendors. | No capability field: image models are known only by ID (`gpt-image-…`). Whether the list is filtered per organisation is unconfirmed. Community reports say an unknown or retired ID returns `404 model_not_found`, and an unverified organisation gets `403` on generation. |
| **Google** | `GET https://generativelanguage.googleapis.com/v1beta/models` (`x-goog-api-key`), paged with `pageSize` (up to 1000) and `pageToken`. **Confirmed:** the default page is 50 and the list has 65 models, so the client must follow `nextPageToken` or send `pageSize=1000`. `GET /v1beta/models/{id}` returns one. | Whether our ID is listed (`name` is `models/<id>`). | No output-modality field; `supportedGenerationMethods` doesn't separate image models. No deprecation field: shutdowns are only on the deprecations page. Whether the list reflects region or tier limits is unconfirmed. |
| **Black Forest Labs** | **No list endpoint.** The model is the URL path (`/v1/flux-2-pro`, `/v1/flux-2-flex`). `GET https://api.bfl.ai/v1/credits` (`x-key`) checks the key and returns `{credits}`. | The key works, and the balance. | Retirement can only be seen on submit. The documented errors are 400, 402 (out of credits), 403, 422, 429, 500 and 503; 404 is undocumented. |
| **Stability AI** | **No list endpoint for v2beta.** `GET /v1/engines/list` covers only the old v1 engines. The model is the URL path (`/v2beta/stable-image/generate/core`, `/ultra`). `GET https://api.stability.ai/v1/user/balance` (Bearer) checks the key: `{credits}`, or 401. | The key works, and the balance. | Retirement can only be seen on submit; the status for a removed path is unconfirmed. On this API, 403 means content moderation, not access. |

What this means for the design:

- **Listing can confirm, never discover.** No vendor says which models make images,
  so the built-in table stays the source of capabilities (non-goal; D-1).
- **OpenAI and Google can be filtered by listing.** BFL and Stability can only have
  their key checked (R-9), and rely on the generation-time path (R-10).
- **OpenAI's `shutdown_date` lets Vinetas warn before a retirement**, not only after (R-5a).
- **Our IDs are already drifting.** OpenAI's deprecation notices now point users at
  `gpt-image-2.6-flare` and `gpt-image-2.6-sunburst`; our 2.5 IDs aren't deprecated
  yet, but they are no longer the recommended targets. Google calls
  `gemini-3.1-flash-image` "previous generation" and lists a new
  `gemini-3.1-flash-lite-image`. Discovery won't add these by itself (D-1), so a
  table update is a separate task (D-6).

## 5. SwiftVinetas changes

### 5.1 Known models stay; availability is added beside them

- **R-1.** `CloudProvider.models`, `CloudModelDescriptor.all` and `.byID` keep their
  meaning: every model this release *can* drive. They stay synchronous, because
  `ImageGenerationEngine.supportedModels` is synchronous and the router, `--model`
  parsing and history lookups depend on it.
- **R-2.** `EngineRouter.allModels` and `CloudImageEngine.supportedModels` are
  unchanged, so resolving a stored model ID always works, available or not.
- **R-3.** Each `CloudModelDescriptor` gains the vendor IDs it accepts as a match
  (`vendorModelID`, plus aliases such as a dated snapshot ID, if §4 shows vendors
  return them). Matching is exact on those IDs, never a prefix guess.

### 5.2 A new availability service

- **R-4.** Add `CloudModelAvailability`, an actor that `VinetasClient` owns and
  exposes as `VinetasClient.cloudAvailability`.
  - `func snapshot(for provider: CloudProvider) async -> CloudAvailabilitySnapshot`
    returns the cached result without a network call.
  - `func refresh(_ provider: CloudProvider, force: Bool = false) async -> CloudAvailabilitySnapshot`
    runs the check when the cache is missing, stale (R-7) or `force` is set.
  - `func availableModels() async -> [CloudModelDescriptor]` returns the available
    models for every provider, in `CloudModelDescriptor.all` order.
  - `nonisolated var updates: AsyncStream<CloudAvailabilitySnapshot>` lets hosts redraw
    when a snapshot changes.
- **R-5.** `CloudAvailabilitySnapshot` holds:
  - `provider`
  - `status`: one of
    - `.available` — the vendor answered; `modelIDs` lists what it confirmed.
    - `.noKey`
    - `.keyRejected` — the vendor rejected the key: 401 or 403, or Google's `400`
      with reason `API_KEY_INVALID` (recon, §10). Carries the reason so hosts can say
      "expired" (OpenAI `expired_secret_key`) apart from "not valid"
      (`invalid_api_key`).
    - `.unreachable` — network failure, timeout, or a 5xx after retries.
    - `.unsupported` — the vendor has no way to check (§4); see R-9.
  - `modelIDs: Set<String>` — our model IDs, not the vendor's.
  - `checkedAt: Date`
  - `keyFingerprint` — a salted SHA-256 prefix of the key. It is used only to tell
    when the key has changed; the key itself is never stored or logged.
  - `shutdownDates: [String: Date]` — our model ID to the vendor's announced
    shutdown date, where the vendor reports one (only OpenAI today, §4).
- **R-5a.** A model whose shutdown date is within **30 days** stays available but
  is flagged `retiringSoon`. Hosts show "Retires on <date>" next to it. On or after
  the date it is treated as unavailable, even before the next check.
- **R-6.** Each vendor's check goes behind a new
  `CloudProviderClient.listAvailableModels(apiKey:session:) async throws -> Set<String>`
  that returns *vendor* model IDs. The service maps them to known models (R-3).
  Adapters reuse `CloudHTTP.perform` for retries and error mapping.
- **R-7.** Cache rules:
  - A snapshot is fresh for **24 hours**.
  - It is stale at once when the key fingerprint changes, a key is added or removed,
    or a generation reports the model is gone (R-10).
  - The cache is persisted so a cold start doesn't wait on the network. Where it
    lives is decision D-4.
- **R-8.** When a check fails, the last good snapshot is kept, with status
  `.unreachable` and its original `checkedAt`. Its models stay available, so a flaky
  network never empties a picker. With no earlier snapshot, the result is decision D-2.
- **R-9.** For a vendor with no way to list models (BFL and Stability, §4), the check
  calls the vendor's balance endpoint (`GET /v1/credits` for BFL,
  `GET /v1/user/balance` for Stability). On success every known model counts as
  available, with status `.unsupported`. Retired models are then caught only by the
  generation-time path (R-10). A zero balance isn't treated as unavailable, but hosts
  may show it.
- **R-9a.** Listing uses one request per vendor: one `GET /v1/models` for OpenAI, and
  Google's list with `pageSize=1000`, following `nextPageToken`. Never one request per model.

### 5.3 Generation-time detection

- **R-10.** Add `CloudEngineError.modelUnavailable(provider:modelID:)`. Each adapter
  maps the vendor's "model not found / not allowed" response (the exact status and
  body pattern is in §4) to this case, not to the generic `httpStatus`. When it is
  thrown, `CloudImageEngine` tells the availability service to drop that model from
  the snapshot (R-7). Hosts redraw from `updates`.
- **R-10a.** Per-vendor mapping to `modelUnavailable`, to confirm in recon (§10):
  - OpenAI: on `POST /v1/images/generations`, an unknown model is **`400`** with
    `error.param == "model"` and `error.code == "invalid_value"` (confirmed in
    recon). `404 model_not_found` comes only from `GET /v1/models/{id}`. Match on
    `param == "model"`, never on the status alone: a bad size is also `400
    invalid_value`, with `param == "size"`. A `403` that says the organisation must
    be verified maps to `modelUnavailable` with that reason (unconfirmed: this
    organisation is verified).
  - Google: `404` on `POST /v1beta/interactions` with `error.code == "not_found"`
    (confirmed in recon; the body names the model and suggests another). Note that
    this endpoint's error body is flat (`{"error": {"message", "code"}}`), unlike the
    `/models` endpoints (`{"error": {"code": 404, "status": "NOT_FOUND"}}`).
  - BFL: `404` on the model path. A `403` keeps meaning "key not allowed", which is
    `keyRejected`, not `modelUnavailable`.
  - Stability: `404` on the model path. A `403` stays a moderation error (§4).

- **R-11.** `modelUnavailable` says in plain words that the vendor no longer offers
  the model, or that the key can't use it, and names the vendor's console. The CLI
  maps it to exit code **69** (`EX_UNAVAILABLE`), the same as the other vendor errors.

### 5.4 `VinetasVocabulary` and `VinetasUI`

- **R-12.** `ModelSummary.cloud` stays as the display table for modules without
  networking. Add a value type, `ModelAvailability` (`available`, `unavailable`,
  `unchecked`), that hosts pass in. `VinetasVocabulary` doesn't fetch anything.
- **R-13.** VinetasUI needs no change: `VinetasGenerationSettingsPanel` already takes
  any `models:` list, and `VinetasPromptDraft`'s lookup by ID
  (`ModelSummary.allIncludingCloud`) keeps resolving every known model. The Vinetas
  app doesn't use this panel; each app has its own `GenerationSettingsPanel` (§7.1).

### 5.5 The `vinetas` CLI

- **R-14.** `vinetas list` runs a refresh for each configured vendor (respecting the
  cache), and shows each cloud model as `available`, `unavailable`, `no key` or
  `not checked`, with when it was checked. `list --json` adds `available` (bool),
  `availability` (the status string) and `checkedAt` to each cloud row. The existing
  `configured` field stays.
- **R-15.** `vinetas list --refresh` forces the check.
- **R-16.** `generate`, `preview` and `storyboard` run with a model whose latest
  snapshot says unavailable fail before contacting the vendor, with exit code 69 and
  the R-11 message. A snapshot that is `.unreachable` or `.unsupported` doesn't block
  the run; the vendor decides.

- **R-17.** `CLIModel.unknownModelError` lists only the available cloud models when
  a snapshot exists, and points at `vinetas list --refresh` otherwise.

## 6. Cross-cutting rules

### 6.1 Keys and privacy

- **R-18.** The key is sent only to its own vendor, only over HTTPS, and only for the
  check in §4. It never appears in a snapshot, log line, telemetry event or error.
- **R-19.** The check runs only when a key resolves. With no key, the status is
  `.noKey` and there is no network call.

### 6.2 Telemetry

- **R-20.** Add one event, `cloudAvailabilityChecked`, with: provider, status, the
  number of available models, the number of known models, and how long the check took.
  It carries no model IDs, because vendor IDs can reveal a customer's tier or preview access.

### 6.3 Cost and rate limits

- **R-21.** At most one check per vendor runs at a time; concurrent callers await the
  same task. A check never retries more than `CloudHTTP.defaultRetryDelays` allows.
  If a vendor charges for or rate-limits the check (§4), the 24-hour cache is the only
  automatic trigger, and Refresh is manual.

### 6.4 App Review and the privacy text

- **R-22.** The check sends the key, and nothing the user wrote, to the vendor the
  user chose. It doesn't need the per-vendor prompt consent. The App Store
  description and privacy policy should still say that Vinetas contacts the vendor to
  check which models the key can use. Update both (`metadata-*/version/<next>/`, and
  the policy page in `vinetas.github.io`) in the release that ships this.

## 7. Consumer changes

### 7.1 Vinetas app (macOS and iPad)

- **V-1.** Bump the SwiftVinetas floor to the release that ships §5.
- **V-2.** `CloudProviderRegistry` publishes `availableCloudModelIDs: Set<String>`
  beside `configuredProviders`: known models that are in `releasedProviders`, have a
  key, **and** are available in the latest snapshot. It listens to
  `cloudAvailability.updates`. Its `availableModels` filters on the same set.
- **V-3.** Refresh triggers:
  - app launch, for each configured vendor, respecting the cache
  - saving or removing a key in Settings → Cloud Engines (forced)
  - a **Refresh** button per vendor in Settings → Cloud Engines (forced)
  - a `modelUnavailable` error (automatic, R-10)
- **V-4.** Settings → Cloud Engines shows each vendor's status in words: "3 models
  available, checked 2 hours ago", "Key rejected — check it in the OpenAI console",
  "Couldn't reach Google; showing the last list", "This vendor can't list models;
  all known models shown." It replaces the static model names in
  `SettingsCloudTab.swift:109` with the available ones.
- **V-5.** When the selected model becomes unavailable, the studio moves the
  selection to the first available model and shows a one-line notice: "<model> isn't
  available for your key; switched to <model>." The same notice is added for a removed
  key, which today switches silently (`GenerationViewModel.applyCloudProviders`).
  `AppDefaults.resolveDefaultModel` skips an unavailable cloud model the same way.
- **V-6.** The gallery and the record details keep showing a record's model name
  even when that model is no longer available (R-2).
- **V-7.** Both studio pickers (`Vinetas/` and `VinetasIOS/`
  `GenerationSettingsPanel.swift`) get their cloud models from
  `GenerationViewModel.cloudModels`, which today filters only by
  `configuredCloudProviders`. `applyCloudProviders` takes the registry's
  `availableCloudModelIDs` as well, and `cloudModels` filters on it. The Settings
  Defaults tab already reads `CloudProviderRegistry.availableModels` (V-2).
- **V-8.** Tests:
  - the registry filter
  - the selection fallback
  - the Settings status text for each snapshot status
  - a stubbed `modelUnavailable` generation that removes the model from the picker

### 7.2 Escribir

Escribir offers every model in `ModelSummary.allIncludingCloud`
(`Shared/Storyboard/ShotDraftMapping.swift:64`) when composing a shot note. It
holds no vendor keys, so it can't run a check itself.

- **E-0.** Add the `group.intrusive-memory.models` App Group to Escribir's
  entitlements (it has none today) and update its provisioning profiles. Raise its
  SwiftVinetas floor (it resolves 0.26.0) to the release that ships §5.
- **E-1.** Escribir reads the availability snapshots that Vinetas and the CLI write,
  if decision D-4 puts them somewhere Escribir can read. It then offers on-device
  models plus available cloud models, and labels the rest "not checked".
- **E-2.** A shot note that already names an unavailable model keeps its value and
  shows it as unavailable. Escribir never rewrites the screenplay for this.
- **E-3.** With no snapshot, Escribir keeps today's behaviour: every known model,
  with a note that availability is checked in Vinetas.

### 7.3 `vinetas-skills`

- **S-1.** `skills/storyboard-screenplay/reference/cloud-models.md` tells agents to
  plan only with models where `list --json` reports `"available": true`. It shows
  `list --refresh` and explains exit code 69 with the `modelUnavailable` message.
- **S-2.** The model table in that file says it lists known models, not a promise
  that they're available.

### 7.4 Not affected

- **Personaje** links SwiftVinetas but uses no cloud models.
- **SwiftBruja** mentions SwiftVinetas only in a comment.

## 8. Release order

Vinetas 1.2.0 is blocked on steps 1–3. Steps 4 and 5 don't block it.

1. **SwiftVinetas minor release** with the model-table refresh (D-6), §5 and §6. It is
   additive: no public API is removed, so `upToNextMajor` consumers pick it up without
   code changes.
2. **Vinetas app** (§7.1) on `development`: raise the SwiftVinetas floor (V-1) and land
   V-2 to V-8, then the usual development → main PR, which ships a TestFlight build.
3. **Vinetas `1.2.0-rc7`** tagged on main and merged into `release/1.2.0`. Before
   submitting, smoke-test on TestFlight with a real OpenAI key and a real Google key:
   the picker lists only models the key can use, and a removed key empties its
   vendor's section. Don't submit build 340 (`rc6`) in the meantime.
4. **`vinetas-skills`** update (§7.3), once step 1 is tagged, because the skills call
   the bundled CLI.
5. **Escribir** (§7.2), after decision D-4 settles where snapshots live. Escribir
   reads the snapshot, so until it ships, Escribir keeps listing every known model.

### 8.1 What ships in 1.2.0

Decided 2026-11-26: 1.2.0 ships the smallest change that stops the pickers listing
models a key can't use. The rest follows in 1.2.1.

**In 1.2.0:**

- **D-6** model-table refresh, as its own SwiftVinetas patch release first.
- **SwiftVinetas:** R-1 to R-5, R-6 to R-11, R-18, R-19, R-21, R-22. R-13 needs no
  change.
  - From R-5a, only the rule that a model is unavailable on or after its
    `shutdown_date`. The `retiringSoon` flag and "Retires on" text wait.
  - Google's `400 API_KEY_INVALID` is a key error on the generation path as well as
    in the check (R-5).
- **Vinetas app:** V-1, V-2, V-5 (including the notice), V-6, V-7.
  - V-3 without the Refresh button: launch, key saved or removed, and
    `modelUnavailable`.
  - V-8 without the Settings status-text tests.

**In 1.2.1:**

- R-5a's `retiringSoon` warning.
- R-12's `ModelAvailability` type in VinetasVocabulary, with Escribir.
- The CLI: R-14 to R-17. Until then, `vinetas list` and generation keep today's
  behaviour, and a dropped model fails with R-11's `modelUnavailable` message.
- Telemetry: R-20.
- Settings → Cloud Engines status text and Refresh button: V-4, and V-3's button.
- Escribir (§7.2) and `vinetas-skills` (§7.3).

## 9. Decisions

All six decided on 2026-11-26 as recommended.

| # | Question | Options | Decision |
|---|---|---|---|
| D-1 | Show image models the vendor lists that Vinetas has no built-in entry for? | (a) Never; (b) CLI only, with conservative defaults and a warning; (c) app and CLI | **(a) for now.** Without known size rules and capabilities, the adapter can send a request the vendor rejects. Revisit with D-5. |
| D-2 | First run with no snapshot and the vendor unreachable: what to offer? | (a) Nothing until a check succeeds; (b) every known model, marked "not checked" | **(b).** Generation needs the network anyway, and the vendor's own error then explains the problem. |
| D-3 | How long is a snapshot fresh? | 1 h / 24 h / 7 d | **24 h.** Retirements are announced weeks ahead; access changes are rare. |
| D-4 | Where do snapshots live? | (a) each process's own caches folder; (b) the shared App Group container (`group.intrusive-memory.models`, already used by SwiftAcervo) | **(b).** The app, the CLI and Escribir then share one answer, and Escribir (§7.2) needs it. Snapshots hold no key material (R-5). |
| D-5 | Should the built-in model table move to a catalog file that updates without an app release? | (a) No; (b) a signed JSON catalog on the CDN, cached, with the built-in table as a fallback | **(a) in this change.** It is a separate project with its own security review. Discovery already covers retirement and per-key access. |
| D-6 | Refresh the built-in table (OpenAI `gpt-image-2.6-*`, Google `gemini-3.1-flash-lite-image`; §4)? | (a) In the same SwiftVinetas release; (b) a separate patch release first; both before 1.2.0 either way | **(b).** Shipping 1.2.0 with IDs the vendors already call "previous generation" is the same problem this change fixes. The patch is small, needs only a live smoke test per model, and can be tagged while the discovery work is built. |

## 10. Recon before implementation

### 10.1 Results, 2026-11-26

Checked with live OpenAI and Google keys (keychain service
`io.intrusive-memory.Vinetas.cloudAPIKeys`, accounts `openai` and `google`).

- **OpenAI**
  - A rejected key is `401` with `error.code` `expired_secret_key` or
    `invalid_api_key`, so `.keyRejected` can say which (R-5).
  - The list holds 103 models with `{id, created, owned_by, shutdown_date}`. Both our
    IDs (`gpt-image-2.5-flare`, `gpt-image-2.5-sunburst`) are listed with no
    shutdown date. `gpt-image-2.6-flare` and `gpt-image-2.6-sunburst` are listed too.
  - **Models stay listed until their shutdown date:** `gpt-image-1.5`,
    `gpt-image-1-mini` and `chatgpt-image-latest` show `2026-12-01`, and
    `gpt-image-2` shows `2027-02-10`. So "listed" alone doesn't mean usable: R-5a
    must treat a `shutdown_date` in the past as unavailable, not only warn before it.
  - An unknown model: `404 model_not_found` on `GET /v1/models/{id}`, but **`400
    invalid_value` with `param: "model"` on generation** (R-10a).
  - A real model with an invalid size got past the model check to a size error, so
    a verified organisation can use `gpt-image-2.5-flare`.
  - No rate-limit headers on `GET /v1/models`; it isn't billed.
- **Google**
  - The list holds all three of our IDs (`gemini-nano-banana-2.1`,
    `gemini-3.1-flash-image`, `gemini-3-pro-image`). It also lists
    `gemini-3.1-flash-lite-image`, plus preview IDs (`gemini-3.1-flash-image-preview`,
    `gemini-3-pro-image-preview`, `nano-banana-pro-preview`) and the older
    `gemini-2.5-flash-image`.
  - No field marks image output; `supportedGenerationMethods` is the same as for
    text models, which supports D-1 (a).
  - Default page size is 50 of 65 models: paging is required (§4).
  - An unknown model: `404 NOT_FOUND` on `GET /models/{id}` and on
    `:generateContent`; `404` with flat `code: "not_found"` on `/interactions` (R-10a).
  - A bad key: **`400 INVALID_ARGUMENT`, reason `API_KEY_INVALID`**, not 401/403.
    `CloudHTTP.perform` must treat it as a key problem, on both the listing and
    the generation path (R-5).
  - Listing isn't billed, and no rate-limit headers were returned.

### 10.2 Still open

1. **OpenAI:** whether `/v1/models` hides `gpt-image-*` from an unverified
   organisation, or lists them and returns `403` on generation. Needs a key from an
   unverified organisation. Either way R-10a catches it at generation time.
2. **Google:** whether region or tier limits change the list (needs a second key in
   another tier or region; low priority).
3. **BFL and Stability (no keys yet):** the status and body for a model path that
   no longer exists. Neither vendor is in `releasedProviders` for 1.2.0, so this
   doesn't block the release.

---
type: requirements
state: complete
updated: 2026-10-18
---

# Requirements — Cloud engines in SwiftVinetas and the `vinetas` CLI

> Status: **final; implemented in this package (release 0.23.0).** The app-side
> follow-up (§6) and the skills update (§7) are specified here and land after
> the release is tagged. Supersedes the draft that lived in the Vinetas app
> repo as `docs/REQUIREMENTS-cloud-engines-cli.md`; that draft now points here.

## 0. Where this sits in the process

The Vinetas app shipped commercial, API-key-backed image engines (OpenAI,
Google Gemini, Black Forest Labs, Stability AI) in its `Vinetas/Cloud/`
folder (app PRs #150, #151, #153). The CLI could not reach them because its
subcommands live in **this** package (`VinetasCLICore`), not in the app: the
app's `VinetasCLI` target is a thin `@main` wrapper that re-bundles
`VinetasCLICore` so it can be signed with the app's team identity and
entitlements. So this is a **library-first** change, following the same chain
as the CLI Pro gate:

1. **SwiftVinetas (this doc, §2–§5):** move the cloud engine layer into the
   library, register it by default, teach the CLI about it. Ship as a
   **minor** release, 0.23.0.
2. **Vinetas app (§6):** bump the SwiftVinetas floor, delete the app-side
   copies the library now owns, adopt the shared keychain group, run the
   one-shot key migration. Lands in a separate PR after 0.23.0 is tagged.
3. **`vinetas-skills` (§7):** document the cloud flags, env vars and exit
   codes. Flips public with the app release.

## 1. Product rules (settled — do not re-derive)

- **Cloud models are not Pro-gated**, in the app or the CLI. The user pays the
  vendor directly; a Pro gate would double-charge. `ProGate` returns `false`
  for every cloud model and never consults the entitlement marker for one.
- **No key is ever written to disk in plaintext** — not in the App Group
  container, not beside `entitlement.jws`, not in a dotfile, not in a PNG's
  metadata, not in a telemetry event, not in an error message. The only
  persistent store is the keychain.
- **There is no `--api-key` flag.** It would land in shell history and `ps`
  output. Keys come from the environment or the keychain.
- A cloud model behaves like any other model at the CLI: same `--model` flag,
  same output files, same metadata sidecar, same stderr conventions. The new
  surface is how the key is supplied, the "configured / no key" state in
  `list`/`info`, and three documented exit codes.
- **Previews are always on-device.** Previews are free by design;
  `vinetas preview` takes no model and `generate --preview --model <cloud>`
  is a validation error.
- Vendor set and ids are the app's and are fixed by this document:

  | Engine id | Vendor | Model ids |
  |---|---|---|
  | `cloud-openai` | OpenAI | `openai-gpt-image-2.5-flare`, `openai-gpt-image-2.5-sunburst` |
  | `cloud-google` | Google | `google-nano-banana-2.1`, `google-gemini-3.1-flash-image`, `google-gemini-3-pro-image` |
  | `cloud-bfl` | Black Forest Labs | `bfl-flux-2-pro`, `bfl-flux-2-flex` |
  | `cloud-stability` | Stability AI | `stability-core`, `stability-ultra` |

  Never ship a catalog that names OpenAI `gpt-image-1*` (retired 2026-10-23).

## 2. Library: the cloud engine layer (`Sources/SwiftVinetas/Cloud/`)

Relocated from the app, same module as the engines (`import SwiftVinetas`
keeps working for the app), behaviour unchanged except where noted.

| Type | Visibility | Notes |
|---|---|---|
| `CloudProvider` | public | Adds `environmentVariable` / `environmentVariableAliases` (§4.1). |
| `CloudModelDescriptor: ModelDescriptor` | public | `cliName == id`, so `--model <id>` works. Public memberwise `init`. |
| `CloudImageEngine: ImageGenerationEngine` | public actor | Public `init(provider:keyStore:session:)`; `keyStore` is public read-only so hosts can show key status. `maxReferenceImages` is 0, `supports(.loraInference)` is false, `validateMemory` is `.ok`, `download`/`delete` are no-ops, `diskSize` is nil, `isAvailable` ⇔ a key resolves. |
| `CloudEngineError` | public | `missingAPIKey` names the env var and the Settings tab; 401/403 hints never include key material. |
| `CloudAPIKeyStoring`, `KeychainAPIKeyStore`, `InMemoryAPIKeyStore` | public | Protocol gains `keySource(for:)` (key-free provenance string). |
| `EnvironmentAPIKeyStore`, `ChainedAPIKeyStore` | public, **new** | §4.1. |
| `KeychainAPIKeyStore.migrateKeys(from:to:providers:)` | public, **new** | §4.2. |
| `CloudHTTP`, `CloudDimensions`, `CloudProviderClient`, `CloudImageOutput`, the four vendor clients | internal | Unchanged shaping; `CloudHTTP.perform` gains the retry in §2.2. |

`CloudProviderRegistry` (observable UI state) **stays in the app**.
`CloudEngineRouter` is **deleted**: the library router now has a registration
API (§3).

### 2.1 Tests move with the code

The adapter suites (stubbed `URLProtocol`, no network) live in
`Tests/SwiftVinetasTests/CloudEngineTests.swift`; the CLI behaviours in
`Tests/SwiftVinetasTests/CLITests/CloudCLITests.swift`. Both run in
`make test-unit` and in CI. The app keeps only its own layers (registry,
view-model gating) — see §6.

### 2.2 Rate limits (closes the draft's open question)

`CloudHTTP.perform` retries **429** and **503** twice (1 s, then 2 s), honouring
a numeric `Retry-After` header clamped to 30 s, before surfacing
`CloudEngineError.httpStatus`. Both the app and the CLI get this because the
adapters are shared. The BFL polling loop uses the same primitive.

## 3. Library: `EngineRouter` registration and default wiring

```swift
public actor EngineRouter {
  public func register(_ engine: any ImageGenerationEngine) async   // replaces same engineID; installs current telemetry
  public func unregister(engineID: String) async                    // unloads first; no-op for unknown id
  public var registeredEngineIDs: [String]
}
```

`VinetasClient.init()` registers `PixArtEngine`, `Flux2Engine`, and one
`CloudImageEngine` per `CloudProvider`, each built on `ChainedAPIKeyStore.default`
(§4.1). Consequences that hold and are tested:

- `router.allModels` includes the nine cloud descriptors on every machine,
  key or no key, so the catalog is stable and `AppDefaults.resolveDefaultModel()`
  / `VinetasClient.listModels()` need no special case.
- `router.engine(for:)` resolves a `CloudModelDescriptor` directly.
- `VinetasClient.validateMemory(for:)` returns `.ok` for a cloud model.
- `availability(model:)` for a cloud model is `.available` iff a key
  resolves, `.notAvailable` otherwise.
- `ReferenceValidator` rejects references for a cloud model **before**
  `loadModel` (the engine reports zero reference slots).
- Telemetry: `engineRegistered(engineID: "cloud-…", reason: "default")` is
  emitted like the local engines. No key material appears in any event.

### 3.1 Output dimensions

Cloud vendors snap requested sizes to their own grids or aspect presets.
`VinetasClient.generate(_:)` now records `result.image.width/height` — the PNG's
real dimensions — in `PanelMetadata.width/height` rather than the request.
On-device engines render the clamped request exactly, so nothing changes for
them. (`generateSequence` already returned images, not metadata.)

## 4. Key resolution

### 4.1 Resolution order (CLI and app share this)

`ChainedAPIKeyStore.default`, first non-nil wins:

1. **Environment** — `EnvironmentAPIKeyStore`, read-only.

   | Provider | Variable | Also accepted |
   |---|---|---|
   | OpenAI | `OPENAI_API_KEY` | — |
   | Google | `GEMINI_API_KEY` | `GOOGLE_API_KEY` |
   | Black Forest Labs | `BFL_API_KEY` | — |
   | Stability AI | `STABILITY_API_KEY` | — |

   This is how agents, cron shells and CI supply keys; it needs no keychain
   and no GUI session. Whitespace is trimmed; an empty value is "unset".

2. **Shared keychain** — `KeychainAPIKeyStore.shared`: the item the GUI wrote.
   Read-write from the app; the CLI only reads (it never persists a key it
   was handed in the environment).

Writes through the chain skip read-only members and land in the keychain;
removals apply to every writable member.

### 4.2 Sharing the keychain item between the app and the CLI

Both binaries are sandboxed and signed by team `H3EJ6Y8VJ6`, and the sandbox
gives each its own keychain partition. Two facts the draft missed, now
designed in:

- **macOS honours `kSecAttrAccessGroup` only in the data-protection keychain.**
  The file-based login keychain (where the app's pre-0.23 items live) has
  per-app ACLs instead, and a second app reading an item prompts the user —
  impossible for a CLI in a non-GUI session. So `KeychainAPIKeyStore` sets
  `kSecUseDataProtectionKeychain = true` whenever an access group is
  configured.
- **The group string carries the team prefix at runtime.** The entitlement
  declares `$(AppIdentifierPrefix)io.intrusive-memory.Vinetas.shared`; the
  resolved value, `H3EJ6Y8VJ6.io.intrusive-memory.Vinetas.shared`, is
  `KeychainAPIKeyStore.vinetasSharedAccessGroup`.

Rules:

- `KeychainAPIKeyStore.shared` is the grouped, data-protection store on macOS
  and the plain per-app store on iOS (no CLI there, so no group).
- `Vinetas/Vinetas.entitlements` (the macOS app) gains
  `keychain-access-groups = ["$(AppIdentifierPrefix)io.intrusive-memory.Vinetas.shared"]`
  (§6).
- **The bundled `VinetasCLI` does not get the group (yet).** It is signed with
  no provisioning profile and no `com.apple.application-identifier`
  (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`). On macOS `keychain-access-groups`
  is a restricted entitlement validated against an embedded profile, so adding
  it to a bare command-line tool would get the binary refused at launch. Until
  the CLI is re-packaged as a bundled helper with its own App ID and profile,
  the CLI resolves keys from the **environment only**, and GUI-saved keys do
  not reach it. The library needs no change for either outcome: an
  unentitled read of the shared store returns nil and the chain falls through.
- **Migration (app, one shot, idempotent):** on first launch after the floor
  bump, `KeychainAPIKeyStore.migrateKeys(from: .legacy, to: .shared)` copies
  each provider's key from the un-grouped item into the group and deletes the
  old item. A provider already present in the group is left alone.
- `kSecAttrAccessible` stays `AfterFirstUnlockThisDeviceOnly`. A CLI call
  after reboot but before first unlock reads no key and surfaces
  `missingAPIKey` with the env-var hint.
- A process **without** the entitlement for the group — the locally built,
  unsigned `vinetas` from `make build` — reads no key from the shared store
  (`errSecMissingEntitlement` is swallowed) and falls through to the
  environment variable. That is the supported path for developers.
- Mac App Store review: a keychain access group under the app's own team
  prefix is the standard Keychain Sharing capability; no extra request is
  needed for the app. Re-packaging the CLI as a provisioned helper is a
  separate decision, to be verified against a real App Store signature.

## 5. CLI behaviour (`VinetasCLICore`)

All `--model` flags resolve through `CLIModel.resolve`: on-device short names
(`klein4b`, `pixart-sigma`) first, then any cloud model id. An unknown value is
a `ValidationError` that lists both vocabularies and points at `vinetas list`.

| Command | Behaviour |
|---|---|
| `generate --model <cloud-id>` | Runs through the registered cloud engine. `--steps`, `--guidance`, `--seed`, `--negative` the model doesn't honour are **ignored with one `warning:` line each on stderr**, not an error. `--lora` is a validation error (cloud engines cannot apply adapters). `-r` fails via `ReferenceValidator` before any network call. The reported seed is written to the sidecar exactly like local runs (0 when the vendor has no seed). Metadata `width`/`height` are the vendor's actual output size. |
| `batch` | Same resolution and warnings; one job per prompt, **sequential** — vendors rate-limit, so no parallel fan-out in v1. |
| `storyboard` | `--model` and a shot's `model=` attribute accept cloud ids. Per panel: a `lora` on a cloud shot is dropped with a warning; unsupported flags warn; `preview` is dropped (previews stay local). Pro gate and downloads are skipped for cloud models. |
| `preview` | **Stays local.** Takes no `--model`. `generate --preview --model <cloud-id>` is a validation error pointing at `generate`. |
| `list` | Adds a "Cloud models" section: model id, vendor, `configured (<source>)` / `no key`, and the variable to set. `--json` adds `cloud`, `provider`, `vendorModelID`, `configured`, `keySource`, `environmentVariable`, capability flags and `pricingHint`, keeping `model` / `requiresPro: false` / `isDownloaded` for existing consumers. Never prints a key or any prefix of one. |
| `info --model <cloud-id>` | Vendor, vendor model id, engine, capability flags, aspect ratios, price hint, key status (with a "set `<VAR>` or add it in Settings" hint when absent), console and terms URLs. |
| `download --model <cloud-id>` | No-op: prints "cloud model — nothing to download" with the env-var hint, exit 0. (There is no `delete` subcommand.) |
| `character reference` / `character train` | Refuse a cloud model with a validation error **before** any paid call: reference sheets need FLUX.2 reference conditioning and LoRA training is on-device only. |
| network | The CLI reaches nothing but the chosen vendor's documented endpoints. No analytics, no key-validation pings. |

### 5.1 Exit codes

| Condition | Code | sysexits | Agents branch on it to… |
|---|---|---|---|
| No API key resolved | **78** | `EX_CONFIG` | export the variable the stderr line names, retry |
| Vendor declined the prompt or output (moderation) | **65** | `EX_DATAERR` | rewrite the prompt |
| Vendor HTTP error, timeout, or undecodable reply | **69** | `EX_UNAVAILABLE` | back off / try another vendor; the vendor's message is on stderr verbatim |
| Unknown model, `--lora`/`--preview`/`-r` with a cloud model | 64 | `EX_USAGE` | fix the invocation |

Every cloud failure is printed as `error: <description>` on stderr before the
process exits with its code.

## 6. Vinetas app follow-up (after the 0.23.0 tag)

- Bump the SwiftVinetas floor to 0.23.0; resolve.
- Delete `Vinetas/Cloud/*` except `CloudProviderRegistry.swift`. The types it
  used (`CloudProvider`, `CloudAPIKeyStoring`, `KeychainAPIKeyStore`,
  `InMemoryAPIKeyStore`, `CloudModelDescriptor`) now come from
  `import SwiftVinetas`.
- `VinetasImageGenerator.engine(for:)` collapses to
  `VinetasClient.shared.router.engine(for:)`; remove `cloudRouter`.
- `MemoryValidator`: drop the `is CloudModelDescriptor` short-circuit.
- `AppDefaults.resolveDefaultModel()`: drop the `CloudModelDescriptor.byID`
  special case (the router lists cloud models now).
- Add `keychain-access-groups` to the macOS app's entitlements only (§4.2);
  on launch call `KeychainAPIKeyStore.migrateKeys(from: .legacy, to: .shared)`
  silently (idempotent). The migration is required: the library's default
  engines read `.shared`, so un-migrated keys would surface as
  `missingAPIKey`. `CloudProviderRegistry` and the app's own key reads
  use `KeychainAPIKeyStore.shared` (which is now the grouped store on macOS).
- `VinetasTests/CloudEngineTests.swift`: keep the registry, view-model gating
  and routing suites; delete the adapter suites (they moved upstream).
- Help → "Use with AI Agents" (`AgentSetupView`) gains a line about
  `OPENAI_API_KEY` / `GEMINI_API_KEY` / `BFL_API_KEY` / `STABILITY_API_KEY`
  and the three exit codes.
- The `AvailableModel` cloud helpers keep working unchanged
  (`cloudDescriptor`, `isCloud`, `supports…`, `engineBadge`, `pickerSubtitle`).

## 7. `vinetas-skills` / `vinetas-cli` skill

- Document the cloud model ids, the env vars, "preview is always local", the
  LoRA/reference refusals, and the three exit codes.
- Add the recipe "render this storyboard with FLUX.2 [pro] via BFL":

  ```bash
  env BFL_API_KEY="$(security find-generic-password -s io.intrusive-memory.Vinetas.cloudAPIKeys -a bfl -w)" \
    VinetasCLI storyboard script.fountain --model bfl-flux-2-pro --output-dir ./board
  ```

  (or export the variable for one shell; never put the key on the command
  line itself).

## 8. Acceptance criteria

1. With `OPENAI_API_KEY` set and no GUI ever launched,
   `vinetas generate --model openai-gpt-image-2.5-flare "…"` writes a PNG and
   exits 0. — `CloudLiveSmokeTests` (GPU/integration target; skipped when the
   variable is unset, never in CI) plus the stubbed `CloudCLITests`.
2. **Deferred.** A key saved in the GUI reaching the bundled CLI needs the CLI
   re-packaged as a provisioned helper (§4.2). Until then the bundled CLI
   uses the environment variable, and with none set it exits 78 naming it.
3. With neither, it exits **78** and names the variable. — `CloudCLITests`.
4. `vinetas list` / `list --json` output contains no substring of any
   configured key. — `CloudCLITests` (key `SECRET-KEY-XYZ-123`).
5. `generate --preview --model bfl-flux-2-pro` exits non-zero with no network
   call. — `CloudCLITests` (stub counts zero requests).
6. App: after the floor bump, `AvailableModel.cloudModels`,
   `GenerationViewModel.cloudModels` and Settings → Cloud Engines behave as
   before, and keys saved before the bump are present after it. —
   `migrateKeys` is unit-tested here with in-memory doubles; the app adds the
   two-partition test in §6.
7. No file under the App Group container contains an API key at any point. —
   The library writes nothing but the keychain; the live smoke test checks
   the PNG and its metadata.

## 9. Resolved questions from the draft

- **Per-project `.vinetas/keys` reference:** no — environment variables are
  enough for v1.
- **429 handling:** retry in the shared adapter (§2.2), decided before the
  move so the app inherits it.
- **Gemini:** the draft predated `cloud-google`; it is in the catalog, env
  var `GEMINI_API_KEY` (alias `GOOGLE_API_KEY`), and its adapter and tests
  moved with the rest.

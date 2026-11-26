---
type: recon-report
state: current
requirements_file: REQUIREMENTS-CLOUD-MODEL-DISCOVERY.md
requirements_sha256: abb017a20ded0b4c6d97007bea5db4236ce4820c924438765f3f923da60f5bac
project_head: f2b10e4
search_root: ~/Projects
generated: 2026-11-26
verdict: CLEAR
---

# RECON_REPORT.md — Cloud model discovery

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**CLEAR**: 34 assumptions checked: 30 confirmed; the 4 blocking ones were settled by
amending the requirements on 2026-11-26 (recommended option for each). Another 3 are
unverifiable and none blocks 1.2.0.

The amended claims (V-2, V-5, V-7, R-13, E-0) rest only on facts confirmed below
(A-22, A-24, A-33, A-41, A-30), so no spoke was re-run.

## Assumption findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `CloudProvider.models`, `CloudModelDescriptor.all` / `.byID` | repo | CONFIRMED | `CloudProvider.swift:111`, `CloudModelDescriptor.swift:260,263` |
| A-02 | A-API | `vendorModelID` on each descriptor; 9 descriptors | repo | CONFIRMED | `CloudModelDescriptor.swift:22,104–248` |
| A-03 | A-API | `ModelSummary.cloud`, `allIncludingCloud`, parity test | repo | CONFIRMED | `ModelSummary.swift:451,464`; `ModelSummaryRoundTripTests.swift:24` |
| A-04 | A-API | `supportedModels` synchronous; `CloudImageEngine` actor; `EngineRouter.allModels` | repo | CONFIRMED | `ImageGenerationEngine.swift:25`; `CloudImageEngine.swift:15,95`; `EngineRouter.swift:90` |
| A-05 | A-API | `VinetasClient` owns the engines | repo | CONFIRMED | `Vinetas.swift:39,132–137`: `final class VinetasClient: Sendable`, `static let shared` |
| A-06 | A-API | `CloudProviderClient` protocol and 4 adapters; stubbable transport | repo | CONFIRMED | `CloudHTTP.swift:18–26` (**internal**); `CloudEngineTests.swift:17` (`StubURLProtocol`) |
| A-07 | A-BEHAVIOR | `CloudHTTP.perform` retries 429/503, maps 401/403, ignores `param`/`code` | repo | CONFIRMED | `CloudHTTP.swift:31,63–88` |
| A-08 | A-API | `CloudEngineError` cases; exhaustive switches | repo | CONFIRMED | 9 cases, not `@frozen`; exhaustive at `CloudEngineError.swift:69` and `CLIModel.swift:225` |
| A-09 | A-BEHAVIOR | Endpoints per adapter | repo | CONFIRMED | `OpenAIImageClient.swift:19,22`; `GeminiImageClient.swift:21`; `BFLImageClient.swift:14`; `StabilityImageClient.swift:14` |
| A-10 | A-BEHAVIOR | Key resolved per call; env then keychain | repo | CONFIRMED | `CloudAPIKeyStore.swift:204–262`; `CloudImageEngine.swift:112,123` |
| A-11 | A-API | CLI `list --json` `configured`; `CLIModel.resolve` / `unknownModelError`; exit codes 69/78/65 | repo | CONFIRMED | `VinetasCLICore.swift:708–801`; `CLIModel.swift:215–247` |
| A-12 | A-API | `VinetasGenerationSettingsPanel(models:)`; `VinetasPromptDraft` uses `allIncludingCloud` | repo | CONFIRMED | `VinetasGenerationSettingsPanel.swift:91`; `VinetasPromptDraft.swift:107` |
| A-13 | A-CONFIG | SwiftVinetas can reach `group.intrusive-memory.models` | repo | CONFIRMED (caveat) | Only via SwiftAcervo (`Acervo.sharedModelsDirectory`); the CLI's `resolveIODirectory()` (`VinetasCLICore.swift:976`) is internal to the CLI. New helper needed in SwiftVinetas. |
| A-14 | A-API | Telemetry facility for a new event | repo | CONFIRMED | `VinetasTelemetryEvent.swift:58` (already has `modelAvailabilityChecked(modelID:available:)` for local models); encoder `VinetasEventEncoding.swift:27` |
| A-15 | A-INVARIANT | No cloud model list is cached today | repo | CONFIRMED | no `/v1/models` or `v1beta/models` in `Sources` |
| A-16 | A-BEHAVIOR | No key-rejected case today | repo | CONFIRMED | Google `400 API_KEY_INVALID` → `httpStatus`, exit 69 |
| A-20 | A-API | `CloudProviderRegistry.releasedProviders`, `availableModels` filters by key | app | CONFIRMED | `Vinetas/Cloud/CloudProviderRegistry.swift:16–18,145–150` |
| A-21 | A-FILE | `SettingsCloudTab.swift:109` lists model names | app | CONFIRMED | lists `provider.models` names; shared by iOS (`VinetasIOS/Views/Settings/SettingsView.swift:47`) |
| **A-22** | A-BEHAVIOR | `applyCloudProviders` moves the selection **and says why** | app | **STALE** | `GenerationViewModel.swift:204–213` |
| A-23 | A-API | `AppDefaults.resolveDefaultModel` | app | CONFIRMED | `AppDefaults.swift:120–139` |
| **A-24** | A-FILE | Both pickers and the Defaults tab use the registry's `availableModels` | app | **STALE** | `GenerationSettingsPanel.swift:37` (both apps); `GenerationViewModel.swift:158` |
| A-25 | A-BEHAVIOR | Gallery shows any record's model | app | CONFIRMED | `GenerationRecord+CloudDisplay.swift:16` (`AvailableModel.byID`); `GalleryDetailView.swift:405` |
| A-26 | A-INVARIANT | No exhaustive app switch over `CloudEngineError` | app | CONFIRMED | only a construction at `GenerationViewModel.swift:571`; errors shown via `localizedDescription` (`GenerationStudioView.swift:72–93`) |
| A-27 | A-CONFIG | App Group in both apps' entitlements | app | CONFIRMED | `Vinetas.entitlements`, `VinetasIOS.entitlements`; also `VinetasCLI.entitlements` |
| A-28 | A-API | App uses `VinetasClient.shared`; registry owns key save/remove | app | CONFIRMED | `SettingsCloudTab.swift:102,118`; `VinetasApp.swift:36` |
| A-29 | A-FILE | `metadata-*/version/<v>/` for the App Store text | app | CONFIRMED | `metadata-{ios,mac}/version/1.2.0/en-US.json` (JSON, not text files) |
| A-30 | A-CONFIG | App's SwiftVinetas requirement | app | CONFIRMED | `project.pbxproj:1581–1585`: `upToNextMajorVersion`, `0.27.1` |
| A-31 | A-BEHAVIOR | Launch hook and key-change observation exist | app | CONFIRMED | `.task` and `.onChange(of: configuredProviders)` at `GenerationStudioView.swift:127,134` |
| A-32 | A-FILE | Existing registry and fallback tests | app | CONFIRMED | `VinetasTests/CloudEngineTests.swift:95–160`; `hiddenVendorSelectionFallsBackThroughApplyCloudProviders` |
| **A-33** | A-API | `VinetasGenerationSettingsPanel` is what hosts use (R-13) | app | **REFUTED** | not used by the Vinetas app: each app has its own `GenerationSettingsPanel` |
| A-40 | A-API | Escribir `ShotDraftMapping.swift:64` uses `allIncludingCloud` | escribir | CONFIRMED | `Shared/Storyboard/ShotDraftMapping.swift:64` |
| **A-41** | A-CONFIG | Escribir can read the shared App Group (E-1, D-4) | escribir | **REFUTED** | `Escribir.entitlements` has no `application-groups` |
| A-42 | A-FILE | `vinetas-skills` `reference/cloud-models.md` and its table | skills | CONFIRMED | `cloud-models.md:8` |
| A-43 | A-FILE | Privacy page in `vinetas.github.io` | site | CONFIRMED | `privacy.md:25,27,40` |

### Blocking findings (all resolved)

#### A-22 — STALE → resolved (V-5 amended: option 1)
**Claim**: V-5: the studio "moves the selection … and says why, as `applyCloudProviders` already does for a removed key."
**Found**: `GenerationViewModel.applyCloudProviders` (`Vinetas/ViewModels/GenerationViewModel.swift:204–213`) sets `selectedModel = availableModels.first` silently. There is no alert, banner or status text.
**Impact**: V-5 is planned as reuse of an existing message, but the message has to be built for both apps.
**Options**:
1. Amend V-5: add a one-line studio notice ("<model> isn't available for your key; switched to <model>"), shown for both a removed key and an unavailable model *(recommended)*.
2. Keep the change silent, as it is today for a removed key.

#### A-24 — STALE → resolved (V-2, V-7 amended: option 1)
**Claim**: V-2 and V-7: both pickers and the Defaults tab use `CloudProviderRegistry.availableModels`.
**Found**: Only `SettingsDefaultsTab.swift:55` uses it. The studio pickers get `GenerationViewModel.cloudModels` (`GenerationViewModel.swift:158`), which filters `AvailableModel.cloudModels` by `configuredCloudProviders`, a copy of the registry's key state passed in by `applyCloudProviders`.
**Impact**: Changing only the registry leaves the studio pickers unfiltered.
**Options**:
1. Amend V-2 and V-7: the registry publishes an `availableCloudModelIDs` set alongside `configuredProviders`; `applyCloudProviders` takes both, and `GenerationViewModel.cloudModels` filters on it *(recommended: smallest change, same path as keys)*.
2. Make the view model read the registry directly (a larger refactor across both apps).

#### A-33 — REFUTED → resolved (R-13 amended; R-12 to 1.2.1)
**Claim**: R-13: hosts pass only available models to `VinetasGenerationSettingsPanel`.
**Found**: The Vinetas app doesn't use `VinetasGenerationSettingsPanel`; each app has its own `GenerationSettingsPanel`. R-13 matters only to other hosts of VinetasUI.
**Options**:
1. Amend R-13: VinetasUI needs no change for 1.2.0; it keeps taking any `models:` list. Move `ModelAvailability` (R-12) to 1.2.1 with Escribir *(recommended)*.

#### A-41 — REFUTED → resolved (E-0 added)
**Claim**: E-1 and D-4: Escribir can read snapshots in `group.intrusive-memory.models`.
**Found**: `Escribir.entitlements` has no App Group.
**Impact**: E-1 needs a new entitlement and its provisioning profile change. Outside 1.2.0 scope; doesn't block the Vinetas work.
**Options**:
1. Amend E-1: Escribir adds the `group.intrusive-memory.models` App Group entitlement first *(recommended)*.

## Local dependency map

| Dependency | Consumer | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------|----------------|-----------|--------|
| intrusive-memory/SwiftVinetas | Vinetas | `upToNextMajor` `0.27.1` | `0.27.1` (`87d7945`) | `~/Projects/package-collection/pkg/SwiftVinetas` | `f2b10e4` (docs branch off `development` `ee3a718`) | LOCAL_AHEAD: 2 commits, `Sources` differ only in the version string |
| intrusive-memory/SwiftVinetas | Escribir | (pbxproj) | `0.26.0` (`07b3e61`) | same | same | LOCAL_AHEAD |
| intrusive-memory/SwiftAcervo | both | — | `0.25.0` (`87ec22c`) | not needed | — | not checked |

### Drift and ambiguity notes

- **The Vinetas checkout is on `release/1.2.0`, not `development`.** App claims were verified against `origin/development` (`dcba0b8`). Its Swift sources match the local `release/1.2.0` tip.
- **Escribir is one minor behind** (0.26.0). E-1 needs it raised to the release that ships §5.
- Other checkouts: `vinetas-skills` is on `docs/cloud-models`; `vinetas.github.io` is on `docs/contract-revisions-4-8`. Both were read at `origin/main`.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| U-1 | OpenAI hides `gpt-image-*` from unverified organisations | needs an unverified organisation's key | a key from one; R-10a catches it at generation either way |
| U-2 | Google list varies by region or tier | one key only | a second key |
| U-3 | BFL and Stability response for a removed model | no keys | keys; neither vendor ships in 1.2.0 |

## Handoff to breakdown

- `CONFIRMED` facts are safe as sortie entry criteria.
- New surface the plan must create: an App Group path helper inside SwiftVinetas (A-13), and an internal `listAvailableModels` on the adapters (A-06).
- Adding `CloudEngineError` cases must update `CloudEngineError.swift:69` and `CLIModel.swift:225` in the same sortie (A-08). No app code breaks (A-26).
- The existing `modelAvailabilityChecked` telemetry event is for local models. Don't reuse its name for R-20 (1.2.1).
- U-1 to U-3 become Open Questions; none blocks 1.2.0.

---
type: project
title: Background Model Downloads on iOS — SwiftVinetas layer
issue: https://github.com/intrusive-memory/SwiftAcervo/issues/81
status: proposed
updated: 2026-07-11
---

# REQUIREMENTS — Background Model Downloads on iOS (SwiftVinetas layer)

**Tracking issue:** [intrusive-memory/SwiftAcervo#81](https://github.com/intrusive-memory/SwiftAcervo/issues/81)
**Downstream app:** [intrusive-memory/Vinetas#134](https://github.com/intrusive-memory/Vinetas/issues/134)
**Peer spec:** `SwiftAcervo/REQUIREMENTS.md` (the transport lives there)
**Status:** Proposed — not started
**Baseline:** SwiftVinetas 0.16.5 (dev: 0.16.5-dev on `development`)

---

## 1. Where SwiftVinetas sits

SwiftVinetas is the **middle layer**: the app calls `VinetasClient.download(...)`,
which fans out to a per-engine `download(...)`, which calls into SwiftAcervo's
component-download API. SwiftAcervo owns the `URLSession`/transport; SwiftVinetas
owns model composition, progress aggregation, and the public app-facing API.

This spec covers **only the SwiftVinetas changes**. Transport (background
`URLSession`, `downloadTask`, multi-file ledger, resume-data) is specified in
`SwiftAcervo/REQUIREMENTS.md`. App-side re-attach (`UIApplicationDelegate` hook)
is a Vinetas concern.

## 2. Platform scope — iOS only

Same as the SwiftAcervo spec: the background path is **iOS-only**. macOS/CLI keep
the current foreground, single-`await` path with **zero behavioral change**. All
new SwiftVinetas behavior is gated `#if os(iOS)` or behind an injected strategy.

## 3. Current architecture (grounded)

- **Public API** — `VinetasClient.download(model:progress:)`
  (`Sources/SwiftVinetas/Vinetas.swift:668`):
  ```swift
  public func download(
    model: any ModelDescriptor,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws
  ```
  Returns `Void`, `async throws`; **completion is signaled only by the call
  returning**. Static convenience overload at `Vinetas.swift:1304`.

- **Engine protocol** — `ImageGenerationEngine.download(_:progress:) async throws`
  with `progress: @Sendable (DownloadProgress) -> Void`
  (`Engine/ImageGenerationEngine.swift:86`).

- **Per-engine fan-out (sequential `for` loop over components):**
  - PixArt: iterates `model.componentIds`, per component calls
    `Acervo.ensureComponentReady(_:progress:telemetry:)`
    (`Engine/PixArtEngine.swift:494`, call at `:545`).
  - FLUX.2: iterates `Self.modelComponents(for:)`, per component calls
    `Acervo.ensureAvailable(_:files:progress:)`
    (`Engine/Flux2Engine.swift:470`, call at `:501`).
  - Overall progress computed as `(componentIndex + component_fraction) / total`.

- **A "model" = multiple SwiftAcervo repos, each multi-file:**
  - PixArt-Sigma XL → 3 components (T5-XXL encoder, DiT backbone, SDXL VAE),
    ~3.6 GB (`PixArtEngine.swift:26-28,41`).
  - FLUX.2 Klein → 3 components (transformer, Qwen3 text encoder, VAE)
    (`Flux2Engine.swift:659-678,733+`).
  - File lists come from the CDN manifest, not hard-coded here
    (`PixArtEngine.swift:213`).

- **Progress model (all synchronous, `@Sendable`, non-streaming):**
  `AcervoDownloadProgress` → `DownloadProgress`
  (`Engine/EngineTypes.swift:127`) → `VinetasDownloadProgress`
  (`Vinetas.swift:11`). Engines wrap the closure with
  `withoutActuallyEscaping(progress)` (`PixArtEngine.swift:530`,
  `Flux2Engine.swift:487`).

- **No durable in-flight state.** No delegates, no `AsyncStream`, no Combine, no
  `NotificationCenter`, no `BGTask`, no `URLSession` in `Sources/` (confirmed).
  The only relaunch-survivable signal is `VinetasClient.availability(model:)`
  (`Vinetas.swift:734`), which re-derives `.available / .partial(missing:) /
  .notAvailable` from disk. `.downloading(progress:)` is backed by SwiftAcervo's
  **in-memory** in-flight registry — lost on process kill.

## 4. Why the current design breaks under background downloads

1. **`async throws` = single live continuation.** The whole chain
   (`VinetasClient.download` → `await engine.download` → per-component
   `await Acervo.ensureComponentReady/ensureAvailable`) assumes one continuation
   alive for the entire transfer. On iOS the awaiting `Task` is torn down on
   suspension/kill, so the `await` **never resumes** and completion delivered in a
   later launch has nothing to return to.

2. **Non-escaping progress closure.** `withoutActuallyEscaping(progress)`
   contractually forbids retaining the closure past the call. A background flow
   that reports progress/completion in a later launch **cannot use it** — it would
   dangle. A new escaping/observation channel is required.

3. **Sequential component loop.** Downloading component-by-component with
   index-based progress assumes synchronous, ordered, in-process completion.
   Background transfer enqueues work the OS drains out-of-process, possibly
   reordered and across launches; progress must be derived from durable per-file
   state (SwiftAcervo ledger), not a loop index.

4. **`.downloading(progress:)` is in-memory.** After relaunch the app can't show
   real progress because the registry is gone.

## 5. Functional requirements (SwiftVinetas)

### SV-R1 — Additive "start background download" API (iOS)
Add an API that **enqueues** a model's component downloads and returns
immediately (does not `await` completion). Example shape (final naming TBD):
```swift
#if os(iOS)
public func startBackgroundDownload(model: any ModelDescriptor) async throws
#endif
```
It resolves each component to its SwiftAcervo repo (reusing the existing
component→repo mapping) and hands the whole set to SwiftAcervo's background
enqueue API (SwiftAcervo R2/R3), rather than looping `await` per component.

### SV-R2 — Escaping observation channel (progress + completion)
Provide a completion/progress surface independent of any live continuation —
e.g. an `AsyncStream<VinetasDownloadEvent>` (or forwarding of SwiftAcervo's
observation API from R11) delivering model-level `progress / completed / failed`
events. This is the source of truth after relaunch. Progress values map to the
existing `VinetasDownloadProgress` shape where possible.

### SV-R3 — Preserve the foreground/macOS API unchanged
`download(model:progress:) async throws` and both progress structs keep their
current signatures and semantics on macOS/CLI. On iOS, this call either (a)
bridges to SV-R2 and resolves **iff** the app stays foregrounded for the whole
transfer, or (b) is documented as best-effort-foreground with SV-R2 as the
authoritative path. **Decide explicitly** (open question OQ-1).

### SV-R4 — Enqueue-all instead of sequential loop (iOS)
On iOS, replace the per-component `for … await` loop with a single enqueue of all
components/files, and derive overall progress from SwiftAcervo's durable per-file
ledger (SwiftAcervo R3), not `(index + fraction)/total`. macOS keeps the loop.

### SV-R5 — Relaunch-survivable progress via availability
`availability(model:)` remains the post-relaunch source of truth. Extend
`.downloading(progress:)` so its progress can be re-derived from SwiftAcervo's
**durable** ledger (SwiftAcervo R3), not the in-memory registry, so the app shows
real progress after a cold launch. `.partial(missing:)` must reflect
files-still-queued vs files-verified.

### SV-R6 — Engine protocol extension
Extend `ImageGenerationEngine` with an additive background-capable method (or a
strategy object) so PixArt and FLUX.2 engines can enqueue via SwiftAcervo's
background API on iOS while keeping the existing `download(_:progress:)` for
foreground/macOS. Both concrete engines (`PixArtEngine`, `Flux2Engine`) implement
it; the understanding-path ViT weights (`ImageClassifier.swift:159`,
`FeatureExtractor.swift`) can remain foreground (small, on-demand) — confirm.

### SV-R7 — Telemetry across process boundaries
The Acervo telemetry reporter (`AcervoManager.shared.currentTelemetry`, read at
`PixArtEngine.swift:528` / `Flux2Engine.swift:474`) must continue to receive
events for background/out-of-process transfers, including those completing in a
relaunch. Confirm the reporter is reconstructable post-relaunch or that events
are buffered.

### SV-R8 — Platform conditioning / no macOS regression
All SV-R1…R7 iOS behavior is `#if os(iOS)` or strategy-injected. macOS/CLI
download path is byte-for-byte unchanged and continues to pass existing tests.

## 6. Cross-repo contract (SwiftAcervo ↔ SwiftVinetas)

**Important correction to the SwiftAcervo spec's entry points:** SwiftVinetas does
**not** call `Acervo.download(...)` / `AcervoManager.download(...)`. It calls:
- `Acervo.ensureComponentReady(_:progress:telemetry:)`
  (`SwiftAcervo/Sources/SwiftAcervo/Acervo+ComponentDownloads.swift:140`) — PixArt.
- `Acervo.ensureAvailable(_:files:progress:)` — FLUX.2.

Therefore SwiftAcervo's background behavior (SwiftAcervo R1–R11) **must be reachable
through `ensureComponentReady` / `ensureAvailable`**, not only through the
lower-level `download` functions. The SwiftAcervo spec should note these as the
real downstream entry points (see §8 follow-up).

SwiftAcervo must additionally expose, for SwiftVinetas to consume:
- A background **enqueue** call accepting a set of components/repos+files (SV-R1/R4).
- An **observation** API (AsyncStream/callback/notification) for per-repo and
  aggregate completion/progress that survives relaunch (SV-R2/R5).
- A durable **per-file/per-component state** query for availability re-derivation
  (SV-R5), backed by the SwiftAcervo R3 ledger.

## 7. API / compatibility & versioning

- **No breaking change** to `download(model:progress:)`, `VinetasDownloadProgress`,
  `DownloadProgress`, or the availability API. New iOS surface (SV-R1/R2/R6) is
  **additive**.
- Downstream call sites that stay source-compatible (Vinetas app): iOS
  `CellularDownloadGate.swift:141,162`, `OnboardingViewModel.swift:64`,
  `GenerationViewModel.swift:402`, `AcervoBindings.swift:44`, onboarding views.
  These migrate to SV-R1/R2 on iOS at the app's pace; until then they keep
  compiling against the foreground API.
- Semver: additive API + new platform behavior → **minor** bump (0.17.0),
  paired with the SwiftAcervo minor (0.24.0).

## 8. Testing requirements

- Unit: strategy selection — iOS enqueues via background API, macOS uses the
  existing sequential loop.
- Unit: progress aggregation from a durable ledger (SV-R4/R5) — reordered and
  partial completion produce monotonic overall progress.
- Unit: availability re-derivation (SV-R5) — `.downloading/.partial/.available`
  computed from persisted state after a simulated cold launch.
- Integration (macOS, CI-runnable): existing foreground download tests unchanged.
- iOS background transfer isn't fully CI-exercisable (needs the device daemon +
  suspension) — cover the SwiftVinetas seams with unit tests and defer end-to-end
  to a device/manual checklist. **Do not** add an iOS integration test that can't
  run reliably in CI.

## 9. Open questions

- **OQ-1 (blocking):** On iOS, does `download(model:progress:)` bridge-and-resolve
  when foregrounded, or become best-effort with SV-R2 authoritative? Determines
  whether app call sites must change immediately or can migrate gradually.
- **OQ-2:** Event type shape for SV-R2 — reuse `VinetasDownloadProgress` in an
  `AsyncStream`, or a richer `VinetasDownloadEvent` enum (`.progress/.completed/
  .failed(repoId,error)`)? Prefer the enum for background failure attribution.
- **OQ-3:** Should the understanding-path ViT download (SV-R6) also go background,
  or stay foreground (it's small and on-demand)? Default: stay foreground.
- **OQ-4:** Cancellation semantics for an enqueued background download (map to
  SwiftAcervo resume-data cancel vs full cancel).

## 10. Out of scope

- Transport/`URLSession` mechanics (owned by `SwiftAcervo/REQUIREMENTS.md`).
- App `UIApplicationDelegate` `handleEventsForBackgroundURLSession` wiring (Vinetas).
- Any macOS/CLI behavior change.
- Generation/inference code paths.

## 11. Implementation sequencing (whole-effort view)

1. **SwiftAcervo** — background transport + durable ledger + observation API,
   reachable via `ensureComponentReady`/`ensureAvailable` (SwiftAcervo spec).
2. **SwiftVinetas** — this spec: enqueue API, observation channel, availability
   re-derivation, engine-protocol extension. Depends on (1).
3. **Vinetas app** — `UIApplicationDelegate` hook, migrate iOS call sites
   (`CellularDownloadGate`, onboarding, `GenerationViewModel`) to the enqueue +
   observe model; reconcile UI on relaunch (Vinetas #134).

Bottom-up: (1) → (2) → (3). Nothing in (2) can be validated end-to-end until (1)
lands, but the SwiftVinetas seams (strategy, aggregation, availability) are
unit-testable against a mock ledger before then.

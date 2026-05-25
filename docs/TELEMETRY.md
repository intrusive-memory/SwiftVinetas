# Telemetry — `--telemetry` and the JSONL trace

SwiftVinetas can record every cross-library handoff during a CLI run as a JSON-Lines (JSONL) trace. One line per event, one event per library boundary. The trace is the canonical way to answer "what did SwiftVinetas actually do, and how long did each step take?" — including model downloads, weight loads, per-step denoise, and now the SwiftAcervo 0.17 in-flight download registry.

This document covers:

- How to enable a trace and where it lands
- The shape of every line (envelope + payload)
- The five `kind` discriminants and what they cover
- The SwiftAcervo 0.17 in-flight download instrumentation in detail — the headline addition this release surfaces
- How to read a trace (recipes with `jq`)
- Programmatic use from a host app (`CLITelemetryBootstrap`)

## Enabling a trace

Pass `--telemetry` to any `vinetas` subcommand:

```sh
vinetas generate "a cyberpunk diner at dusk" --telemetry
vinetas preview  "neon hallway" --telemetry
vinetas classify ./photo.jpg --telemetry
vinetas features ./photo.jpg --telemetry
```

The trace file path is printed to stderr when the subcommand exits:

```
[vinetas] Telemetry trace: /Users/<you>/Library/Caches/vinetas/telemetry/2026-05-25T18-30-12.jsonl
```

The default directory is `~/Library/Caches/vinetas/telemetry/`. One file per run, named by ISO-8601 timestamp.

## Line shape

Every line is a JSON object with three keys:

```json
{
  "timestamp": "2026-05-25T18:30:12.453Z",
  "kind": "acervo",
  "payload": { "case": "inFlightDownloadRegistered", ... }
}
```

- `timestamp` — ISO-8601 with millisecond precision, set when the sink writes the line (not when the event was emitted, but the gap is sub-millisecond in practice).
- `kind` — which library emitted the event. One of `vinetas`, `flux2`, `pixart`, `tuberia`, `acervo`.
- `payload` — the event itself. Always has a `"case"` discriminant string naming the enum case. The remaining keys are the case's associated values.

The five host libraries each define their own `*TelemetryEvent` enum upstream; SwiftVinetas ships an `*EventCodable` wrapper per library that flattens each case into JSON. See `Sources/VinetasCLICore/Telemetry/*EventEncoding.swift` for the per-library mappings.

## What each `kind` covers

| `kind` | Source library | Coverage |
|---|---|---|
| `vinetas` | SwiftVinetas itself | Engine routing, memory verdict, model lifecycle, concurrency gate, `modelAvailabilityChecked`, classifier/feature-extraction lifecycle |
| `flux2` | flux-2-swift-mlx (3.2.2+) | Flux2 pipeline lifecycle, weight load, quantization, text encode, scheduler, per-step `denoiseStart`/`denoiseComplete`, VAE decode |
| `pixart` | pixart-swift-mlx (0.7.2+) | PixArt DiT weight load, recipe validation, per-forward `backboneForwardComplete`, numerical anomalies |
| `tuberia` | SwiftTuberia (0.7.1+) | Pipeline assembly, weight load, encoder/scheduler/backbone/decoder boundary stats, per-step latent stats |
| `acervo` | SwiftAcervo (0.17+) | Model and component cache events (see next section) |

Which `kind`s actually appear in a trace depends on which engine the request routes through:

- **Flux2 path** (`vinetas generate --model klein4b` / `klein9b`, `vinetas preview`) — emits `vinetas` + `flux2`. Flux2 reaches Acervo through a static seam without a reporter, so `acervo` events do **not** appear on Flux2 runs.
- **PixArt path** (`vinetas generate --model pixart-sigma-xl`) — emits all five `kind`s.
- **Image-understanding** (`vinetas classify`, `vinetas features`, `vinetas similarity`) — emits `vinetas` + `acervo` (the latter only on the first run, when the ViT-B/16 or DINOv2-B/14 backbone is downloaded).

## SwiftAcervo download instrumentation (the 0.17 surface)

SwiftAcervo 0.17 added a matched pair of events that tie a component download to the in-flight registry that drives `Acervo.availability(repoId)`. SwiftVinetas threads its `AcervoTelemetryCLIAdapter` through every `Acervo.ensureComponentReady(...)` call site so these events reach your trace:

| Event (`payload.case`) | Fires when |
|---|---|
| `inFlightDownloadRegistered` | Once per `ensureComponentReady` call that actually performs a download (cache miss). The `role` field is `originator` if this caller registered the underlying Task, or `joiner` if it joined an in-flight Task started by a concurrent caller. |
| `inFlightDownloadCleared` | Once per underlying download Task, fired from the originator's `defer` block. `outcome` is `success` (download returned without throwing) or `failure` (download threw — see the matching `errorThrown` event for the phase). |

Both events carry:

- `modelID` — the HuggingFace `org/repo` string (`"black-forest-labs/FLUX.2-klein-4B"`, `"mlx-vision/vit_base_patch14_518.dinov2-mlxim"`, etc.)
- `componentID` — the SwiftAcervo component descriptor ID (`"transformer-int4"`, `"vit-base-patch16-224-imagenet1k"`, etc.). Optional; absent on the rare path where the registry is keyed by `repoID` alone.

**Cache hits do NOT emit these events.** When `ensureComponentReady` short-circuits because the component is already on disk, you see `componentResolveStart` and `componentResolveComplete(cacheState: "alreadyReady")` only — no `Registered`/`Cleared` pair. That asymmetry is intentional: the in-flight registry is the source of truth for the `.downloading(progress:)` arm of `Acervo.availability(_:)`, and there is nothing to register on a cache hit.

**Concurrent downloads converge.** Two `ensureComponentReady` calls for the same `repoID` (whether for the same component or two components that share a repo) deduplicate onto a single Task. The originator fires `Registered(role: "originator")`; each joiner fires `Registered(role: "joiner")`. Exactly one `Cleared` event closes out the registration window.

### What you can answer with these events

- **"How long did the download take?"** — diff the timestamps of the matched `inFlightDownloadRegistered(role: "originator")` and `inFlightDownloadCleared` events for the same `(modelID, componentID)`. The `componentResolveComplete.durationSeconds` field gives the same number for the originator only.
- **"Did the UI see `.downloading(progress:)` during the download?"** — if `Registered` is present and `Cleared` is absent (process crashed mid-download), or if your UI polling logs say it observed `.partial` instead of `.downloading` during the window between the two events, that's a SwiftAcervo regression — file it against `intrusive-memory/SwiftAcervo`.
- **"How many concurrent callers piled onto the same download?"** — count the `Registered` events between a matched `originator` and `Cleared`. One `originator` + N `joiner` lines means N+1 concurrent callers.
- **"Did the download fail?"** — search for `Cleared(outcome: "failure")` and then look back for the matching `errorThrown` event with `phase = "fileDownload"` / `"fileDownloadIntegrity"` / `"manifestDownload"` etc. for the actual error.

## Reading a trace

Every event is one line of JSON, so the standard `jq` recipes work. Some specific ones:

Count events per kind:

```sh
jq -r '.kind' trace.jsonl | sort | uniq -c | sort -rn
```

Show only the in-flight download lifecycle, in order:

```sh
jq -c 'select(.kind=="acervo") | select(.payload.case == "inFlightDownloadRegistered" or .payload.case == "inFlightDownloadCleared") | {ts: .timestamp, case: .payload.case, role: .payload.role, outcome: .payload.outcome, model: .payload.modelID, comp: .payload.componentID}' trace.jsonl
```

Compute download wall-clock for each `(modelID, componentID)`:

```sh
jq -r '
  select(.kind=="acervo") |
  select(.payload.case == "inFlightDownloadRegistered" and .payload.role == "originator") as $r |
  $r | "\(.payload.modelID)|\(.payload.componentID // "-")|registered|\(.timestamp)"
' trace.jsonl
jq -r '
  select(.kind=="acervo") |
  select(.payload.case == "inFlightDownloadCleared") |
  "\(.payload.modelID)|\(.payload.componentID // "-")|cleared|\(.timestamp)|\(.payload.outcome)"
' trace.jsonl
```

(Stitch the two streams together in your shell/script of choice — `jq` doesn't do windowed joins natively.)

Find all error events with their phase:

```sh
jq -c 'select(.payload.case == "errorThrown") | {kind, phase: .payload.phase, msg: .payload.errorDescription}' trace.jsonl
```

## From a host app (programmatic use)

If your app embeds SwiftVinetas's CLI core (`VinetasCLICore`), you can install the same bootstrap directly:

```swift
import VinetasCLICore

// Full mode: install all five adapters (Vinetas + Acervo + Flux2 + PixArt + Tuberia).
// Use for diffusion-producing flows (generate, preview).
let bootstrap = try await CLITelemetryBootstrap.enable(
    traceURL: URL(fileURLWithPath: "/tmp/my-app-trace.jsonl"),
    mode: .full
)

defer { Task { await bootstrap.finish() } }

// Run your generation. All emitted events stream to the JSONL file.
let image = try await VinetasClient.shared.generate(
    prompt: "a cyberpunk diner at dusk",
    model: VinetasClient.pixartSigmaXL
)
```

For image-understanding flows (no diffusion), use `mode: .partial` — the Vinetas and Acervo adapters are installed but the diffusion-only adapters (Flux2/PixArt/Tuberia) are skipped:

```swift
let bootstrap = try await CLITelemetryBootstrap.enable(
    traceURL: URL(fileURLWithPath: "/tmp/my-app-trace.jsonl"),
    mode: .partial
)
defer { Task { await bootstrap.finish() } }

let classifications = try await Vinetas.classify(file: imageURL, topK: 5)
```

`finish()` is idempotent and safe to call from a `defer { Task { ... } }` block — the per-line flush in the sink means at most one truncated trailing line if the process exits before the Task runs.

## Related references

- `docs/INSTRUMENTATION_PATTERN.md` — the dual-seam telemetry pattern shared across SwiftVinetas, SwiftAcervo, Flux2Core, PixArtBackbone, and SwiftTuberia.
- `Sources/VinetasCLICore/Telemetry/AcervoEventEncoding.swift` — the JSON shape for every `kind: "acervo"` payload, including the 0.17 in-flight pair.
- `Sources/VinetasCLICore/Telemetry/CLITelemetryBootstrap.swift` — where the per-library adapters get installed on `AcervoManager.shared`, `Flux2Telemetry`, `PixArtTelemetry`, `TuberiaTelemetry`, and `VinetasClient.shared`.
- Upstream `SwiftAcervo/Docs/UPGRADING-library.md` — the SwiftAcervo 0.17 release notes that motivated the new in-flight events.

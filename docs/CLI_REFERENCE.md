---
type: doc
updated: 2026-09-26
---

# `vinetas` CLI Reference

Full command reference for the `vinetas` CLI (`Sources/vinetas`, logic in
`Sources/VinetasCLICore`). Every subcommand also answers `--help`; this
document adds the cross-cutting behavior (reference images, streaming,
embedded metadata, sandboxing) that doesn't fit in a single `--help` block.

Build from source with `make build` (see [AGENTS.md](../AGENTS.md)); the
signed/notarized app-bundled CLI ships the same command surface.

## Model storage environment variables

`vinetas --help` interpolates `Acervo.environmentHelp()` (SwiftAcervo), so the
authoritative text always lives there. Summary:

| Variable | Purpose |
|---|---|
| `ACERVO_APP_GROUP_ID` | App Group identifier that locates the shared models directory (`~/Library/Group Containers/<id>/SharedModels`). Required for CLIs/scripts/test runners, which have no entitlement to read it otherwise. |
| `ACERVO_MODELS_DIR` | Absolute path that replaces the shared models directory outright; takes precedence over `ACERVO_APP_GROUP_ID`. Escape hatch for unentitled processes. Not for production. |
| `ACERVO_CDN_BASE_URL` | Base URL every model download/manifest fetch is built from. |
| `ACERVO_OFFLINE` | Set to `1` to forbid all network access; only already-cached models resolve. |

## `vinetas generate`

Generate a single panel from a text prompt.

```
USAGE: vinetas generate [<options>] <prompt>

ARGUMENTS:
  <prompt>                Text description of the panel to generate.

OPTIONS:
  -s, --style <style>     Style prompt for consistent look (e.g., 'noir comic').
  -o, --output <output>   Output PNG path, or - to write the PNG (with embedded
                          metadata, no sidecar) to stdout. (default: panel.png)
  --model <model>         Model variant: klein4b (default) or pixart-sigma.
                          (default: klein4b)
  --lora <lora>           Path to a LoRA safetensors file.
  --lora-scale <lora-scale>
                          LoRA scale (0.0-1.0). (default: 0.8)
  --seed <seed>           Random seed for reproducibility.
  --steps <steps>         Number of inference steps.
  --guidance <guidance>   Classifier-free guidance scale.
  --width <width>         Output image width in pixels. Overrides --aspect width.
  --height <height>       Output image height in pixels. Overrides --aspect height.
  --aspect <aspect>       Aspect ratio preset: square, wide, ultrawide, portrait, panel, strip.
  --negative <negative>   Negative prompt to steer away from unwanted characteristics.
  --preview               Fast preview mode (4 steps, 512x512, Klein 4B).
  -r, --reference <reference>
                          Reference (conditioning) image path, or - to read one
                          from stdin. Repeatable, 1-3.
  --telemetry             Write a JSONL trace of every library handoff (see docs/TELEMETRY.md).
```

`generate` is the default subcommand: `vinetas "a detective in a rain-soaked alley"` is equivalent to `vinetas generate "a detective in a rain-soaked alley"`.

### Reference images (`-r`/`--reference`)

FLUX.2 Klein 4B accepts up to 3 reference (conditioning) images for
image-to-image generation. PixArt-Sigma does not support references — passing
any `-r` with `--model pixart-sigma` fails before any download or model load.

```bash
# Order is priority: the first reference is weighted highest.
vinetas generate "Vale in the rain" -r vale-front.png -r vale-side.jpg -o panel.png

# A single reference can be read from stdin instead of a file.
cat vale-front.png | vinetas generate "Vale in the rain" -r - -o panel.png
```

- Repeatable 1–3 times; more than 3 (or more than the active model's max)
  fails validation before any download or model load.
- Accepted formats: PNG, JPEG, HEIC (anything `CGImageSourceCreateWithData`
  decodes).
- A reference larger than the model's native conditioning size is downscaled
  automatically. When that happens, `generate` prints one line per affected
  reference to stderr:
  `note: reference <n> (<source>) downscaled <w>×<h> → <w'>×<h'>`
- Only one `-r -` (stdin) reference is allowed per invocation — a second `-r -`
  is a validation error.
- A missing file, an empty file, or bytes that don't decode as an image each
  fail with a message naming the path (or `stdin`), before any model load.

### Streaming output (`-o -`)

```bash
vinetas generate "A detective in a rain-soaked alley" -o - > panel.png
```

- Writes a byte-pure PNG to stdout: the stream starts with the PNG signature
  and ends exactly at the `IEND` chunk's CRC. Every log line, warning, and
  telemetry note — from `vinetas` itself and from every library it calls —
  goes to stderr instead, so the stdout stream is always safe to pipe
  directly into another tool or decode with `CGImageSourceCreateWithData`.
- No `.json` sidecar is written for `-o -`.
- `-o <path>` (the default) writes both the PNG **and** a `<path>.json`
  sidecar with the same metadata, byte-identical to what's embedded in the
  PNG.

### Embedded metadata

Every generated PNG — streamed or written to a path — carries its generation
metadata in a `vinetas` `iTXt` chunk (uncompressed, empty language/translated
keyword, JSON payload with `.sortedKeys`):

- `prompt`, `composedPrompt`, `style`
- `model`, `engine`, `mode` (`textToImage` / `imageToImage`)
- actual `seed` (not the CLI's `--seed` echoed back — the value the engine
  actually used), `steps`, `guidance`, output `width`/`height`
- `negative` and `negativeApplied` (see below)
- `loras`: LoRA(s) actually applied (path + scale), recorded only after a
  successful load
- `references`: one record per reference image (`source`, `sha256`,
  `originalWidth`/`Height`, `effectiveWidth`/`Height`)
- `durationSeconds`, `generatedAt`

Path outputs additionally get a `.json` sidecar with byte-identical contents,
for tooling that would rather not parse PNG chunks.

### `--negative` on engines that don't apply it

FLUX.2 (Klein 4B) does not apply negative prompts. Passing `--negative`
with a FLUX.2 model still runs — it does not fail — but:

- prints `warning: <engine> does not apply negative prompts; --negative ignored` to stderr
- records `negativeApplied: false` in the embedded/sidecar metadata (with
  `negative` still recorded as given, so the record shows what was requested
  vs. what happened)

PixArt-Sigma applies `--negative` normally, with no warning and
`negativeApplied: true`.

## `vinetas batch`

Generate a sequence of panels from a YAML prompts file.

```
USAGE: vinetas batch <prompts-file> [--output-dir <output-dir>] [--model <model>] [--aspect <aspect>] [--preview] [--telemetry]
```

Each panel in the file is generated via the same client path as `generate`
and written with `writePanel` (PNG + sidecar), so per-panel metadata reflects
the actual steps/guidance/seed used for that panel, not the file's defaults.
See the [YAML Prompt File Format](../README.md#yaml-prompt-file-format) in
the README.

## `vinetas storyboard`

Generate storyboard panels from a screenplay's GLOSA `<shot>` directives.

```
USAGE: vinetas storyboard <screenplay> [--output-dir <output-dir>] [--model <model>] [--dry-run] [--continue-on-error] [--telemetry]
```

Accepts `.fountain`, `.highland`, `.fdx`. `--dry-run` resolves and prints the
storyboard's prompts without generating. See
[docs/REQUIREMENTS-STORYBOARD-COMMAND.md](REQUIREMENTS-STORYBOARD-COMMAND.md).

## `vinetas download` / `vinetas list`

```
USAGE: vinetas download [--model <model>]
USAGE: vinetas list [--json]
```

`download` fetches a model's weights ahead of time; `generate`/`batch`/etc.
download on first use otherwise. `list` shows every known model's cache
status (`--json` for machine-readable output).

## `vinetas info`

Display detailed information about a model variant, or print the CLI's
staging directory.

```
USAGE: vinetas info [--model <model>]
USAGE: vinetas info --print-io-dir
```

`--model` (default `klein4b`) prints the model's HuggingFace repo,
quantization, minimum memory, and cache status.

### `vinetas info --print-io-dir`

```bash
vinetas info --print-io-dir
# /Users/you/Library/Group Containers/group.intrusive-memory.models/vinetas-io
```

Resolves `<App Group container>/vinetas-io/` — a sibling of Acervo's
`SharedModels` cache inside the same container, **not** the models
subdirectory — creates it if missing, prints only that absolute path to
stdout, and exits 0. The rest of `info`'s output is skipped when this flag is
passed.

**Sandbox note**: the signed, notarized `vinetas` CLI carries no
Downloads-folder entitlement, so it cannot read a file a user drops in their
downloads folder or write a panel there directly. Use `-r -` / `-o -` streams
for pipelines, or stage files through this directory for anything that needs
a real path on disk.

## `vinetas preview`

Fast, low-quality preview: always Klein 4B, 4 steps, 512×512.

```
USAGE: vinetas preview <prompt> [--output <output>] [--telemetry]
```

`--preview` on `generate` is the same fast path, but composable with the
rest of `generate`'s options (seed, guidance, style, negative, LoRA,
references) — `preview` the subcommand is the minimal, argument-free version.

## `vinetas character`

Manage characters for consistent actor rendering across panels.

```
USAGE: vinetas character <subcommand>

SUBCOMMANDS:
  create      Create a new character with optional source photo.
  list        List all characters.
  info        Display detailed information about a character.
  delete      Delete a character and all its data.
  reference   Generate pencil-sketch reference sheets from a character's source photo.
  prepare     Prepare training data from reference sheets.
  train       Train a LoRA adapter for a character.
  verify      Verify character consistency via DINOv2 similarity scoring.
```

| Subcommand | Usage |
|---|---|
| `create` | `vinetas character create <name> [--photo <photo>] [--description <description>]` |
| `list` | `vinetas character list` |
| `info` | `vinetas character info <slug>` |
| `delete` | `vinetas character delete <slug> [--force]` |
| `reference` | `vinetas character reference <slug> [--views <views>] [--strength <strength>] [--model <model>]` |
| `prepare` | `vinetas character prepare <slug> [--include-source]` |
| `train` | `vinetas character train <slug> [--steps <steps>] [--rank <rank>] [--model <model>]` |
| `verify` | `vinetas character verify <slug> [--threshold <threshold>]` |

### `character reference` hardening

- `--model` is validated eagerly: an unknown value (anything other than
  `klein4b`) is a `ValidationError` naming the valid choice,
  instead of silently falling back to `klein4b`. `--model pixart-sigma` is
  rejected specifically — PixArt has no reference-image support — **before**
  any download or model load.
- `--strength` is **deprecated**: FLUX.2 reference conditioning has no
  strength control. Passing it explicitly prints
  `warning: --strength has no effect and will be removed in the next minor release`
  to stderr; the library call it forwards to ignores the value. Omitting
  `--strength` prints no warning.

## `vinetas classify` / `vinetas features` / `vinetas similarity`

Image-understanding subcommands (ViT-B/16 classification, DINOv2-B/14
feature extraction and cosine similarity):

```
USAGE: vinetas classify <image-path> [--top-k <top-k>] [--telemetry]
USAGE: vinetas features <image-path> [--telemetry]
USAGE: vinetas similarity <image1-path> <image2-path> [--telemetry]
```

These do not generate panels and do not accept `-r`/`--reference`; they read
one or two image files directly.

## Telemetry

Every subcommand accepts `--telemetry`, writing a JSONL trace to
`~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl` (path printed to
stderr on completion). See [docs/TELEMETRY.md](TELEMETRY.md) for the full
event catalogue and which libraries emit on which command.

## See also

- [README.md § Reference images and streams](../README.md#reference-images-and-streams)
- [docs/REQUIREMENTS-REFERENCE-IMAGES.md](REQUIREMENTS-REFERENCE-IMAGES.md) — the requirements this CLI surface implements
- [docs/TELEMETRY.md](TELEMETRY.md)
- [docs/REQUIREMENTS-STORYBOARD-COMMAND.md](REQUIREMENTS-STORYBOARD-COMMAND.md)

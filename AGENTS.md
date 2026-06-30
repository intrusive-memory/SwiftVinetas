---
type: doc
updated: 2026-06-29
---

# SwiftVinetas - AI Agent Instructions

**Version**: 0.16.0-dev
**Purpose**: Guide AI agents working on SwiftVinetas
**Audience**: Claude Code, Gemini, and other AI development assistants

## Product Overview

**SwiftVinetas** — On-device storyboard and comic panel generation from text prompts using FLUX.2 Klein models via MLX on Apple Silicon.

**Platforms**: macOS 26.0+ (Apple Silicon), iOS 26.0+.

## Architecture

- **Library**: `SwiftVinetas` wraps `Flux2Core` (from flux-2-swift-mlx) via an engine abstraction layer
- **Engine Layer**: `ImageGenerationEngine` protocol + `EngineRouter` dispatcher — supports multiple backends
- **Engines**: `Flux2Engine` (wraps Flux2Core), `PixArtEngine` (wraps PixArtBackbone via SwiftTubería pipeline)
- **Public API**: `VinetasClient` (instance-based, `.shared` singleton) — replaces deprecated static `Vinetas` enum
- **CLI**: `vinetas` for testing and standalone use
- **Models**: FLUX.2 Klein 4B (fast, default) and Klein 9B (quality), extensible via `ModelDescriptor` protocol
- **Style**: LoRA adapters in safetensors format, tagged with `compatibleEngines: [String]`
- **Prompt files**: YAML parsed via `marcprux/universal`
- **Model cache**: App Group container (`group.intrusive-memory.models`) via SwiftAcervo, with Application Support fallback — sandbox-safe on all platforms

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full design decisions.
See [docs/V1_REQUIREMENTS.md](docs/V1_REQUIREMENTS.md) for prioritized library requirements.
See [docs/GUI_REQUIREMENTS.md](docs/GUI_REQUIREMENTS.md) for GUI/host-app requirements.
See [docs/ENGINE_ABSTRACTION_REQUIREMENTS.md](docs/ENGINE_ABSTRACTION_REQUIREMENTS.md) for the engine plugin contract.
See [docs/LEARNING.md](docs/LEARNING.md) for research findings.
Active investigations / in-flight design notes live in [docs/incomplete/](docs/incomplete/); shipped/landed plans get archived to [docs/complete/](docs/complete/).

## Queryable Codemap

A prebuilt [graphify](https://pypi.org/project/graphifyy/) knowledge graph of this
codebase lives in [`graphify-out/`](graphify-out/) (2536 nodes · 4017 edges). **Prefer
querying it before grepping** for architecture or "what connects to what" questions:

```bash
graphify query "How does X flow through the system?"
graphify path "TypeA" "TypeB"      # shortest path between two nodes
graphify explain "SomeType"        # plain-language node explanation
```

Human-readable summary: [`graphify-out/GRAPH_REPORT.md`](graphify-out/GRAPH_REPORT.md).
Refresh after significant changes with `/codemap` (or `graphify . --update`).

## Build System

**CRITICAL**: Always use `xcodebuild` or Makefile targets. NEVER use `swift build` or `swift test` — Metal shaders required by MLX won't compile.

```bash
# Using Makefile (preferred) — `make help` lists every target
make build               # Debug build + copy to ./bin/vinetas
make test                # All macOS tests (unit + GPU)
make test-unit           # macOS unit tests only (no GPU) — CI-safe
make test-gpu            # GPU tests only (requires Apple Silicon + cached models) — local only
make test-integration    # Integration tests: model download + image generation — local only
make test-fixtures       # Generate seed-42 reference fixtures for both engines (PNGs + JSON) — local only
make test-fixtures-fp16  # Generate fp16 DiT fixture for int4-vs-fp16 PixArt comparison — local only
make test-pixart-repro   # Run PixArt 5× across seeds 42–46 for garbage-output diagnosis — local only
make test-ios            # All iOS Simulator tests
make test-unit-ios       # iOS unit tests only (no GPU)
make build-ios           # Build library for iOS Simulator
make release             # Release build
make install             # Release build + copy to ./bin/vinetas
make lint                # Format Swift sources via swift-format

# NOTE: test-gpu, test-integration, test-fixtures*, and test-pixart-repro are LOCAL-ONLY.
# They require Apple Silicon hardware and pre-downloaded model weights.
# CI (GitHub Actions) only runs `make test-unit` and `make test-unit-ios`.
# The GPU-test Makefile targets depend on `link-test-models`, which hardlinks model
# weights from the App Group container into /tmp so the xctest process can open them
# (the Makefile passes them through as TEST_RUNNER_VINETAS_TEST_MODELS_DIR).

# Using xcodebuild directly
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS,arch=arm64'
xcodebuild build -scheme SwiftVinetas -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
```

## Key Types

```swift
// Primary API (v0.5.0+, updated v0.8.2) — instance-based
let client = VinetasClient.shared
client.generate(prompt:style:model:)               // Single panel (routes through EngineRouter)
client.generateSequence(prompts:referenceImages:style:model:progress:)  // Multi-panel
client.generate(prompt:character:style:model:)     // Character-aware (LoRA compatibility check)
client.preview(prompt:)                            // FLUX.2-only fast path (Klein 4B, 4 steps, 512x512)

// Engine Abstraction
ImageGenerationEngine  // Protocol: generate, loadModel, loadLoRA, download, validateMemory
EngineRouter           // Actor: dispatches to registered engines by model's engineID
Flux2Engine            // Actor: wraps Flux2Pipeline, engineID "flux2"
PixArtEngine           // Actor: wraps DiffusionPipeline via PixArtBackbone, engineID "pixart-sigma"
ModelDescriptor        // Protocol: id, displayName, engineID, minimumMemoryGB, etc.
Flux2ModelDescriptor   // .klein4B ("flux2-klein-4b"), .klein9B ("flux2-klein-9b")
PixArtModelDescriptor  // .sigmaXL ("pixart-sigma-xl"), 8 GB minimum, Apache 2.0

// Deprecated API (still functional, forwards to VinetasClient.shared)
Vinetas                // @available(*, deprecated) — static enum, use VinetasClient instead
VinetasModel           // @available(*, deprecated) — use ModelDescriptor types directly

// Configuration & Output
StyleConfig         // steps, guidance, seed, dimensions, style/negative prompts
PanelOutput         // CGImage + metadata (prompt, seed, duration, modelID: String)
VinetasError        // modelNotFound, insufficientMemory, generationFailed, engineNotFound, etc.
GenerationRequest   // mode (.textToImage / .imageToImage), prompt, steps, guidance
GenerationResult    // image, seed, duration
```

## Dependencies

Pinned floors (see [Package.swift](Package.swift) for the source of truth):

| Package | Import | Min version | Purpose |
|---------|--------|-------------|---------|
| flux-2-swift-mlx | `Flux2Core`, `FluxTextEncoders` | 3.0.0 | FLUX.2 pipeline (MIT) |
| SwiftTubería | `Tuberia`, `TuberiaCatalog` | 0.6.0 | Componentized diffusion pipeline protocols |
| pixart-swift-mlx | `PixArtBackbone` | 0.5.0 | PixArt-Sigma DiT model plugin |
| SwiftAcervo | `SwiftAcervo` | 0.17.0 | Model download/cache; 0.17 in-flight download registry |
| Universal | `YAML`, `JSON` | 5.3.0 | Prompt file parsing |
| swift-argument-parser | `ArgumentParser` | 1.7.1 | CLI (vinetas target only) |

**Local sibling overrides**: `Package.swift` automatically prefers `../<package-name>` sibling checkouts when present and `CI != "true"`, falling back to the pinned remote otherwise. Lets in-flight upstream changes be exercised end-to-end without cutting a release. CI always uses the pinned remotes.

**Rejected**: `mzbac/flux.swift` — GPL-3.0 license incompatible with Produciesta.

## Underlying Flux2Core API

The library wraps `Flux2Pipeline`. Key patterns:

```swift
let pipeline = try await Flux2Pipeline(model: .klein4b, quantization: .balanced)
try await pipeline.loadModels(progressCallback: { progress in ... })

// Text-to-image
let result = try await pipeline.generateTextToImageWithResult(prompt: "...", height: 1024, width: 1024)

// Image-to-image with references (up to 3)
let result = try await pipeline.generateImageToImageWithResult(prompt: "...", images: [refImage], strength: 0.7)

// LoRA
pipeline.loadLoRA(LoRAConfig(filePath: "style.safetensors", scale: 0.8))
pipeline.unloadAllLoRAs()
```

## Package Structure

```
SwiftVinetas/
├── Sources/
│   ├── SwiftVinetas/           # Library
│   │   ├── Vinetas.swift       # VinetasClient (primary API) + deprecated Vinetas enum
│   │   ├── Core/               # StyleConfig, VinetasError, PanelOutput, Pipeline, Memory
│   │   ├── Engine/             # Engine abstraction layer (v0.5.0+)
│   │   │   ├── ImageGenerationEngine.swift  # Protocol
│   │   │   ├── ModelDescriptor.swift        # Protocol + ModelLicense
│   │   │   ├── EngineTypes.swift            # GenerationRequest, GenerationResult, etc.
│   │   │   ├── EngineRouter.swift           # Actor dispatcher
│   │   │   ├── Flux2Engine.swift            # FLUX.2 conformance
│   │   │   └── PixArtEngine.swift           # PixArt-Sigma conformance
│   │   ├── Character/          # Character pipeline, LoRA training
│   │   └── Understanding/      # ViT-B/16, DINOv2, image preprocessing
│   ├── VinetasCLICore/         # Testable CLI logic library (v0.9.0+)
│   │   └── VinetasCLICore.swift
│   └── vinetas/                # CLI executable (thin wrapper over VinetasCLICore)
│       └── VinetasCLI.swift
├── Tests/
│   ├── SwiftVinetasTests/                   # Unit tests (CI-safe, no GPU)
│   │   ├── VinetasClientTests.swift         # VinetasClient routing and validation
│   │   ├── VinetasErrorTests.swift          # Parameterized error type tests
│   │   ├── EngineRouterTests.swift          # EngineRouter dispatch
│   │   ├── Flux2EngineTests.swift           # Flux2Engine unit-level behavior
│   │   ├── PixArtEngineTests.swift          # PixArtEngine unit-level behavior
│   │   ├── CLIArgumentTests.swift           # CLI argument parsing (VinetasCLICore)
│   │   ├── LoRAManagerTests.swift           # LoRA sequencing tests
│   │   ├── LoRACompatibilityTests.swift     # LoRA<->engine compatibility checks
│   │   ├── ConcurrentClientTests.swift      # Actor isolation stress tests
│   │   ├── PlatformRegistrationTests.swift  # Engine/component registration on cold start
│   │   ├── …                                # plus: Aspect/Character/Classification/Prompt/Style/Verification suites
│   │   └── MockEngine.swift                 # Test double for ImageGenerationEngine
│   └── SwiftVinetasGPUTests/                # Local-only GPU + integration tests
│       ├── TestTags.swift                   # Shared tag taxonomy (.integration, .gpu, .flux2, .pixart)
│       ├── IntegrationTestHelpers.swift     # assertImageNotGarbage, assertModelDownloaded
│       ├── Flux2IntegrationTests.swift      # FLUX.2 pipeline: compile, download, generate, determinism
│       ├── PixArtIntegrationTests.swift     # PixArt-Sigma pipeline: compile, download, generate
│       ├── BatchIntegrationTests.swift      # Batch generation integration tests
│       ├── PixArtGarbageReproTests.swift    # PixArt 5×-seed garbage-output diagnostic harness
│       ├── T5DiffuserComparisonDump.swift   # T5 vs diffusers parity dump (research aid)
│       ├── AllModelsExampleTests.swift      # End-to-end smoke across every registered model
│       ├── ImagePreprocessorTests.swift     # GPU-accelerated image preprocessing
│       ├── ImageQualityReport.swift         # Output-quality scoring helpers
│       ├── Fixtures/                        # Reference images / metadata committed to the repo
│       └── SwiftVinetasGPUTests.entitlements
├── docs/
│   ├── ARCHITECTURE.md
│   ├── V1_REQUIREMENTS.md
│   ├── GUI_REQUIREMENTS.md
│   ├── ENGINE_ABSTRACTION_REQUIREMENTS.md
│   ├── LEARNING.md
│   ├── incomplete/                          # Active investigations + in-flight design notes
│   ├── complete/                            # Shipped/landed plans (archived)
│   └── archive/                             # Superseded historical docs
└── .github/workflows/tests.yml
```

## Git Workflow

- Branch: `development` -> PR -> `main`
- Never commit directly to `main`
- CI: Unit tests (macOS + iOS) must pass before merge to main
- Required status checks: "Unit Tests (macOS)", "Unit Tests (iOS Simulator)"

## Platform Constraints

- **macOS 26.0+** — never add `@available` for older versions
- **iOS 26.0+** — supported via MLX on iOS
- **Apple Silicon ONLY** — M-series / A-series chips required (MLX/Metal)

## Memory Constraints

- PixArt-Sigma XL int4: 8 GB minimum (works on all iPads and most Macs)
- Klein 4B int4: 16 GB minimum
- Klein 9B qint8: 24 GB minimum
- Always validate memory before loading models
- VAE must stay at bf16/fp16 (never quantize)

## Critical Rules for AI Agents

1. NEVER use `swift build` or `swift test` — use `xcodebuild` or `make` targets
2. NEVER commit directly to `main` — always PR from `development`
3. NEVER add `@available` for macOS versions older than 26.0 or iOS versions older than 26.0
4. ALWAYS validate memory before loading models
5. ALWAYS read files before editing
6. NEVER create files unless necessary
7. Follow agent-specific instructions — see [CLAUDE.md](CLAUDE.md) or [GEMINI.md](GEMINI.md)

## Recent Changes

### Unreleased (post-v0.10.1, on `development`)

- _No changes yet._

### v0.10.1

- **Release workflow** — added `.github/workflows/release.yml` that builds the canonical tarball with `make dist` on a clean runner, uploads it to the GitHub release, and dispatches `formula-update` to the homebrew-tap repo.
- **Makefile reorganization** — split install/release targets so `make dist` is reproducible in CI without depending on local install state.
- **CI release upload** — `GITHUB_TOKEN` is now passed explicitly to the upload step so release-asset uploads succeed under stricter token-scoping rules.

### v0.10.0

- **FLUX.2 re-enabled** — engine restored after upstream tokenizer-collision fix landed in `flux-2-swift-mlx` 3.0.0 (PR #20).
- **MLX reentrancy guard + memory/clock/seed hardening** in the engine layer to keep concurrent generations deterministic and crash-free.
- **PixArt garbage-image fix** — 7 bugs across 3 repos resolved; PixArt-Sigma now requires native 1024×1024 (other resolutions error early) and includes S7b text-embedding fixes.
- **Local sibling overrides** — `Package.swift` prefers `../<sibling>` checkouts when not in CI; non-CI dev no longer needs released versions of in-flight upstream changes. CI always uses the pinned remotes.
- **Dependency floors raised**: flux-2-swift-mlx → 3.0.1, SwiftAcervo → 0.8.4, SwiftTubería → 0.6.0, pixart-swift-mlx → 0.5.1.
- **New fixture/repro tooling**: `make test-fixtures`, `make test-pixart-repro`; tests `PixArtGarbageReproTests`, `T5DiffuserComparisonDump`, `AllModelsExampleTests`.
- **Configurable fixture prompt** — `make test-fixtures PROMPT="..."` overrides the default red-car prompt without editing source.
- **Makefile fix**: switched env-var pass-through to `TEST_RUNNER_` prefix so `VINETAS_TEST_MODELS_DIR` actually reaches the xctest process.
- Dropped `loadModelThrowsWhenWeightsAbsent` (test rot after weight-loading refactor).
- In-flight design note: [docs/incomplete/FIXTURE_CACHE_WARMER.md](docs/incomplete/FIXTURE_CACHE_WARMER.md) — proposal for a CI fixture-test cache warmer so cold-cache PRs fail loudly instead of silently skipping.

### v0.9.1

- Flux2 MACF (memory-aware compute facility) bypass fix via SwiftTubería 0.3.5 WeightLoader update.
- `Flux2Engine`: removed `diskSize(for:)` call (not present in `flux-2-swift-mlx` v2.6.0).
- CLI bug fixes and a cross-model test suite.

### v0.9.0

- Added `VinetasCLICore` library target — CLI logic extracted from `vinetas` executable into a testable library
- Comprehensive unit test suite: `VinetasClientTests`, `VinetasErrorTests`, `CLIArgumentTests`, `LoRAManagerTests`, `ConcurrentClientTests`
- GPU integration test expansion: fixed-seed determinism (Checkpoint 4), `unloadModel` memory release (Checkpoint 5)
- Actor isolation stress tests for concurrent `VinetasClient` usage
- `generateSequence` callback ordering tests for multi-panel generation
- Added `SwiftVinetasGPUTests.entitlements` for GPU test target entitlements

### v0.8.4

- Fix `isAvailable` always returning false on fresh app launch — `PixArtComponents.registered` now called before checking component IDs
- Bumped SwiftTubería minimum from 0.2.6 to 0.2.7
- Added `lint` Makefile target (`swift format -i -r .`)

### v0.8.3

- Bumped SwiftTubería minimum from 0.2.0 to 0.2.6 to require the fix for the compiled silu op in the SDXL VAE decoder

## SwiftAcervo manifest contract — decisions

### R6.1 — Acervo.deleteFromCDN and Acervo.recache (tooling-only)

They are NOT wired into `VinetasClient` at runtime. The `acervo-cdn-setup` skill covers this workflow. See: docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md § R6.1

### R6.2 / Q2 — migrateFromLegacyPaths() is a consuming-app concern

e.g. Produciesta owns the call, not the Vinetas library. A library shouldn't migrate user data on import. See: docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md § R6.2 and Q2

### Q3 / R5.2 — PixArt component-bridge duplication is intentional

Drift is caught by the WU6 stderr CI gate. Do NOT extract a helper until a third call site appears. See: docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md § R5.2 and Q3

### 0.17 — pass `AcervoManager.shared.currentTelemetry` to `ensureComponentReady`

`Acervo.ensureComponentReady(_:progress:telemetry:)` emits its event stream (including the new `inFlightDownloadRegistered`/`Cleared` pair) only when a reporter is passed via the `telemetry:` parameter — there is no static fallback. Every call site in SwiftVinetas that downloads via this API (`PixArtEngine.download`, `ImageClassifier.loadModel`, `FeatureExtractor.loadModel`) must forward `await AcervoManager.shared.currentTelemetry` so the bootstrap-installed JSONL adapter sees the events. New call sites should follow the same pattern. See [docs/TELEMETRY.md](docs/TELEMETRY.md) for what the surfaced events mean.

# Re-enabling FLUX.2 — Breadcrumbs

**Status**: FLUX.2 is **temporarily disabled** in this package as of 2026-04-30.
**Intent**: Re-enable once the upstream tokenizer collision (below) is resolved.
**Owner**: Whoever next picks up the SwiftTubería integration in `REQUIREMENTS.md`.

---

## Why flux2 is off

The package graph couldn't resolve. Two transitive dependencies declare a Swift Package target literally named `Tokenizers`:

- `flux-2-swift-mlx` (≥ v2.6.0) → `huggingface/swift-transformers` → vends `Tokenizers`
- `SwiftTuberia` (≥ v0.5.0) → `DePasqualeOrg/swift-tokenizers` → vends `Tokenizers`

SwiftPM rejects this with:

```
multiple packages ('swift-tokenizers', 'swift-transformers') declare targets
with a conflicting name: 'Tokenizers'; target names need to be unique across
the package graph
```

The collision was introduced by the dependency-floor bump in commit `4c6c6ea` (2026-04-29), which moved Tubería from 0.3.6 → 0.6.0 and Acervo from 0.6.0 → 0.8.3 to align with the `pixart-swift-mlx` v0.5.0 release. That release is required to keep moving on the SwiftTubería integration described in `REQUIREMENTS.md`. Until upstream picks one tokenizer library, the only ways to compile are: (a) roll all three back to pre-`4c6c6ea`, (b) drop flux2 from the package.

We chose (b) so PixArt can keep iterating on the v0.5.0 / Tubería 0.6 stack.

## Upstream signal that says it's safe to re-enable

The build is unblocked when **either** of the following becomes true:

1. **`flux-2-swift-mlx`** publishes a release that uses `DePasqualeOrg/swift-tokenizers` instead of `huggingface/swift-transformers`. (Track: the `Package.swift` of the latest tag — `cd ../flux-2-swift-mlx && git show <tag>:Package.swift | grep tokenizers`.) **OR**
2. **`SwiftTubería`** publishes a release that switches back to `huggingface/swift-transformers`. (Less likely — the migration was deliberate; `swift-tokenizers` is the maintained fork.) **OR**
3. **`huggingface/swift-transformers`** removes its `Tokenizers` target (renames it). Verify by checking its `Package.swift` on the tag pinned in flux2.

Sanity check before re-enabling — add `flux-2-swift-mlx` back to a scratch `Package.swift` alongside `SwiftTubería`/`pixart-swift-mlx`, and confirm:

```bash
xcodebuild -resolvePackageDependencies \
  -scheme SwiftVinetas-Package \
  -derivedDataPath /tmp/flux2-resolve-probe
```

succeeds with no `conflicting name: 'Tokenizers'` error.

## Re-enable checklist

1. **Confirm upstream is reconciled** (see signal above).
2. **`Package.swift`**: remove the `flux2Enabled` env-var gate; restore the `flux-2-swift-mlx` dependency and `Flux2Core` / `FluxTextEncoders` products on the `SwiftVinetas` target. Drop the `.define("VINETAS_FLUX2_DISABLED")` swiftSetting.
3. **Source files**: remove every `#if !VINETAS_FLUX2_DISABLED` … `#endif` block. The full list is in [§ File inventory](#file-inventory) below.
4. **Test files**: same `#if` removal for the test target.
5. **`Makefile`**: re-enable the flux2 fixture target if it was no-op'd; re-add Flux2 entries to `INTEGRATION_SUITES`.
6. **`BUGS.md`**: remove the "Flux2 disabled" note that points back to this doc.
7. **Verify**:
   ```bash
   make resolve              # no Tokenizers collision
   make build                # both engines compile
   make test-unit            # unit tests cover both engines again
   make test-fixtures        # both seed-42 PNGs regenerate
   ```
   The fixture comparison should produce a non-garbled FLUX.2 image (Klein 4B) and the existing PixArt seed-42 image. If FLUX.2 looks broken, treat it as a regression — the disable window may have masked unrelated breakage. Re-run the supervisor-state pattern from `docs/complete/pixart-garbage-supervisor-state.md` for FLUX.2 specifically.
8. **Move this doc** to `docs/complete/FLUX2_REENABLE.md` once verified.

## File inventory

Every file modified during the disable. The `#if`-gating uses the symbol `VINETAS_FLUX2_DISABLED`, defined in `Package.swift` only when `VINETAS_ENABLE_FLUX2 != "1"`.

### Package config

- `Package.swift` — env-driven `flux2Enabled` flag; conditionally includes `flux-2-swift-mlx` dep, `Flux2Core` + `FluxTextEncoders` products on `SwiftVinetas` target, and excludes `Sources/SwiftVinetas/Engine/Flux2Engine.swift` from compilation; defines `VINETAS_FLUX2_DISABLED` swift setting when the env var is unset.

### Sources

- `Sources/SwiftVinetas/Engine/Flux2Engine.swift` — **excluded entirely** from target sources via `Package.swift` `exclude:` when disabled. Whole-file `#if !VINETAS_FLUX2_DISABLED` wrapper as a defense in depth.
- `Sources/SwiftVinetas/Vinetas.swift` — gates the `import Flux2Core` / `import FluxTextEncoders` lines, the engine registration in `VinetasClient.init`, the `preview()` fast path (which is FLUX.2-only), and the `defaultModel` / `klein4B` / `klein9B` static accessors. When disabled, `defaultModel` falls back to `PixArtModelDescriptor.sigmaXL`.
- `Sources/SwiftVinetas/Core/VinetasModelManager.swift` — gates flux2 download/management entry points.
- `Sources/SwiftVinetas/Core/VinetasPipeline.swift` — already deprecated per `REQUIREMENTS.md` § S11; whole file gated.
- `Sources/SwiftVinetas/Core/LoRAManager.swift` — gates flux-specific LoRA paths. Generic LoRA path stays.
- `Sources/SwiftVinetas/Engine/EngineRouter.swift` — gates two `Flux2ModelDescriptor` references (engine registration helpers).
- `Sources/SwiftVinetas/Engine/ModelDescriptor.swift` — gates `Flux2ModelDescriptor` re-exports.
- `Sources/SwiftVinetas/Character/CharacterTrainer.swift` — gates flux2-only training paths (LoRA training is currently flux-only per `ENGINE_ABSTRACTION_REQUIREMENTS.md` § E8.1).

### Tests

- `Tests/SwiftVinetasTests/Flux2EngineTests.swift` — whole file `#if !VINETAS_FLUX2_DISABLED`.
- `Tests/SwiftVinetasTests/VinetasClientTests.swift` — gate the flux2-using cases.
- `Tests/SwiftVinetasTests/VinetasModelTests.swift` — gate flux2 model assertions.
- `Tests/SwiftVinetasTests/VinetasModelManagerTests.swift` — gate flux2 manager tests.
- `Tests/SwiftVinetasTests/EngineRouterTests.swift` — gate flux2 engine registration tests.
- `Tests/SwiftVinetasTests/PlatformRegistrationTests.swift` — gate flux2 macOS registration assertions.
- `Tests/SwiftVinetasTests/LoRACompatibilityTests.swift` — gate flux2 LoRA-format cases.
- `Tests/SwiftVinetasTests/CharacterTests.swift` — gate flux2 model references.
- `Tests/SwiftVinetasTests/CharacterTrainerTests.swift` — gate flux2 trainer cases.
- `Tests/SwiftVinetasGPUTests/Flux2IntegrationTests.swift` — whole file gated.
- `Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift` — gate `generateFlux2Fixture()`.
- `Tests/SwiftVinetasGPUTests/AllModelsExampleTests.swift` — gate flux2 case in the model loop.
- `Tests/SwiftVinetasGPUTests/PixArtIntegrationTests.swift` — gate one helper that mentioned Flux2.
- `Tests/SwiftVinetasGPUTests/IntegrationTestHelpers.swift` — gate flux2-specific helpers.

### Makefile

- `INTEGRATION_SUITES` — `Flux2IntegrationTests` removed. Restore on re-enable.
- `link-test-models` — Flux2 Klein hardlinks block left in place but harmlessly skips on absence; no change needed.

### BUGS.md

- Top-of-file note added: "FLUX.2 is temporarily disabled — see `docs/incomplete/FLUX2_REENABLE.md`." Remove on re-enable.

## Smoke test for the disable

While disabled, verify nothing regressed silently:

```bash
make resolve         # must succeed with no Tokenizers collision
make build           # CLI builds
make test-unit       # all non-GPU unit tests pass (Flux2 tests are excluded)
make test-fixtures   # only PixArt fixture regenerates; Flux2 fixture path is no-op
```

If `make resolve` still complains about `Tokenizers`, something else in the graph is also pulling `huggingface/swift-transformers`. Inspect:

```bash
grep -rln "swift-transformers" ~/Projects/{flux-2,pixart-,SwiftTuberia,SwiftAcervo}*/Package.swift
```

## Related docs

- `REQUIREMENTS.md` § S6 — dependency target shape.
- `REQUIREMENTS.md` § S11 — Acervo integration audit (deferred for flux2).
- `docs/complete/pixart-garbage-supervisor-state.md` — the pattern to use if FLUX.2 generation regresses on re-enable.
- `docs/ENGINE_ABSTRACTION_REQUIREMENTS.md` § E8.1 — LoRA compatibility list; update if `compatibleEngines` rules change while flux2 is off.

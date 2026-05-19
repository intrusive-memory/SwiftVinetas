# TODO

## 2026-05-18 — Stop owning model-availability logic; defer to Acervo's three-state API

Driven by: `../SwiftAcervo/Docs/MODEL_AVAILABILITY_PATH.md` (the architecture doc) and `../SwiftAcervo/TODO.md` (the upstream work item). This entry tracks the SwiftVinetas-side changes that depend on the upstream Acervo changes landing first.

### Why

Today `Flux2Engine.isAvailable` (`Sources/SwiftVinetas/Engine/Flux2Engine.swift:409-420`) implements its own per-component check that ORs `Acervo.isComponentReady(component.localDirectoryName)` against `Acervo.isModelAvailable(Self.acervoRepoId(for: component))`. `PixArtEngine.isAvailable` does the same (`Sources/SwiftVinetas/Engine/PixArtEngine.swift:475-496`). Both exist because `Acervo.isModelAvailable` only checks `config.json` at the model root — too loose to trust standalone.

Once Acervo tightens `isModelAvailable` (or, better, ships the new `Acervo.availability(_:) async -> ModelAvailability`), the engine-side workarounds become redundant and actively harmful: they hide the in-flight-download state from Vinetas and make it impossible to show a unified "downloading… 30%" UI.

### Items (blocked on upstream)

- [ ] **Replace `Flux2Engine.isAvailable`'s body** with `await Acervo.availability(component.repoId)` per component, AND'd across components. The current `isComponentReady || isModelAvailable` workaround goes away.
- [ ] **Replace `PixArtEngine.isAvailable`'s body** the same way.
- [ ] **Replace `VinetasClient.isModelAvailable(_:)`** (`Sources/SwiftVinetas/Vinetas.swift:645-651`) so it returns `Acervo.availability(modelId) == .available` instead of calling the legacy `VinetasModelManager.isModelAvailable`. Keep the function signature returning `Bool` for now — the three-state surface for the UI is exposed via a new passthrough below, not here.
- [ ] **Expose a passthrough on `VinetasClient`** for Vinetas's UI: `public func availability(_ modelId: String) async -> Acervo.ModelAvailability`. Vinetas's `ModelManagementService` will observe this instead of owning its own `isDownloading` flag.

---

## 2026-05-16 — PixArt color cast / telemetry coverage — SwiftVinetas-side follow-ups

While diagnosing why PixArt-Sigma produces severely red-dominant, oversaturated, crushed-shadow output relative to Flux2 Klein-4B on identical prompts/seeds, several SwiftVinetas-side follow-ups were identified. The root-cause work itself lives in sibling repos; this list is what SwiftVinetas needs to do once those land.

Reproducer used throughout: `vinetas generate "<prompt>" --model {pixart-sigma|klein4b} --seed 42 --telemetry`. Traces land in `~/Library/Caches/vinetas/telemetry/`. The mid-century-illustration prompt (high color diversity in expected output) is the most discriminating fixture for the color-cast question.

### SwiftVinetas-side work once upstreams land

1. **Regenerate the comparison fixtures** with the new SwiftTuberia 0.7.2 + pixart-swift-mlx 0.7.3 floors (`tmp/fixtures/pixart-midcent-seed42.png` vs `flux2-midcent-seed42.png`) and verify hue-distribution / saturation-P90 / crushed-black-pct regress toward Flux2's numbers.
2. Once SwiftAcervo telemetry lands, **add an acervo-event assertion** to `make test-telemetry-debug` so future regressions in cross-library event routing fail the test, not silently disappear.
3. Update `--telemetry` help text in `vinetas generate` once the actual event coverage matches the advertised set (today the help text overstates SwiftAcervo coverage).
4. Consider promoting the post-clamp pixel histogram (RGB mean per channel, hue-bin distribution, saturation P50/P90, % crushed black, % blown highlights) into the vinetas trace itself — currently computed ad-hoc from rendered PNGs during investigations.

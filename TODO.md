# TODO

## 2026-05-16 — PixArt color cast / telemetry coverage — cross-repo follow-ups

While diagnosing why PixArt-Sigma produces severely red-dominant, oversaturated, crushed-shadow output relative to Flux2 Klein-4B on identical prompts/seeds, four upstream gaps were identified. Each lives in a sibling library and has its own TODO.md entry. SwiftVinetas's job here is to **track these as blockers on the PixArt-garbage investigation** (see `docs/incomplete/pixart-garbage-supervisor-state.md`) and re-run the comparison fixture after each upstream lands.

Reproducer used throughout: `vinetas generate "<prompt>" --model {pixart-sigma|klein4b} --seed 42 --telemetry`. Traces land in `~/Library/Caches/vinetas/telemetry/`. The mid-century-illustration prompt (high color diversity in expected output) is the most discriminating fixture for the color-cast question.

### Upstream items being tracked

- **[`../pixart-swift-mlx/TODO.md`](../pixart-swift-mlx/TODO.md)** — color cast root-cause hunt: SDXL VAE latent scaling constant (0.13025), post-VAE clamp vs `tanh`, T5-XXL int4 conditioning bias. Carries the measured stats (final PNG: 96.4% red+orange / 0% blue+cyan; saturation P90 = 1.00; 23.5% crushed-black pixels). **Primary blocker** for the PixArt garbage investigation.
- ~~**SwiftTuberia TODO**~~ — closed 2026-05-16. SwiftTuberia 0.7.2 shipped the SDXL VAE renderer-contract fix (`(x * 0.5 + 0.5).clamp(0, 1)` applied to `SDXLVAEDecoder.decode` output). The companion null-per-step-telemetry-fields TODO was retired with it: it existed to localize the color cast, and the fix subsumes the diagnostic need.
- **[`../flux-2-swift-mlx/TODO.md`](../flux-2-swift-mlx/TODO.md)** — Flux2 emits only 13 events end-to-end; per-step `denoiseStep*` events and a transformer `weightLoadComplete` are missing. Less urgent than the PixArt items, but needed for symmetric cross-engine telemetry comparisons.
- **[`../SwiftAcervo/TODO.md`](../SwiftAcervo/TODO.md)** — `kind:acervo` events never reach the vinetas trace despite `vinetas generate --help` advertising them. Either not wired on the new component-keyed APIs (`ensureComponentReady`, `withComponentAccess`) or not routed through `TelemetryRouter`. Cross-cutting: affects every engine's trace.

### SwiftVinetas-side work once upstreams land

1. **Regenerate the comparison fixtures** with the new SwiftTuberia 0.7.2 + pixart-swift-mlx 0.7.3 floors (`tmp/fixtures/pixart-midcent-seed42.png` vs `flux2-midcent-seed42.png`) and verify hue-distribution / saturation-P90 / crushed-black-pct regress toward Flux2's numbers per the verification criteria in `../pixart-swift-mlx/TODO.md`.
2. Once SwiftAcervo telemetry lands, **add an acervo-event assertion** to `make test-telemetry-debug` so future regressions in cross-library event routing fail the test, not silently disappear.
3. Update `--telemetry` help text in `vinetas generate` once the actual event coverage matches the advertised set (today the help text overstates SwiftAcervo coverage).
4. Consider promoting the post-clamp pixel histogram (RGB mean per channel, hue-bin distribution, saturation P50/P90, % crushed black, % blown highlights) into the vinetas trace itself — currently computed ad-hoc from rendered PNGs during investigations.

### Stale-memory note

Auto-memory at `~/.claude/projects/-Users-stovak-Projects-SwiftVinetas/memory/project_manifest_destiny_followups.md` (dated 2026-05-06) says Flux2 generation is **blocked** on a SwiftAcervo manifest-as-bundle migration. That blocker has cleared: as of today, `vinetas generate --model klein4b` runs end-to-end and produces correct output. The acervo TODO above is *telemetry-only*, not a generation blocker. Memory should be refreshed when the Flux2 migration itself is fully retired.

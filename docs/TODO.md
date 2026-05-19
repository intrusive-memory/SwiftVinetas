# TODO

## 2026-05-16 — PixArt color cast / telemetry coverage — SwiftVinetas-side follow-ups

While diagnosing why PixArt-Sigma produces severely red-dominant, oversaturated, crushed-shadow output relative to Flux2 Klein-4B on identical prompts/seeds, several SwiftVinetas-side follow-ups were identified. The root-cause work itself lives in sibling repos; this list is what SwiftVinetas needs to do once those land.

Reproducer used throughout: `vinetas generate "<prompt>" --model {pixart-sigma|klein4b} --seed 42 --telemetry`. Traces land in `~/Library/Caches/vinetas/telemetry/`. The mid-century-illustration prompt (high color diversity in expected output) is the most discriminating fixture for the color-cast question.

### SwiftVinetas-side work once upstreams land

1. **Regenerate the comparison fixtures** with the new SwiftTuberia 0.7.2 + pixart-swift-mlx 0.7.3 floors (`tmp/fixtures/pixart-midcent-seed42.png` vs `flux2-midcent-seed42.png`) and verify hue-distribution / saturation-P90 / crushed-black-pct regress toward Flux2's numbers.
2. Once SwiftAcervo telemetry lands, **add an acervo-event assertion** to `make test-telemetry-debug` so future regressions in cross-library event routing fail the test, not silently disappear.
3. Update `--telemetry` help text in `vinetas generate` once the actual event coverage matches the advertised set (today the help text overstates SwiftAcervo coverage).
4. Consider promoting the post-clamp pixel histogram (RGB mean per channel, hue-bin distribution, saturation P50/P90, % crushed black, % blown highlights) into the vinetas trace itself — currently computed ad-hoc from rendered PNGs during investigations.

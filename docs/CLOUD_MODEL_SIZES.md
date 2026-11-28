---
type: reference
updated: 2026-11-27
---

# Cloud model output sizes

The smallest and largest image each cloud model can return for each Vinetas aspect
ratio, from the vendors' own documentation (checked 2026-11-27). Use it when you add
or change a `CloudModelDescriptor`, and when you read the live acceptance results
(`make test-cloud-models`, `docs/cloud-model-acceptance.md`).

Vinetas ratios: square 1:1 · wide 16:9 · ultrawide 2.4:1 · portrait 9:16 ·
panel ~3:2 · strip 4:1.

## OpenAI: `gpt-image-2.6-flare`, `gpt-image-2.6-sunburst`, `gpt-image-2.5-flare`, `gpt-image-2.5-sunburst`

Source: <https://developers.openai.com/api/docs/guides/image-generation>, "Customize
Image Output" (Sunburst and Flare, 2.5 and 2.6). The 2.6 model pages state no size
rules of their own.

Vendor rules:

- Width and height are multiples of **16**.
- Neither edge is over **3840** px.
- Total pixels are between **655,360** and **8,294,400**.
- The aspect ratio is between **1:3** and **3:1**.
- Recommended sizes: 1024×1024, 1536×1024, 1024×1536.
- `auto` lets the model choose. The default size isn't documented.
- Sizes above 2560×1440 are "experimental" (stated for 2.5 only).

The same four limits are applied below, with the ratio held within 1%. The minimum
is set by total pixels and the maximum by total pixels or the 3840 px edge.

| Ratio | Min (W×H) | Max (W×H) |
|---|---|---|
| square 1:1 | 816×816 | 2880×2880 |
| wide 16:9 | 1088×608 | 3840×2160 |
| ultrawide 2.4:1 | 1264×528 (Vinetas sends 1248×528, accepted) | 3840×1616 (Vinetas asks for 3840×1600) |
| portrait 9:16 | 608×1088 | 2160×3840 |
| panel 3:2 | 1008×672 | 3520×2352 |
| strip 4:1 | **not supported** (wider than 3:1) | — |

Reference images (edits endpoint): no documented limit. Vinetas caps them at 10.

## Google: Gemini image models

Source: <https://aistudio.google.com/docs/image-generation>, "Aspect ratios and image
size", plus each model page under `aistudio.google.com/docs/models/`. Google publishes
fixed sizes per ratio and resolution tier, not rules. Vinetas ratios map to the
nearest Google ratio: ultrawide → 21:9, panel → 3:2.

| Model | Tiers | Vinetas ratios | Reference images (documented) |
|---|---|---|---|
| `gemini-nano-banana-2.1` | 1K, 2K, 4K | all six, including strip (4:1) | 14 (10 objects + 4 characters) |
| `gemini-3.1-flash-image` | 512px, 1K, 2K, 4K | all six, including strip (4:1) | 14 (10 objects + 4 characters) |
| `gemini-3-pro-image` | 1K, 2K, 4K | five; **no 4:1** | 14 (6 objects + 5 characters + 3 style) |
| `gemini-3.1-flash-lite-image` | **1K only** | five; **no 4:1** | not stated ("not optimized for multiple reference inputs") |

Pixel sizes (W×H). Every model that offers a tier uses the same size for it:

| Ratio (Google) | 512px | 1K | 2K | 4K |
|---|---|---|---|---|
| square 1:1 | 512×512 | 1024×1024 | 2048×2048 | 4096×4096 |
| wide 16:9 | 688×384 | 1376×768 | 2752×1536 | 5504×3072 |
| ultrawide → 21:9 | 792×168 * | 1584×672 | 3168×1344 | 6336×2688 |
| portrait 9:16 | 384×688 | 768×1376 | 1536×2752 | 3072×5504 |
| panel → 3:2 | 632×424 | 1264×848 | 2528×1696 | 5056×3392 |
| strip 4:1 | 1024×256 † | **2064×512** (measured) | 4096×1024 † | 8192×2048 † |

† Unverified. The 4:1 row came from a summary of Google's table, and its 1K value
(2048×512) was wrong: both 4:1 models returned 2064×512 in the live run of
2026-11-27. Treat the other 4:1 tiers as unverified until measured.

\* 792×168 is 4.7:1, not 21:9. This is as published and is probably a typo in
Google's table. Vinetas doesn't use the 512px tier.

Each model's min and max, by its own tiers:

| Model | Min (1:1) | Max |
|---|---|---|
| `gemini-nano-banana-2.1` | 1024×1024 | 4K: 4096×4096 (1:1), 5504×3072 (16:9), 4:1 unverified |
| `gemini-3.1-flash-image` | 512×512 (512px tier; Vinetas uses 1K and up) | as 2.1 |
| `gemini-3-pro-image` | 1024×1024 | 4K: 4096×4096 (1:1), 5504×3072 (16:9); no 4:1 |
| `gemini-3.1-flash-lite-image` | 1024×1024 | 1K only: 1376×768 (16:9), 1584×672 (21:9) |

## Not documented by the vendors

- **OpenAI:** a minimum edge (only the pixel total), the default `size`, and a
  maximum number of edit input images.
- **Google:** a size table for `gemini-3.1-flash-lite-image` beyond 1024×1024. Its
  page says "14 aspect ratios" but names only 10. The table above assumes Flash Lite
  uses the shared 1K sizes. The live run of 2026-11-27 (AC-5) confirmed it for all
five Vinetas ratios.
- **Google:** a numeric reference-image limit for Flash Lite. Vinetas assumes 10. In
  AC-6 the vendor accepted 11, so 10 is Vinetas's own cap.
- **OpenAI:** the edits endpoint also accepted 11 references in AC-6.
- The Google size table comes from the guide's tabs, not the model pages. Re-check it
  when a model is added.

## Black Forest Labs, Stability AI

Not offered in 1.2.0 and not checked here.

---
type: report
title: Cloud model acceptance results
updated: 2026-11-27
---

# Cloud model acceptance results

Written by `make test-cloud-models` (run date 2026-11-27). Requirements section 8.2 B,
AC-4 to AC-7. AC-8 (pricing hint) is a manual check against the vendor's pricing page.

| Model | Check | Result | Actual dimensions | Vendor reference limit | Approx. cost | Note |
| --- | --- | --- | --- | --- | --- | --- |
| gpt-image-2.6-flare | AC-4 listed | pass | - | - | none | listed as gpt-image-2.6-flare |
| gpt-image-2.6-sunburst | AC-4 listed | pass | - | - | none | listed as gpt-image-2.6-sunburst |
| gemini-3.1-flash-lite-image | AC-4 listed | pass | - | - | none | listed as gemini-3.1-flash-lite-image |
| gpt-image-2.6-flare | AC-5 ratio square | pass | 816x816 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-flare | AC-5 ratio wide | pass | 1088x608 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-flare | AC-5 ratio ultrawide | pass | 1248x528 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-flare | AC-5 ratio portrait | pass | 608x1088 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-flare | AC-5 ratio panel | pass | 1008x672 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-5 ratio square | pass | 816x816 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-5 ratio wide | pass | 1088x608 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-5 ratio ultrawide | pass | 1248x528 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-5 ratio portrait | pass | 608x1088 | - | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-5 ratio panel | pass | 1008x672 | - | billed ($30/1M image output tokens) |  |
| gemini-3.1-flash-lite-image | AC-5 ratio square | pass | 1024x1024 | - | billed (~$0.034/image (1K)) |  |
| gemini-3.1-flash-lite-image | AC-5 ratio wide | pass | 1376x768 | - | billed (~$0.034/image (1K)) |  |
| gemini-3.1-flash-lite-image | AC-5 ratio ultrawide | pass | 1584x672 | - | billed (~$0.034/image (1K)) |  |
| gemini-3.1-flash-lite-image | AC-5 ratio portrait | pass | 768x1376 | - | billed (~$0.034/image (1K)) |  |
| gemini-3.1-flash-lite-image | AC-5 ratio panel | pass | 1264x848 | - | billed (~$0.034/image (1K)) |  |
| gemini-nano-banana-2.1 | AC-5 ratio strip | FAIL | 2064x512 | - | billed (~$0.03–0.11/image) | expected 2048x512 |
| gemini-3.1-flash-image | AC-5 ratio strip | FAIL | 2064x512 | - | billed (~$0.07–0.15/image) | expected 2048x512 |
| gpt-image-2.6-flare | AC-6 1 reference | pass | - | declared 10 | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-flare | AC-6 10 references | pass | - | declared 10 | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-flare | AC-6 11 references (direct) | pass | - | vendor accepted 11: limit is Vinetas's own cap | billed if accepted |  |
| gpt-image-2.6-sunburst | AC-6 1 reference | pass | - | declared 10 | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-6 10 references | pass | - | declared 10 | billed ($30/1M image output tokens) |  |
| gpt-image-2.6-sunburst | AC-6 11 references (direct) | pass | - | vendor accepted 11: limit is Vinetas's own cap | billed if accepted |  |
| gemini-3.1-flash-lite-image | AC-6 1 reference | pass | - | declared 10 | billed (~$0.034/image (1K)) |  |
| gemini-3.1-flash-lite-image | AC-6 10 references | pass | - | declared 10 | billed (~$0.034/image (1K)) |  |
| gemini-3.1-flash-lite-image | AC-6 11 references (direct) | pass | - | vendor accepted 11: limit is Vinetas's own cap | billed if accepted |  |
| gpt-image-2.6-flare | AC-7 invalid size | pass | - | - | unbilled | HTTP 400 |
| gpt-image-2.6-flare | AC-7 misspelled model | pass | - | - | unbilled | modelUnavailable |
| gpt-image-2.6-sunburst | AC-7 invalid size | pass | - | - | unbilled | HTTP 400 |
| gpt-image-2.6-sunburst | AC-7 misspelled model | pass | - | - | unbilled | modelUnavailable |
| gemini-3.1-flash-lite-image | AC-7 invalid size | pass | - | - | unbilled | HTTP 400 |
| gemini-3.1-flash-lite-image | AC-7 misspelled model | pass | - | - | unbilled | modelUnavailable |

## Resolution of the two strip failures

Both 4:1 generations succeeded and returned a valid strip (2064x512, 4.03:1, both edges
multiples of 16). The expected value was wrong: 2048x512 came from a summary of
Google's size table, not the page itself. The expected 1K 4:1 size is now 2064x512 in
the test and in `docs/CLOUD_MODEL_SIZES.md`, and the 512px/2K/4K strip sizes there are
marked unverified. The suite was not rerun after the correction; the rows above are the
run as recorded. The tolerance (±1 px) is unchanged.

Other findings:

- The OpenAI edits endpoint and Flash Lite both accepted 11 references. The limit of
  10 is Vinetas's own cap, not the vendor's.
- Flash Lite uses Google's shared 1K sizes for all five Vinetas ratios.

# Fixture Test Cache Warmer — Design

**Status**: draft (uncommitted) · 2026-05-01
**Owner**: TBD
**Related**: BUGS.md, Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift, .github/workflows/tests.yml

---

## Problem

`make test-fixtures` exercises both image-generation engines end-to-end on seed 42. With a warm SwiftAcervo cache it finishes in a few minutes. With a cold cache, **FLUX.2 Klein 4B + T5-XXL int4 + SDXL VAE decoder are multi-GB downloads** that exceed the 10-minute Swift Testing time limit, and on hosted CI runners the cache is empty on every fresh runner. Result: the only fixture verification we have can never pass on cold CI.

We've also lived with this gap producing PRs that build green but were never actually exercised end-to-end (PR #20 was an example — build passed, fixtures never ran cleanly).

## Background — current convention this design changes

Per `CLAUDE.md`, `make test-fixtures` (along with `test-gpu`, `test-integration`, `test-pixart-repro`) is currently a **local-only target** that "never runs in CI" and depends on `link-test-models` to hardlink weights from the App Group container into `/tmp`. **This design proposes changing that convention** so fixture tests gate PRs in CI, with the cache warmer providing the persistence layer that makes it tractable.

That convention change is itself a decision that warrants review — it's the most consequential thing in this doc. See §Open questions Q0.

## Goals

1. **Fixtures actually run on every PR build** — but only when models are pre-warmed.
2. **Cold-cache builds fail loudly** — the build is red, with a clear "needs cache warmer" signal in the PR check name; never silently green.
3. **Cache warmer is separately invokable** — manually via `workflow_dispatch` for pre-warming; automatically when a parent build hits cold cache.
4. **Self-healing**: warmer's completion triggers a re-run of the build that needed it, so a contributor doesn't have to babysit the loop.
5. **Local `make test-fixtures` still works** — locally, cold cache should warn + skip + exit clean (no automation to invoke); only CI cold-cache fails the build.

## Non-goals

- Caching outputs (generated PNGs). Only model weights.
- Replacing SwiftAcervo's existing on-runner download path. We're caching what Acervo already downloads, not bypassing Acervo.
- Solving the broader question of "should fixture tests gate PRs at all." Out of scope; design assumes yes.

## Architecture (one-screen view)

```
   ┌──────────────────────────┐                        ┌──────────────────────────┐
   │   Parent build           │                        │   Cache warmer           │
   │   (tests.yml)            │                        │   (warm-fixture-cache    │
   │                          │                        │    .yml)                 │
   │   1. checkout            │                        │                          │
   │   2. restore actions/    │  cold key miss →       │   1. checkout            │
   │      cache (per-engine)  │  triggers warmer  ──►  │   2. swift run vinetas   │
   │   3. set VINETAS_FIXTURE │                        │      warm-cache --engine │
   │      _COLD_<E>=1 envs    │                        │      <E>                 │
   │      for missed keys     │                        │   3. save actions/cache  │
   │   4. make build          │                        │      with engine key     │
   │   5. make test-fixtures  │                        │   4. gh workflow run     │
   │   6. wrapper exits       │                        │      tests.yml --ref SHA │
   │      non-zero if any                              │      -f triggered_by=    │
   │      _COLD_ env was set  │                        │      warmer_<RUN>        │
   │   7. on failure with     │  ───►  workflow run    │                          │
   │      cold cause:         │        warm-fixture-   │                          │
   │      gh workflow run     │        cache.yml       │                          │
   └──────────────────────────┘                        └──────────────────────────┘
                ▲
                │ re-run on same SHA
                │ (carries VINETAS_TRIGGERED_BY_WARMER=1; if cold again, fail without
                │ retriggering warmer — single-shot loop guard)
```

## Decisions (with reasoning, push back if wrong)

### D1: Cache backend = `actions/cache`, per-engine keys

Choice: GitHub `actions/cache@v4`, with **two independent cache keys**, one per engine:

- `vinetas-fixtures-pixart-${{ hashFiles('Tests/.../pixart-manifest.json') }}-${{ runner.os }}-${{ runner.arch }}`
- `vinetas-fixtures-flux2-${{ hashFiles('Tests/.../flux2-manifest.json') }}-${{ runner.os }}-${{ runner.arch }}`

Path: `~/Library/Caches/SwiftAcervo` (or whichever path SwiftAcervo writes to — verify with one `ls` on a warm runner before locking the path).

**Why per-engine, not one big key:** the 10 GB repo cache limit is tight for both engines simultaneously. Splitting means each engine evicts independently — a cold FLUX.2 can warm without invalidating PixArt and vice versa. If both engines' caches together exceed 10 GB, GitHub's LRU evicts the oldest, which is fine — the warmer fixes it next run.

**Why `hashFiles` on a manifest, not on Package.resolved:** the actual model weights change when the SwiftAcervo manifest changes, not when our Swift code changes. Tying invalidation to a manifest file (committed to the repo or fetched at job start) means cache stays valid across unrelated code changes.

**Open**: where does the per-engine manifest file live? Options below in §Open questions.

**Rejected alternatives:**
- *External R2 cache only (no actions/cache)*: simpler but every build re-downloads multi-GB from R2. Unacceptable for fast iteration.
- *Self-hosted runner*: best ergonomics, but commits us to runner ops. Worth considering long-term but not for this design.

### D2: Cold-cache detection = CI-side env vars, not in-test probes

The CI step that runs `actions/cache@v4` knows whether each key hit (it returns `cache-hit: true|false`). We piggyback on that:

```yaml
- uses: actions/cache@v4
  id: cache-pixart
  with:
    key: vinetas-fixtures-pixart-...
    path: ~/Library/Caches/SwiftAcervo/pixart-sigma-xl

- name: Detect cold engines
  run: |
    if [ "${{ steps.cache-pixart.outputs.cache-hit }}" != "true" ]; then
      echo "VINETAS_FIXTURE_COLD_PIXART=1" >> "$GITHUB_ENV"
    fi
    # ... same for flux2
```

The Swift Testing fixture tests then check the env var via `Test.disabled(if:)`:

```swift
@Test("Generate PixArt-Sigma XL fixture (seed 42)",
      .disabled(if: ProcessInfo.processInfo.environment["VINETAS_FIXTURE_COLD_PIXART"] == "1",
                "Cold cache — warmer dispatched"))
```

Disabled tests show as **skipped** in the test report, not as failures. The build is then failed by a separate **wrapper step** that runs after tests:

```yaml
- name: Fail if any fixture skipped due to cold cache
  if: env.VINETAS_FIXTURE_COLD_PIXART == '1' || env.VINETAS_FIXTURE_COLD_FLUX2 == '1'
  run: |
    echo "::error::Fixture cache cold — warmer dispatched. Build will re-run after warm."
    exit 1
```

**Why CI-side, not in-test:** keeps test code unaware of CI infrastructure. Locally, `make test-fixtures` doesn't set those env vars, so tests run normally. (Locally, if weights are missing, you get the existing failure — that's already the right behavior; no extra design needed.)

### D3: Trigger flow = `gh workflow run` with parameters, single-shot loop guard

**Parent → warmer**: parent's failure-handler step (only runs when cold cache caused the failure) invokes:

```yaml
- name: Dispatch cache warmer
  if: failure() && (env.VINETAS_FIXTURE_COLD_PIXART == '1' || env.VINETAS_FIXTURE_COLD_FLUX2 == '1')
  run: |
    gh workflow run warm-fixture-cache.yml \
      --ref "${{ github.head_ref || github.ref_name }}" \
      -f parent_run_id="${{ github.run_id }}" \
      -f parent_sha="${{ github.sha }}" \
      -f cold_engines="${COLD_ENGINES}"
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Warmer → parent re-run**: warmer's last step, on success:

```yaml
- name: Re-run parent build
  if: success() && inputs.parent_run_id != ''
  run: |
    # Re-run the failed jobs of the parent run; carries VINETAS_TRIGGERED_BY_WARMER=1
    # so the parent's cold-cache step knows not to dispatch another warmer.
    gh run rerun "${{ inputs.parent_run_id }}" --failed
```

**Loop guard**: parent's cold-detect step refuses to dispatch a warmer if `${{ github.event.workflow_run.conclusion }}` indicates this build itself was a re-run triggered by a warmer (or a simpler approach: check for the presence of an env var carried via the re-run). If still cold after warm, the build fails terminally with a "warmer ran but cache still cold — investigate manually" message. This caps the auto-loop at one round.

**Concurrency**: warmer workflow has `concurrency: { group: warm-fixtures-${{ inputs.cold_engines }}, cancel-in-progress: false }` so two PRs hitting cold cache simultaneously share one warmer run instead of duplicating multi-GB downloads.

## Component inventory

| Component | New / modified | Path |
|---|---|---|
| Cache warmer workflow | NEW | `.github/workflows/warm-fixture-cache.yml` |
| `vinetas warm-cache` CLI subcommand | NEW | `Sources/VinetasCLICore/Commands/WarmCacheCommand.swift` (one new file) |
| Engine manifest files for cache keys | NEW | `Tests/SwiftVinetasGPUTests/Fixtures/manifests/{pixart,flux2}.json` |
| Parent workflow | MODIFIED | `.github/workflows/tests.yml` — add cache restore + cold-detect + dispatch steps |
| Fixture tests | MODIFIED | `Tests/SwiftVinetasGPUTests/FixtureGenerationTests.swift` — add `.disabled(if:)` |
| Makefile | unchanged | (`make test-fixtures` already does what we need; the wrapper logic is in the workflow, not the Makefile, so local behavior stays the same) |

## Flow walkthroughs

### Warm-cache happy path
1. PR pushed → parent build starts.
2. `actions/cache@v4` restores both engine caches → `cache-hit: true` for both.
3. No `VINETAS_FIXTURE_COLD_*` env vars set.
4. `make build` → `make test-fixtures` → fixtures generate normally → tests pass.
5. Parent build green. Done.

### Cold-cache path → warmer → re-run
1. PR pushed → parent build starts.
2. `actions/cache@v4` restores fail for FLUX.2 (e.g., manifest hash changed). `cache-hit: false` for flux2; true for pixart.
3. Cold-detect step sets `VINETAS_FIXTURE_COLD_FLUX2=1`.
4. `make test-fixtures` runs. PixArt fixture passes. FLUX.2 fixture skipped (`.disabled(if:)`).
5. Wrapper step exits 1 because `VINETAS_FIXTURE_COLD_FLUX2=1`. Parent build fails.
6. Failure-handler dispatches warmer with `cold_engines=flux2` and `parent_run_id`.
7. Warmer runs (60-min timeout). Downloads Klein 4B + Mistral encoder. Saves cache.
8. Warmer triggers `gh run rerun <parent_run_id> --failed`.
9. Parent re-runs. `actions/cache@v4` hits the new key. Fixtures all pass. Green.

### Warmer fails / times out
1. Warmer step hits 60-min limit or download error.
2. Warmer's "re-run parent" step is gated on `success()`, so it does not fire.
3. PR check shows: parent failed (cold) + warmer failed. User investigates manually.
4. Re-running the warmer manually via `workflow_dispatch` is the recovery path.

### Manual pre-warm before merging
1. Contributor runs `gh workflow run warm-fixture-cache.yml -f cold_engines=flux2,pixart` from their machine.
2. Warmer runs, populates cache.
3. Subsequent PR builds hit warm cache and pass without dispatching a warmer.

## Loop prevention

- A re-run dispatched by the warmer carries the `parent_run_id` it warmed for.
- The parent's cold-detect step writes `VINETAS_TRIGGERED_BY_WARMER=1` to env when it sees this is a re-run after a warmer (detected via `${{ github.run_attempt > 1 }}` plus matching the warmer's recent run).
- The dispatch-warmer step is also guarded by `if: env.VINETAS_TRIGGERED_BY_WARMER != '1'`. So if cache is cold *again* after a warm cycle, the build fails terminally without re-dispatching.

(Simpler alternative: cap on `github.run_attempt`. If it's > 1, never dispatch a warmer. This is more brittle if someone manually re-runs a green build, but easier to read.)

## Local behavior

- Locally, `make test-fixtures` runs unchanged.
- `VINETAS_FIXTURE_COLD_*` env vars are never set locally (the cache-restore step doesn't run locally), so `.disabled(if:)` is always false → all tests run.
- If weights are genuinely missing locally, the existing failure modes apply (`missingComponent` etc.). User can pre-warm manually with the new `vinetas warm-cache` CLI subcommand.

## Open questions for you

These need answers (or "use your judgment") before YAML. Listed in priority order — Q0 and Q0a are potentially fatal if the answer is wrong; everything else is tuning.

### Q0. Should fixture tests run in CI at all?

The current convention (`CLAUDE.md`) says fixtures are local-only and never run in CI. This design proposes flipping that. Three positions:

- **(a) Yes, gate PRs on fixtures.** What this design assumes. Highest signal but biggest blast radius — every PR now waits on a multi-minute fixture run, and the cache warmer must work reliably or PRs back up.
- **(b) No, keep fixtures local-only — but build the cache warmer for *local* use only.** Drops the CI-gating goal entirely; `vinetas warm-cache` becomes a developer ergonomics tool. Removes 80% of this design's complexity (no actions/cache, no parent re-run loop, no skip-and-fail dance).
- **(c) Run fixtures in CI but only on a nightly schedule, not on every PR.** Compromise — catches regressions without blocking iteration. Fits naturally with a scheduled cache warmer.

The rest of this doc assumes (a). If (b) or (c) wins, the design contracts substantially.

### Q0a. Can hosted `macos-26` runners run MLX/Metal inference at all?

**This is a load-bearing assumption that I have not verified.** GitHub-hosted macOS runners are Apple Silicon, but it's unclear whether their Metal/GPU surface is sufficient for MLX inference under the constraints of a hosted VM. If hosted runners can't run MLX, the entire CI-side path is moot regardless of caching.

Mitigation paths if hosted runners don't work:
- **Self-hosted Apple Silicon runner** (your local machine, or a dedicated mini, or a leased Apple Silicon host). Cache lives on disk naturally → drops `actions/cache` entirely → drops most of the complexity in this doc → fixture builds become "fast on warm runner, occasional one-time download." This may end up the right answer regardless.
- **Drop CI fixture-gating** (back to Q0 (b)).

**Action**: spike a one-off PR that runs `make test-fixtures` on `macos-26` against a known-warm small model (e.g., quantize PixArt down to a tiny variant) and confirm Metal works. Or check the [macOS runner image docs](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md) for GPU/Metal support.

### Q1. Cache key source

Where do the per-engine model manifests live so `hashFiles` can pick them up?

- **(a)** Commit a small JSON like `Tests/.../manifests/flux2.json` listing the model slugs + expected R2 manifest hashes (manually updated when models bump).
- **(b)** Fetch the manifest at job start from R2 and hash that (zero maintenance, but adds a network dependency to the cache key step).

I lean (a) — it's a 5-line file, version-controlled, no surprises.

### Q2. Klein 4B actual size

I'm assuming ~5-8 GB based on quantization. Need to verify before locking in per-engine cache budget. Quick `curl -sI` on the R2 URL should give a content-length. If Klein 4B alone is >10 GB, the per-engine-key strategy is moot and we need a different approach (e.g., warming only the int4 quantized variant).

### Q3. `vinetas warm-cache` CLI subcommand or just a script?

I proposed a Swift CLI subcommand for symmetry with the rest of the project, but a `scripts/warm-fixture-cache.sh` calling SwiftAcervo's resolver via xcodebuild would also work and avoid touching the CLI. Subcommand is cleaner if it's also useful for local pre-warming.

### Q4. Model coverage

The warmer should warm: PixArt-Sigma XL transformer + SDXL VAE decoder fp16; FLUX.2 Klein 4B + Mistral encoder + T5 (if used). **Anything else either engine touches that I'm missing?** This list directly determines the cache budget — over-list and we hit the 10 GB cap; under-list and the cache warmer "succeeds" but the parent build still fails on a missing component.

### Q5. Concurrency policy for simultaneously-cold PRs

With `cancel-in-progress: false` and `group: warm-fixtures-flux2`, two simultaneously-cold PRs both wait on the same warmer. Is that acceptable, or do you want them to share a warmer's output (more complex) or each get their own (wastes bandwidth)?

### Q6. Cache eviction reality check

GitHub claims 10 GB total per repo with 7-day LRU eviction. If we exceed, the eldest engine cache evicts. Acceptable, or do you want a budget split mechanism (e.g., periodically check size + delete one)?

### Q7. Local cache path collision with `link-test-models`

The current local flow uses `link-test-models` to hardlink weights from the App Group container into `/tmp`. The new `vinetas warm-cache` CLI subcommand would write to wherever SwiftAcervo's default cache path is (likely `~/Library/Caches/SwiftAcervo` or similar). These are two different code paths populating two different directories. **Should the warmer's CLI also produce hardlinks to `/tmp` like `link-test-models` does**, so locally `make test-fixtures` works regardless of which path was used to populate weights? Or do we lean on SwiftAcervo's own resolver to find weights wherever they live?

## Out of scope (for this design)

- Caching across forks (forks can't write to upstream's actions/cache).
- Warming on a schedule (could be added later as a `schedule:` trigger on the warmer; orthogonal).
- Caching the build outputs (`/tmp/SwiftVinetasBuild`) — separate concern, separate design.
- Detecting bit-rot in the cache (e.g., a corrupted weight). Out of scope; the SwiftAcervo manifest hash check at runtime catches manifest mismatches.

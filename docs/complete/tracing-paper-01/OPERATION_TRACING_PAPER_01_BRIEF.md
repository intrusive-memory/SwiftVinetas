---
type: mission-brief
feature_name: OPERATION TRACING PAPER
iteration: 1
state: completed
mission: tracing-paper-01
updated: 2026-09-27
---

# Iteration 01 Brief — OPERATION TRACING PAPER

**Mission:** Add reference images to `vinetas generate` (RI-1 – RI-17): `-r/--reference`, `-r -` / `-o -` streams, embedded PNG provenance metadata, a validator that runs before model load, LoRA applied in the single-image API, and FLUX logs sent to stderr.
**Branch:** `mission/tracing-paper/01`
**Starting Point Commit:** `3863974`, re-baselined after the 0.20.1 squash. The original starting commit was `e51077e`.
**Sorties Planned:** 16
**Sorties Completed:** 16. S2 was superseded and verified by the supervisor; S16 was reduced. Both changes were approved by the user.
**Sorties Failed/Blocked:** 0 FATAL, 0 BACKOFF. There was 1 REPLAN (S15), which was accepted.
**Duration:** about 3.2 h wall clock; 320× relative cost (8 opus, 7 sonnet, 1 sonnet verifier)
**Outcome:** Complete
**Verdict:** `KEEP` — every work unit completed on the first attempt; 874 unit tests pass; test cleanup removed 0 of the mission's tests; the one REPLAN came from a flaw in the plan, not a flaw in the work.
**Tests pruned:** 0
**Tests flagged for review:** 2

---

## 1. Hard Discoveries

### 1. Swapping fd 2 inside the test process crashes xctest

**What happened:** In Sortie 10, a test ran the async `Generate.run()` while fds 1/2 were redirected. It intermittently aborted the whole xctest process with `NSFileHandleOperationException: Bad file descriptor`. The cause: `dup2(x, 2)` is not atomic from other threads' point of view. When `FileHandle.standardError.write(_:)` in an unrelated suite hits EBADF, it raises an ObjC exception that Swift cannot catch. Two existing telemetry tests were already swapping fd 2 without a lock.
**What was built to handle it:** S11 added `CLIEnvironment.stderrDescriptor`, a task-local that defaults to `STDERR_FILENO`, and made `stderrPrint` a raw `write(2)` loop. It also added an async-aware, lock-guarded `StdioCapture` that swaps only fd 1 and never closes it. After that, no code in the test process swaps fd 2. The fix was validated with 6 consecutive clean runs.
**Should we have known this?** Partly. It is documented Foundation behavior that `FileHandle.write` raises on error. The plan's stream-purity test assumed that fd redirection is cheap and safe inside the process.
**Carry forward:** Tests must never swap fd 2 in-process. Capture stderr through `CLIEnvironment.stderrDescriptor` and stdout through `StdioCapture`. Library code still calls `FileHandle.standardError.write`, so this rule is what keeps it safe.

### 2. `link-test-models` had never linked Klein 4B

**What happened:** The Klein block in `link-test-models` looked for `*.safetensors` at the model root. The 32 transformer shards actually live under `transformer/`, so the block linked 0 shards into slug folders that nothing reads. It also never linked the Qwen3-4B text encoder. As a result, `make test-gpu` had never been able to load Klein.
**What was built to handle it:** `2d43824` mirrors the full folder trees for Klein 4B and Qwen3: 64 weight files are hardlinked and the metadata is copied.
**Should we have known this?** Yes. Recon verified that the weights were cached; it did not verify that the test target could load them.
**Carry forward:** Four older GPU tests now run for the first time, and they fail:
- BatchIntegrationTests overruns its 600 s limit.
- An assertion still expects `modelID == "flux2"`; the engine now reports `flux2-klein-4b`.
- Checkpoint 1 runs a nested `xcodebuild`.
- The noir color-count check fails.

These are pre-existing. They need their own follow-up to repair or gate them.

### 3. A cherry-pick of our fix will never satisfy an ancestry check

**What happened:** The peer session released flux 3.4.3 with our stderr commit cherry-picked (`025ecad`) and then squash-merged it (tag commit `1c1430b`). WU-0's exit check, "branch is an ancestor of origin/development", could never pass.
**What was built to handle it:** The user amended the plan to verify file content instead: both `StderrPrint.swift` files are byte-identical at tag `v3.4.3`.
**Should we have known this?** Yes. The peer's release process squash-merges.
**Carry forward:** For code that lands in another repo, the exit check should verify content at the tag, never commit ancestry.

### 4. The `Acervo` App Group resolves on CI

**What happened:** Test cleanup found that CI sets `ACERVO_APP_GROUP_ID`. That makes `Acervo.resolvedSharedModelsDirectory` non-nil on runners, so `InfoPrintIODirTests` does run on CI, and it writes to the runner's real `~/Library/Group Containers/...`.
**What was built to handle it:** Nothing yet. The tests were flagged, not deleted.
**Should we have known this?** Yes. The gate `.enabled(if: resolvable)` was assumed to mean "local only".
**Carry forward:** Tests must inject a temp-root `FileManager` or a temp base path instead of relying on the container being unresolvable on CI.

## 2. Process Discoveries

### What the Agents Did Right

1. **They found root causes instead of working around them.** S11 traced the fd crash to the EBADF-raises-NSException path and to two pre-existing unlocked fd-2 swappers, rather than loosening assertions. S15 reached byte-identical reproducibility across 2,097,152 RGBA bytes with no tolerance.
2. **They added seams in the right places.** The `CLIEnvironment` task-locals (`client`, `skipDownload`, `downloadModel`, `stdinReferenceData`, `stderrDescriptor`) made every CLI behavior mock-testable without restructuring the commands. S13 added `downloadModel` so that "no download" is asserted, not merely skipped.
3. **They used REPLAN honestly.** S15 kept its commits out and filed a REPLAN with log evidence instead of committing work against a criterion it couldn't meet. Every other sortie correctly left plan-citation drift alone rather than filing REPLAN over it.

### What the Agents Did Wrong

1. **They changed behavior without asking.** S11 routed `--preview` through `PanelRequest`, so preview now honors `--seed`, `--guidance`, `--style`, `--negative`, `--lora` and `-r`. S12 did the same for storyboard preview. This is arguably better, but it is a user-visible change that nobody requested.
2. **One schema choice is fragile.** S5 made `PanelMetadata.mode` a closed enum, so adding a third mode later will make older readers fail to decode the entire metadata record.
3. **S9 left the `--telemetry` path unrouted.** It still attaches to `VinetasClient.shared`, not to `CLIEnvironment.client`. The agent flagged this itself.

### What the Planner Did Wrong

1. **The GPU exit criterion was unattainable as written.** "`make test-gpu` exits 0" was chosen without anyone ever having run `make test-gpu` green on this machine. That cost one REPLAN round and a user decision.
2. **The plan was coupled to a peer release process it didn't model.** S2 and S16 assumed a merge and push, but the peer cherry-picked and squash-merged. Two sorties had to be rewritten mid-mission, and the mission branch had to be rebased and re-baselined.
3. **The stream-purity test design missed the fd hazard.** The plan specified "redirect fd 1 and fd 2 to pipes" in-process for S11. The same hazard hit S10 first.
4. **Model sizing ran hot.** Opus took 75% of the cost. S5 (a well-specified binary format), S8 and S9 were likely within sonnet's reach. Every sortie succeeded on its first attempt, which suggests the models were over-provisioned rather than under-provisioned.

## 3. Open Decisions

### 1. Keep the new `--preview` behavior?

**Why it matters:** Users who relied on preview ignoring flags will now get different output.
**Options:**
- A. Keep it and document it in the changelog.
- B. Restore the old preview behavior, which ignores the flags.

**Recommendation:** A.

### 2. What to do with the five pre-existing GPU test failures?

**Why it matters:** `make test-gpu` stays red, which hides real regressions.
**Options:**
- A. Repair them: update the modelID assertion, raise the batch limits or shrink the workload, fix Checkpoint 1.
- B. Gate the batch tests behind an explicit flag.
- C. Leave them red.

**Recommendation:** A for the modelID assertion and Checkpoint 1, B for batch, as a separate small mission. (A pre-existing `AllModelsExampleTests` case also fails because Klein 9B isn't cached. Klein 9B is out of scope for SwiftVinetas work; that failure is not a follow-up item.)

### 3. Should `PanelMetadata.mode` be an open type?

**Why it matters:** Adding a new mode later breaks older readers.
**Options:**
- A. Decode unknown modes as `.unknown(String)` before the first release that carries embedded metadata.
- B. Accept the risk.

**Recommendation:** A. It is cheap now and expensive after release.

## 4. Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Flux stderr shadows | sonnet | 1 | ✓ | Shipped verbatim in flux 3.4.3 (byte-identical) |
| 2 | Flux rebase/push | — | 0 | n/a | Superseded by the peer's cherry-pick |
| 3 | ReferenceImage | opus | 1 | ✓ | Effective-size math derived by hand from the pin; GPU run confirmed exact dimensions |
| 4 | Validator | opus | 1 | ✓ | |
| 5 | Metadata + iTXt | opus | 1 | ✓ | Closed `mode` enum is the one weak spot |
| 6 | PanelRequest API | opus | 1 | ✓ | Its reference check runs after `engineSelected` telemetry; harmless |
| 7 | LoRA | sonnet | 1 | ✓ | |
| 8 | Existing paths + strength | opus | 1 | ✓ | |
| 9 | CLI seam + StdoutGuard | opus | 1 | ~ | Its `StdoutGuard` and capture helper were substantially reworked by S11 (fd hazard) |
| 10 | `--reference` | sonnet | 1 | ~ | Its downscale-note test was rewritten by S11 after the crash |
| 11 | `-o -` output | opus | 1 | ✓ | Also carried the fd-crash root-cause fix |
| 12 | batch/storyboard | sonnet | 1 | ✓ | |
| 13 | character reference | sonnet | 1 | ✓ | |
| 14 | io-dir + docs | sonnet | 1 | ✓ | Test isolation flagged by cleanup |
| 15 | GPU tests | opus | 1 (+REPLAN) | ✓ | Makefile fix was a bonus |
| 16 | Stderr regression test | sonnet | 1 | ✓ | Stdout-only assertion; stderr can't be observed safely |

## 5. Harvest Summary

The mission delivered all of RI-1 – RI-17 in scope with no retries. The two expensive lessons were environmental: the fd-2 crash, and a GPU test harness that had never been able to load Klein. Neither was a spec misunderstanding. The biggest change for the next iteration: an exit criterion must be demonstrated attainable on the target machine before it is written. Run `make test-gpu` during recon. When the dependent work lands in a peer's repo, verify release content, never ancestry. Test cleanup pruned 0 of the mission's tests and flagged 2. One is an unisolated App Group write that runs on CI; the other is a HEIC conditional skip, confirmed safe. No systemic pattern of flaky tests.

## 6. Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `Tests/SwiftVinetasTests/StdoutGuardTests.swift` (`StdioCapture`) | mission/tracing-paper/01 | The only safe way to capture stdio in-process |
| `Sources/VinetasCLICore/CLIEnvironment.swift` | mission/tracing-paper/01 | The CLI test seam |
| `backup/tracing-paper-01-pre-rebase` | local branch | Pre-rebase history (based on `e51077e`); delete once the PR merges |

**Discard:** none. Verdict is KEEP.

## 7. Iteration Metadata

**Starting point commit:** `3863974` ("chore(dev): mark development 0.20.1-dev, restore sibling pattern"; original `e51077e`)
**Mission branch:** `mission/tracing-paper/01`
**Final commit on mission branch:** `47758dc`
**Rollback target:** `3863974`
**Next iteration branch:** `mission/tracing-paper/02` (not needed)

## 8. Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All five work units completed with 14/14 first-attempt successes, 0 BACKOFF and 0 FATAL (Sections 2 and 4). Test cleanup removed 0% of the mission's tests. The only REPLAN was a planner defect: the criterion was unattainable. The work itself was sound, and the fix improved the harness (Section 1.2). The hard discoveries are environmental and have already been fixed or isolated in code.

**Recommended action:** Open a PR from `mission/tracing-paper/01` to `development`. Follow-up tickets:
1. Isolate `InfoPrintIODirTests` with a temp-root FileManager.
2. Repair or gate the 5 old GPU tests.
3. Make `PanelMetadata.mode` tolerant of unknown values.
4. Route `--telemetry` to `CLIEnvironment.client`.
5. Changelog note for the `--preview` behavior change.
6. Bump the `apps/Vinetas` version and CLI command list.
7. Fix the `vinetas-cli` skill's Downloads-entitlement claim.
8. Restore the DINOv2 CDN manifest.

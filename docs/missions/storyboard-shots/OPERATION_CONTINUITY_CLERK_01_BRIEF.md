---
type: mission-brief
state: complete
---

# OPERATION CONTINUITY CLERK — Brief 01

## Terminology

> **Mission** — A definable, testable scope of work. **Sortie** — An atomic unit of work executed by one agent in one dispatch. **Work Unit** — A grouping of sorties.

## 1. Outcome
10/10 sorties completed on the first attempt. One verifier round failed (S6) and was fixed in the same agent. No REPLAN.

## 2. Hard discoveries
- **SwiftCompartido cannot carry a notation-2.0 JSON `ref` array in `.fountain`.** Its note regex (`FountainParser.swift:55`) rejects `]` inside `[[ ]]` and drops the note silently as Action. Workaround: use the 1.0 tag `ref="A,B"`. Needs an upstream fix in SwiftCompartido.
- **glosa-av writes seeds above 2^53−1 as decimal strings** in `schemaJSONData()`. The sidecar's raw-JSON bridge preserves them, and `renderDigest` round-trips.
- **`make verify-ui-isolation` greps exported symbol names** for `Flux2`/`PixArt`/…, so vocabulary statics were named `bflFluxPro`/`bflFluxFlex`.
- **The `--shot-json` conflict rule forced `Generate.model`/`loraScale` to become optionals.** This is a public CLI-struct change, listed in the CHANGELOG.
- **`VinetasPromptComposer` is now generic over `StatusSection`.** Call sites compile unchanged, but explicit type spellings need `<EmptyView>`. This is noted in the CHANGELOG.

## 3. Requirements accuracy
- The requirements assumed a CHANGELOG existed. It didn't, so one was created (D-2).
- They didn't say whether `ModelSummary.all` should include cloud models. The plan kept it on-device and added `cloud` / `allIncludingCloud` (D-1).
- `--shot-json` `ref` resolution was unspecified. The plan decided it in D-7.

## 4. Process lessons
- The independent verifier caught a real defect (the dead-but-forbidden `--output-dir` fallback) that the implementer had dismissed as unreachable.
- The xcodebuild log prints one Swift Testing total per bundle. Track all three totals, not just the core number.

## 8. Rollback Verdict
**KEEP.** All gates are green locally; CI is pending on the PR.

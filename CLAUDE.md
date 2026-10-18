# Claude-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Claude Code agents.

## Build Preferences

**CRITICAL**: Always use `xcodebuild`. NEVER use `swift build` or `swift test` — Metal shaders required by MLX won't compile.

Prefer Makefile targets when available (`make help` lists everything):

```bash
make build               # Debug build
make test                # All macOS tests (unit + GPU)
make test-unit           # macOS unit tests only (no GPU, perf suites skipped) — CI-safe
make test-perf           # Performance/timing suites only — local only, never CI
make test-gpu            # GPU tests (local only; needs Apple Silicon + cached models)
make test-integration    # Integration tests (local only)
make test-fixtures       # Seed-42 cross-engine reference fixtures (local only)
make test-pixart-repro   # PixArt 5×-seed diagnostic harness (local only)
make test-ios            # All iOS Simulator tests
make test-unit-ios       # iOS unit tests only (no GPU)
make lint                # swift-format -i -r .
make lint-check / make verify-ui-isolation  # lint gate (fails on a format diff) / VinetasUI links no inference stack
make install             # Release build + install
```

Local-only targets (`test-gpu`, `test-integration`, `test-fixtures*`, `test-pixart-repro`) require pre-cached weights and never run in CI. They depend on `link-test-models`, which hardlinks weights from the App Group container into `/tmp` and passes the path as `TEST_RUNNER_VINETAS_TEST_MODELS_DIR`.

## CI Rules

- **CI does not run on draft PRs.** Open drafts for work in progress; `gh pr ready <n>` runs the suite. Jobs in `tests.yml` / `pixart-integration.yml` are gated with `if: !draft` and the trigger includes `ready_for_review` (the `draft-pr-ci-gate` skill).
- Required checks: `development` requires "Unit Tests (macOS)"; `main` requires "Unit Tests (macOS)" and "PixArt Integration (macOS)". Renaming a job silently un-requires it — update the protection in the same PR.
- **Performance tests never run in CI.** Suites that assert on elapsed time live in `PERF_SUITES` (Makefile) and are `-skip-testing:` in `test-unit` / `test-unit-ios`; run them with `make test-perf`. Never widen a timing tolerance to make one pass on a runner — add it to `PERF_SUITES`.

## MCP Server Configuration

### XcodeBuildMCP

Use XcodeBuildMCP tools for all Xcode operations instead of direct `xcodebuild` commands:

- **Building**: `build_macos`, `swift_package_build`
- **Testing**: `test_macos`, `swift_package_test`
- **Project Info**: `list_schemes`, `show_build_settings`
- **Utilities**: `clean`

## Claude-Specific Critical Rules

1. ALWAYS use XcodeBuildMCP tools when available
2. NEVER use `swift build` or `swift test`
3. Leverage MCP servers for automation
4. Follow global `~/.claude/CLAUDE.md` patterns (security, communication style)

# Claude-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Claude Code agents.

## Build Preferences

**CRITICAL**: Always use `xcodebuild`. NEVER use `swift build` or `swift test` — Metal shaders required by MLX won't compile.

Prefer Makefile targets when available (`make help` lists everything):

```bash
make build               # Debug build
make test                # All macOS tests (unit + GPU)
make test-unit           # macOS unit tests only (no GPU) — CI-safe
make test-gpu            # GPU tests (local only; needs Apple Silicon + cached models)
make test-integration    # Integration tests (local only)
make test-fixtures       # Seed-42 cross-engine reference fixtures (local only)
make test-pixart-repro   # PixArt 5×-seed diagnostic harness (local only)
make test-ios            # All iOS Simulator tests
make test-unit-ios       # iOS unit tests only (no GPU)
make lint                # swift-format -i -r .
make install             # Release build + install
```

Local-only targets (`test-gpu`, `test-integration`, `test-fixtures*`, `test-pixart-repro`) require pre-cached weights and never run in CI. They depend on `link-test-models`, which hardlinks weights from the App Group container into `/tmp` and passes the path as `TEST_RUNNER_VINETAS_TEST_MODELS_DIR`.

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

# Claude-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Claude Code agents.

## Build Preferences

**CRITICAL**: Always use `xcodebuild`. NEVER use `swift build` or `swift test` — Metal shaders required by MLX won't compile.

Prefer Makefile targets when available:

```bash
make build          # Debug build
make test           # All macOS tests
make test-unit      # macOS unit tests only (no GPU)
make test-ios       # All iOS Simulator tests
make test-unit-ios  # iOS unit tests only (no GPU)
make install        # Release build + install
```

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

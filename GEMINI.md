# Gemini-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Google Gemini agents.

## Build Commands

Use Makefile targets or direct `xcodebuild` commands (no MCP access):

```bash
# Preferred: Makefile targets
make build          # Debug build
make test           # All tests
make test-unit      # Unit tests only (no GPU)

# Direct xcodebuild
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'
```

## Gemini-Specific Critical Rules

1. Use standard CLI tools (no MCP access)
2. NEVER use `swift build` or `swift test` — use `xcodebuild` or `make`
3. Follow Xcode standard workflows

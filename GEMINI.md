# Gemini-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Google Gemini agents.

## Build Commands

Use Makefile targets or direct `xcodebuild` commands (no MCP access):

```bash
# Preferred: Makefile targets
make build          # Debug build
make test           # All macOS tests
make test-unit      # macOS unit tests only (no GPU)
make test-ios       # All iOS Simulator tests
make test-unit-ios  # iOS unit tests only (no GPU)

# Direct xcodebuild
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS,arch=arm64'
xcodebuild build -scheme SwiftVinetas -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
```

## Gemini-Specific Critical Rules

1. Use standard CLI tools (no MCP access)
2. NEVER use `swift build` or `swift test` — use `xcodebuild` or `make`
3. Follow Xcode standard workflows

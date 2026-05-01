# Gemini-Specific Agent Instructions

**Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Google Gemini agents.

## Build Commands

Use Makefile targets or direct `xcodebuild` commands (no MCP access). Run `make help` for the full list.

```bash
# Preferred: Makefile targets
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

# Direct xcodebuild
xcodebuild build -scheme SwiftVinetas -destination 'platform=macOS,arch=arm64'
xcodebuild build -scheme SwiftVinetas -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
```

Local-only test targets (`test-gpu`, `test-integration`, `test-fixtures*`, `test-pixart-repro`) require pre-cached weights and are never run in CI.

## Gemini-Specific Critical Rules

1. Use standard CLI tools (no MCP access)
2. NEVER use `swift build` or `swift test` — use `xcodebuild` or `make`
3. Follow Xcode standard workflows

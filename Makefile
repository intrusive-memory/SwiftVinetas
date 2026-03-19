# SwiftVinetas Makefile
# Build with xcodebuild (required for Metal shaders used by MLX)
# NEVER use `swift build` or `swift test`

DERIVED_DATA = /tmp/SwiftVinetasBuild
DESTINATION_MACOS = 'platform=macOS,arch=arm64'
DESTINATION_IOS = 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
SCHEME_LIB = SwiftVinetas
SCHEME_CLI = vinetas
SCHEME_PKG = SwiftVinetas-Package
BINDIR = ./bin

.PHONY: build release test test-unit test-integration test-ios test-unit-ios build-ios install clean resolve help

help: ## Show all available targets with descriptions
	@echo "SwiftVinetas — Makefile targets"
	@echo ""
	@grep -E '^[a-z][a-z_-]*:.*##' $(MAKEFILE_LIST) | \
		awk -F ':.*## ' '{ printf "  %-20s %s\n", $$1, $$2 }'
	@echo ""
	@echo "Examples:"
	@echo "  make build          # Debug build (macOS CLI)"
	@echo "  make test           # Run all macOS tests"
	@echo "  make test-unit      # Unit tests only (no GPU)"
	@echo "  make test-ios       # Run all iOS Simulator tests"
	@echo "  make test-unit-ios  # iOS unit tests only (no GPU)"
	@echo "  make install        # Release build + copy to ./bin/vinetas"

build: ## Debug build of the vinetas CLI + copy to ./bin/vinetas
	xcodebuild build \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA)
	@mkdir -p $(BINDIR)
	@cp $(DERIVED_DATA)/Build/Products/Debug/vinetas $(BINDIR)/vinetas
	@rsync -a --include='*.bundle' --include='*.bundle/**' --exclude='*' $(DERIVED_DATA)/Build/Products/Debug/ $(BINDIR)/
	@echo "Installed: $(BINDIR)/vinetas (with bundles)"

build-ios: ## Build the library for iOS Simulator
	xcodebuild build \
		-scheme $(SCHEME_LIB) \
		-destination $(DESTINATION_IOS) \
		-derivedDataPath $(DERIVED_DATA)

release: ## Release build of the vinetas CLI
	xcodebuild build \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION_MACOS) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA)

test: ## Run all macOS tests (unit + integration)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA)

test-unit: ## Run macOS unit tests only (no GPU or model required)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-skip-testing:SwiftVinetasTests/BatchIntegrationTests

test-integration: ## Run integration tests only (requires GPU + cached model)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasTests/BatchIntegrationTests

test-ios: ## Run all iOS Simulator tests
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_IOS) \
		-derivedDataPath $(DERIVED_DATA)

test-unit-ios: ## Run iOS Simulator unit tests only (no GPU or model required)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_IOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-skip-testing:SwiftVinetasTests/BatchIntegrationTests

install: release ## Release build + copy binary to ./bin/vinetas
	@mkdir -p $(BINDIR)
	@cp $(DERIVED_DATA)/Build/Products/Release/vinetas $(BINDIR)/vinetas
	@rsync -a --include='*.bundle' --include='*.bundle/**' --exclude='*' $(DERIVED_DATA)/Build/Products/Release/ $(BINDIR)/
	@echo "Installed: $(BINDIR)/vinetas (with bundles)"

clean: ## Clean build artifacts
	xcodebuild clean \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA)
	rm -rf $(DERIVED_DATA)

resolve: ## Resolve Swift Package Manager dependencies
	xcodebuild -resolvePackageDependencies \
		-scheme $(SCHEME_PKG) \
		-derivedDataPath $(DERIVED_DATA)

# SwiftVinetas Makefile
# Build with xcodebuild (required for Metal shaders used by MLX)
# NEVER use `swift build` or `swift test`
#
# ──────────────────────────────────────────────────────────────────────────────
# Test Filtering Strategy (Path B — Makefile-based)
# ──────────────────────────────────────────────────────────────────────────────
#
# This project is pure SPM (no .xcodeproj/.xcworkspace). The auto-generated
# SwiftVinetas-Package scheme does not support .xctestplan files because
# xcodebuild requires test plans to be "associated" with a scheme, and
# SPM auto-generated schemes have no persistent .xcscheme file to edit.
#
# Instead, we partition the test suite using -only-testing: flags:
#
#   test-unit         SwiftVinetasTests               CI-safe, no GPU
#   test-gpu          SwiftVinetasGPUTests            All GPU tests (unit + integration)
#   test-integration  SwiftVinetasGPUTests (filtered) Integration suites only (by class name)
#
# LIMITATION: Swift Testing tags (.integration, .gpu, .flux2, .pixart) defined
# in Tests/SwiftVinetasGPUTests/TestTags.swift are NOT directly filterable via
# -only-testing: flags. The -only-testing: flag operates at the target, class,
# and method level — not the tag level. The test-integration target approximates
# tag-based filtering by enumerating integration test suite class names. If new
# integration test suites are added, they must be added to INTEGRATION_SUITES.
# ──────────────────────────────────────────────────────────────────────────────

DERIVED_DATA = /tmp/SwiftVinetasBuild
DESTINATION_MACOS = 'platform=macOS,arch=arm64'
DESTINATION_IOS = 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1'
SCHEME_LIB = SwiftVinetas
SCHEME_CLI = vinetas
SCHEME_PKG = SwiftVinetas-Package
BINDIR = ./bin

# Integration test suites (class names within SwiftVinetasGPUTests).
# These correspond to all test files tagged .integration in TestTags.swift.
# Update this list when adding new integration test suites.
INTEGRATION_SUITES = \
	-only-testing:SwiftVinetasGPUTests/Flux2IntegrationTests \
	-only-testing:SwiftVinetasGPUTests/PixArtIntegrationTests \
	-only-testing:SwiftVinetasGPUTests/BatchIntegrationTests

.PHONY: build release test test-unit test-gpu test-integration test-ios test-unit-ios build-ios install clean resolve lint help

help: ## Show all available targets with descriptions
	@echo "SwiftVinetas — Makefile targets"
	@echo ""
	@grep -E '^[a-z][a-z_-]*:.*##' $(MAKEFILE_LIST) | \
		awk -F ':.*## ' '{ printf "  %-20s %s\n", $$1, $$2 }'
	@echo ""
	@echo "Examples:"
	@echo "  make build            # Debug build (macOS CLI)"
	@echo "  make test             # Run all macOS tests"
	@echo "  make test-unit        # Unit tests only (no GPU)"
	@echo "  make test-gpu         # GPU tests only (requires Apple Silicon + model)"
	@echo "  make test-integration # Integration tests only (download + generation)"
	@echo "  make test-ios         # Run all iOS Simulator tests"
	@echo "  make test-unit-ios    # iOS unit tests only (no GPU)"
	@echo "  make install          # Release build + copy to ./bin/vinetas"

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

test: ## Run all macOS tests (unit + GPU)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA)

test-unit: ## Run macOS unit tests only (no GPU or model required)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasTests

test-gpu: ## Run GPU tests only (requires Apple Silicon + cached model)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasGPUTests

test-integration: ## Run integration tests only (model download + image generation)
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		$(INTEGRATION_SUITES)

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
		-only-testing:SwiftVinetasTests

install: release ## Release build + copy binary to ./bin/vinetas
	@mkdir -p $(BINDIR)
	@cp $(DERIVED_DATA)/Build/Products/Release/vinetas $(BINDIR)/vinetas
	@rsync -a --include='*.bundle' --include='*.bundle/**' --exclude='*' $(DERIVED_DATA)/Build/Products/Release/ $(BINDIR)/
	@echo "Installed: $(BINDIR)/vinetas (with bundles)"

lint: ## Format Swift source files with swift-format
	swift format -i -r .

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

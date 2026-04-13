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

# Directory where WeightLoader looks for pre-hardlinked PixArt safetensors.
# xctest processes lack the com.apple.security.application-groups entitlement,
# so MACF blocks fopen() on files inside ~/Library/Group Containers/…  even
# though the files are readable from the shell. WeightLoader in SwiftTuberia
# detects this and falls back to hardlinks at PIXART_TEST_MODELS/<componentId>/.
# Creating the hardlinks here (from the entitled shell) bypasses the MACF check.
PIXART_TEST_MODELS = /tmp/vinetas-test-models
PIXART_SHARED_MODELS = $(HOME)/Library/Group Containers/group.intrusive-memory.models/SharedModels

# Integration test suites (class names within SwiftVinetasGPUTests).
# These correspond to all test files tagged .integration in TestTags.swift.
# Update this list when adding new integration test suites.
INTEGRATION_SUITES = \
	-only-testing:SwiftVinetasGPUTests/Flux2IntegrationTests \
	-only-testing:SwiftVinetasGPUTests/PixArtIntegrationTests \
	-only-testing:SwiftVinetasGPUTests/BatchIntegrationTests \
	-only-testing:SwiftVinetasGPUTests/AllModelsExampleTests

.PHONY: build release test test-unit test-gpu test-integration test-ios test-unit-ios build-ios install clean resolve lint link-test-models link-pixart-models help

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

link-test-models: ## Hardlink all model weights + tokenizer files from App Group container to /tmp so xctest can open them
	@SHARED="$(PIXART_SHARED_MODELS)"; \
	DEST="$(PIXART_TEST_MODELS)"; \
	echo "Linking PixArt / T5 / VAE (Acervo component directories)..."; \
	for pair in \
		"intrusive-memory_t5-xxl-int4-mlx:t5-xxl-encoder-int4" \
		"intrusive-memory_pixart-sigma-xl-dit-int4-mlx:pixart-sigma-xl-dit-int4" \
		"intrusive-memory_sdxl-vae-fp16-mlx:sdxl-vae-decoder-fp16"; do \
		srcdir=$$(echo "$$pair" | cut -d: -f1); \
		dstdir=$$(echo "$$pair" | cut -d: -f2); \
		srcpath="$$SHARED/$$srcdir"; \
		if [ ! -d "$$srcpath" ]; then \
			echo "  SKIP $$dstdir (not downloaded: $$srcpath)"; \
			continue; \
		fi; \
		mkdir -p "$$DEST/$$dstdir"; \
		linked=0; \
		for f in "$$srcpath/"*.safetensors; do \
			[ -e "$$f" ] || continue; \
			ln -f "$$f" "$$DEST/$$dstdir/" && linked=$$((linked + 1)); \
		done; \
		echo "  $$dstdir: $$linked shard(s) linked"; \
		copied=0; \
		for f in "$$srcpath/"*.json "$$srcpath/tokenizer.json" "$$srcpath/tokenizer_config.json" "$$srcpath/special_tokens_map.json"; do \
			[ -e "$$f" ] || continue; \
			cp -n "$$f" "$$DEST/$$dstdir/" 2>/dev/null && copied=$$((copied + 1)); \
		done; \
		[ $$copied -gt 0 ] && echo "  $$dstdir: $$copied config/tokenizer file(s) copied"; \
	done; \
	echo "Linking Flux2 Klein models (ModelRegistry directory structure)..."; \
	for pair in \
		"black-forest-labs/FLUX.2-klein-4B-klein4b-bf16:black-forest-labs/FLUX.2-klein-4B-klein4b-bf16" \
		"black-forest-labs/FLUX.2-klein-4B-vae:black-forest-labs/FLUX.2-klein-4B-vae"; do \
		srcrel=$$(echo "$$pair" | cut -d: -f1); \
		dstrel=$$(echo "$$pair" | cut -d: -f2); \
		srcpath="$$SHARED/$$srcrel"; \
		dstpath="$$DEST/$$dstrel"; \
		if [ ! -d "$$srcpath" ]; then \
			echo "  SKIP $$dstrel (not downloaded: $$srcpath)"; \
			continue; \
		fi; \
		mkdir -p "$$dstpath"; \
		linked=0; \
		for f in "$$srcpath/"*.safetensors; do \
			[ -e "$$f" ] || continue; \
			ln -f "$$f" "$$dstpath/" && linked=$$((linked + 1)); \
		done; \
		echo "  $$dstrel: $$linked shard(s) linked"; \
		copied=0; \
		for f in "$$srcpath/"*.json; do \
			[ -e "$$f" ] || continue; \
			cp -n "$$f" "$$dstpath/" 2>/dev/null && copied=$$((copied + 1)); \
		done; \
		[ $$copied -gt 0 ] && echo "  $$dstrel: $$copied json file(s) copied"; \
	done

# Keep the old name as an alias for backwards compatibility with any scripts.
link-pixart-models: link-test-models

test-gpu: link-test-models ## Run GPU tests only (requires Apple Silicon + cached model)
	VINETAS_TEST_MODELS_DIR=$(PIXART_TEST_MODELS) xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasGPUTests

test-integration: link-test-models ## Run integration tests only (model download + image generation)
	VINETAS_TEST_MODELS_DIR=$(PIXART_TEST_MODELS) xcodebuild test \
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

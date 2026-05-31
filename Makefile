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

SHELL := /bin/bash

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

# Default prompt for fixture generation. Override via:
#   make test-fixtures PROMPT="A field of sunflowers bathed in sunshine underneath a blue sky."
PROMPT ?= A red car parked on a cobblestone street

# Integration test suites (class names within SwiftVinetasGPUTests and SwiftVinetasTests).
# These correspond to all test files tagged .integration in TestTags.swift plus
# the telemetry integration tests (Sortie 9) in SwiftVinetasTests.
# Update this list when adding new integration test suites.
INTEGRATION_SUITES = \
	-only-testing:SwiftVinetasGPUTests/PixArtIntegrationTests \
	-only-testing:SwiftVinetasGPUTests/Flux2IntegrationTests \
	-only-testing:SwiftVinetasGPUTests/BatchIntegrationTests \
	-only-testing:SwiftVinetasGPUTests/AllModelsExampleTests \
	-only-testing:SwiftVinetasTests/TelemetryIntegrationTests

.PHONY: build release test test-unit test-gpu test-integration test-fixtures test-pixart-repro test-ios test-unit-ios build-ios install clean resolve lint link-test-models link-pixart-models help check-acervo-warnings test-telemetry-debug

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

release: ## Release build of the vinetas CLI + copy binary and Metal bundle to ./bin/
	xcodebuild build \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION_MACOS) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA)
	@mkdir -p $(BINDIR)
	@cp $(DERIVED_DATA)/Build/Products/Release/vinetas $(BINDIR)/vinetas
	@if [ -d "$(DERIVED_DATA)/Build/Products/Release/mlx-swift_Cmlx.bundle" ]; then \
		rm -rf $(BINDIR)/mlx-swift_Cmlx.bundle; \
		cp -R $(DERIVED_DATA)/Build/Products/Release/mlx-swift_Cmlx.bundle $(BINDIR)/; \
		echo "Installed: $(BINDIR)/vinetas + mlx-swift_Cmlx.bundle (Release)"; \
	else \
		echo "Error: mlx-swift_Cmlx.bundle not found in Release products"; \
		exit 1; \
	fi

test: ## Run all macOS tests (unit + GPU)
	TEST_RUNNER_CI=$${CI:-} TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA)

test-unit: ## Run macOS unit tests only (no GPU or model required); output captured to build/test-output.log
	@mkdir -p build
	TEST_RUNNER_CI=$${CI:-} TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasTests \
		2>&1 | tee build/test-output.log; exit $${PIPESTATUS[0]}

link-test-models: ## Hardlink all model weights + tokenizer files from App Group container to /tmp so xctest can open them
	@SHARED="$(PIXART_SHARED_MODELS)"; \
	DEST="$(PIXART_TEST_MODELS)"; \
	echo "Linking PixArt / T5 / VAE (Acervo component directories)..."; \
	for pair in \
		"intrusive-memory_t5-xxl-int4-mlx:intrusive-memory_t5-xxl-int4-mlx" \
		"intrusive-memory_pixart-sigma-xl-dit-int4-mlx:intrusive-memory_pixart-sigma-xl-dit-int4-mlx" \
		"intrusive-memory_sdxl-vae-fp16-mlx:intrusive-memory_sdxl-vae-fp16-mlx"; do \
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
		[ $$copied -gt 0 ] && echo "  $$dstdir: $$copied config/tokenizer file(s) copied" || :; \
	done; \
	echo "Linking Flux2 Klein models (Acervo slug directory structure)..."; \
	KLEIN_SLUG="black-forest-labs_FLUX.2-klein-4B"; \
	KLEIN_SRC="$$SHARED/$$KLEIN_SLUG"; \
	if [ ! -d "$$KLEIN_SRC" ]; then \
		echo "  SKIP Klein 4B (not downloaded: $$KLEIN_SRC)"; \
	else \
		XFMR_DEST="$$DEST/$$KLEIN_SLUG-klein4b-bf16"; \
		mkdir -p "$$XFMR_DEST"; \
		linked=0; \
		for f in "$$KLEIN_SRC/"*.safetensors; do \
			[ -e "$$f" ] || continue; \
			ln -f "$$f" "$$XFMR_DEST/" && linked=$$((linked + 1)); \
		done; \
		echo "  $$KLEIN_SLUG-klein4b-bf16 (transformer): $$linked shard(s) linked"; \
		for f in "$$KLEIN_SRC/"*.json; do \
			[ -e "$$f" ] || continue; \
			cp -n "$$f" "$$XFMR_DEST/" 2>/dev/null || :; \
		done; \
		VAE_SRC="$$KLEIN_SRC/vae"; \
		VAE_DEST="$$DEST/$$KLEIN_SLUG-vae"; \
		mkdir -p "$$VAE_DEST"; \
		linked=0; \
		for f in "$$VAE_SRC/"*.safetensors; do \
			[ -e "$$f" ] || continue; \
			ln -f "$$f" "$$VAE_DEST/" && linked=$$((linked + 1)); \
		done; \
		echo "  $$KLEIN_SLUG-vae (VAE): $$linked shard(s) linked"; \
		for f in "$$VAE_SRC/"*.json; do \
			[ -e "$$f" ] || continue; \
			cp -n "$$f" "$$VAE_DEST/" 2>/dev/null || :; \
		done; \
	fi

# Keep the old name as an alias for backwards compatibility with any scripts.
link-pixart-models: link-test-models

test-gpu: link-test-models ## Run GPU tests only (requires Apple Silicon + cached model)
	TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models TEST_RUNNER_VINETAS_TEST_MODELS_DIR=$(PIXART_TEST_MODELS) xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-parallel-testing-enabled NO \
		-only-testing:SwiftVinetasGPUTests

test-integration: link-test-models ## Run integration tests only (model download + image generation)
	TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models TEST_RUNNER_VINETAS_TEST_MODELS_DIR=$(PIXART_TEST_MODELS) xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-parallel-testing-enabled NO \
		$(INTEGRATION_SUITES)

test-telemetry-debug: link-test-models ## Run the Flux2 + PixArt telemetry integration tests; pipes log to /tmp/test-telemetry.log and prints the trace paths
	@TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models TEST_RUNNER_VINETAS_TEST_MODELS_DIR=$(PIXART_TEST_MODELS) xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasTests/TelemetryIntegrationTests/testEndToEndGenerationProducesCompleteTrace \
		-only-testing:SwiftVinetasTests/TelemetryIntegrationTests/testPixArtEngineRoutingEmitsCorrectEvents \
		2>&1 | tee /tmp/test-telemetry.log
	@echo "Telemetry integration traces:"
	@grep -oE '/tmp/[^ ]+\.jsonl|/var/folders/[^ ]+\.jsonl' /tmp/test-telemetry.log | sort -u

test-fixtures: build ## Generate one image per engine via the CLI, save to tmp/fixtures/, and open in Preview (override prompt: PROMPT="...")
	$(eval _PROMPT := $(if $(PROMPT),$(PROMPT),A red car parked on a cobblestone street))
	@mkdir -p tmp/fixtures
	@echo "[test-fixtures] prompt: $(_PROMPT)"
	./bin/vinetas generate "$(_PROMPT)" --model pixart-sigma --seed 42 --output tmp/fixtures/pixart-seed42.png
	./bin/vinetas generate "$(_PROMPT)" --model klein4b --seed 42 --output tmp/fixtures/flux2-seed42.png
	@open tmp/fixtures/pixart-seed42.png tmp/fixtures/flux2-seed42.png

test-pixart-repro: link-test-models ## Run PixArt 5× across seeds 42-46 to diagnose garbage output — saves to ~/Desktop/SwiftVinetasDebug/
	TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models \
	TEST_RUNNER_VINETAS_TEST_MODELS_DIR=$(PIXART_TEST_MODELS) xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_MACOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasGPUTests/PixArtGarbageReproTests

test-ios: ## Run all iOS Simulator tests
	TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_IOS) \
		-derivedDataPath $(DERIVED_DATA)

test-unit-ios: ## Run iOS Simulator unit tests only (no GPU or model required); output captured to build/test-output-ios.log
	@mkdir -p build
	TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION_IOS) \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SwiftVinetasTests \
		2>&1 | tee build/test-output-ios.log; exit $${PIPESTATUS[0]}

check-acervo-warnings: ## Fail if build/test-output.log contains SwiftAcervo regression warnings (run after test-unit)
	@LOG=build/test-output.log; \
	if [ ! -f "$$LOG" ]; then \
		echo "ERROR: $$LOG not found — run 'make test-unit' before 'make check-acervo-warnings'"; \
		echo "See: docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md § R7.1"; \
		exit 1; \
	fi; \
	if grep -qE '\[SwiftAcervo\] Warning: re-registering component|\[SwiftAcervo\] Manifest drift detected' "$$LOG"; then \
		echo ""; \
		echo "FAIL: SwiftAcervo regression warning detected in $$LOG:"; \
		grep -E '\[SwiftAcervo\] Warning: re-registering component|\[SwiftAcervo\] Manifest drift detected' "$$LOG"; \
		echo ""; \
		echo "A component was registered with a hardcoded 'files:' list, or the CDN manifest"; \
		echo "disagrees with the registered file list. Fix the registration and re-run tests."; \
		echo "See: docs/complete/SWIFTACERVO_MANIFEST_MIGRATION.md § R7.1"; \
		exit 1; \
	fi; \
	echo "OK: no SwiftAcervo regression warnings in $$LOG"

install: release ## Alias for `release` (Release build + copy to ./bin/)

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

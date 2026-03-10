# SwiftVinetas Makefile
# Build with xcodebuild (required for Metal shaders used by MLX)
# NEVER use `swift build` or `swift test`

DERIVED_DATA = /tmp/SwiftVinetasBuild
DESTINATION = 'platform=macOS'
SCHEME_LIB = SwiftVinetas
SCHEME_CLI = vinetas
SCHEME_PKG = SwiftVinetas-Package
BINDIR = ./bin

.PHONY: build release test install clean resolve help

help: ## Show all available targets with descriptions
	@echo "SwiftVinetas — Makefile targets"
	@echo ""
	@grep -E '^[a-z][a-z_-]*:.*##' $(MAKEFILE_LIST) | \
		awk -F ':.*## ' '{ printf "  %-12s %s\n", $$1, $$2 }'
	@echo ""
	@echo "Examples:"
	@echo "  make build     # Debug build"
	@echo "  make test      # Run all unit tests"
	@echo "  make install   # Release build + copy to ./bin/vinetas"

build: ## Debug build of the vinetas CLI
	xcodebuild build \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION) \
		-derivedDataPath $(DERIVED_DATA)

release: ## Release build of the vinetas CLI
	xcodebuild build \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA)

test: ## Run all unit tests
	xcodebuild test \
		-scheme $(SCHEME_PKG) \
		-destination $(DESTINATION) \
		-derivedDataPath $(DERIVED_DATA)

install: release ## Release build + copy binary to ./bin/vinetas
	@mkdir -p $(BINDIR)
	@cp $(DERIVED_DATA)/Build/Products/Release/vinetas $(BINDIR)/vinetas
	@echo "Installed: $(BINDIR)/vinetas"

clean: ## Clean build artifacts
	xcodebuild clean \
		-scheme $(SCHEME_CLI) \
		-destination $(DESTINATION) \
		-derivedDataPath $(DERIVED_DATA)
	rm -rf $(DERIVED_DATA)

resolve: ## Resolve Swift Package Manager dependencies
	xcodebuild -resolvePackageDependencies \
		-scheme $(SCHEME_PKG) \
		-derivedDataPath $(DERIVED_DATA)

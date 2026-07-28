// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SwiftVinetas",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    // Library for programmatic access (embed in Produciesta)
    .library(
      name: "SwiftVinetas",
      targets: ["SwiftVinetas"]
    ),
    // CLI command structs as a library (testable)
    .library(
      name: "VinetasCLICore",
      targets: ["VinetasCLICore"]
    ),
    // CLI for testing and debugging
    .executable(
      name: "vinetas",
      targets: ["vinetas"]
    ),
  ],
  dependencies: [
    // FLUX.2 image generation pipeline (MIT license, includes mlx-swift transitively)
    // Floored at 3.4.1: flux 3.3.2 floors mlx-swift at 0.31.4, which carries
    // upstream #410 (deadlock/EINVAL); 3.3.3 pins mlx exactly to 0.31.3, 3.3.4
    // fixes Klein transformer-weight resolution (weights live in the diffusers
    // `transformer/` subfolder, not the repo root), 3.4.0 adds iPad memory-tier
    // support (device-RAM-aware defaults, direct int4 load, VAE tiling), and
    // 3.4.1 makes pre-quantized MLX transformer dirs loadable (findModelPath now
    // accepts `model.safetensors.index.json` / bare `*.safetensors`, not just
    // `config.json`/`model_index.json`) — the fix for Klein 4B int4 generation.
    // Keep this as upToNextMajor so a future flux that adopts a fixed mlx is
    // picked up automatically — the mlx-version guarantee lives in flux itself.
    .package(
      url: "https://github.com/intrusive-memory/flux-2-swift-mlx.git", .upToNextMajor(from: "3.4.2")
    ),

    // Shared model management (download, cache, discovery)
    // Floored at 0.23.0: 0.21.0 made the CDN base URL a per-consumer config value
    // with NO hardcoded default (Acervo.cdnBaseURL traps when unset), and 0.23.0
    // adds lossless safetensors resharding + model-integrity verification used by
    // the integrity-checkpoint work. Consumers must supply ACERVO_CDN_BASE_URL
    // (CLI / tests / CI) or the AcervoCDNBaseURL Info.plist key (UI apps).
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.24.1")),

    // Componentized diffusion pipeline (protocols + infrastructure).
    // Floored at 0.7.9 (PixArt iOS OOM fix — phased text-encoder unload, REQ-MEM-01;
    // mlx-swift pinned .exact("0.31.3")).
    .package(
      url: "https://github.com/intrusive-memory/SwiftTuberia.git", .upToNextMajor(from: "0.7.9")),

    // PixArt-Sigma model plugin (DiT backbone + recipe).
    // Floored at 0.8.1: 0.8.0 landed the seam-free tiled VAE decode (#45/#83) —
    // PixArtRecipe sets decodeTileLatentSize so the macOS 4K decode transient is
    // bounded — and 0.8.1 is the current published patch.
    .package(
      url: "https://github.com/intrusive-memory/pixart-swift-mlx.git", .upToNextMajor(from: "0.8.1")
    ),

    // GLOSA screenplay directive parser — provides the `<shot>` storyboard
    // directives consumed by `vinetas storyboard`. Foundation-only leaf.
    .package(
      url: "https://github.com/intrusive-memory/glosa-av.git", .upToNextMajor(from: "0.8.0")),

    // Screenplay file parsing (.fountain / .highland / .fdx) — turns a
    // screenplay path into the `[[ ]]` note stream GlosaCore parses. Same
    // parser glosa-tools uses, so the screenplay→notes extraction has one
    // source of truth.
    .package(
      url: "https://github.com/intrusive-memory/SwiftCompartido.git", .upToNextMajor(from: "7.2.4")),

    // YAML/JSON prompt file parsing (zero dependencies)
    .package(url: "https://github.com/marcprux/universal.git", from: "5.3.0"),

    // CLI argument parsing
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),

    // swift-tokenizers 0.7.1 carries upstream 0.6.3's "Fixes for Xcode build
    // with artifact bundle", which resolves the UniFFI module-map/linker blocker
    // that previously froze us at 0.5.x. 0.6.0+ also makes the Tokenizer protocol
    // typed-throwing and relabels the encode/decode/tokenize convenience overloads.
    .package(
      url: "https://github.com/DePasqualeOrg/swift-tokenizers.git",
      .upToNextMinor(from: "0.7.1")),

    // Verifying the App Store entitlement the CLI is gated on. The stored
    // `Transaction.jwsRepresentation` is an Apple-signed JWS whose x5c chain
    // must be validated against a pinned Apple root — swift-certificates does
    // the X.509 work, swift-crypto the ES256 signature check.
    .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
  ],
  targets: [
    // Main library - storyboard/comic panel generation
    .target(
      name: "SwiftVinetas",
      dependencies: [
        .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "Tuberia", package: "SwiftTuberia"),
        .product(name: "TuberiaCatalog", package: "SwiftTuberia"),
        .product(name: "PixArtBackbone", package: "pixart-swift-mlx"),
        .product(name: "YAML", package: "universal"),
        .product(name: "JSON", package: "universal"),
      ]
    ),

    // CLI command structs as a library (imported by vinetas executable and test target)
    .target(
      name: "VinetasCLICore",
      dependencies: [
        "SwiftVinetas",
        .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
        .product(name: "PixArtBackbone", package: "pixart-swift-mlx"),
        .product(name: "Tuberia", package: "SwiftTuberia"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        // `vinetas storyboard`: screenplay → `<shot>` directives → panels.
        .product(name: "GlosaCore", package: "glosa-av"),
        .product(name: "SwiftCompartido", package: "SwiftCompartido"),
        // Pro entitlement gate on the FLUX.2 models.
        .product(name: "X509", package: "swift-certificates"),
        .product(name: "Crypto", package: "swift-crypto"),
      ]
    ),

    // CLI executable
    .executableTarget(
      name: "vinetas",
      dependencies: [
        "VinetasCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // Unit Tests (no GPU or MLX required — safe for CI)
    .testTarget(
      name: "SwiftVinetasTests",
      dependencies: [
        "SwiftVinetas",
        "VinetasCLICore",
        // ProGateTests mints a throwaway CA + leaf so entitlement verification
        // can be exercised hermetically, without a real App Store transaction.
        .product(name: "X509", package: "swift-certificates"),
        .product(name: "SwiftASN1", package: "swift-asn1"),
        .product(name: "Crypto", package: "swift-crypto"),
      ]
    ),

    // GPU Tests (requires Apple Silicon GPU + downloaded models)
    .testTarget(
      name: "SwiftVinetasGPUTests",
      dependencies: [
        "SwiftVinetas"
      ],
      // T5DiffuserComparisonDump is a one-off diagnostic that depends on
      // unreleased SwiftTuberia public surface (`transformer`, `blocks`,
      // `debugTap` exposed at module scope). Excluded until SwiftTuberia
      // ships a release that makes those symbols public.
      exclude: ["T5DiffuserComparisonDump.swift"],
      resources: [
        .copy("Fixtures")
      ]
    ),
  ]
)

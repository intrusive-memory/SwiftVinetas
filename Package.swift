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
    .package(
      url: "https://github.com/intrusive-memory/flux-2-swift-mlx.git", .upToNextMajor(from: "3.0.3")
    ),

    // Shared model management (download, cache, discovery)
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.12.0")),

    // Componentized diffusion pipeline (protocols + infrastructure)
    .package(
      url: "https://github.com/intrusive-memory/SwiftTuberia.git", .upToNextMajor(from: "0.6.5")),

    // PixArt-Sigma model plugin (DiT backbone + recipe)
    .package(
      url: "https://github.com/intrusive-memory/pixart-swift-mlx.git", .upToNextMajor(from: "0.6.0")
    ),

    // YAML/JSON prompt file parsing (zero dependencies)
    .package(url: "https://github.com/marcprux/universal.git", from: "5.3.0"),

    // CLI argument parsing
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
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
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
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

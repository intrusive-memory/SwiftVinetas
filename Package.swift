// swift-tools-version: 6.2

import PackageDescription
import Foundation

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
let useLocalSiblings = ProcessInfo.processInfo.environment["CI"] != "true"

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, from: version)
}

// FLUX.2 is temporarily disabled while the upstream tokenizer-target collision
// (flux-2-swift-mlx → huggingface/swift-transformers vs SwiftTuberia 0.6 →
// DePasqualeOrg/swift-tokenizers, both vending a target named `Tokenizers`)
// is being resolved. Set VINETAS_ENABLE_FLUX2=1 to opt in once upstream is
// reconciled. Re-enable breadcrumbs: docs/incomplete/FLUX2_REENABLE.md
let flux2Enabled = ProcessInfo.processInfo.environment["VINETAS_ENABLE_FLUX2"] == "1"

var packageDependencies: [Package.Dependency] = []
if flux2Enabled {
  // FLUX.2 image generation pipeline (MIT license, includes mlx-swift transitively)
  packageDependencies.append(
    sibling(
      "flux-2-swift-mlx",
      remote: "https://github.com/intrusive-memory/flux-2-swift-mlx.git",
      from: "2.6.0"))
}
packageDependencies.append(contentsOf: [
  // Shared model management (download, cache, discovery)
  sibling(
    "SwiftAcervo",
    remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
    from: "0.8.4"),

  // Componentized diffusion pipeline (protocols + infrastructure)
  sibling(
    "SwiftTuberia",
    remote: "https://github.com/intrusive-memory/SwiftTuberia.git",
    from: "0.6.0"),

  // PixArt-Sigma model plugin (DiT backbone + recipe)
  sibling(
    "pixart-swift-mlx",
    remote: "https://github.com/intrusive-memory/pixart-swift-mlx.git",
    from: "0.5.0"),

  // YAML/JSON prompt file parsing (zero dependencies)
  .package(url: "https://github.com/marcprux/universal.git", from: "5.3.0"),

  // CLI argument parsing
  .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
])

var swiftVinetasDependencies: [Target.Dependency] = [
  .product(name: "SwiftAcervo", package: "SwiftAcervo"),
  .product(name: "Tuberia", package: "SwiftTuberia"),
  .product(name: "TuberiaCatalog", package: "SwiftTuberia"),
  .product(name: "PixArtBackbone", package: "pixart-swift-mlx"),
  .product(name: "YAML", package: "universal"),
  .product(name: "JSON", package: "universal"),
]
if flux2Enabled {
  swiftVinetasDependencies.append(contentsOf: [
    .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
    .product(name: "FluxTextEncoders", package: "flux-2-swift-mlx"),
  ])
}

// When flux2 is disabled, exclude its engine file entirely from compilation and
// define VINETAS_FLUX2_DISABLED so dependent files can #if-gate their flux2 usage.
let flux2DisabledSetting: [SwiftSetting] = flux2Enabled ? [] : [.define("VINETAS_FLUX2_DISABLED")]
let swiftVinetasExcludes: [String] = flux2Enabled ? [] : ["Engine/Flux2Engine.swift"]
// Test files that are wholly built around the deprecated `Vinetas` namespace
// or `VinetasModel.klein*` cases. Gated out when flux2 is disabled.
let swiftVinetasTestsExcludes: [String] = flux2Enabled ? [] : [
  "Flux2EngineTests.swift",
  "VinetasMemoryTests.swift",
  "VinetasModelTests.swift",
  "VinetasModelManagerTests.swift",
  "PlatformRegistrationTests.swift",
  "CharacterPromptTests.swift",
  "CharacterTrainerTests.swift",
  "CLIArgumentTests.swift",
]
let swiftVinetasGPUTestsExcludes: [String] = flux2Enabled ? [] : [
  "Flux2IntegrationTests.swift",
  "BatchIntegrationTests.swift",
]

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
  dependencies: packageDependencies,
  targets: [
    // Main library - storyboard/comic panel generation
    .target(
      name: "SwiftVinetas",
      dependencies: swiftVinetasDependencies,
      exclude: swiftVinetasExcludes,
      swiftSettings: flux2DisabledSetting
    ),

    // CLI command structs as a library (imported by vinetas executable and test target)
    .target(
      name: "VinetasCLICore",
      dependencies: [
        "SwiftVinetas",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: flux2DisabledSetting
    ),

    // CLI executable
    .executableTarget(
      name: "vinetas",
      dependencies: [
        "VinetasCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: flux2DisabledSetting
    ),

    // Unit Tests (no GPU or MLX required — safe for CI)
    .testTarget(
      name: "SwiftVinetasTests",
      dependencies: [
        "SwiftVinetas",
        "VinetasCLICore",
      ],
      exclude: swiftVinetasTestsExcludes,
      swiftSettings: flux2DisabledSetting
    ),

    // GPU Tests (requires Apple Silicon GPU + downloaded models)
    .testTarget(
      name: "SwiftVinetasGPUTests",
      dependencies: [
        "SwiftVinetas"
      ],
      exclude: swiftVinetasGPUTestsExcludes,
      resources: [
        .copy("Fixtures")
      ],
      swiftSettings: flux2DisabledSetting
    ),
  ]
)

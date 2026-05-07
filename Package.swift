// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
//
// When this manifest is evaluated as a transitive dependency inside Xcode's
// `SourcePackages/checkouts/` or SwiftPM's `.build/checkouts/`, every other
// dependency lives as a sibling in the same directory. Treating those as
// in-development local paths produces conflicting package identities, so we
// must skip the sibling shortcut in that context.
let manifestDir = (#filePath as NSString).deletingLastPathComponent
let isSPMCheckout = manifestDir.contains("/SourcePackages/checkouts/")
  || manifestDir.contains("/.build/checkouts/")
let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
let useLocalSiblings = !isCI && !isSPMCheckout

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, from: version)
}

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
    sibling(
      "flux-2-swift-mlx",
      remote: "https://github.com/intrusive-memory/flux-2-swift-mlx.git",
      from: "3.0.3"),

    // Shared model management (download, cache, discovery)
    sibling(
      "SwiftAcervo",
      remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
      from: "0.12.0"),

    // Componentized diffusion pipeline (protocols + infrastructure)
    sibling(
      "SwiftTuberia",
      remote: "https://github.com/intrusive-memory/SwiftTuberia.git",
      from: "0.6.5"),

    // PixArt-Sigma model plugin (DiT backbone + recipe)
    sibling(
      "pixart-swift-mlx",
      remote: "https://github.com/intrusive-memory/pixart-swift-mlx.git",
      from: "0.6.0"),

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

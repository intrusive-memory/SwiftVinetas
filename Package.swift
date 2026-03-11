// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftVinetas",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Library for programmatic access (embed in Produciesta)
        .library(
            name: "SwiftVinetas",
            targets: ["SwiftVinetas"]
        ),
        // CLI for testing and debugging
        .executable(
            name: "vinetas",
            targets: ["vinetas"]
        )
    ],
    dependencies: [
        // FLUX.2 image generation pipeline (MIT license, includes mlx-swift transitively)
        .package(url: "https://github.com/VincentGourbin/flux-2-swift-mlx.git", from: "2.1.0"),

        // Shared model management (download, cache, discovery)
        .package(url: "https://github.com/intrusive-memory/SwiftAcervo.git", branch: "main"),

        // YAML/JSON prompt file parsing (zero dependencies)
        .package(url: "https://github.com/marcprux/universal.git", from: "5.3.0"),

        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Main library - storyboard/comic panel generation
        .target(
            name: "SwiftVinetas",
            dependencies: [
                .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
                .product(name: "FluxTextEncoders", package: "flux-2-swift-mlx"),
                .product(name: "SwiftAcervo", package: "SwiftAcervo"),
                .product(name: "YAML", package: "universal"),
                .product(name: "JSON", package: "universal"),
            ]
        ),

        // CLI executable
        .executableTarget(
            name: "vinetas",
            dependencies: [
                "SwiftVinetas",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // Unit Tests
        .testTarget(
            name: "SwiftVinetasTests",
            dependencies: [
                "SwiftVinetas",
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)

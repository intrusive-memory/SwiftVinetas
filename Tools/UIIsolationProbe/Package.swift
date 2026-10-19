// swift-tools-version: 6.2

// UI-isolation probe for `make verify-ui-isolation`. Built only through
// xcodebuild by the Makefile target.
//
// - `UIIsolationProbe` imports only `VinetasUI`; its binary and build log must
//   carry no MLX / Flux2 / PixArt / Tuberia / Acervo symbol or module.
// - `UIIsolationProbeEngine` imports `SwiftVinetas` on purpose; it is the
//   detector's self-test subject (`EXPECT_FAIL=1 make verify-ui-isolation`).

import PackageDescription

let package = Package(
  name: "UIIsolationProbe",
  platforms: [
    .macOS(.v26)
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "UIIsolationProbe",
      dependencies: [
        .product(name: "VinetasUI", package: "SwiftVinetas")
      ]
    ),
    .executableTarget(
      name: "UIIsolationProbeEngine",
      dependencies: [
        .product(name: "SwiftVinetas", package: "SwiftVinetas")
      ]
    ),
  ]
)

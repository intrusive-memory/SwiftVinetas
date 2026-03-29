import Testing

// MARK: - Shared Tag Definitions
//
// All Swift Testing tags for SwiftVinetasGPUTests are defined here in one
// canonical location. Do NOT redeclare these in individual test files.

extension Tag {
  /// Marks a test as an integration test requiring external resources
  /// (downloaded models, network access, GPU hardware).
  @Tag static var integration: Self

  /// Marks a test as requiring Apple Silicon GPU hardware.
  @Tag static var gpu: Self

  /// Marks a test as specific to the FLUX.2 image generation engine.
  @Tag static var flux2: Self

  /// Marks a test as specific to the PixArt-Sigma image generation engine.
  @Tag static var pixart: Self
}

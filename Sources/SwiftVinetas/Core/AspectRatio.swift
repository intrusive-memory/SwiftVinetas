import Foundation

/// Standard aspect ratio presets for comic panel and storyboard generation.
///
/// Dimensions are **platform-tiered**:
///
/// - **macOS** generates at television resolution — each ratio is fit inside a
///   3840×2160 4K UHD (Rec. 2020 / UHD-1) frame. Macs have the unified-memory and
///   swap headroom for full-resolution panels, so the ceiling is one 4K frame
///   (≤ 8.3 MP).
/// - **iOS** uses a smaller, memory-safe tier. iOS has no swap and a per-app jetsam
///   dirty-page budget that is a fraction of physical RAM, so the largest tensors
///   (latent, VAE-decode transient, decoded `CGImage`, encoded PNG — all scale with
///   `width × height`) must stay bounded.
///
/// All dimensions on both tiers are multiples of **16** — the true pipeline
/// constraint: the SDXL VAE downsamples by 8 and FLUX.2 / PixArt patchify the latent
/// by 2, so `width` and `height` must divide by `8 × 2 = 16` (e.g.
/// `flux-2-swift-mlx` `LatentUtils.generatePatchifiedLatents` → `H/16`, `W/16`).
/// (The earlier "multiple of 64" rule was a conservative superset; 16 is what the
/// VAE/DiT actually require, which is why exact 4K UHD — 2160 = 135×16, *not* a
/// multiple of 64 — is reachable.)
public enum AspectRatio: String, Sendable, CaseIterable {
  /// Square (1:1) — macOS 2160×2160, iOS 1024×1024.
  case square

  /// Widescreen (16:9) — macOS 3840×2160 (4K UHD), iOS 1344×768.
  case wide

  /// Ultra-wide cinematic (2.4:1) — macOS 3840×1600, iOS 1536×640.
  case ultrawide

  /// Portrait (9:16) — macOS 2160×3840 (vertical 4K), iOS 768×1344.
  case portrait

  /// Comic panel (~3:2) — macOS 3232×2160, iOS 1216×832.
  case panel

  /// Strip (4:1) — macOS 3840×960, iOS 2048×512.
  case strip

  /// The output width in pixels for this aspect ratio, for the current platform tier.
  public var width: Int {
    #if os(macOS)
      switch self {
      case .square: 2160
      case .wide: 3840
      case .ultrawide: 3840
      case .portrait: 2160
      case .panel: 3232
      case .strip: 3840
      }
    #else
      switch self {
      case .square: 1024
      case .wide: 1344
      case .ultrawide: 1536
      case .portrait: 768
      case .panel: 1216
      case .strip: 2048
      }
    #endif
  }

  /// The output height in pixels for this aspect ratio, for the current platform tier.
  public var height: Int {
    #if os(macOS)
      switch self {
      case .square: 2160
      case .wide: 2160
      case .ultrawide: 1600
      case .portrait: 3840
      case .panel: 2160
      case .strip: 960
      }
    #else
      switch self {
      case .square: 1024
      case .wide: 768
      case .ultrawide: 640
      case .portrait: 1344
      case .panel: 832
      case .strip: 512
      }
    #endif
  }

  /// Returns a `StyleConfig` with this aspect ratio's dimensions applied.
  ///
  /// All other style properties are inherited from the supplied base config
  /// (or from `StyleConfig()` defaults if none is provided).
  ///
  /// - Parameter base: Optional base style configuration.
  /// - Returns: A new `StyleConfig` with `width` and `height` set to this preset.
  public func styleConfig(base: StyleConfig = StyleConfig()) -> StyleConfig {
    var config = base
    config.width = width
    config.height = height
    return config
  }
}

import Foundation

/// Standard aspect ratio presets for comic panel and storyboard generation.
///
/// Dimensions are **platform-tiered**:
///
/// - **macOS** targets television resolution — each ratio's *desired* size is fit
///   inside a 3840×2160 4K UHD (Rec. 2020 / UHD-1) frame (≤ 8.3 MP). This is a
///   ceiling, not a guarantee: the size actually generated (``width``/``height``)
///   is clamped down per device via ``ResolutionClamp`` so the worst-case
///   attention buffer never exceeds the Metal `maxBufferLength` — a 4K frame on a
///   32 GB Mac would otherwise demand a single >20 GB allocation and abort
///   `mlx_eval` on the first denoising step. High-RAM Macs still render full 4K.
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

  /// The *desired* output width in pixels for this aspect ratio's platform tier,
  /// before any device-capability clamping. On macOS this is the 4K-class
  /// ceiling; see ``width`` for the value actually used.
  public var desiredWidth: Int {
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

  /// The *desired* output height in pixels for this aspect ratio's platform tier,
  /// before any device-capability clamping. See ``height``.
  public var desiredHeight: Int {
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

  /// The device-clamped output dimensions actually used for generation.
  ///
  /// On **macOS** the 4K-class ``desiredWidth``/``desiredHeight`` are scaled down
  /// (preserving aspect ratio, staying multiples of 16) so the worst-case
  /// attention buffer fits the Metal device's `maxBufferLength` — see
  /// ``ResolutionClamp``. On a high-RAM Mac this is a no-op and full 4K panels
  /// are produced; on a memory-constrained Mac the resolution steps down instead
  /// of crashing `mlx_eval` on the first step. **iOS** dimensions are already
  /// well within the per-buffer ceiling and are returned unclamped.
  public var dimensions: (width: Int, height: Int) {
    #if os(macOS)
      return ResolutionClamp.clampedDimensions(width: desiredWidth, height: desiredHeight)
    #else
      return (desiredWidth, desiredHeight)
    #endif
  }

  /// The output width in pixels for this aspect ratio, clamped to device
  /// capability. See ``dimensions``.
  public var width: Int { dimensions.width }

  /// The output height in pixels for this aspect ratio, clamped to device
  /// capability. See ``dimensions``.
  public var height: Int { dimensions.height }

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

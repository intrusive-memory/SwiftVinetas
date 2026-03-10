import Foundation

/// Standard aspect ratio presets for comic panel and storyboard generation.
///
/// All presets produce dimensions compatible with FLUX.2 Klein models,
/// using multiples of 64 pixels as required by the VAE.
public enum AspectRatio: String, Sendable, CaseIterable {
    /// Square format (1:1) — 1024×1024.
    case square

    /// Widescreen format (16:9) — 1344×768.
    case wide

    /// Ultra-wide cinematic format (2.4:1) — 1536×640.
    case ultrawide

    /// Portrait format (9:16) — 768×1344.
    case portrait

    /// Comic panel format (~3:2) — 1216×832.
    case panel

    /// Strip format (4:1) — 2048×512.
    case strip

    /// The output width in pixels for this aspect ratio.
    public var width: Int {
        switch self {
        case .square:     1024
        case .wide:       1344
        case .ultrawide:  1536
        case .portrait:    768
        case .panel:      1216
        case .strip:      2048
        }
    }

    /// The output height in pixels for this aspect ratio.
    public var height: Int {
        switch self {
        case .square:     1024
        case .wide:        768
        case .ultrawide:   640
        case .portrait:   1344
        case .panel:       832
        case .strip:       512
        }
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

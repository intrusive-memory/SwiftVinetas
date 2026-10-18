import Foundation

#if canImport(Metal)
  import Metal
#endif

/// Device-adaptive generation-resolution clamping.
///
/// The image-generation engines allocate a single attention-score buffer of
/// roughly `heads × tokens² × bytesPerScore`, where `tokens = (W / 16) × (H / 16)`
/// is the patchified latent sequence length (the VAE downsamples by 8 and the
/// DiT patchifies the latent by 2 → a `16`-pixel stride). That buffer grows with
/// the **square** of the pixel area, so a 4K-class macOS frame can demand a
/// single allocation larger than Metal's per-buffer ceiling
/// (`MTLDevice.maxBufferLength`) and the run aborts inside `mlx_eval` with
/// `[metal::malloc] Attempting to allocate … greater than the maximum allowed
/// buffer size …` — model load succeeds, generation crashes on the first step.
///
/// Concrete example that motivated this type: PixArt-Sigma **XL** (16 heads) at
/// macOS `.square` = 2160×2160 → `tokens = 135 × 135 = 18 225` →
/// `16 × 18 225² × 4 = 21 257 640 000` bytes, which exceeds a 20 100 448 256-byte
/// (`~18.7 GiB`) `maxBufferLength` on a 32 GB Mac. FLUX.2 (MMDiT, ~24 heads) is
/// worse still, so the clamp is calibrated to the **worst-case** head count.
///
/// ``clampedDimensions(width:height:maxBufferLengthBytes:)`` scales a desired
/// resolution down — preserving aspect ratio and keeping both edges multiples of
/// 16 — until the worst-case attention buffer fits a safety fraction of the
/// device's `maxBufferLength`. It is a no-op when the desired resolution already
/// fits, so high-RAM Macs keep full 4K panels while memory-constrained machines
/// transparently step down instead of crashing.
public enum ResolutionClamp: Sendable {

  // MARK: - Tunables

  /// Worst-case attention head count across all supported engines. PixArt-Sigma
  /// XL uses 16; FLUX.2 Klein's MMDiT uses ~24. Calibrating to the larger value
  /// keeps the clamp conservative for *every* model routed through an aspect
  /// ratio, since ``AspectRatio`` is model-agnostic.
  static let attentionHeadsWorstCase = 24

  /// Bytes per attention-score element. MLX computes scaled-dot-product
  /// attention scores in fp32 (4 bytes) — matched against the observed crash.
  static let scoreBytes = 4

  /// Fraction of `maxBufferLength` the score buffer is allowed to occupy. The
  /// half left over absorbs the Q/K/V projections, the attention output, and
  /// other transient buffers that coexist with the score matrix during eval.
  static let safetyFraction = 0.5

  /// Pixel stride between the output image and the patchified latent token grid
  /// (VAE ÷8 × DiT patchify ×2). Width and height must stay multiples of this.
  static let pixelsPerToken = 16

  /// Floor for either edge after clamping (a 16×16 token grid). Prevents a
  /// pathologically small `maxBufferLength` from collapsing the image to zero.
  static let minimumEdge = 256

  /// Fallback `maxBufferLength` used when no Metal device is available (e.g. a
  /// headless CI agent without a GPU). Chosen so a `.square` frame clamps to a
  /// ~1536-class resolution — safe on essentially any Apple Silicon GPU.
  static let fallbackMaxBufferLengthBytes: UInt64 = 16_000_000_000

  // MARK: - Device query

  /// The default Metal device's per-buffer allocation ceiling, in bytes.
  ///
  /// Cached on first access. Falls back to ``fallbackMaxBufferLengthBytes`` when
  /// `MTLCreateSystemDefaultDevice()` returns `nil`.
  public static let maxBufferLengthBytes: UInt64 = {
    #if canImport(Metal)
      if let device = MTLCreateSystemDefaultDevice() {
        return UInt64(device.maxBufferLength)
      }
    #endif
    return fallbackMaxBufferLengthBytes
  }()

  // MARK: - Pure clamping core (deterministic; testable with an explicit cap)

  /// The largest patchified token count (`(W/16) × (H/16)`) whose worst-case
  /// attention buffer fits ``safetyFraction`` of `maxBufferLengthBytes`.
  ///
  /// Solves `heads × tokens² × scoreBytes ≤ safetyFraction × cap` for `tokens`.
  public static func maxAttentionTokens(maxBufferLengthBytes cap: UInt64) -> Int {
    let usable = safetyFraction * Double(cap)
    let perToken = Double(attentionHeadsWorstCase * scoreBytes)
    let tokens = (usable / perToken).squareRoot()
    // 16×16 token floor mirrors ``minimumEdge``.
    return max((minimumEdge / pixelsPerToken) * (minimumEdge / pixelsPerToken), Int(tokens))
  }

  /// Clamps a desired `width × height` so the worst-case attention buffer fits
  /// `maxBufferLengthBytes`, preserving aspect ratio and snapping both edges down
  /// to multiples of ``pixelsPerToken``.
  ///
  /// A no-op (beyond 16-snapping) when the desired resolution already fits.
  ///
  /// - Parameters:
  ///   - width: Desired output width in pixels.
  ///   - height: Desired output height in pixels.
  ///   - cap: The device per-buffer ceiling to fit within. Defaults to
  ///     ``maxBufferLengthBytes``; pass an explicit value for deterministic tests.
  /// - Returns: A `(width, height)` pair, both multiples of 16 and ≥ ``minimumEdge``.
  public static func clampedDimensions(
    width: Int,
    height: Int,
    maxBufferLengthBytes cap: UInt64 = maxBufferLengthBytes
  ) -> (width: Int, height: Int) {
    guard width > 0, height > 0 else { return (width, height) }

    let stride = pixelsPerToken
    let desiredTokens = (width / stride) * (height / stride)
    let maxTokens = maxAttentionTokens(maxBufferLengthBytes: cap)

    guard desiredTokens > maxTokens else {
      // Already fits; just guarantee the 16-multiple invariant.
      return (snapDown(width), snapDown(height))
    }

    // Scale both edges by √(maxTokens / desiredTokens) — the score buffer is
    // quadratic in token count, so the linear edge scale is the square root.
    let scale = (Double(maxTokens) / Double(desiredTokens)).squareRoot()
    let clampedWidth = snapDown(Int(Double(width) * scale))
    let clampedHeight = snapDown(Int(Double(height) * scale))
    return (clampedWidth, clampedHeight)
  }

  /// Rounds `value` down to the nearest multiple of ``pixelsPerToken``, with a
  /// ``minimumEdge`` floor.
  private static func snapDown(_ value: Int) -> Int {
    max(minimumEdge, (value / pixelsPerToken) * pixelsPerToken)
  }
}

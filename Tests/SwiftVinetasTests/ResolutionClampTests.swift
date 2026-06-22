import Foundation
import Testing

@testable import SwiftVinetas

@Suite("ResolutionClamp Tests")
struct ResolutionClampTests {

  /// The 32 GB-Mac `maxBufferLength` that reproduced the original crash
  /// (`~18.7 GiB`). PixArt-Sigma XL `.square` (2160²) demanded 21,257,640,000 B
  /// against this ceiling and aborted `mlx_eval`.
  static let crashingCap: UInt64 = 20_100_448_256

  /// A ceiling large enough that no 4K-class frame ever needs clamping.
  static let hugeCap: UInt64 = 1 << 52

  /// Worst-case single attention-score buffer: `heads × tokens² × 4`.
  private func worstCaseBytes(width: Int, height: Int) -> UInt64 {
    let tokens = UInt64((width / 16) * (height / 16))
    return UInt64(ResolutionClamp.attentionHeadsWorstCase)
      * tokens * tokens
      * UInt64(ResolutionClamp.scoreBytes)
  }

  // MARK: - No-op when it already fits

  @Test("a desired size that already fits is returned unchanged")
  func noOpWhenFits() {
    let (w, h) = ResolutionClamp.clampedDimensions(
      width: 2160, height: 2160, maxBufferLengthBytes: Self.hugeCap)
    #expect(w == 2160)
    #expect(h == 2160)
  }

  @Test("iOS-tier sizes never clamp even against the crashing cap")
  func iOSTierNeverClamps() {
    // 1024×1024 → 64×64 = 4096 tokens → 24×4096²×4 ≈ 1.6 GB, well under the cap.
    let (w, h) = ResolutionClamp.clampedDimensions(
      width: 1024, height: 1024, maxBufferLengthBytes: Self.crashingCap)
    #expect(w == 1024)
    #expect(h == 1024)
  }

  // MARK: - Clamps oversized requests under the cap

  @Test("the original crashing case (2160² @ ~18.7 GiB) clamps to fit")
  func clampsTheCrashCase() {
    let (w, h) = ResolutionClamp.clampedDimensions(
      width: 2160, height: 2160, maxBufferLengthBytes: Self.crashingCap)
    #expect(w < 2160, "expected the 2160² square to be clamped down, got \(w)")
    #expect(w % 16 == 0)
    #expect(h % 16 == 0)
    #expect(w == h, "a square must stay square after clamping")
    // The whole point: the worst-case buffer must now fit the device ceiling.
    #expect(worstCaseBytes(width: w, height: h) <= Self.crashingCap)
  }

  @Test("every macOS 4K-class preset clamps under the crashing cap")
  func allMacPresetsClampUnderCap() {
    // (desiredWidth, desiredHeight) for the macOS tier.
    let presets: [(Int, Int)] = [
      (2160, 2160),  // square
      (3840, 2160),  // wide
      (3840, 1600),  // ultrawide
      (2160, 3840),  // portrait
      (3232, 2160),  // panel
      (3840, 960),  // strip
    ]
    for (dw, dh) in presets {
      let (w, h) = ResolutionClamp.clampedDimensions(
        width: dw, height: dh, maxBufferLengthBytes: Self.crashingCap)
      #expect(w % 16 == 0 && h % 16 == 0, "\(dw)×\(dh) → \(w)×\(h) not multiples of 16")
      #expect(w <= dw && h <= dh, "\(dw)×\(dh) → \(w)×\(h) grew")
      #expect(
        worstCaseBytes(width: w, height: h) <= Self.crashingCap,
        "\(dw)×\(dh) → \(w)×\(h) still exceeds the cap")
    }
  }

  // MARK: - Aspect ratio preservation

  @Test("clamping preserves the aspect ratio within rounding")
  func preservesAspectRatio() {
    let (w, h) = ResolutionClamp.clampedDimensions(
      width: 3840, height: 2160, maxBufferLengthBytes: Self.crashingCap)
    let desiredRatio = 3840.0 / 2160.0
    let clampedRatio = Double(w) / Double(h)
    // Independent 16-px snapping on each edge perturbs the ratio slightly.
    #expect(abs(clampedRatio - desiredRatio) < 0.05, "ratio drifted: \(clampedRatio)")
  }

  // MARK: - maxAttentionTokens monotonicity

  @Test("a larger buffer cap permits at least as many tokens")
  func maxTokensMonotonic() {
    let small = ResolutionClamp.maxAttentionTokens(maxBufferLengthBytes: Self.crashingCap)
    let large = ResolutionClamp.maxAttentionTokens(maxBufferLengthBytes: Self.crashingCap * 2)
    #expect(large >= small)
    #expect(small > 0)
  }

  // MARK: - Edge cases

  @Test("non-positive dimensions are returned unchanged")
  func nonPositivePassthrough() {
    let (w, h) = ResolutionClamp.clampedDimensions(
      width: 0, height: 0, maxBufferLengthBytes: Self.crashingCap)
    #expect(w == 0 && h == 0)
  }

  @Test("the real device reports a positive max buffer length")
  func realDeviceCapIsPositive() {
    #expect(ResolutionClamp.maxBufferLengthBytes > 0)
  }
}

import CoreGraphics
import Foundation

// MARK: - ImageQualityMetrics

/// Objective, descriptive quality metrics computed from a generated CGImage.
///
/// These metrics are **purely descriptive** — they make no claims about whether
/// an image is "good" or "garbage". Their purpose is to provide observable,
/// numeric data alongside saved fixture images so that empirical patterns can
/// be identified by human inspection or later automated rules.
///
/// Compare metrics from known-garbage runs against known-good runs to build
/// intuition about meaningful thresholds. Do not hard-code thresholds here.
struct ImageQualityMetrics: Codable, Sendable {

  // MARK: Dimensions

  /// Width of the image in pixels.
  let width: Int

  /// Height of the image in pixels.
  let height: Int

  // MARK: Degenerate-output flags

  /// `true` if every sampled pixel has R=0, G=0, B=0.
  let isAllBlack: Bool

  /// `true` if every sampled pixel has R=255, G=255, B=255.
  let isAllWhite: Bool

  // MARK: Color diversity

  /// Count of distinct packed-RGB values in a 5×5 evenly-spaced grid (25 samples).
  let distinctColors5x5: Int

  /// Count of distinct packed-RGB values in a 10×10 evenly-spaced grid (100 samples).
  let distinctColors10x10: Int

  // MARK: Luminance statistics  (BT.601 luma: 0.299R + 0.587G + 0.114B)

  /// Mean luma of all 100 sampled pixels (0–255 scale).
  let meanLuminance: Double

  /// Standard deviation of luma across all 100 sampled pixels.
  /// Low stdLuminance (< ~5) often indicates a washed-out or near-monochrome image.
  let stdLuminance: Double

  // MARK: Per-channel means

  /// Mean red channel value (0–255) across all 100 sampled pixels.
  let meanRed: Double

  /// Mean green channel value (0–255) across all 100 sampled pixels.
  let meanGreen: Double

  /// Mean blue channel value (0–255) across all 100 sampled pixels.
  let meanBlue: Double

  // MARK: Metadata

  /// ISO 8601 timestamp when these metrics were computed.
  let computedAt: String
}

// MARK: - FixtureSidecar

/// Generation provenance recorded alongside each fixture image.
struct FixtureGenerationInfo: Codable, Sendable {
  let prompt: String
  let modelID: String
  let seed: UInt64
  let steps: Int
  let guidanceScale: Float
  let width: Int
  let height: Int
  let durationSeconds: Double
  let generatedAt: String
}

/// JSON sidecar written next to each fixture PNG.
/// Contains both the generation parameters and the computed quality metrics.
struct FixtureSidecar: Codable, Sendable {
  let generation: FixtureGenerationInfo
  let metrics: ImageQualityMetrics
}

// MARK: - Metrics Computation

/// Compute descriptive quality metrics for a `CGImage`.
///
/// Renders the image into an 8-bit RGBA context and samples pixels at two
/// grid resolutions. All statistics derive from the sampled pixels only;
/// the full pixel buffer is not retained after return.
///
/// If `image.width` or `image.height` is zero, or if `CGContext` creation
/// fails, a zero-filled sentinel is returned (with `isAllBlack: true`).
///
/// - Parameter image: The `CGImage` to analyse.
/// - Returns: A populated `ImageQualityMetrics` instance.
func computeMetrics(for image: CGImage) -> ImageQualityMetrics {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  let now = formatter.string(from: Date())

  let w = image.width
  let h = image.height

  guard w > 0, h > 0 else {
    return ImageQualityMetrics(
      width: w, height: h,
      isAllBlack: true, isAllWhite: false,
      distinctColors5x5: 0, distinctColors10x10: 0,
      meanLuminance: 0, stdLuminance: 0,
      meanRed: 0, meanGreen: 0, meanBlue: 0,
      computedAt: now
    )
  }

  let bpp = 4
  let bpr = w * bpp
  var buf = [UInt8](repeating: 0, count: h * bpr)

  guard
    let ctx = CGContext(
      data: &buf,
      width: w, height: h,
      bitsPerComponent: 8, bytesPerRow: bpr,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    return ImageQualityMetrics(
      width: w, height: h,
      isAllBlack: false, isAllWhite: false,
      distinctColors5x5: 0, distinctColors10x10: 0,
      meanLuminance: 0, stdLuminance: 0,
      meanRed: 0, meanGreen: 0, meanBlue: 0,
      computedAt: now
    )
  }

  ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

  // Pixel sampler for an n×n evenly-spaced grid (includes corners).
  func rgb(col: Int, of nCols: Int, row: Int, of nRows: Int) -> (UInt8, UInt8, UInt8) {
    let x = min((col * (w - 1)) / max(nCols - 1, 1), w - 1)
    let y = min((row * (h - 1)) / max(nRows - 1, 1), h - 1)
    let off = y * bpr + x * bpp
    return (buf[off], buf[off + 1], buf[off + 2])
  }

  // 5×5 distinct color count
  var set5: Set<UInt32> = []
  for row in 0..<5 {
    for col in 0..<5 {
      let (r, g, b) = rgb(col: col, of: 5, row: row, of: 5)
      set5.insert((UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b))
    }
  }

  // 10×10 grid — all statistics derived from this set
  var set10: Set<UInt32> = []
  var allBlack = true
  var allWhite = true
  var reds: [Double] = []
  var greens: [Double] = []
  var blues: [Double] = []
  var lumas: [Double] = []

  for row in 0..<10 {
    for col in 0..<10 {
      let (r, g, b) = rgb(col: col, of: 10, row: row, of: 10)
      set10.insert((UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b))
      if r != 0 || g != 0 || b != 0 { allBlack = false }
      if r != 255 || g != 255 || b != 255 { allWhite = false }
      let rd = Double(r), gd = Double(g), bd = Double(b)
      reds.append(rd)
      greens.append(gd)
      blues.append(bd)
      lumas.append(0.299 * rd + 0.587 * gd + 0.114 * bd)
    }
  }

  let n = Double(lumas.count)
  let meanL = lumas.reduce(0, +) / n
  let stdL = (lumas.map { ($0 - meanL) * ($0 - meanL) }.reduce(0, +) / n).squareRoot()

  return ImageQualityMetrics(
    width: w, height: h,
    isAllBlack: allBlack, isAllWhite: allWhite,
    distinctColors5x5: set5.count,
    distinctColors10x10: set10.count,
    meanLuminance: meanL, stdLuminance: stdL,
    meanRed: reds.reduce(0, +) / n,
    meanGreen: greens.reduce(0, +) / n,
    meanBlue: blues.reduce(0, +) / n,
    computedAt: now
  )
}

// MARK: - Metric Observations (non-asserting)

/// Returns a list of human-readable observations about metric values that
/// may indicate undesirable output. These are **not assertions** — they are
/// printed to test output so a developer or agent can make a judgment call.
///
/// Each entry is prefixed with "⚠️ " to make it easy to spot in logs.
func metricObservations(_ m: ImageQualityMetrics) -> [String] {
  var obs: [String] = []
  if m.isAllBlack {
    obs.append("⚠️  ALL BLACK — degenerate output (VAE decode failure or zeroed latents)")
  }
  if m.isAllWhite {
    obs.append("⚠️  ALL WHITE — degenerate output (saturated latents or decoder fault)")
  }
  if m.distinctColors5x5 < 16 {
    obs.append("⚠️  Only \(m.distinctColors5x5)/25 distinct colors in 5×5 grid — may be monotone or near-single-color")
  }
  if m.distinctColors10x10 < 40 {
    obs.append("⚠️  Only \(m.distinctColors10x10)/100 distinct colors in 10×10 grid — low diversity")
  }
  if m.stdLuminance < 5.0 && !m.isAllBlack && !m.isAllWhite {
    obs.append("⚠️  stdLuminance=\(String(format: "%.2f", m.stdLuminance)) — very low contrast (washed-out or near-flat image)")
  }
  if m.meanLuminance < 5.0 {
    obs.append("⚠️  meanLuminance=\(String(format: "%.1f", m.meanLuminance)) — image is very dark")
  }
  if m.meanLuminance > 250.0 {
    obs.append("⚠️  meanLuminance=\(String(format: "%.1f", m.meanLuminance)) — image is very bright / near-white")
  }
  return obs
}

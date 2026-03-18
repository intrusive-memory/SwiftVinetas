import CoreGraphics
import MLX

// MARK: - Interpolation

/// Interpolation method for image resizing.
public enum Interpolation: Sendable {
  /// Bilinear interpolation (faster, slightly less sharp).
  case bilinear
  /// Bicubic interpolation (slower, sharper — recommended for ViT/DINOv2).
  case bicubic

  /// Maps to a CGInterpolationQuality.
  var cgQuality: CGInterpolationQuality {
    switch self {
    case .bilinear: return .medium
    case .bicubic: return .high
    }
  }
}

// MARK: - PreprocessingConfig

/// Preprocessing configuration presets for common vision models.
public struct PreprocessingConfig: Sendable {

  /// Input image size (assumes square: `inputSize x inputSize`).
  public let inputSize: Int

  /// Ratio used to determine the resize target before center-cropping.
  /// The shortest edge is scaled to `ceil(inputSize / cropRatio)`.
  /// Default is 224/256 ≈ 0.875 for ViT, 518/518 = 1.0 for DINOv2.
  public let cropRatio: Float

  /// Interpolation method used when resizing.
  public let interpolation: Interpolation

  /// Per-channel mean for normalization (ImageNet defaults).
  public let mean: [Float]

  /// Per-channel standard deviation for normalization (ImageNet defaults).
  public let std: [Float]

  public init(
    inputSize: Int,
    cropRatio: Float,
    interpolation: Interpolation,
    mean: [Float] = [0.485, 0.456, 0.406],
    std: [Float] = [0.229, 0.224, 0.225]
  ) {
    self.inputSize = inputSize
    self.cropRatio = cropRatio
    self.interpolation = interpolation
    self.mean = mean
    self.std = std
  }

  // MARK: Presets

  /// ViT-B/16 preset: 224 px input, bicubic, standard ImageNet normalisation.
  /// The resize target is ceil(224 / 0.875) = 256 before center crop.
  public static let vitB16 = PreprocessingConfig(
    inputSize: 224,
    cropRatio: 0.875,  // 224/256
    interpolation: .bicubic
  )

  /// DINOv2-B/14 preset: 518 px input, bicubic, standard ImageNet normalisation.
  /// cropRatio = 1.0 means resize shortest edge to 518, then crop to 518
  /// (no additional margin needed for DINOv2).
  public static let dinov2B14 = PreprocessingConfig(
    inputSize: 518,
    cropRatio: 1.0,
    interpolation: .bicubic
  )
}

// MARK: - ImagePreprocessor

/// Preprocesses `CGImage`s into `MLXArray` tensors suitable for ViT / DINOv2 inference.
///
/// The pipeline is:
/// 1. Resize so the shortest edge equals `ceil(inputSize / cropRatio)`.
/// 2. Center-crop to `inputSize × inputSize`.
/// 3. Convert pixels to `Float32` in [0, 1].
/// 4. Normalize per channel: `(pixel - mean) / std`.
/// 5. Add batch dimension → output shape `[1, H, W, 3]` (NHWC).
public struct ImagePreprocessor: Sendable {

  // MARK: Public properties

  public let inputSize: Int
  public let cropRatio: Float
  public let interpolation: Interpolation
  public let mean: [Float]
  public let std: [Float]

  // MARK: Init

  public init(
    inputSize: Int,
    cropRatio: Float,
    interpolation: Interpolation = .bicubic,
    mean: [Float] = [0.485, 0.456, 0.406],
    std: [Float] = [0.229, 0.224, 0.225]
  ) {
    self.inputSize = inputSize
    self.cropRatio = cropRatio
    self.interpolation = interpolation
    self.mean = mean
    self.std = std
  }

  /// Convenience initializer using a `PreprocessingConfig` preset.
  public init(config: PreprocessingConfig) {
    self.init(
      inputSize: config.inputSize,
      cropRatio: config.cropRatio,
      interpolation: config.interpolation,
      mean: config.mean,
      std: config.std
    )
  }

  // MARK: Preprocessing

  /// Preprocess a `CGImage` into an MLXArray ready for inference.
  ///
  /// - Parameter image: Source image (any size, any colour space).
  /// - Returns: `MLXArray` of shape `[1, inputSize, inputSize, 3]`, dtype `.float32`.
  public func preprocess(image: CGImage) -> MLXArray {
    // Step 1: Resize shortest edge to ceil(inputSize / cropRatio)
    let resized = resize(image: image)

    // Step 2: Center-crop to inputSize × inputSize
    let cropped = centerCrop(image: resized)

    // Step 3 & 4: Render to RGBA bytes, convert to float32 [0,1], normalize
    let array = toNormalizedMLXArray(image: cropped)

    return array
  }

  // MARK: Private helpers

  /// Computes the resize target: shortest edge → `ceil(inputSize / cropRatio)`.
  private func resize(image: CGImage) -> CGImage {
    let srcWidth = image.width
    let srcHeight = image.height

    // Target for the shortest edge
    let targetShortEdge = Int(ceil(Float(inputSize) / cropRatio))

    // Scale so that the shortest edge == targetShortEdge
    let scale: Float
    if srcWidth <= srcHeight {
      scale = Float(targetShortEdge) / Float(srcWidth)
    } else {
      scale = Float(targetShortEdge) / Float(srcHeight)
    }

    let targetWidth = Int(round(Float(srcWidth) * scale))
    let targetHeight = Int(round(Float(srcHeight) * scale))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue  // RGBX
    guard
      let ctx = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: targetWidth * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      // Fallback: return original (should never happen)
      return image
    }

    ctx.interpolationQuality = interpolation.cgQuality
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

    return ctx.makeImage() ?? image
  }

  /// Center-crops the image to `inputSize × inputSize`.
  private func centerCrop(image: CGImage) -> CGImage {
    let w = image.width
    let h = image.height
    let cropX = (w - inputSize) / 2
    let cropY = (h - inputSize) / 2
    let cropRect = CGRect(x: cropX, y: cropY, width: inputSize, height: inputSize)
    return image.cropping(to: cropRect) ?? image
  }

  /// Renders `image` into a flat UInt8 RGBA buffer, converts to Float32 [0,1],
  /// then normalizes and returns an MLXArray of shape `[1, H, W, 3]`.
  private func toNormalizedMLXArray(image: CGImage) -> MLXArray {
    let w = image.width
    let h = image.height
    let bytesPerPixel = 4  // RGBX
    let bytesPerRow = w * bytesPerPixel

    // Allocate raw buffer
    var pixelBuffer = [UInt8](repeating: 0, count: h * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

    guard
      let ctx = CGContext(
        data: &pixelBuffer,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      // Return a zero tensor on failure
      return MLXArray.zeros([1, h, w, 3])
    }

    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Convert RGBX → Float32 RGB, normalize
    // Output layout: [H, W, 3] interleaved
    let numPixels = w * h
    var floats = [Float](repeating: 0, count: numPixels * 3)

    let meanR = mean[0]
    let meanG = mean[1]
    let meanB = mean[2]
    let stdR = std[0]
    let stdG = std[1]
    let stdB = std[2]

    for idx in 0..<numPixels {
      let byteOffset = idx * 4
      let r = Float(pixelBuffer[byteOffset + 0]) / 255.0
      let g = Float(pixelBuffer[byteOffset + 1]) / 255.0
      let b = Float(pixelBuffer[byteOffset + 2]) / 255.0

      floats[idx * 3 + 0] = (r - meanR) / stdR
      floats[idx * 3 + 1] = (g - meanG) / stdG
      floats[idx * 3 + 2] = (b - meanB) / stdB
    }

    // Build MLXArray [H, W, 3] then add batch dim → [1, H, W, 3]
    let hwc = MLXArray(floats, [h, w, 3])
    return hwc.expandedDimensions(axis: 0)
  }
}

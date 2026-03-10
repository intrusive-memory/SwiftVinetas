import CoreGraphics
import MLX
import Testing

@testable import SwiftVinetas

// MARK: - Helpers

/// Creates a solid-color CGImage of the given size.
private func makeSolidColorImage(
    width: Int,
    height: Int,
    red: UInt8 = 255,
    green: UInt8 = 128,
    blue: UInt8 = 64
) -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow   = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for idx in 0 ..< (width * height) {
        pixels[idx * 4 + 0] = red
        pixels[idx * 4 + 1] = green
        pixels[idx * 4 + 2] = blue
        pixels[idx * 4 + 3] = 255
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

    guard
        let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let image = ctx.makeImage()
    else {
        fatalError("Failed to create test CGImage")
    }

    return image
}

// MARK: - Tests

@Suite("ImagePreprocessor")
struct ImagePreprocessorTests {

    // MARK: Output shape — ViT-B/16

    @Test("ViT-B/16 output shape is [1, 224, 224, 3]")
    func vitB16OutputShape() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        let image = makeSolidColorImage(width: 640, height: 480)

        let result = preprocessor.preprocess(image: image)

        #expect(result.shape == [1, 224, 224, 3],
                "Expected shape [1, 224, 224, 3], got \(result.shape)")
    }

    @Test("ViT-B/16 output shape from square input")
    func vitB16OutputShapeSquareInput() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        let image = makeSolidColorImage(width: 300, height: 300)

        let result = preprocessor.preprocess(image: image)

        #expect(result.shape == [1, 224, 224, 3])
    }

    @Test("ViT-B/16 output shape from portrait input")
    func vitB16OutputShapePortraitInput() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        let image = makeSolidColorImage(width: 200, height: 800)

        let result = preprocessor.preprocess(image: image)

        #expect(result.shape == [1, 224, 224, 3])
    }

    // MARK: Output shape — DINOv2-B/14

    @Test("DINOv2-B/14 output shape is [1, 518, 518, 3]")
    func dinov2B14OutputShape() {
        let preprocessor = ImagePreprocessor(config: .dinov2B14)
        let image = makeSolidColorImage(width: 800, height: 600)

        let result = preprocessor.preprocess(image: image)

        #expect(result.shape == [1, 518, 518, 3],
                "Expected shape [1, 518, 518, 3], got \(result.shape)")
    }

    @Test("DINOv2-B/14 output shape from small square input")
    func dinov2B14OutputShapeSmallInput() {
        let preprocessor = ImagePreprocessor(config: .dinov2B14)
        let image = makeSolidColorImage(width: 100, height: 100)

        let result = preprocessor.preprocess(image: image)

        #expect(result.shape == [1, 518, 518, 3])
    }

    // MARK: Value range after normalisation

    @Test("Normalised values are not all zero for a non-grey image")
    func normalizedValuesNotAllZero() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        // Use a bright red image — after normalization these should be non-zero
        let image = makeSolidColorImage(width: 256, height: 256, red: 255, green: 0, blue: 0)

        let result = preprocessor.preprocess(image: image)
        let flat = result.flattened()
        // Evaluate the array (MLX is lazy)
        MLX.eval(flat)

        // At least one value should be non-zero
        let values = flat.asArray(Float.self)
        let allZero = values.allSatisfy { $0 == 0.0 }
        #expect(!allZero, "Expected non-zero values after normalisation")
    }

    @Test("Normalised channel values are in a reasonable range")
    func normalizedValueRange() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        // White image: R=G=B=255 → (1.0 - mean) / std
        let image = makeSolidColorImage(width: 256, height: 256, red: 255, green: 255, blue: 255)

        let result = preprocessor.preprocess(image: image)
        MLX.eval(result)
        let values = result.asArray(Float.self)

        // For white pixels:
        //   R channel: (1.0 - 0.485) / 0.229 ≈  2.249
        //   G channel: (1.0 - 0.456) / 0.224 ≈  2.429
        //   B channel: (1.0 - 0.406) / 0.225 ≈  2.640
        // All values should be positive and finite
        for v in values {
            #expect(v.isFinite, "Expected finite normalised values, got \(v)")
            // Reasonable upper bound for normalized pixel values
            #expect(v > -10.0 && v < 10.0, "Normalised value out of expected range: \(v)")
        }

        // Spot-check red channel approximate value (~2.249)
        if let firstValue = values.first {
            #expect(firstValue > 2.0 && firstValue < 2.6,
                    "Expected ~2.249 for white R channel, got \(firstValue)")
        }
    }

    @Test("Normalised values for black image are negative")
    func normalizedBlackImageNegative() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        // Black image: R=G=B=0 → (0.0 - mean) / std — all negative
        let image = makeSolidColorImage(width: 256, height: 256, red: 0, green: 0, blue: 0)

        let result = preprocessor.preprocess(image: image)
        MLX.eval(result)
        let values = result.asArray(Float.self)

        for v in values {
            #expect(v < 0.0, "Expected negative normalised values for black image, got \(v)")
        }
    }

    // MARK: dtype

    @Test("Output dtype is float32")
    func outputDtype() {
        let preprocessor = ImagePreprocessor(config: .vitB16)
        let image = makeSolidColorImage(width: 256, height: 256)

        let result = preprocessor.preprocess(image: image)

        #expect(result.dtype == .float32, "Expected float32, got \(result.dtype)")
    }

    // MARK: Configuration presets

    @Test("PreprocessingConfig.vitB16 has correct inputSize")
    func vitB16ConfigInputSize() {
        #expect(PreprocessingConfig.vitB16.inputSize == 224)
    }

    @Test("PreprocessingConfig.vitB16 has bicubic interpolation")
    func vitB16ConfigInterpolation() {
        if case .bicubic = PreprocessingConfig.vitB16.interpolation {
            // pass
        } else {
            Issue.record("Expected bicubic interpolation for ViT-B/16")
        }
    }

    @Test("PreprocessingConfig.dinov2B14 has correct inputSize")
    func dinov2B14ConfigInputSize() {
        #expect(PreprocessingConfig.dinov2B14.inputSize == 518)
    }

    @Test("PreprocessingConfig.dinov2B14 has bicubic interpolation")
    func dinov2B14ConfigInterpolation() {
        if case .bicubic = PreprocessingConfig.dinov2B14.interpolation {
            // pass
        } else {
            Issue.record("Expected bicubic interpolation for DINOv2-B/14")
        }
    }

    @Test("Default ImageNet mean values are correct")
    func defaultMeanValues() {
        let config = PreprocessingConfig.vitB16
        #expect(abs(config.mean[0] - 0.485) < 1e-6)
        #expect(abs(config.mean[1] - 0.456) < 1e-6)
        #expect(abs(config.mean[2] - 0.406) < 1e-6)
    }

    @Test("Default ImageNet std values are correct")
    func defaultStdValues() {
        let config = PreprocessingConfig.vitB16
        #expect(abs(config.std[0] - 0.229) < 1e-6)
        #expect(abs(config.std[1] - 0.224) < 1e-6)
        #expect(abs(config.std[2] - 0.225) < 1e-6)
    }
}

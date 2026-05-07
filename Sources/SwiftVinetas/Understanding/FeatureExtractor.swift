import CoreGraphics
import Foundation
import ImageIO
import MLX
import MLXNN
import SwiftAcervo

// MARK: - FeatureExtractor

/// On-device feature extractor using DINOv2-B/14 weights from mlx-vision/vit_base_patch14_518.dinov2-mlxim.
///
/// Uses `VisionTransformer` with `numClasses: 0` (no classification head) to extract
/// the CLS token embedding as a 768-dimensional feature vector.
///
/// Weights are downloaded on first use via SwiftAcervo and cached at
/// `~/Library/SharedModels/`. Subsequent calls reuse the cached model instance.
public actor FeatureExtractor {

  // MARK: - Constants

  /// Vinetas-owned component ID for the DINOv2-B/14 feature extractor.
  static let componentId = "dinov2-vit-base-patch14-518"

  // MARK: - Shared instance

  /// The shared singleton feature extractor.
  public static let shared = FeatureExtractor()

  // MARK: - State

  private var model: VisionTransformer?
  private let preprocessor = ImagePreprocessor(config: .dinov2B14)

  // MARK: - Init

  private init() {}

  // MARK: - Public API

  /// Extract a 768-dimensional feature vector from an image using DINOv2-B/14.
  ///
  /// Downloads model weights on the first call (idempotent). The model is then cached
  /// in memory for subsequent calls.
  ///
  /// - Parameter image: The image to extract features from.
  /// - Returns: Array of 768 Float values representing the CLS token embedding.
  /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
  ///           `VinetasError.modelNotFound` if the weight file is missing post-download,
  ///           `VinetasError.generationFailed` for any runtime error.
  public func extractFeatures(from image: CGImage) async throws -> [Float] {
    let vitModel = try await loadModelIfNeeded()

    // Preprocess: CGImage -> [1, 518, 518, 3] MLXArray
    let tensor = preprocessor.preprocess(image: image)

    // Forward pass -> CLS token embedding [1, 768]
    let output = vitModel(tensor)

    // Extract the CLS token (first row): [768]
    let clsToken = output[0]

    // Convert to Swift Float array
    return clsToken.asArray(Float.self)
  }

  /// Extract a 768-dimensional feature vector from an image loaded from a file URL.
  ///
  /// - Parameter url: File URL to the image (JPEG, PNG, HEIC, etc.).
  /// - Returns: Array of 768 Float values representing the CLS token embedding.
  /// - Throws: `VinetasError.generationFailed` if the image cannot be loaded,
  ///           plus any errors from `extractFeatures(from:)`.
  public func extractFeatures(from url: URL) async throws -> [Float] {
    guard let cgImage = loadCGImage(from: url) else {
      throw VinetasError.generationFailed("Could not load image from \(url.path)")
    }
    return try await extractFeatures(from: cgImage)
  }

  // MARK: - Private helpers

  /// Load and cache the DINOv2-B/14 model. Returns the cached model on subsequent calls.
  private func loadModelIfNeeded() async throws -> VisionTransformer {
    if let existing = model {
      return existing
    }

    // Lazily register the component the first time the singleton is exercised.
    // Acervo.register is idempotent — safe to call on every first use.
    Acervo.register(
      ComponentDescriptor(
        id: Self.componentId,
        type: .backbone,
        displayName: "DINOv2-B/14 518px",
        repoId: "mlx-vision/vit_base_patch14_518.dinov2-mlxim",
        minimumMemoryBytes: 0
      ))

    // Ensure weights are downloaded via component-keyed API
    do {
      try await Acervo.ensureComponentReady(Self.componentId, progress: { _ in })
    } catch {
      throw VinetasError.downloadFailed(
        "Failed to download DINOv2-B/14 weights for component \(Self.componentId): \(error.localizedDescription)"
      )
    }

    // Build DINOv2-B/14 model (no classification head)
    let vit = VisionTransformer(
      imageSize: 518,
      patchSize: 14,
      numClasses: 0,
      dim: 768,
      depth: 12,
      numHeads: 12
    )

    // Resolve the safetensors URL via scoped component handle, then load outside the closure.
    // MLXArray is not Sendable, so loadArrays must be called after withComponentAccess returns.
    let weightsURL: URL
    do {
      weightsURL = try await AcervoManager.shared.withComponentAccess(Self.componentId) { handle in
        try handle.url(matching: ".safetensors")
      }
    } catch {
      throw VinetasError.modelNotFound(
        "Could not locate .safetensors for component \(Self.componentId): \(error.localizedDescription)"
      )
    }

    let weights: [String: MLXArray]
    do {
      weights = try loadArrays(url: weightsURL)
    } catch {
      throw VinetasError.generationFailed(
        "Failed to load weights for component \(Self.componentId): \(error.localizedDescription)"
      )
    }

    // Apply weights to the model
    var updates: [String: MLXArray] = [:]
    for (key, value) in weights {
      updates[key] = value
    }
    vit.update(parameters: ModuleParameters.unflattened(updates))

    // Evaluate parameters and set to inference mode
    eval(vit)
    vit.train(false)

    self.model = vit
    return vit
  }

  /// Load a CGImage from a file URL using ImageIO.
  private func loadCGImage(from url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

// MARK: - Cosine Similarity

/// Compute the cosine similarity between two Float vectors.
///
/// Returns a value in the range `[-1, 1]` where:
/// - `1.0` indicates identical direction
/// - `0.0` indicates orthogonal (perpendicular) vectors
/// - `-1.0` indicates opposite direction
///
/// If either vector has zero magnitude, returns `0.0`.
///
/// - Parameters:
///   - a: First feature vector.
///   - b: Second feature vector.
/// - Returns: Cosine similarity as a Float.
public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
  guard a.count == b.count, !a.isEmpty else { return 0.0 }

  var dotProduct: Float = 0.0
  var magnitudeA: Float = 0.0
  var magnitudeB: Float = 0.0

  for i in 0..<a.count {
    dotProduct += a[i] * b[i]
    magnitudeA += a[i] * a[i]
    magnitudeB += b[i] * b[i]
  }

  let denominator = magnitudeA.squareRoot() * magnitudeB.squareRoot()

  guard denominator > 0 else { return 0.0 }

  return dotProduct / denominator
}

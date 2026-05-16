import CoreGraphics
import Foundation
import ImageIO
import MLX
import MLXNN
import SwiftAcervo
import Tuberia

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

  // Reporter is propagated via VinetasClient.setTelemetry → FeatureExtractor.shared.setTelemetry
  // — see OQ-3 MARK in Vinetas.swift (REQUIREMENTS §5.5, long-lived singleton pattern).
  /// Vinetas telemetry reporter, propagated from
  /// ``VinetasClient/setTelemetry(_:)`` per OQ-3 (REQUIREMENTS §5.5).
  /// The one documented `TuberiaTensorStat` invocation is gated on this being non-nil.
  private var telemetry: (any VinetasTelemetryReporter)?

  // MARK: - Init

  private init() {}

  // MARK: - Telemetry

  /// Install (or clear) the telemetry reporter on this singleton.
  /// Called from ``VinetasClient/setTelemetry(_:)`` because
  /// ``FeatureExtractor`` is not reachable through ``EngineRouter``.
  public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
    self.telemetry = reporter
  }

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

    // --- Telemetry: featureExtractionStart ---
    let imageDims = [image.width, image.height]
    await telemetry?.capture(.featureExtractionStart(imageDims: imageDims))
    let extractionStart = Date()

    // Forward pass -> CLS token embedding [1, 768]
    let output = vitModel(tensor)

    // Extract the CLS token (first row): [768]
    let clsToken = output[0]

    // --- Telemetry: featureExtractionComplete ---
    // Compute exactly one TuberiaTensorStat per extract — documented exception to hot-path
    // discipline per REQUIREMENTS §6. Guard ensures zero cost when telemetry is off.
    if let reporter = telemetry {
      let featureStat = TuberiaTensorStat.sample(clsToken)
      let extractionDuration = Date().timeIntervalSince(extractionStart)
      await reporter.capture(
        .featureExtractionComplete(
          featureDim: clsToken.shape.last ?? 0,
          featureStat: featureStat,
          durationSeconds: extractionDuration
        ))
    }

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
      await telemetry?.capture(
        .errorThrown(
          phase: .featureExtraction,
          errorDescription: "Could not load image from \(url.path)"
        ))
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
      let description =
        "Failed to download DINOv2-B/14 weights for component \(Self.componentId): \(error.localizedDescription)"
      await telemetry?.capture(
        .errorThrown(phase: .featureExtraction, errorDescription: description))
      throw VinetasError.downloadFailed(description)
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
      let description =
        "Could not locate .safetensors for component \(Self.componentId): \(error.localizedDescription)"
      await telemetry?.capture(
        .errorThrown(phase: .featureExtraction, errorDescription: description))
      throw VinetasError.modelNotFound(description)
    }

    let weights: [String: MLXArray]
    do {
      weights = try loadArrays(url: weightsURL)
    } catch {
      let description =
        "Failed to load weights for component \(Self.componentId): \(error.localizedDescription)"
      await telemetry?.capture(
        .errorThrown(phase: .featureExtraction, errorDescription: description))
      throw VinetasError.generationFailed(description)
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

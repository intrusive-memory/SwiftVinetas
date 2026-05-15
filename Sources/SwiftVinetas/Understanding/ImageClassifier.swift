import CoreGraphics
import Foundation
import ImageIO
import MLX
import MLXNN
import SwiftAcervo

// MARK: - ImageClassifier

/// On-device image classifier using ViT-B/16 weights from mlx-vision/vit_base_patch16_224-mlxim.
///
/// Uses `VisionTransformer` with 1000 ImageNet-1K output classes and `ImagePreprocessor`
/// with the `.vitB16` preset (224×224 input, bicubic interpolation, ImageNet normalization).
///
/// Weights are downloaded on first use via SwiftAcervo and cached at
/// `~/Library/SharedModels/`. Subsequent calls reuse the cached model instance.
public actor ImageClassifier {

  // MARK: - Constants

  /// Vinetas-owned component ID for the ViT-B/16 classifier.
  static let componentId = "vit-base-patch16-224-imagenet1k"

  // MARK: - Shared instance

  /// The shared singleton classifier.
  public static let shared = ImageClassifier()

  // MARK: - State

  private var model: VisionTransformer?
  private let preprocessor = ImagePreprocessor(config: .vitB16)

  /// Vinetas telemetry reporter, propagated from
  /// ``VinetasClient/setTelemetry(_:)`` per OQ-3 (REQUIREMENTS §5.5). Stored
  /// only; emission sites land in Sortie 5.
  private var telemetry: (any VinetasTelemetryReporter)?

  // MARK: - Init

  private init() {}

  // MARK: - Telemetry

  /// Install (or clear) the telemetry reporter on this singleton.
  /// Called from ``VinetasClient/setTelemetry(_:)`` because
  /// ``ImageClassifier`` is not reachable through ``EngineRouter``.
  public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
    self.telemetry = reporter
  }

  // MARK: - Public API

  /// Classify an image and return the top-K predictions sorted by confidence (descending).
  ///
  /// Downloads model weights on the first call (idempotent). The model is then cached
  /// in memory for subsequent calls.
  ///
  /// - Parameters:
  ///   - image: The image to classify.
  ///   - topK: Maximum number of classifications to return (default 5).
  /// - Returns: Array of `Classification` sorted by confidence, highest first.
  /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
  ///           `VinetasError.modelNotFound` if the weight file is missing post-download,
  ///           `VinetasError.generationFailed` for any runtime error.
  public func classify(image: CGImage, topK: Int = 5) async throws -> [Classification] {
    let vitModel = try await loadModelIfNeeded()

    // Preprocess: CGImage -> [1, 224, 224, 3] MLXArray
    let tensor = preprocessor.preprocess(image: image)

    // Forward pass -> logits [1, 1000]
    let logits = vitModel(tensor)

    // Softmax -> probabilities [1, 1000]
    let probs = softmax(logits, axis: -1)

    // Convert to Swift array
    let probArray = probs.flattened().asArray(Float.self)

    // Build Classification results
    var results = probArray.enumerated().map { idx, prob in
      Classification(
        label: idx < ImageNetLabels.labels.count ? ImageNetLabels.labels[idx] : "class_\(idx)",
        confidence: prob
      )
    }

    // Sort by confidence descending and take top-K
    results.sort()
    return Array(results.prefix(topK))
  }

  /// Classify an image loaded from a file URL and return the top-K predictions.
  ///
  /// - Parameters:
  ///   - url: File URL to the image (JPEG, PNG, HEIC, etc.).
  ///   - topK: Maximum number of classifications to return (default 5).
  /// - Returns: Array of `Classification` sorted by confidence, highest first.
  /// - Throws: `VinetasError.generationFailed` if the image cannot be loaded,
  ///           plus any errors from `classify(image:topK:)`.
  public func classify(file url: URL, topK: Int = 5) async throws -> [Classification] {
    guard let cgImage = loadCGImage(from: url) else {
      throw VinetasError.generationFailed("Could not load image from \(url.path)")
    }
    return try await classify(image: cgImage, topK: topK)
  }

  // MARK: - Private helpers

  /// Load and cache the ViT-B/16 model. Returns the cached model on subsequent calls.
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
        displayName: "ViT-B/16 ImageNet-1K",
        repoId: "mlx-vision/vit_base_patch16_224-mlxim",
        minimumMemoryBytes: 0
      ))

    // Ensure weights are downloaded via component-keyed API
    do {
      try await Acervo.ensureComponentReady(Self.componentId, progress: { _ in })
    } catch {
      throw VinetasError.downloadFailed(
        "Failed to download ViT-B/16 weights for component \(Self.componentId): \(error.localizedDescription)"
      )
    }

    // Build ViT-B/16 model (1000 ImageNet classes)
    let vit = VisionTransformer(
      imageSize: 224,
      patchSize: 16,
      numClasses: 1000,
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

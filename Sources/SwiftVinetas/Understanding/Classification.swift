/// A classification result containing a label and its confidence score.
///
/// Used as the output type for image classification via ViT-B/16.
/// Confidence scores are in the range [0, 1] and represent softmax probabilities.
@frozen public struct Classification: Sendable, Codable {

  /// The predicted class label (e.g., "golden retriever").
  public let label: String

  /// The confidence score for this classification, in the range [0, 1].
  public let confidence: Float

  /// Create a new classification result.
  ///
  /// - Parameters:
  ///   - label: The predicted class label.
  ///   - confidence: The confidence score (softmax probability).
  public init(label: String, confidence: Float) {
    self.label = label
    self.confidence = confidence
  }
}

extension Classification: Comparable {
  /// Classifications are compared by confidence in descending order,
  /// so higher confidence sorts first.
  public static func < (lhs: Classification, rhs: Classification) -> Bool {
    lhs.confidence > rhs.confidence
  }
}

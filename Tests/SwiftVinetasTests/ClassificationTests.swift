import Foundation
import Testing

@testable import SwiftVinetas

@Suite("Classification Tests")
struct ClassificationTests {

  // MARK: - Sendable Conformance

  @Test("Classification is Sendable across actor boundaries")
  func sendableConformance() async {
    let classification = Classification(label: "golden retriever", confidence: 0.95)

    // Send across an actor boundary to verify Sendable conformance
    let result = await TransferActor.transfer(classification)

    #expect(result.label == "golden retriever")
    #expect(result.confidence == 0.95)
  }

  // MARK: - Codable Round-Trip

  @Test("Classification encodes and decodes via JSON")
  func codableRoundTrip() throws {
    let original = Classification(label: "tabby cat", confidence: 0.87)

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(Classification.self, from: data)

    #expect(decoded.label == original.label)
    #expect(decoded.confidence == original.confidence)
  }

  @Test("Classification array encodes and decodes via JSON")
  func codableArrayRoundTrip() throws {
    let originals = [
      Classification(label: "golden retriever", confidence: 0.85),
      Classification(label: "labrador", confidence: 0.10),
      Classification(label: "poodle", confidence: 0.05),
    ]

    let encoder = JSONEncoder()
    let data = try encoder.encode(originals)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode([Classification].self, from: data)

    #expect(decoded.count == 3)
    #expect(decoded[0].label == "golden retriever")
    #expect(decoded[1].label == "labrador")
    #expect(decoded[2].label == "poodle")
  }

  // MARK: - Sorting by Confidence

  @Test("Classifications sort by confidence descending")
  func sortByConfidenceDescending() {
    let classifications = [
      Classification(label: "poodle", confidence: 0.05),
      Classification(label: "golden retriever", confidence: 0.85),
      Classification(label: "labrador", confidence: 0.10),
    ]

    let sorted = classifications.sorted()

    #expect(sorted[0].label == "golden retriever")
    #expect(sorted[0].confidence == 0.85)
    #expect(sorted[1].label == "labrador")
    #expect(sorted[1].confidence == 0.10)
    #expect(sorted[2].label == "poodle")
    #expect(sorted[2].confidence == 0.05)
  }

  @Test("Classifications with equal confidence maintain stable order")
  func equalConfidenceSorting() {
    let classifications = [
      Classification(label: "cat", confidence: 0.5),
      Classification(label: "dog", confidence: 0.5),
    ]

    let sorted = classifications.sorted()

    // Both have equal confidence; sorted should contain both
    #expect(sorted.count == 2)
    #expect(sorted[0].confidence == 0.5)
    #expect(sorted[1].confidence == 0.5)
  }

  @Test("Empty classification array sorts without error")
  func emptyArraySorting() {
    let classifications: [Classification] = []
    let sorted = classifications.sorted()
    #expect(sorted.isEmpty)
  }

  @Test("Single classification sorts without error")
  func singleElementSorting() {
    let classifications = [Classification(label: "cat", confidence: 0.99)]
    let sorted = classifications.sorted()
    #expect(sorted.count == 1)
    #expect(sorted[0].label == "cat")
  }
}

/// A simple actor used to verify Sendable conformance by transferring values across actor boundaries.
private actor TransferActor {
  static func transfer(_ classification: Classification) -> Classification {
    classification
  }
}

import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VerificationReport Tests

@Suite("VerificationReport")
struct VerificationReportTests {

  @Test("Report has expected properties")
  func reportHasExpectedProperties() {
    let report = VerificationReport(
      pairs: [
        (view1: "front", view2: "left", similarity: 0.85),
        (view1: "front", view2: "right", similarity: 0.82),
      ],
      passed: true,
      threshold: 0.6,
      averageSimilarity: 0.835
    )

    #expect(report.pairs.count == 2)
    #expect(report.passed == true)
    #expect(report.threshold == 0.6)
    #expect(report.averageSimilarity == 0.835)
  }

  @Test("Report passes when all pairs meet threshold")
  func reportPassesWhenAllAboveThreshold() {
    let threshold: Float = 0.6
    let pairs: [(view1: String, view2: String, similarity: Float)] = [
      (view1: "front", view2: "left", similarity: 0.75),
      (view1: "front", view2: "right", similarity: 0.80),
      (view1: "front", view2: "back", similarity: 0.65),
      (view1: "left", view2: "right", similarity: 0.90),
      (view1: "left", view2: "back", similarity: 0.70),
      (view1: "right", view2: "back", similarity: 0.60),
    ]

    let allAbove = pairs.allSatisfy { $0.similarity >= threshold }
    let avg = pairs.map(\.similarity).reduce(0, +) / Float(pairs.count)

    let report = VerificationReport(
      pairs: pairs,
      passed: allAbove,
      threshold: threshold,
      averageSimilarity: avg
    )

    #expect(report.passed == true)
    #expect(report.averageSimilarity > 0)
  }

  @Test("Report fails when any pair is below threshold")
  func reportFailsWhenAnyBelowThreshold() {
    let threshold: Float = 0.6
    let pairs: [(view1: String, view2: String, similarity: Float)] = [
      (view1: "front", view2: "left", similarity: 0.75),
      (view1: "front", view2: "right", similarity: 0.80),
      (view1: "front", view2: "back", similarity: 0.59),  // Below threshold
      (view1: "left", view2: "right", similarity: 0.90),
      (view1: "left", view2: "back", similarity: 0.70),
      (view1: "right", view2: "back", similarity: 0.65),
    ]

    let allAbove = pairs.allSatisfy { $0.similarity >= threshold }
    let avg = pairs.map(\.similarity).reduce(0, +) / Float(pairs.count)

    let report = VerificationReport(
      pairs: pairs,
      passed: allAbove,
      threshold: threshold,
      averageSimilarity: avg
    )

    #expect(report.passed == false)
    #expect(report.averageSimilarity > 0)
  }

  @Test("Report with exact threshold value passes")
  func reportPassesAtExactThreshold() {
    let threshold: Float = 0.6
    let pairs: [(view1: String, view2: String, similarity: Float)] = [
      (view1: "front", view2: "back", similarity: 0.6)
    ]

    let allAbove = pairs.allSatisfy { $0.similarity >= threshold }

    let report = VerificationReport(
      pairs: pairs,
      passed: allAbove,
      threshold: threshold,
      averageSimilarity: 0.6
    )

    #expect(report.passed == true)
  }

  @Test("Empty pairs results in passed report")
  func emptyPairsReportPasses() {
    let report = VerificationReport(
      pairs: [],
      passed: true,
      threshold: 0.6,
      averageSimilarity: 0.0
    )

    #expect(report.passed == true)
    #expect(report.pairs.isEmpty)
  }

  @Test("Pair view names are accessible")
  func pairViewNamesAccessible() {
    let pairs: [(view1: String, view2: String, similarity: Float)] = [
      (view1: "front", view2: "left", similarity: 0.75)
    ]

    let report = VerificationReport(
      pairs: pairs,
      passed: true,
      threshold: 0.6,
      averageSimilarity: 0.75
    )

    #expect(report.pairs[0].view1 == "front")
    #expect(report.pairs[0].view2 == "left")
    #expect(report.pairs[0].similarity == 0.75)
  }
}

// MARK: - Vinetas.verifyCharacter API Compilation Tests

@Suite("Vinetas verifyCharacter API")
struct VinetasVerifyCharacterAPITests {

  @Test("verifyCharacter signature compiles")
  func verifyCharacterSignatureCompiles() {
    // Verify that the method reference compiles with the expected signature.
    // This does NOT call the method (which requires disk I/O and model weights).
    let _verifyFn: (Character, Float) async throws -> VerificationReport = Vinetas.verifyCharacter
    _ = _verifyFn
  }

  @Test("VerificationReport is Sendable")
  func verificationReportIsSendable() {
    // Verify VerificationReport conforms to Sendable at compile time.
    let report = VerificationReport(
      pairs: [],
      passed: true,
      threshold: 0.6,
      averageSimilarity: 0.0
    )
    let sendable: any Sendable = report
    _ = sendable
  }
}

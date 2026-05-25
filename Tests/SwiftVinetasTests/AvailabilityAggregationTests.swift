import Foundation
import SwiftAcervo
import Testing

@testable import SwiftVinetas

@Suite("AvailabilityAggregation Tests")
struct AvailabilityAggregationTests {

  private func entry(_ id: String, _ state: ModelAvailability) -> AvailabilityAggregation.Entry {
    AvailabilityAggregation.Entry(componentId: id, state: state)
  }

  @Test("Empty input aggregates to .notAvailable")
  func emptyInputNotAvailable() {
    #expect(AvailabilityAggregation.aggregate([]) == .notAvailable)
  }

  @Test("All .available aggregates to .available")
  func allAvailable() {
    let result = AvailabilityAggregation.aggregate([
      entry("a", .available),
      entry("b", .available),
      entry("c", .available),
    ])
    #expect(result == .available)
  }

  @Test("All .notAvailable aggregates to .notAvailable")
  func allNotAvailable() {
    let result = AvailabilityAggregation.aggregate([
      entry("a", .notAvailable),
      entry("b", .notAvailable),
    ])
    #expect(result == .notAvailable)
  }

  @Test("Some .available + some missing → .partial(missing:)")
  func partialMissing() {
    let result = AvailabilityAggregation.aggregate([
      entry("a", .available),
      entry("b", .notAvailable),
      entry("c", .partial(missing: ["x"])),
    ])
    if case .partial(let missing) = result {
      #expect(missing == ["b", "c"])
    } else {
      Issue.record("Expected .partial, got \(result)")
    }
  }

  @Test("Any .downloading propagates as .downloading(weightedAverage)")
  func anyDownloadingPropagates() {
    // Two components: one fully available (1.0), one half downloaded (0.5).
    // Average = 0.75.
    let result = AvailabilityAggregation.aggregate([
      entry("a", .available),
      entry("b", .downloading(progress: 0.5)),
    ])
    if case .downloading(let progress) = result {
      #expect(abs(progress - 0.75) < 1e-9)
    } else {
      Issue.record("Expected .downloading, got \(result)")
    }
  }

  @Test("Downloading + missing component still surfaces as .downloading")
  func downloadingWithMissing() {
    // .notAvailable contributes 0, .downloading(0.6) contributes 0.6.
    // Average = 0.3.
    let result = AvailabilityAggregation.aggregate([
      entry("a", .downloading(progress: 0.6)),
      entry("b", .notAvailable),
    ])
    if case .downloading(let progress) = result {
      #expect(abs(progress - 0.3) < 1e-9)
    } else {
      Issue.record("Expected .downloading, got \(result)")
    }
  }
}

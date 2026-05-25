import Foundation
import SwiftAcervo

/// Aggregates per-component ``ModelAvailability`` values into a single
/// model-level state.
///
/// Engines that compose multiple Acervo repos into one logical model
/// (``PixArtEngine``, ``Flux2Engine``) query Acervo per component and then
/// call ``aggregate(_:)`` to produce the ``ModelAvailability`` returned by
/// ``ImageGenerationEngine/availability(_:)``.
///
/// Rules (mirror ``SwiftAcervo/AvailabilityAggregator``):
/// - Empty input → ``ModelAvailability/notAvailable``
/// - Every component ``ModelAvailability/available`` →
///   ``ModelAvailability/available``
/// - At least one component ``ModelAvailability/downloading(progress:)`` →
///   ``ModelAvailability/downloading(progress:)`` with the simple average of
///   per-component contributions (`.available` = 1.0, `.downloading` = p,
///   `.partial`/`.notAvailable` = 0.0)
/// - No download in flight, but at least one component fully `.available`
///   and at least one missing → ``ModelAvailability/partial(missing:)`` with
///   the component identifiers of the missing pieces
/// - Otherwise → ``ModelAvailability/notAvailable``
enum AvailabilityAggregation {

  struct Entry {
    let componentId: String
    let state: ModelAvailability
  }

  static func aggregate(_ entries: [Entry]) -> ModelAvailability {
    guard !entries.isEmpty else { return .notAvailable }

    var allAvailable = true
    var anyDownloading = false
    var anyAvailable = false
    var missing: [String] = []
    var progressSum: Double = 0

    for entry in entries {
      switch entry.state {
      case .available:
        anyAvailable = true
        progressSum += 1.0
      case .downloading(let progress):
        allAvailable = false
        anyDownloading = true
        progressSum += progress
      case .partial:
        allAvailable = false
        missing.append(entry.componentId)
      case .notAvailable:
        allAvailable = false
        missing.append(entry.componentId)
      }
    }

    if allAvailable { return .available }
    if anyDownloading {
      let avg = progressSum / Double(entries.count)
      return .downloading(progress: avg)
    }
    if anyAvailable && !missing.isEmpty {
      return .partial(missing: missing)
    }
    return .notAvailable
  }
}

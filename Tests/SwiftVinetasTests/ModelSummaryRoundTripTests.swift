import Foundation
import Testing

@testable import SwiftVinetas

/// Proves that the engine-free `ModelSummary` statics equal what the concrete
/// engine descriptors report, and that the summaries' CLI names match the
/// deprecated `VinetasModel` raw values one for one.
@Suite
struct ModelSummaryRoundTripTests {

  @Test
  func klein4BDescriptorSummaryEqualsStatic() {
    #expect(Flux2ModelDescriptor.klein4B.summary == ModelSummary.klein4B)
  }

  @Test
  func sigmaXLDescriptorSummaryEqualsStatic() {
    #expect(PixArtModelDescriptor.sigmaXL.summary == ModelSummary.pixartSigmaXL)
  }

  @Test
  func cliNamesMatchVinetasModelRawValues() {
    let legacy = Self.legacyModelRawValues()
    let summaries = ModelSummary.all.map(\.cliName)
    for name in summaries {
      #expect(legacy.contains(name), "\(name) has no VinetasModel case")
    }
    for raw in legacy {
      #expect(summaries.contains(raw), "VinetasModel.\(raw) has no ModelSummary")
    }
  }

  /// Wraps the one deprecated `VinetasModel` read so its warning stays local.
  @available(*, deprecated)
  private static func legacyModelRawValues() -> [String] {
    VinetasModel.allCases.map(\.rawValue)
  }
}

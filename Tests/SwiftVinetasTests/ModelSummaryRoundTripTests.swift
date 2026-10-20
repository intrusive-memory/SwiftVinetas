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
  func testVocabularyCloudSummariesEqualCoreMapping() {
    #expect(ModelSummary.cloud == CloudModelDescriptor.all.map(\.summary))
    #expect(ModelSummary.cloud.count == 9)
    #expect(ModelSummary.cloud.allSatisfy { $0.isCloud })
  }

  @Test
  func testVocabularyOnDeviceSummariesEqualCoreMapping() async {
    #expect(
      ModelSummary.all == [
        Flux2ModelDescriptor.klein4B.summary, PixArtModelDescriptor.sigmaXL.summary,
      ])
    #expect(ModelSummary.all.allSatisfy { !$0.isCloud })
    let flux = Flux2Engine()
    let pixart = PixArtEngine()
    #expect(
      ModelSummary.klein4B.maxReferenceImages
        == flux.maxReferenceImages(for: Flux2ModelDescriptor.klein4B))
    #expect(
      ModelSummary.pixartSigmaXL.maxReferenceImages
        == pixart.maxReferenceImages(for: PixArtModelDescriptor.sigmaXL))
  }

  @Test
  func cloudDescriptorSummaryCarriesCapabilitiesAndVendorNames() {
    let summary = CloudModelDescriptor.gptImage25Flare.summary
    #expect(!summary.supportsSteps)
    #expect(!summary.supportsGuidance)
    #expect(!summary.supportsSeed)
    #expect(!summary.supportsNegativePrompt)
    #expect(summary.engineName == "OpenAI")
    #expect(summary.subtitle == "OpenAI · ~$0.03–0.25/image")
  }

  @Test
  func everyCloudSummaryMirrorsItsDescriptor() {
    for provider in CloudProvider.allCases {
      for model in provider.models {
        let summary = model.summary
        #expect(summary.supportsSteps == model.supportsSteps)
        #expect(summary.supportsGuidance == model.supportsGuidance)
        #expect(summary.supportsSeed == model.supportsSeed)
        #expect(summary.supportsNegativePrompt == model.supportsNegativePrompt)
        #expect(summary.engineName == provider.shortName)
        #expect(summary.subtitle == "\(provider.displayName) · \(model.pricingHint)")
      }
    }
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

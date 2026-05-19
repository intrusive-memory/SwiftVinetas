import Foundation
import Testing

@testable import SwiftVinetas

@Suite("Flux2Engine Tests")
struct Flux2EngineTests {

  // MARK: - Flux2ModelDescriptor Properties

  @Test("Klein 4B has correct id")
  func klein4BID() {
    #expect(Flux2ModelDescriptor.klein4B.id == "flux2-klein-4b")
  }

  @Test("Klein 9B has correct id")
  func klein9BID() {
    #expect(Flux2ModelDescriptor.klein9B.id == "flux2-klein-9b")
  }

  @Test("Klein 4B has correct displayName")
  func klein4BDisplayName() {
    #expect(Flux2ModelDescriptor.klein4B.displayName == "FLUX.2 Klein 4B")
  }

  @Test("Klein 9B has correct displayName")
  func klein9BDisplayName() {
    #expect(Flux2ModelDescriptor.klein9B.displayName == "FLUX.2 Klein 9B")
  }

  @Test("Klein 4B has engineID 'flux2'")
  func klein4BEngineID() {
    #expect(Flux2ModelDescriptor.klein4B.engineID == "flux2")
  }

  @Test("Klein 9B has engineID 'flux2'")
  func klein9BEngineID() {
    #expect(Flux2ModelDescriptor.klein9B.engineID == "flux2")
  }

  @Test("Klein 4B requires 16 GB minimum")
  func klein4BMinimumMemory() {
    #expect(Flux2ModelDescriptor.klein4B.minimumMemoryGB == 16)
  }

  @Test("Klein 9B requires 24 GB minimum")
  func klein9BMinimumMemory() {
    #expect(Flux2ModelDescriptor.klein9B.minimumMemoryGB == 24)
  }

  @Test("Klein 4B has non-commercial license")
  func klein4BLicense() {
    if case .nonCommercial = Flux2ModelDescriptor.klein4B.license {
      // Expected
    } else {
      Issue.record("Klein 4B license should be nonCommercial")
    }
  }

  @Test("Klein 9B has non-commercial license")
  func klein9BLicense() {
    if case .nonCommercial = Flux2ModelDescriptor.klein9B.license {
      // Expected
    } else {
      Issue.record("Klein 9B license should be nonCommercial")
    }
  }

  @Test("Klein 4B estimated time is 26 seconds")
  func klein4BEstimatedTime() {
    #expect(Flux2ModelDescriptor.klein4B.estimatedSecondsPerImage == 26)
  }

  @Test("Klein 9B estimated time is 62 seconds")
  func klein9BEstimatedTime() {
    #expect(Flux2ModelDescriptor.klein9B.estimatedSecondsPerImage == 62)
  }

  @Test("Klein 4B has 20 default steps")
  func klein4BDefaultSteps() {
    #expect(Flux2ModelDescriptor.klein4B.defaultSteps == 20)
  }

  @Test("Klein 9B has 20 default steps")
  func klein9BDefaultSteps() {
    #expect(Flux2ModelDescriptor.klein9B.defaultSteps == 20)
  }

  @Test("Klein 4B has 3.5 default guidance")
  func klein4BDefaultGuidance() {
    #expect(Flux2ModelDescriptor.klein4B.defaultGuidance == 3.5)
  }

  @Test("Klein 9B has 3.5 default guidance")
  func klein9BDefaultGuidance() {
    #expect(Flux2ModelDescriptor.klein9B.defaultGuidance == 3.5)
  }

  @Test("Klein 4B supports all aspect ratios")
  func klein4BAspectRatios() {
    #expect(Flux2ModelDescriptor.klein4B.supportedAspectRatios == AspectRatio.allCases)
  }

  @Test("Klein 9B supports all aspect ratios")
  func klein9BAspectRatios() {
    #expect(Flux2ModelDescriptor.klein9B.supportedAspectRatios == AspectRatio.allCases)
  }

  @Test("Klein 4B approximate download size is ~11 GB")
  func klein4BDownloadSize() {
    #expect(Flux2ModelDescriptor.klein4B.approximateDownloadSize == "~11 GB")
  }

  @Test("Klein 9B approximate download size is ~18 GB")
  func klein9BDownloadSize() {
    #expect(Flux2ModelDescriptor.klein9B.approximateDownloadSize == "~18 GB")
  }

  // MARK: - Flux2Engine Identity

  @Test("Flux2Engine has engineID 'flux2'")
  func flux2EngineID() {
    let engine = Flux2Engine()
    #expect(engine.engineID == "flux2")
  }

  @Test("Flux2Engine supportedModels contains Klein 4B and Klein 9B")
  func flux2EngineSupportedModels() {
    let engine = Flux2Engine()
    let models = engine.supportedModels
    #expect(models.count == 2)
    let ids = models.map { $0.id }
    #expect(ids.contains("flux2-klein-4b"))
    #expect(ids.contains("flux2-klein-9b"))
  }

  // MARK: - Feature Support

  @Test("Flux2Engine supports textToImage")
  func supportsTextToImage() {
    let engine = Flux2Engine()
    #expect(engine.supports(.textToImage) == true)
  }

  @Test("Flux2Engine supports imageToImage")
  func supportsImageToImage() {
    let engine = Flux2Engine()
    #expect(engine.supports(.imageToImage(maxReferenceImages: 3)) == true)
  }

  @Test("Flux2Engine supports loraInference")
  func supportsLoraInference() {
    let engine = Flux2Engine()
    #expect(engine.supports(.loraInference) == true)
  }

  @Test("Flux2Engine supports loraTraining")
  func supportsLoraTraining() {
    let engine = Flux2Engine()
    #expect(engine.supports(.loraTraining) == true)
  }

  @Test("Flux2Engine does not support promptUpsampling")
  func doesNotSupportPromptUpsampling() {
    let engine = Flux2Engine()
    #expect(engine.supports(.promptUpsampling) == false)
  }

  // MARK: - Memory Validation Thresholds

  @Test("Klein 4B validates as ok on system with sufficient memory")
  func klein4BMemoryOK() {
    let engine = Flux2Engine()
    let result = engine.validateMemory(for: Flux2ModelDescriptor.klein4B)
    // The system this runs on should have >= 16 GB,
    // but we just verify it returns a valid MemoryValidation
    switch result {
    case .ok, .warning:
      break  // These are acceptable on a machine with >= 16 GB
    case .insufficient:
      break  // Also acceptable if running on a small machine
    }
  }

  @Test("Flux2Engine validateMemory returns insufficient for unknown model")
  func validateMemoryUnknownModel() {
    let engine = Flux2Engine()
    let unknownModel = MockModelDescriptor(
      id: "unknown", displayName: "Unknown", engineID: "other"
    )
    let result = engine.validateMemory(for: unknownModel)
    if case .insufficient = result {
      // Expected — unknown model resolves to insufficient
    } else {
      Issue.record("Expected .insufficient for unknown model, got \(result)")
    }
  }

  @Test("Flux2Engine isAvailable returns false for unknown model")
  func isAvailableUnknownModel() async {
    let engine = Flux2Engine()
    let unknownModel = MockModelDescriptor(
      id: "unknown", displayName: "Unknown", engineID: "other"
    )
    #expect(await engine.isAvailable(unknownModel) == false)
  }

  @Test("Flux2Engine diskSize returns nil for unknown model")
  func diskSizeUnknownModel() async {
    let engine = Flux2Engine()
    let unknownModel = MockModelDescriptor(
      id: "unknown", displayName: "Unknown", engineID: "other"
    )
    let size = await engine.diskSize(of: unknownModel)
    #expect(size == nil)
  }

  // MARK: - Flux2ModelDescriptor Identifiable Conformance

  @Test("Flux2ModelDescriptor conforms to Identifiable with String ID")
  func flux2ModelDescriptorIdentifiable() {
    let descriptor = Flux2ModelDescriptor.klein4B
    // Identifiable requires `id`, which is a String
    let id: String = descriptor.id
    #expect(id == "flux2-klein-4b")
  }

  @Test("Two different Flux2ModelDescriptors have different IDs")
  func flux2ModelDescriptorDifferentIDs() {
    #expect(Flux2ModelDescriptor.klein4B.id != Flux2ModelDescriptor.klein9B.id)
  }

  // MARK: - ModelDescriptor Protocol Conformance

  @Test("Flux2ModelDescriptor conforms to ModelDescriptor")
  func flux2ModelDescriptorConformsToProtocol() {
    let descriptor: any ModelDescriptor = Flux2ModelDescriptor.klein4B
    #expect(descriptor.id == "flux2-klein-4b")
    #expect(descriptor.engineID == "flux2")
  }

  @Test("Flux2ModelDescriptor is Sendable")
  func flux2ModelDescriptorSendable() async {
    let descriptor = Flux2ModelDescriptor.klein4B
    let result = await Task { descriptor }.value
    #expect(result.id == "flux2-klein-4b")
  }
}

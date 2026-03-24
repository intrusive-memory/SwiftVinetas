import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

@Suite("GenerationRequest Tests")
struct GenerationRequestTests {

  // MARK: - Text-to-Image Request Construction

  @Test("Text-to-image request stores all properties")
  func textToImageRequestConstruction() {
    let request = GenerationRequest(
      prompt: "A comic panel of a superhero",
      negativePrompt: "blurry, low quality",
      steps: 20,
      guidanceScale: 3.5,
      seed: 12345,
      width: 1024,
      height: 1024,
      mode: .textToImage
    )

    #expect(request.prompt == "A comic panel of a superhero")
    #expect(request.negativePrompt == "blurry, low quality")
    #expect(request.steps == 20)
    #expect(request.guidanceScale == 3.5)
    #expect(request.seed == 12345)
    #expect(request.width == 1024)
    #expect(request.height == 1024)
  }

  @Test("Text-to-image mode is textToImage")
  func textToImageMode() {
    let request = GenerationRequest(
      prompt: "test",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    if case .textToImage = request.mode {
      // Expected
    } else {
      Issue.record("Expected textToImage mode")
    }
  }

  // MARK: - Image-to-Image Request Construction

  @Test("Image-to-image request stores references")
  func imageToImageRequestConstruction() {
    let image = MockEngine.create1x1Image()
    let request = GenerationRequest(
      prompt: "A variation of this image",
      steps: 15,
      guidanceScale: 4.0,
      width: 1024,
      height: 1024,
      mode: .imageToImage(references: [image])
    )

    #expect(request.prompt == "A variation of this image")
    #expect(request.steps == 15)
    #expect(request.guidanceScale == 4.0)

    if case .imageToImage(let references) = request.mode {
      #expect(references.count == 1)
    } else {
      Issue.record("Expected imageToImage mode")
    }
  }

  @Test("Image-to-image mode with multiple references")
  func imageToImageMultipleReferences() {
    let image1 = MockEngine.create1x1Image()
    let image2 = MockEngine.create1x1Image()
    let image3 = MockEngine.create1x1Image()

    let request = GenerationRequest(
      prompt: "Combined reference",
      steps: 20,
      guidanceScale: 3.5,
      width: 1024,
      height: 1024,
      mode: .imageToImage(references: [image1, image2, image3])
    )

    if case .imageToImage(let references) = request.mode {
      #expect(references.count == 3)
    } else {
      Issue.record("Expected imageToImage mode with 3 references")
    }
  }

  @Test("Image-to-image mode with empty references")
  func imageToImageEmptyReferences() {
    let request = GenerationRequest(
      prompt: "No references",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512,
      mode: .imageToImage(references: [])
    )

    if case .imageToImage(let references) = request.mode {
      #expect(references.isEmpty)
    } else {
      Issue.record("Expected imageToImage mode with empty references")
    }
  }

  // MARK: - Default Values

  @Test("Default mode is textToImage")
  func defaultModeIsTextToImage() {
    let request = GenerationRequest(
      prompt: "test",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512
    )

    if case .textToImage = request.mode {
      // Expected — default mode
    } else {
      Issue.record("Default mode should be textToImage")
    }
  }

  @Test("Default negativePrompt is nil")
  func defaultNegativePromptIsNil() {
    let request = GenerationRequest(
      prompt: "test",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512
    )

    #expect(request.negativePrompt == nil)
  }

  @Test("Default seed is nil")
  func defaultSeedIsNil() {
    let request = GenerationRequest(
      prompt: "test",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512
    )

    #expect(request.seed == nil)
  }

  // MARK: - Mutability

  @Test("GenerationRequest properties are mutable")
  func requestMutability() {
    var request = GenerationRequest(
      prompt: "original",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512
    )

    request.prompt = "modified"
    request.negativePrompt = "added"
    request.steps = 30
    request.guidanceScale = 7.5
    request.seed = 99999
    request.width = 1024
    request.height = 768

    #expect(request.prompt == "modified")
    #expect(request.negativePrompt == "added")
    #expect(request.steps == 30)
    #expect(request.guidanceScale == 7.5)
    #expect(request.seed == 99999)
    #expect(request.width == 1024)
    #expect(request.height == 768)
  }

  @Test("GenerationRequest mode can be changed after init")
  func requestModeChange() {
    var request = GenerationRequest(
      prompt: "test",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512,
      mode: .textToImage
    )

    let image = MockEngine.create1x1Image()
    request.mode = .imageToImage(references: [image])

    if case .imageToImage(let refs) = request.mode {
      #expect(refs.count == 1)
    } else {
      Issue.record("Mode should have changed to imageToImage")
    }
  }

  // MARK: - Sendable Conformance

  @Test("GenerationRequest is Sendable")
  func requestIsSendable() async {
    let request = GenerationRequest(
      prompt: "test",
      steps: 10,
      guidanceScale: 3.0,
      width: 512,
      height: 512
    )

    let result = await Task { request }.value
    #expect(result.prompt == "test")
  }

  // MARK: - GenerationResult Properties

  @Test("GenerationResult stores all properties")
  func generationResultProperties() {
    let image = MockEngine.create1x1Image()
    let result = GenerationResult(
      image: image,
      usedPrompt: "A test prompt",
      seed: 42,
      durationSeconds: 12.5,
      modelID: "flux2-klein-4b"
    )

    #expect(result.usedPrompt == "A test prompt")
    #expect(result.seed == 42)
    #expect(result.durationSeconds == 12.5)
    #expect(result.modelID == "flux2-klein-4b")
  }

  @Test("GenerationResult is Sendable")
  func generationResultSendable() async {
    let image = MockEngine.create1x1Image()
    let result = GenerationResult(
      image: image,
      usedPrompt: "test",
      seed: 1,
      durationSeconds: 1.0,
      modelID: "test"
    )

    let transferred = await Task { result }.value
    #expect(transferred.seed == 1)
  }

  // MARK: - DownloadProgress

  @Test("DownloadProgress stores fraction and message")
  func downloadProgressProperties() {
    let progress = DownloadProgress(fraction: 0.75, message: "Downloading transformer...")
    #expect(progress.fraction == 0.75)
    #expect(progress.message == "Downloading transformer...")
  }

  // MARK: - LoadProgress

  @Test("LoadProgress stores phase and fraction")
  func loadProgressProperties() {
    let progress = LoadProgress(phase: "Loading text encoder", fraction: 0.5)
    #expect(progress.phase == "Loading text encoder")
    #expect(progress.fraction == 0.5)
  }

  // MARK: - MemoryValidation

  @Test("MemoryValidation.ok case")
  func memoryValidationOK() {
    let validation = MemoryValidation.ok
    if case .ok = validation {
      // Expected
    } else {
      Issue.record("Expected .ok")
    }
  }

  @Test("MemoryValidation.warning case contains message")
  func memoryValidationWarning() {
    let validation = MemoryValidation.warning(message: "Low memory")
    if case .warning(let message) = validation {
      #expect(message == "Low memory")
    } else {
      Issue.record("Expected .warning")
    }
  }

  @Test("MemoryValidation.insufficient case contains required and available")
  func memoryValidationInsufficient() {
    let validation = MemoryValidation.insufficient(
      required: 24 * 1_073_741_824,
      available: 16 * 1_073_741_824
    )
    if case .insufficient(let required, let available) = validation {
      #expect(required == 24 * 1_073_741_824)
      #expect(available == 16 * 1_073_741_824)
    } else {
      Issue.record("Expected .insufficient")
    }
  }

  // MARK: - EngineFeature

  @Test("EngineFeature.textToImage is hashable")
  func engineFeatureTextToImageHashable() {
    let feature: EngineFeature = .textToImage
    var set: Set<EngineFeature> = []
    set.insert(feature)
    #expect(set.contains(.textToImage))
  }

  @Test("EngineFeature.imageToImage carries maxReferenceImages")
  func engineFeatureImageToImage() {
    let feature = EngineFeature.imageToImage(maxReferenceImages: 3)
    if case .imageToImage(let max) = feature {
      #expect(max == 3)
    } else {
      Issue.record("Expected imageToImage")
    }
  }

  @Test("EngineFeature cases are distinct in a set")
  func engineFeatureDistinctCases() {
    var set: Set<EngineFeature> = []
    set.insert(.textToImage)
    set.insert(.loraInference)
    set.insert(.loraTraining)
    set.insert(.promptUpsampling)
    #expect(set.count == 4)
  }

  // MARK: - ModelLicense

  @Test("ModelLicense.apache2 case")
  func modelLicenseApache2() {
    let license = ModelLicense.apache2
    if case .apache2 = license {
      // Expected
    } else {
      Issue.record("Expected .apache2")
    }
  }

  @Test("ModelLicense.nonCommercial contains details")
  func modelLicenseNonCommercial() {
    let license = ModelLicense.nonCommercial(details: "Test License")
    if case .nonCommercial(let details) = license {
      #expect(details == "Test License")
    } else {
      Issue.record("Expected .nonCommercial")
    }
  }

  @Test("ModelLicense.custom contains name and optional URL")
  func modelLicenseCustom() {
    let url = URL(string: "https://example.com/license")
    let license = ModelLicense.custom(name: "Custom", url: url)
    if case .custom(let name, let licenseURL) = license {
      #expect(name == "Custom")
      #expect(licenseURL?.absoluteString == "https://example.com/license")
    } else {
      Issue.record("Expected .custom")
    }
  }

  @Test("ModelLicense.custom with nil URL")
  func modelLicenseCustomNilURL() {
    let license = ModelLicense.custom(name: "Proprietary", url: nil)
    if case .custom(let name, let licenseURL) = license {
      #expect(name == "Proprietary")
      #expect(licenseURL == nil)
    } else {
      Issue.record("Expected .custom with nil URL")
    }
  }
}

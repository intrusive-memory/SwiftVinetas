import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasError")
struct VinetasErrorTests {

  // MARK: - modelNotFound

  @Test("modelNotFound error description contains model name")
  func modelNotFoundDescription() {
    let error = VinetasError.modelNotFound("test-model")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("test-model"))
  }

  // MARK: - insufficientMemory

  @Test("insufficientMemory error description contains required and available GB")
  func insufficientMemoryDescription() {
    let error = VinetasError.insufficientMemory(
      required: 16 * 1_073_741_824, available: 8 * 1_073_741_824)
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("16"))
    #expect(desc.contains("8"))
  }

  // MARK: - generationFailed

  @Test("generationFailed error description contains reason")
  func generationFailedDescription() {
    let error = VinetasError.generationFailed("out of memory")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("out of memory"))
  }

  // MARK: - invalidPromptFile

  @Test("invalidPromptFile error description contains file path")
  func invalidPromptFileDescription() {
    let error = VinetasError.invalidPromptFile(URL(fileURLWithPath: "/tmp/bad.yaml"))
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    // Path should appear in description (either full path or filename)
    #expect(desc.contains("/tmp/bad.yaml") || desc.contains("bad.yaml"))
  }

  // MARK: - downloadFailed

  @Test("downloadFailed error description contains reason")
  func downloadFailedDescription() {
    let error = VinetasError.downloadFailed("network timeout")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("network timeout"))
  }

  // MARK: - engineNotFound

  @Test("engineNotFound error description contains engine ID")
  func engineNotFoundDescription() {
    let error = VinetasError.engineNotFound(engineID: "flux2")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("flux2"))
  }

  // MARK: - modelNotSupported

  @Test("modelNotSupported error description contains model and engine IDs")
  func modelNotSupportedDescription() {
    let error = VinetasError.modelNotSupported(modelID: "flux2-klein-4b", engineID: "pixart-sigma")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("flux2-klein-4b"))
    #expect(desc.contains("pixart-sigma"))
  }

  // MARK: - loraIncompatible

  @Test("loraIncompatible error description contains LoRA engine and current engine")
  func loraIncompatibleDescription() {
    let error = VinetasError.loraIncompatible(loraEngine: "flux2", currentEngine: "pixart-sigma")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("flux2"))
    #expect(desc.contains("pixart-sigma"))
  }

  // MARK: - engineFeatureUnsupported

  @Test("engineFeatureUnsupported error description contains engine ID")
  func engineFeatureUnsupportedDescription() {
    let error = VinetasError.engineFeatureUnsupported(
      feature: .imageToImage(maxReferenceImages: 4), engineID: "flux2")
    let desc = error.localizedDescription
    #expect(!desc.isEmpty)
    #expect(desc.contains("flux2"))
  }
}

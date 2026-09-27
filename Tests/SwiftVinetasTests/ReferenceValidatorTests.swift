import Foundation
import Testing

@testable import SwiftVinetas

@Suite("ReferenceValidatorTests")
struct ReferenceValidatorTests {

  @Test("PixArt with 1 reference throws referencesUnsupported")
  func pixArtRejectsReferences() {
    let engine = PixArtEngine()
    do {
      try ReferenceValidator.validate(
        referenceCount: 1, engine: engine, model: PixArtModelDescriptor.sigmaXL)
      Issue.record("Expected referencesUnsupported")
    } catch VinetasError.referencesUnsupported(let engineID) {
      #expect(engineID == "pixart-sigma")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Klein 4B with 3 references passes")
  func klein4BAcceptsThree() throws {
    let engine = Flux2Engine()
    #expect(engine.maxReferenceImages(for: Flux2ModelDescriptor.klein4B) == 3)
    try ReferenceValidator.validate(
      referenceCount: 3, engine: engine, model: Flux2ModelDescriptor.klein4B)
  }

  @Test("Klein 4B with 4 references throws tooManyReferences with exact message")
  func klein4BRejectsFour() {
    let engine = Flux2Engine()
    do {
      try ReferenceValidator.validate(
        referenceCount: 4, engine: engine, model: Flux2ModelDescriptor.klein4B)
      Issue.record("Expected tooManyReferences")
    } catch let error as VinetasError {
      guard case .tooManyReferences(let model, let max, let got) = error else {
        Issue.record("Unexpected VinetasError: \(error)")
        return
      }
      #expect(model == "flux2-klein-4b")
      #expect(max == 3)
      #expect(got == 4)
      #expect(error.errorDescription == "flux2-klein-4b accepts at most 3 reference images; got 4")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("0 references passes on every engine")
  func zeroReferencesPasses() throws {
    try ReferenceValidator.validate(
      referenceCount: 0, engine: PixArtEngine(), model: PixArtModelDescriptor.sigmaXL)
    try ReferenceValidator.validate(
      referenceCount: 0, engine: Flux2Engine(), model: Flux2ModelDescriptor.klein4B)
    try ReferenceValidator.validate(
      referenceCount: 0, engine: MockEngine(), model: MockModelDescriptor())
  }

  @Test("Mock with max 1 and 2 references throws tooManyReferences")
  func mockMaxOneRejectsTwo() {
    let engine = MockEngine(maxReferenceImages: 1)
    let model = MockModelDescriptor()
    #expect(throws: VinetasError.self) {
      try ReferenceValidator.validate(referenceCount: 2, engine: engine, model: model)
    }
    do {
      try ReferenceValidator.validate(referenceCount: 2, engine: engine, model: model)
    } catch VinetasError.tooManyReferences(let id, let max, let got) {
      #expect(id == model.id)
      #expect(max == 1)
      #expect(got == 2)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Flux2Engine supports imageToImage only up to 3 references")
  func flux2SupportsCap() {
    let engine = Flux2Engine()
    #expect(engine.supports(.imageToImage(maxReferenceImages: 3)))
    #expect(!engine.supports(.imageToImage(maxReferenceImages: 4)))
  }
}

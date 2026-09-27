import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

@Suite("PanelRequestTests")
struct PanelRequestTests {

  // MARK: - Helpers

  private func makeClient(_ engine: MockEngine) -> VinetasClient {
    VinetasClient(router: EngineRouter(engines: [engine]))
  }

  private func makeReference() throws -> ReferenceImage {
    let png = try #require(ImageOutput.pngData(from: MockEngine.create1x1Image()))
    return try ReferenceImage.load(data: png, source: .file(path: "ref.png"))
  }

  // MARK: - Seed

  @Test("nil style seed records the engine's actual seed")
  func actualSeedFromEngine() async throws {
    let engine = MockEngine()
    await engine.setGenerateResult(
      GenerationResult(
        image: MockEngine.create1x1Image(),
        usedPrompt: "a cat",
        seed: 987_654_321,
        durationSeconds: 0.1,
        modelID: "mock-model"))
    let panel = try await makeClient(engine).generate(
      PanelRequest(prompt: "a cat", style: StyleConfig(seed: nil), model: MockModelDescriptor()))
    #expect(panel.metadata.seed == 987_654_321)
    #expect(await engine.lastRequest?.seed == nil)
  }

  // MARK: - Reference validation before load

  @Test("references on an engine with max 0 throw before loadModel")
  func referencesUnsupportedThrowsBeforeLoad() async throws {
    let engine = MockEngine(maxReferenceImages: 0)
    let reference = try makeReference()
    do {
      _ = try await makeClient(engine).generate(
        PanelRequest(prompt: "a cat", model: MockModelDescriptor(), references: [reference]))
      Issue.record("Expected referencesUnsupported")
    } catch VinetasError.referencesUnsupported(let engineID) {
      #expect(engineID == "mock")
    }
    #expect(await engine.loadModelCallCount == 0)
    #expect(await engine.generateCallCount == 0)
  }

  @Test("too many references throw before loadModel")
  func tooManyReferencesThrowsBeforeLoad() async throws {
    let engine = MockEngine(maxReferenceImages: 2)
    let reference = try makeReference()
    do {
      _ = try await makeClient(engine).generate(
        PanelRequest(
          prompt: "a cat", model: MockModelDescriptor(),
          references: [reference, reference, reference]))
      Issue.record("Expected tooManyReferences")
    } catch VinetasError.tooManyReferences(let model, let max, let got) {
      #expect(model == "mock-model")
      #expect(max == 2)
      #expect(got == 3)
    }
    #expect(await engine.loadModelCallCount == 0)
    #expect(await engine.generateCallCount == 0)
  }

  @Test("references map to imageToImage and are recorded in metadata")
  func referencesUseImageToImage() async throws {
    let engine = MockEngine(maxReferenceImages: 3)
    let reference = try makeReference()
    let panel = try await makeClient(engine).generate(
      PanelRequest(prompt: "a cat", model: MockModelDescriptor(), references: [reference]))
    let request = try #require(await engine.lastRequest)
    guard case .imageToImage(let refs) = request.mode else {
      Issue.record("Expected imageToImage mode, got textToImage")
      return
    }
    #expect(refs.count == 1)
    #expect(panel.metadata.mode == .imageToImage)
    #expect(panel.metadata.references == [ImageOutput.ReferenceRecord(reference)])
  }

  // MARK: - Negative prompt

  @Test("negativeApplied is false when the engine lacks .negativePrompt")
  func negativeNotApplied() async throws {
    let engine = MockEngine()
    let panel = try await makeClient(engine).generate(
      PanelRequest(
        prompt: "a cat", style: StyleConfig(negativePrompt: "blurry"),
        model: MockModelDescriptor()))
    #expect(panel.metadata.negative == "blurry")
    #expect(panel.metadata.negativeApplied == false)
  }

  @Test("negativeApplied is true when the engine supports .negativePrompt")
  func negativeApplied() async throws {
    let engine = MockEngine(supportsNegativePrompt: true)
    let panel = try await makeClient(engine).generate(
      PanelRequest(
        prompt: "a cat", style: StyleConfig(negativePrompt: "blurry"),
        model: MockModelDescriptor()))
    #expect(panel.metadata.negativeApplied == true)
  }

  // MARK: - Effective size and metadata fields

  @Test("metadata records the clamped effective size")
  func effectiveSizeIsClamped() async throws {
    let engine = MockEngine()
    let style = StyleConfig(width: 8192, height: 8192)
    let expected = ResolutionClamp.clampedDimensions(width: 8192, height: 8192)
    let panel = try await makeClient(engine).generate(
      PanelRequest(prompt: "a cat", style: style, model: MockModelDescriptor()))
    #expect(panel.metadata.width == expected.width)
    #expect(panel.metadata.height == expected.height)
    let request = try #require(await engine.lastRequest)
    #expect(request.width == expected.width)
    #expect(request.height == expected.height)
  }

  @Test("metadata records prompts, mode, engine, model, steps, guidance, loras")
  func metadataFields() async throws {
    let engine = MockEngine()
    let style = StyleConfig(stylePrompt: "noir", steps: 7, guidanceScale: 2.5)
    let panel = try await makeClient(engine).generate(
      PanelRequest(prompt: "a cat", style: style, model: MockModelDescriptor()))
    let meta = panel.metadata
    #expect(meta.prompt == "a cat")
    #expect(meta.composedPrompt == "noir, a cat")
    #expect(meta.style == "noir")
    #expect(meta.mode == .textToImage)
    #expect(meta.engine == "mock")
    #expect(meta.model == "mock-model")
    #expect(meta.steps == 7)
    #expect(meta.guidance == 2.5)
    #expect(meta.loras == [])
    #expect(meta.references == [])
    #expect(meta.negative == nil)
    #expect(meta.negativeApplied == nil)
    #expect(meta.durationSeconds >= 0)
  }

  // MARK: - Wrapper

  @Test("generate(prompt:style:model:) wrapper returns an image")
  func wrapperReturnsImage() async throws {
    let engine = MockEngine()
    let image = try await makeClient(engine).generate(
      prompt: "a cat", style: nil, model: MockModelDescriptor())
    #expect(image.width == 1)
    #expect(image.height == 1)
    #expect(await engine.generateCallCount == 1)
    let request = try #require(await engine.lastRequest)
    guard case .textToImage = request.mode else {
      Issue.record("Wrapper must generate text-to-image")
      return
    }
  }
}

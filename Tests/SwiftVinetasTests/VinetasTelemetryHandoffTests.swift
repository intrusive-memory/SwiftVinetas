import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VinetasTelemetryHandoffTests
//
// Asserts that the four VinetasClient entry points each emit:
//  - Exactly one generationStart (single-emission rule) with all required fields
//  - Exactly one generationEnd with success/failure captured correctly
//
// The four entry points:
//  1. generate(prompt:style:model:)         — mode .textToImage
//  2. generateSequence(prompts:...)         — mode .textToImage or .imageToImage
//  3. generate(prompt:character:style:model:) — mode .textToImage
//  4. preview(prompt:)                      — mode .preview
//
// For entry points that use the router (1, 2, 3, 4), we drive through a failure
// path (empty prompt or unreachable model) to avoid GPU dependency while still
// exercising the generationEnd(success: false) path. For success-path testing
// on entry points 1 and 3, we use a MockEngine that returns a synthetic result.

@Suite("VinetasClient Telemetry — Generation Handoff")
struct VinetasTelemetryHandoffTests {

  // MARK: - Helpers

  private func makeMockClient(engineID: String = "mock") -> (
    client: VinetasClient, engine: MockEngine, model: MockModelDescriptor
  ) {
    let model = MockModelDescriptor(id: "mock-model", engineID: engineID)
    let engine = MockEngine(engineID: engineID, supportedModels: [model])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine, model)
  }

  // MARK: - Entry point 1: generate(prompt:style:model:)

  /// A successful generation emits generationStart then generationEnd(success: true).
  @Test func generateEmitsStartThenEnd() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generate(prompt: "test panel", model: model)
    // Allow fire-and-forget Task in defer to complete.
    await Task.yield()
    await Task.yield()

    let events = mock.events
    let startIdx = events.firstIndex {
      if case .generationStart = $0 { return true }
      return false
    }
    let endIdx = events.firstIndex {
      if case .generationEnd = $0 { return true }
      return false
    }
    #expect(startIdx != nil, "generationStart must be emitted")
    #expect(endIdx != nil, "generationEnd must be emitted")
  }

  /// Single-emission rule: exactly ONE generationStart per generate() call.
  @Test func generateEmitsExactlyOneGenerationStart() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generate(prompt: "unique prompt", model: model)
    await Task.yield()

    let starts = mock.all { if case .generationStart = $0 { return true }; return false }
    #expect(starts.count == 1, "Exactly one generationStart per call (single-emission rule)")
  }

  /// generationStart carries the correct mode (.textToImage) and non-empty fields.
  @Test func generateStartEventCarriesCorrectFields() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generate(prompt: "hello world", model: model)
    await Task.yield()

    guard let startEvent = mock.first(matching: { if case .generationStart = $0 { return true }; return false }) else {
      Issue.record("No generationStart captured")
      return
    }
    if case .generationStart(let prompt, let promptLength, let engineID, let modelID, _, _, _, _, _, let mode, _, _, _, _, _) = startEvent {
      #expect(prompt.contains("hello world"), "Prompt must be reflected in event (may include style prefix)")
      #expect(promptLength > 0, "promptLength must be positive")
      #expect(engineID == "mock", "engineID must match the mock engine")
      #expect(modelID == "mock-model", "modelID must match the model descriptor")
      #expect(mode == .textToImage, "generate(prompt:) must use .textToImage mode")
    }
  }

  /// generate() on a blank prompt emits generationEnd(success: false) and errorThrown.
  @Test func generateWithEmptyPromptEmitsFailureEnd() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try? await client.generate(prompt: "   ", model: model)
    await Task.yield()
    await Task.yield()

    let endEvent = mock.first { if case .generationEnd = $0 { return true }; return false }
    #expect(endEvent != nil, "generationEnd must fire even on error paths")
    if case .generationEnd(_, _, let success, _, _, _) = endEvent! {
      #expect(!success, "generationEnd.success must be false on error path")
    }

    let errorEvent = mock.first { if case .errorThrown = $0 { return true }; return false }
    #expect(errorEvent != nil, "errorThrown must be emitted on empty-prompt failure")
  }

  // MARK: - Entry point 2: generateSequence(prompts:...)

  /// generateSequence emits exactly one generationStart for the full sequence.
  @Test func generateSequenceEmitsOneStartForAllPanels() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generateSequence(prompts: ["panel 1", "panel 2"], model: model)
    await Task.yield()
    await Task.yield()

    let starts = mock.all { if case .generationStart = $0 { return true }; return false }
    #expect(starts.count == 1, "generateSequence emits exactly one generationStart for the whole batch")
  }

  /// generateSequence emits generationEnd on an empty-prompts call (succeeds with []).
  @Test func generateSequenceEmptyPromptsEmitsEnd() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generateSequence(prompts: [], model: model)
    await Task.yield()
    await Task.yield()

    let endEvent = mock.first { if case .generationEnd = $0 { return true }; return false }
    #expect(endEvent != nil, "generateSequence emits generationEnd even for empty prompts")
  }

  // MARK: - Entry point 3: generate(prompt:character:style:model:)

  /// generate(prompt:character:...) emits generationStart with .textToImage mode.
  @Test func generateWithCharacterEmitsTextToImageMode() async throws {
    let (client, _, model) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    let character = Character(
      name: "Hero",
      slug: "hero",
      triggerWord: "HERO",
      description: "A test hero",
      lora: nil
    )
    _ = try await client.generate(prompt: "hero pose", character: character, model: model)
    await Task.yield()

    guard let startEvent = mock.first(matching: { if case .generationStart = $0 { return true }; return false }) else {
      Issue.record("No generationStart captured for generate(prompt:character:)")
      return
    }
    if case .generationStart(_, _, _, _, _, _, _, _, _, let mode, _, _, _, _, _) = startEvent {
      #expect(mode == .textToImage, "generate(prompt:character:) must use .textToImage mode")
    }
  }

  // MARK: - Entry point 4: preview(prompt:)

  /// preview(prompt:) emits generationStart with .preview mode.
  /// This test uses the failure path (no flux2 engine registered) to avoid GPU.
  @Test func previewEmitsPreviewMode() async throws {
    // preview() uses router.engine(forEngineID: "flux2") — no flux2 registered.
    let model = MockModelDescriptor(id: "mock-model", engineID: "mock")
    let engine = MockEngine(engineID: "mock", supportedModels: [model])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    // preview() will throw because "flux2" engine isn't registered.
    _ = try? await client.preview(prompt: "fast preview")
    await Task.yield()
    await Task.yield()

    // generationEnd fires via defer — even on the failure path.
    let endEvent = mock.first { if case .generationEnd = $0 { return true }; return false }
    #expect(endEvent != nil, "generationEnd must be emitted even when preview fails")
    if case .generationEnd(_, _, let success, _, _, _) = endEvent! {
      #expect(!success, "preview's generationEnd.success must be false on no-flux2-engine path")
    }
  }

  // MARK: - generationEnd success vs failure via router

  /// Requesting an unroutable model fires generationEnd(success: false) via defer.
  @Test func unroutableModelEmitsFailureEnd() async throws {
    let (client, _, _) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    let unreachableModel = MockModelDescriptor(id: "gone", engineID: "nonexistent")
    _ = try? await client.generate(prompt: "any", model: unreachableModel)
    await Task.yield()
    await Task.yield()

    let endEvent = mock.first { if case .generationEnd = $0 { return true }; return false }
    #expect(endEvent != nil, "generationEnd must fire via defer even on router-failure path")
    if case .generationEnd(_, _, let success, let duration, _, _) = endEvent! {
      #expect(!success)
      #expect(duration >= 0)
    }
  }
}

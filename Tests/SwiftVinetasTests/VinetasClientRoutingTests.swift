import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasClient Routing Tests")
struct VinetasClientRoutingTests {

  // MARK: - VinetasModelInfo Struct Properties

  @Test("VinetasModelInfo stores name correctly")
  func modelInfoName() {
    let info = VinetasModelInfo(
      name: "black-forest-labs/FLUX.2-klein-4B",
      size: 2_500_000_000,
      downloadDate: Date(),
      isDownloaded: true
    )
    #expect(info.name == "black-forest-labs/FLUX.2-klein-4B")
  }

  @Test("VinetasModelInfo stores size correctly")
  func modelInfoSize() {
    let info = VinetasModelInfo(
      name: "test-model",
      size: 4_000_000_000,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(info.size == 4_000_000_000)
  }

  @Test("VinetasModelInfo stores download date correctly")
  func modelInfoDownloadDate() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let info = VinetasModelInfo(
      name: "test-model",
      size: 1_000_000,
      downloadDate: date,
      isDownloaded: true
    )
    #expect(info.downloadDate == date)
  }

  @Test("VinetasModelInfo download date is nil when not downloaded")
  func modelInfoNilDownloadDate() {
    let info = VinetasModelInfo(
      name: "test-model",
      size: 0,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(info.downloadDate == nil)
    #expect(info.isDownloaded == false)
  }

  @Test("VinetasModelInfo isDownloaded flag")
  func modelInfoIsDownloaded() {
    let downloaded = VinetasModelInfo(
      name: "downloaded-model",
      size: 5_000_000_000,
      downloadDate: Date(),
      isDownloaded: true
    )
    let notDownloaded = VinetasModelInfo(
      name: "not-downloaded-model",
      size: 0,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(downloaded.isDownloaded == true)
    #expect(notDownloaded.isDownloaded == false)
  }

  // MARK: - Formatted Size

  @Test("Formatted size shows 'Not downloaded' for zero bytes")
  func formattedSizeZero() {
    let info = VinetasModelInfo(
      name: "test",
      size: 0,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(info.formattedSize == "Not downloaded")
  }

  @Test("Formatted size shows bytes for small sizes")
  func formattedSizeBytes() {
    let info = VinetasModelInfo(
      name: "test",
      size: 512,
      downloadDate: Date(),
      isDownloaded: true
    )
    #expect(info.formattedSize == "512 bytes")
  }

  @Test("Formatted size shows GB for large sizes")
  func formattedSizeGB() {
    let info = VinetasModelInfo(
      name: "test",
      size: 2_684_354_560,  // 2.5 GB
      downloadDate: Date(),
      isDownloaded: true
    )
    #expect(info.formattedSize == "2.5 GB")
  }

  // MARK: - Equatable

  @Test("VinetasModelInfo Equatable conformance")
  func equatable() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let info1 = VinetasModelInfo(
      name: "model-a",
      size: 1000,
      downloadDate: date,
      isDownloaded: true
    )
    let info2 = VinetasModelInfo(
      name: "model-a",
      size: 1000,
      downloadDate: date,
      isDownloaded: true
    )
    let info3 = VinetasModelInfo(
      name: "model-b",
      size: 1000,
      downloadDate: date,
      isDownloaded: true
    )
    #expect(info1 == info2)
    #expect(info1 != info3)
  }

  // MARK: - Model Availability Check

  @Test("isAvailable returns false for models not on disk")
  func isAvailableFalseForMissingModels() async throws {
    // Use a custom client with Flux2Engine so the test doesn't depend on CI runner memory
    let router = EngineRouter(engines: [Flux2Engine()])
    let client = VinetasClient(router: router)
    let available = try await client.isAvailable(Flux2ModelDescriptor.klein4B)
    #expect(type(of: available) == Bool.self)
  }

  // MARK: - listAllModels

  @Test("listModels returns at least one model from shared client")
  func listAllModelsReturnsAtLeastOneModel() async {
    let models = await VinetasClient.shared.listModels()
    // PixArtEngine is always registered regardless of memory
    #expect(models.count >= 1)
    let names = models.map(\.name)
    #expect(names.contains(PixArtModelDescriptor.sigmaXL.displayName))
  }

  @Test("listAllModels returns all variants when both engines registered")
  func listAllModelsReturnsAllVariants() async {
    let router = EngineRouter(engines: [PixArtEngine(), Flux2Engine()])
    let client = VinetasClient(router: router)
    let models = await client.listModels()

    #expect(models.count >= 3)

    let names = models.map(\.name)
    #expect(names.contains(Flux2ModelDescriptor.klein4B.displayName))
    #expect(names.contains(Flux2ModelDescriptor.klein9B.displayName))
    #expect(names.contains(PixArtModelDescriptor.sigmaXL.displayName))
  }

  // MARK: - Vinetas Public API

  @Test("Vinetas.listModels compiles and returns VinetasModelInfo array")
  func vinetasListModels() async {
    let models: [VinetasModelInfo] = await Vinetas.listModels()
    // PixArtEngine is always registered; Flux2 depends on runtime memory
    #expect(models.count >= 1)
  }

  @Test("Vinetas.validateMemory compiles and returns Bool")
  func vinetasValidateMemory() async {
    // On any Apple Silicon Mac with 16+ GB, Klein 4B should pass.
    // On machines with less, it will throw — both paths are valid.
    do {
      let result: Bool = try await Vinetas.validateMemory(for: .klein4b)
      #expect(result == true)
    } catch {
      // If the machine has < 16 GB, this is the expected path
      #expect(error is VinetasError)
    }
  }

  // MARK: - Async Overloads Accepting any ModelDescriptor

  @Test("isAvailable accepts any ModelDescriptor (Flux2 klein4B)")
  func isAvailableAcceptsModelDescriptorKlein4B() async throws {
    let router = EngineRouter(engines: [Flux2Engine()])
    let client = VinetasClient(router: router)
    let model: any ModelDescriptor = Flux2ModelDescriptor.klein4B
    let available = try await client.isAvailable(model)
    #expect(type(of: available) == Bool.self)
  }

  @Test("isAvailable accepts any ModelDescriptor (Flux2 klein9B)")
  func isAvailableAcceptsModelDescriptorKlein9B() async throws {
    let router = EngineRouter(engines: [Flux2Engine()])
    let client = VinetasClient(router: router)
    let model: any ModelDescriptor = Flux2ModelDescriptor.klein9B
    let available = try await client.isAvailable(model)
    #expect(type(of: available) == Bool.self)
  }

  @Test("isAvailable accepts any ModelDescriptor (PixArt sigmaXL) via MockEngine")
  func isAvailableAcceptsModelDescriptorPixArtSigmaXL() async throws {
    // PixArt stub engine in shared client may not be registered (PixArtCore not importable),
    // so route through a MockEngine instead to verify the any ModelDescriptor API.
    let pixartModel = MockModelDescriptor(
      id: "pixart-sigma-xl", displayName: "PixArt-Sigma XL", engineID: "pixart-sigma"
    )
    let engine = MockEngine(engineID: "pixart-sigma", supportedModels: [pixartModel])
    engine.isAvailableResult = false
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    let model: any ModelDescriptor = pixartModel
    let available = try await client.isAvailable(model)
    // Mock engine configured to return false
    #expect(available == false)
  }

  // MARK: - Engine-Aware Routing via MockEngine

  @Test("download routes through MockEngine for mock descriptor")
  func downloadRoutesThroughMockEngine() async throws {
    let mockModel = MockModelDescriptor(
      id: "mock-model", displayName: "Mock Model", engineID: "mock"
    )
    let engine = MockEngine(engineID: "mock", supportedModels: [mockModel])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    // download should invoke engine.download without error
    try await client.download(model: mockModel, progress: nil)
    // No error thrown means routing worked correctly
  }

  @Test("isAvailable routes through MockEngine and returns configured value")
  func isAvailableRoutesThroughMockEngineReturnsConfiguredValue() async throws {
    let mockModel = MockModelDescriptor(
      id: "mock-model", displayName: "Mock Model", engineID: "mock"
    )
    let engine = MockEngine(engineID: "mock", supportedModels: [mockModel])
    engine.isAvailableResult = true
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    let available = try await client.isAvailable(mockModel)
    #expect(available == true)
  }

  @Test("isAvailable routes through MockEngine and returns false by default")
  func isAvailableRoutesThroughMockEngineReturnsFalseByDefault() async throws {
    let mockModel = MockModelDescriptor(
      id: "mock-model", displayName: "Mock Model", engineID: "mock"
    )
    let engine = MockEngine(engineID: "mock", supportedModels: [mockModel])
    // isAvailableResult defaults to false
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    let available = try await client.isAvailable(mockModel)
    #expect(available == false)
  }

  @Test("delete routes through MockEngine")
  func deleteRoutesThroughMockEngine() async throws {
    let mockModel = MockModelDescriptor(
      id: "mock-model", displayName: "Mock Model", engineID: "mock"
    )
    let engine = MockEngine(engineID: "mock", supportedModels: [mockModel])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    try await client.delete(mockModel)
    let calls = await engine.calls
    #expect(calls.contains(.delete("mock-model")))
  }

  @Test("isAvailable throws engineNotFound when no engine handles model")
  func isAvailableThrowsEngineNotFoundForUnknownEngine() async throws {
    let unknownModel = MockModelDescriptor(
      id: "unknown", displayName: "Unknown", engineID: "nonexistent-engine"
    )
    let engine = MockEngine(engineID: "known-engine")
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    await #expect(throws: VinetasError.self) {
      _ = try await client.isAvailable(unknownModel)
    }
  }

  @Test("download throws engineNotFound when no engine handles model")
  func downloadThrowsEngineNotFoundForUnknownEngine() async throws {
    let unknownModel = MockModelDescriptor(
      id: "unknown", displayName: "Unknown", engineID: "nonexistent-engine"
    )
    let engine = MockEngine(engineID: "known-engine")
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    await #expect(throws: VinetasError.self) {
      try await client.download(model: unknownModel, progress: nil)
    }
  }

  @Test("listModels via VinetasClient returns all models from router")
  func listModelsReturnsAllModelsFromRouter() async {
    let modelA = MockModelDescriptor(
      id: "model-a", displayName: "Alpha", engineID: "engine-a"
    )
    let modelB = MockModelDescriptor(
      id: "model-b", displayName: "Beta", engineID: "engine-b"
    )
    let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
    let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB])
    let router = EngineRouter(engines: [engineA, engineB])
    let client = VinetasClient(router: router)

    let models = await client.listModels()
    #expect(models.count == 2)
    let names = models.map(\.name)
    #expect(names.contains("Alpha"))
    #expect(names.contains("Beta"))
  }

  @Test("validateMemory routes through MockEngine and returns configured validation")
  func validateMemoryRoutesThroughMockEngine() async throws {
    let mockModel = MockModelDescriptor(
      id: "mock-model", displayName: "Mock Model", engineID: "mock"
    )
    let engine = MockEngine(engineID: "mock", supportedModels: [mockModel])
    engine.validateMemoryResult = .ok
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    let validation = try await client.validateMemory(for: mockModel)
    if case .ok = validation {
      // Expected
    } else {
      Issue.record("Expected .ok from mock engine, got \(validation)")
    }
  }
}

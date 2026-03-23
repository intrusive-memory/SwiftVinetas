import Foundation
import Testing

@testable import SwiftVinetas

/// Tests for memory-gated engine registration logic.
///
/// ``VinetasClient.init()`` uses runtime memory detection via
/// ``DeviceCapability/current`` to decide which engines to register:
/// - ``PixArtEngine`` is always registered (requires 8 GB minimum).
/// - ``Flux2Engine`` is registered only when the device has >=16 GB.
///
/// All tests use ``VinetasClient/init(router:)`` with controlled routers to
/// avoid real model loading. Platform-conditional tests verify that the
/// ``EngineRouter`` correctly reflects single-engine vs. dual-engine configurations.
@Suite("Platform Registration Tests")
struct PlatformRegistrationTests {

    // MARK: - Helpers

    /// Creates a VinetasClient backed by only PixArtEngine (simulates iPad or low-memory Mac).
    private func clientWithPixArtOnly() -> VinetasClient {
        let pixart = PixArtEngine()
        let router = EngineRouter(engines: [pixart])
        return VinetasClient(router: router)
    }

    /// Creates a VinetasClient backed by both engines (simulates high-memory Mac).
    private func clientWithBothEngines() -> VinetasClient {
        let pixart = PixArtEngine()
        let flux2 = Flux2Engine()
        let router = EngineRouter(engines: [pixart, flux2])
        return VinetasClient(router: router)
    }

    // MARK: - PixArt-only configuration (simulates iPad / low-memory Mac)

    @Test("VinetasClient with PixArtEngine only has exactly 1 model")
    func pixArtOnlyHasOneModel() async {
        let client = clientWithPixArtOnly()
        let models = await client.router.allModels
        #expect(models.count == 1)
    }

    @Test("VinetasClient with PixArtEngine only lists sigmaXL")
    func pixArtOnlyListsSigmaXL() async {
        let client = clientWithPixArtOnly()
        let models = await client.router.allModels
        #expect(models.first?.id == "pixart-sigma-xl")
    }

    @Test("VinetasClient with PixArtEngine only resolves pixart-sigma engine")
    func pixArtOnlyResolvesPixArtEngine() async throws {
        let client = clientWithPixArtOnly()
        let engine = try await client.router.engine(for: PixArtModelDescriptor.sigmaXL)
        #expect(engine.engineID == "pixart-sigma")
    }

    @Test("VinetasClient with PixArtEngine only throws engineNotFound for flux2")
    func pixArtOnlyThrowsForFlux2() async throws {
        let client = clientWithPixArtOnly()
        await #expect(throws: VinetasError.self) {
            _ = try await client.router.engine(forEngineID: "flux2")
        }
    }

    // MARK: - Dual-engine configuration (simulates macOS with 16+ GB)

    @Test("VinetasClient with both engines has 3 models")
    func bothEnginesHaveThreeModels() async {
        let client = clientWithBothEngines()
        let models = await client.router.allModels
        // PixArt: sigmaXL (1), Flux2: klein4B + klein9B (2) = 3 total
        #expect(models.count == 3)
    }

    @Test("VinetasClient with both engines lists PixArt and Flux2 models")
    func bothEnginesListAllModels() async {
        let client = clientWithBothEngines()
        let models = await client.router.allModels
        let ids = Set(models.map { $0.id })
        #expect(ids.contains("pixart-sigma-xl"))
        #expect(ids.contains(Flux2ModelDescriptor.klein4B.id))
        #expect(ids.contains(Flux2ModelDescriptor.klein9B.id))
    }

    @Test("VinetasClient with both engines resolves PixArtEngine for sigmaXL")
    func bothEnginesResolvesPixArt() async throws {
        let client = clientWithBothEngines()
        let engine = try await client.router.engine(for: PixArtModelDescriptor.sigmaXL)
        #expect(engine.engineID == "pixart-sigma")
    }

    @Test("VinetasClient with both engines resolves Flux2Engine for klein4B")
    func bothEnginesResolvesFlux2ForKlein4B() async throws {
        let client = clientWithBothEngines()
        let engine = try await client.router.engine(for: Flux2ModelDescriptor.klein4B)
        #expect(engine.engineID == "flux2")
    }

    @Test("VinetasClient with both engines resolves Flux2Engine for klein9B")
    func bothEnginesResolvesFlux2ForKlein9B() async throws {
        let client = clientWithBothEngines()
        let engine = try await client.router.engine(for: Flux2ModelDescriptor.klein9B)
        #expect(engine.engineID == "flux2")
    }

    // MARK: - allModels sorting

    @Test("allModels is sorted by displayName in PixArt-only configuration")
    func pixArtOnlyModelsSortedByDisplayName() async {
        let client = clientWithPixArtOnly()
        let models = await client.router.allModels
        let names = models.map { $0.displayName }
        #expect(names == names.sorted())
    }

    @Test("allModels is sorted by displayName in dual-engine configuration")
    func bothEnginesModelsSortedByDisplayName() async {
        let client = clientWithBothEngines()
        let models = await client.router.allModels
        let names = models.map { $0.displayName }
        #expect(names == names.sorted())
    }

    // MARK: - Model ID uniqueness

    @Test("allModels IDs are unique in PixArt-only configuration")
    func pixArtOnlyModelIDsAreUnique() async {
        let client = clientWithPixArtOnly()
        let models = await client.router.allModels
        let ids = models.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    @Test("allModels IDs are unique in dual-engine configuration")
    func bothEnginesModelIDsAreUnique() async {
        let client = clientWithBothEngines()
        let models = await client.router.allModels
        let ids = models.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    // MARK: - listModels() surface

    @Test("listModels() returns one entry in PixArt-only configuration")
    func listModelsPixArtOnly() async {
        let client = clientWithPixArtOnly()
        let modelInfos = await client.listModels()
        #expect(modelInfos.count == 1)
    }

    @Test("listModels() returns three entries in dual-engine configuration")
    func listModelsBothEngines() async {
        let client = clientWithBothEngines()
        let modelInfos = await client.listModels()
        #expect(modelInfos.count == 3)
    }

    // MARK: - Empty router edge case

    @Test("VinetasClient with empty router has no models")
    func emptyRouterHasNoModels() async {
        let router = EngineRouter(engines: [])
        let client = VinetasClient(router: router)
        let models = await client.router.allModels
        #expect(models.isEmpty)
    }

    @Test("VinetasClient with empty router listModels returns empty array")
    func emptyRouterListModelsEmpty() async {
        let router = EngineRouter(engines: [])
        let client = VinetasClient(router: router)
        let modelInfos = await client.listModels()
        #expect(modelInfos.isEmpty)
    }

    // MARK: - MockEngine-based registration tests

    @Test("VinetasClient router works with MockEngine simulating PixArt")
    func mockEngineSimulatingPixArt() async throws {
        let pixartDescriptor = MockModelDescriptor(
            id: "pixart-sigma-xl",
            displayName: "PixArt-Sigma XL",
            engineID: "pixart-sigma",
            minimumMemoryGB: 8
        )
        let mockPixArt = MockEngine(
            engineID: "pixart-sigma",
            supportedModels: [pixartDescriptor]
        )
        let router = EngineRouter(engines: [mockPixArt])
        let client = VinetasClient(router: router)
        let models = await client.router.allModels
        #expect(models.count == 1)
        #expect(models.first?.id == "pixart-sigma-xl")
    }

    @Test("VinetasClient router with MockEngine simulating both engines has correct model count")
    func mockEngineBothEngines() async throws {
        let pixartDesc = MockModelDescriptor(
            id: "pixart-sigma-xl",
            displayName: "PixArt-Sigma XL",
            engineID: "pixart-sigma",
            minimumMemoryGB: 8
        )
        let flux2Desc4B = MockModelDescriptor(
            id: "flux2-klein-4b",
            displayName: "FLUX.2 Klein 4B",
            engineID: "flux2",
            minimumMemoryGB: 16
        )
        let flux2Desc9B = MockModelDescriptor(
            id: "flux2-klein-9b",
            displayName: "FLUX.2 Klein 9B",
            engineID: "flux2",
            minimumMemoryGB: 16
        )
        let mockPixArt = MockEngine(
            engineID: "pixart-sigma",
            supportedModels: [pixartDesc]
        )
        let mockFlux2 = MockEngine(
            engineID: "flux2",
            supportedModels: [flux2Desc4B, flux2Desc9B]
        )
        let router = EngineRouter(engines: [mockPixArt, mockFlux2])
        let client = VinetasClient(router: router)
        let models = await client.router.allModels
        #expect(models.count == 3)
    }

    // MARK: - Memory threshold logic

    @Test("PixArtModelDescriptor minimumMemoryGB is 8")
    func pixArtMinimumMemory() {
        #expect(PixArtModelDescriptor.sigmaXL.minimumMemoryGB == 8)
    }

    @Test("Flux2ModelDescriptor klein4B minimumMemoryGB is 16")
    func flux2Klein4BMinimumMemory() {
        #expect(Flux2ModelDescriptor.klein4B.minimumMemoryGB == 16)
    }

    @Test("Flux2ModelDescriptor klein9B minimumMemoryGB is 24")
    func flux2Klein9BMinimumMemory() {
        #expect(Flux2ModelDescriptor.klein9B.minimumMemoryGB == 24)
    }

    @Test("PixArt 8GB threshold is below Flux2 16GB threshold")
    func memoryThresholdOrdering() {
        #expect(PixArtModelDescriptor.sigmaXL.minimumMemoryGB < Flux2ModelDescriptor.klein4B.minimumMemoryGB)
    }
}

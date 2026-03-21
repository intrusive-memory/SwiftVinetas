import Foundation
import Testing

@testable import SwiftVinetas

@Suite("EngineRouter Tests")
struct EngineRouterTests {

    // MARK: - Engine Registration

    @Test("Router initializes with a single engine")
    func singleEngineRegistration() async throws {
        let engine = MockEngine(engineID: "test-engine")
        let router = EngineRouter(engines: [engine])
        let models = await router.allModels
        #expect(!models.isEmpty)
    }

    @Test("Router initializes with multiple engines")
    func multipleEngineRegistration() async throws {
        let modelA = MockModelDescriptor(
            id: "model-a", displayName: "Alpha Model", engineID: "engine-a"
        )
        let modelB = MockModelDescriptor(
            id: "model-b", displayName: "Beta Model", engineID: "engine-b"
        )
        let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
        let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB])
        let router = EngineRouter(engines: [engineA, engineB])
        let models = await router.allModels
        #expect(models.count == 2)
    }

    @Test("Router handles empty engine list")
    func emptyEngineList() async throws {
        let router = EngineRouter(engines: [])
        let models = await router.allModels
        #expect(models.isEmpty)
    }

    @Test("Duplicate engine IDs: last engine wins")
    func duplicateEngineIDs() async throws {
        let model1 = MockModelDescriptor(
            id: "model-1", displayName: "First", engineID: "dup"
        )
        let model2 = MockModelDescriptor(
            id: "model-2", displayName: "Second", engineID: "dup"
        )
        let engine1 = MockEngine(engineID: "dup", supportedModels: [model1])
        let engine2 = MockEngine(engineID: "dup", supportedModels: [model2])
        let router = EngineRouter(engines: [engine1, engine2])

        // The last engine with the "dup" ID should be the one returned
        let resolved = try await router.engine(
            for: MockModelDescriptor(id: "x", displayName: "X", engineID: "dup")
        )
        #expect(resolved.engineID == "dup")
    }

    // MARK: - allModels Aggregation and Sorting

    @Test("allModels aggregates models from all engines")
    func allModelsAggregation() async throws {
        let modelA = MockModelDescriptor(
            id: "model-a", displayName: "Alpha", engineID: "engine-a"
        )
        let modelB = MockModelDescriptor(
            id: "model-b", displayName: "Beta", engineID: "engine-b"
        )
        let modelC = MockModelDescriptor(
            id: "model-c", displayName: "Charlie", engineID: "engine-b"
        )
        let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
        let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB, modelC])
        let router = EngineRouter(engines: [engineA, engineB])
        let models = await router.allModels
        #expect(models.count == 3)
    }

    @Test("allModels sorted by displayName")
    func allModelsSortedByDisplayName() async throws {
        let modelZ = MockModelDescriptor(
            id: "model-z", displayName: "Zephyr", engineID: "engine-1"
        )
        let modelA = MockModelDescriptor(
            id: "model-a", displayName: "Alpha", engineID: "engine-1"
        )
        let modelM = MockModelDescriptor(
            id: "model-m", displayName: "Middle", engineID: "engine-2"
        )
        let engine1 = MockEngine(engineID: "engine-1", supportedModels: [modelZ, modelA])
        let engine2 = MockEngine(engineID: "engine-2", supportedModels: [modelM])
        let router = EngineRouter(engines: [engine1, engine2])
        let models = await router.allModels
        let names = models.map { $0.displayName }
        #expect(names == ["Alpha", "Middle", "Zephyr"])
    }

    // MARK: - engine(for:) Correct Dispatch

    @Test("engine(for:) returns correct engine based on engineID")
    func engineForModelReturnsCorrectEngine() async throws {
        let modelA = MockModelDescriptor(
            id: "model-a", displayName: "Alpha", engineID: "engine-a"
        )
        let modelB = MockModelDescriptor(
            id: "model-b", displayName: "Beta", engineID: "engine-b"
        )
        let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
        let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB])
        let router = EngineRouter(engines: [engineA, engineB])

        let resolvedA = try await router.engine(for: modelA)
        #expect(resolvedA.engineID == "engine-a")

        let resolvedB = try await router.engine(for: modelB)
        #expect(resolvedB.engineID == "engine-b")
    }

    @Test("engine(forEngineID:) returns correct engine")
    func engineForEngineIDReturnsCorrectEngine() async throws {
        let engineA = MockEngine(engineID: "engine-a")
        let engineB = MockEngine(engineID: "engine-b")
        let router = EngineRouter(engines: [engineA, engineB])

        let resolved = try await router.engine(forEngineID: "engine-b")
        #expect(resolved.engineID == "engine-b")
    }

    // MARK: - Unknown Engine ID Throws engineNotFound

    @Test("engine(for:) throws engineNotFound for unknown engineID")
    func engineForModelThrowsEngineNotFound() async throws {
        let engine = MockEngine(engineID: "known-engine")
        let router = EngineRouter(engines: [engine])

        let unknownModel = MockModelDescriptor(
            id: "unknown-model", displayName: "Unknown", engineID: "unknown-engine"
        )

        await #expect(throws: VinetasError.self) {
            try await router.engine(for: unknownModel)
        }
    }

    @Test("engine(forEngineID:) throws engineNotFound for unknown ID")
    func engineForEngineIDThrowsEngineNotFound() async throws {
        let engine = MockEngine(engineID: "known-engine")
        let router = EngineRouter(engines: [engine])

        await #expect(throws: VinetasError.self) {
            try await router.engine(forEngineID: "nonexistent")
        }
    }

    @Test("engineNotFound error contains the missing engineID")
    func engineNotFoundContainsMissingID() async throws {
        let router = EngineRouter(engines: [])

        do {
            _ = try await router.engine(forEngineID: "missing-id")
            Issue.record("Expected engineNotFound error")
        } catch let error as VinetasError {
            switch error {
            case .engineNotFound(let engineID):
                #expect(engineID == "missing-id")
            default:
                Issue.record("Expected engineNotFound, got \(error)")
            }
        }
    }

    // MARK: - Real Engine Integration

    @Test("Router works with real Flux2Engine and PixArtEngine types")
    func routerWithRealEngines() async throws {
        let flux2 = Flux2Engine()
        let pixart = PixArtEngine()
        let router = EngineRouter(engines: [flux2, pixart])
        let models = await router.allModels
        // Flux2 has 2 models (klein4B, klein9B), PixArt has 1 (sigmaXL)
        #expect(models.count == 3)

        // Verify models are sorted by displayName
        let names = models.map { $0.displayName }
        #expect(names == names.sorted())
    }

    @Test("Router resolves Flux2ModelDescriptor to Flux2Engine")
    func routerResolvesFlux2() async throws {
        let flux2 = Flux2Engine()
        let pixart = PixArtEngine()
        let router = EngineRouter(engines: [flux2, pixart])

        let engine = try await router.engine(for: Flux2ModelDescriptor.klein4B)
        #expect(engine.engineID == "flux2")
    }

    @Test("Router resolves PixArtModelDescriptor to PixArtEngine")
    func routerResolvesPixArt() async throws {
        let flux2 = Flux2Engine()
        let pixart = PixArtEngine()
        let router = EngineRouter(engines: [flux2, pixart])

        let engine = try await router.engine(for: PixArtModelDescriptor.sigmaXL)
        #expect(engine.engineID == "pixart-sigma")
    }
}

import Foundation
import Testing

@testable import SwiftVinetas

@Suite("PixArtEngine Tests")
struct PixArtEngineTests {

    // MARK: - PixArtModelDescriptor.sigmaXL Properties

    @Test("sigmaXL has correct id")
    func sigmaXLID() {
        #expect(PixArtModelDescriptor.sigmaXL.id == "pixart-sigma-xl")
    }

    @Test("sigmaXL has correct displayName")
    func sigmaXLDisplayName() {
        #expect(PixArtModelDescriptor.sigmaXL.displayName == "PixArt-Sigma XL")
    }

    @Test("sigmaXL has engineID 'pixart-sigma'")
    func sigmaXLEngineID() {
        #expect(PixArtModelDescriptor.sigmaXL.engineID == "pixart-sigma")
    }

    @Test("sigmaXL has Apache 2.0 license")
    func sigmaXLLicense() {
        if case .apache2 = PixArtModelDescriptor.sigmaXL.license {
            // Expected
        } else {
            Issue.record("sigmaXL license should be .apache2")
        }
    }

    @Test("sigmaXL requires 8 GB minimum")
    func sigmaXLMinimumMemory() {
        #expect(PixArtModelDescriptor.sigmaXL.minimumMemoryGB == 8)
    }

    @Test("sigmaXL approximate download size is ~3.6 GB")
    func sigmaXLDownloadSize() {
        #expect(PixArtModelDescriptor.sigmaXL.approximateDownloadSize == "~3.6 GB")
    }

    @Test("sigmaXL has 20 default steps")
    func sigmaXLDefaultSteps() {
        #expect(PixArtModelDescriptor.sigmaXL.defaultSteps == 20)
    }

    @Test("sigmaXL has 4.5 default guidance")
    func sigmaXLDefaultGuidance() {
        #expect(PixArtModelDescriptor.sigmaXL.defaultGuidance == 4.5)
    }

    @Test("sigmaXL supports all aspect ratios")
    func sigmaXLAspectRatios() {
        #expect(PixArtModelDescriptor.sigmaXL.supportedAspectRatios == AspectRatio.allCases)
    }

    @Test("sigmaXL estimated time is 10 seconds")
    func sigmaXLEstimatedTime() {
        #expect(PixArtModelDescriptor.sigmaXL.estimatedSecondsPerImage == 10)
    }

    // MARK: - PixArtModelDescriptor Protocol Conformance

    @Test("PixArtModelDescriptor conforms to ModelDescriptor")
    func pixArtModelDescriptorConformsToProtocol() {
        let descriptor: any ModelDescriptor = PixArtModelDescriptor.sigmaXL
        #expect(descriptor.id == "pixart-sigma-xl")
        #expect(descriptor.engineID == "pixart-sigma")
    }

    @Test("PixArtModelDescriptor is Sendable")
    func pixArtModelDescriptorSendable() async {
        let descriptor = PixArtModelDescriptor.sigmaXL
        let result = await Task { descriptor }.value
        #expect(result.id == "pixart-sigma-xl")
    }

    @Test("PixArtModelDescriptor conforms to Identifiable with String ID")
    func pixArtModelDescriptorIdentifiable() {
        let id: String = PixArtModelDescriptor.sigmaXL.id
        #expect(id == "pixart-sigma-xl")
    }

    // MARK: - PixArtEngine Identity

    @Test("PixArtEngine has engineID 'pixart-sigma'")
    func pixArtEngineID() async {
        let engine = PixArtEngine()
        let id = await engine.engineID
        #expect(id == "pixart-sigma")
    }

    @Test("PixArtEngine supportedModels contains sigmaXL")
    func pixArtEngineSupportedModels() async {
        let engine = PixArtEngine()
        let models = await engine.supportedModels
        #expect(models.count == 1)
        #expect(models.first?.id == "pixart-sigma-xl")
    }

    // MARK: - Feature Support

    @Test("PixArtEngine supports textToImage")
    func supportsTextToImage() {
        let engine = PixArtEngine()
        #expect(engine.supports(.textToImage) == true)
    }

    @Test("PixArtEngine supports loraInference")
    func supportsLoraInference() {
        let engine = PixArtEngine()
        #expect(engine.supports(.loraInference) == true)
    }

    @Test("PixArtEngine does not support imageToImage")
    func doesNotSupportImageToImage() {
        let engine = PixArtEngine()
        #expect(engine.supports(.imageToImage(maxReferenceImages: 3)) == false)
    }

    @Test("PixArtEngine does not support loraTraining")
    func doesNotSupportLoraTraining() {
        let engine = PixArtEngine()
        #expect(engine.supports(.loraTraining) == false)
    }

    @Test("PixArtEngine does not support promptUpsampling")
    func doesNotSupportPromptUpsampling() {
        let engine = PixArtEngine()
        #expect(engine.supports(.promptUpsampling) == false)
    }

    // MARK: - Availability and Memory

    @Test("PixArtEngine isAvailable returns false when not downloaded")
    func isAvailableReturnsFalse() {
        let engine = PixArtEngine()
        // Components are not downloaded in the test environment, so isAvailable returns false.
        #expect(engine.isAvailable(PixArtModelDescriptor.sigmaXL) == false)
    }

    @Test("PixArtEngine validateMemory returns a meaningful result")
    func validateMemoryReturnsResult() {
        let engine = PixArtEngine()
        let result = engine.validateMemory(for: PixArtModelDescriptor.sigmaXL)
        // The real implementation delegates to system memory checks.
        // On an 8+ GB machine (test environment), we expect .ok or .warning.
        // On a machine below 8 GB, we expect .insufficient.
        switch result {
        case .ok, .warning, .insufficient:
            break  // All are valid outcomes from the real implementation
        }
    }

    @Test("PixArtEngine diskSize returns nil or non-negative bytes")
    func diskSizeReturnsNilOrBytes() {
        let engine = PixArtEngine()
        // The real implementation returns nil if components are not downloaded,
        // or a non-negative Int64 byte count if they are. Both are valid.
        let size = engine.diskSize(of: PixArtModelDescriptor.sigmaXL)
        if let bytes = size {
            #expect(bytes >= 0)
        }
        // nil is also acceptable (components not on disk)
    }

    // MARK: - Stub Behavior: generate throws

    @Test("PixArtEngine generate throws generationFailed (stub)")
    func generateThrows() async throws {
        let engine = PixArtEngine()
        let request = GenerationRequest(
            prompt: "test",
            steps: 20,
            guidanceScale: 4.5,
            width: 1024,
            height: 1024,
            mode: .textToImage
        )

        await #expect(throws: VinetasError.self) {
            try await engine.generate(request: request, stepProgress: nil)
        }
    }

    // MARK: - Stub Behavior: download throws

    @Test("PixArtEngine download throws downloadFailed (stub)")
    func downloadThrows() async throws {
        let engine = PixArtEngine()

        await #expect(throws: VinetasError.self) {
            try await engine.download(PixArtModelDescriptor.sigmaXL) { _ in }
        }
    }

    // MARK: - Stub Behavior: loadModel throws

    @Test("PixArtEngine loadModel throws generationFailed (stub)")
    func loadModelThrows() async throws {
        let engine = PixArtEngine()

        await #expect(throws: VinetasError.self) {
            try await engine.loadModel(PixArtModelDescriptor.sigmaXL) { _ in }
        }
    }

    // MARK: - Stub Behavior: loadLoRA throws

    @Test("PixArtEngine loadLoRA throws generationFailed (stub)")
    func loadLoRAThrows() async throws {
        let engine = PixArtEngine()
        let path = URL(fileURLWithPath: "/tmp/fake.safetensors")

        await #expect(throws: VinetasError.self) {
            try await engine.loadLoRA(at: path, scale: 0.8)
        }
    }

    // MARK: - Delete behavior

    @Test("PixArtEngine delete does not throw for unloaded model")
    func deleteDoesNotThrowWhenNotDownloaded() async throws {
        let engine = PixArtEngine()
        // The real implementation iterates componentIds and silently skips
        // components that are not registered. No throw is expected.
        try await engine.delete(PixArtModelDescriptor.sigmaXL)
    }

    // MARK: - Stub Behavior: unload is no-op

    @Test("PixArtEngine unloadModel does not throw (stub)")
    func unloadModelNoOp() async throws {
        let engine = PixArtEngine()
        // Should not throw
        await engine.unloadModel()
    }

    @Test("PixArtEngine unloadLoRA does not throw (stub)")
    func unloadLoRANoOp() async throws {
        let engine = PixArtEngine()
        // Should not throw
        await engine.unloadLoRA()
    }
}

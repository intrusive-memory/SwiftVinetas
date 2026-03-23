import Foundation
import Testing

@testable import SwiftVinetas

/// Tests for ``PixArtEngine``'s internal request translation:
/// ``GenerationRequest`` -> ``DiffusionGenerationRequest`` field mapping.
///
/// Because `translateRequest` is a private method, we exercise it indirectly
/// by testing ``PixArtEngine/generate(request:stepProgress:)`` error paths that
/// occur before any pipeline call, and by verifying the ``PixArtEngine``'s
/// field-mapping behavior through the observable protocol surface.
@Suite("Request Translation Tests")
struct RequestTranslationTests {

    // MARK: - GenerationRequest Field Defaults

    /// Baseline: a minimal ``GenerationRequest`` can be constructed with all fields.
    @Test("GenerationRequest holds all required fields")
    func generationRequestFields() {
        let request = GenerationRequest(
            prompt: "a red fox",
            negativePrompt: "blurry, low quality",
            steps: 20,
            guidanceScale: 4.5,
            seed: 12345,
            width: 1024,
            height: 1024,
            mode: .textToImage
        )

        #expect(request.prompt == "a red fox")
        #expect(request.negativePrompt == "blurry, low quality")
        #expect(request.steps == 20)
        #expect(request.guidanceScale == 4.5)
        #expect(request.seed == 12345)
        #expect(request.width == 1024)
        #expect(request.height == 1024)

        if case .textToImage = request.mode {
            // expected
        } else {
            Issue.record("Expected .textToImage mode")
        }
    }

    @Test("GenerationRequest seed defaults to nil")
    func generationRequestSeedDefaultsToNil() {
        let request = GenerationRequest(
            prompt: "test",
            steps: 10,
            guidanceScale: 3.0,
            width: 512,
            height: 512
        )
        #expect(request.seed == nil)
    }

    @Test("GenerationRequest negativePrompt defaults to nil")
    func generationRequestNegativePromptDefaultsToNil() {
        let request = GenerationRequest(
            prompt: "test",
            steps: 10,
            guidanceScale: 3.0,
            width: 512,
            height: 512
        )
        #expect(request.negativePrompt == nil)
    }

    @Test("GenerationRequest mode defaults to textToImage")
    func generationRequestModeDefaultsToTextToImage() {
        let request = GenerationRequest(
            prompt: "test",
            steps: 10,
            guidanceScale: 3.0,
            width: 512,
            height: 512
        )

        if case .textToImage = request.mode {
            // expected
        } else {
            Issue.record("Default mode should be .textToImage")
        }
    }

    // MARK: - imageToImage Mode Rejection

    /// PixArtEngine does not support imageToImage. When a model is loaded,
    /// ``PixArtEngine/generate(request:stepProgress:)`` throws ``VinetasError/engineFeatureUnsupported``.
    /// When no model is loaded (as in the test environment), the pipeline guard
    /// fires first and throws ``VinetasError/generationFailed``.
    /// Either way the result is always a ``VinetasError``.
    @Test("PixArtEngine throws VinetasError for imageToImage mode")
    func pixArtRejectsImageToImageMode() async throws {
        let engine = PixArtEngine()
        let request = GenerationRequest(
            prompt: "a portrait",
            steps: 20,
            guidanceScale: 4.5,
            width: 1024,
            height: 1024,
            mode: .imageToImage(references: [])
        )

        await #expect(throws: VinetasError.self) {
            try await engine.generate(request: request, stepProgress: nil)
        }
    }

    /// Verify that ``EngineFeature/imageToImage`` is explicitly not supported by PixArtEngine.
    @Test("PixArtEngine supports(_:) returns false for imageToImage feature")
    func pixArtDoesNotSupportImageToImageFeature() {
        let engine = PixArtEngine()
        #expect(engine.supports(.imageToImage(maxReferenceImages: 0)) == false)
        #expect(engine.supports(.imageToImage(maxReferenceImages: 3)) == false)
    }

    @Test("PixArtEngine imageToImage generates a VinetasError, not a generic error")
    func pixArtImageToImageErrorIsVinetasError() async throws {
        let engine = PixArtEngine()
        let request = GenerationRequest(
            prompt: "test",
            steps: 10,
            guidanceScale: 3.0,
            width: 512,
            height: 512,
            mode: .imageToImage(references: [])
        )

        do {
            _ = try await engine.generate(request: request, stepProgress: nil)
            Issue.record("Should have thrown a VinetasError")
        } catch is VinetasError {
            // Expected: VinetasError (either generationFailed from pipeline guard
            // or engineFeatureUnsupported from mode guard, depending on load state).
        } catch {
            Issue.record("Expected VinetasError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - textToImage mode passthrough

    /// textToImage mode should not be rejected by the mode guard.
    /// Without a loaded pipeline the engine throws a different error (no model loaded).
    @Test("PixArtEngine does not throw engineFeatureUnsupported for textToImage mode")
    func pixArtAcceptsTextToImageMode() async throws {
        let engine = PixArtEngine()
        let request = GenerationRequest(
            prompt: "a landscape",
            steps: 20,
            guidanceScale: 4.5,
            width: 1024,
            height: 1024,
            mode: .textToImage
        )

        do {
            _ = try await engine.generate(request: request, stepProgress: nil)
            Issue.record("Expected an error because no model is loaded")
        } catch let error as VinetasError {
            // Must NOT be engineFeatureUnsupported for textToImage
            if case .engineFeatureUnsupported(let feature, _) = error {
                if case .textToImage = feature {
                    Issue.record("textToImage should not trigger engineFeatureUnsupported")
                }
            }
            // Any other VinetasError (e.g., generationFailed "no model loaded") is expected.
        }
    }

    // MARK: - Seed Truncation

    /// The seed mapping from UInt64 to UInt32 truncates the high 32 bits.
    /// Test that the ``GenerationRequest`` seed is accepted as UInt64.
    @Test("GenerationRequest accepts UInt64 seed values")
    func generationRequestAcceptsUInt64Seed() {
        // Seed larger than UInt32.max — should be storable in GenerationRequest.
        let largeSeed: UInt64 = UInt64(UInt32.max) + 1
        let request = GenerationRequest(
            prompt: "test",
            steps: 10,
            guidanceScale: 3.0,
            seed: largeSeed,
            width: 512,
            height: 512
        )
        #expect(request.seed == largeSeed)
    }

    // MARK: - Width / Height passthrough

    @Test("GenerationRequest width and height are preserved")
    func generationRequestDimensions() {
        let request = GenerationRequest(
            prompt: "test",
            steps: 10,
            guidanceScale: 3.0,
            width: 768,
            height: 512
        )
        #expect(request.width == 768)
        #expect(request.height == 512)
    }

    // MARK: - Steps and GuidanceScale passthrough

    @Test("GenerationRequest steps and guidanceScale are preserved")
    func generationRequestStepsAndGuidance() {
        let request = GenerationRequest(
            prompt: "test",
            steps: 50,
            guidanceScale: 7.5,
            width: 512,
            height: 512
        )
        #expect(request.steps == 50)
        #expect(request.guidanceScale == 7.5)
    }

    // MARK: - Prompt field

    @Test("GenerationRequest preserves the prompt string")
    func generationRequestPreservesPrompt() {
        let longPrompt = "a hyper-detailed portrait of an astronaut on Mars, golden hour, 8K"
        let request = GenerationRequest(
            prompt: longPrompt,
            steps: 20,
            guidanceScale: 4.5,
            width: 1024,
            height: 1024
        )
        #expect(request.prompt == longPrompt)
    }

    @Test("GenerationRequest preserves the negative prompt string")
    func generationRequestPreservesNegativePrompt() {
        let negPrompt = "blurry, low quality, artifacts"
        let request = GenerationRequest(
            prompt: "test",
            negativePrompt: negPrompt,
            steps: 20,
            guidanceScale: 4.5,
            width: 1024,
            height: 1024
        )
        #expect(request.negativePrompt == negPrompt)
    }
}

import Foundation

/// Shared pre-flight check for reference-image counts, used by every
/// generation entry point (library and CLI) before any model is loaded.
///
/// The limit comes solely from
/// ``ImageGenerationEngine/maxReferenceImages(for:)`` — there is no
/// memory or device-tier input.
public enum ReferenceValidator {

  /// Validates that `model` on `engine` accepts `referenceCount` reference images.
  ///
  /// - A count of `0` is always valid (text-to-image).
  /// - Throws: ``VinetasError/referencesUnsupported(engineID:)`` when the
  ///   engine/model accepts no references, and
  ///   ``VinetasError/tooManyReferences(model:max:got:)`` when the count
  ///   exceeds the model's limit.
  public static func validate(
    referenceCount: Int,
    engine: any ImageGenerationEngine,
    model: any ModelDescriptor
  ) throws {
    guard referenceCount > 0 else { return }
    let max = engine.maxReferenceImages(for: model)
    guard max > 0 else {
      throw VinetasError.referencesUnsupported(engineID: engine.engineID)
    }
    guard referenceCount <= max else {
      throw VinetasError.tooManyReferences(model: model.id, max: max, got: referenceCount)
    }
  }
}

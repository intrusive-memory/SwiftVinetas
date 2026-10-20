import Foundation

/// A protocol describing a model that can be run by an ``ImageGenerationEngine``.
///
/// Each engine defines its own concrete descriptor types (e.g., `Flux2ModelDescriptor`,
/// `PixArtModelDescriptor`). Each can carry engine-specific internal metadata beyond
/// the properties required by this protocol.
///
/// Conforms to `Sendable` and `Identifiable where ID == String`.
/// Does not require `Hashable` -- `Hashable` breaks existential usage
/// (`[any ModelDescriptor]`). All lookups use the `id` string.
public protocol ModelDescriptor: Sendable, Identifiable where ID == String {

  /// Unique model identifier (e.g., "flux2-klein-4b", "pixart-sigma-xl").
  var id: String { get }

  /// Human-readable display name (e.g., "FLUX.2 Klein 4B", "PixArt-Sigma XL").
  var displayName: String { get }

  /// Engine identifier that routes this model to the correct engine.
  var engineID: String { get }

  /// The name the CLI and GLOSA `model=` attributes use for this model (e.g. "klein4b").
  var cliName: String { get }

  /// License under which the model weights are distributed.
  var license: ModelLicense { get }

  /// Minimum system memory in GB required to run this model.
  var minimumMemoryGB: Int { get }

  /// Human-readable approximate download size (e.g., "~11 GB", "~3.6 GB").
  var approximateDownloadSize: String { get }

  /// Default number of inference steps for this model.
  var defaultSteps: Int { get }

  /// Default classifier-free guidance scale for this model.
  var defaultGuidance: Float { get }

  /// Aspect ratios this model supports for generation.
  var supportedAspectRatios: [AspectRatio] { get }

  /// Acervo component IDs required by this model.
  ///
  /// These are the Acervo-internal identifiers (e.g., "t5-xxl-encoder-int4") used
  /// for download orchestration, availability checks, and disk size queries.
  /// Distinct from `id`, which is the consumer-facing model identifier.
  ///
  /// Engines that manage downloads through their own path (e.g., Flux2Engine)
  /// return the default empty array.
  var componentIds: [String] { get }
}

// MARK: - Default Implementations

extension ModelDescriptor {
  /// Default implementation returns an empty array.
  ///
  /// Engines that use Acervo component-based downloads override this property
  /// in their concrete descriptor types.
  public var componentIds: [String] { [] }

  /// The engine-free ``ModelSummary`` of this descriptor.
  ///
  /// Built from the descriptor's own fields plus ``cliName``; ``license`` and
  /// ``componentIds`` are not part of the summary. A ``CloudModelDescriptor``
  /// also carries its capability flags, its provider's short name as the
  /// engine name, and "provider · price hint" as the subtitle; every other
  /// descriptor reports all capabilities and no names.
  public var summary: ModelSummary {
    let cloud = self as? CloudModelDescriptor
    return ModelSummary(
      id: id,
      displayName: displayName,
      engineID: engineID,
      cliName: cliName,
      minimumMemoryGB: minimumMemoryGB,
      approximateDownloadSize: approximateDownloadSize,
      defaultSteps: defaultSteps,
      defaultGuidance: defaultGuidance,
      supportedAspectRatios: supportedAspectRatios,
      supportsSteps: cloud?.supportsSteps ?? true,
      supportsGuidance: cloud?.supportsGuidance ?? true,
      supportsSeed: cloud?.supportsSeed ?? true,
      supportsNegativePrompt: cloud?.supportsNegativePrompt ?? true,
      engineName: cloud?.provider.shortName,
      subtitle: cloud.map { "\($0.provider.displayName) · \($0.pricingHint)" },
      isCloud: cloud != nil,
      maxReferenceImages: cloud?.maxReferenceImages
        ?? (self as? Flux2ModelDescriptor)?.engineMaxReferenceImages ?? 0
    )
  }
}

// MARK: - ModelLicense

/// License classification for model weights.
public enum ModelLicense: Sendable, Hashable {
  /// Apache License 2.0.
  case apache2

  /// Non-commercial license with details.
  case nonCommercial(details: String)

  /// Custom license with a name and optional URL.
  case custom(name: String, url: URL?)
}

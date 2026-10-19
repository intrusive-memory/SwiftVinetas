import Foundation

/// A ``ModelDescriptor`` for a model hosted by a ``CloudProvider``.
///
/// Conforms to the same descriptor protocol as the on-device models so cloud
/// models flow through ``EngineRouter``, ``VinetasClient`` and the CLI's
/// `--model` flag unchanged. Nothing is downloaded and no unified memory is
/// required, so ``minimumMemoryGB`` is `0` and ``approximateDownloadSize``
/// reads "Cloud".
///
/// The capability flags describe which ``GenerationRequest`` fields the vendor
/// honours. Hosts disable the matching controls (or warn, as the CLI does)
/// instead of silently dropping them.
public struct CloudModelDescriptor: ModelDescriptor, Hashable {

  public let id: String
  public let displayName: String
  public let provider: CloudProvider

  /// The identifier the vendor's API expects (e.g. `gpt-image-2.5-flare`,
  /// `flux-2-pro`, `core`).
  public let vendorModelID: String

  public let defaultSteps: Int
  public let defaultGuidance: Float
  public let supportedAspectRatios: [AspectRatio]

  /// Whether the vendor accepts an inference step count.
  public let supportsSteps: Bool
  /// Whether the vendor accepts a guidance scale.
  public let supportsGuidance: Bool
  /// Whether the vendor accepts a seed (and therefore can be reproducible).
  public let supportsSeed: Bool
  /// Whether the vendor accepts a negative prompt.
  public let supportsNegativePrompt: Bool

  /// A short, non-authoritative price hint ("~$0.03/image").
  public let pricingHint: String

  public var engineID: String { provider.engineID }

  /// Cloud models are addressed on the CLI by their full id
  /// (e.g. `--model openai-gpt-image-2.5-flare`).
  public var cliName: String { id }

  public var license: ModelLicense {
    .custom(name: "\(provider.displayName) Terms of Service", url: provider.termsURL)
  }
  public var minimumMemoryGB: Int { 0 }
  public var approximateDownloadSize: String { "Cloud" }

  public init(
    id: String,
    displayName: String,
    provider: CloudProvider,
    vendorModelID: String,
    defaultSteps: Int,
    defaultGuidance: Float,
    supportedAspectRatios: [AspectRatio],
    supportsSteps: Bool,
    supportsGuidance: Bool,
    supportsSeed: Bool,
    supportsNegativePrompt: Bool,
    pricingHint: String
  ) {
    self.id = id
    self.displayName = displayName
    self.provider = provider
    self.vendorModelID = vendorModelID
    self.defaultSteps = defaultSteps
    self.defaultGuidance = defaultGuidance
    self.supportedAspectRatios = supportedAspectRatios
    self.supportsSteps = supportsSteps
    self.supportsGuidance = supportsGuidance
    self.supportsSeed = supportsSeed
    self.supportsNegativePrompt = supportsNegativePrompt
    self.pricingHint = pricingHint
  }

  // MARK: - Catalog

  /// Every aspect ratio Vinetas offers; cloud vendors that take explicit
  /// dimensions can honour all of them.
  private static let allRatios: [AspectRatio] = AspectRatio.allCases

  /// Ratios OpenAI and Google accept (1:3 … 3:1); the 4:1 strip is out of range.
  private static let widescreenRatios: [AspectRatio] = [
    .square, .wide, .ultrawide, .portrait, .panel,
  ]

  /// OpenAI `gpt-image-2.5-flare`, the vendor's default: explicit sizes in
  /// multiples of 16; no steps, guidance, seed, or negative prompt.
  public static let gptImage25Flare = CloudModelDescriptor(
    id: "openai-gpt-image-2.5-flare",
    displayName: "GPT Image 2.5 Flare",
    provider: .openAI,
    vendorModelID: "gpt-image-2.5-flare",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "~$0.03–0.25/image"
  )

  /// OpenAI `gpt-image-2.5-sunburst`, the slower premium sibling.
  public static let gptImage25Sunburst = CloudModelDescriptor(
    id: "openai-gpt-image-2.5-sunburst",
    displayName: "GPT Image 2.5 Sunburst",
    provider: .openAI,
    vendorModelID: "gpt-image-2.5-sunburst",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "~$0.03–0.25/image"
  )

  /// Google `gemini-nano-banana-2.1`, the recommended default. Aspect-ratio
  /// presets and a 1K/2K/4K size tier; no steps, guidance, seed, or
  /// negative prompt.
  public static let nanoBanana21 = CloudModelDescriptor(
    id: "google-nano-banana-2.1",
    displayName: "Nano Banana 2.1",
    provider: .google,
    vendorModelID: "gemini-nano-banana-2.1",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "~$0.03–0.11/image"
  )

  /// Google `gemini-3.1-flash-image`, tuned for sequential art.
  public static let gemini31FlashImage = CloudModelDescriptor(
    id: "google-gemini-3.1-flash-image",
    displayName: "Gemini 3.1 Flash Image",
    provider: .google,
    vendorModelID: "gemini-3.1-flash-image",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "~$0.07–0.15/image"
  )

  /// Google `gemini-3-pro-image`, for text rendering and production assets.
  public static let gemini3ProImage = CloudModelDescriptor(
    id: "google-gemini-3-pro-image",
    displayName: "Gemini 3 Pro Image",
    provider: .google,
    vendorModelID: "gemini-3-pro-image",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "~$0.13–0.24/image"
  )

  /// Black Forest Labs `flux-2-pro`. Explicit dimensions and seed; the
  /// schedule is fixed server-side.
  public static let flux2Pro = CloudModelDescriptor(
    id: "bfl-flux-2-pro",
    displayName: "FLUX.2 [pro]",
    provider: .blackForestLabs,
    vendorModelID: "flux-2-pro",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: allRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: true,
    supportsNegativePrompt: false,
    pricingHint: "~$0.03/MP"
  )

  /// Black Forest Labs `flux-2-flex`. Exposes steps and guidance.
  public static let flux2Flex = CloudModelDescriptor(
    id: "bfl-flux-2-flex",
    displayName: "FLUX.2 [flex]",
    provider: .blackForestLabs,
    vendorModelID: "flux-2-flex",
    defaultSteps: 28,
    defaultGuidance: 3.5,
    supportedAspectRatios: allRatios,
    supportsSteps: true,
    supportsGuidance: true,
    supportsSeed: true,
    supportsNegativePrompt: false,
    pricingHint: "~$0.06/MP"
  )

  /// Stability AI Stable Image Core. Aspect-ratio presets only, so the 4:1
  /// strip is unavailable.
  public static let stableImageCore = CloudModelDescriptor(
    id: "stability-core",
    displayName: "Stable Image Core",
    provider: .stabilityAI,
    vendorModelID: "core",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: [.square, .wide, .ultrawide, .portrait, .panel],
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: true,
    supportsNegativePrompt: true,
    pricingHint: "3 credits/image"
  )

  /// Stability AI Stable Image Ultra.
  public static let stableImageUltra = CloudModelDescriptor(
    id: "stability-ultra",
    displayName: "Stable Image Ultra",
    provider: .stabilityAI,
    vendorModelID: "ultra",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: [.square, .wide, .ultrawide, .portrait, .panel],
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: true,
    supportsNegativePrompt: true,
    pricingHint: "8 credits/image"
  )

  /// Every cloud model across every provider, in provider → model order.
  public static let all: [CloudModelDescriptor] = CloudProvider.allCases.flatMap(\.models)

  /// Slug → descriptor lookup over ``all``.
  public static let byID: [String: CloudModelDescriptor] =
    Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

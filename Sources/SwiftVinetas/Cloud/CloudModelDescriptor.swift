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

  /// Other vendor IDs that mean this model, such as a dated snapshot. Matched
  /// exactly, never by prefix (R-3).
  public let vendorAliases: [String]

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

  /// How many reference images the vendor accepts for one request. `0`
  /// means the adapter sends text only.
  public let maxReferenceImages: Int

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
    pricingHint: String,
    maxReferenceImages: Int = 0,
    vendorAliases: [String] = []
  ) {
    self.id = id
    self.displayName = displayName
    self.provider = provider
    self.vendorModelID = vendorModelID
    self.vendorAliases = vendorAliases
    self.defaultSteps = defaultSteps
    self.defaultGuidance = defaultGuidance
    self.supportedAspectRatios = supportedAspectRatios
    self.supportsSteps = supportsSteps
    self.supportsGuidance = supportsGuidance
    self.supportsSeed = supportsSeed
    self.supportsNegativePrompt = supportsNegativePrompt
    self.pricingHint = pricingHint
    self.maxReferenceImages = maxReferenceImages
  }

  /// Whether `vendorID`, as a vendor lists it, is this model: an exact match on
  /// ``vendorModelID`` or one of ``vendorAliases``.
  public func matches(vendorID: String) -> Bool {
    vendorID == vendorModelID || vendorAliases.contains(vendorID)
  }

  // MARK: - Catalog

  /// Every aspect ratio Vinetas offers; cloud vendors that take explicit
  /// dimensions can honour all of them.
  private static let allRatios: [AspectRatio] = AspectRatio.allCases

  /// Ratios OpenAI and Google accept (1:3 … 3:1); the 4:1 strip is out of range.
  private static let widescreenRatios: [AspectRatio] = [
    .square, .wide, .ultrawide, .portrait, .panel,
  ]

  /// OpenAI's edits endpoint takes repeated `image[]` parts. The vendor
  /// documents no hard limit for the 2.5 family; ten keeps the multipart
  /// body well under its upload cap after downscaling.
  private static let openAIReferenceLimit = 10

  /// OpenAI `gpt-image-2.6-flare`, the 2.6 successor to 2.5 Flare.
  ///
  /// Sources (fetched 2026-11-26):
  /// - https://developers.openai.com/api/docs/models/gpt-image-2.6-flare: text and image input,
  ///   image output; `v1/images/generations` and `v1/images/edits`; image output
  ///   billed at $30 per 1M tokens (no per-image price is published).
  /// - https://developers.openai.com/api/docs/guides/image-generation: sizes in
  ///   multiples of 16, edges up to 3840, ratio between 1:3 and 3:1 (so the 4:1
  ///   strip is out); no steps, guidance, seed or negative-prompt parameter is
  ///   documented, so none are enabled.
  /// - Reference-image limit: not documented for 2.6; assumed same as
  ///   gpt-image-2.5-flare (`openAIReferenceLimit`).
  public static let gptImage26Flare = CloudModelDescriptor(
    id: "openai-gpt-image-2.6-flare",
    displayName: "GPT Image 2.6 Flare",
    provider: .openAI,
    vendorModelID: "gpt-image-2.6-flare",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "$30/1M image output tokens",
    maxReferenceImages: openAIReferenceLimit
  )

  /// OpenAI `gpt-image-2.6-sunburst`, the 2.6 successor to 2.5 Sunburst.
  ///
  /// Sources (fetched 2026-11-26):
  /// - https://developers.openai.com/api/docs/models/gpt-image-2.6-sunburst: text and image input,
  ///   image output; `v1/images/generations` and `v1/images/edits`; image output
  ///   billed at $30 per 1M tokens (no per-image price is published).
  /// - https://developers.openai.com/api/docs/guides/image-generation: sizes in
  ///   multiples of 16, edges up to 3840, ratio between 1:3 and 3:1 (so the 4:1
  ///   strip is out); no steps, guidance, seed or negative-prompt parameter is
  ///   documented, so none are enabled.
  /// - Reference-image limit: not documented for 2.6; assumed same as
  ///   gpt-image-2.5-flare (`openAIReferenceLimit`).
  public static let gptImage26Sunburst = CloudModelDescriptor(
    id: "openai-gpt-image-2.6-sunburst",
    displayName: "GPT Image 2.6 Sunburst",
    provider: .openAI,
    vendorModelID: "gpt-image-2.6-sunburst",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "$30/1M image output tokens",
    maxReferenceImages: openAIReferenceLimit
  )

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
    pricingHint: "~$0.03–0.25/image",
    maxReferenceImages: openAIReferenceLimit,
    vendorAliases: ["gpt-image-2.5-flare-2026-09-08"]
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
    pricingHint: "~$0.03–0.25/image",
    maxReferenceImages: openAIReferenceLimit,
    vendorAliases: ["gpt-image-2.5-sunburst-2026-09-08"]
  )

  /// Google's image models take up to 10 object references (Nano Banana 2.1,
  /// 3.1 Flash Image) or 6 (3 Pro Image), inline as base64 `image` blocks.
  ///
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
    pricingHint: "~$0.03–0.11/image",
    maxReferenceImages: 10
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
    pricingHint: "~$0.07–0.15/image",
    maxReferenceImages: 10
  )

  /// Google `gemini-3.1-flash-lite-image`, the lower-cost Flash tier.
  ///
  /// Sources (fetched 2026-11-26):
  /// - https://aistudio.google.com/docs/models/gemini-3.1-flash-lite-image
  ///   (formerly ai.google.dev/gemini-api/docs/models/...): 14 aspect ratios
  ///   including 1:1, 3:2, 16:9, 9:16 and 21:9 (so every ratio in
  ///   `widescreenRatios` is covered); 1K output only (no 2K/4K); a 1K image is
  ///   1,120 tokens at $30 per 1M, about $0.0336 per image.
  /// - https://aistudio.google.com/docs/image-generation: the model is "not
  ///   optimized for multiple reference inputs"; seed and negative prompt are
  ///   not documented, so neither is enabled.
  /// - Reference-image limit: no maximum documented; assumed same as
  ///   gemini-3.1-flash-image (10).
  public static let gemini31FlashLiteImage = CloudModelDescriptor(
    id: "google-gemini-3.1-flash-lite-image",
    displayName: "Gemini 3.1 Flash Lite Image",
    provider: .google,
    vendorModelID: "gemini-3.1-flash-lite-image",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    pricingHint: "~$0.034/image (1K)",
    maxReferenceImages: 10
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
    pricingHint: "~$0.13–0.24/image",
    maxReferenceImages: 6
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

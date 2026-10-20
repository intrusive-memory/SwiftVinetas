import Foundation

/// An engine-free description of an image-generation model a host can offer.
///
/// `ModelSummary` carries the subset of a model descriptor that a picker or
/// settings screen needs — identity, the CLI name, memory and download
/// expectations, and the generation defaults — without linking any inference
/// stack. The two on-device models are ``klein4B`` and ``pixartSigmaXL``; ``all``
/// lists only them, in display order. ``cloud`` lists the cloud models and
/// ``allIncludingCloud`` both.
///
/// The four `supports…` flags say which generation controls the model
/// honours; a host disables the matching control when one is `false`. They,
/// ``engineName`` and ``subtitle`` exist for cloud models: the on-device
/// models answer `true` to every flag and `nil` to both names.
///
/// `AspectRatio` is not itself `Codable`, so ``supportedAspectRatios`` is
/// encoded as an array of each ratio's `rawValue`. A summary encoded before
/// the capability fields existed (0.22.0, 0.23.0) still decodes: a missing
/// flag reads `true` and a missing name reads `nil`.
public struct ModelSummary: Hashable, Sendable, Identifiable, Codable {
  /// Unique model identifier, the value a prompt draft's `modelID` holds
  /// (e.g. `"flux2-klein-4b"`).
  public let id: String

  /// Human-readable display name (e.g. `"FLUX.2 Klein 4B"`).
  public let displayName: String

  /// Identifier of the engine that runs this model (e.g. `"flux2"`).
  public let engineID: String

  /// The external name: the one the CLI and GLOSA `model=` attributes use
  /// (e.g. `"klein4b"`).
  public let cliName: String

  /// Minimum system memory in GB required to run this model.
  public let minimumMemoryGB: Int

  /// Human-readable approximate download size (e.g. `"~11 GB"`).
  public let approximateDownloadSize: String

  /// Default number of inference steps for this model.
  public let defaultSteps: Int

  /// Default classifier-free guidance scale for this model.
  public let defaultGuidance: Float

  /// Aspect ratios this model supports for generation.
  public let supportedAspectRatios: [AspectRatio]

  /// Whether the model accepts an inference step count. `true` for every
  /// on-device model.
  public let supportsSteps: Bool

  /// Whether the model accepts a guidance scale. `true` for every on-device
  /// model.
  public let supportsGuidance: Bool

  /// Whether the model accepts a seed, and so can reproduce an image. `true`
  /// for every on-device model.
  public let supportsSeed: Bool

  /// Whether the model accepts a negative prompt. `true` for every on-device
  /// model.
  public let supportsNegativePrompt: Bool

  /// The short engine name a picker section or engine badge shows (e.g.
  /// `"OpenAI"` for a cloud model), or `nil` to let the host name the engine
  /// from ``engineID``.
  public let engineName: String?

  /// One line describing the model in a picker (e.g. `"OpenAI · ~$0.03/image"`
  /// for a cloud model), or `nil` to show the download size and memory.
  public let subtitle: String?

  /// Whether the model runs in a vendor's cloud rather than on device. `false`
  /// for the on-device models and for a summary encoded before this field
  /// existed.
  public let isCloud: Bool

  /// How many reference images the model accepts for one request; `0` means
  /// it takes none. A host caps a reference list at this value and disables
  /// the control at `0`. A summary encoded before this field existed reads `0`.
  public let maxReferenceImages: Int

  /// Creates a model summary from its individual fields.
  ///
  /// The capability flags default to `true` and the two names to `nil`,
  /// which is what an on-device model reports.
  public init(
    id: String,
    displayName: String,
    engineID: String,
    cliName: String,
    minimumMemoryGB: Int,
    approximateDownloadSize: String,
    defaultSteps: Int,
    defaultGuidance: Float,
    supportedAspectRatios: [AspectRatio],
    supportsSteps: Bool = true,
    supportsGuidance: Bool = true,
    supportsSeed: Bool = true,
    supportsNegativePrompt: Bool = true,
    engineName: String? = nil,
    subtitle: String? = nil,
    isCloud: Bool = false,
    maxReferenceImages: Int = 0
  ) {
    self.id = id
    self.displayName = displayName
    self.engineID = engineID
    self.cliName = cliName
    self.minimumMemoryGB = minimumMemoryGB
    self.approximateDownloadSize = approximateDownloadSize
    self.defaultSteps = defaultSteps
    self.defaultGuidance = defaultGuidance
    self.supportedAspectRatios = supportedAspectRatios
    self.supportsSteps = supportsSteps
    self.supportsGuidance = supportsGuidance
    self.supportsSeed = supportsSeed
    self.supportsNegativePrompt = supportsNegativePrompt
    self.engineName = engineName
    self.subtitle = subtitle
    self.isCloud = isCloud
    self.maxReferenceImages = maxReferenceImages
  }

  // MARK: - Codable

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case engineID
    case cliName
    case minimumMemoryGB
    case approximateDownloadSize
    case defaultSteps
    case defaultGuidance
    case supportedAspectRatios
    case supportsSteps
    case supportsGuidance
    case supportsSeed
    case supportsNegativePrompt
    case engineName
    case subtitle
    case isCloud
    case maxReferenceImages
  }

  /// Decodes a summary, reading ``supportedAspectRatios`` as `rawValue` strings.
  ///
  /// A missing capability flag decodes as `true` and a missing
  /// ``engineName`` or ``subtitle`` as `nil`, so summaries encoded by 0.22.0
  /// and 0.23.0 still decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    engineID = try container.decode(String.self, forKey: .engineID)
    cliName = try container.decode(String.self, forKey: .cliName)
    minimumMemoryGB = try container.decode(Int.self, forKey: .minimumMemoryGB)
    approximateDownloadSize = try container.decode(String.self, forKey: .approximateDownloadSize)
    defaultSteps = try container.decode(Int.self, forKey: .defaultSteps)
    defaultGuidance = try container.decode(Float.self, forKey: .defaultGuidance)
    let rawRatios = try container.decode([String].self, forKey: .supportedAspectRatios)
    supportedAspectRatios = try rawRatios.map { raw in
      guard let ratio = AspectRatio(rawValue: raw) else {
        throw DecodingError.dataCorruptedError(
          forKey: .supportedAspectRatios,
          in: container,
          debugDescription: "Unknown aspect ratio \"\(raw)\"."
        )
      }
      return ratio
    }
    supportsSteps = try container.decodeIfPresent(Bool.self, forKey: .supportsSteps) ?? true
    supportsGuidance = try container.decodeIfPresent(Bool.self, forKey: .supportsGuidance) ?? true
    supportsSeed = try container.decodeIfPresent(Bool.self, forKey: .supportsSeed) ?? true
    supportsNegativePrompt =
      try container.decodeIfPresent(Bool.self, forKey: .supportsNegativePrompt) ?? true
    engineName = try container.decodeIfPresent(String.self, forKey: .engineName)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    isCloud = try container.decodeIfPresent(Bool.self, forKey: .isCloud) ?? false
    maxReferenceImages =
      try container.decodeIfPresent(Int.self, forKey: .maxReferenceImages) ?? 0
  }

  /// Encodes a summary, writing ``supportedAspectRatios`` as `rawValue` strings.
  ///
  /// The capability flags are always written; a `nil` ``engineName`` or
  /// ``subtitle`` is omitted.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(engineID, forKey: .engineID)
    try container.encode(cliName, forKey: .cliName)
    try container.encode(minimumMemoryGB, forKey: .minimumMemoryGB)
    try container.encode(approximateDownloadSize, forKey: .approximateDownloadSize)
    try container.encode(defaultSteps, forKey: .defaultSteps)
    try container.encode(defaultGuidance, forKey: .defaultGuidance)
    try container.encode(supportedAspectRatios.map(\.rawValue), forKey: .supportedAspectRatios)
    try container.encode(supportsSteps, forKey: .supportsSteps)
    try container.encode(supportsGuidance, forKey: .supportsGuidance)
    try container.encode(supportsSeed, forKey: .supportsSeed)
    try container.encode(supportsNegativePrompt, forKey: .supportsNegativePrompt)
    try container.encodeIfPresent(engineName, forKey: .engineName)
    try container.encodeIfPresent(subtitle, forKey: .subtitle)
    try container.encode(isCloud, forKey: .isCloud)
    try container.encode(maxReferenceImages, forKey: .maxReferenceImages)
  }

  // MARK: - Shipped models

  /// FLUX.2 Klein 4B — fast generation, 16 GB minimum.
  public static let klein4B = ModelSummary(
    id: "flux2-klein-4b",
    displayName: "FLUX.2 Klein 4B",
    engineID: "flux2",
    cliName: "klein4b",
    minimumMemoryGB: 16,
    approximateDownloadSize: "~11 GB",
    defaultSteps: 8,
    defaultGuidance: 3.5,
    supportedAspectRatios: AspectRatio.allCases,
    maxReferenceImages: 3
  )

  /// PixArt-Sigma XL — 8 GB minimum.
  public static let pixartSigmaXL = ModelSummary(
    id: "pixart-sigma-xl",
    displayName: "PixArt-Sigma XL",
    engineID: "pixart-sigma",
    cliName: "pixart-sigma",
    minimumMemoryGB: 8,
    approximateDownloadSize: "~3.6 GB",
    defaultSteps: 20,
    defaultGuidance: 4.5,
    supportedAspectRatios: AspectRatio.allCases
  )

  /// Every shipped model, FLUX.2 first and then PixArt.
  public static let all: [ModelSummary] = [klein4B, pixartSigmaXL]

  // MARK: - Cloud models

  /// Ratios OpenAI and Google accept (1:3 … 3:1); the 4:1 strip is out of range.
  private static let widescreenRatios: [AspectRatio] = [
    .square, .wide, .ultrawide, .portrait, .panel,
  ]

  /// Ratios Stability's presets accept; the 4:1 strip is unavailable.
  private static let noStrip: [AspectRatio] = [
    .square, .wide, .ultrawide, .portrait, .panel,
  ]

  /// GPT Image 2.5 Flare (cloud, OpenAI).
  public static let openaiGPTImage25Flare = ModelSummary(
    id: "openai-gpt-image-2.5-flare",
    displayName: "GPT Image 2.5 Flare",
    engineID: "cloud-openai",
    cliName: "openai-gpt-image-2.5-flare",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    engineName: "OpenAI",
    subtitle: "OpenAI · ~$0.03–0.25/image",
    isCloud: true,
    maxReferenceImages: 10
  )

  /// GPT Image 2.5 Sunburst (cloud, OpenAI).
  public static let openaiGPTImage25Sunburst = ModelSummary(
    id: "openai-gpt-image-2.5-sunburst",
    displayName: "GPT Image 2.5 Sunburst",
    engineID: "cloud-openai",
    cliName: "openai-gpt-image-2.5-sunburst",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    engineName: "OpenAI",
    subtitle: "OpenAI · ~$0.03–0.25/image",
    isCloud: true,
    maxReferenceImages: 10
  )

  /// Nano Banana 2.1 (cloud, Google).
  public static let googleNanoBanana21 = ModelSummary(
    id: "google-nano-banana-2.1",
    displayName: "Nano Banana 2.1",
    engineID: "cloud-google",
    cliName: "google-nano-banana-2.1",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    engineName: "Gemini",
    subtitle: "Google · ~$0.03–0.11/image",
    isCloud: true,
    maxReferenceImages: 10
  )

  /// Gemini 3.1 Flash Image (cloud, Google).
  public static let googleGemini31FlashImage = ModelSummary(
    id: "google-gemini-3.1-flash-image",
    displayName: "Gemini 3.1 Flash Image",
    engineID: "cloud-google",
    cliName: "google-gemini-3.1-flash-image",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    engineName: "Gemini",
    subtitle: "Google · ~$0.07–0.15/image",
    isCloud: true,
    maxReferenceImages: 10
  )

  /// Gemini 3 Pro Image (cloud, Google).
  public static let googleGemini3ProImage = ModelSummary(
    id: "google-gemini-3-pro-image",
    displayName: "Gemini 3 Pro Image",
    engineID: "cloud-google",
    cliName: "google-gemini-3-pro-image",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: widescreenRatios,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    engineName: "Gemini",
    subtitle: "Google · ~$0.13–0.24/image",
    isCloud: true,
    maxReferenceImages: 6
  )

  /// FLUX.2 [pro] (cloud, Black Forest Labs).
  public static let bflFluxPro = ModelSummary(
    id: "bfl-flux-2-pro",
    displayName: "FLUX.2 [pro]",
    engineID: "cloud-bfl",
    cliName: "bfl-flux-2-pro",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: AspectRatio.allCases,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: true,
    supportsNegativePrompt: false,
    engineName: "BFL",
    subtitle: "Black Forest Labs · ~$0.03/MP",
    isCloud: true,
    maxReferenceImages: 0
  )

  /// FLUX.2 [flex] (cloud, Black Forest Labs).
  public static let bflFluxFlex = ModelSummary(
    id: "bfl-flux-2-flex",
    displayName: "FLUX.2 [flex]",
    engineID: "cloud-bfl",
    cliName: "bfl-flux-2-flex",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 28,
    defaultGuidance: 3.5,
    supportedAspectRatios: AspectRatio.allCases,
    supportsSteps: true,
    supportsGuidance: true,
    supportsSeed: true,
    supportsNegativePrompt: false,
    engineName: "BFL",
    subtitle: "Black Forest Labs · ~$0.06/MP",
    isCloud: true,
    maxReferenceImages: 0
  )

  /// Stable Image Core (cloud, Stability AI).
  public static let stabilityCore = ModelSummary(
    id: "stability-core",
    displayName: "Stable Image Core",
    engineID: "cloud-stability",
    cliName: "stability-core",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: noStrip,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: true,
    supportsNegativePrompt: true,
    engineName: "Stability",
    subtitle: "Stability AI · 3 credits/image",
    isCloud: true,
    maxReferenceImages: 0
  )

  /// Stable Image Ultra (cloud, Stability AI).
  public static let stabilityUltra = ModelSummary(
    id: "stability-ultra",
    displayName: "Stable Image Ultra",
    engineID: "cloud-stability",
    cliName: "stability-ultra",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: noStrip,
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: true,
    supportsNegativePrompt: true,
    engineName: "Stability",
    subtitle: "Stability AI · 8 credits/image",
    isCloud: true,
    maxReferenceImages: 0
  )

  /// The nine cloud models, in the order of the core's cloud catalog.
  ///
  /// Hand-maintained: this module links no networking, so it cannot read the
  /// core's cloud catalog. `SwiftVinetasTests` asserts the list equals the
  /// core's own mapping, so a drift fails the build.
  public static let cloud: [ModelSummary] = [
    openaiGPTImage25Flare,
    openaiGPTImage25Sunburst,
    googleNanoBanana21,
    googleGemini31FlashImage,
    googleGemini3ProImage,
    bflFluxPro,
    bflFluxFlex,
    stabilityCore,
    stabilityUltra,
  ]

  /// Every on-device and cloud model: ``all`` followed by ``cloud``.
  public static let allIncludingCloud: [ModelSummary] = all + cloud

  /// Returns the model whose ``cliName`` is `cli`, searching the on-device
  /// and the cloud models, or `nil` if none matches.
  public static func named(cli: String) -> ModelSummary? {
    allIncludingCloud.first { $0.cliName == cli }
  }
}

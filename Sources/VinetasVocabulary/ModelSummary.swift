import Foundation

/// An engine-free description of an image-generation model a host can offer.
///
/// `ModelSummary` carries the subset of a model descriptor that a picker or
/// settings screen needs — identity, the CLI name, memory and download
/// expectations, and the generation defaults — without linking any inference
/// stack. The two shipped models are ``klein4B`` and ``pixartSigmaXL``; ``all``
/// lists them in display order.
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
    subtitle: String? = nil
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
    supportedAspectRatios: AspectRatio.allCases
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

  /// Returns the shipped model whose ``cliName`` is `cli`, or `nil` if none matches.
  public static func named(cli: String) -> ModelSummary? {
    all.first { $0.cliName == cli }
  }
}

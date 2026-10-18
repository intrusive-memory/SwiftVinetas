import Foundation

/// An engine-free description of an image-generation model a host can offer.
///
/// `ModelSummary` carries the subset of a model descriptor that a picker or
/// settings screen needs — identity, the CLI name, memory and download
/// expectations, and the generation defaults — without linking any inference
/// stack. The two shipped models are ``klein4B`` and ``pixartSigmaXL``; ``all``
/// lists them in display order.
///
/// `AspectRatio` is not itself `Codable`, so ``supportedAspectRatios`` is
/// encoded as an array of each ratio's `rawValue`.
public struct ModelSummary: Hashable, Sendable, Identifiable, Codable {
  /// Unique model identifier (e.g. `"flux2-klein-4b"`).
  public let id: String

  /// Human-readable display name (e.g. `"FLUX.2 Klein 4B"`).
  public let displayName: String

  /// Identifier of the engine that runs this model (e.g. `"flux2"`).
  public let engineID: String

  /// The name the CLI and GLOSA `model=` attributes use (e.g. `"klein4b"`).
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

  /// Creates a model summary from its individual fields.
  public init(
    id: String,
    displayName: String,
    engineID: String,
    cliName: String,
    minimumMemoryGB: Int,
    approximateDownloadSize: String,
    defaultSteps: Int,
    defaultGuidance: Float,
    supportedAspectRatios: [AspectRatio]
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
  }

  /// Decodes a summary, reading ``supportedAspectRatios`` as `rawValue` strings.
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
  }

  /// Encodes a summary, writing ``supportedAspectRatios`` as `rawValue` strings.
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

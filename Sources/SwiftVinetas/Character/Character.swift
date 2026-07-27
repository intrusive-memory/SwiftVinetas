import Foundation
import YAML

// MARK: - LoRAMetadata

/// Metadata describing a trained LoRA adapter for a character.
public struct LoRAMetadata: Sendable {
  /// Relative path to the safetensors file (relative to character directory).
  public var path: String

  /// Blend scale for this LoRA adapter (0.0–1.0).
  public var scale: Float

  /// Monotonically incrementing version number (1-based).
  public var version: Int

  /// When this LoRA was trained. Nil if not recorded.
  public var trainedAt: Date?

  /// Number of training steps used to produce this LoRA.
  public var trainingSteps: Int?

  /// The engine IDs this LoRA is compatible with (e.g., `["flux2"]`).
  ///
  /// Replaces the legacy `model: VinetasModel?` field. Old YAML files containing
  /// `model: klein4b` or `model: klein9b` are migrated during deserialization to
  /// `compatibleEngines: ["flux2"]`.
  public var compatibleEngines: [String]

  /// Whether this LoRA may be used with the given engine.
  ///
  /// An empty `compatibleEngines` means no restriction was recorded, which is
  /// treated as compatible with everything — LoRAs trained before the field
  /// existed must keep working.
  ///
  /// This lives on the metadata rather than inside the client because it is the
  /// single definition of the rule. It was previously a `private` method on
  /// `Vinetas`, which its tests could not reach, so they re-implemented the
  /// branch inline and asserted against their own copy — meaning the real rule
  /// had no coverage and could have been inverted without failing anything.
  public func isCompatible(with engineID: String) -> Bool {
    guard !compatibleEngines.isEmpty else { return true }
    return compatibleEngines.contains(engineID)
  }

  public init(
    path: String,
    scale: Float = 0.8,
    version: Int = 1,
    trainedAt: Date? = nil,
    trainingSteps: Int? = nil,
    compatibleEngines: [String] = []
  ) {
    self.path = path
    self.scale = scale
    self.version = version
    self.trainedAt = trainedAt
    self.trainingSteps = trainingSteps
    self.compatibleEngines = compatibleEngines
  }

  /// Deprecated initializer that accepted a `VinetasModel?` field.
  ///
  /// Use ``init(path:scale:version:trainedAt:trainingSteps:compatibleEngines:)`` instead.
  /// Migrates `klein4b`/`klein9b` to `compatibleEngines: ["flux2"]`.
  @available(
    *, deprecated,
    message: "Use init(path:scale:version:trainedAt:trainingSteps:compatibleEngines:) instead"
  )
  public init(
    path: String,
    scale: Float = 0.8,
    version: Int = 1,
    trainedAt: Date? = nil,
    trainingSteps: Int? = nil,
    model: VinetasModel?
  ) {
    self.path = path
    self.scale = scale
    self.version = version
    self.trainedAt = trainedAt
    self.trainingSteps = trainingSteps
    // Migrate model to compatibleEngines
    switch model {
    case .klein4b, .klein9b:
      self.compatibleEngines = ["flux2"]
    case .pixartSigma:
      self.compatibleEngines = ["pixart-sigma"]
    case nil:
      self.compatibleEngines = []
    }
  }
}

// MARK: - Character

/// A character definition used for consistent actor rendering across storyboard panels.
///
/// Characters are stored under `~/Library/SwiftVinetas/characters/<slug>/`
/// with a `character.yaml` manifest describing their identity and any trained LoRA adapters.
public struct Character: Sendable {
  /// Human-readable display name (e.g., "Detective Vale").
  public var name: String

  /// URL-safe identifier derived from name (e.g., "detective-vale").
  public var slug: String

  /// LoRA trigger word injected into prompts (e.g., "sks_detective-vale").
  public var triggerWord: String

  /// When this character was first created.
  public var created: Date

  /// Relative paths to source photos within the character directory.
  public var sourcePhotos: [String]

  /// Plain-text description of the character's appearance used in prompt composition.
  public var description: String

  /// Metadata for the most recently trained LoRA adapter, if any.
  public var lora: LoRAMetadata?

  public init(
    name: String,
    slug: String? = nil,
    triggerWord: String? = nil,
    created: Date = Date(),
    sourcePhotos: [String] = [],
    description: String = "",
    lora: LoRAMetadata? = nil
  ) {
    let derivedSlug = slug ?? Character.deriveSlug(from: name)
    self.name = name
    self.slug = derivedSlug
    self.triggerWord = triggerWord ?? "sks_\(derivedSlug)"
    self.created = created
    self.sourcePhotos = sourcePhotos
    self.description = description
    self.lora = lora
  }

  // MARK: - Slug Derivation

  /// Derive a URL-safe slug from a human-readable name.
  ///
  /// Rules:
  /// - Lowercase
  /// - Spaces replaced with hyphens
  /// - All non-alphanumeric, non-hyphen characters stripped
  /// - Multiple consecutive hyphens collapsed to one
  /// - Leading/trailing hyphens removed
  ///
  /// Examples:
  /// - "Detective Vale" → "detective-vale"
  /// - "Dr. O'Brien!" → "dr-obrien"
  public static func deriveSlug(from name: String) -> String {
    let lowercased = name.lowercased()
    let hyphenated = lowercased.replacingOccurrences(of: " ", with: "-")
    let filtered = hyphenated.unicodeScalars.filter { scalar in
      let value = scalar.value
      // Allow ASCII alphanumeric and hyphen
      let isAlphanumeric =
        (value >= 48 && value <= 57)  // 0-9
        || (value >= 97 && value <= 122)  // a-z
      let isHyphen = value == 45
      return isAlphanumeric || isHyphen
    }
    let result = String(String.UnicodeScalarView(filtered))
    // Collapse consecutive hyphens and trim
    var collapsed = result
    while collapsed.contains("--") {
      collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
    }
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

// MARK: - YAML Serialization

extension Character {

  /// Encode this character to a YAML string.
  public func yamlEncoded() throws -> String {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    var lines: [String] = []

    // Required fields
    lines.append("name: \(yamlQuote(name))")
    lines.append("slug: \(slug)")
    lines.append("trigger_word: \(triggerWord)")
    lines.append("created: \(dateFormatter.string(from: created))")

    // source_photos
    if sourcePhotos.isEmpty {
      lines.append("source_photos: []")
    } else {
      let photos = sourcePhotos.map { "  - \(yamlQuote($0))" }.joined(separator: "\n")
      lines.append("source_photos:\n\(photos)")
    }

    // description (may be empty)
    lines.append("description: \(yamlQuote(description))")

    // lora (optional)
    if let lora = lora {
      lines.append("lora:")
      lines.append("  path: \(lora.path)")
      lines.append("  scale: \(lora.scale)")
      lines.append("  version: \(lora.version)")
      if let trainedAt = lora.trainedAt {
        lines.append("  trained_at: \(isoFormatter.string(from: trainedAt))")
      }
      if let steps = lora.trainingSteps {
        lines.append("  training_steps: \(steps)")
      }
      if !lora.compatibleEngines.isEmpty {
        let enginesYAML = lora.compatibleEngines.map { "    - \($0)" }.joined(separator: "\n")
        lines.append("  compatible_engines:\n\(enginesYAML)")
      }
    }

    return lines.joined(separator: "\n") + "\n"
  }

  /// Decode a `Character` from a YAML string.
  public static func from(yaml yamlString: String) throws -> Character {
    let yamlNode = try YAML.parse(yaml: yamlString)

    guard let name = yamlNode["name"]?.string else {
      throw CharacterError.missingField("name")
    }
    guard let slug = yamlNode["slug"]?.string else {
      throw CharacterError.missingField("slug")
    }
    let triggerWord = yamlNode["trigger_word"]?.string ?? "sks_\(slug)"

    let created: Date
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let createdStr = yamlNode["created"]?.string {
      if let date = isoFormatter.date(from: createdStr) {
        created = date
      } else {
        // Try date-only format
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        created = df.date(from: createdStr) ?? Date()
      }
    } else {
      created = Date()
    }

    let sourcePhotos: [String]
    if let arr = yamlNode["source_photos"]?.array {
      sourcePhotos = arr.compactMap { $0.string }
    } else {
      sourcePhotos = []
    }

    let description = yamlNode["description"]?.string ?? ""

    let lora: LoRAMetadata?
    if let loraNode = yamlNode["lora"], loraNode != .null {
      let path = loraNode["path"]?.string ?? ""
      let scale = loraNode["scale"]?.number.map { Float($0) } ?? 0.8
      let version = loraNode["version"]?.integer ?? 1
      let trainedAt: Date? = loraNode["trained_at"]?.string.flatMap {
        isoFormatter.date(from: $0)
      }
      let trainingSteps = loraNode["training_steps"]?.integer

      // Migrate legacy `model` field: klein4b/klein9b → compatibleEngines: ["flux2"]
      // New files write `compatible_engines` and never write `model`.
      var compatibleEngines: [String]
      if let enginesArray = loraNode["compatible_engines"]?.array {
        compatibleEngines = enginesArray.compactMap { $0.string }
      } else if let legacyModel = loraNode["model"]?.string {
        // Legacy migration: any klein* model maps to "flux2"
        switch legacyModel {
        case "klein4b", "klein9b":
          compatibleEngines = ["flux2"]
        default:
          compatibleEngines = []
        }
      } else {
        compatibleEngines = []
      }

      lora = LoRAMetadata(
        path: path,
        scale: scale,
        version: version,
        trainedAt: trainedAt,
        trainingSteps: trainingSteps,
        compatibleEngines: compatibleEngines
      )
    } else {
      lora = nil
    }

    return Character(
      name: name,
      slug: slug,
      triggerWord: triggerWord,
      created: created,
      sourcePhotos: sourcePhotos,
      description: description,
      lora: lora
    )
  }

  // MARK: - Private Helpers

  /// Quote a string value for YAML if it contains special characters or spaces.
  private func yamlQuote(_ str: String) -> String {
    if str.isEmpty { return "\"\"" }
    let needsQuoting =
      str.contains(":") || str.contains("#") || str.contains("\"")
      || str.hasPrefix(" ") || str.hasSuffix(" ")
    if needsQuoting {
      let escaped = str.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      return "\"\(escaped)\""
    }
    return str
  }
}

// MARK: - CharacterError

/// Errors thrown by Character serialization.
public enum CharacterError: Error, LocalizedError {
  case missingField(String)
  case invalidFormat(String)

  public var errorDescription: String? {
    switch self {
    case .missingField(let field):
      return "Character YAML is missing required field: '\(field)'"
    case .invalidFormat(let reason):
      return "Character YAML format error: \(reason)"
    }
  }
}

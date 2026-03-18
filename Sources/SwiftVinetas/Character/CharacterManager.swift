import CoreGraphics
import Foundation

/// Manages the on-disk lifecycle of characters stored under
/// `~/Library/SwiftVinetas/characters/<slug>/`.
///
/// Each character directory contains:
/// ```
/// <slug>/
/// ├── character.yaml      — Character manifest
/// ├── source/             — Original source photos
/// ├── references/         — Generated reference sheets
/// ├── training/           — Captioned training image pairs
/// └── lora/               — Trained LoRA safetensors files
/// ```
public struct CharacterManager: Sendable {

  // MARK: - Base Directory

  /// The root characters directory: `~/Library/SwiftVinetas/characters/`.
  public let baseDirectory: URL

  /// Create a manager rooted at the standard library characters directory.
  public init() {
    let libraryURL = FileManager.default.urls(
      for: .libraryDirectory,
      in: .userDomainMask
    ).first!
    self.baseDirectory =
      libraryURL
      .appendingPathComponent("SwiftVinetas", isDirectory: true)
      .appendingPathComponent("characters", isDirectory: true)
  }

  /// Create a manager rooted at a custom directory (useful in tests).
  public init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
  }

  // MARK: - Directory Layout

  /// The directory for a given slug.
  public func characterDirectory(slug: String) -> URL {
    baseDirectory.appendingPathComponent(slug, isDirectory: true)
  }

  private func subdirectory(_ name: String, slug: String) -> URL {
    characterDirectory(slug: slug).appendingPathComponent(name, isDirectory: true)
  }

  // MARK: - Create

  /// Create a new character, set up the directory tree, and save the initial manifest.
  ///
  /// If `slug` is not provided it is derived from `name` via `Character.deriveSlug(from:)`.
  /// The source photo is written as PNG to `source/<slug>-photo-01.png`.
  ///
  /// - Parameters:
  ///   - name: Human-readable character name (e.g., "Detective Vale").
  ///   - photo: Optional source photograph to store in the `source/` subdirectory.
  ///   - slug: Optional slug; derived from `name` if omitted.
  ///   - description: Plain-text description of the character's appearance.
  /// - Returns: The newly created `Character` value.
  /// - Throws: File I/O or YAML encoding errors.
  @discardableResult
  public func createCharacter(
    name: String,
    photo: CGImage? = nil,
    slug: String? = nil,
    description: String = ""
  ) throws -> Character {
    let resolvedSlug = slug ?? Character.deriveSlug(from: name)
    let charDir = characterDirectory(slug: resolvedSlug)

    // Create directory tree
    let fm = FileManager.default
    let subdirs = ["source", "references", "training", "lora"]
    for sub in subdirs {
      let url = charDir.appendingPathComponent(sub, isDirectory: true)
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // Persist source photo if provided
    var sourcePhotos: [String] = []
    if let photo {
      let photoFilename = "\(resolvedSlug)-photo-01.png"
      let photoURL =
        charDir
        .appendingPathComponent("source", isDirectory: true)
        .appendingPathComponent(photoFilename)
      try ImageOutput.writePNG(image: photo, to: photoURL)
      sourcePhotos = ["source/\(photoFilename)"]
    }

    var character = Character(
      name: name,
      slug: resolvedSlug,
      created: Date(),
      sourcePhotos: sourcePhotos,
      description: description
    )
    character.slug = resolvedSlug
    character.triggerWord = "sks_\(resolvedSlug)"

    // Write character.yaml
    try saveCharacter(character)

    return character
  }

  // MARK: - Read

  /// Load a single character from its slug.
  ///
  /// - Parameter slug: The character's slug identifier.
  /// - Returns: The decoded `Character`.
  /// - Throws: File I/O or YAML decoding errors.
  public func loadCharacter(slug: String) throws -> Character {
    let yamlURL = characterDirectory(slug: slug)
      .appendingPathComponent("character.yaml")
    let yamlString = try String(contentsOf: yamlURL, encoding: .utf8)
    return try Character.from(yaml: yamlString)
  }

  /// List all characters found in the base directory.
  ///
  /// Characters without a valid `character.yaml` are silently skipped.
  ///
  /// - Returns: Array of decoded `Character` values, sorted by name.
  public func listCharacters() throws -> [Character] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: baseDirectory.path) else { return [] }

    let contents = try fm.contentsOfDirectory(
      at: baseDirectory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    var characters: [Character] = []
    for url in contents {
      var isDirectory: ObjCBool = false
      fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
      guard isDirectory.boolValue else { continue }

      let slug = url.lastPathComponent
      if let character = try? loadCharacter(slug: slug) {
        characters.append(character)
      }
    }
    return characters.sorted { $0.name < $1.name }
  }

  // MARK: - Update

  /// Persist a character manifest to `character.yaml`.
  ///
  /// - Parameter character: The character to save.
  /// - Throws: File I/O or YAML encoding errors.
  public func saveCharacter(_ character: Character) throws {
    let yamlURL = characterDirectory(slug: character.slug)
      .appendingPathComponent("character.yaml")
    let yamlString = try character.yamlEncoded()
    try yamlString.write(to: yamlURL, atomically: true, encoding: .utf8)
  }

  // MARK: - Delete

  /// Delete a character and its entire directory tree.
  ///
  /// - Parameter slug: The character's slug identifier.
  /// - Throws: File I/O errors.
  public func deleteCharacter(slug: String) throws {
    let charDir = characterDirectory(slug: slug)
    try FileManager.default.removeItem(at: charDir)
  }
}

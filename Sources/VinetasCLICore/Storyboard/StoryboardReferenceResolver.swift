import Foundation
import SwiftVinetas

/// Resolves the `ref` entries of a storyboard shot to image files.
///
/// Rules, first match wins (docs/missions/storyboard-shots/REQUIREMENTS.md § 2):
/// 1. an absolute path that exists;
/// 2. a path relative to the project root, else the screenplay's folder;
/// 3. `characters/<NAME>/` under the project root — the first of `portrait.*`,
///    `ref-portrait.*`, then any image in that folder, alphabetically;
/// 4. a Vinetas character with that slug (its reference images, best first).
///
/// The *project root* is the nearest ancestor directory of the screenplay that
/// holds a `PROJECT.md`, else the screenplay's own folder
/// (``discoverProjectRoot(documentFolder:)``). With no document folder (a shot
/// fed on stdin) only rules 1 and 4 can match.
struct StoryboardReferenceResolver {

  /// The nearest project root for a document in `documentFolder`: the closest
  /// ancestor (the folder itself included) containing `PROJECT.md`, else
  /// `documentFolder`. Reuse this wherever a "project root" is needed.
  static func discoverProjectRoot(documentFolder: URL) -> URL {
    let start = documentFolder.standardizedFileURL
    var candidate = start
    while true {
      let marker = candidate.appendingPathComponent("PROJECT.md")
      if FileManager.default.fileExists(atPath: marker.path) { return candidate }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path { return start }
      candidate = parent
    }
  }

  /// The screenplay's folder, or `nil` when there is no document (stdin).
  let documentFolder: URL?
  /// The project root derived from ``documentFolder``, or `nil` without one.
  let projectRoot: URL?
  let characters: CharacterManager

  init(documentFolder: URL?, characters: CharacterManager = CharacterManager()) {
    self.documentFolder = documentFolder?.standardizedFileURL
    self.projectRoot = documentFolder.map { Self.discoverProjectRoot(documentFolder: $0) }
    self.characters = characters
  }

  /// Convenience for a screenplay file path.
  init(screenplay path: String, characters: CharacterManager = CharacterManager()) {
    self.init(
      documentFolder: URL(fileURLWithPath: path).deletingLastPathComponent(),
      characters: characters)
  }

  private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

  /// Resolve one `ref` entry to one or more image files (rule 4 can yield
  /// several: a character's reference sheets and photos).
  func resolve(_ entry: String) throws -> [URL] {
    let fm = FileManager.default
    func isFile(_ url: URL) -> Bool {
      var isDirectory: ObjCBool = false
      return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    // 1. absolute path
    if entry.hasPrefix("/") {
      let url = URL(fileURLWithPath: entry)
      if isFile(url) { return [url] }
    }

    // 2. relative to the project root, else the screenplay's folder
    let relativeCandidates = relativeSearchRoots.map { $0.appendingPathComponent(entry) }
    if !entry.hasPrefix("/") {
      for url in relativeCandidates where isFile(url) { return [url] }
    }

    // 3. characters/<NAME>/ in the project root
    let characterFolder = projectRoot?
      .appendingPathComponent("characters", isDirectory: true)
      .appendingPathComponent(entry, isDirectory: true)
    if let characterFolder, let image = Self.portraitImage(in: characterFolder) {
      return [image]
    }

    // 4. a Vinetas character slug
    var slugNote = ""
    if let character = try? characters.loadCharacter(slug: entry) {
      let images = characters.referenceImageURLs(for: character)
      if !images.isEmpty { return images }
      slugNote = " (the character exists but has no reference images)"
    }

    throw StoryboardPanelError(
      message: Self.unresolvedMessage(
        entry: entry,
        absolute: entry.hasPrefix("/"),
        relativeCandidates: entry.hasPrefix("/") ? [] : relativeCandidates,
        characterFolder: characterFolder,
        slugNote: slugNote,
        charactersDirectory: characters.baseDirectory))
  }

  /// Project root first, then the screenplay's folder (de-duplicated).
  private var relativeSearchRoots: [URL] {
    var roots: [URL] = []
    for url in [projectRoot, documentFolder].compactMap({ $0 })
    where !roots.contains(where: { $0.path == url.path }) {
      roots.append(url)
    }
    return roots
  }

  /// `portrait.*`, then `ref-portrait.*`, then any image, alphabetically.
  private static func portraitImage(in folder: URL) -> URL? {
    let fm = FileManager.default
    guard
      let contents = try? fm.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return nil }
    let images =
      contents
      .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    for stem in ["portrait", "ref-portrait"] {
      if let match = images.first(where: {
        $0.deletingPathExtension().lastPathComponent.lowercased() == stem
      }) {
        return match
      }
    }
    return images.first
  }

  private static func unresolvedMessage(
    entry: String, absolute: Bool, relativeCandidates: [URL], characterFolder: URL?,
    slugNote: String, charactersDirectory: URL
  ) -> String {
    var places: [String] = []
    if absolute { places.append("absolute path \(entry)") }
    for url in relativeCandidates { places.append("relative path \(url.path)") }
    if let characterFolder {
      places.append("project character folder \(characterFolder.path)/")
    }
    places.append(
      "Vinetas character slug '\(entry)' in \(charactersDirectory.path)\(slugNote)")
    return "unresolved reference '\(entry)': searched, in order: "
      + places.joined(separator: "; ")
  }
}

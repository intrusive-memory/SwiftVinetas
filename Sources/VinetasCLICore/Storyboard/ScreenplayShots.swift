import Foundation
import GlosaCore
import SwiftCompartido

/// Loads GlosaCore `<shot>` directives from a screenplay file.
///
/// GlosaCore parses an already-extracted `[[ ]]` note stream rather than a file,
/// so this helper bridges a screenplay path to that stream using
/// `SwiftCompartido.GuionParsedElementCollection` — the same parser
/// `glosa-tools` uses, keeping screenplay→notes extraction to one source of
/// truth. Supports `.fountain`, `.highland` (ZIP bundle or plain text), and
/// `.fdx`.
public enum ScreenplayShots {

  /// Parse a screenplay file and return its `<shot>` directives (in
  /// `documentIndex` order) plus any GlosaCore diagnostics (e.g. warnings on
  /// unrecognized `model`/`aspect` values).
  ///
  /// - Parameter path: path to a `.fountain`, `.highland`, or `.fdx` file.
  public static func load(
    from path: String
  ) throws -> (shots: [Shot], diagnostics: [GlosaDiagnostic]) {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    let parser = GlosaParser()

    if ext == "fdx" {
      // FDX carries directives as `<glosa:shot/>` XML elements — parse the raw
      // FDX data directly rather than going through the `[[ ]]` note stream.
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let (score, diagnostics) = parser.parseFDXWithDiagnostics(data: data)
      return (score.shots, diagnostics)
    }

    // Fountain / Highland → element collection → `[[ ]]` note stream.
    let screenplay = try GuionParsedElementCollection(file: path)
    let notes = extractNotes(from: screenplay)
    let (score, diagnostics) = parser.parseFountainWithDiagnostics(notes: notes)
    return (score.shots, diagnostics)
  }

  /// Build the ordered `[[ ]]` note stream GlosaCore's Fountain parser expects.
  ///
  /// Mirrors `glosa-tools`' `extractNotesAndDialogue`: `.comment` elements hold
  /// standalone note text (brackets stripped) and dialogue raw text is included
  /// so inline notes keep their document position. Standalone `[[<shot/>]]`
  /// notes arrive as `.comment` elements; their relative order in this stream is
  /// what fixes each `Shot.documentIndex`.
  static func extractNotes(from screenplay: GuionParsedElementCollection) -> [String] {
    var notes: [String] = []
    for element in screenplay.elements {
      switch element.elementType {
      case .comment:
        let trimmed = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { notes.append(trimmed) }
      case .dialogue:
        notes.append(element.elementText)
      default:
        break
      }
    }
    return notes
  }
}

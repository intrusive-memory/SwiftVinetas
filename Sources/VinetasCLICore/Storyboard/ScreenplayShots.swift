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

  /// Parse a screenplay file and return its raw `<shot>` directives (in
  /// `documentIndex` order, defaults shots included, nothing folded) plus any
  /// GlosaCore diagnostics. Use ``loadScore(from:)`` and
  /// `GlosaScore.effectiveShots` to get the renderable, defaults-folded shots.
  ///
  /// - Parameter path: path to a `.fountain`, `.highland`, or `.fdx` file.
  public static func load(
    from path: String
  ) throws -> (shots: [Shot], diagnostics: [GlosaDiagnostic]) {
    let (score, diagnostics) = try loadScore(from: path)
    return (score.shots, diagnostics)
  }

  /// Parse a screenplay file into a `GlosaScore` plus any GlosaCore diagnostics
  /// (e.g. warnings on unrecognized `model`/`aspect` values). Parsing goes
  /// through `GlosaParser` only; notation 2.0 JSON notes and notation 1.0
  /// `<shot/>` tags both land in `score.shots`.
  ///
  /// - Parameter path: path to a `.fountain`, `.highland`, or `.fdx` file.
  public static func loadScore(
    from path: String
  ) throws -> (score: GlosaScore, diagnostics: [GlosaDiagnostic]) {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    let parser = GlosaParser()

    if ext == "fdx" {
      // FDX carries directives as `<glosa:shot/>` XML elements — parse the raw
      // FDX data directly rather than going through the `[[ ]]` note stream.
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      return parser.parseFDXWithDiagnostics(data: data)
    }

    // Fountain / Highland → element collection → `[[ ]]` note stream.
    let screenplay = try GuionParsedElementCollection(file: path)
    let notes = extractNotes(from: screenplay)
    return parser.parseFountainWithDiagnostics(notes: notes)
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

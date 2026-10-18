// GranvilleFixtures.swift
// VinetasUITests
//
// Test-only loader for the real granville project files copied unchanged
// into Fixtures/granville: the episode 1 cold-open fountain and its 13
// generated storyboard panels.

import Foundation

/// One generated storyboard panel, decoded from a granville `storyboards/*.json`.
struct GranvillePanel: Decodable, Equatable {
  var composedPrompt: String
  var durationSeconds: Double
  var engine: String
  var generatedAt: String
  var guidance: Float
  var height: Int
  var loras: [String]
  var mode: String
  var model: String
  var negative: String
  var negativeApplied: Bool
  var prompt: String
  var references: [GranvilleReference]
  var seed: UInt64
  var steps: Int
  var style: String
  var width: Int
}

/// One reference image a panel was conditioned on, as the panel JSON records it.
struct GranvilleReference: Decodable, Equatable {
  var effectiveHeight: Int
  var effectiveWidth: Int
  var originalHeight: Int
  var originalWidth: Int
  var sha256: String
  var source: String
}

/// The granville fixtures every VinetasUI test, preview and recipe reads.
enum GranvilleFixtures {

  enum FixtureError: Error {
    case missing(String)
  }

  /// The subdirectory of the test bundle that holds the granville files.
  static let subdirectory = "Fixtures/granville"

  /// The scene heading under the defaults shot (fountain line 9).
  static let sceneHeading = "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET"

  /// The 13 generated panels, sorted by file name.
  static func panels() throws -> [GranvillePanel] {
    guard
      let urls = Bundle.module.urls(
        forResourcesWithExtension: "json", subdirectory: subdirectory)
    else {
      throw FixtureError.missing("\(subdirectory)/*.json")
    }
    let decoder = JSONDecoder()
    return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { try decoder.decode(GranvillePanel.self, from: Data(contentsOf: $0)) }
  }

  /// The attribute maps of the 14 `<shot …/>` directives in the cold-open
  /// fountain, in script order.
  static func shotDirectives() throws -> [[String: String]] {
    let text = try String(contentsOf: url("episode_1_01_cold_open", "fountain"), encoding: .utf8)
    let shot = try NSRegularExpression(pattern: #"<shot\s+([^>]*?)/>"#)
    let attribute = try NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_-]*)="([^"]*)""#)
    let whole = NSRange(text.startIndex..., in: text)
    return shot.matches(in: text, range: whole).map { match in
      let body = String(text[Range(match.range(at: 1), in: text)!])
      let bodyRange = NSRange(body.startIndex..., in: body)
      var attributes: [String: String] = [:]
      for pair in attribute.matches(in: body, range: bodyRange) {
        let name = String(body[Range(pair.range(at: 1), in: body)!])
        attributes[name] = String(body[Range(pair.range(at: 2), in: body)!])
      }
      return attributes
    }
  }

  /// The first, prompt-less directive that sets the episode's defaults.
  static var defaultsShot: [String: String] {
    get throws { try shotDirectives()[0] }
  }

  /// The second directive: the establishing shot's prompt and output.
  static var establishingShot: [String: String] {
    get throws { try shotDirectives()[1] }
  }

  /// The panel generated from the establishing shot.
  static var establishingPanel: GranvillePanel {
    get throws {
      try JSONDecoder().decode(
        GranvillePanel.self,
        from: Data(contentsOf: url("ep1_sc1_01_establishing", "json")))
    }
  }

  private static func url(_ name: String, _ ext: String) throws -> URL {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: ext, subdirectory: subdirectory)
    else {
      throw FixtureError.missing("\(subdirectory)/\(name).\(ext)")
    }
    return url
  }
}

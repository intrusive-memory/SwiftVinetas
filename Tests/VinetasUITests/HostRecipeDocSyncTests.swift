// HostRecipeDocSyncTests.swift
// VinetasUITests
//
// Keeps docs/VinetasUI.md honest: the code between each recipe's markers in
// the guide must be byte-identical to the compiled copy in
// HostRecipeTests.swift.

import Foundation
import Testing

@Suite struct HostRecipeDocSyncTests {

  enum SyncError: Error {
    case markerMissing(String, file: String)
  }

  /// The package root, three levels above this file
  /// (`Tests/VinetasUITests/HostRecipeDocSyncTests.swift`).
  static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  static let guideURL = packageRoot.appending(path: "docs/VinetasUI.md")

  static let recipesURL = packageRoot.appending(path: "Tests/VinetasUITests/HostRecipeTests.swift")

  /// The lines strictly between the line equal to `begin` and the line equal
  /// to `end`, dropping Markdown fence lines when `dropsFences` is true.
  static func block(
    in text: String, begin: String, end: String, dropsFences: Bool, file: String
  ) throws -> String {
    let lines = text.components(separatedBy: "\n")
    guard let start = lines.firstIndex(of: begin) else {
      throw SyncError.markerMissing(begin, file: file)
    }
    guard let stop = lines[(start + 1)...].firstIndex(of: end) else {
      throw SyncError.markerMissing(end, file: file)
    }
    let body = lines[(start + 1)..<stop].filter { line in
      !(dropsFences && line.hasPrefix("```"))
    }
    return body.joined(separator: "\n")
  }

  static func assertInSync(recipe: Int) throws {
    let guide = try String(contentsOf: guideURL, encoding: .utf8)
    let recipes = try String(contentsOf: recipesURL, encoding: .utf8)
    let documented = try block(
      in: guide,
      begin: "<!-- recipe-\(recipe):begin -->",
      end: "<!-- recipe-\(recipe):end -->",
      dropsFences: true,
      file: "docs/VinetasUI.md"
    )
    let compiled = try block(
      in: recipes,
      begin: "// recipe-\(recipe):begin",
      end: "// recipe-\(recipe):end",
      dropsFences: false,
      file: "HostRecipeTests.swift"
    )
    #expect(!compiled.isEmpty)
    #expect(Array(documented.utf8) == Array(compiled.utf8))
  }

  @Test func inspectorRecipeMatchesTheGuide() throws {
    try Self.assertInSync(recipe: 1)
  }

  @Test func pushedScreenRecipeMatchesTheGuide() throws {
    try Self.assertInSync(recipe: 2)
  }
}

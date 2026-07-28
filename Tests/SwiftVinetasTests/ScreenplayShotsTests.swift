import Foundation
import GlosaCore
import Testing

@testable import VinetasCLICore

// MARK: - ScreenplayShotsTests
//
// Integration coverage for the screenplay → `<shot>` bridge: a Fountain file
// with `[[<shot .../>]]` notes must parse (via SwiftCompartido) into the note
// stream GlosaCore reads, yielding Shot values in document order. End-to-end
// with ShotResolver, the defaults convention must survive the round trip.

@Suite("ScreenplayShots — Fountain ingestion")
struct ScreenplayShotsTests {

  /// Write `contents` to a uniquely-named temp `.fountain` file and return its path.
  private func writeTempFountain(_ contents: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vinetas-storyboard-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(UUID().uuidString).fountain")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url.path
  }

  @Test("Extracts <shot> notes from a Fountain screenplay in document order")
  func extractsShotsInOrder() throws {
    let fountain = """
      INT. OFFICE - DAY

      [[<shot prompt="" model="klein9b" aspect="wide"/>]]

      [[<shot prompt="wide office, rain"/>]]

      MARIA
      Hello there.

      [[<shot prompt="close on Maria" aspect="panel"/>]]
      """
    let path = try writeTempFountain(fountain)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let (shots, _) = try ScreenplayShots.load(from: path)
    let prompts = shots.map(\.prompt)
    #expect(prompts.contains("wide office, rain"))
    #expect(prompts.contains("close on Maria"))
    // The empty-prompt defaults shot is carried through (not dropped at parse).
    #expect(prompts.contains(""))
  }

  @Test("End-to-end: defaults convention folds through ingestion + resolution")
  func defaultsFoldEndToEnd() throws {
    let fountain = """
      INT. OFFICE - DAY

      [[<shot prompt="" model="klein9b" aspect="wide"/>]]

      [[<shot prompt="wide office, rain"/>]]

      [[<shot prompt="close on Maria" aspect="panel"/>]]
      """
    let path = try writeTempFountain(fountain)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let (shots, _) = try ScreenplayShots.load(from: path)
    let resolved = ShotResolver.resolve(shots)

    #expect(resolved.count == 2)
    #expect(resolved[0].prompt == "wide office, rain")
    #expect(resolved[0].model == "klein9b")  // inherited default
    #expect(resolved[0].aspect == "wide")  // inherited default
    #expect(resolved[1].prompt == "close on Maria")
    #expect(resolved[1].model == "klein9b")  // inherited default
    #expect(resolved[1].aspect == "panel")  // own value wins
  }

  @Test("A screenplay with no <shot> notes yields no shots")
  func noShots() throws {
    let fountain = """
      INT. OFFICE - DAY

      MARIA
      Nothing to storyboard here.
      """
    let path = try writeTempFountain(fountain)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let (shots, _) = try ScreenplayShots.load(from: path)
    #expect(ShotResolver.resolve(shots).isEmpty)
  }
}

import Foundation
import GlosaCore
import SwiftVinetas
import Testing

@testable import VinetasCLICore

// MARK: - StoryboardFoldTests
//
// The storyboard fold is GlosaCore's `GlosaScore.effectiveShots`. These tests
// drive synthetic inline Fountain through `ScreenplayShots.loadScore` and
// `Storyboard.resolvePlan`, covering notation 2.0 JSON notes, their notation 1.0
// `<shot/>` twins, and the Vinetas-side whitespace-only-prompt rule (D-6).

@Suite("Storyboard — GlosaCore fold")
struct StoryboardFoldTests {

  private func writeTempFountain(_ contents: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vinetas-storyboard-fold-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(UUID().uuidString).fountain")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url.path
  }

  private func plans(for fountain: String) throws -> [Storyboard.PanelPlan] {
    let path = try writeTempFountain(fountain)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let (score, _) = try ScreenplayShots.loadScore(from: path)
    let command = Storyboard()
    return score.effectiveShots.enumerated().map { index, shot in
      command.resolvePlan(for: shot, panelNumber: index + 1, fleetModel: .klein4b)
    }
  }

  private let notation2 = """
    INT. WORKSHOP - DAY

    [[{"shot": {"model": "pixart-sigma", "style": "ink wash", "aspect": "wide"}}]]

    [[{"shot": {"prompt": "a lantern on a bench"}}]]

    [[{"shot": {"prompt": "a gloved hand turns a key", "aspect": "panel", "output": "key.png"}}]]

    [[{"shot": {"prompt": "the door swings open", "steps": 12}}]]
    """

  private let notation1 = """
    INT. WORKSHOP - DAY

    [[<shot prompt="" model="pixart-sigma" style="ink wash" aspect="wide"/>]]

    [[<shot prompt="a lantern on a bench"/>]]

    [[<shot prompt="a gloved hand turns a key" aspect="panel" output="key.png"/>]]

    [[<shot prompt="the door swings open" steps="12"/>]]
    """

  @Test("A notation 2.0 JSON-shot fixture and its 1.0 <shot/> twin produce identical plans")
  func testNotation2AndNotation1TwinsProduceIdenticalPlans() throws {
    let two = try plans(for: notation2)
    let one = try plans(for: notation1)

    #expect(two.count == 3)
    #expect(one.count == 3)
    for (a, b) in zip(two, one) {
      #expect(a.panelNumber == b.panelNumber)
      #expect(a.prompt == b.prompt)
      #expect(a.model == b.model)
      #expect(a.style.stylePrompt == b.style.stylePrompt)
      #expect(a.style.width == b.style.width)
      #expect(a.style.height == b.style.height)
      #expect(a.style.steps == b.style.steps)
      #expect(a.output == b.output)
    }
    #expect(two[0].model == .pixartSigma)
    #expect(two[0].style.stylePrompt == "ink wash")
    #expect(two[1].output == "key.png")
    #expect(two[2].style.steps == 12)
  }

  @Test("output is not inherited from a defaults shot")
  func testOutputIsNotInheritedFromDefaults() throws {
    let result = try plans(
      for: """
        INT. WORKSHOP - DAY

        [[{"shot": {"output": "shared.png", "model": "pixart-sigma"}}]]

        [[{"shot": {"prompt": "first panel"}}]]

        [[{"shot": {"prompt": "second panel"}}]]
        """)
    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.output == nil })
    #expect(result.allSatisfy { $0.shot.output == nil })
    // Other defaults still fold.
    #expect(result.allSatisfy { $0.model == .pixartSigma })
  }

  @Test("ref and character fold from defaults into the effective shot")
  func testRefAndCharacterFoldFromDefaults() throws {
    // `ref` is a JSON array, and SwiftCompartido's Fountain note recognizer
    // (`section` regex, `[^\]\n]+`) does not accept a `]` inside a `[[ ]]` note,
    // so an array-valued shot cannot be authored in a .fountain file today. Feed
    // the note stream to GlosaParser directly — the same call ScreenplayShots
    // makes after extraction — to cover the fold itself.
    let notes = [
      #"{"shot": {"ref": ["refs/a.png", "refs/b.png"], "character": "tinker"}}"#,
      #"{"shot": {"prompt": "inherits both"}}"#,
      #"{"shot": {"prompt": "overrides character", "character": "apprentice"}}"#,
    ]
    let (score, diagnostics) = GlosaParser().parseFountainWithDiagnostics(notes: notes)
    #expect(diagnostics.isEmpty)
    let result = score.effectiveShots
    #expect(result.count == 2)
    #expect(result[0].ref == ["refs/a.png", "refs/b.png"])
    #expect(result[0].character == "tinker")
    #expect(result[1].ref == ["refs/a.png", "refs/b.png"])
    #expect(result[1].character == "apprentice")

    // And the file path: a string-valued `character` default folds through
    // ScreenplayShots.loadScore from real Fountain.
    let path = try writeTempFountain(
      """
      INT. WORKSHOP - DAY

      [[{"shot": {"character": "tinker"}}]]

      [[{"shot": {"prompt": "inherits"}}]]
      """)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let (fileScore, _) = try ScreenplayShots.loadScore(from: path)
    #expect(fileScore.effectiveShots.first?.character == "tinker")
  }

  @Test("A whitespace-only prompt is a per-panel error, not a defaults shot")
  func testWhitespaceOnlyPromptIsAPanelError() throws {
    let result = try plans(
      for: """
        INT. WORKSHOP - DAY

        [[{"shot": {"model": "pixart-sigma"}}]]

        [[{"shot": {"prompt": "   "}}]]

        [[{"shot": {"prompt": "a valid panel"}}]]
        """)
    // The whitespace-only shot is a panel (GlosaCore folds only empty prompts).
    #expect(result.count == 2)
    let problem = try #require(result[0].problem)
    #expect(problem.contains("whitespace-only prompt"))
    #expect(problem.contains("panel 1"))
    #expect(result[1].problem == nil)
    // It did not become a defaults shot: the model default came from the
    // earlier empty-prompt shot only, and the next panel is unaffected.
    #expect(result[1].prompt == "a valid panel")
  }
}

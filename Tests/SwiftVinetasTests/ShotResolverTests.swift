import Foundation
import GlosaCore
import Testing

@testable import VinetasCLICore

// MARK: - ShotResolverTests
//
// Exercises the "<shot> with no prompt sets defaults" convention that
// `ShotResolver` folds over GlosaCore's parse-and-carry shot stream. GlosaCore
// emits every shot in documentIndex order; ShotResolver must:
//   - drop empty-prompt shots from the render list,
//   - accumulate their attributes as rolling defaults,
//   - apply the active defaults to later prompted shots (own attrs win),
//   - update individual default entries when a later empty-prompt shot names them.

@Suite("ShotResolver — defaults convention")
struct ShotResolverTests {

  @Test("Empty-prompt shot renders nothing")
  func emptyPromptRendersNothing() {
    let shots = [Shot(documentIndex: 0, prompt: "", model: "klein9b")]
    #expect(ShotResolver.resolve(shots).isEmpty)
  }

  @Test("A defaults shot's attributes are inherited by a later prompted shot")
  func defaultsAreInherited() {
    let shots = [
      Shot(documentIndex: 0, prompt: "", model: "pixart-sigma", aspect: "wide", steps: 30),
      Shot(documentIndex: 1, prompt: "a bar at dusk"),
    ]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 1)
    #expect(resolved[0].prompt == "a bar at dusk")
    #expect(resolved[0].model == "pixart-sigma")
    #expect(resolved[0].aspect == "wide")
    #expect(resolved[0].steps == 30)
  }

  @Test("A shot's own attributes win per-attribute over the defaults")
  func ownAttributesWinPerAttribute() {
    let shots = [
      Shot(documentIndex: 0, prompt: "", model: "pixart-sigma", aspect: "wide", steps: 30),
      // Overrides aspect only; inherits model + steps from the defaults.
      Shot(documentIndex: 1, prompt: "close on the glass", aspect: "square"),
    ]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 1)
    #expect(resolved[0].aspect == "square")  // own value wins
    #expect(resolved[0].model == "pixart-sigma")  // inherited
    #expect(resolved[0].steps == 30)  // inherited
  }

  @Test("A later defaults shot updates individual default entries; others persist")
  func defaultsAccumulateAndUpdate() {
    let shots = [
      Shot(documentIndex: 0, prompt: "", model: "klein4b", aspect: "wide"),
      Shot(documentIndex: 1, prompt: "guy walks in"),
      // Update only the model going forward; aspect=wide must persist.
      Shot(documentIndex: 2, prompt: "", model: "klein9b"),
      Shot(documentIndex: 3, prompt: "he orders a drink"),
    ]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 2)

    #expect(resolved[0].prompt == "guy walks in")
    #expect(resolved[0].model == "klein4b")
    #expect(resolved[0].aspect == "wide")

    #expect(resolved[1].prompt == "he orders a drink")
    #expect(resolved[1].model == "klein9b")  // updated default
    #expect(resolved[1].aspect == "wide")  // earlier default persists
  }

  @Test("Whitespace-only prompt is treated as a defaults shot")
  func whitespaceOnlyPromptIsDefaults() {
    let shots = [
      Shot(documentIndex: 0, prompt: "   \n\t ", seed: 42),
      Shot(documentIndex: 1, prompt: "a wide establishing shot"),
    ]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 1)
    #expect(resolved[0].seed == 42)
  }

  @Test("Resolution is deterministic regardless of input order")
  func resortsByDocumentIndex() {
    let shots = [
      Shot(documentIndex: 3, prompt: "second panel"),
      Shot(documentIndex: 0, prompt: "", model: "klein9b"),
      Shot(documentIndex: 1, prompt: "first panel"),
    ]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 2)
    // Sorted by documentIndex: "first panel" (1) before "second panel" (3),
    // both inherit the model default declared at index 0.
    #expect(resolved[0].prompt == "first panel")
    #expect(resolved[1].prompt == "second panel")
    #expect(resolved[0].model == "klein9b")
    #expect(resolved[1].model == "klein9b")
  }

  @Test("Prompted shots with no active defaults keep nil attributes")
  func noDefaultsLeavesNil() {
    let shots = [Shot(documentIndex: 0, prompt: "just a prompt")]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 1)
    #expect(resolved[0].model == nil)
    #expect(resolved[0].aspect == nil)
    #expect(resolved[0].seed == nil)
  }

  @Test("An empty-prompt shot that names no attributes is a no-op")
  func emptyShotNoAttributesIsNoop() {
    let shots = [
      Shot(documentIndex: 0, prompt: "", model: "klein9b"),
      Shot(documentIndex: 1, prompt: ""),  // names nothing → must not clear model
      Shot(documentIndex: 2, prompt: "a panel"),
    ]
    let resolved = ShotResolver.resolve(shots)
    #expect(resolved.count == 1)
    #expect(resolved[0].model == "klein9b")
  }
}

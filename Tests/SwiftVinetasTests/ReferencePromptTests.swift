import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - ReferenceView Tests

@Suite("ReferenceView")
struct ReferenceViewTests {

  @Test("allCases contains exactly 4 views")
  func allCasesCount() {
    #expect(ReferenceView.allCases.count == 4)
  }

  @Test("allCases contains front, left, right, back")
  func allCasesContainsExpectedViews() {
    let views = Set(ReferenceView.allCases)
    #expect(views.contains(.front))
    #expect(views.contains(.left))
    #expect(views.contains(.right))
    #expect(views.contains(.back))
  }

  @Test("front rawValue is 'front'")
  func frontRawValue() {
    #expect(ReferenceView.front.rawValue == "front")
  }

  @Test("left rawValue is 'left'")
  func leftRawValue() {
    #expect(ReferenceView.left.rawValue == "left")
  }

  @Test("right rawValue is 'right'")
  func rightRawValue() {
    #expect(ReferenceView.right.rawValue == "right")
  }

  @Test("back rawValue is 'back'")
  func backRawValue() {
    #expect(ReferenceView.back.rawValue == "back")
  }

  @Test("front promptSuffix contains 'front view, facing camera'")
  func frontPromptSuffix() {
    #expect(ReferenceView.front.promptSuffix.contains("front view, facing camera"))
  }

  @Test("left promptSuffix contains 'three-quarter view'")
  func leftPromptSuffix() {
    #expect(ReferenceView.left.promptSuffix.contains("three-quarter view"))
  }

  @Test("right promptSuffix contains 'three-quarter view'")
  func rightPromptSuffix() {
    #expect(ReferenceView.right.promptSuffix.contains("three-quarter view"))
  }

  @Test("back promptSuffix contains 'back view, facing away'")
  func backPromptSuffix() {
    #expect(ReferenceView.back.promptSuffix.contains("back view, facing away"))
  }
}

// MARK: - Prompt Composition Tests

@Suite("Reference Sheet Prompt Composition")
struct ReferencePromptCompositionTests {

  /// A test character with known trigger word and description.
  private var testCharacter: Character {
    Character(
      name: "Detective Vale",
      slug: "detective-vale",
      triggerWord: "sks_detective-vale",
      description: "Male, 40s, angular jaw, short dark hair"
    )
  }

  @Test("Front prompt contains 'pencil sketch'")
  func frontPromptContainsPencilSketch() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .front,
      character: testCharacter
    )
    #expect(prompt.contains("pencil sketch"))
  }

  @Test("Front prompt contains 'front view, facing camera'")
  func frontPromptContainsFrontView() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .front,
      character: testCharacter
    )
    #expect(prompt.contains("front view, facing camera"))
  }

  @Test("Front prompt contains the trigger word")
  func frontPromptContainsTriggerWord() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .front,
      character: testCharacter
    )
    #expect(prompt.contains("sks_detective-vale"))
  }

  @Test("Front prompt contains character description")
  func frontPromptContainsDescription() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .front,
      character: testCharacter
    )
    #expect(prompt.contains("Male, 40s, angular jaw, short dark hair"))
  }

  @Test("Front prompt contains 'clean lines, white background'")
  func frontPromptContainsStyleSuffix() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .front,
      character: testCharacter
    )
    #expect(prompt.contains("clean lines, white background"))
  }

  @Test("Back prompt contains 'back view, facing away'")
  func backPromptContainsBackView() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .back,
      character: testCharacter
    )
    #expect(prompt.contains("back view, facing away"))
  }

  @Test("Back prompt contains the trigger word")
  func backPromptContainsTriggerWord() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .back,
      character: testCharacter
    )
    #expect(prompt.contains("sks_detective-vale"))
  }

  @Test("Left prompt contains 'three-quarter view'")
  func leftPromptContainsThreeQuarter() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .left,
      character: testCharacter
    )
    #expect(prompt.contains("three-quarter view"))
  }

  @Test("Right prompt contains 'three-quarter view'")
  func rightPromptContainsThreeQuarter() {
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .right,
      character: testCharacter
    )
    #expect(prompt.contains("three-quarter view"))
  }

  @Test("All four prompts are distinct")
  func allPromptsDistinct() {
    let prompts = ReferenceView.allCases.map { view in
      ReferenceSheetGenerator.composePrompt(for: view, character: testCharacter)
    }
    let uniquePrompts = Set(prompts)
    #expect(uniquePrompts.count == 4)
  }

  @Test("Prompt with custom trigger word uses the custom word")
  func customTriggerWordInPrompt() {
    let character = Character(
      name: "Alice",
      triggerWord: "sks_custom_alice",
      description: "Young woman with red hair"
    )
    let prompt = ReferenceSheetGenerator.composePrompt(
      for: .front,
      character: character
    )
    #expect(prompt.contains("sks_custom_alice"))
  }
}

// MARK: - Default Strength Tests

@Suite("Reference Sheet Default Strength")
struct ReferenceDefaultStrengthTests {

  @Test("Default strength is 0.65")
  func defaultStrengthValue() {
    #expect(ReferenceSheetGenerator.defaultStrength == 0.65)
  }
}

// MARK: - Public API Compilation Tests

@Suite("Vinetas Reference Sheet API Compilation")
struct VinetasReferenceSheetAPITests {

  @Test("ReferenceView is CaseIterable")
  func referenceViewIsCaseIterable() {
    let allViews: [ReferenceView] = ReferenceView.allCases.map { $0 }
    #expect(allViews.count == 4)
  }

  @Test("ReferenceView conforms to Sendable")
  func referenceViewIsSendable() async {
    // Transfer a ReferenceView across actor boundary to verify Sendable
    let view: ReferenceView = .front
    let result = await ReferenceViewTransferActor.transfer(view)
    #expect(result == .front)
  }

  #if !VINETAS_FLUX2_DISABLED
  @Test("generateReferenceSheets method reference compiles with correct signature")
  func generateReferenceSheetsSignature() {
    // Verify the method exists and has the expected signature
    // We cannot call it because it requires model loading, but the reference must compile
    typealias RefSheetFn = (
      Character,
      [ReferenceView],
      Float,
      VinetasModel,
      ((Int, Int) -> Void)?
    ) async throws -> [CGImage]

    // This line would fail to compile if the signature is wrong
    let _: RefSheetFn = Vinetas.generateReferenceSheets(for:views:strength:model:progress:)
  }
  #endif
}

/// A simple actor used to verify Sendable conformance of ReferenceView.
private actor ReferenceViewTransferActor {
  static func transfer(_ view: ReferenceView) -> ReferenceView {
    view
  }
}

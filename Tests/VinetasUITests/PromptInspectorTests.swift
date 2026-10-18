import SwiftUI
import Testing
import VinetasVocabulary

@testable import VinetasUI

@Suite struct PromptInspectorTests {

  @MainActor @Test func modifierTypeChecksWithEmptyHeaderDefault() {
    var isPresented = true
    var draft = VinetasPromptDraft()
    let presented = Binding(get: { isPresented }, set: { isPresented = $0 })
    let draftBinding = Binding(get: { draft }, set: { draft = $0 })
    _ = Text("doc").vinetasPromptInspector(
      isPresented: presented, draft: draftBinding
    ) {
      Button("Save") {}
    }
    _ = Text("doc").vinetasPromptInspector(
      isPresented: presented, draft: draftBinding, showsCaption: true,
      header: { Text("Title") },
      actions: { Button("Save") {} }
    )
  }

  @Test func policyPresentsOnMacAndPadOnly() {
    #expect(VinetasPromptInspectorPolicy.presents(onIdiom: .mac))
    #expect(VinetasPromptInspectorPolicy.presents(onIdiom: .pad))
    #expect(!VinetasPromptInspectorPolicy.presents(onIdiom: .phone))
  }
}

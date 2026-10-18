// VinetasPromptInspector.swift
// VinetasUI
//
// The inspector presentation of the prompt panel: a non-modal trailing
// inspector on macOS and iPad, and a deliberate no-op on iPhone.

import SwiftUI
import VinetasVocabulary

/// The pure decision of whether the prompt inspector presents on a device.
public enum VinetasPromptInspectorPolicy {

  /// The kind of device the inspector is asked to present on.
  public enum Idiom: Sendable, CaseIterable {
    /// A Mac.
    case mac
    /// An iPad.
    case pad
    /// An iPhone.
    case phone
  }

  /// Whether the inspector presents on `onIdiom`.
  ///
  /// True on ``Idiom/mac`` and ``Idiom/pad``; false on ``Idiom/phone``,
  /// where the panel is a pushed screen instead.
  public static func presents(onIdiom: Idiom) -> Bool {
    switch onIdiom {
    case .mac, .pad: return true
    case .phone: return false
    }
  }

  /// The idiom of the device this code is running on.
  @MainActor static var current: Idiom {
    #if os(macOS)
      return .mac
    #else
      return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    #endif
  }
}

extension View {

  /// Presents the prompt panel as a trailing inspector, with `header` pinned
  /// above it and `actions` pinned below it.
  ///
  /// On macOS and iPad the inspector is non-modal, 340 points ideal (300 min,
  /// 420 max), and shows `header`, then ``VinetasPromptComposer`` in a scroll
  /// view forced to the `.sidebar` layout, then `actions`. The package draws
  /// no action of its own; the host supplies every control in `header` and
  /// `actions`.
  ///
  /// On iPhone this modifier returns the view unchanged and, in debug builds,
  /// trips an `assertionFailure` when the view is rendered. Present the panel
  /// as a pushed screen instead, as recipe 2 of the host guide shows.
  ///
  /// - Parameters:
  ///   - isPresented: Whether the inspector is open.
  ///   - draft: The draft the composer edits.
  ///   - models: The models to offer, already filtered by the host.
  ///   - showsCaption: Whether the composer shows the caption field.
  ///   - header: Content pinned at the top of the inspector.
  ///   - actions: Content pinned at the bottom of the inspector.
  public func vinetasPromptInspector<Header: View, Actions: View>(
    isPresented: Binding<Bool>,
    draft: Binding<VinetasPromptDraft>,
    models: [ModelSummary] = ModelSummary.all,
    showsCaption: Bool = false,
    @ViewBuilder header: () -> Header,
    @ViewBuilder actions: () -> Actions
  ) -> some View {
    modifier(
      VinetasPromptInspectorModifier(
        isPresented: isPresented,
        draft: draft,
        models: models,
        showsCaption: showsCaption,
        header: header(),
        actions: actions()
      ))
  }

  /// Presents the prompt panel as a trailing inspector with no header.
  ///
  /// Equivalent to the full overload with an empty header; see
  /// ``vinetasPromptInspector(isPresented:draft:models:showsCaption:header:actions:)``.
  ///
  /// - Parameters:
  ///   - isPresented: Whether the inspector is open.
  ///   - draft: The draft the composer edits.
  ///   - models: The models to offer, already filtered by the host.
  ///   - showsCaption: Whether the composer shows the caption field.
  ///   - actions: Content pinned at the bottom of the inspector.
  public func vinetasPromptInspector<Actions: View>(
    isPresented: Binding<Bool>,
    draft: Binding<VinetasPromptDraft>,
    models: [ModelSummary] = ModelSummary.all,
    showsCaption: Bool = false,
    @ViewBuilder actions: () -> Actions
  ) -> some View {
    vinetasPromptInspector(
      isPresented: isPresented,
      draft: draft,
      models: models,
      showsCaption: showsCaption,
      header: { EmptyView() },
      actions: actions)
  }
}

/// Applies the inspector where the idiom allows it and asserts where not.
private struct VinetasPromptInspectorModifier<Header: View, Actions: View>: ViewModifier {
  let isPresented: Binding<Bool>
  let draft: Binding<VinetasPromptDraft>
  let models: [ModelSummary]
  let showsCaption: Bool
  let header: Header
  let actions: Actions

  @MainActor private func unsupported(_ content: Content) -> Content {
    assertionFailure(
      "vinetasPromptInspector is not supported on iPhone; present the panel as a pushed screen.")
    return content
  }

  @MainActor @ViewBuilder func body(content: Content) -> some View {
    if VinetasPromptInspectorPolicy.presents(onIdiom: VinetasPromptInspectorPolicy.current) {
      content
        .inspector(isPresented: isPresented) {
          VStack(spacing: 0) {
            header
            ScrollView {
              VinetasPromptComposer(
                draft: draft, models: models, showsCaption: showsCaption
              )
              .vinetasPanelLayout(.sidebar)
            }
            actions
          }
          .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
    } else {
      unsupported(content)
    }
  }
}

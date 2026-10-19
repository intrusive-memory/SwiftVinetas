// VinetasStylePickerStyle.swift
// VinetasUI
//
// The opt-in presentation for the style picker and the environment value a
// host sets to choose it.

import SwiftUI

/// How the style picker presents its styles.
public enum VinetasStylePickerStyle: Sendable {
  /// The picker follows the panel layout: a button that opens a popover in
  /// `.sidebar` and `.regular`, a chevron row in `.compact`.
  case automatic
  /// The 5.5-row style list inline, whatever the layout.
  case list
}

extension EnvironmentValues {

  /// The presentation the style picker uses in this view hierarchy.
  ///
  /// Defaults to ``VinetasStylePickerStyle/automatic``.
  @Entry public var vinetasStylePickerStyle: VinetasStylePickerStyle = .automatic
}

extension View {

  /// Sets the presentation of every style picker in this view hierarchy.
  public func vinetasStylePickerStyle(_ style: VinetasStylePickerStyle) -> some View {
    environment(\.vinetasStylePickerStyle, style)
  }
}

// VinetasCompactEmbedding.swift
// VinetasUI
//
// The internal switch that lets a composite view hold several panels'
// compact sections in one form instead of one form per panel.

import SwiftUI

extension EnvironmentValues {

  /// Whether the panels in this hierarchy draw their compact layout as bare
  /// sections for an enclosing form, rather than wrapping them in a form of
  /// their own.
  ///
  /// ``VinetasPromptComposer`` sets this to `true` on both panels so the
  /// compact layout is one inset-grouped form that scrolls as a whole.
  /// Defaults to `false`. Internal: hosts never see it.
  @Entry var vinetasEmbedsCompactSections: Bool = false
}

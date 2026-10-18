// VinetasNavigationAvailability.swift
// VinetasUI
//
// Whether the host wraps the prompt panel in a `NavigationStack`. SwiftUI
// offers no query for an enclosing stack, so the host says so through this
// environment flag instead.

import SwiftUI

extension EnvironmentValues {

  /// Whether an enclosing `NavigationStack` is available to the prompt panel.
  ///
  /// At compact width the panel's chevron rows are `NavigationLink`s, which
  /// need a stack. A host that presents the panel without one sets this to
  /// `false`, and those rows open as popovers instead. Defaults to `true`.
  @Entry public var vinetasNavigationStackAvailable: Bool = true
}

extension View {

  /// Tells the prompt panel in this view hierarchy whether an enclosing
  /// `NavigationStack` is available; pass `false` to get the popover form.
  public func vinetasNavigationStackAvailable(_ available: Bool) -> some View {
    environment(\.vinetasNavigationStackAvailable, available)
  }
}

// VinetasPanelLayout.swift
// VinetasUI
//
// The three shapes the prompt panel takes — a macOS sidebar, a regular-width
// iOS inspector, a compact-width iOS pushed screen — the pure resolver that
// picks one from a platform and a size class, and the environment value a
// host uses to force a shape instead of resolving it.

import SwiftUI

/// The platform a ``VinetasPanelLayout`` is resolved for.
///
/// Named explicitly, rather than read from `#if os(...)`, so the resolver is
/// a pure function that can be asked about iOS on a macOS test pass and the
/// other way round.
public enum VinetasPlatform: Sendable, CaseIterable {
  /// macOS, where the panel is always ``VinetasPanelLayout/sidebar``.
  case macOS
  /// iOS and iPadOS, where the panel follows the horizontal size class.
  case iOS
}

/// The horizontal size class, restated because SwiftUI's
/// `UserInterfaceSizeClass` is unavailable on macOS and the resolver must
/// compile, and be asked about iOS, on both platforms.
public enum VinetasSizeClass: Sendable, CaseIterable {
  /// A compact horizontal size class, such as an iPhone in portrait.
  case compact
  /// A regular horizontal size class, such as a full-screen iPad.
  case regular
}

/// The shape the prompt panel takes.
///
/// Views in VinetasUI read the resolved layout from the environment. A host
/// that wants a specific shape applies `vinetasPanelLayout(_:)`;
/// otherwise the shape comes from ``resolve(platform:horizontalSizeClass:)``.
public enum VinetasPanelLayout: Sendable, CaseIterable {
  /// The inspector column: the default on macOS, and the layout the inspector
  /// forces on iPad.
  case sidebar
  /// iOS at regular width outside an inspector (iPad full screen), with Steps
  /// and Guidance side by side.
  case regular
  /// iOS at compact width: the iPhone pushed screen, an inset-grouped form.
  case compact

  /// The layout for `platform` at `horizontalSizeClass`.
  ///
  /// macOS is always ``sidebar``, whatever the size class. On iOS a
  /// ``VinetasSizeClass/regular`` size class gives ``regular`` and a
  /// ``VinetasSizeClass/compact`` one gives ``compact``. An unknown size
  /// class — `nil`, which only happens outside a resolved SwiftUI hierarchy —
  /// is treated as ``regular``: that layout shows every control in
  /// place, so a guess never hides the panel behind a navigation push.
  public static func resolve(
    platform: VinetasPlatform,
    horizontalSizeClass: VinetasSizeClass?
  ) -> VinetasPanelLayout {
    switch platform {
    case .macOS:
      return .sidebar
    case .iOS:
      return horizontalSizeClass == .compact ? .compact : .regular
    }
  }
}

extension VinetasPlatform {

  /// The platform this code is compiled for.
  static var current: VinetasPlatform {
    #if os(macOS)
      return .macOS
    #else
      return .iOS
    #endif
  }
}

extension EnvironmentValues {

  /// A layout the host forces on the prompt panel, or `nil` to resolve one
  /// from the platform and the horizontal size class.
  ///
  /// Defaults to `nil`.
  @Entry public var vinetasPanelLayout: VinetasPanelLayout? = nil

  /// The layout VinetasUI views draw: ``vinetasPanelLayout`` when the host
  /// set one, otherwise ``VinetasPanelLayout/resolve(platform:horizontalSizeClass:)``
  /// for the current platform and, on iOS, `horizontalSizeClass` (`nil` on macOS).
  ///
  /// Views read it with `@Environment(\.resolvedPanelLayout)`.
  var resolvedPanelLayout: VinetasPanelLayout {
    if let vinetasPanelLayout {
      return vinetasPanelLayout
    }
    return VinetasPanelLayout.resolve(
      platform: .current,
      horizontalSizeClass: vinetasHorizontalSizeClass
    )
  }

  /// The horizontal size class as a ``VinetasSizeClass``; always `nil` on macOS.
  var vinetasHorizontalSizeClass: VinetasSizeClass? {
    #if os(iOS)
      switch horizontalSizeClass {
      case .compact: return .compact
      case .regular: return .regular
      case nil: return nil
      @unknown default: return nil
      }
    #else
      return nil
    #endif
  }
}

extension View {

  /// Forces the prompt panel in this view hierarchy into `layout`, or, with
  /// `nil`, restores resolving it from the platform and size class.
  public func vinetasPanelLayout(_ layout: VinetasPanelLayout?) -> some View {
    environment(\.vinetasPanelLayout, layout)
  }
}

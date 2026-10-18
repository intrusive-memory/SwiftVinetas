// Localization.swift
// VinetasUI
//
// The one route every user-facing string in VinetasUI takes into the
// package's English string catalogue (`Resources/Localizable.xcstrings`).

import Foundation

/// Looks up `key` in VinetasUI's own string catalogue.
///
/// Views in this package never call `String(localized:)` against the host's
/// main bundle; they call this helper so the lookup always resolves in
/// `Bundle.module`, whichever app embeds the package.
func localized(_ key: String.LocalizationValue) -> String {
  String(localized: key, bundle: .module)
}

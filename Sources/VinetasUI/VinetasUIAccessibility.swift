// VinetasUIAccessibility.swift
// VinetasUI
//
// Canonical accessibility identifiers for the prompt panel and its
// generation controls. Exposed publicly so host apps' UI tests can locate
// elements without duplicating the strings.

import Foundation

/// Stable accessibility identifiers used by the VinetasUI prompt panel.
///
/// Every `accessibilityIdentifier` a VinetasUI view sets comes from this
/// enum. Two identifiers are prefixes completed at runtime with a raw value:
///
/// ```text
/// stylePicker.row.<style.rawValue>
/// generation.aspectRatioTile.<ratio.rawValue>
/// ```
///
/// Use ``stylePickerRow(_:)`` and ``aspectRatioTile(_:)`` to build them.
/// Host apps reference these constants in their XCUITests rather than
/// hardcoding the strings.
public enum VinetasUIAccessibility {

  // MARK: - Prompt

  /// The primary prompt text editor.
  public static let promptPrimary = "prompt.primary"

  /// The caption shown with the prompt (the scene heading or shot label).
  public static let promptCaption = "prompt.caption"

  /// The style picker control inside the prompt panel.
  public static let promptStylePicker = "prompt.stylePicker"

  /// The custom style prompt text field.
  public static let promptStyleCustom = "prompt.styleCustom"

  /// The toggle that shows or hides the negative prompt.
  public static let promptNegativeToggle = "prompt.negativeToggle"

  /// The negative prompt text editor.
  public static let promptNegative = "prompt.negative"

  // MARK: - Style picker

  /// The list of styles in the style picker.
  public static let stylePickerList = "stylePicker.list"

  /// Style row identifier prefix. Full id: `"stylePicker.row.<style.rawValue>"`.
  public static let stylePickerRowPrefix = "stylePicker.row"

  /// The disclosure that reveals a style's prompt text.
  public static let stylePickerPromptTextDisclosure = "stylePicker.promptTextDisclosure"

  // MARK: - Generation settings

  /// The model picker.
  public static let generationModelPicker = "generation.modelPicker"

  /// The aspect-ratio selection group.
  public static let generationAspectRatioSelection = "generation.aspectRatioSelection"

  /// Aspect-ratio tile identifier prefix. Full id:
  /// `"generation.aspectRatioTile.<ratio.rawValue>"`.
  public static let generationAspectRatioTilePrefix = "generation.aspectRatioTile"

  /// The steps slider.
  public static let generationStepsSlider = "generation.stepsSlider"

  /// The control that resets steps to the model's default.
  public static let generationStepsUseDefault = "generation.stepsUseDefault"

  /// The guidance slider.
  public static let generationGuidanceSlider = "generation.guidanceSlider"

  /// The control that resets guidance to the model's default.
  public static let generationGuidanceUseDefault = "generation.guidanceUseDefault"

  /// The control that resets the aspect ratio to the default.
  public static let generationAspectRatioUseDefault = "generation.aspectRatioUseDefault"

  /// The seed text field.
  public static let generationSeedField = "generation.seedField"

  /// The control that picks a random seed.
  public static let generationRandomizeSeed = "generation.randomizeSeed"

  /// Retained for existing host UI tests only; no VinetasUI view renders it.
  public static let generationMemoryWarning = "generation.memoryWarning"

  // MARK: - Builders

  /// The identifier of the style picker row for the style with `rawValue`.
  ///
  /// - Parameter rawValue: The style's raw value, for example `"custom"`.
  /// - Returns: `"stylePicker.row.<rawValue>"`.
  public static func stylePickerRow(_ rawValue: String) -> String {
    "\(stylePickerRowPrefix).\(rawValue)"
  }

  /// The identifier of the aspect-ratio tile for the ratio with `rawValue`.
  ///
  /// - Parameter rawValue: The aspect ratio's raw value.
  /// - Returns: `"generation.aspectRatioTile.<rawValue>"`.
  public static func aspectRatioTile(_ rawValue: String) -> String {
    "\(generationAspectRatioTilePrefix).\(rawValue)"
  }
}

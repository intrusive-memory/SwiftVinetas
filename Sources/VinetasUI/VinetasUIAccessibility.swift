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

  /// The single-line caption field under the prompt.
  public static let promptCaption = "prompt.caption"

  /// The style picker's button or chevron row.
  public static let promptStylePicker = "prompt.stylePicker"

  /// The custom style field the style picker shows for free text.
  public static let promptStyleCustom = "prompt.styleCustom"

  /// The disclosure that shows or hides the Negative Prompt section.
  public static let promptNegativeToggle = "prompt.negativeToggle"

  /// The negative prompt text editor.
  public static let promptNegative = "prompt.negative"

  /// The note under the negative prompt when the selected model ignores it.
  public static let promptNegativeUnsupportedNote = "prompt.negativeUnsupportedNote"

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

  /// The Default toggle for steps.
  public static let generationStepsUseDefault = "generation.stepsUseDefault"

  /// The guidance slider.
  public static let generationGuidanceSlider = "generation.guidanceSlider"

  /// The Default toggle for guidance.
  public static let generationGuidanceUseDefault = "generation.guidanceUseDefault"

  /// The Default toggle for the aspect ratio.
  public static let generationAspectRatioUseDefault = "generation.aspectRatioUseDefault"

  /// The seed text field.
  public static let generationSeedField = "generation.seedField"

  /// The Randomize toggle for the seed.
  public static let generationRandomizeSeed = "generation.randomizeSeed"

  /// The note under the steps slider when the selected model does not use steps.
  public static let generationStepsUnsupportedNote = "generation.stepsUnsupportedNote"

  /// The note under the guidance slider when the selected model does not use
  /// guidance.
  public static let generationGuidanceUnsupportedNote = "generation.guidanceUnsupportedNote"

  /// The note under the seed when the selected model does not use a seed.
  public static let generationSeedUnsupportedNote = "generation.seedUnsupportedNote"

  /// Retained for existing host UI tests only; no VinetasUI view renders it.
  public static let generationMemoryWarning = "generation.memoryWarning"

  // MARK: - References and character

  /// The References row's container.
  public static let referencesList = "references.list"

  /// The button that adds a reference.
  public static let referencesAdd = "references.add"

  /// The note shown when the selected model accepts no reference images.
  public static let referencesUnsupportedNote = "references.unsupportedNote"

  /// Reference field identifier prefix. Full id: `"references.item.<index>"`.
  public static let referencesItemPrefix = "references.item"

  /// Reference remove-button prefix. Full id: `"references.remove.<index>"`.
  public static let referencesRemovePrefix = "references.remove"

  /// Reference move-up-button prefix. Full id: `"references.moveUp.<index>"`.
  public static let referencesMoveUpPrefix = "references.moveUp"

  /// Reference move-down-button prefix. Full id: `"references.moveDown.<index>"`.
  public static let referencesMoveDownPrefix = "references.moveDown"

  /// The Character row's text field.
  public static let characterField = "character.field"

  // MARK: - Builders

  /// The identifier of the reference field at `index`.
  public static func referenceItem(_ index: Int) -> String { "\(referencesItemPrefix).\(index)" }

  /// The identifier of the remove button for the reference at `index`.
  public static func referenceRemove(_ index: Int) -> String {
    "\(referencesRemovePrefix).\(index)"
  }

  /// The identifier of the move-up button for the reference at `index`.
  public static func referenceMoveUp(_ index: Int) -> String {
    "\(referencesMoveUpPrefix).\(index)"
  }

  /// The identifier of the move-down button for the reference at `index`.
  public static func referenceMoveDown(_ index: Int) -> String {
    "\(referencesMoveDownPrefix).\(index)"
  }

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

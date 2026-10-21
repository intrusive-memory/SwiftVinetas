import Foundation
import GlosaCore
import SwiftVinetas

/// The one shot → generation-parameters mapping, shared by `vinetas storyboard`
/// (every panel) and `vinetas generate --shot-json` (a single shot). Mirrors the
/// `generate` command's StyleConfig construction. Unrecognized `model`/`aspect`
/// values warn (prefixed with `label`) and fall back rather than aborting.
func resolveShotPlan(
  for shot: Shot, panelNumber: Int, label: String, fleetModel: CLIModel
) -> Storyboard.PanelPlan {
  // Resolve model: shot value wins (on-device short name or cloud model id);
  // unknown → warn + fleet default.
  let resolvedModel: CLIModel
  if let raw = shot.model {
    if let m = CLIModel.resolve(raw) {
      resolvedModel = m
    } else {
      stderrPrint(
        "[vinetas] \(label): unknown model '\(raw)', using '\(fleetModel.name)'.")
      resolvedModel = fleetModel
    }
  } else {
    resolvedModel = fleetModel
  }

  // Seed StyleConfig with the model's per-engine defaults (PixArt guidance/steps
  // differ from FLUX), then apply shot overrides — same order as `generate`.
  let descriptor = resolvedModel.descriptor
  var style = StyleConfig(
    steps: descriptor.defaultSteps,
    guidanceScale: descriptor.defaultGuidance
  )
  if let s = shot.style { style.stylePrompt = s }
  if let n = shot.negative { style.negativePrompt = n }
  if let steps = shot.steps { style.steps = steps }
  if let guidance = shot.guidance { style.guidanceScale = Float(guidance) }
  if let seed = shot.seed { style.seed = seed }

  // Aspect preset (explicit width/height take precedence). Unknown → warn + skip.
  if let aspectName = shot.aspect {
    if let ratio = AspectRatio(rawValue: aspectName) {
      style.width = ratio.width
      style.height = ratio.height
    } else {
      let valid = AspectRatio.allCases.map(\.rawValue).joined(separator: ", ")
      stderrPrint(
        "[vinetas] \(label): unknown aspect '\(aspectName)', ignoring. Valid: \(valid)"
      )
    }
  }
  if let width = shot.width { style.width = width }
  if let height = shot.height { style.height = height }

  if let lora = shot.lora { style.loraPath = lora }
  if let loraScale = shot.loraScale { style.loraScale = Float(loraScale) }

  // Cloud engines cannot apply a LoRA and ignore the flags their vendor
  // doesn't take. Warn per panel and keep going — a storyboard should not
  // abort twenty panels in over one shot's attribute.
  if let cloud = resolvedModel.cloud {
    if style.loraPath != nil {
      stderrPrint(
        "[vinetas] \(label): \(cloud.id) is a cloud model and cannot apply a LoRA; ignoring lora."
      )
      style.loraPath = nil
    }
    let warnings = cloudCapabilityWarnings(
      for: cloud, steps: shot.steps, guidance: shot.guidance.map { Float($0) },
      seed: shot.seed, negative: shot.negative)
    for line in warnings {
      stderrPrint("[vinetas] \(label): \(line)")
    }
  }

  // Preview is FLUX Klein-4B only (forces 4 steps / 512×512). If a shot asks
  // for preview on another model — on-device or cloud — warn and drop
  // preview rather than silently ignoring the model. Previews stay local.
  var usePreview = shot.preview ?? false
  if usePreview && resolvedModel != .klein4b {
    stderrPrint(
      "[vinetas] \(label): --preview is Klein-4B only; ignoring preview for '\(resolvedModel.name)'."
    )
    usePreview = false
  }
  if usePreview {
    style.steps = 4
    style.width = 512
    style.height = 512
  }

  // GlosaCore folds only *empty* prompts into defaults, so a non-empty,
  // all-whitespace prompt reaches here as a panel. It is a per-panel error.
  let problem: String? =
    shot.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    ? "panel \(panelNumber): whitespace-only prompt" : nil

  return Storyboard.PanelPlan(
    panelNumber: panelNumber,
    shot: shot,
    problem: problem,
    prompt: shot.prompt,
    model: resolvedModel,
    style: style,
    usePreview: usePreview,
    output: shot.output
  )
}

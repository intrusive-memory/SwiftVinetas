import ArgumentParser
import CoreGraphics
import Foundation
import GlosaCore
import SwiftVinetas

/// `vinetas storyboard` — generate a panel per `<shot>` directive in a
/// screenplay.
///
/// Parses a screenplay with GlosaCore (`.fountain` / `.highland` / `.fdx`),
/// folds the empty-prompt "defaults" convention (`ShotResolver`) into a list of
/// renderable shots, and maps each shot 1:1 onto a single-panel generation —
/// the same in-process path `vinetas generate` uses.
public struct Storyboard: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "storyboard",
    abstract: "Generate storyboard panels from a screenplay's <shot> directives."
  )

  public init() {}

  @Argument(help: "Path to a screenplay file (.fountain, .highland, or .fdx).")
  public var screenplay: String

  @Option(name: .shortAndLong, help: "Output directory for generated panels.")
  public var outputDir: String = "./storyboard"

  @Option(
    name: .long,
    help:
      "Fleet default model for shots that declare none: klein4b (default), klein9b, or pixart-sigma."
  )
  public var model: String = "klein4b"

  @Flag(
    name: .long,
    help: "Parse and resolve shots, print the storyboard prompts, and exit without generating.")
  public var dryRun: Bool = false

  @Flag(
    name: .long,
    help: "Continue generating remaining panels if one fails (default: stop on first failure).")
  public var continueOnError: Bool = false

  @Flag(
    name: .long,
    help:
      "Write a JSONL telemetry trace to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl for the whole run."
  )
  public var telemetry: Bool = false

  public func run() async throws {
    // Validate the fleet default up front so a bad --model fails fast.
    guard let fleetModel = VinetasModel(rawValue: model) else {
      let valid = VinetasModel.allCases.map(\.rawValue).joined(separator: ", ")
      throw ValidationError("Unknown model '\(model)'. Valid models: \(valid)")
    }

    // 1. Parse screenplay → shots + diagnostics.
    let (rawShots, diagnostics) = try ScreenplayShots.load(from: screenplay)
    for diagnostic in diagnostics {
      stderrPrint("[vinetas] glosa \(diagnostic.severity.rawValue): \(diagnostic.message)")
    }

    // 2. Fold the defaults convention → renderable shots.
    let shots = ShotResolver.resolve(rawShots)
    guard !shots.isEmpty else {
      stderrPrint(
        "[vinetas] No renderable <shot> directives found in \(screenplay). Nothing to generate.")
      return
    }

    // 3. Resolve each shot into a concrete generation plan (model + style),
    //    warning + falling back to the fleet default on unrecognized values.
    let plan = shots.enumerated().map { index, shot in
      resolvePlan(for: shot, panelNumber: index + 1, fleetModel: fleetModel)
    }

    // 4. Dry run: print only the resolved storyboard prompts (one per line, to
    //    stdout so they can be piped) and exit without generating.
    if dryRun {
      stderrPrint("[vinetas] Storyboard — \(plan.count) prompt(s):")
      for item in plan {
        print(item.prompt)
      }
      return
    }

    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .full) : nil
    defer { Task { await bootstrap?.finish() } }

    // Create output directory.
    let outputDirURL = URL(fileURLWithPath: outputDir)
    try FileManager.default.createDirectory(
      at: outputDirURL, withIntermediateDirectories: true)

    stderrPrint("[vinetas] Storyboard from: \(screenplay)")
    stderrPrint("[vinetas] Output directory: \(outputDirURL.path)")
    stderrPrint("[vinetas] Panels: \(plan.count)")

    // 5. Download every model the plan needs, up front (union), mirroring batch.
    let neededModels = Set(plan.map(\.model))
    for needed in neededModels {
      stderrPrint("[vinetas] Checking model cache: \(needed.rawValue)...")
      try await Vinetas.download(model: needed) { progress in
        stderrPrint(
          "[vinetas] Downloading \(needed.rawValue): \(String(format: "%.1f", progress.overallProgress * 100))%"
        )
      }
    }

    // 6. Generate each panel in order — one prompt per shot.
    var succeeded = 0
    var failures: [(panel: Int, error: Error)] = []

    for item in plan {
      let panelURL = outputURL(for: item, in: outputDirURL)
      stderrPrint(
        "[vinetas] Panel \(item.panelNumber)/\(plan.count) (\(item.model.rawValue)) → \(panelURL.lastPathComponent)"
      )
      do {
        let image: CGImage
        if item.usePreview {
          image = try await Vinetas.preview(prompt: item.prompt)
        } else {
          image = try await Vinetas.generate(
            prompt: item.prompt, style: item.style, model: item.model)
        }
        try ImageOutput.writePNG(image: image, to: panelURL)
        stderrPrint("[vinetas] Wrote \(panelURL.lastPathComponent)")
        succeeded += 1
      } catch {
        failures.append((item.panelNumber, error))
        if continueOnError {
          stderrPrint("[vinetas] Panel \(item.panelNumber) FAILED: \(error). Continuing.")
        } else {
          stderrPrint("[vinetas] Panel \(item.panelNumber) FAILED: \(error). Stopping.")
          throw error
        }
      }
    }

    stderrPrint(
      "[vinetas] Storyboard complete. \(succeeded)/\(plan.count) panel(s) written to \(outputDirURL.path)."
    )
    if !failures.isEmpty {
      stderrPrint("[vinetas] \(failures.count) panel(s) failed: \(failures.map(\.panel))")
    }
  }

  // MARK: - Planning

  /// A single resolved panel: concrete model + style, ready to generate.
  struct PanelPlan {
    var panelNumber: Int
    var prompt: String
    var model: VinetasModel
    var style: StyleConfig
    var usePreview: Bool
    var output: String?
  }

  /// Map a defaults-folded `Shot` onto a concrete generation plan, mirroring the
  /// `generate` command's StyleConfig construction. Unrecognized `model`/`aspect`
  /// values warn and fall back (fleet model / no aspect) rather than aborting the
  /// whole run.
  func resolvePlan(for shot: Shot, panelNumber: Int, fleetModel: VinetasModel) -> PanelPlan {
    // Resolve model: shot value wins; unknown → warn + fleet default.
    let resolvedModel: VinetasModel
    if let raw = shot.model {
      if let m = VinetasModel(rawValue: raw) {
        resolvedModel = m
      } else {
        stderrPrint(
          "[vinetas] Panel \(panelNumber): unknown model '\(raw)', using '\(fleetModel.rawValue)'.")
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
          "[vinetas] Panel \(panelNumber): unknown aspect '\(aspectName)', ignoring. Valid: \(valid)"
        )
      }
    }
    if let width = shot.width { style.width = width }
    if let height = shot.height { style.height = height }

    if let lora = shot.lora { style.loraPath = lora }
    if let loraScale = shot.loraScale { style.loraScale = Float(loraScale) }

    // Preview is FLUX Klein-4B only (forces 4 steps / 512×512). If a shot asks
    // for preview on another model, warn and drop preview rather than silently
    // ignoring --model.
    var usePreview = shot.preview ?? false
    if usePreview && resolvedModel != .klein4b {
      stderrPrint(
        "[vinetas] Panel \(panelNumber): --preview is Klein-4B only; ignoring preview for '\(resolvedModel.rawValue)'."
      )
      usePreview = false
    }
    if usePreview {
      style.steps = 4
      style.width = 512
      style.height = 512
    }

    return PanelPlan(
      panelNumber: panelNumber,
      prompt: shot.prompt,
      model: resolvedModel,
      style: style,
      usePreview: usePreview,
      output: shot.output
    )
  }

  /// Resolve a panel's output URL: honor an explicit `output` (relative paths
  /// resolved under the output dir), otherwise auto-name `panel-NNN.png`.
  func outputURL(for item: PanelPlan, in outputDir: URL) -> URL {
    if let output = item.output, !output.isEmpty {
      let url = URL(fileURLWithPath: output)
      return url.path.hasPrefix("/")
        ? url : outputDir.appendingPathComponent(output)
    }
    return outputDir.appendingPathComponent(String(format: "panel-%03d.png", item.panelNumber))
  }
}

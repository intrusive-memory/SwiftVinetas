import ArgumentParser
import Foundation
import GlosaCore
import SwiftVinetas

/// `vinetas storyboard` — generate a panel per `<shot>` directive in a
/// screenplay.
///
/// Parses a screenplay with GlosaCore (`.fountain` / `.highland` / `.fdx`),
/// folds the empty-prompt "defaults" convention (`GlosaScore.effectiveShots`)
/// into a list of renderable shots, and maps each shot 1:1 onto a single-panel generation —
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
    help: ArgumentHelp(
      "Fleet default model for shots that declare none: klein4b (default), pixart-sigma, "
        + "or a cloud model id such as bfl-flux-2-pro (see `vinetas list`).")
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
    guard let fleetModel = CLIModel.resolve(model) else {
      throw CLIModel.unknownModelError(model)
    }

    // 1. Parse screenplay → shots + diagnostics.
    let (score, diagnostics) = try ScreenplayShots.loadScore(from: screenplay)
    for diagnostic in diagnostics {
      stderrPrint("[vinetas] glosa \(diagnostic.severity.rawValue): \(diagnostic.message)")
    }

    // 2. Fold the defaults convention → renderable shots.
    let shots = score.effectiveShots
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
    //    stdout so they can be piped) and exit without generating. A panel with
    //    a whitespace-only prompt is reported to stderr instead of printed.
    if dryRun {
      stderrPrint("[vinetas] Storyboard — \(plan.count) prompt(s):")
      for item in plan {
        if let problem = item.problem {
          stderrPrint("[vinetas] Panel \(item.panelNumber) ERROR: \(problem)")
        } else {
          print(item.prompt)
        }
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
    //    Check the Pro gate for the whole union first: a board that is half
    //    FLUX.2 should fail before panel 1, not twenty panels in.
    //    Cloud models have nothing to download and are never Pro-gated; a
    //    missing API key surfaces from the first panel as exit code 78.
    let neededModels = Set(plan.filter { $0.problem == nil }.map(\.model)).sorted {
      $0.name < $1.name
    }
    for needed in neededModels {
      try await ProGate.requireAccess(to: needed)
    }
    for needed in neededModels {
      try await downloadIfNeeded(needed)
    }

    // 6. Generate each panel in order — one prompt per shot.
    var succeeded = 0
    var failures: [(panel: Int, error: Error)] = []

    try await reportingCloudErrors {
      for item in plan {
        let panelURL = outputURL(for: item, in: outputDirURL)
        stderrPrint(
          "[vinetas] Panel \(item.panelNumber)/\(plan.count) (\(item.model.name)) → \(panelURL.lastPathComponent)"
        )
        do {
          if let problem = item.problem {
            throw StoryboardPanelError(message: problem)
          }
          // Always through the PanelRequest path — including preview panels,
          // whose steps/width/height overrides are already folded into
          // `item.style` by `resolvePlan` — so `writePanel` records what this
          // panel actually used (RI-13). `VinetasClient.preview(prompt:)` would
          // skip that: it returns a bare `CGImage` with no metadata.
          let generated = try await CLIEnvironment.client.generate(
            PanelRequest(prompt: item.prompt, style: item.style, model: item.model.descriptor))
          try ImageOutput.writePanel(
            image: generated.image, metadata: generated.metadata, to: panelURL)
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
    /// The effective shot (defaults already folded by `GlosaScore.effectiveShots`)
    /// this panel was planned from. Later stages (ref/character, output, the
    /// GLOSA render record) read it from here.
    var shot: Shot
    /// Set when the panel cannot be generated (currently: whitespace-only
    /// prompt). Reported per panel, honouring `--continue-on-error`, and in
    /// `--dry-run`; never printed as a prompt.
    var problem: String? = nil
    var prompt: String
    var model: CLIModel
    var style: StyleConfig
    var usePreview: Bool
    var output: String?
  }

  /// Map a defaults-folded `Shot` onto a concrete generation plan, mirroring the
  /// `generate` command's StyleConfig construction. Unrecognized `model`/`aspect`
  /// values warn and fall back (fleet model / no aspect) rather than aborting the
  /// whole run.
  func resolvePlan(for shot: Shot, panelNumber: Int, fleetModel: CLIModel) -> PanelPlan {
    // Resolve model: shot value wins (on-device short name or cloud model id);
    // unknown → warn + fleet default.
    let resolvedModel: CLIModel
    if let raw = shot.model {
      if let m = CLIModel.resolve(raw) {
        resolvedModel = m
      } else {
        stderrPrint(
          "[vinetas] Panel \(panelNumber): unknown model '\(raw)', using '\(fleetModel.name)'.")
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

    // Cloud engines cannot apply a LoRA and ignore the flags their vendor
    // doesn't take. Warn per panel and keep going — a storyboard should not
    // abort twenty panels in over one shot's attribute.
    if let cloud = resolvedModel.cloud {
      if style.loraPath != nil {
        stderrPrint(
          "[vinetas] Panel \(panelNumber): \(cloud.id) is a cloud model and cannot apply a LoRA; ignoring lora."
        )
        style.loraPath = nil
      }
      let warnings = cloudCapabilityWarnings(
        for: cloud, steps: shot.steps, guidance: shot.guidance.map { Float($0) },
        seed: shot.seed, negative: shot.negative)
      for line in warnings {
        stderrPrint("[vinetas] Panel \(panelNumber): \(line)")
      }
    }

    // Preview is FLUX Klein-4B only (forces 4 steps / 512×512). If a shot asks
    // for preview on another model — on-device or cloud — warn and drop
    // preview rather than silently ignoring the model. Previews stay local.
    var usePreview = shot.preview ?? false
    if usePreview && resolvedModel != .klein4b {
      stderrPrint(
        "[vinetas] Panel \(panelNumber): --preview is Klein-4B only; ignoring preview for '\(resolvedModel.name)'."
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

    return PanelPlan(
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

  /// Resolve a panel's output URL: honor an explicit `output` (relative paths
  /// resolved under the output dir), otherwise auto-name `panel-NNN.png`.
  func outputURL(for item: PanelPlan, in outputDir: URL) -> URL {
    if let output = item.output, !output.isEmpty {
      // Test the raw string, not `URL(fileURLWithPath:).path`. That initializer
      // resolves a relative path against the process's current directory, so the
      // resulting URL is *always* absolute — which made the old check always
      // true and silently sent `<shot output="panel.png"/>` to the CWD instead
      // of `--output-dir`. Under the sandboxed CLI shipped in Vinetas.app that
      // is not merely wrong, it is unwritable.
      return output.hasPrefix("/")
        ? URL(fileURLWithPath: output)
        : outputDir.appendingPathComponent(output)
    }
    return outputDir.appendingPathComponent(String(format: "panel-%03d.png", item.panelNumber))
  }
}

/// A panel that cannot be generated before any engine is involved (e.g. a
/// whitespace-only prompt).
struct StoryboardPanelError: Error, CustomStringConvertible {
  var message: String
  var description: String { message }
}

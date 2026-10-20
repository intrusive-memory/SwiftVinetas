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
    let referenceResolver = StoryboardReferenceResolver(screenplay: screenplay)
    var succeeded = 0
    var failures: [(panel: Int, error: Error)] = []

    try await reportingCloudErrors {
      for item in plan {
        let panelURL = outputURL(
          for: item, in: outputDirURL,
          relativeTo: referenceResolver.projectRoot
            ?? URL(fileURLWithPath: screenplay).deletingLastPathComponent())
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
          try checkWritable(panelURL, for: item)
          let inputs = try panelInputs(for: item, resolver: referenceResolver)
          let generated = try await CLIEnvironment.client.generate(
            PanelRequest(
              prompt: item.prompt, style: item.style, model: item.model.descriptor,
              references: inputs.references, character: inputs.character,
              shot: item.shot))
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

  /// Map a defaults-folded `Shot` onto a concrete generation plan. The mapping
  /// itself lives in `resolveShotPlan` (Storyboard/ShotPlan.swift), shared with
  /// `vinetas generate --shot-json`.
  func resolvePlan(for shot: Shot, panelNumber: Int, fleetModel: CLIModel) -> PanelPlan {
    resolveShotPlan(
      for: shot, panelNumber: panelNumber, label: "Panel \(panelNumber)", fleetModel: fleetModel)
  }

  /// The references (in `ref` order, a character slug expanding to its
  /// reference images) and the character a panel needs, resolved per panel so a
  /// failure is that panel's failure (and honours `--continue-on-error`). The
  /// per-model reference limit is enforced by `VinetasClient`'s
  /// `ReferenceValidator` before any vendor call.
  func panelInputs(
    for item: PanelPlan, resolver: StoryboardReferenceResolver
  ) throws -> (references: [ReferenceImage], character: Character?) {
    var references: [ReferenceImage] = []
    for entry in item.shot.ref ?? [] {
      do {
        for url in try resolver.resolve(entry) {
          references.append(try ReferenceImage.load(path: url.path))
        }
      } catch let error as StoryboardPanelError {
        throw StoryboardPanelError(message: "panel \(item.panelNumber): \(error.message)")
      }
    }
    var character: Character?
    if let slug = item.shot.character {
      do {
        character = try resolver.characters.loadCharacter(slug: slug)
      } catch {
        throw StoryboardPanelError(
          message:
            "panel \(item.panelNumber): unknown character '\(slug)' — no character.yaml in "
            + resolver.characters.characterDirectory(slug: slug).path)
      }
    }
    return (references, character)
  }

  /// Resolve a panel's output URL. An explicit relative `output` resolves
  /// against `base` — the project root, else the screenplay's folder
  /// (``StoryboardReferenceResolver/projectRoot``) — never the process's
  /// current directory and never `--output-dir`. An absolute `output` is used
  /// as given. A shot with no `output` is auto-named `panel-NNN.png` under
  /// `outputDir`.
  func outputURL(for item: PanelPlan, in outputDir: URL, relativeTo base: URL) -> URL {
    if let output = item.output, !output.isEmpty {
      // Test the raw string: `URL(fileURLWithPath:)` resolves a relative path
      // against the CWD, which the sandboxed CLI cannot write to.
      if output.hasPrefix("/") { return URL(fileURLWithPath: output) }
      return base.appendingPathComponent(output)
    }
    return outputDir.appendingPathComponent(String(format: "panel-%03d.png", item.panelNumber))
  }

  /// For a panel whose explicit relative `output` lands in the project root /
  /// screenplay folder, verify (via the injectable
  /// ``CLIEnvironment/directoryWritabilityProbe``) that the folder is writable.
  /// On denial the panel fails naming the full path and the remedy; there is
  /// no fallback to the CWD.
  func checkWritable(_ panelURL: URL, for item: PanelPlan) throws {
    guard let output = item.output, !output.isEmpty, !output.hasPrefix("/") else { return }
    let directory = panelURL.deletingLastPathComponent()
    guard CLIEnvironment.directoryWritabilityProbe(directory) else {
      throw StoryboardPanelError(
        message:
          "panel \(item.panelNumber): cannot write '\(panelURL.path)' — Vinetas has no write "
          + "access to '\(directory.path)'. Grant that folder to the Vinetas app, use an "
          + "absolute `output` in a writable location, or omit `output` to use --output-dir.")
    }
  }
}

/// A panel that cannot be generated before any engine is involved (e.g. a
/// whitespace-only prompt).
struct StoryboardPanelError: Error, CustomStringConvertible {
  var message: String
  var description: String { message }
}

import ArgumentParser
import CoreGraphics
import Foundation
import GlosaCore
import ImageIO
import SwiftAcervo
import SwiftVinetas

// MARK: - Helpers

/// Write one line of diagnostics to ``CLIEnvironment/stderrDescriptor``
/// (stderr in production).
///
/// Uses a raw `write(2)` loop rather than `FileHandle.standardError.write(_:)`,
/// which raises an uncatchable Objective-C exception on any write error (a
/// closed stderr, `EPIPE`, …). A diagnostic line is never worth a crash.
func stderrPrint(_ message: String) {
  writeAll(Data((message + "\n").utf8), to: CLIEnvironment.stderrDescriptor)
}

/// Load a CGImage from a file path using ImageIO.
func loadCGImage(from path: String) -> CGImage? {
  let url = URL(fileURLWithPath: path)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// One `note: ...` line per reference whose engine-side conditioning size
/// (``ReferenceImage/effectiveSize``) differs from what was decoded
/// (``ReferenceImage/originalSize``). Pure and synchronous so it's testable
/// without touching stdio; `Generate.run()` just prints whatever it returns.
func downscaleNoteLines(
  for references: [ReferenceImage], engineID: String = "flux2"
) -> [String] {
  references.enumerated().compactMap { index, reference in
    let effective = reference.effectiveSize(forEngineID: engineID)
    guard reference.originalSize != effective else { return nil }
    return "note: reference \(index + 1) (\(reference.source)) downscaled "
      + "\(reference.originalSize.width)×\(reference.originalSize.height) → "
      + "\(effective.width)×\(effective.height)"
  }
}

// MARK: - Generate a single panel

/// Reads the `--shot-json` argument: a file path, or `-` for stdin (read through
/// the injected closure so tests never touch the real standard input).
func readShotJSON(_ argument: String, stdin: () throws -> Data) throws -> Data {
  if argument == "-" { return try stdin() }
  do {
    return try Data(contentsOf: URL(fileURLWithPath: argument))
  } catch {
    throw ValidationError(
      "cannot read --shot-json file '\(argument)': \(error.localizedDescription)")
  }
}

public struct Generate: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Generate a single panel from a text prompt."
  )

  public init() {}

  @Argument(
    help: "Text description of the panel to generate. Required unless --shot-json is given.")
  public var prompt: String?

  @Option(name: .shortAndLong, help: "Style prompt for consistent look (e.g., 'noir comic').")
  public var style: String?

  @Option(
    name: .shortAndLong,
    help: "Output PNG path, or - to write the PNG (with embedded metadata, no sidecar) to stdout."
  )
  public var output: String = "panel.png"

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Model: klein4b (default), pixart-sigma, or a cloud model id such as "
        + "openai-gpt-image-2.5-flare or bfl-flux-2-pro.",
      discussion: """
        Cloud models run on the vendor's servers with your own API key and are
        never Pro-gated. Supply the key through the environment
        (OPENAI_API_KEY, GEMINI_API_KEY, BFL_API_KEY, STABILITY_API_KEY) or
        save it in Vinetas → Settings → Cloud Engines; `vinetas list` shows
        every cloud model and whether a key resolves. There is deliberately no
        --api-key flag.
        """
    )
  )
  public var model: String?

  @Option(name: .long, help: "Path to a LoRA safetensors file.")
  public var lora: String?

  @Option(name: .long, help: "LoRA scale (0.0-1.0).")
  public var loraScale: Float?

  @Option(name: .long, help: "Random seed for reproducibility.")
  public var seed: UInt64?

  @Option(name: .long, help: "Number of inference steps (higher = more detail, slower).")
  public var steps: Int?

  @Option(name: .long, help: "Classifier-free guidance scale.")
  public var guidance: Float?

  @Option(name: .long, help: "Output image width in pixels. Overrides --aspect width.")
  public var width: Int?

  @Option(name: .long, help: "Output image height in pixels. Overrides --aspect height.")
  public var height: Int?

  @Option(
    name: .long, help: "Aspect ratio preset: square, wide, ultrawide, portrait, panel, strip.")
  public var aspect: String?

  @Option(name: .long, help: "Negative prompt to steer away from unwanted characteristics.")
  public var negative: String?

  @Flag(name: .long, help: "Fast preview mode (4 steps, 512x512, Klein 4B).")
  public var preview: Bool = false

  @Option(
    name: [.customShort("r"), .customLong("reference")],
    help: ArgumentHelp(
      "Reference (conditioning) image path, or - to read one from stdin. Repeatable.",
      discussion: """
        The limit is per model: 3 for klein4b, 10 for the OpenAI models and
        Nano Banana 2.1 / Gemini 3.1 Flash Image, 6 for Gemini 3 Pro Image.
        PixArt, BFL, and Stability models take none. `vinetas list --json`
        reports maxReferenceImages for every model.
        """
    )
  )
  public var references: [String] = []

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Character slug (see `vinetas character list`) to depict in the panel.",
      discussion: """
        On-device, the character's trained LoRA is applied with its trigger
        word. On a cloud model that takes references, the character's
        description is written into the prompt and its reference sheets and
        source photos are attached (unless --reference is given). The trigger
        word is never sent without the adapter it activates.
        """
    )
  )
  public var character: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      "A bare GLOSA 2.0 shot object (JSON): a file path, or - to read it from stdin.",
      discussion: """
        The shot supplies the generation parameters (prompt, model, style,
        negative, steps, guidance, seed, aspect/size, lora, preview, ref,
        character) exactly as `vinetas storyboard` maps them, and is recorded
        in the sidecar's `glosa` object. Relative `ref` paths resolve against
        the shot file's folder; with - only absolute paths and character slugs
        resolve. It cannot be combined with the prompt argument or with
        --style, --model, --seed, --steps, --guidance, --width, --height,
        --aspect, --negative, --lora, --lora-scale, --preview, --reference or
        --character; --output, --dry-run and --telemetry remain allowed.
        """
    )
  )
  public var shotJson: String?

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Print the fully resolved request as JSON to stdout and exit without generating.",
      discussion: """
        Shows exactly what would be sent: the model and engine, the prompt
        text the engine receives (for a cloud model, the rendered prompt
        bundle spelling out style, frame size, aspect ratio, character, and
        reference roles), the native parameters, every reference image, and
        any LoRA. Nothing is downloaded, no model is loaded, and no vendor is
        called, so no cost is incurred.
        """
    )
  )
  public var dryRun: Bool = false

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Write a JSONL trace of every library handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
      discussion: """
        Captures events from the instrumented libraries actually reached by this
        generation. The set of `kind` discriminants you see depends on which
        engine routes the request:

          SwiftVinetas    — always (engine routing, memory verdict, model lifecycle)

          flux-2-swift-mlx — Flux2 routes only (Klein/Dev). Pipeline lifecycle,
                             weight load, quantization, text encode, scheduler,
                             per-step denoise{Start,Complete}, VAE decode.

          pixart-swift-mlx — PixArt routes only. Weight load, recipe validation,
                             per-forward backboneForwardComplete, numerical
                             anomalies.

          SwiftTuberia    — PixArt routes only. Pipeline assembly, weight load,
                             encoder/scheduler/backbone/decoder boundary stats,
                             per-step latent stats.

          SwiftAcervo     — PixArt routes only (component-keyed cache events
                             via withComponentAccess, plus the SwiftAcervo
                             0.17+ inFlightDownloadRegistered/Cleared pair
                             from any ensureComponentReady download).
                             Flux2 currently reaches Acervo through a static
                             seam without a reporter, so kind:acervo events do
                             not appear on Flux2 runs.

        The trace path is printed to stderr after the run completes.

        See docs/TELEMETRY.md for the full event catalogue and analysis tips.

        Example:
          vinetas generate "a cyberpunk diner at dusk" --telemetry
          # → trace at ~/Library/Caches/vinetas/telemetry/2026-05-15T143022.jsonl
        """
    )
  )
  public var telemetry: Bool = false

  /// Names of the explicit generation flags that cannot accompany `--shot-json`.
  var shotJsonConflicts: [String] {
    var names: [String] = []
    if prompt != nil { names.append("<prompt>") }
    if style != nil { names.append("--style") }
    if model != nil { names.append("--model") }
    if seed != nil { names.append("--seed") }
    if steps != nil { names.append("--steps") }
    if guidance != nil { names.append("--guidance") }
    if width != nil { names.append("--width") }
    if height != nil { names.append("--height") }
    if aspect != nil { names.append("--aspect") }
    if negative != nil { names.append("--negative") }
    if lora != nil { names.append("--lora") }
    if loraScale != nil { names.append("--lora-scale") }
    if preview { names.append("--preview") }
    if !references.isEmpty { names.append("--reference") }
    if character != nil { names.append("--character") }
    return names
  }

  public mutating func validate() throws {
    if shotJson != nil {
      let conflicts = shotJsonConflicts
      guard conflicts.isEmpty else {
        throw ValidationError(
          "--shot-json supplies the generation parameters and cannot be combined with "
            + conflicts.joined(separator: ", ")
            + ". Put those settings in the shot, or drop --shot-json.")
      }
    } else if prompt == nil {
      throw ValidationError("Missing expected argument '<prompt>' (or pass --shot-json).")
    }
    let stdinReferenceCount = references.filter { $0 == "-" }.count
    guard stdinReferenceCount <= 1 else {
      throw ValidationError("only one --reference may read from stdin")
    }
  }

  public func run() async throws {
    // `-o -` streams the PNG to stdout. Guard fd 1 before anything else runs
    // so library `print(` output lands on stderr, never in the PNG stream.
    if output == "-" { StdoutGuard.begin() }
    defer { if output == "-" { StdoutGuard.end() } }

    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .full) : nil
    defer { Task { await bootstrap?.finish() } }

    try await reportingCloudErrors { try await generatePanel() }
  }

  /// The body of `run()`, split out so a `CloudEngineError` maps to its exit
  /// code in one place (`reportingCloudErrors`).
  private func generatePanel() async throws {
    var loadedReferences: [ReferenceImage] = []
    var loadedCharacter: Character?
    var recordedShot: Shot?
    var warnedNegative = false
    let cliModel: CLIModel
    var styleConfig: StyleConfig
    let promptText: String
    let negativeText: String?

    if let shotJson {
      // The shot supplies every generation parameter; the mapping is the one
      // `vinetas storyboard` uses (`resolveShotPlan`).
      let data = try readShotJSON(shotJson, stdin: { CLIEnvironment.stdinReferenceData() })
      let shot: Shot
      do {
        shot = try Shot(schemaJSONData: data)
      } catch {
        throw ValidationError("invalid --shot-json: \(error.message)")
      }
      let plan = resolveShotPlan(for: shot, panelNumber: 1, label: "Shot", fleetModel: .klein4b)
      if let problem = plan.problem { throw ValidationError("invalid --shot-json: \(problem)") }
      cliModel = plan.model
      try await ProGate.requireAccess(to: cliModel)
      // D-7: relative `ref` paths resolve against the shot file's folder;
      // stdin has no folder (absolute paths and character slugs only).
      let resolver = StoryboardReferenceResolver(
        documentFolder: shotJson == "-"
          ? nil : URL(fileURLWithPath: shotJson).deletingLastPathComponent())
      let inputs = try Storyboard().panelInputs(for: plan, resolver: resolver)
      loadedReferences = inputs.references
      loadedCharacter = inputs.character
      styleConfig = plan.style
      promptText = plan.prompt
      negativeText = shot.negative
      recordedShot = shot
      warnedNegative = cliModel.cloud != nil
    } else {
      guard let resolved = CLIModel.resolve(model ?? "klein4b") else {
        throw CLIModel.unknownModelError(model ?? "klein4b")
      }
      cliModel = resolved
      try await ProGate.requireAccess(to: cliModel)

      // --preview is a FLUX-only fast path (forces Klein 4B at 4 steps, 512×512).
      // Combining it with another model — on-device or cloud — would silently
      // ignore --model. Previews are free by design and always stay on-device.
      if preview && cliModel != .klein4b {
        throw ValidationError(
          "--preview is FLUX.2-only (Klein 4B, 4 steps, 512×512) and always runs on-device. "
            + "Drop --model or omit --preview."
        )
      }

      // Cloud vendors ignore flags they don't take: say so once, up front,
      // instead of after a paid call. LoRA is the one hard refusal — a cloud
      // engine cannot apply an adapter at all.
      if let cloud = cliModel.cloud {
        if lora != nil {
          throw ValidationError(
            "'\(cloud.id)' is a cloud model; cloud engines cannot apply LoRA adapters. "
              + "Drop --lora or use an on-device model (klein4b)."
          )
        }
        let warnings = cloudCapabilityWarnings(
          for: cloud, steps: steps, guidance: guidance, seed: seed, negative: negative)
        for line in warnings { stderrPrint(line) }
        warnedNegative = warnings.contains { $0.contains("--negative") }
      }

      // Load and validate reference images BEFORE any download or engine call
      // (RI-1 – RI-5): a bad path, an unsupported engine, or too many
      // references all fail fast, with no download and no model load.
      loadedCharacter = try character.map { try CharacterManager().loadCharacter(slug: $0) }
      for reference in references {
        if reference == "-" {
          let data = CLIEnvironment.stdinReferenceData()
          loadedReferences.append(try ReferenceImage.load(data: data, source: .stdin))
        } else {
          loadedReferences.append(try ReferenceImage.load(path: reference))
        }
      }

      // Seed StyleConfig with this model's per-engine defaults so PixArt's
      // recommended guidance (4.5) and steps don't get overridden by FLUX-tuned
      // defaults. User-supplied --steps / --guidance still take precedence.
      let seedDescriptor = cliModel.descriptor
      styleConfig = StyleConfig(
        steps: seedDescriptor.defaultSteps,
        guidanceScale: seedDescriptor.defaultGuidance
      )
      if let stylePrompt = style { styleConfig.stylePrompt = stylePrompt }
      if let negative { styleConfig.negativePrompt = negative }
      if let steps { styleConfig.steps = steps }
      if let guidance { styleConfig.guidanceScale = guidance }
      if let seed { styleConfig.seed = seed }

      // Apply aspect ratio preset (explicit --width/--height take precedence)
      if let aspectName = aspect {
        guard let ratio = AspectRatio(rawValue: aspectName) else {
          let validValues = AspectRatio.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError(
            "Unknown aspect ratio '\(aspectName)'. Valid values: \(validValues)")
        }
        styleConfig.width = ratio.width
        styleConfig.height = ratio.height
      }
      if let width { styleConfig.width = width }
      if let height { styleConfig.height = height }

      if let lora { styleConfig.loraPath = lora }
      styleConfig.loraScale = loraScale ?? 0.8

      // Override everything for preview mode
      if preview {
        styleConfig.steps = 4
        styleConfig.width = 512
        styleConfig.height = 512
      }
      promptText = prompt ?? ""
      negativeText = negative
    }

    let descriptor = cliModel.descriptor
    if !loadedReferences.isEmpty {
      let engine = try await CLIEnvironment.client.router.engine(for: descriptor)
      try ReferenceValidator.validate(
        referenceCount: loadedReferences.count, engine: engine, model: descriptor)
    }
    for line in downscaleNoteLines(for: loadedReferences, engineID: descriptor.engineID) {
      stderrPrint(line)
    }

    let panelRequest = PanelRequest(
      prompt: promptText, style: styleConfig, model: descriptor, references: loadedReferences,
      character: loadedCharacter, shot: recordedShot)

    if dryRun {
      let prepared = try await CLIEnvironment.client.prepare(panelRequest)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let json = try encoder.encode(DryRunReport(prepared, character: loadedCharacter))
      print(String(decoding: json, as: UTF8.self))
      return
    }

    stderrPrint("[vinetas] Generating panel...")
    stderrPrint("[vinetas] Model: \(cliModel.name)")
    stderrPrint("[vinetas] Dimensions: \(styleConfig.width)x\(styleConfig.height)")
    stderrPrint("[vinetas] Steps: \(styleConfig.steps)")

    // Download model if not already cached (zero-config first run). A cloud
    // model has nothing to download.
    try await downloadIfNeeded(cliModel)

    // --preview goes through the same PanelRequest path (its Klein 4B /
    // 4-step / 512×512 overrides are already applied to styleConfig above), so
    // it records real provenance metadata like any other panel.
    let panel = try await CLIEnvironment.client.generate(panelRequest)
    if let loadedCharacter {
      let carried =
        panel.metadata.loras?.isEmpty == false
        ? "LoRA v\(loadedCharacter.lora?.version ?? 0)"
        : "\(panel.metadata.references?.count ?? 0) reference image(s) + description"
      stderrPrint("[vinetas] Character: \(loadedCharacter.name) (\(carried))")
    }

    if negativeText != nil, !warnedNegative, panel.metadata.negativeApplied == false {
      let engineName = panel.metadata.engine ?? descriptor.engineID
      stderrPrint("warning: \(engineName) does not apply negative prompts; --negative ignored")
    }

    if output == "-" {
      // Embedded metadata only: no sidecar, and no file named "-".
      try StdoutGuard.write(ImageOutput.pngData(image: panel.image, metadata: panel.metadata))
      stderrPrint("[vinetas] Done. Output: stdout")
      return
    }

    let outputURL = URL(fileURLWithPath: output)
    try ImageOutput.writePanel(image: panel.image, metadata: panel.metadata, to: outputURL)
    let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("json")
    stderrPrint("[vinetas] Done. Output: \(outputURL.path)")
    stderrPrint("[vinetas] Metadata: \(sidecarURL.path)")
  }
}

// MARK: - Batch generate from a prompts file

public struct Batch: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Generate a sequence of panels from a YAML prompts file."
  )

  public init() {}

  @Argument(help: "Path to a YAML prompt file.")
  public var promptsFile: String

  @Option(name: .shortAndLong, help: "Output directory for generated panels.")
  public var outputDir: String = "./panels"

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Model: klein4b (default), pixart-sigma, or a cloud model id such as "
        + "openai-gpt-image-2.5-flare or bfl-flux-2-pro.",
      discussion: """
        Cloud models run on the vendor's servers with your own API key and are
        never Pro-gated. Supply the key through the environment
        (OPENAI_API_KEY, GEMINI_API_KEY, BFL_API_KEY, STABILITY_API_KEY) or
        save it in Vinetas → Settings → Cloud Engines; `vinetas list` shows
        every cloud model and whether a key resolves. There is deliberately no
        --api-key flag.
        """
    )
  )
  public var model: String = "klein4b"

  @Option(
    name: .long, help: "Aspect ratio preset: square, wide, ultrawide, portrait, panel, strip.")
  public var aspect: String?

  @Flag(name: .long, help: "Fast preview mode (reduced quality and resolution).")
  public var preview: Bool = false

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Write a JSONL trace of every library handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
      discussion: """
        Captures events from the instrumented libraries actually reached by each
        per-prompt iteration. The set of `kind` discriminants you see depends on
        which engine routes the request:

          SwiftVinetas    — always.
          flux-2-swift-mlx — Flux2 routes only.
          pixart-swift-mlx — PixArt routes only.
          SwiftTuberia    — PixArt routes only.
          SwiftAcervo     — PixArt routes only. Includes the SwiftAcervo 0.17+
                             inFlightDownloadRegistered/Cleared events for any
                             component download that actually runs. Flux2
                             reaches Acervo via a static seam with no reporter,
                             so kind:acervo events do not appear on Flux2 runs.

        Per-prompt events from each iteration land in the same trace file.
        The trace path is printed to stderr after the run completes.
        See docs/TELEMETRY.md for the full event catalogue.
        """
    )
  )
  public var telemetry: Bool = false

  public func run() async throws {
    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .full) : nil
    defer { Task { await bootstrap?.finish() } }

    try await reportingCloudErrors { try await generateBatch() }
  }

  /// The body of `run()`, split out so a `CloudEngineError` maps to its exit
  /// code in one place. Panels run sequentially — cloud vendors rate-limit,
  /// so there is no parallel fan-out.
  private func generateBatch() async throws {
    guard let cliModel = CLIModel.resolve(model) else {
      throw CLIModel.unknownModelError(model)
    }
    try await ProGate.requireAccess(to: cliModel)
    let promptURL = URL(fileURLWithPath: promptsFile)
    let outputDirURL = URL(fileURLWithPath: outputDir)

    // Create output directory if needed
    try FileManager.default.createDirectory(
      at: outputDirURL,
      withIntermediateDirectories: true,
      attributes: nil
    )

    // Validate aspect ratio option if provided
    if let aspectName = aspect {
      guard AspectRatio(rawValue: aspectName) != nil else {
        let validValues = AspectRatio.allCases.map(\.rawValue).joined(separator: ", ")
        throw ValidationError("Unknown aspect ratio '\(aspectName)'. Valid values: \(validValues)")
      }
    }

    stderrPrint("[vinetas] Batch generating from: \(promptsFile)")
    stderrPrint("[vinetas] Output directory: \(outputDirURL.path)")
    stderrPrint("[vinetas] Model: \(cliModel.name)")
    if let aspectName = aspect, let ratio = AspectRatio(rawValue: aspectName) {
      stderrPrint("[vinetas] Aspect ratio: \(aspectName) (\(ratio.width)x\(ratio.height))")
    }

    // Download model if not cached (zero-config first run). A cloud model has
    // nothing to download.
    try await downloadIfNeeded(cliModel)

    let panels = try await Self.generatePanels(
      from: promptURL,
      descriptor: cliModel.descriptor,
      client: CLIEnvironment.client,
      progress: { current, total in
        stderrPrint("[vinetas] Panel \(current)/\(total)...")
      }
    )

    for (index, panel) in panels.enumerated() {
      let panelNumber = index + 1
      let filename = String(format: "panel-%03d.png", panelNumber)
      let panelURL = outputDirURL.appendingPathComponent(filename)
      try ImageOutput.writePanel(image: panel.image, metadata: panel.metadata, to: panelURL)
      stderrPrint("[vinetas] Wrote \(filename) (seed: \(panel.metadata.seed))")
    }

    stderrPrint(
      "[vinetas] Batch complete. \(panels.count) panel(s) written to \(outputDirURL.path)")
  }

  /// Generate every panel of a YAML prompt file through `client`.
  ///
  /// Mirrors the deprecated static prompt-file loop (project style as
  /// defaults with per-panel overrides, seed resolved up front so the recorded
  /// seed is accurate) but dispatches through the injected client and never
  /// downloads — `run()` owns the download. Uses
  /// ``VinetasClient/generate(_:characters:stepProgress:)`` (rather than the plain-`CGImage`
  /// overload) so each returned ``GeneratedPanel/metadata`` records exactly
  /// what was used for that item (RI-13): actual seed, steps, guidance, etc.
  static func generatePanels(
    from url: URL,
    descriptor: any ModelDescriptor,
    client: VinetasClient,
    progress: (Int, Int) -> Void
  ) async throws -> [GeneratedPanel] {
    let promptFile = try PromptFile.parse(url: url)
    let total = promptFile.panels.count
    var outputs: [GeneratedPanel] = []
    outputs.reserveCapacity(total)

    for index in 0..<total {
      progress(index + 1, total)

      let panel = promptFile.panels[index]
      var panelStyle = promptFile.resolvedStyle(for: index)
      let resolvedSeed = panelStyle.seed ?? UInt64.random(in: 0...UInt64.max)
      panelStyle.seed = resolvedSeed

      let generated = try await client.generate(
        PanelRequest(prompt: panel.prompt, style: panelStyle, model: descriptor))
      outputs.append(generated)
    }
    return outputs
  }
}

// MARK: - Download models

public struct Download: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Download a model for local generation."
  )

  public init() {}

  @Option(
    name: .shortAndLong,
    help: "Model to download: klein4b or pixart-sigma. A cloud model id is accepted and is a no-op."
  )
  public var model: String = "klein4b"

  public func run() async throws {
    guard let cliModel = CLIModel.resolve(model) else {
      throw CLIModel.unknownModelError(model)
    }
    if let cloud = cliModel.cloud {
      print(
        "'\(cloud.id)' is a cloud model served by \(cloud.provider.displayName) — nothing to download. "
          + "Set \(cloud.provider.environmentVariable) (or add the key in Vinetas → Settings → "
          + "Cloud Engines) and run `vinetas generate --model \(cloud.id)`."
      )
      return
    }
    let vinetasModel = cliModel.local ?? .klein4b
    try await ProGate.requireAccess(to: vinetasModel)

    stderrPrint("[vinetas] Downloading model: \(vinetasModel.rawValue)")
    stderrPrint("[vinetas] Repo: \(vinetasModel.repoId)")

    try await Vinetas.download(model: vinetasModel) { progress in
      let pct = String(format: "%.1f", progress.overallProgress * 100)
      stderrPrint("[vinetas] Progress: \(pct)%")
    }

    print("Model '\(vinetasModel.rawValue)' downloaded successfully.")
  }
}

// MARK: - List cached models

public struct ListModels: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List models: on-device cache status and cloud API-key status."
  )

  public init() {}

  @Flag(name: .long, help: "Output model information as JSON.")
  public var json: Bool = false

  /// One cloud row: the catalog entry plus whether a key resolves and a
  /// key-free description of where it came from.
  struct CloudRow {
    var model: CloudModelDescriptor
    var configured: Bool
    var source: String?
  }

  public func run() async throws {
    let client = CLIEnvironment.client
    let registered = await client.router.allModels

    // Cloud rows come from the registered cloud descriptors in catalog
    // (provider → model) order; on-device rows keep the cache-status surface
    // `listModels()` has always had.
    let cloudModels = CloudModelDescriptor.all.filter { catalog in
      registered.contains { $0.id == catalog.id }
    }
    let cloudDisplayNames = Set(cloudModels.map(\.displayName))
    let localModels = await client.listModels().filter { !cloudDisplayNames.contains($0.name) }

    var cloudRows: [CloudRow] = []
    for cloud in cloudModels {
      let status = await cloudKeyStatus(for: cloud, client: client)
      cloudRows.append(CloudRow(model: cloud, configured: status.configured, source: status.source))
    }

    if json {
      try await printJSON(local: localModels, cloud: cloudRows)
    } else {
      printTable(local: localModels, cloud: cloudRows)
    }
  }

  private func printJSON(local: [VinetasModelInfo], cloud: [CloudRow]) async throws {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]

    // Report the Pro gate alongside the cache state so a tool driving the CLI
    // can tell "you have not downloaded this" apart from "you cannot use
    // this", which are very different problems with very different fixes.
    let isUnlocked = await ProGate.status().isUnlocked

    var jsonModels: [[String: Any]] = []
    for info in local {
      var entry: [String: Any] = [
        "name": info.name,
        "size": info.size,
        "formattedSize": info.formattedSize,
        "isDownloaded": info.isDownloaded,
        "cloud": false,
      ]
      if let model = VinetasModel.allCases.first(where: {
        $0.descriptor.displayName == info.name
      }) {
        entry["model"] = model.rawValue
        let requiresPro = ProGate.requiresPro(model)
        entry["requiresPro"] = requiresPro
        if requiresPro { entry["isUnlocked"] = isUnlocked }
        if let engine = try? await CLIEnvironment.client.router.engine(for: model.descriptor) {
          entry["maxReferenceImages"] = engine.maxReferenceImages(for: model.descriptor)
        }
      }
      if let date = info.downloadDate {
        entry["downloadDate"] = isoFormatter.string(from: date)
      }
      jsonModels.append(entry)
    }

    // Cloud entries: same `model` / `requiresPro` / `isDownloaded` keys an
    // agent already reads, plus the key status and how to configure it. No
    // key material, ever.
    for row in cloud {
      let cloud = row.model
      var entry: [String: Any] = [
        "name": cloud.displayName,
        "model": cloud.id,
        "cloud": true,
        "provider": cloud.provider.rawValue,
        "vendorModelID": cloud.vendorModelID,
        "engineID": cloud.engineID,
        "requiresPro": false,
        "configured": row.configured,
        "isDownloaded": row.configured,
        "size": 0,
        "formattedSize": "Cloud",
        "environmentVariable": cloud.provider.environmentVariable,
        "supportsSteps": cloud.supportsSteps,
        "supportsGuidance": cloud.supportsGuidance,
        "supportsSeed": cloud.supportsSeed,
        "supportsNegativePrompt": cloud.supportsNegativePrompt,
        "pricingHint": cloud.pricingHint,
        "maxReferenceImages": cloud.maxReferenceImages,
      ]
      if let source = row.source { entry["keySource"] = source }
      jsonModels.append(entry)
    }

    let data = try JSONSerialization.data(
      withJSONObject: jsonModels,
      options: [.prettyPrinted, .sortedKeys]
    )
    if let jsonString = String(data: data, encoding: .utf8) {
      print(jsonString)
    }
  }

  private func printTable(local: [VinetasModelInfo], cloud: [CloudRow]) {
    let header = "%-40@  %-14@  %-24@  %@"
    print(String(format: header, "Name", "Size", "Downloaded", "Status"))
    print(String(repeating: "-", count: 86))

    for info in local {
      let dateStr: String
      if let date = info.downloadDate {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        dateStr = fmt.string(from: date)
      } else {
        dateStr = "-"
      }
      let status = info.isDownloaded ? "cached" : "not downloaded"
      print(
        String(
          format: "%-40@  %-14@  %-24@  %@",
          info.name, info.formattedSize, dateStr, status))
    }

    guard !cloud.isEmpty else { return }
    print("")
    print("Cloud models (your own API key; billed by the vendor, never Pro-gated)")
    let cloudHeader = "%-34@  %-18@  %-30@  %@"
    print(String(format: cloudHeader, "Model", "Vendor", "API key", "Configure with"))
    print(String(repeating: "-", count: 104))
    for row in cloud {
      let key = row.configured ? "configured (\(row.source ?? "configured"))" : "no key"
      print(
        String(
          format: cloudHeader,
          row.model.id, row.model.provider.displayName, key,
          row.model.provider.environmentVariable))
    }
  }
}

// MARK: - Info: display detailed model information

public struct Info: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Display detailed information about a model variant."
  )

  public init() {}

  @Option(
    name: .shortAndLong,
    help: "Model: klein4b, pixart-sigma, or a cloud model id (see `vinetas list`)."
  )
  public var model: String = "klein4b"

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Print the absolute path of the CLI's I/O staging directory and exit.",
      discussion: """
        Resolves `<App Group container>/vinetas-io/` — a sibling of Acervo's
        `SharedModels` cache inside the same App Group container, not the
        models directory itself — creates it if it doesn't already exist, and
        prints only that absolute path to stdout. The rest of `info`'s output
        is skipped.

        The signed CLI has no Downloads-folder entitlement, so this directory
        is the sandbox-safe place to stage reference images and generated
        panels when a stream (`-r -` / `-o -`) isn't a better fit. See
        README.md § "Reference images and streams".
        """
    )
  )
  public var printIODir: Bool = false

  public func run() async throws {
    if printIODir {
      print(try Self.resolveIODirectory().path)
      return
    }

    guard let cliModel = CLIModel.resolve(model) else {
      throw CLIModel.unknownModelError(model)
    }
    if let cloud = cliModel.cloud {
      await printCloudInfo(cloud)
      return
    }
    let vinetasModel = cliModel.local ?? .klein4b

    print("Model:              \(vinetasModel.rawValue)")
    print("HuggingFace Repo:   \(vinetasModel.repoId)")
    print("Quantization:       \(vinetasModel.quantization)")
    print("Min. Memory (GB):   \(vinetasModel.minimumMemoryGB) GB")

    // Show cache status
    let allModels = await CLIEnvironment.client.listModels()
    if let info = allModels.first(where: { $0.name == vinetasModel.descriptor.displayName }) {
      let cacheStatus =
        info.isDownloaded
        ? "Downloaded (\(info.formattedSize))"
        : "Not downloaded"
      print("Cache Status:       \(cacheStatus)")
    }
  }

  /// `info` for a cloud model: vendor, capability flags, price hint, and key
  /// status. Never prints a key or any prefix of one.
  private func printCloudInfo(_ cloud: CloudModelDescriptor) async {
    func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
    let status = await cloudKeyStatus(for: cloud, client: CLIEnvironment.client)
    print("Model:              \(cloud.id)")
    print("Display name:       \(cloud.displayName)")
    print("Vendor:             \(cloud.provider.displayName)")
    print("Vendor model:       \(cloud.vendorModelID)")
    print("Engine:             \(cloud.engineID)")
    print(
      "Supports:           steps \(yesNo(cloud.supportsSteps)) · guidance \(yesNo(cloud.supportsGuidance)) · "
        + "seed \(yesNo(cloud.supportsSeed)) · negative prompt \(yesNo(cloud.supportsNegativePrompt))"
    )
    print(
      "Aspect ratios:      \(cloud.supportedAspectRatios.map(\.rawValue).joined(separator: ", "))")
    print("Price hint:         \(cloud.pricingHint) (billed by the vendor; not Pro-gated)")
    if status.configured {
      print("API key:            configured — \(status.source ?? "configured")")
    } else {
      print(
        "API key:            not configured — set \(cloud.provider.environmentVariable) "
          + "or add it in Vinetas → Settings → Cloud Engines")
    }
    print("Get a key:          \(cloud.provider.consoleURL.absoluteString)")
    print("Terms:              \(cloud.provider.termsURL.absoluteString)")
  }

  /// The name of the CLI's staging subdirectory, a sibling of Acervo's
  /// `SharedModels` cache inside the App Group container.
  static let ioDirectoryName = "vinetas-io"

  /// Resolves and creates `<App Group container>/vinetas-io/`.
  ///
  /// `Acervo.resolvedSharedModelsDirectory` (when configured) is the
  /// container's `SharedModels` subdirectory
  /// (`Acervo+PathResolution.swift:153, 249-251`); this walks up one level to
  /// the container **root** — the directory the App Group itself resolves
  /// to — so `vinetas-io` sits alongside `SharedModels` rather than inside
  /// it. Factored out from `run()` so tests can assert on the computed path
  /// without touching stdio.
  ///
  /// - Throws: `ValidationError` if no App Group / override is configured
  ///   (see `Acervo.environmentHelp()`), or any `FileManager` directory
  ///   creation error.
  static func resolveIODirectory(fileManager: FileManager = .default) throws -> URL {
    guard let sharedModelsDirectory = Acervo.resolvedSharedModelsDirectory else {
      throw ValidationError(
        "Could not resolve the App Group container. Configure ACERVO_APP_GROUP_ID "
          + "or ACERVO_MODELS_DIR — see `vinetas --help` for details."
      )
    }
    let containerRoot = sharedModelsDirectory.deletingLastPathComponent()
    let ioDirectory = containerRoot.appendingPathComponent(ioDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: ioDirectory, withIntermediateDirectories: true)
    return ioDirectory
  }
}

// MARK: - Preview: fast low-quality generation

public struct Preview: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Generate a fast low-quality preview at 512x512 (4 steps, Klein 4B)."
  )

  public init() {}

  @Argument(help: "Text description of the panel to preview.")
  public var prompt: String

  @Option(name: .shortAndLong, help: "Output file path.")
  public var output: String = "preview.png"

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Write a JSONL trace of every library handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
      discussion: """
        Preview always routes through Flux2 Klein 4B, so the trace contains:
          SwiftVinetas    — engine routing, memory verdict, model lifecycle.
          flux-2-swift-mlx — pipeline lifecycle, weight load, quantization,
                             text encode, scheduler, per-step denoise, VAE decode.

        SwiftTuberia and SwiftAcervo do not currently emit on the Flux2 path
        (Flux2 has its own pipeline + uses a static Acervo seam without a
         reporter), so kind:tuberia / kind:acervo events do not appear here.

        The trace records `mode: "preview"` on the generationStart event.
        The trace path is printed to stderr after the run completes.
        See docs/TELEMETRY.md for the full event catalogue.
        """
    )
  )
  public var telemetry: Bool = false

  public func run() async throws {
    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .full) : nil
    defer { Task { await bootstrap?.finish() } }

    let outputURL = URL(fileURLWithPath: output)

    // Preview is hardwired to Klein 4B, which is a FLUX.2 model — so it is
    // Pro-gated even though it takes no --model.
    try await ProGate.requireAccess(to: VinetasModel.klein4b)

    stderrPrint("[vinetas] Generating preview (Klein 4B, 4 steps, 512x512)...")

    // Download Klein 4B if not cached
    stderrPrint("[vinetas] Checking model cache...")
    try await Vinetas.download(model: .klein4b) { progress in
      stderrPrint(
        "[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
    }

    let image = try await Vinetas.preview(prompt: prompt)
    try ImageOutput.writePNG(image: image, to: outputURL)

    stderrPrint("[vinetas] Preview written to \(outputURL.path)")
  }
}

// MARK: - Character Command Group

public struct CharacterCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "character",
    abstract: "Manage characters for consistent actor rendering across panels.",
    subcommands: [
      Create.self,
      ListCharacters.self,
      CharacterInfo.self,
      Delete.self,
      Reference.self,
      Prepare.self,
      Train.self,
      Verify.self,
    ]
  )

  public init() {}

  // MARK: - character create

  public struct Create: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Create a new character with optional source photo."
    )

    public init() {}

    @Argument(help: "Human-readable character name (e.g., 'Detective Vale').")
    public var name: String

    @Option(name: .long, help: "Path to a source photograph (JPEG, PNG, HEIC).")
    public var photo: String?

    @Option(name: .long, help: "Plain-text description of the character's appearance.")
    public var description: String = ""

    public func run() async throws {
      var sourceImage: CGImage?
      if let photoPath = photo {
        guard let image = loadCGImage(from: photoPath) else {
          throw ValidationError("Could not load image from '\(photoPath)'.")
        }
        sourceImage = image
      }

      let character = try Vinetas.createCharacter(
        name: name,
        photo: sourceImage,
        description: description
      )

      print("Character created:")
      print("  Name:         \(character.name)")
      print("  Slug:         \(character.slug)")
      print("  Trigger word: \(character.triggerWord)")
      if !character.sourcePhotos.isEmpty {
        print("  Source photo:  \(character.sourcePhotos.first ?? "-")")
      }
      if !character.description.isEmpty {
        print("  Description:  \(character.description)")
      }
    }
  }

  // MARK: - character list

  public struct ListCharacters: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List all characters."
    )

    public init() {}

    public func run() async throws {
      let characters = try Vinetas.listCharacters()

      if characters.isEmpty {
        print("No characters found.")
        return
      }

      let header = "%-24s  %-24s  %-10s  %s"
      print(String(format: header, "Name", "Slug", "Has LoRA", "Created"))
      print(String(repeating: "-", count: 72))

      let dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .medium
      dateFormatter.timeStyle = .none

      for character in characters {
        let hasLora = character.lora != nil ? "yes" : "no"
        let created = dateFormatter.string(from: character.created)
        print(
          String(
            format: "%-24@  %-24@  %-10@  %@",
            String(character.name.prefix(24)),
            String(character.slug.prefix(24)),
            hasLora,
            created))
      }
    }
  }

  // MARK: - character info

  public struct CharacterInfo: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      commandName: "info",
      abstract: "Display detailed information about a character."
    )

    public init() {}

    @Argument(help: "The character's slug identifier (e.g., 'detective-vale').")
    public var slug: String

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)

      let dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .medium
      dateFormatter.timeStyle = .short

      print("Name:           \(character.name)")
      print("Slug:           \(character.slug)")
      print("Trigger word:   \(character.triggerWord)")
      print("Created:        \(dateFormatter.string(from: character.created))")
      print("Description:    \(character.description.isEmpty ? "-" : character.description)")

      if character.sourcePhotos.isEmpty {
        print("Source photos:  none")
      } else {
        print("Source photos:")
        for photo in character.sourcePhotos {
          print("  - \(photo)")
        }
      }

      if let lora = character.lora {
        print("LoRA:")
        print("  Path:     \(lora.path)")
        print("  Scale:    \(lora.scale)")
        print("  Version:  \(lora.version)")
        if let steps = lora.trainingSteps {
          print("  Steps:    \(steps)")
        }
        if !lora.compatibleEngines.isEmpty {
          print("  Engines:  \(lora.compatibleEngines.joined(separator: ", "))")
        }
        if let trainedAt = lora.trainedAt {
          print("  Trained:  \(dateFormatter.string(from: trainedAt))")
        }
      } else {
        print("LoRA:           none")
      }
    }
  }

  // MARK: - character delete

  public struct Delete: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Delete a character and all its data."
    )

    public init() {}

    @Argument(help: "The character's slug identifier.")
    public var slug: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt.")
    public var force: Bool = false

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)

      if !force {
        stderrPrint("Delete character '\(character.name)' (\(slug))? This cannot be undone.")
        stderrPrint("Type 'yes' to confirm: ")
        guard let response = readLine(), response.lowercased() == "yes" else {
          print("Aborted.")
          return
        }
      }

      let manager = CharacterManager()
      try manager.deleteCharacter(slug: slug)
      print("Character '\(character.name)' deleted.")
    }
  }

  // MARK: - character reference

  public struct Reference: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Generate pencil-sketch reference sheets from a character's source photo."
    )

    public init() {}

    @Argument(help: "The character's slug identifier.")
    public var slug: String

    @Option(name: .long, help: "Comma-separated views to generate: front,left,right,back.")
    public var views: String = "front,left,right,back"

    @Option(
      name: .long,
      help: ArgumentHelp(
        "Deprecated: img2img deviation strength. FLUX.2 reference conditioning has no "
          + "strength control, so this has no effect and will be removed in the next minor release."
      )
    )
    public var strength: Float?

    @Option(name: .long, help: "Model variant: klein4b (default).")
    public var model: String = "klein4b"

    public func run() async throws {
      if let cloud = CLIModel.resolve(model)?.cloud {
        throw ValidationError(
          "'\(cloud.id)' is a cloud model; reference sheets use FLUX.2 reference conditioning, "
            + "which runs on-device only. Use --model klein4b.")
      }
      guard let vinetasModel = VinetasModel(rawValue: model) else {
        throw ValidationError("Unknown model '\(model)'. Valid: klein4b")
      }

      if strength != nil {
        stderrPrint(
          "warning: --strength has no effect and will be removed in the next minor release")
      }

      try await ProGate.requireAccess(to: vinetasModel)

      // Resolve the engine and validate the reference count (character
      // reference sheets always pass exactly one) BEFORE any download or
      // model load (RI-5, RI-8): `--model pixart-sigma` fails here, since
      // PixArt accepts no reference images.
      let descriptor = vinetasModel.descriptor
      let engine = try await CLIEnvironment.client.router.engine(for: descriptor)
      try ReferenceValidator.validate(referenceCount: 1, engine: engine, model: descriptor)

      let character = try Vinetas.loadCharacter(slug: slug)

      let viewNames = views.split(separator: ",").map {
        String($0).trimmingCharacters(in: .whitespaces)
      }
      var referenceViews: [ReferenceView] = []
      for name in viewNames {
        guard let view = ReferenceView(rawValue: name) else {
          let valid = ReferenceView.allCases.map(\.rawValue).joined(separator: ", ")
          throw ValidationError("Unknown view '\(name)'. Valid views: \(valid)")
        }
        referenceViews.append(view)
      }

      stderrPrint("[vinetas] Generating reference sheets for '\(character.name)'...")
      stderrPrint("[vinetas] Views: \(referenceViews.map(\.rawValue).joined(separator: ", "))")
      stderrPrint("[vinetas] Model: \(vinetasModel.rawValue)")

      // Download model if not cached
      if !CLIEnvironment.skipDownload {
        stderrPrint("[vinetas] Checking model cache...")
        try await CLIEnvironment.downloadModel(vinetasModel) { progress in
          stderrPrint(
            "[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
        }
      }

      // `strength` is not forwarded: FLUX.2 reference conditioning has no
      // strength control (the library's `strength:` overload ignores it).
      let images = try await CLIEnvironment.client.generateReferenceSheets(
        for: character,
        views: referenceViews,
        model: descriptor,
        progress: { current, total in
          stderrPrint("[vinetas] Reference \(current)/\(total)...")
        }
      )

      print("Generated \(images.count) reference sheet(s) for '\(character.name)'.")
    }
  }

  // MARK: - character prepare

  public struct Prepare: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Prepare training data from reference sheets."
    )

    public init() {}

    @Argument(help: "The character's slug identifier.")
    public var slug: String

    @Flag(name: .long, help: "Include source photos in addition to reference sheets.")
    public var includeSource: Bool = false

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)

      stderrPrint("[vinetas] Preparing training data for '\(character.name)'...")

      let pairs = try Vinetas.prepareTrainingData(
        for: character,
        includeSourcePhotos: includeSource
      )

      print("Prepared \(pairs.count) training pair(s) for '\(character.name)'.")
      for pair in pairs {
        let imageName = URL(fileURLWithPath: pair.imagePath).lastPathComponent
        let captionName = URL(fileURLWithPath: pair.captionPath).lastPathComponent
        print("  - \(imageName) + \(captionName)")
      }
    }
  }

  // MARK: - character train

  public struct Train: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Train a LoRA adapter for a character."
    )

    public init() {}

    @Argument(help: "The character's slug identifier.")
    public var slug: String

    @Option(name: .long, help: "Number of training steps.")
    public var steps: Int = 1500

    @Option(name: .long, help: "LoRA rank (8-64).")
    public var rank: Int = 48

    @Option(name: .long, help: "Model variant: klein4b (default).")
    public var model: String = "klein4b"

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)
      if let cloud = CLIModel.resolve(model)?.cloud {
        throw ValidationError(
          "'\(cloud.id)' is a cloud model; LoRA training runs on-device only. Use --model klein4b.")
      }
      let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b
      try await ProGate.requireAccess(to: vinetasModel)
      let config = TrainingConfig(rank: rank, steps: steps)

      stderrPrint("[vinetas] Training LoRA for '\(character.name)'...")
      stderrPrint("[vinetas] Steps: \(steps), Rank: \(rank), Model: \(vinetasModel.rawValue)")

      // Download model if not cached
      stderrPrint("[vinetas] Checking model cache...")
      try await Vinetas.download(model: vinetasModel) { progress in
        stderrPrint(
          "[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
      }

      let outputURL = try await Vinetas.trainCharacterLoRA(
        for: character,
        config: config,
        model: vinetasModel,
        progress: { currentStep, totalSteps, loss in
          stderrPrint(
            "[vinetas] Step \(currentStep)/\(totalSteps) — loss: \(String(format: "%.4f", loss))")
        }
      )

      print("LoRA trained: \(outputURL.path)")
    }
  }

  // MARK: - character verify

  public struct Verify: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Verify character consistency via DINOv2 similarity scoring."
    )

    public init() {}

    @Argument(help: "The character's slug identifier.")
    public var slug: String

    @Option(name: .long, help: "Minimum cosine similarity threshold (default: 0.6).")
    public var threshold: Float = 0.6

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)

      stderrPrint("[vinetas] Verifying character '\(character.name)'...")
      stderrPrint("[vinetas] Threshold: \(threshold)")

      let report = try await Vinetas.verifyCharacter(character, threshold: threshold)

      print("Character verification: \(report.passed ? "PASSED" : "FAILED")")
      print("Threshold:              \(String(format: "%.2f", report.threshold))")
      print("Average similarity:     \(String(format: "%.4f", report.averageSimilarity))")
      print("")

      let header = "%-12@  %-12@  %@"
      print(String(format: header, "View 1", "View 2", "Similarity"))
      print(String(repeating: "-", count: 40))

      for pair in report.pairs {
        let status = pair.similarity >= report.threshold ? "" : " < threshold"
        print(
          String(
            format: "%-12@  %-12@  %.4f%@",
            pair.view1, pair.view2,
            pair.similarity, status))
      }
    }
  }
}

// MARK: - Classify: ViT-B/16 image classification

public struct Classify: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "classify",
    abstract: "Classify an image using ViT-B/16 (ImageNet-1K)."
  )

  public init() {}

  @Argument(help: "Path to the image file to classify.")
  public var imagePath: String

  @Option(name: .long, help: "Number of top predictions to display.")
  public var topK: Int = 5

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Write a JSONL trace of every SwiftVinetas image-understanding handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
      discussion: """
        Image-understanding subcommands wire the SwiftVinetas adapter and (since
        SwiftAcervo 0.17) the Acervo adapter, since the ViT-B/16 classifier
        weights are downloaded on first use via Acervo.ensureComponentReady.
        The flux2/pixart/tuberia adapters are intentionally not installed
        because no diffusion happens (REQUIREMENTS §7.7).

        Captures:
          - SwiftVinetas:  classifierForwardStart / classifierForwardComplete
                           errorThrown (phase: .classifierForward) on failure
          - SwiftAcervo:   componentResolveStart / componentResolveComplete
                           inFlightDownloadRegistered / inFlightDownloadCleared
                           cacheHit / downloadStart / downloadComplete
                           (only the first run downloads; cached runs emit
                            cacheHit or componentResolveComplete(.alreadyReady))

        The trace path is printed to stderr after the run completes.
        See docs/TELEMETRY.md for the full event catalogue.
        """
    )
  )
  public var telemetry: Bool = false

  public func run() async throws {
    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .partial) : nil
    defer { Task { await bootstrap?.finish() } }

    let fileURL = URL(fileURLWithPath: imagePath)

    stderrPrint("[vinetas] Classifying image: \(imagePath)")

    let results = try await Vinetas.classify(file: fileURL, topK: topK)

    if results.isEmpty {
      print("No classifications returned.")
      return
    }

    let header = "%-40@  %@"
    print(String(format: header, "Label", "Confidence"))
    print(String(repeating: "-", count: 56))

    for classification in results {
      let confidence = String(format: "%.2f%%", classification.confidence * 100)
      print(
        String(
          format: "%-40@  %@",
          String(classification.label.prefix(40)),
          confidence))
    }
  }
}

// MARK: - Features: DINOv2 feature extraction

public struct Features: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "features",
    abstract: "Extract DINOv2-B/14 feature vector from an image."
  )

  public init() {}

  @Argument(help: "Path to the image file.")
  public var imagePath: String

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Write a JSONL trace of every SwiftVinetas image-understanding handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
      discussion: """
        Image-understanding subcommands wire the SwiftVinetas adapter and (since
        SwiftAcervo 0.17) the Acervo adapter, since the DINOv2-B/14 backbone
        weights are downloaded on first use via Acervo.ensureComponentReady.
        The flux2/pixart/tuberia adapters are intentionally not installed
        because no diffusion happens (REQUIREMENTS §7.7).

        Captures:
          - SwiftVinetas:  featureExtractionStart / featureExtractionComplete
                           (with one TuberiaTensorStat summary of the vector)
                           errorThrown (phase: .featureExtraction) on failure
          - SwiftAcervo:   componentResolveStart / componentResolveComplete
                           inFlightDownloadRegistered / inFlightDownloadCleared
                           cacheHit / downloadStart / downloadComplete
                           (only the first run downloads; cached runs emit
                            cacheHit or componentResolveComplete(.alreadyReady))

        The trace path is printed to stderr after the run completes.
        See docs/TELEMETRY.md for the full event catalogue.
        """
    )
  )
  public var telemetry: Bool = false

  public func run() async throws {
    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .partial) : nil
    defer { Task { await bootstrap?.finish() } }

    let fileURL = URL(fileURLWithPath: imagePath)

    stderrPrint("[vinetas] Extracting features: \(imagePath)")

    let features = try await Vinetas.extractFeatures(from: fileURL)

    print("Feature vector dimensions: \(features.count)")
    let previewCount = min(10, features.count)
    let previewValues = features.prefix(previewCount).map { String(format: "%.6f", $0) }.joined(
      separator: ", ")
    print("First \(previewCount) values: [\(previewValues)]")

    // Summary statistics
    let minVal = features.min() ?? 0
    let maxVal = features.max() ?? 0
    let mean = features.reduce(0, +) / Float(features.count)
    print("Min: \(String(format: "%.6f", minVal))")
    print("Max: \(String(format: "%.6f", maxVal))")
    print("Mean: \(String(format: "%.6f", mean))")
  }
}

// MARK: - Similarity: DINOv2 cosine similarity between two images

public struct Similarity: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: "similarity",
    abstract: "Compute DINOv2 cosine similarity between two images."
  )

  public init() {}

  @Argument(help: "Path to the first image.")
  public var image1Path: String

  @Argument(help: "Path to the second image.")
  public var image2Path: String

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Write a JSONL trace of every SwiftVinetas image-understanding handoff to ~/Library/Caches/vinetas/telemetry/<timestamp>.jsonl",
      discussion: """
        Image-understanding subcommands wire the SwiftVinetas adapter and (since
        SwiftAcervo 0.17) the Acervo adapter, since the DINOv2-B/14 backbone
        weights are downloaded on first use via Acervo.ensureComponentReady.
        The flux2/pixart/tuberia adapters are intentionally not installed
        because no diffusion happens (REQUIREMENTS §7.7).

        Captures one featureExtractionStart / featureExtractionComplete pair
        per input image, plus errorThrown on failure. On a cold cache, also
        captures the SwiftAcervo download events (componentResolveStart/Complete,
        inFlightDownloadRegistered/Cleared, cacheHit, downloadStart/Complete).

        The trace path is printed to stderr after the run completes.
        See docs/TELEMETRY.md for the full event catalogue.
        """
    )
  )
  public var telemetry: Bool = false

  public func run() async throws {
    let bootstrap: CLITelemetryBootstrap? =
      telemetry ? try await CLITelemetryBootstrap.enable(mode: .partial) : nil
    defer { Task { await bootstrap?.finish() } }

    guard let image1 = loadCGImage(from: image1Path) else {
      throw ValidationError("Could not load image from '\(image1Path)'.")
    }
    guard let image2 = loadCGImage(from: image2Path) else {
      throw ValidationError("Could not load image from '\(image2Path)'.")
    }

    stderrPrint("[vinetas] Computing similarity between:")
    stderrPrint("[vinetas]   \(image1Path)")
    stderrPrint("[vinetas]   \(image2Path)")

    let score = try await Vinetas.similarity(between: image1, and: image2)

    print("Cosine similarity: \(String(format: "%.6f", score))")

    if score >= 0.8 {
      print("Interpretation: Very similar (likely same subject)")
    } else if score >= 0.6 {
      print("Interpretation: Similar (possibly same subject, different angle)")
    } else if score >= 0.4 {
      print("Interpretation: Somewhat similar")
    } else {
      print("Interpretation: Different subjects")
    }
  }
}

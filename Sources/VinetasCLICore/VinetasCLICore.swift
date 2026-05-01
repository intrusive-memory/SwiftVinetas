// VinetasCLICore is built on top of the deprecated `Vinetas` namespace and
// `.klein4b`/`.klein9b` enum cases, both of which are gated out while FLUX.2
// is disabled. Re-enable instructions: docs/incomplete/FLUX2_REENABLE.md
#if !VINETAS_FLUX2_DISABLED
import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import SwiftVinetas

// MARK: - Helpers

func stderrPrint(_ message: String) {
  let data = (message + "\n").data(using: .utf8) ?? Data()
  FileHandle.standardError.write(data)
}

/// Load a CGImage from a file path using ImageIO.
func loadCGImage(from path: String) -> CGImage? {
  let url = URL(fileURLWithPath: path)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - Generate a single panel

public struct Generate: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Generate a single panel from a text prompt."
  )

  public init() {}

  @Argument(help: "Text description of the panel to generate.")
  public var prompt: String

  @Option(name: .shortAndLong, help: "Style prompt for consistent look (e.g., 'noir comic').")
  public var style: String?

  @Option(name: .shortAndLong, help: "Output file path.")
  public var output: String = "panel.png"

  @Option(name: .long, help: "Model variant: klein4b (default, fast) or klein9b (quality).")
  public var model: String = "klein4b"

  @Option(name: .long, help: "Path to a LoRA safetensors file.")
  public var lora: String?

  @Option(name: .long, help: "LoRA scale (0.0-1.0).")
  public var loraScale: Float = 0.8

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

  public func run() async throws {
    let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b

    // Build StyleConfig from CLI options
    var styleConfig = StyleConfig()
    if let stylePrompt = style { styleConfig.stylePrompt = stylePrompt }
    if let negative { styleConfig.negativePrompt = negative }
    if let steps { styleConfig.steps = steps }
    if let guidance { styleConfig.guidanceScale = guidance }
    if let seed { styleConfig.seed = seed }

    // Apply aspect ratio preset (explicit --width/--height take precedence)
    if let aspectName = aspect {
      guard let ratio = AspectRatio(rawValue: aspectName) else {
        let validValues = AspectRatio.allCases.map(\.rawValue).joined(separator: ", ")
        throw ValidationError("Unknown aspect ratio '\(aspectName)'. Valid values: \(validValues)")
      }
      styleConfig.width = ratio.width
      styleConfig.height = ratio.height
    }
    if let width { styleConfig.width = width }
    if let height { styleConfig.height = height }

    if let lora { styleConfig.loraPath = lora }
    styleConfig.loraScale = loraScale

    // Override everything for preview mode
    if preview {
      styleConfig.steps = 4
      styleConfig.width = 512
      styleConfig.height = 512
    }

    let outputURL = URL(fileURLWithPath: output)

    stderrPrint("[vinetas] Generating panel...")
    stderrPrint("[vinetas] Model: \(vinetasModel.rawValue)")
    stderrPrint("[vinetas] Dimensions: \(styleConfig.width)x\(styleConfig.height)")
    stderrPrint("[vinetas] Steps: \(styleConfig.steps)")

    // Download model if not already cached (zero-config first run)
    stderrPrint("[vinetas] Checking model cache...")
    try await Vinetas.download(model: vinetasModel) { progress in
      stderrPrint(
        "[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
    }

    let image: CGImage
    if preview {
      image = try await Vinetas.preview(prompt: prompt)
    } else {
      image = try await Vinetas.generate(prompt: prompt, style: styleConfig, model: vinetasModel)
    }

    try ImageOutput.writePNG(image: image, to: outputURL)

    // Write metadata sidecar
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]
    let meta = ImageOutput.PanelMetadata(
      prompt: prompt,
      model: vinetasModel.rawValue,
      seed: styleConfig.seed ?? 0,
      steps: styleConfig.steps,
      guidance: styleConfig.guidanceScale,
      width: styleConfig.width,
      height: styleConfig.height,
      durationSeconds: 0,
      loras: styleConfig.loraPath.map {
        [ImageOutput.LoRAEntry(path: $0, scale: styleConfig.loraScale ?? 1.0)]
      },
      generatedAt: isoFormatter.string(from: Date())
    )
    let sidecarURL = outputURL.deletingPathExtension().appendingPathExtension("json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let metaData = try encoder.encode(meta)
    try metaData.write(to: sidecarURL, options: .atomic)

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

  @Option(name: .long, help: "Model variant: klein4b (default) or klein9b.")
  public var model: String = "klein4b"

  @Option(
    name: .long, help: "Aspect ratio preset: square, wide, ultrawide, portrait, panel, strip.")
  public var aspect: String?

  @Flag(name: .long, help: "Fast preview mode (reduced quality and resolution).")
  public var preview: Bool = false

  public func run() async throws {
    let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b
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
    stderrPrint("[vinetas] Model: \(vinetasModel.rawValue)")
    if let aspectName = aspect, let ratio = AspectRatio(rawValue: aspectName) {
      stderrPrint("[vinetas] Aspect ratio: \(aspectName) (\(ratio.width)x\(ratio.height))")
    }

    // Download model if not cached (zero-config first run)
    stderrPrint("[vinetas] Checking model cache...")
    try await Vinetas.download(model: vinetasModel) { progress in
      stderrPrint(
        "[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
    }

    let outputs = try await Vinetas.generateFromFile(
      promptURL,
      model: vinetasModel,
      progress: { current, total in
        stderrPrint("[vinetas] Panel \(current)/\(total)...")
      },
      stepProgress: { currentStep, totalSteps, elapsed in
        stderrPrint(
          "[vinetas] Step \(currentStep)/\(totalSteps), elapsed: \(String(format: "%.1f", elapsed))s"
        )
      }
    )

    for (index, output) in outputs.enumerated() {
      let panelNumber = index + 1
      let filename = String(format: "panel-%03d.png", panelNumber)
      let panelURL = outputDirURL.appendingPathComponent(filename)
      let style = StyleConfig(width: output.width, height: output.height)
      try ImageOutput.writePanel(output, to: panelURL, style: style)
      stderrPrint("[vinetas] Wrote \(filename) (seed: \(output.seed))")
    }

    stderrPrint(
      "[vinetas] Batch complete. \(outputs.count) panel(s) written to \(outputDirURL.path)")
  }
}

// MARK: - Download models

public struct Download: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Download a FLUX.2 model for local generation."
  )

  public init() {}

  @Option(name: .shortAndLong, help: "Model to download: klein4b or klein9b.")
  public var model: String = "klein4b"

  public func run() async throws {
    let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b

    stderrPrint("[vinetas] Downloading model: \(vinetasModel.rawValue)")
    stderrPrint("[vinetas] Repo: \(vinetasModel.huggingFaceRepo)")

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
    abstract: "List downloaded models and their cache status."
  )

  public init() {}

  @Flag(name: .long, help: "Output model information as JSON.")
  public var json: Bool = false

  public func run() async throws {
    let models = await Vinetas.listModels()

    if json {
      let isoFormatter = ISO8601DateFormatter()
      isoFormatter.formatOptions = [.withInternetDateTime]

      let jsonModels: [[String: Any]] = models.map { info in
        var entry: [String: Any] = [
          "name": info.name,
          "size": info.size,
          "formattedSize": info.formattedSize,
          "isDownloaded": info.isDownloaded,
        ]
        if let date = info.downloadDate {
          entry["downloadDate"] = isoFormatter.string(from: date)
        }
        return entry
      }
      let data = try JSONSerialization.data(
        withJSONObject: jsonModels,
        options: [.prettyPrinted, .sortedKeys]
      )
      if let jsonString = String(data: data, encoding: .utf8) {
        print(jsonString)
      }
      return
    }

    let header = "%-40@  %-14@  %-24@  %@"
    print(String(format: header, "Name", "Size", "Downloaded", "Status"))
    print(String(repeating: "-", count: 86))

    for info in models {
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
  }
}

// MARK: - Info: display detailed model information

public struct Info: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "Display detailed information about a FLUX.2 model variant."
  )

  public init() {}

  @Option(name: .shortAndLong, help: "Model variant: klein4b or klein9b.")
  public var model: String = "klein4b"

  public func run() async throws {
    let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b

    print("Model:              \(vinetasModel.rawValue)")
    print("HuggingFace Repo:   \(vinetasModel.huggingFaceRepo)")
    print("Quantization:       \(vinetasModel.quantization)")
    print("Min. Memory (GB):   \(vinetasModel.minimumMemoryGB) GB")
    print("Est. Time/Image:    ~\(vinetasModel.estimatedSecondsPerImage)s (M3/M4 Pro)")

    // Show cache status
    let allModels = await Vinetas.listModels()
    if let info = allModels.first(where: { $0.name == vinetasModel.huggingFaceRepo }) {
      let cacheStatus =
        info.isDownloaded
        ? "Downloaded (\(info.formattedSize))"
        : "Not downloaded"
      print("Cache Status:       \(cacheStatus)")
    }
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

  public func run() async throws {
    let outputURL = URL(fileURLWithPath: output)

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

    @Option(name: .long, help: "Img2img deviation strength (0.0-1.0).")
    public var strength: Float = 0.65

    @Option(name: .long, help: "Model variant: klein4b (default) or klein9b.")
    public var model: String = "klein4b"

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)
      let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b

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
      stderrPrint("[vinetas] Strength: \(strength)")
      stderrPrint("[vinetas] Model: \(vinetasModel.rawValue)")

      // Download model if not cached
      stderrPrint("[vinetas] Checking model cache...")
      try await Vinetas.download(model: vinetasModel) { progress in
        stderrPrint(
          "[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
      }

      let images = try await Vinetas.generateReferenceSheets(
        for: character,
        views: referenceViews,
        strength: strength,
        model: vinetasModel,
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

    @Option(name: .long, help: "Model variant: klein4b (default) or klein9b.")
    public var model: String = "klein4b"

    public func run() async throws {
      let character = try Vinetas.loadCharacter(slug: slug)
      let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b
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

  public func run() async throws {
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

  public func run() async throws {
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

  public func run() async throws {
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
#endif // !VINETAS_FLUX2_DISABLED

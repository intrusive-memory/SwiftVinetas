import ArgumentParser
import CoreGraphics
import Foundation
import SwiftVinetas

// MARK: - Helpers

private func stderrPrint(_ message: String) {
    let data = (message + "\n").data(using: .utf8) ?? Data()
    FileHandle.standardError.write(data)
}

// MARK: - Root Command

@main
struct VinetasCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vinetas",
        abstract: "Generate storyboard panels and comic art from text prompts using FLUX.2 on Apple Silicon.",
        subcommands: [Generate.self, Batch.self, Download.self, ListModels.self, Info.self, Preview.self],
        defaultSubcommand: Generate.self
    )
}

// MARK: - Generate a single panel

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a single panel from a text prompt."
    )

    @Argument(help: "Text description of the panel to generate.")
    var prompt: String

    @Option(name: .shortAndLong, help: "Style prompt for consistent look (e.g., 'noir comic').")
    var style: String?

    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String = "panel.png"

    @Option(name: .long, help: "Model variant: klein4b (default, fast) or klein9b (quality).")
    var model: String = "klein4b"

    @Option(name: .long, help: "Path to a LoRA safetensors file.")
    var lora: String?

    @Option(name: .long, help: "LoRA scale (0.0-1.0).")
    var loraScale: Float = 0.8

    @Option(name: .long, help: "Random seed for reproducibility.")
    var seed: UInt64?

    @Option(name: .long, help: "Number of inference steps (higher = more detail, slower).")
    var steps: Int?

    @Option(name: .long, help: "Classifier-free guidance scale.")
    var guidance: Float?

    @Option(name: .long, help: "Output image width in pixels.")
    var width: Int?

    @Option(name: .long, help: "Output image height in pixels.")
    var height: Int?

    @Option(name: .long, help: "Negative prompt to steer away from unwanted characteristics.")
    var negative: String?

    @Flag(name: .long, help: "Fast preview mode (4 steps, 512x512, Klein 4B).")
    var preview: Bool = false

    func run() async throws {
        let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b

        // Build StyleConfig from CLI options
        var styleConfig = StyleConfig()
        if let stylePrompt = style { styleConfig.stylePrompt = stylePrompt }
        if let negative { styleConfig.negativePrompt = negative }
        if let steps { styleConfig.steps = steps }
        if let guidance { styleConfig.guidanceScale = guidance }
        if let seed { styleConfig.seed = seed }
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
            stderrPrint("[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
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

struct Batch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a sequence of panels from a YAML prompts file."
    )

    @Argument(help: "Path to a YAML prompt file.")
    var promptsFile: String

    @Option(name: .shortAndLong, help: "Output directory for generated panels.")
    var outputDir: String = "./panels"

    @Option(name: .long, help: "Model variant: klein4b (default) or klein9b.")
    var model: String = "klein4b"

    @Flag(name: .long, help: "Fast preview mode (reduced quality and resolution).")
    var preview: Bool = false

    func run() async throws {
        let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b
        let promptURL = URL(fileURLWithPath: promptsFile)
        let outputDirURL = URL(fileURLWithPath: outputDir)

        // Create output directory if needed
        try FileManager.default.createDirectory(
            at: outputDirURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        stderrPrint("[vinetas] Batch generating from: \(promptsFile)")
        stderrPrint("[vinetas] Output directory: \(outputDirURL.path)")
        stderrPrint("[vinetas] Model: \(vinetasModel.rawValue)")

        // Download model if not cached (zero-config first run)
        stderrPrint("[vinetas] Checking model cache...")
        try await Vinetas.download(model: vinetasModel) { progress in
            stderrPrint("[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
        }

        let outputs = try await Vinetas.generateFromFile(
            promptURL,
            model: vinetasModel,
            progress: { current, total in
                stderrPrint("[vinetas] Panel \(current)/\(total)...")
            },
            stepProgress: { currentStep, totalSteps, elapsed in
                stderrPrint("[vinetas] Step \(currentStep)/\(totalSteps), elapsed: \(String(format: "%.1f", elapsed))s")
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

        stderrPrint("[vinetas] Batch complete. \(outputs.count) panel(s) written to \(outputDirURL.path)")
    }
}

// MARK: - Download models

struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download a FLUX.2 model for local generation."
    )

    @Option(name: .shortAndLong, help: "Model to download: klein4b or klein9b.")
    var model: String = "klein4b"

    func run() async throws {
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

struct ListModels: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List downloaded models and their cache status."
    )

    func run() async throws {
        let models = try Vinetas.listModels()

        let header = "%-40s  %-14s  %-24s  %s"
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
            print(String(format: "%-40s  %-14s  %-24s  %s",
                         info.name, info.formattedSize, dateStr, status))
        }
    }
}

// MARK: - Info: display detailed model information

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display detailed information about a FLUX.2 model variant."
    )

    @Option(name: .shortAndLong, help: "Model variant: klein4b or klein9b.")
    var model: String = "klein4b"

    func run() async throws {
        let vinetasModel = VinetasModel(rawValue: model) ?? .klein4b

        print("Model:              \(vinetasModel.rawValue)")
        print("HuggingFace Repo:   \(vinetasModel.huggingFaceRepo)")
        print("Quantization:       \(vinetasModel.quantization)")
        print("Min. Memory (GB):   \(vinetasModel.minimumMemoryGB) GB")
        print("Est. Time/Image:    ~\(vinetasModel.estimatedSecondsPerImage)s (M3/M4 Pro)")

        // Show cache status
        let allModels = try Vinetas.listModels()
        if let info = allModels.first(where: { $0.name == vinetasModel.huggingFaceRepo }) {
            let cacheStatus = info.isDownloaded
                ? "Downloaded (\(info.formattedSize))"
                : "Not downloaded"
            print("Cache Status:       \(cacheStatus)")
        }
    }
}

// MARK: - Preview: fast low-quality generation

struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a fast low-quality preview at 512x512 (4 steps, Klein 4B)."
    )

    @Argument(help: "Text description of the panel to preview.")
    var prompt: String

    @Option(name: .shortAndLong, help: "Output file path.")
    var output: String = "preview.png"

    func run() async throws {
        let outputURL = URL(fileURLWithPath: output)

        stderrPrint("[vinetas] Generating preview (Klein 4B, 4 steps, 512x512)...")

        // Download Klein 4B if not cached
        stderrPrint("[vinetas] Checking model cache...")
        try await Vinetas.download(model: .klein4b) { progress in
            stderrPrint("[vinetas] Downloading: \(String(format: "%.1f", progress.overallProgress * 100))%")
        }

        let image = try await Vinetas.preview(prompt: prompt)
        try ImageOutput.writePNG(image: image, to: outputURL)

        stderrPrint("[vinetas] Preview written to \(outputURL.path)")
    }
}

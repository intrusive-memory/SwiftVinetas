import ArgumentParser
import Foundation
import SwiftVinetas

@main
struct VinetasCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vinetas",
        abstract: "Generate storyboard panels and comic art from text prompts using FLUX.2 on Apple Silicon.",
        subcommands: [Generate.self, Batch.self, Download.self, ListModels.self],
        defaultSubcommand: Generate.self
    )
}

// MARK: - Generate a single panel

struct Generate: ParsableCommand {
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

    func run() throws {
        print("Generating panel from prompt: \(prompt)")
        print("Model: \(model)")
        print("Output: \(output)")
        // TODO: Call Vinetas.generate() and write to output path
    }
}

// MARK: - Batch generate from a prompts file

struct Batch: ParsableCommand {
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

    func run() throws {
        print("Batch generating from: \(promptsFile)")
        print("Output directory: \(outputDir)")
        // TODO: Read YAML prompt file, call Vinetas.generateFromFile(), write panels
    }
}

// MARK: - Download models

struct Download: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download a FLUX.2 model for local generation."
    )

    @Option(name: .shortAndLong, help: "Model to download: klein4b or klein9b.")
    var model: String = "klein4b"

    func run() throws {
        print("Downloading model: \(model)")
        // TODO: Call Vinetas.download()
    }
}

// MARK: - List cached models

struct ListModels: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List downloaded models."
    )

    func run() throws {
        print("Cached models:")
        // TODO: Call Vinetas.listModels()
    }
}

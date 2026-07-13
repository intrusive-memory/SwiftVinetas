import ArgumentParser
import VinetasCLICore

// MARK: - Root Command

@main
struct VinetasCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "vinetas",
    abstract:
      "Generate storyboard panels and comic art from text prompts using FLUX.2 on Apple Silicon.",
    subcommands: [
      Generate.self,
      Batch.self,
      Storyboard.self,
      Download.self,
      ListModels.self,
      Info.self,
      Preview.self,
      CharacterCommand.self,
      Classify.self,
      Features.self,
      Similarity.self,
    ],
    defaultSubcommand: Generate.self
  )
}

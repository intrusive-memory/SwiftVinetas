import ArgumentParser
import SwiftAcervo
import VinetasCLICore

// MARK: - Root Command

@main
struct VinetasCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "vinetas",
    abstract:
      "Generate storyboard panels and comic art from text prompts using FLUX.2 on Apple Silicon.",
    discussion: """
      vinetas renders panels with FLUX.2 / PixArt on Apple Silicon. Model
      weights are fetched from the CDN on first use and cached in the shared
      App Group container, so every tool in the ecosystem reuses the same
      download.

      \(Acervo.environmentHelp())
      """,
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

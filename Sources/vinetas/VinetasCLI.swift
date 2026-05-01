#if VINETAS_FLUX2_DISABLED
// FLUX.2 is temporarily disabled; the CLI is built on top of the deprecated
// Vinetas namespace and is not available during the disable window.
// See docs/incomplete/FLUX2_REENABLE.md to restore.
import Foundation

@main
enum VinetasCLI {
  static func main() {
    FileHandle.standardError.write(Data(
      "vinetas CLI is unavailable while FLUX.2 is disabled. See docs/incomplete/FLUX2_REENABLE.md\n".utf8
    ))
    exit(1)
  }
}
#else
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
#endif

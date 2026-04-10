// MARK: - Import Strategy
//
// Option B was chosen: A new `VinetasCLICore` library target was created in Package.swift
// containing all CLI command structs (moved from Sources/vinetas/VinetasCLI.swift).
// The `vinetas` executable now depends on `VinetasCLICore` and provides only the @main
// entry point. `SwiftVinetasTests` adds `VinetasCLICore` as a dependency so the command
// types are importable here via `@testable import VinetasCLICore`.
//
// Rationale for rejecting Option A: Swift does NOT support importing .executableTarget
// modules in test targets — @testable import of an executable target will fail at
// compile time regardless of Swift version.
//
// Rationale for rejecting Option C: Option B makes real ArgumentParser struct field
// assertions possible, which gives higher confidence than only testing library types.
//
// No `run()` methods are called in any test below.

import Testing

@testable import VinetasCLICore

// MARK: - Generate subcommand

@Suite("CLI generate subcommand")
struct GenerateArgumentTests {

  @Test("defaults: model is klein4b, output is panel.png, preview is false")
  func generateDefaults() throws {
    let cmd = try Generate.parse(["test prompt"])
    #expect(cmd.model == "klein4b")
    #expect(cmd.output == "panel.png")
    #expect(cmd.preview == false)
  }

  @Test("--model klein9b sets model to klein9b")
  func generateModel() throws {
    let cmd = try Generate.parse(["test prompt", "--model", "klein9b"])
    #expect(cmd.model == "klein9b")
  }

  @Test("--output foo.png sets output to foo.png")
  func generateOutput() throws {
    let cmd = try Generate.parse(["test prompt", "--output", "foo.png"])
    #expect(cmd.output == "foo.png")
  }

  @Test("--seed 42 sets seed to 42")
  func generateSeed() throws {
    let cmd = try Generate.parse(["test prompt", "--seed", "42"])
    #expect(cmd.seed == 42)
  }

  @Test("--steps 20 sets steps to 20")
  func generateSteps() throws {
    let cmd = try Generate.parse(["test prompt", "--steps", "20"])
    #expect(cmd.steps == 20)
  }

  @Test("--aspect square sets aspect to square")
  func generateAspect() throws {
    let cmd = try Generate.parse(["test prompt", "--aspect", "square"])
    #expect(cmd.aspect == "square")
  }

  @Test("--preview flag sets preview to true")
  func generatePreview() throws {
    let cmd = try Generate.parse(["test prompt", "--preview"])
    #expect(cmd.preview == true)
  }
}

// MARK: - Batch subcommand

@Suite("CLI batch subcommand")
struct BatchArgumentTests {

  @Test("positional promptsFile argument is captured")
  func batchPromptsFile() throws {
    let cmd = try Batch.parse(["prompts.yaml"])
    #expect(cmd.promptsFile == "prompts.yaml")
  }

  @Test("--model klein9b sets model to klein9b")
  func batchModel() throws {
    let cmd = try Batch.parse(["prompts.yaml", "--model", "klein9b"])
    #expect(cmd.model == "klein9b")
  }
}

// MARK: - ListModels subcommand

@Suite("CLI list subcommand")
struct ListModelsArgumentTests {

  @Test("list parses with no required arguments")
  func listParsesWithNoArguments() throws {
    let cmd = try ListModels.parse([])
    #expect(cmd.json == false)
  }
}

// MARK: - Preview subcommand

@Suite("CLI preview subcommand")
struct PreviewArgumentTests {

  @Test("positional prompt argument is required and captured")
  func previewPrompt() throws {
    let cmd = try Preview.parse(["a futuristic city"])
    #expect(cmd.prompt == "a futuristic city")
  }

  @Test("--output defaults to preview.png when not provided")
  func previewOutputDefault() throws {
    let cmd = try Preview.parse(["a futuristic city"])
    #expect(cmd.output == "preview.png")
  }
}

// MARK: - CharacterCommand.Create subcommand
//
// Source-verified fields (VinetasCLICore.swift § CharacterCommand.Create):
//   @Argument var name: String
//   @Option(name: .long) var description: String = ""
//   @Option(name: .long) var photo: String?
// There is NO --trigger-word option on Create.

@Suite("CLI character subcommand")
struct CharacterArgumentTests {

  // MARK: Create

  @Test("create: positional name argument captures multi-word value")
  func characterCreateName() throws {
    let cmd = try CharacterCommand.Create.parse(["Detective Vale"])
    #expect(cmd.name == "Detective Vale")
  }

  @Test("create: --description sets description field")
  func characterCreateDescription() throws {
    let cmd = try CharacterCommand.Create.parse([
      "Detective Vale", "--description", "tall detective",
    ])
    #expect(cmd.description == "tall detective")
  }

  @Test("create: description defaults to empty string when not provided")
  func characterCreateDescriptionDefault() throws {
    let cmd = try CharacterCommand.Create.parse(["Detective Vale"])
    #expect(cmd.description == "")
  }

  // MARK: Delete
  //
  // Source-verified fields (VinetasCLICore.swift § CharacterCommand.Delete):
  //   @Argument var slug: String
  //   @Flag(name: .shortAndLong) var force: Bool = false

  @Test("delete: positional slug argument is captured")
  func characterDeleteSlug() throws {
    let cmd = try CharacterCommand.Delete.parse(["detective-vale"])
    #expect(cmd.slug == "detective-vale")
  }

  @Test("delete: --force flag sets force to true")
  func characterDeleteForce() throws {
    let cmd = try CharacterCommand.Delete.parse(["detective-vale", "--force"])
    #expect(cmd.force == true)
  }

  @Test("delete: force defaults to false when not provided")
  func characterDeleteForceDefault() throws {
    let cmd = try CharacterCommand.Delete.parse(["detective-vale"])
    #expect(cmd.force == false)
  }

  // MARK: Train
  //
  // Source-verified fields (VinetasCLICore.swift § CharacterCommand.Train):
  //   @Argument var slug: String
  //   @Option(name: .long) var steps: Int = 1500
  //   @Option(name: .long) var model: String = "klein4b"
  //   @Option(name: .long) var rank: Int = 48

  @Test("train: positional slug argument is captured")
  func characterTrainSlug() throws {
    let cmd = try CharacterCommand.Train.parse(["detective-vale"])
    #expect(cmd.slug == "detective-vale")
  }

  @Test("train: --steps 1500 sets steps to 1500 (matches default)")
  func characterTrainSteps() throws {
    let cmd = try CharacterCommand.Train.parse(["detective-vale", "--steps", "1500"])
    #expect(cmd.steps == 1500)
  }

  @Test("train: steps defaults to 1500 when not provided")
  func characterTrainStepsDefault() throws {
    let cmd = try CharacterCommand.Train.parse(["detective-vale"])
    #expect(cmd.steps == 1500)
  }

  @Test("train: --model klein4b sets model to klein4b")
  func characterTrainModel() throws {
    let cmd = try CharacterCommand.Train.parse(["detective-vale", "--model", "klein4b"])
    #expect(cmd.model == "klein4b")
  }
}

// MARK: - Classify subcommand
//
// Source-verified fields (VinetasCLICore.swift § Classify):
//   @Argument var imagePath: String
//   @Option(name: .long) var topK: Int = 5

@Suite("CLI classify subcommand")
struct ClassifyArgumentTests {

  @Test("positional imagePath argument is captured")
  func classifyImagePath() throws {
    let cmd = try Classify.parse(["/path/to/image.jpg"])
    #expect(cmd.imagePath == "/path/to/image.jpg")
  }

  @Test("--top-k 5 sets topK to 5")
  func classifyTopK() throws {
    let cmd = try Classify.parse(["/path/to/image.jpg", "--top-k", "5"])
    #expect(cmd.topK == 5)
  }

  @Test("topK defaults to 5 when not provided")
  func classifyTopKDefault() throws {
    let cmd = try Classify.parse(["/path/to/image.jpg"])
    #expect(cmd.topK == 5)
  }
}

// MARK: - Similarity subcommand
//
// Source-verified fields (VinetasCLICore.swift § Similarity):
//   @Argument var image1Path: String
//   @Argument var image2Path: String

@Suite("CLI similarity subcommand")
struct SimilarityArgumentTests {

  @Test("two positional image path arguments are captured")
  func similarityBothPaths() throws {
    let cmd = try Similarity.parse(["/path/to/image1.jpg", "/path/to/image2.jpg"])
    #expect(cmd.image1Path == "/path/to/image1.jpg")
    #expect(cmd.image2Path == "/path/to/image2.jpg")
  }

  @Test("image1Path is the first positional argument")
  func similarityImage1Path() throws {
    let cmd = try Similarity.parse(["first.png", "second.png"])
    #expect(cmd.image1Path == "first.png")
  }

  @Test("image2Path is the second positional argument")
  func similarityImage2Path() throws {
    let cmd = try Similarity.parse(["first.png", "second.png"])
    #expect(cmd.image2Path == "second.png")
  }
}

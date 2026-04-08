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

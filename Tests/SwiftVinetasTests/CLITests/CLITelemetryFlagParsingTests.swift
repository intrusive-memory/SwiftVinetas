import ArgumentParser
import Foundation
import Testing

@testable import VinetasCLICore

// MARK: - CLITelemetryFlagParsingTests (Sortie 11a)
//
// Verifies that the six in-scope subcommands (Generate, Batch, Preview, Classify,
// Features, Similarity) expose a `telemetry` Bool flag that:
//  - defaults to false when omitted
//  - becomes true when --telemetry is passed
//
// Also verifies that the out-of-scope subcommands (Download, ListModels, Info, and the
// CharacterCommand subcommands) do NOT have a `telemetry` property by reflecting their
// stored-property labels via Mirror.
//
// Help-text verification: Generate.helpMessage() must contain --telemetry and the
// expected discussion text from REQUIREMENTS §7.1.

@Suite("CLITelemetryFlagParsing")
struct CLITelemetryFlagParsingTests {

  // MARK: - In-scope: Generate

  @Test("Generate defaults telemetry to false")
  func generateTelemetryDefaultsFalse() throws {
    let cmd = try Generate.parse(["a prompt"])
    #expect(cmd.telemetry == false, "Generate.telemetry should default to false")
  }

  @Test("Generate --telemetry sets flag to true")
  func generateTelemetryFlagTrue() throws {
    let cmd = try Generate.parse(["a prompt", "--telemetry"])
    #expect(cmd.telemetry == true, "Generate.telemetry should be true when --telemetry is passed")
  }

  // MARK: - In-scope: Batch

  @Test("Batch defaults telemetry to false")
  func batchTelemetryDefaultsFalse() throws {
    let cmd = try Batch.parse(["prompts.yaml"])
    #expect(cmd.telemetry == false, "Batch.telemetry should default to false")
  }

  @Test("Batch --telemetry sets flag to true")
  func batchTelemetryFlagTrue() throws {
    let cmd = try Batch.parse(["prompts.yaml", "--telemetry"])
    #expect(cmd.telemetry == true, "Batch.telemetry should be true when --telemetry is passed")
  }

  // MARK: - In-scope: Preview

  @Test("Preview defaults telemetry to false")
  func previewTelemetryDefaultsFalse() throws {
    let cmd = try Preview.parse(["a prompt"])
    #expect(cmd.telemetry == false, "Preview.telemetry should default to false")
  }

  @Test("Preview --telemetry sets flag to true")
  func previewTelemetryFlagTrue() throws {
    let cmd = try Preview.parse(["a prompt", "--telemetry"])
    #expect(cmd.telemetry == true, "Preview.telemetry should be true when --telemetry is passed")
  }

  // MARK: - In-scope: Classify

  @Test("Classify defaults telemetry to false")
  func classifyTelemetryDefaultsFalse() throws {
    let cmd = try Classify.parse(["/tmp/image.png"])
    #expect(cmd.telemetry == false, "Classify.telemetry should default to false")
  }

  @Test("Classify --telemetry sets flag to true")
  func classifyTelemetryFlagTrue() throws {
    let cmd = try Classify.parse(["/tmp/image.png", "--telemetry"])
    #expect(cmd.telemetry == true, "Classify.telemetry should be true when --telemetry is passed")
  }

  // MARK: - In-scope: Features

  @Test("Features defaults telemetry to false")
  func featuresTelemetryDefaultsFalse() throws {
    let cmd = try Features.parse(["/tmp/image.png"])
    #expect(cmd.telemetry == false, "Features.telemetry should default to false")
  }

  @Test("Features --telemetry sets flag to true")
  func featuresTelemetryFlagTrue() throws {
    let cmd = try Features.parse(["/tmp/image.png", "--telemetry"])
    #expect(cmd.telemetry == true, "Features.telemetry should be true when --telemetry is passed")
  }

  // MARK: - In-scope: Similarity

  @Test("Similarity defaults telemetry to false")
  func similarityTelemetryDefaultsFalse() throws {
    let cmd = try Similarity.parse(["/tmp/a.png", "/tmp/b.png"])
    #expect(cmd.telemetry == false, "Similarity.telemetry should default to false")
  }

  @Test("Similarity --telemetry sets flag to true")
  func similarityTelemetryFlagTrue() throws {
    let cmd = try Similarity.parse(["/tmp/a.png", "/tmp/b.png", "--telemetry"])
    #expect(cmd.telemetry == true, "Similarity.telemetry should be true when --telemetry is passed")
  }

  // MARK: - Out-of-scope: no telemetry property

  /// Reflects a value type's stored property labels and asserts none is named "telemetry".
  private func assertNoTelemetryProperty<T>(_ value: T, commandName: String) {
    let labels = Mirror(reflecting: value).children.compactMap(\.label)
    #expect(
      !labels.contains("telemetry"),
      "\(commandName) should NOT have a 'telemetry' stored property (out-of-scope per REQUIREMENTS §7.7)"
    )
  }

  @Test("Download does not have a telemetry property")
  func downloadHasNoTelemetryProperty() {
    assertNoTelemetryProperty(Download(), commandName: "Download")
  }

  @Test("ListModels does not have a telemetry property")
  func listModelsHasNoTelemetryProperty() {
    assertNoTelemetryProperty(ListModels(), commandName: "ListModels")
  }

  @Test("Info does not have a telemetry property")
  func infoHasNoTelemetryProperty() {
    assertNoTelemetryProperty(Info(), commandName: "Info")
  }

  @Test("CharacterCommand.Create does not have a telemetry property")
  func characterCreateHasNoTelemetryProperty() {
    assertNoTelemetryProperty(CharacterCommand.Create(), commandName: "CharacterCommand.Create")
  }

  // MARK: - Help text verification

  @Test("Generate help message contains --telemetry flag")
  func generateHelpContainsTelemetryFlag() {
    let help = Generate.helpMessage()
    #expect(
      help.contains("--telemetry"),
      "Generate help message must mention --telemetry flag; got:\n\(help)"
    )
  }

  @Test("Generate help message contains telemetry discussion from REQUIREMENTS §7.1")
  func generateHelpContainsTelemetryDiscussion() {
    let help = Generate.helpMessage()
    // REQUIREMENTS §7.1 specifies the discussion text must mention all five libraries.
    #expect(
      help.contains("SwiftVinetas"),
      "Generate help discussion should mention SwiftVinetas; got:\n\(help)"
    )
    #expect(
      help.contains("flux-2-swift-mlx") || help.contains("Flux2") || help.contains("FLUX"),
      "Generate help discussion should mention flux-2-swift-mlx; got:\n\(help)"
    )
    #expect(
      help.contains("SwiftAcervo") || help.contains("SwiftTuberia") || help.contains("Tuberia"),
      "Generate help discussion should mention dep libraries; got:\n\(help)"
    )
  }

  @Test("Generate help message mentions trace path location")
  func generateHelpMentionsTracePathLocation() {
    let help = Generate.helpMessage()
    #expect(
      help.contains("Library/Caches") || help.contains(".jsonl"),
      "Generate help should describe where the trace file is written; got:\n\(help)"
    )
  }
}

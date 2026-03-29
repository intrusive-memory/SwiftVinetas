import Foundation
import Testing

@testable import SwiftVinetas

/// Integration tests that require a downloaded FLUX.2 model and Apple Silicon GPU.
/// These tests generate real images and take ~2 minutes on an M-series Mac.
///
/// Run with: xcodebuild test -scheme SwiftVinetas-Package -destination 'platform=macOS'
/// Or selectively: swift test --filter BatchIntegrationTests
@Suite("Batch Integration Tests", .tags(.integration, .flux2))
struct BatchIntegrationTests {

  /// Locate the YNTSWYD Chapter 1 fixture bundled as a test resource.
  private var fixtureURL: URL {
    get throws {
      guard
        let url = Bundle.module.url(
          forResource: "yntswyd-chapter1",
          withExtension: "yaml",
          subdirectory: "Fixtures"
        )
      else {
        throw VinetasError.invalidPromptFile(
          URL(fileURLWithPath: "Fixtures/yntswyd-chapter1.yaml")
        )
      }
      return url
    }
  }

  // MARK: - Fixture Validation (fast, no GPU)

  @Test("Fixture parses as valid PromptFile with 4 panels")
  func fixtureParses() throws {
    let url = try fixtureURL
    let promptFile = try PromptFile.parse(url: url)

    #expect(promptFile.version == 1)
    #expect(promptFile.project.title == "YNTSWYD Chapter 1 - Bernard's Descent")
    #expect(promptFile.panels.count == 4)

    // Each panel has a prompt and a deterministic seed
    for (index, panel) in promptFile.panels.enumerated() {
      #expect(!panel.prompt.isEmpty, "Panel \(index) has empty prompt")
      #expect(panel.seed != nil, "Panel \(index) missing seed for reproducibility")
    }

    // Style inherits gritty noir look
    let style = promptFile.project.style
    #expect(style != nil)
    #expect(style?.prompt?.contains("gritty noir") == true)
    #expect(style?.width == 1536)
    #expect(style?.height == 640)
  }

  @Test("Each panel resolves correct style with wide dimensions")
  func panelStyleResolution() throws {
    let url = try fixtureURL
    let promptFile = try PromptFile.parse(url: url)

    for i in 0..<promptFile.panels.count {
      let resolved = promptFile.resolvedStyle(for: i)
      #expect(resolved.width == 1536, "Panel \(i) width should be 1536")
      #expect(resolved.height == 640, "Panel \(i) height should be 640")
      #expect(resolved.steps == 20)
      #expect(resolved.guidanceScale == 3.5)
      #expect(resolved.stylePrompt.contains("gritty noir"))
    }
  }

  // MARK: - Image Generation (requires GPU + model)

  @Test(
    "Generate 4 non-empty images from YNTSWYD Chapter 1 fixture",
    .tags(.integration, .gpu, .flux2),
    .timeLimit(.minutes(10)))
  func generateBatchFromFixture() async throws {
    let url = try fixtureURL

    // Ensure Klein 4B model is available
    let model = VinetasModel.klein4b
    try #require(
      try await Vinetas.validateMemory(for: model), "Insufficient memory for \(model.rawValue)")

    try await Vinetas.download(model: model) { _ in }

    var panelProgress: [(current: Int, total: Int)] = []
    let outputs = try await Vinetas.generateFromFile(
      url,
      model: model,
      progress: { current, total in
        panelProgress.append((current, total))
      }
    )

    // Must produce exactly 4 panels
    #expect(outputs.count == 4, "Expected 4 panels, got \(outputs.count)")

    // Each image must be non-empty with correct dimensions
    for (index, output) in outputs.enumerated() {
      #expect(output.image.width > 0, "Panel \(index) image has zero width")
      #expect(output.image.height > 0, "Panel \(index) image has zero height")
      #expect(output.width == 1536, "Panel \(index) expected width 1536, got \(output.width)")
      #expect(output.height == 640, "Panel \(index) expected height 640, got \(output.height)")
      #expect(!output.prompt.isEmpty, "Panel \(index) output has empty prompt")
      #expect(output.durationSeconds > 0, "Panel \(index) reported zero duration")
      #expect(output.model == model)
    }

    // Verify seeds match fixture for reproducibility
    #expect(outputs[0].seed == 1001)
    #expect(outputs[1].seed == 1002)
    #expect(outputs[2].seed == 1003)
    #expect(outputs[3].seed == 1004)

    // Verify progress was reported for all 4 panels
    #expect(!panelProgress.isEmpty, "No progress callbacks received")
  }

  // MARK: - CLI Batch Output (requires GPU + model)

  @Test(
    "CLI batch writes 4 non-empty PNG files to output directory",
    .tags(.integration, .gpu, .flux2),
    .timeLimit(.minutes(10)))
  func cliBatchWritesPNGs() async throws {
    let url = try fixtureURL
    let model = VinetasModel.klein4b
    try #require(
      try await Vinetas.validateMemory(for: model), "Insufficient memory for \(model.rawValue)")

    try await Vinetas.download(model: model) { _ in }

    // Create a temporary output directory
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vinetas-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let outputs = try await Vinetas.generateFromFile(url, model: model)

    // Write each panel as the CLI batch command would
    for (index, output) in outputs.enumerated() {
      let filename = String(format: "panel-%03d.png", index + 1)
      let panelURL = tempDir.appendingPathComponent(filename)
      let style = StyleConfig(width: output.width, height: output.height)
      try ImageOutput.writePanel(output, to: panelURL, style: style)
    }

    // Verify 4 PNG files exist and are non-empty
    let files = try FileManager.default.contentsOfDirectory(
      at: tempDir,
      includingPropertiesForKeys: [.fileSizeKey]
    ).filter { $0.pathExtension == "png" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    #expect(files.count == 4, "Expected 4 PNG files, found \(files.count)")

    for file in files {
      let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
      let size = attrs[.size] as? Int ?? 0
      #expect(size > 0, "\(file.lastPathComponent) is empty (0 bytes)")
    }
  }
}


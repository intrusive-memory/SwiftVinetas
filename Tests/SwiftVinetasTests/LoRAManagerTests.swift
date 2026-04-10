import Foundation
import Testing

@testable import SwiftVinetas

@Suite("LoRAManager")
struct LoRAManagerTests {

  // MARK: - Test 1: Load call recorded on MockEngine

  @Test
  func loraLoadCallRecordedOnMockEngine() async throws {
    // Create a temporary file to simulate a LoRA safetensors file
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent("test-lora-\(UUID().uuidString).safetensors")

    // Write dummy content to make the file exist
    try Data().write(to: tempFile)

    defer {
      // Clean up temp file after test
      try? FileManager.default.removeItem(at: tempFile)
    }

    // Create a mock engine to record calls
    let engine = MockEngine(engineID: "test-engine")

    // Call VinetasLoRAManager.load with the temp file
    try await VinetasLoRAManager.load(
      path: tempFile.path,
      scale: 0.8,
      on: engine
    )

    // Assert that the engine recorded the loadLoRA call with correct parameters
    let calls = await engine.calls
    #expect(
      calls.contains(.loadLoRA(tempFile.lastPathComponent, 0.8)),
      "Expected .loadLoRA call to be recorded on engine"
    )
  }

  // MARK: - Test 2: Unload call recorded on MockEngine

  @Test
  func loraUnloadCallRecordedOnMockEngine() async {
    let engine = MockEngine(engineID: "test-engine")

    // Call VinetasLoRAManager.unload
    await VinetasLoRAManager.unload(from: engine)

    // Assert that the engine recorded the unloadLoRA call
    let calls = await engine.calls
    #expect(
      calls.contains(.unloadLoRA),
      "Expected .unloadLoRA call to be recorded on engine"
    )
  }

  // MARK: - Test 3: Load followed by Unload in correct order

  @Test
  func loraLoadFollowedByUnload() async throws {
    // Create a temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent("test-lora-\(UUID().uuidString).safetensors")

    try Data().write(to: tempFile)

    defer {
      try? FileManager.default.removeItem(at: tempFile)
    }

    let engine = MockEngine(engineID: "test-engine")

    // Load the LoRA
    try await VinetasLoRAManager.load(
      path: tempFile.path,
      scale: 0.8,
      on: engine
    )

    // Unload the LoRA
    await VinetasLoRAManager.unload(from: engine)

    // Assert the calls are in the correct order: [.loadLoRA, .unloadLoRA]
    let calls = await engine.calls
    #expect(calls.count == 2, "Expected exactly 2 calls (load and unload)")

    if calls.count == 2 {
      if case .loadLoRA(let filename, let scale) = calls[0] {
        #expect(
          filename == tempFile.lastPathComponent,
          "First call should be loadLoRA with correct filename")
        #expect(scale == 0.8, "First call should have scale 0.8")
      } else {
        Issue.record("First call should be .loadLoRA")
      }

      if case .unloadLoRA = calls[1] {
        // Correct
      } else {
        Issue.record("Second call should be .unloadLoRA")
      }
    }
  }

  // MARK: - Test 4: Load with missing file throws error

  @Test
  func loraLoadWithMissingFileThrows() async throws {
    let engine = MockEngine(engineID: "test-engine")

    // Attempt to load from a non-existent path
    let nonexistentPath = "/nonexistent/path/lora.safetensors"

    // Use await #expect to verify that the call throws VinetasError
    await #expect(throws: VinetasError.self) {
      try await VinetasLoRAManager.load(
        path: nonexistentPath,
        scale: 0.8,
        on: engine
      )
    }

    // Assert that the engine was never reached (no calls recorded)
    let calls = await engine.calls
    #expect(
      calls.isEmpty,
      "Expected engine.calls to be empty since file validation happens before engine call"
    )
  }
}

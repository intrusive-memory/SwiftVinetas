import Foundation
import Testing

@testable import SwiftVinetas

/// Mock-level tests for the cancellation-teardown behavior added for
/// SwiftVinetas#41. The real engines wrap their pipeline call in
/// `withTaskCancellationHandler { … } onCancel: { VinetasMemory.releaseMLXCache() }`
/// so a cancelled generation deterministically flushes the MLX buffer cache and
/// resets the `isGenerating` reentrancy flag. `MockEngine` reproduces that
/// `withTaskCancellationHandler` shape (recording a `cacheFlushed` flag in place
/// of the real MLX flush) so the contract is exercised without a GPU.
@Suite("Cancellation Teardown")
struct CancellationTeardownTests {

  @Test("Cancelling a suspended generate runs the cache flush and resets isGenerating")
  func cancelFlushesCacheAndResetsFlag() async throws {
    let engine = MockEngine(engineID: "mock")
    await engine.setSuspendUntilCancelled(true)

    let request = GenerationRequest(
      prompt: "anything", steps: 4, guidanceScale: 3.0, width: 64, height: 64, mode: .textToImage)

    let task = Task {
      try await engine.generate(request: request, stepProgress: nil)
    }

    // Give the generate Task time to enter the suspend loop and set isGenerating.
    while await engine.isGenerating == false {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await engine.isGenerating == true)

    task.cancel()

    // The generate Task should unwind by throwing (CancellationError).
    let result = await task.result
    switch result {
    case .success:
      Issue.record("Expected the cancelled generate to throw, but it returned a value")
    case .failure:
      break  // expected
    }

    // The onCancel flush dispatches a Task onto the actor; poll until it lands.
    var flushed = await engine.cacheFlushed
    var attempts = 0
    while !flushed && attempts < 200 {
      try await Task.sleep(for: .milliseconds(5))
      flushed = await engine.cacheFlushed
      attempts += 1
    }
    #expect(flushed, "Cancellation should have run the cache flush (onCancel closure)")

    // The reentrancy guard must be reset after the cancelled generate unwinds.
    #expect(await engine.isGenerating == false)
  }

  @Test("A non-suspended generate completes without flagging a cache flush")
  func normalGenerateDoesNotFlush() async throws {
    let engine = MockEngine(engineID: "mock")
    // suspendUntilCancelled defaults to false → normal completion path.
    let request = GenerationRequest(
      prompt: "hello", steps: 4, guidanceScale: 3.0, width: 64, height: 64, mode: .textToImage)
    _ = try await engine.generate(request: request, stepProgress: nil)

    #expect(await engine.cacheFlushed == false)
    #expect(await engine.isGenerating == false)
  }
}

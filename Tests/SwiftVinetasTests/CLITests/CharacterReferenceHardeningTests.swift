import ArgumentParser
import Foundation
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

/// Sortie 13: harden `character reference` — pre-download validation and the
/// `--strength` warning (RI-5, RI-8).
///
/// Every test routes through the `CLIEnvironment` seam to a `MockEngine`
/// registered as `pixart-sigma` (free — `ProGate` never engages) instead of
/// touching the real `VinetasClient.shared` or the network.
@Suite("character reference hardening (Sortie 13)", .serialized)
struct CharacterReferenceHardeningTests {

  /// Counts attempted model downloads. Bound to
  /// ``CLIEnvironment/downloadModel`` (with ``CLIEnvironment/skipDownload``
  /// left `false`) so a validation regression that lets the command reach
  /// the download step is actually caught, rather than trivially passing
  /// because `skipDownload` suppressed the real download anyway.
  private actor DownloadAttemptCounter {
    private(set) var count = 0
    func increment() { count += 1 }
  }

  /// Runs `body` with CLI stderr bound to a pipe and returns what it wrote,
  /// even if `body` throws — the warning tests below only care about what
  /// reached stderr before the command (expectedly) fails further down for
  /// an unrelated reason (e.g. no character on disk). Touches no
  /// process-wide descriptor.
  private static func captureCLIStderr(_ body: () async throws -> Void) async -> String {
    let pipe = Pipe()
    try? await CLIEnvironment.$stderrDescriptor.withValue(
      pipe.fileHandleForWriting.fileDescriptor
    ) {
      try await body()
    }
    try? pipe.fileHandleForWriting.close()
    let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }

  /// Runs `Character.Reference` with `client` bound to a router containing
  /// only `engine`, and `downloadModel` bound to a counting stub (never the
  /// real `Vinetas.download`). `skipDownload` is left at its default
  /// (`false`) so the counter is meaningful.
  private static func runReference(
    _ arguments: [String],
    engine: MockEngine,
    downloadCounter: DownloadAttemptCounter
  ) async throws {
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    try await CLIEnvironment.$client.withValue(client) {
      try await CLIEnvironment.$downloadModel.withValue({ _, _ in
        await downloadCounter.increment()
      }) {
        let cmd = try CharacterCommand.Reference.parse(arguments)
        try await cmd.run()
      }
    }
  }

  // MARK: - Task 1: pre-download validation

  @Test("--model pixart-sigma fails before any download or model load")
  func pixartSigmaFailsBeforeDownloadOrLoad() async throws {
    // Default maxReferenceImages is 0: PixArt accepts no reference images.
    let engine = MockEngine(engineID: "pixart-sigma")
    let counter = DownloadAttemptCounter()

    await #expect(throws: VinetasError.self) {
      try await Self.runReference(
        ["probe-slug", "--model", "pixart-sigma"], engine: engine, downloadCounter: counter)
    }

    #expect(await counter.count == 0)
    #expect(await engine.loadModelCallCount == 0)
  }

  // MARK: - Task 2: unknown --model

  @Test("--model bogus throws a ValidationError naming the valid FLUX models")
  func unknownModelThrows() async throws {
    let engine = MockEngine(engineID: "pixart-sigma")
    let counter = DownloadAttemptCounter()

    do {
      try await Self.runReference(
        ["probe-slug", "--model", "bogus"], engine: engine, downloadCounter: counter)
      Issue.record("Expected ValidationError")
    } catch let error as ValidationError {
      #expect(error.message == "Unknown model 'bogus'. Valid: klein4b")
    }

    #expect(await counter.count == 0)
    #expect(await engine.loadModelCallCount == 0)
  }

  // MARK: - Task 3: --strength warning

  @Test("--strength 0.5 emits the deprecation warning on stderr")
  func explicitStrengthWarns() async throws {
    let engine = MockEngine(engineID: "pixart-sigma")
    let counter = DownloadAttemptCounter()

    let stderrText = await Self.captureCLIStderr {
      try await Self.runReference(
        ["probe-slug", "--model", "pixart-sigma", "--strength", "0.5"],
        engine: engine, downloadCounter: counter)
    }

    #expect(
      stderrText.contains(
        "warning: --strength has no effect and will be removed in the next minor release"))
  }

  @Test("no --strength emits no warning")
  func noStrengthNoWarning() async throws {
    let engine = MockEngine(engineID: "pixart-sigma")
    let counter = DownloadAttemptCounter()

    let stderrText = await Self.captureCLIStderr {
      try await Self.runReference(
        ["probe-slug", "--model", "pixart-sigma"], engine: engine, downloadCounter: counter)
    }

    #expect(!stderrText.contains("warning: --strength"))
  }
}

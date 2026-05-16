import Flux2Core
import Foundation
import PixArtBackbone
import SwiftAcervo
import SwiftVinetas
import Testing
import Tuberia
import VinetasCLICore

// MARK: - CLITelemetryBootstrapTests (Sortie 11c)
//
// Deeper coverage of CLITelemetryBootstrap beyond the S8 smoke test.
// Covers:
//  - enable(.full) installs all five adapters; each seam is non-nil after enable
//  - finish() uninstalls adapters; seams return to nil
//  - bootstrap.traceURL returns the expected URL
//  - enable(.partial) installs only the Vinetas adapter; dep seams remain nil
//
// NOTE: All tests in this suite are serialized (.serialized trait) because they
// exercise process-wide singletons (Flux2Telemetry.current, PixArtTelemetry.current,
// TuberiaTelemetry.current, VinetasClient.shared). Parallel execution would produce
// unreliable results due to shared mutable global state.

@Suite("CLITelemetryBootstrap unit tests", .serialized)
struct CLITelemetryBootstrapTests {

  private func makeTraceURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("bootstrap-test-\(UUID().uuidString).jsonl")
  }

  // MARK: - Full mode: all five seams installed

  @Test("enable(.full) installs Vinetas adapter: modelAvailabilityChecked event lands in trace")
  func fullModeInstallsVinetasAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    // Ensure clean state.
    await VinetasClient.shared.setTelemetry(nil)

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)

    // isModelAvailble emits modelAvailabilityChecked via currentTelemetry()?.capture(...)
    // which goes synchronously through the adapter to the sink.
    _ = await VinetasClient.shared.isModelAvailable("any-model-id")

    await bootstrap.finish()

    let data = try Data(contentsOf: url)
    let lineCount = data.split(separator: 0x0A).filter { !$0.isEmpty }.count
    #expect(
      lineCount >= 1,
      "enable(.full) should install the Vinetas adapter; trace should have ≥1 line, got \(lineCount)"
    )
  }

  @Test("enable(.full) installs Flux2 adapter (Flux2Telemetry.current is non-nil)")
  func fullModeInstallsFlux2Adapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    Flux2Telemetry.setReporter(nil)

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)
    #expect(
      Flux2Telemetry.current != nil,
      "enable(.full) should install the Flux2 adapter; Flux2Telemetry.current should be non-nil"
    )
    await bootstrap.finish()
  }

  @Test("enable(.full) installs PixArt adapter (PixArtTelemetry.current is non-nil)")
  func fullModeInstallsPixArtAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    PixArtTelemetry.setReporter(nil)

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)
    #expect(
      PixArtTelemetry.current != nil,
      "enable(.full) should install the PixArt adapter; PixArtTelemetry.current should be non-nil"
    )
    await bootstrap.finish()
  }

  @Test("enable(.full) installs Tuberia adapter (TuberiaTelemetry.current is non-nil)")
  func fullModeInstalllsTuberiaAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    TuberiaTelemetry.setReporter(nil)

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)
    #expect(
      TuberiaTelemetry.current != nil,
      "enable(.full) should install the Tuberia adapter; TuberiaTelemetry.current should be non-nil"
    )
    await bootstrap.finish()
  }

  // MARK: - finish() uninstalls dep adapters

  @Test("finish() uninstalls Flux2 adapter (Flux2Telemetry.current becomes nil)")
  func finishUninstallsFlux2Adapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    Flux2Telemetry.setReporter(nil)
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)
    #expect(Flux2Telemetry.current != nil, "Precondition: Flux2 adapter should be installed")

    await bootstrap.finish()
    #expect(
      Flux2Telemetry.current == nil,
      "finish() should uninstall the Flux2 adapter; Flux2Telemetry.current should be nil"
    )
  }

  @Test("finish() uninstalls PixArt adapter (PixArtTelemetry.current becomes nil)")
  func finishUninstallsPixArtAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    PixArtTelemetry.setReporter(nil)
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)
    #expect(PixArtTelemetry.current != nil, "Precondition: PixArt adapter should be installed")

    await bootstrap.finish()
    #expect(
      PixArtTelemetry.current == nil,
      "finish() should uninstall the PixArt adapter; PixArtTelemetry.current should be nil"
    )
  }

  @Test("finish() uninstalls Tuberia adapter (TuberiaTelemetry.current becomes nil)")
  func finishUninstalslTuberiaAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    TuberiaTelemetry.setReporter(nil)
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .full)
    #expect(TuberiaTelemetry.current != nil, "Precondition: Tuberia adapter should be installed")

    await bootstrap.finish()
    #expect(
      TuberiaTelemetry.current == nil,
      "finish() should uninstall the Tuberia adapter; TuberiaTelemetry.current should be nil"
    )
  }

  // MARK: - traceURL

  @Test("bootstrap.traceURL matches the URL passed to enable")
  func traceURLMatchesPassedURL() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .partial)
    // traceURL is actor-isolated on TelemetryJSONLSink; access with await.
    let sinkURL = await bootstrap.sink.traceURL
    #expect(
      sinkURL == url,
      "bootstrap.sink.traceURL should equal the traceURL passed to enable"
    )
    await bootstrap.finish()
  }

  // MARK: - Mode: partial

  @Test("enable(.partial) does NOT install Flux2 adapter")
  func partialModeSkipsFlux2Adapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    Flux2Telemetry.setReporter(nil)
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .partial)
    #expect(
      Flux2Telemetry.current == nil,
      "enable(.partial) should NOT install the Flux2 adapter"
    )
    await bootstrap.finish()
  }

  @Test("enable(.partial) does NOT install PixArt adapter")
  func partialModeSkipsPixArtAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    PixArtTelemetry.setReporter(nil)
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .partial)
    #expect(
      PixArtTelemetry.current == nil,
      "enable(.partial) should NOT install the PixArt adapter"
    )
    await bootstrap.finish()
  }

  @Test("enable(.partial) does NOT install Tuberia adapter")
  func partialModeSkipsTuberiaAdapter() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    TuberiaTelemetry.setReporter(nil)
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .partial)
    #expect(
      TuberiaTelemetry.current == nil,
      "enable(.partial) should NOT install the Tuberia adapter"
    )
    await bootstrap.finish()
  }

  // MARK: - Mode stored on bootstrap

  @Test("bootstrap.mode reflects the mode passed to enable")
  func bootstrapModeIsPreserved() async throws {
    let urlFull = makeTraceURL()
    let urlPartial = makeTraceURL()
    defer {
      try? FileManager.default.removeItem(at: urlFull)
      try? FileManager.default.removeItem(at: urlPartial)
    }

    let full = try await CLITelemetryBootstrap.enable(traceURL: urlFull, mode: .full)
    await full.finish()

    let partial = try await CLITelemetryBootstrap.enable(traceURL: urlPartial, mode: .partial)
    await partial.finish()

    #expect(full.mode == .full, "bootstrap.mode should be .full when passed .full")
    #expect(partial.mode == .partial, "bootstrap.mode should be .partial when passed .partial")
  }

  // MARK: - stderr: finish() prints the trace path

  @Test("finish() writes [vinetas] Telemetry trace: <path> to stderr")
  func finishPrintsTracePathToStderr() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: url, mode: .partial)

    // Capture stderr.
    let pipe = Pipe()
    let savedStderr = dup(fileno(stderr))
    dup2(pipe.fileHandleForWriting.fileDescriptor, fileno(stderr))

    await bootstrap.finish()

    fflush(stderr)
    dup2(savedStderr, fileno(stderr))
    close(savedStderr)
    try? pipe.fileHandleForWriting.close()

    let capturedData = try pipe.fileHandleForReading.readToEnd() ?? Data()
    let capturedText = String(data: capturedData, encoding: .utf8) ?? ""

    #expect(
      capturedText.contains("[vinetas] Telemetry trace:"),
      "finish() must print '[vinetas] Telemetry trace:' to stderr; got: \(capturedText.debugDescription)"
    )
    // Verify the captured text contains the trace file name.
    #expect(
      capturedText.contains(url.lastPathComponent),
      "finish() must print the trace file name to stderr; got: \(capturedText.debugDescription)"
    )
  }
}

import Flux2Core
import Foundation
import PixArtBackbone
import SwiftAcervo
import SwiftVinetas
import Tuberia

// MARK: - OQ-1 RESOLUTION — per-dep setTelemetry entry points (verified against v3.2.1/v0.7.1/v0.7.1 sibling releases):
//   Vinetas:  VinetasClient.shared.setTelemetry(_:)   — instance-bound (S3 seam, singleton works)
//   Acervo:   AcervoManager.shared.setTelemetry(_:)   — instance-bound (singleton works)
//   Flux2:    Flux2Telemetry.setReporter(_:)          — process-wide (Flux2Core 3.2.1+)
//   PixArt:   PixArtTelemetry.setReporter(_:)         — process-wide (PixArtBackbone 0.7.1+)
//   Tuberia:  TuberiaTelemetry.setReporter(_:)        — process-wide (Tuberia 0.7.1+)
//
// Note: `Flux2Telemetry.setReporter(_:)` is the process-wide seam that supersedes the
// previously-used `Flux2WeightLoader.setTelemetry(_:)` static call. Per Flux2Core AGENTS.md,
// `pipeline.setTelemetry(_:)` propagates the reporter to every owned subcomponent including
// `Flux2WeightLoader`; the process-wide seam resolves through `effectiveReporter` at each
// emission site (`instanceReporter ?? Flux2Telemetry.current`), so all 11 Flux2TelemetryEvent
// cases — including weight-load events — reach the adapter via the single process-wide install.

/// Holds the JSONL sink and the five CLI-side telemetry adapters for the
/// duration of a single `vinetas` subcommand invocation.
///
/// Per REQUIREMENTS §7.5. Construct via ``enable(traceURL:)``, tear down via
/// ``finish()``. The struct is `Sendable` because every stored property is
/// `Sendable` (the sink is an actor; the adapters are `struct`s with a single
/// actor-typed stored property).
public struct CLITelemetryBootstrap: Sendable {

  /// Wiring mode: "full" installs all five adapters; "partial" installs only
  /// the Vinetas adapter (used by `Classify` / `Features` / `Similarity`
  /// subcommands per REQUIREMENTS §7.7).
  public enum Mode: Sendable {
    case full
    case partial
  }

  public let sink: TelemetryJSONLSink
  public let vinetasAdapter: VinetasTelemetryCLIAdapter
  public let flux2Adapter: Flux2TelemetryCLIAdapter
  public let pixartAdapter: PixArtTelemetryCLIAdapter
  public let tuberiaAdapter: TuberiaTelemetryCLIAdapter
  public let acervoAdapter: AcervoTelemetryCLIAdapter

  /// The mode this bootstrap was enabled with. Used by ``finish()`` to mirror
  /// the install steps when tearing down.
  public let mode: Mode

  private init(
    sink: TelemetryJSONLSink,
    vinetasAdapter: VinetasTelemetryCLIAdapter,
    flux2Adapter: Flux2TelemetryCLIAdapter,
    pixartAdapter: PixArtTelemetryCLIAdapter,
    tuberiaAdapter: TuberiaTelemetryCLIAdapter,
    acervoAdapter: AcervoTelemetryCLIAdapter,
    mode: Mode
  ) {
    self.sink = sink
    self.vinetasAdapter = vinetasAdapter
    self.flux2Adapter = flux2Adapter
    self.pixartAdapter = pixartAdapter
    self.tuberiaAdapter = tuberiaAdapter
    self.acervoAdapter = acervoAdapter
    self.mode = mode
  }

  /// Constructs the sink + five adapters and installs every reachable
  /// reporter on its dep's canonical install seam. See the OQ-1 RESOLUTION
  /// block at the top of this file for the per-dep seam citations.
  ///
  /// - Parameters:
  ///   - traceURL: Optional override for the JSONL trace file path. When nil,
  ///               the path returned by ``defaultTraceURL()`` is used (CLI
  ///               default behaviour). Tests pass an explicit URL.
  ///   - mode: `.full` for diffusion-producing subcommands, `.partial` for
  ///           image-understanding subcommands (REQUIREMENTS §7.7).
  /// - Returns: The bootstrap instance, retained so the caller can invoke
  ///            ``finish()`` after the subcommand body completes.
  public static func enable(
    traceURL: URL? = nil,
    mode: Mode = .full
  ) async throws -> CLITelemetryBootstrap {
    let resolvedURL = traceURL ?? defaultTraceURL()
    let sink = try TelemetryJSONLSink(traceURL: resolvedURL)

    let bootstrap = CLITelemetryBootstrap(
      sink: sink,
      vinetasAdapter: VinetasTelemetryCLIAdapter(sink: sink),
      flux2Adapter: Flux2TelemetryCLIAdapter(sink: sink),
      pixartAdapter: PixArtTelemetryCLIAdapter(sink: sink),
      tuberiaAdapter: TuberiaTelemetryCLIAdapter(sink: sink),
      acervoAdapter: AcervoTelemetryCLIAdapter(sink: sink),
      mode: mode
    )

    // Vinetas adapter — always installed (covers Vinetas-scope events in
    // every subcommand, including the image-understanding ones).
    await VinetasClient.shared.setTelemetry(bootstrap.vinetasAdapter)

    // Dep adapters — only installed in .full mode. Image-understanding
    // subcommands skip these per REQUIREMENTS §7.7 to keep their traces clean
    // of dep events that wouldn't fire anyway.
    if mode == .full {
      // Acervo: singleton actor, reachable everywhere.
      await AcervoManager.shared.setTelemetry(bootstrap.acervoAdapter)

      // Flux2: process-wide seam (Flux2Core 3.2.1+). Covers all 11 event cases
      // including weight-load events — supersedes the previous
      // Flux2WeightLoader.setTelemetry(_:) static call.
      Flux2Telemetry.setReporter(bootstrap.flux2Adapter)

      // PixArt: process-wide seam (PixArtBackbone 0.7.1+). Covers DiT instances
      // constructed lazily inside PixArtEngine — unreachable directly from CLI bootstrap.
      PixArtTelemetry.setReporter(bootstrap.pixartAdapter)

      // Tuberia: process-wide seam (Tuberia 0.7.1+). Covers DiffusionPipeline
      // instances constructed lazily inside engine actors.
      TuberiaTelemetry.setReporter(bootstrap.tuberiaAdapter)
    }

    return bootstrap
  }

  /// Tears down every install performed by ``enable(traceURL:mode:)``, flushes
  /// the sink, and prints the trace path to stderr.
  ///
  /// Per REQUIREMENTS §7.6 / OQ-2: this is invoked from `defer { Task { … } }`
  /// in each subcommand's `run()` body. Fire-and-forget — the per-line flush
  /// in the sink means at most one truncated trailing line if the process
  /// exits before this Task runs.
  public func finish() async {
    await VinetasClient.shared.setTelemetry(nil)

    if mode == .full {
      await AcervoManager.shared.setTelemetry(nil)
      Flux2Telemetry.setReporter(nil)
      PixArtTelemetry.setReporter(nil)
      TuberiaTelemetry.setReporter(nil)
    }

    await sink.close()

    let message = "[vinetas] Telemetry trace: \(sink.traceURL.path)\n"
    if let data = message.data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }
}

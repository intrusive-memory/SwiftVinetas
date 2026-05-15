import Flux2Core
import Foundation
import PixArtBackbone
import SwiftAcervo
import SwiftVinetas
import Tuberia

// MARK: - OQ-1 RESOLUTION — per-dep setTelemetry entry points
//
// Each dep ships a reporter protocol (verified against sibling checkouts under
// /Users/stovak/Projects/<repo>) but only a subset expose a process-wide
// install seam reachable from CLI bootstrap. The instance-bound seams
// (`Flux2Pipeline.setTelemetry`, `PixArtDiT.setTelemetry`,
// `DiffusionPipeline.setTelemetry`) live behind SwiftVinetas's engine actors;
// the engines create those instances lazily during `loadModel(_:)`. Adapters
// for all five protocols are constructed up front so they are ready to install
// once a library-side propagation seam exists, but `enable()` only installs on
// the seams that are actually reachable today.
//
//  Vinetas:  VinetasClient.shared.setTelemetry(_:)
//            — Sources/SwiftVinetas/Vinetas.swift (S3 seam)
//
//  Acervo:   AcervoManager.shared.setTelemetry(_:)
//            — /Users/stovak/Projects/SwiftAcervo/Sources/SwiftAcervo/AcervoManager.swift:70
//              (singleton actor used by SwiftVinetas for component access)
//
//  Flux2:    Flux2WeightLoader.setTelemetry(_:)  [static, process-wide]
//            — /Users/stovak/Projects/flux-2-swift-mlx/Sources/Flux2Core/Loading/WeightLoader.swift:23
//              (per-instance Flux2Pipeline.setTelemetry at
//               /Users/stovak/Projects/flux-2-swift-mlx/Sources/Flux2Core/Pipeline/Flux2Pipeline.swift:83
//               is owned by SwiftVinetas's Flux2Engine actor and not reachable
//               from CLI bootstrap; weight-load events still flow through the
//               static seam, which captures the most diagnostically useful
//               subset of dep events from the CLI's perspective.)
//
//  PixArt:   no process-wide seam.
//            — Per-instance PixArtDiT.setTelemetry(_:) at
//              /Users/stovak/Projects/pixart-swift-mlx/Sources/PixArtBackbone/PixArtDiT.swift:40
//              is owned by SwiftVinetas's PixArtEngine actor and the DiT is
//              instantiated lazily inside loadModel(_:). Adapter constructed
//              but not installed; capture of PixArt events requires a future
//              library-side seam (e.g. PixArtEngine.setPixArtReporter(_:)).
//
//  Tuberia:  no process-wide seam.
//            — Per-instance DiffusionPipeline.setTelemetry(_:) at
//              /Users/stovak/Projects/SwiftTuberia/Sources/Tuberia/Pipeline/DiffusionPipeline+Telemetry.swift:31
//              is owned by individual engines and constructed lazily. Same
//              future-seam requirement as PixArt.
//
// Library-side follow-up (out of scope for S8): SwiftVinetas grows a
// public surface for installing dep-reporter triples (Flux2 / PixArt /
// Tuberia) on each engine, so the CLI bootstrap can route adapters into the
// engines' internal pipelines without breaking the §5.3 contract that
// SwiftVinetas does not bridge dep events onto its own surface.

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

      // Flux2: static weight-loader seam. The Flux2Pipeline instance lives
      // inside Flux2Engine and isn't reachable from CLI bootstrap; weight-
      // load events still flow through this static seam.
      Flux2WeightLoader.setTelemetry(bootstrap.flux2Adapter)

      // PixArt and Tuberia: no process-wide install seam today. Adapters are
      // built so the wiring is ready when SwiftVinetas grows a propagation
      // seam, but the install is a no-op in this revision.
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
      Flux2WeightLoader.setTelemetry(nil)
    }

    await sink.close()

    let message = "[vinetas] Telemetry trace: \(sink.traceURL.path)\n"
    if let data = message.data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }
}

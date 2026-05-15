import Flux2Core
import Foundation

/// CLI-side adapter conforming to `Flux2TelemetryReporter`. Forwards every
/// `Flux2TelemetryEvent` to the shared `TelemetryJSONLSink` with `kind: "flux2"`.
///
/// Install via `Flux2WeightLoader.setTelemetry(_:)` (the only process-wide
/// install seam Flux2Core exposes; `Flux2Pipeline.setTelemetry` is instance-
/// scoped and the pipeline lives inside SwiftVinetas's `Flux2Engine` actor,
/// which the CLI bootstrap cannot reach without breaking encapsulation).
public struct Flux2TelemetryCLIAdapter: Flux2TelemetryReporter {
  private let sink: TelemetryJSONLSink

  public init(sink: TelemetryJSONLSink) {
    self.sink = sink
  }

  public func capture(_ event: Flux2TelemetryEvent) async {
    await sink.write(kind: "flux2", payload: Flux2EventCodable(event: event))
  }
}

import Foundation
import Tuberia

/// CLI-side adapter conforming to `TuberiaTelemetryReporter`. Forwards every
/// `TuberiaTelemetryEvent` to the shared `TelemetryJSONLSink` with `kind: "tuberia"`.
///
/// Tuberia exposes `setTelemetry(_:)` only on `DiffusionPipeline` instances,
/// which the CLI bootstrap cannot reach (pipelines are constructed inside
/// SwiftVinetas's engine actors during generation). The adapter is shipped so
/// it is ready to install once the library grows a propagation seam for dep
/// reporters; today it conforms to the protocol but has no canonical install
/// point reachable from CLI bootstrap.
public struct TuberiaTelemetryCLIAdapter: TuberiaTelemetryReporter {
  private let sink: TelemetryJSONLSink

  public init(sink: TelemetryJSONLSink) {
    self.sink = sink
  }

  public func capture(_ event: TuberiaTelemetryEvent) async {
    await sink.write(kind: "tuberia", payload: TuberiaEventCodable(event: event))
  }
}

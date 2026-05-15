import Foundation
import SwiftAcervo

/// CLI-side adapter conforming to `AcervoTelemetryReporter`. Forwards every
/// `AcervoTelemetryEvent` to the shared `TelemetryJSONLSink` with `kind: "acervo"`.
///
/// Install via `AcervoManager.shared.setTelemetry(_:)` — the singleton seam
/// the rest of SwiftVinetas already uses to coordinate model access.
public struct AcervoTelemetryCLIAdapter: AcervoTelemetryReporter {
  private let sink: TelemetryJSONLSink

  public init(sink: TelemetryJSONLSink) {
    self.sink = sink
  }

  public func capture(_ event: AcervoTelemetryEvent) async {
    await sink.write(kind: "acervo", payload: AcervoEventCodable(event: event))
  }
}

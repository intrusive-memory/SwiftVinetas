import Foundation
import SwiftVinetas

/// CLI-side adapter that conforms to `VinetasTelemetryReporter` and forwards
/// every captured event to a shared `TelemetryJSONLSink` with `kind: "vinetas"`.
///
/// One adapter per CLI invocation. The adapter is `Sendable` (`struct` with
/// only `Sendable` stored properties), safe to pass to
/// `VinetasClient.shared.setTelemetry(_:)`.
///
/// Per REQUIREMENTS §7.4: each adapter is bound to one reporter protocol and
/// one `kind` string. No filtering, no pretty-printing, no cross-library
/// bridging — encode-and-forward only.
public struct VinetasTelemetryCLIAdapter: VinetasTelemetryReporter {
  private let sink: TelemetryJSONLSink

  public init(sink: TelemetryJSONLSink) {
    self.sink = sink
  }

  public func capture(_ event: VinetasTelemetryEvent) async {
    await sink.write(kind: "vinetas", payload: VinetasEventCodable(event: event))
  }
}

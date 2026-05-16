import Foundation
import PixArtBackbone

/// CLI-side adapter conforming to `PixArtTelemetryReporter`. Forwards every
/// `PixArtTelemetryEvent` to the shared `TelemetryJSONLSink` with `kind: "pixart"`.
///
/// PixArt exposes `setTelemetry(_:)` only on `PixArtDiT` instances, which the
/// CLI bootstrap cannot reach (the DiT is owned by SwiftVinetas's `PixArtEngine`
/// actor and created lazily during model load). The adapter is shipped so it
/// is ready to install once the library grows a propagation seam for dep
/// reporters; today it conforms to the protocol but has no canonical install
/// point reachable from CLI bootstrap.
public struct PixArtTelemetryCLIAdapter: PixArtTelemetryReporter {
  private let sink: TelemetryJSONLSink

  public init(sink: TelemetryJSONLSink) {
    self.sink = sink
  }

  public func capture(_ event: PixArtTelemetryEvent) async {
    await sink.write(kind: "pixart", payload: PixArtEventCodable(event: event))
  }
}

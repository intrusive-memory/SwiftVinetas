public protocol VinetasTelemetryReporter: Sendable {
  func capture(_ event: VinetasTelemetryEvent) async
}

public struct NoopVinetasTelemetryReporter: VinetasTelemetryReporter {
  public init() {}
  public func capture(_ event: VinetasTelemetryEvent) async {}
}

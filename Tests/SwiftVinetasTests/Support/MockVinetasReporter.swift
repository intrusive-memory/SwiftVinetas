import Foundation
import os.lock

@testable import SwiftVinetas

// MARK: - MockVinetasReporter

/// A thread-safe mock implementation of `VinetasTelemetryReporter` for use in
/// unit tests. Events are captured under an `OSAllocatedUnfairLock` so the mock
/// is safe to share across actors and concurrent test tasks.
///
/// Marked `@unchecked Sendable` because the `OSAllocatedUnfairLock` provides
/// the actual safety guarantee; the type itself is a `final class` so no
/// subclassing can bypass the lock.
final class MockVinetasReporter: VinetasTelemetryReporter, @unchecked Sendable {

  // MARK: - Private storage

  private let _lock = OSAllocatedUnfairLock<[VinetasTelemetryEvent]>(initialState: [])

  // MARK: - VinetasTelemetryReporter conformance

  func capture(_ event: VinetasTelemetryEvent) async {
    _lock.withLock { $0.append(event) }
  }

  // MARK: - Thread-safe read accessors

  /// All captured events in capture order.
  var events: [VinetasTelemetryEvent] {
    _lock.withLock { $0 }
  }

  /// Number of captured events.
  var count: Int {
    _lock.withLock { $0.count }
  }

  /// Clears the captured event buffer.
  func reset() {
    _lock.withLock { $0.removeAll() }
  }

  /// Returns the first captured event matching the predicate, or `nil`.
  func first(matching predicate: @Sendable (VinetasTelemetryEvent) -> Bool) -> VinetasTelemetryEvent? {
    _lock.withLock { $0.first(where: predicate) }
  }

  /// Returns the last captured event matching the predicate, or `nil`.
  func last(matching predicate: @Sendable (VinetasTelemetryEvent) -> Bool) -> VinetasTelemetryEvent? {
    _lock.withLock { $0.last(where: predicate) }
  }

  /// Returns all events matching the predicate.
  func all(matching predicate: @Sendable (VinetasTelemetryEvent) -> Bool) -> [VinetasTelemetryEvent] {
    _lock.withLock { $0.filter(predicate) }
  }
}

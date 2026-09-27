import Foundation
import SwiftVinetas

/// Task-local injection seam for CLI commands.
///
/// Generation commands (`generate`, `batch`, `storyboard`, `character reference`)
/// reach the library through ``client`` instead of the process-wide
/// `VinetasClient.shared`, so tests can bind a client built on a mock
/// `EngineRouter`:
///
/// ```swift
/// try await CLIEnvironment.$client.withValue(VinetasClient(router: mockRouter)) {
///   try await CLIEnvironment.$skipDownload.withValue(true) {
///     try await Generate.parse(["a prompt"]).run()
///   }
/// }
/// ```
public enum CLIEnvironment {
  /// The client every CLI generation call dispatches through.
  @TaskLocal public static var client: VinetasClient = .shared

  /// When `true`, commands skip their up-front model download (tests only).
  @TaskLocal public static var skipDownload = false

  /// Supplies the raw bytes for a `-r -` (stdin) reference. Defaults to
  /// reading the process's real standard input; tests override this so a
  /// `generate -r -` run doesn't block on (or depend on) the actual stdin
  /// file descriptor.
  @TaskLocal public static var stdinReferenceData: @Sendable () -> Data = {
    FileHandle.standardInput.readDataToEndOfFile()
  }
}

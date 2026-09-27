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

  /// The file descriptor CLI diagnostics go to: ``stderrPrint(_:)`` writes
  /// here, and ``StdoutGuard/begin()`` diverts fd 1 here while a command
  /// streams binary output to stdout. Always `STDERR_FILENO` in production.
  ///
  /// Tests bind a pipe's write end so they can observe "stderr" without
  /// `dup2`-ing over the process-wide fd 2. Replacing fd 2 is not atomic on
  /// Darwin: during `dup2(x, 2)` the slot is briefly reserved and a concurrent
  /// `write(2, …)` from another thread fails with `EBADF`, which
  /// `FileHandle.standardError.write(_:)` turns into an uncatchable
  /// `NSFileHandleOperationException` that aborts the whole test process.
  @TaskLocal public static var stderrDescriptor: Int32 = STDERR_FILENO
}

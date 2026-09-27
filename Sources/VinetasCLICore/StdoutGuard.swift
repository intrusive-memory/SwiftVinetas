import Foundation

#if canImport(Darwin)
  import Darwin
#endif

/// Keeps stdout byte-clean while a command streams binary data to it.
///
/// Libraries on the generate path (SwiftAcervo, SwiftTuberia, …) still call
/// bare `print(`. Between ``begin()`` and ``end()`` fd 1 points at stderr
/// (``CLIEnvironment/stderrDescriptor``), so that log output lands on stderr;
/// the command's payload goes to the real stdout through ``write(_:)``.
///
/// Both swaps hold the C `stdout` stream lock (`flockfile`) so no other
/// thread's `print` can interleave a partial flush with the descriptor swap.
/// `begin()` swaps *before* flushing, so anything still buffered in `stdout`
/// when the guard starts is diverted to stderr instead of polluting the
/// payload; `end()` flushes *before* swapping back for the same reason.
public enum StdoutGuard {
  /// Duplicate of the original fd 1, valid between `begin()` and `end()`.
  nonisolated(unsafe) private static var savedFD: Int32 = -1

  /// Redirect fd 1 to stderr, keeping a private handle to the real stdout.
  public static func begin() {
    guard savedFD < 0 else { return }
    flockfile(stdout)
    defer { funlockfile(stdout) }
    let saved = dup(STDOUT_FILENO)
    guard saved >= 0 else { return }
    savedFD = saved
    dup2(CLIEnvironment.stderrDescriptor, STDOUT_FILENO)
    fflush(stdout)
  }

  /// Write every byte of `data` to the real stdout.
  ///
  /// Loops on partial writes and retries on `EINTR`. Before `begin()` (or
  /// after `end()`) it writes to fd 1 directly.
  public static func write(_ data: Data) throws {
    let fd = savedFD >= 0 ? savedFD : STDOUT_FILENO
    if let errorCode = writeAll(data, to: fd) {
      throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
    }
  }

  /// Restore fd 1 to the original stdout.
  public static func end() {
    guard savedFD >= 0 else { return }
    flockfile(stdout)
    defer { funlockfile(stdout) }
    fflush(stdout)
    dup2(savedFD, STDOUT_FILENO)
    close(savedFD)
    savedFD = -1
  }
}

/// Write every byte of `data` to `fd`, looping on partial writes and retrying
/// on `EINTR`. Never raises.
///
/// - Returns: `nil` on success, or the `errno` of the first failed `write(2)`.
@discardableResult
func writeAll(_ data: Data, to fd: Int32) -> Int32? {
  data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int32? in
    guard var pointer = buffer.baseAddress else { return nil }
    var remaining = buffer.count
    while remaining > 0 {
      let written = Darwin.write(fd, pointer, remaining)
      if written < 0 {
        if errno == EINTR { continue }
        return errno
      }
      remaining -= written
      pointer = pointer.advanced(by: written)
    }
    return nil
  }
}

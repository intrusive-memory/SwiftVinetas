import Foundation

#if canImport(Darwin)
  import Darwin
#endif

/// Keeps stdout byte-clean while a command streams binary data to it.
///
/// Libraries on the generate path (SwiftAcervo, SwiftTuberia, …) still call
/// bare `print(`. Between ``begin()`` and ``end()`` fd 1 points at stderr, so
/// that log output lands on stderr; the command's payload goes to the real
/// stdout through ``write(_:)``.
public enum StdoutGuard {
  /// Duplicate of the original fd 1, valid between `begin()` and `end()`.
  nonisolated(unsafe) private static var savedFD: Int32 = -1

  /// Redirect fd 1 to stderr, keeping a private handle to the real stdout.
  public static func begin() {
    guard savedFD < 0 else { return }
    fflush(stdout)
    let saved = dup(STDOUT_FILENO)
    guard saved >= 0 else { return }
    savedFD = saved
    dup2(STDERR_FILENO, STDOUT_FILENO)
  }

  /// Write every byte of `data` to the real stdout.
  ///
  /// Loops on partial writes and retries on `EINTR`. Before `begin()` (or
  /// after `end()`) it writes to fd 1 directly.
  public static func write(_ data: Data) throws {
    let fd = savedFD >= 0 ? savedFD : STDOUT_FILENO
    try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      guard var pointer = buffer.baseAddress else { return }
      var remaining = buffer.count
      while remaining > 0 {
        let written = Darwin.write(fd, pointer, remaining)
        if written < 0 {
          if errno == EINTR { continue }
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        remaining -= written
        pointer = pointer.advanced(by: written)
      }
    }
  }

  /// Restore fd 1 to the original stdout.
  public static func end() {
    guard savedFD >= 0 else { return }
    fflush(stdout)
    dup2(savedFD, STDOUT_FILENO)
    close(savedFD)
    savedFD = -1
  }
}

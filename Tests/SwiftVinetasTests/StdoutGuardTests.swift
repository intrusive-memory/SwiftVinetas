import Foundation
import Testing

@testable import VinetasCLICore

// MARK: - StdioCapture

/// Captures what a (possibly async) body writes to stdout and to CLI stderr.
///
/// **Why it never touches fd 2.** `dup2(x, 2)` is not atomic on Darwin: while
/// the old file is closed the fd slot is reserved, and a concurrent
/// `write(2, …)` on another thread fails with `EBADF`.
/// `FileHandle.standardError.write(_:)` — used by the library and its
/// dependencies — turns that into an uncatchable
/// `NSFileHandleOperationException` that aborts the whole xctest process (seen
/// as `-[_NSStdIOFileHandle writeData:]: Bad file descriptor`). Swift Testing
/// runs suites in parallel, so *any* `dup2` onto fd 2 races every other
/// suite's stderr logging. Instead, "stderr" is captured by binding
/// ``CLIEnvironment/stderrDescriptor`` to a pipe: `stderrPrint` writes there
/// and `StdoutGuard.begin()` diverts fd 1 there, exactly as it diverts to fd 2
/// in production.
///
/// **fd 1 is genuinely redirected**, because stdout purity is what's under
/// test. Nothing in this process writes fd 1 through `FileHandle` (only C
/// stdio, which reports `EBADF` as a stream error rather than raising), so
/// the `dup2` race on fd 1 can drop a concurrent suite's print but can't
/// crash the process. Invariants:
/// - one capture at a time process-wide, via an async mutex held across the
///   body's `await`s (a blocking lock can't be held across suspension);
/// - fd 1 is only ever *replaced* with `dup2` (never closed), under the
///   `stdout` stream lock so no other thread's stdio flush interleaves;
/// - pipe write ends are closed only after fd 1 is restored and the body has
///   finished, so no writer ever holds a closed descriptor;
/// - both pipes are drained on background threads, so a noisy parallel suite
///   can't fill a pipe buffer and deadlock the window.
///
/// Parallel suites' `print` output that happens to flush inside the window can
/// land in the stdout pipe outside a `StdoutGuard` span, so callers that
/// don't hold the guard for the whole body should assert with "contains".
enum StdioCapture {
  struct Result {
    var stdout: Data
    var stderr: Data
  }

  private static let mutex = AsyncMutex()

  static func run(_ body: () async throws -> Void) async throws -> Result {
    await mutex.lock()
    do {
      let result = try await locked(body)
      await mutex.unlock()
      return result
    } catch {
      await mutex.unlock()
      throw error
    }
  }

  private static func locked(_ body: () async throws -> Void) async throws -> Result {
    var outPipe: [Int32] = [-1, -1]
    var errPipe: [Int32] = [-1, -1]
    guard pipe(&outPipe) == 0 else { throw POSIXError(.EMFILE) }
    guard pipe(&errPipe) == 0 else {
      close(outPipe[0])
      close(outPipe[1])
      throw POSIXError(.EMFILE)
    }
    let outReader = PipeReader(fd: outPipe[0])
    let errReader = PipeReader(fd: errPipe[0])

    // Swap fd 1. Flush first so bytes the runner already buffered go to the
    // real stdout, not the pipe.
    flockfile(stdout)
    fflush(stdout)
    let savedOut = dup(STDOUT_FILENO)
    dup2(outPipe[1], STDOUT_FILENO)
    funlockfile(stdout)

    var bodyError: Error?
    do {
      try await CLIEnvironment.$stderrDescriptor.withValue(errPipe[1]) {
        try await body()
      }
    } catch {
      bodyError = error
    }

    // A guard left open would keep a dup of the stdout pipe alive and the
    // reader would never see EOF. (No-op when the body ended it.)
    StdoutGuard.end()

    // Restore fd 1 *without* flushing: anything a parallel suite buffered
    // after the body finished belongs to the real stdout.
    flockfile(stdout)
    dup2(savedOut, STDOUT_FILENO)
    funlockfile(stdout)
    close(savedOut)
    // Only now drop our write ends, so both readers see EOF.
    close(outPipe[1])
    close(errPipe[1])

    let result = Result(stdout: outReader.finish(), stderr: errReader.finish())
    if let bodyError { throw bodyError }
    return result
  }
}

/// A FIFO mutex that can be held across `await`.
actor AsyncMutex {
  private var isLocked = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func lock() async {
    guard isLocked else {
      isLocked = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func unlock() {
    if waiters.isEmpty {
      isLocked = false
    } else {
      // Ownership passes directly to the next waiter; `isLocked` stays true.
      waiters.removeFirst().resume()
    }
  }
}

/// Drains a pipe's read end on a background thread until EOF.
private final class PipeReader: @unchecked Sendable {
  private let fd: Int32
  private var data = Data()
  private let done = DispatchSemaphore(value: 0)

  init(fd: Int32) {
    self.fd = fd
    let thread = Thread { [self] in
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        let n = read(fd, &buffer, buffer.count)
        if n > 0 {
          data.append(buffer, count: n)
        } else if n < 0 && errno == EINTR {
          continue
        } else {
          break
        }
      }
      close(fd)
      done.signal()
    }
    // `finish()` blocks the (user-initiated) test task on this thread; run the
    // reader at a QoS at least as high to avoid a priority inversion.
    thread.qualityOfService = .userInteractive
    thread.start()
  }

  func finish() -> Data {
    done.wait()
    return data
  }
}

// MARK: - StdoutGuardTests

@Suite("StdoutGuard", .serialized)
struct StdoutGuardTests {

  private func marker(_ label: String) -> String {
    "STDOUTGUARD-\(label)-\(UUID().uuidString)"
  }

  @Test("after begin(), print lands on stderr, not stdout")
  func printGoesToStderrWhileGuarded() async throws {
    let text = marker("PRINT")
    let result = try await StdioCapture.run {
      StdoutGuard.begin()
      print(text)
      fflush(stdout)
      StdoutGuard.end()
    }
    #expect(result.stderr.range(of: Data(text.utf8)) != nil)
    #expect(result.stdout.range(of: Data(text.utf8)) == nil)
  }

  @Test("write(_:) sends raw bytes to the real stdout")
  func writeGoesToRealStdout() async throws {
    // 0x89 is the PNG signature's first byte; the UUID tail makes the payload
    // unique so noise from parallel suites can't produce a false match.
    let payload = Data([0x89]) + Data(marker("BIN").utf8)
    let result = try await StdioCapture.run {
      StdoutGuard.begin()
      try StdoutGuard.write(payload)
      StdoutGuard.end()
    }
    #expect(result.stdout.range(of: payload) != nil)
    #expect(result.stderr.range(of: payload) == nil)
  }

  @Test("after end(), stdout is restored")
  func endRestoresStdout() async throws {
    let during = marker("DURING")
    let after = marker("AFTER")
    let result = try await StdioCapture.run {
      StdoutGuard.begin()
      print(during)
      StdoutGuard.end()
      print(after)
      fflush(stdout)
    }
    #expect(result.stdout.range(of: Data(after.utf8)) != nil)
    #expect(result.stderr.range(of: Data(after.utf8)) == nil)
    #expect(result.stderr.range(of: Data(during.utf8)) != nil)
  }
}

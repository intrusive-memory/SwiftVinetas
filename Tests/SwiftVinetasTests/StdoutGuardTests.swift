import Foundation
import Testing

@testable import VinetasCLICore

// MARK: - StdioCapture

/// Swaps fds 1 and 2 for pipes around `body` and returns what each received.
///
/// fd swapping is process-global and Swift Testing runs suites in parallel,
/// so this is shared test infrastructure:
/// - every capture in the test process takes `lock`, so two capturing suites
///   never overlap their redirection windows;
/// - the original fds are restored in a `defer`, even when `body` throws;
/// - both pipes are drained on background threads, so a noisy parallel suite
///   can't fill a pipe buffer and deadlock the window.
///
/// Output from *non-capturing* suites that happens to land inside the window
/// is swallowed into the pipes. Callers must therefore assert on unique
/// markers with "contains" / "does not contain", never on exact equality.
enum StdioCapture {
  struct Result {
    var stdout: Data
    var stderr: Data
  }

  private static let lock = NSLock()

  static func run(_ body: () throws -> Void) throws -> Result {
    lock.lock()
    defer { lock.unlock() }

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

    // Tight window: flush what the runner already buffered, swap, run, flush, restore.
    fflush(stdout)
    fflush(stderr)
    let savedOut = dup(STDOUT_FILENO)
    let savedErr = dup(STDERR_FILENO)
    dup2(outPipe[1], STDOUT_FILENO)
    dup2(errPipe[1], STDERR_FILENO)
    // fds 1/2 now hold the write ends; drop ours so EOF arrives on restore.
    close(outPipe[1])
    close(errPipe[1])

    do {
      defer {
        // A guard left open would keep a dup of the stdout pipe alive and
        // the reader would never see EOF.
        StdoutGuard.end()
        fflush(stdout)
        fflush(stderr)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut)
        close(savedErr)
      }
      try body()
    }

    return Result(stdout: outReader.finish(), stderr: errReader.finish())
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
  func printGoesToStderrWhileGuarded() throws {
    let text = marker("PRINT")
    let result = try StdioCapture.run {
      StdoutGuard.begin()
      print(text)
      fflush(stdout)
      StdoutGuard.end()
    }
    #expect(result.stderr.range(of: Data(text.utf8)) != nil)
    #expect(result.stdout.range(of: Data(text.utf8)) == nil)
  }

  @Test("write(_:) sends raw bytes to the real stdout")
  func writeGoesToRealStdout() throws {
    // 0x89 is the PNG signature's first byte; the UUID tail makes the payload
    // unique so noise from parallel suites can't produce a false match.
    let payload = Data([0x89]) + Data(marker("BIN").utf8)
    let result = try StdioCapture.run {
      StdoutGuard.begin()
      try StdoutGuard.write(payload)
      StdoutGuard.end()
    }
    #expect(result.stdout.range(of: payload) != nil)
    #expect(result.stderr.range(of: payload) == nil)
  }

  @Test("after end(), stdout is restored")
  func endRestoresStdout() throws {
    let during = marker("DURING")
    let after = marker("AFTER")
    let result = try StdioCapture.run {
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

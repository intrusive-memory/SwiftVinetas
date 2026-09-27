import Flux2Core
import Foundation
import Testing

// MARK: - Flux2StderrTests (Sortie 16, reduced)
//
// Regression test for the flux-2-swift-mlx 3.4.3 stderr fix: Flux2Debug.log
// (and every other bare `print(` in Flux2Core / FluxTextEncoders) is now
// routed to stderr via a module-scope `print` shadow
// (`Sources/Flux2Core/Utils/StderrPrint.swift`), so it never corrupts a raw
// PNG streamed on stdout by `vinetas generate -o -`.
//
// Capture is done exclusively through the async, lock-guarded `StdioCapture`
// helper declared in `StdoutGuardTests.swift` (same test target). It is the
// only permitted way to capture stdout in this suite — swapping fd 2
// in-process crashed the test process in an earlier sortie (see
// `StdioCapture`'s doc comment: `dup2` onto fd 2 races concurrent stderr
// writers under Swift Testing's parallel suite execution).
//
// Stderr-side note: `StdioCapture`'s "stderr" pipe is fed only by
// `CLIEnvironment.stderrDescriptor`, which `stderrPrint` (VinetasCLICore)
// writes to. Flux2Core's `print` shadow writes directly to
// `FileHandle.standardError` — real fd 2 — which `StdioCapture` never
// touches (that's the whole point: it avoids the fd-2 swap that crashed the
// process). So there is no safe, in-process way to observe Flux2Debug's
// stderr output without swapping fd 2 ourselves, which is forbidden. This
// suite therefore asserts only the stdout side and skips the stderr
// assertion, as the sortie plan allows.
@Suite("Flux2StderrTests", .serialized)
struct Flux2StderrTests {

  @Test("Flux2Debug.log never reaches stdout")
  func logDoesNotReachStdout() async throws {
    let marker = "FLUX2STDERR-PROBE-\(UUID().uuidString)"

    let wasEnabled = Flux2Debug.enabled
    Flux2Debug.enabled = true
    defer { Flux2Debug.enabled = wasEnabled }

    let result = try await StdioCapture.run {
      Flux2Debug.log(marker)
    }

    #expect(result.stdout.range(of: Data(marker.utf8)) == nil)
  }
}

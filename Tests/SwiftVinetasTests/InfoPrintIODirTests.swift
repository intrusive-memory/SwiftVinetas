import Foundation
import SwiftAcervo
import Testing

@testable import VinetasCLICore

// MARK: - `vinetas info --print-io-dir`
//
// Gated on the App Group container actually resolving (`.enabled(if:)`)
// rather than pointed at a temp directory via `ACERVO_MODELS_DIR`: that
// override is a *process-wide* environment variable, and Swift Testing runs
// suites concurrently, so mutating it here could race any other suite that
// resolves an Acervo path mid-test. On the machines that build SwiftVinetas
// (`make link-test-models` / an entitled shell), `ACERVO_APP_GROUP_ID` is
// already exported, so this exercises the real resolution path. See
// `Info.resolveIODirectory` — the path computation is a pure function
// separate from the `print` in `run()`, so it's testable without touching
// stdio (StdioCapture is reserved for the stdout-purity assertion below).

@Suite("Info --print-io-dir")
struct InfoPrintIODirTests {

  @Test(
    "resolveIODirectory returns a path ending in /vinetas-io and creates it",
    .enabled(if: Acervo.resolvedSharedModelsDirectory != nil)
  )
  func resolvesAndCreatesDirectory() throws {
    let ioDirectory = try Info.resolveIODirectory()

    let path = ioDirectory.path
    let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
    #expect(trimmed.hasSuffix("/vinetas-io"))

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    #expect(exists)
    #expect(isDirectory.boolValue)
  }

  @Test(
    "resolveIODirectory sits beside SharedModels, not inside it",
    .enabled(if: Acervo.resolvedSharedModelsDirectory != nil)
  )
  func sitsAlongsideSharedModels() throws {
    let sharedModels = try #require(Acervo.resolvedSharedModelsDirectory)
    let ioDirectory = try Info.resolveIODirectory()

    #expect(ioDirectory.deletingLastPathComponent() == sharedModels.deletingLastPathComponent())
    #expect(ioDirectory != sharedModels)
  }

  @Test(
    "resolveIODirectory is idempotent — a second call succeeds on an existing directory",
    .enabled(if: Acervo.resolvedSharedModelsDirectory != nil)
  )
  func idempotent() throws {
    _ = try Info.resolveIODirectory()
    let second = try Info.resolveIODirectory()
    #expect(FileManager.default.fileExists(atPath: second.path))
  }

  @Test(
    "info --print-io-dir prints only the path, nothing else, to stdout",
    .enabled(if: Acervo.resolvedSharedModelsDirectory != nil)
  )
  func commandPrintsPathAlone() async throws {
    let expected = try Info.resolveIODirectory()

    let result = try await StdioCapture.run {
      var command = try Info.parse(["--print-io-dir"])
      try await command.run()
    }

    let stdout = String(decoding: result.stdout, as: UTF8.self)
    #expect(stdout == expected.path + "\n")
    #expect(!stdout.contains("Model:"))
  }
}

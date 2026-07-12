// VinetasBackgroundDownloads.swift
// SwiftVinetas
//
// iOS background model downloads — SwiftVinetas layer (SwiftAcervo #81).
//
// SwiftVinetas is the middle layer: it maps a logical "model" (which may be
// several SwiftAcervo components/repos) onto SwiftAcervo's background download
// API and re-exposes progress/completion as an escaping observation stream that
// is authoritative across app suspension/relaunch.
//
// This is the additive iOS path (SV-R1/R2). The existing
// `VinetasClient.download(model:progress:)` — the foreground/macOS `async throws`
// call — is unchanged (SV-R3). All of this is `#if os(iOS)`.

#if os(iOS)

  import Foundation
  import SwiftAcervo

  /// A background download event surfaced to SwiftVinetas consumers.
  ///
  /// A 1:1 mapping of `SwiftAcervo.BackgroundDownloadEvent`, re-declared here so
  /// app-side consumers don't need to import SwiftAcervo. Events are keyed by the
  /// SwiftAcervo `repoId` a file belongs to (one model = one or more repos).
  public enum VinetasDownloadEvent: Sendable, Equatable {
    /// Byte progress for the file currently downloading under `repoId`.
    case progress(repoId: String, file: String, fraction: Double)
    /// A file was delivered, integrity-verified, and installed.
    case fileVerified(repoId: String, file: String)
    /// A file failed terminally (integrity mismatch or transport error).
    case fileFailed(repoId: String, file: String, reason: String)
    /// Every tracked file for `repoId` is now verified.
    case repoCompleted(repoId: String)

    init(_ event: BackgroundDownloadEvent) {
      switch event {
      case .progress(let repoId, let file, let fraction):
        self = .progress(repoId: repoId, file: file, fraction: fraction)
      case .fileVerified(let repoId, let file):
        self = .fileVerified(repoId: repoId, file: file)
      case .fileFailed(let repoId, let file, let reason):
        self = .fileFailed(repoId: repoId, file: file, reason: reason)
      case .repoCompleted(let repoId):
        self = .repoCompleted(repoId: repoId)
      }
    }
  }

  extension VinetasClient {

    /// Enqueues every component of `model` for **iOS background download** and
    /// returns as soon as the tasks are handed to the OS — the transfers
    /// continue while the app is suspended and complete even across a relaunch.
    ///
    /// This is intentionally *not* an `async`-until-complete call: completion may
    /// arrive in a later process launch, so observe ``backgroundDownloadEvents``
    /// (authoritative across relaunch) rather than awaiting this. The engine
    /// routes each component to the correct SwiftAcervo entry point —
    /// component-addressed models (PixArt) via
    /// `enqueueBackgroundDownloadComponent`, repo-addressed models (FLUX.2) via
    /// `enqueueBackgroundDownload(modelId:)`.
    ///
    /// - Throws: `VinetasError.modelNotSupported` / `.downloadFailed`, or
    ///   SwiftAcervo hydration/manifest errors while enqueuing.
    public func startBackgroundDownload(model: any ModelDescriptor) async throws {
      let engine = try await router.engine(for: model)
      try await engine.enqueueBackgroundDownload(model)
    }

    /// The authoritative stream of background download events across all
    /// in-flight models, survivable across app relaunch. **Single-consumer** —
    /// iterate it from one place (mirrors SwiftAcervo's stream contract).
    public var backgroundDownloadEvents: AsyncStream<VinetasDownloadEvent> {
      let source = Acervo.backgroundDownloadEvents
      return AsyncStream { continuation in
        let task = Task {
          for await event in source {
            continuation.yield(VinetasDownloadEvent(event))
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }

#endif

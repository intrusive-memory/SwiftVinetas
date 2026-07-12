// VinetasBackgroundDownloads.swift
// SwiftVinetas
//
// iOS background model downloads — SwiftVinetas layer (SwiftAcervo #81).
//
// SwiftVinetas is the middle layer: it maps a logical "model" (which may be
// several SwiftAcervo components/repos) onto SwiftAcervo's background download
// API and re-exposes progress/completion as escaping observation streams that
// are authoritative across app suspension/relaunch.
//
// SwiftAcervo's `backgroundDownloadEvents` is a single-consumer stream keyed by
// `repoId`. `BackgroundDownloadHub` consumes it once and fans out to any number
// of subscribers (SV-R5), which lets both a global observer and per-model
// aggregators run at the same time. Per-model streams resolve the model's
// `repoId`s (via the engine) and aggregate the repo-keyed events into a single
// model-level progress/completion.
//
// The existing foreground `download(model:progress:)` (macOS + foreground) is
// unchanged (SV-R3). All of this is `#if os(iOS)`.

#if os(iOS)

  import Foundation
  import SwiftAcervo

  /// A repo-keyed background download event (1:1 with
  /// `SwiftAcervo.BackgroundDownloadEvent`, re-declared so app consumers don't
  /// import SwiftAcervo). One model spans one or more repos.
  public enum VinetasDownloadEvent: Sendable, Equatable {
    case progress(repoId: String, file: String, fraction: Double)
    case fileVerified(repoId: String, file: String)
    case fileFailed(repoId: String, file: String, reason: String)
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

  /// A model-level background download event, aggregated across all of a model's
  /// repos. This is what UI flows observe: one smooth progress fraction, one
  /// completion, one failure.
  public enum VinetasModelDownloadEvent: Sendable, Equatable {
    /// Aggregate progress across the model's repos, 0...1.
    case progress(fraction: Double)
    /// Every repo of the model is verified and installed.
    case completed
    /// A file in one of the model's repos failed terminally.
    case failed(reason: String)
  }

  /// Fan-out multiplexer over SwiftAcervo's single-consumer background event
  /// stream (SV-R5). Consumes the source once; broadcasts to N subscribers.
  actor BackgroundDownloadHub {
    static let shared = BackgroundDownloadHub()

    private var subscribers: [UUID: AsyncStream<VinetasDownloadEvent>.Continuation] = [:]
    private var pump: Task<Void, Never>?

    /// A fresh subscription to the shared event stream. Safe to call many times.
    func subscribe() -> AsyncStream<VinetasDownloadEvent> {
      ensurePump()
      let id = UUID()
      let (stream, continuation) = AsyncStream<VinetasDownloadEvent>.makeStream()
      subscribers[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.remove(id) }
      }
      return stream
    }

    private func remove(_ id: UUID) { subscribers[id] = nil }

    private func broadcast(_ event: VinetasDownloadEvent) {
      for continuation in subscribers.values { continuation.yield(event) }
    }

    private func ensurePump() {
      guard pump == nil else { return }
      pump = Task { [weak self] in
        for await event in Acervo.backgroundDownloadEvents {
          await self?.broadcast(VinetasDownloadEvent(event))
        }
      }
    }
  }

  extension VinetasClient {

    /// Enqueues every component of `model` for **iOS background download** and
    /// returns as soon as the tasks are handed to the OS — transfers continue
    /// while the app is suspended and complete even across a relaunch.
    ///
    /// Not an `async`-until-complete call. Observe ``backgroundModelEvents(for:)``
    /// (model-level) or ``backgroundDownloadEvents`` (repo-level) for
    /// progress/completion, both authoritative across relaunch.
    ///
    /// - Throws: `VinetasError.modelNotSupported` / `.downloadFailed`, or
    ///   SwiftAcervo hydration/manifest errors while enqueuing.
    public func startBackgroundDownload(model: any ModelDescriptor) async throws {
      let engine = try await router.engine(for: model)
      try await engine.enqueueBackgroundDownload(model)
    }

    /// The repo-level stream of background events across all in-flight models.
    /// Multi-consumer safe (fanned out via ``BackgroundDownloadHub``).
    public var backgroundDownloadEvents: AsyncStream<VinetasDownloadEvent> {
      AsyncStream { continuation in
        let task = Task {
          for await event in await BackgroundDownloadHub.shared.subscribe() {
            continuation.yield(event)
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }

    /// A **model-level** background download stream: one aggregate progress
    /// fraction, one `.completed`, one `.failed`, across all of `model`'s repos.
    ///
    /// Resolves the model's repos via the engine (call **after**
    /// ``startBackgroundDownload(model:)`` so components are hydrated). If the
    /// model has no resolvable repos, the stream finishes immediately.
    public func backgroundModelEvents(
      for model: any ModelDescriptor
    ) async -> AsyncStream<VinetasModelDownloadEvent> {
      let engine = try? await router.engine(for: model)
      let repoIds = Set(await engine?.backgroundDownloadRepoIds(model) ?? [])

      return AsyncStream { continuation in
        guard !repoIds.isEmpty else {
          continuation.finish()
          return
        }
        let task = Task {
          var fractions = Dictionary(uniqueKeysWithValues: repoIds.map { ($0, 0.0) })
          var completed = Set<String>()
          func aggregate() -> Double {
            fractions.values.reduce(0, +) / Double(repoIds.count)
          }
          for await event in await BackgroundDownloadHub.shared.subscribe() {
            switch event {
            case .progress(let repo, _, let fraction) where repoIds.contains(repo):
              fractions[repo] = fraction
              continuation.yield(.progress(fraction: aggregate()))
            case .repoCompleted(let repo) where repoIds.contains(repo):
              completed.insert(repo)
              fractions[repo] = 1.0
              if completed == repoIds {
                continuation.yield(.completed)
                continuation.finish()
                return
              }
              continuation.yield(.progress(fraction: aggregate()))
            case .fileFailed(let repo, _, let reason) where repoIds.contains(repo):
              continuation.yield(.failed(reason: reason))
              continuation.finish()
              return
            default:
              break
            }
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }

#endif

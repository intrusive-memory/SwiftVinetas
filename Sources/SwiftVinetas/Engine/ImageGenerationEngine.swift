import Foundation
import SwiftAcervo

/// A protocol that every generation backend must conform to.
///
/// The engine receives fully-composed prompts and renders images.
/// It does not know about characters, trigger words, or prompt composition --
/// those are orchestrator-level concerns handled by `VinetasClient`.
///
/// Sync query methods (`supports`, `isAvailable`, `validateMemory`)
/// are `nonisolated` since they only read static or filesystem state.
/// `diskSize(of:)` is `async` because it may need to acquire a SwiftAcervo
/// `withComponentAccess` scope (path-agnostic file resolution requires async).
/// Async lifecycle and generation methods are actor-isolated in conforming actors.
public protocol ImageGenerationEngine: Sendable {

  // MARK: - Identity

  /// Unique identifier for this engine (e.g., "flux2", "pixart-sigma").
  var engineID: String { get }

  // MARK: - Model Catalog

  /// All models this engine can run.
  var supportedModels: [any ModelDescriptor] { get }

  // MARK: - Capabilities

  /// Returns whether this engine supports the given feature.
  func supports(_ feature: EngineFeature) -> Bool

  // MARK: - Lifecycle

  /// Load a model into memory, ready for generation.
  ///
  /// Engines manage their own multi-phase loading internally
  /// (e.g., text encoder then transformer for FLUX.2).
  ///
  /// - Parameters:
  ///   - model: The model descriptor to load.
  ///   - progress: A callback reporting load progress phases and fractions.
  func loadModel(
    _ model: any ModelDescriptor,
    progress: @escaping @Sendable (LoadProgress) -> Void
  ) async throws

  /// Unload the current model, freeing memory.
  func unloadModel() async

  // MARK: - Generation

  /// Generate one image from a fully-composed prompt.
  ///
  /// The engine receives the final prompt string -- it does not know about
  /// characters, trigger words, or style composition.
  ///
  /// - Parameters:
  ///   - request: The generation request containing prompt, dimensions, and mode.
  ///   - stepProgress: Optional callback reporting (currentStep, totalSteps, elapsedTime).
  /// - Returns: The generation result containing the image and metadata.
  func generate(
    request: GenerationRequest,
    stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
  ) async throws -> GenerationResult

  // MARK: - LoRA

  /// Load a LoRA adapter. The engine applies it to whichever internal layers
  /// are appropriate for its architecture.
  ///
  /// - Parameters:
  ///   - path: Path to the LoRA safetensors file.
  ///   - scale: LoRA scale factor (typically 0.0--1.0).
  func loadLoRA(at path: URL, scale: Float) async throws

  /// Remove the currently loaded LoRA adapter.
  func unloadLoRA() async

  // MARK: - Model Management

  /// Download model weights to local storage.
  ///
  /// - Parameters:
  ///   - model: The model descriptor to download.
  ///   - progress: A callback reporting download progress.
  func download(
    _ model: any ModelDescriptor,
    progress: @Sendable (DownloadProgress) -> Void
  ) async throws

  #if os(iOS)
    /// Enqueue every component of `model` for **iOS background download**
    /// (SwiftAcervo #81), returning once the tasks are handed to the OS.
    ///
    /// A default implementation throws ``VinetasError/modelNotSupported`` — only
    /// engines that support background downloads (PixArt, FLUX.2) override it.
    /// The engine is responsible for routing each component to the correct
    /// SwiftAcervo entry point (component- vs repo-addressed).
    func enqueueBackgroundDownload(_ model: any ModelDescriptor) async throws
  #endif

  /// Check whether a model's weights are available on disk.
  ///
  /// `async` because conforming engines defer to
  /// `Acervo.availability(_:)`, which is async — see
  /// `ModelAvailability` for the four-state value (`.available`,
  /// `.downloading(progress:)`, `.partial(missing:)`, `.notAvailable`).
  /// Engines collapse those to `Bool` here; UI consumers wanting the full
  /// state should use ``availability(_:)`` (or
  /// ``VinetasClient/availability(model:)``).
  func isAvailable(_ model: any ModelDescriptor) async -> Bool

  /// Four-state availability for the given model, aggregated across every
  /// component the model declares.
  ///
  /// Engines that download a model as a single repo (e.g. ``Flux2Engine``)
  /// delegate to ``SwiftAcervo/Acervo/availability(_:)`` per component and
  /// aggregate the results. Engines that compose multiple repos into one
  /// logical model (e.g. ``PixArtEngine``) walk `model.componentIds`,
  /// resolve each to its `repoId`, query Acervo per repo, and aggregate.
  ///
  /// Aggregation rules (mirror ``SwiftAcervo/AvailabilityAggregator``):
  /// - All components `.available` → `.available`
  /// - Any component `.downloading(p)` → `.downloading(weightedAvg)` with
  ///   `.available` components contributing `1.0` and others contributing
  ///   their reported progress (or `0.0`).
  /// - Some components `.available` and some not (and none downloading) →
  ///   `.partial(missing: <componentIds>)`
  /// - Otherwise → `.notAvailable`
  ///
  /// Default implementation synthesizes the result from ``isAvailable(_:)``
  /// so existing engine implementations compile without change; conforming
  /// engines should override this to expose `.downloading` and `.partial`.
  func availability(_ model: any ModelDescriptor) async -> ModelAvailability

  /// Delete a model's weights from local storage.
  func delete(_ model: any ModelDescriptor) async throws

  /// Returns the disk size in bytes of a downloaded model, or nil if not downloaded.
  ///
  /// `async` because conforming engines may need to acquire a SwiftAcervo
  /// `withComponentAccess` scope to resolve component file paths.
  func diskSize(of model: any ModelDescriptor) async -> Int64?

  /// Validate whether the current system has enough memory to run the given model.
  func validateMemory(for model: any ModelDescriptor) -> MemoryValidation

  // MARK: - Telemetry

  /// Install (or clear) the telemetry reporter for engine-scoped Vinetas events
  /// (e.g. `concurrencyGateRejected`, `modelLoadStart`/`Complete`, `modelUnload`,
  /// `loraAttachStart`/`Complete`, `errorThrown(phase:)` for engine-internal
  /// throws).
  ///
  /// Per REQUIREMENTS §5.3, the override **only** stores the reporter — it must
  /// NOT bridge `Flux2TelemetryEvent` / `PixArtTelemetryEvent` into the Vinetas
  /// schema; the host wires those dep reporters directly. Default
  /// implementation is a no-op so engines without Vinetas-scope events compile
  /// without changes.
  func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async
}

extension ImageGenerationEngine {
  public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
    // No-op default — engines override to store the reporter for their own
    // emission sites. See REQUIREMENTS §5.3.
  }

  /// Default implementation synthesizes a two-state result from
  /// ``isAvailable(_:)``. Engines that compose multiple Acervo repos should
  /// override this to expose `.downloading(progress:)` and
  /// `.partial(missing:)`.
  public func availability(_ model: any ModelDescriptor) async -> ModelAvailability {
    await isAvailable(model) ? .available : .notAvailable
  }
}

#if os(iOS)
  extension ImageGenerationEngine {
    /// Default: background download is unsupported. Engines that support it
    /// (PixArt, FLUX.2) override this; others (and test mocks) inherit the throw.
    public func enqueueBackgroundDownload(_ model: any ModelDescriptor) async throws {
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: "background-download")
    }
  }
#endif

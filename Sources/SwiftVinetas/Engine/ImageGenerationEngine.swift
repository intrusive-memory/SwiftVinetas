import Foundation

/// A protocol that every generation backend must conform to.
///
/// The engine receives fully-composed prompts and renders images.
/// It does not know about characters, trigger words, or prompt composition --
/// those are orchestrator-level concerns handled by `VinetasClient`.
///
/// Sync query methods (`supports`, `isAvailable`, `validateMemory`, `diskSize`)
/// are `nonisolated` since they only read static or filesystem state.
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
    progress: @Sendable (LoadProgress) -> Void
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

  /// Check whether a model's weights are available on disk.
  func isAvailable(_ model: any ModelDescriptor) -> Bool

  /// Delete a model's weights from local storage.
  func delete(_ model: any ModelDescriptor) async throws

  /// Returns the disk size in bytes of a downloaded model, or nil if not downloaded.
  func diskSize(of model: any ModelDescriptor) -> Int64?

  /// Validate whether the current system has enough memory to run the given model.
  func validateMemory(for model: any ModelDescriptor) -> MemoryValidation
}

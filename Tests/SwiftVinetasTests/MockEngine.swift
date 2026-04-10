import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - MockModelDescriptor

/// A simple model descriptor for testing purposes.
struct MockModelDescriptor: ModelDescriptor {
  let id: String
  let displayName: String
  let engineID: String
  let license: ModelLicense
  let minimumMemoryGB: Int
  let approximateDownloadSize: String
  let defaultSteps: Int
  let defaultGuidance: Float
  let supportedAspectRatios: [AspectRatio]
  let estimatedSecondsPerImage: Int
  let componentIds: [String]

  /// A convenience initializer with sensible defaults for testing.
  init(
    id: String = "mock-model",
    displayName: String = "Mock Model",
    engineID: String = "mock",
    license: ModelLicense = .apache2,
    minimumMemoryGB: Int = 8,
    approximateDownloadSize: String = "~1 GB",
    defaultSteps: Int = 10,
    defaultGuidance: Float = 3.0,
    supportedAspectRatios: [AspectRatio] = AspectRatio.allCases,
    estimatedSecondsPerImage: Int = 5,
    componentIds: [String] = []
  ) {
    self.id = id
    self.displayName = displayName
    self.engineID = engineID
    self.license = license
    self.minimumMemoryGB = minimumMemoryGB
    self.approximateDownloadSize = approximateDownloadSize
    self.defaultSteps = defaultSteps
    self.defaultGuidance = defaultGuidance
    self.supportedAspectRatios = supportedAspectRatios
    self.estimatedSecondsPerImage = estimatedSecondsPerImage
    self.componentIds = componentIds
  }
}

// MARK: - MockEngine

/// A mock ``ImageGenerationEngine`` that records all method calls and returns
/// configurable canned results, per E12.3.
///
/// Use this in tests for the router, facade, and character logic
/// without loading real models.
actor MockEngine: ImageGenerationEngine {

  // MARK: - Identity

  nonisolated let engineID: String

  // MARK: - Model Catalog

  nonisolated let supportedModels: [any ModelDescriptor]

  // MARK: - Call Recording

  /// Records of method calls made to this engine.
  enum MethodCall: Equatable, Sendable {
    case supports(String)
    case loadModel(String)
    case unloadModel
    case generate(String)
    case loadLoRA(String, Float)
    case unloadLoRA
    case download(String)
    case isAvailable(String)
    case delete(String)
    case diskSize(String)
    case validateMemory(String)
  }

  /// All method calls recorded in order.
  private(set) var calls: [MethodCall] = []

  // MARK: - Configurable Results

  /// The set of features this mock engine supports.
  var supportedFeatures: Set<String> = ["textToImage"]

  /// The number of step-progress callbacks to fire during `generate`. Defaults to 0 (no callbacks).
  var generateStepCount: Int = 0

  /// The result to return from `generate(request:stepProgress:)`.
  var generateResult: GenerationResult?

  /// If non-nil, `generate` will throw this error.
  var generateError: Error?

  /// The value to return from `isAvailable(_:)`.
  /// Marked `nonisolated(unsafe)` because `isAvailable` is nonisolated per protocol.
  /// Set before concurrent access in test setup.
  nonisolated(unsafe) var isAvailableResult: Bool = false

  /// The value to return from `validateMemory(for:)`.
  /// Marked `nonisolated(unsafe)` because `validateMemory` is nonisolated per protocol.
  /// Set before concurrent access in test setup.
  nonisolated(unsafe) var validateMemoryResult: MemoryValidation = .ok

  /// The value to return from `diskSize(of:)`.
  /// Marked `nonisolated(unsafe)` because `diskSize` is nonisolated per protocol.
  /// Set before concurrent access in test setup.
  nonisolated(unsafe) var diskSizeResult: Int64?

  /// If non-nil, `download` will throw this error.
  /// Marked `nonisolated(unsafe)` because `download` is nonisolated async per protocol.
  /// Set before concurrent access in test setup.
  nonisolated(unsafe) var downloadError: Error?

  /// If non-nil, `loadModel` will throw this error.
  var loadModelError: Error?

  /// If non-nil, `loadLoRA` will throw this error.
  var loadLoRAError: Error?

  /// If non-nil, `delete` will throw this error.
  var deleteError: Error?

  /// Sets the number of step-progress callbacks to fire per `generate` call.
  func setGenerateStepCount(_ count: Int) {
    generateStepCount = count
  }

  // MARK: - Init

  init(
    engineID: String = "mock",
    supportedModels: [any ModelDescriptor] = [
      MockModelDescriptor()
    ]
  ) {
    self.engineID = engineID
    self.supportedModels = supportedModels
  }

  // MARK: - Capabilities

  nonisolated func supports(_ feature: EngineFeature) -> Bool {
    switch feature {
    case .textToImage:
      return true
    case .imageToImage:
      return false
    case .loraInference:
      return false
    case .loraTraining:
      return false
    case .promptUpsampling:
      return false
    }
  }

  // MARK: - Lifecycle

  func loadModel(
    _ model: any ModelDescriptor,
    progress: @Sendable (LoadProgress) -> Void
  ) async throws {
    calls.append(.loadModel(model.id))
    if let error = loadModelError {
      throw error
    }
    progress(LoadProgress(phase: "Loading", fraction: 0.5))
    progress(LoadProgress(phase: "Ready", fraction: 1.0))
  }

  func unloadModel() async {
    calls.append(.unloadModel)
  }

  // MARK: - Generation

  func generate(
    request: GenerationRequest,
    stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
  ) async throws -> GenerationResult {
    calls.append(.generate(request.prompt))
    if let error = generateError {
      throw error
    }
    // Fire step-progress callbacks if configured
    if generateStepCount > 0 {
      for step in 1...generateStepCount {
        let fraction = Double(step) / Double(generateStepCount)
        stepProgress?(step, generateStepCount, fraction)
      }
    }
    if let result = generateResult {
      return result
    }
    // Return a minimal 1x1 pixel result by default
    let image = MockEngine.create1x1Image()
    return GenerationResult(
      image: image,
      usedPrompt: request.prompt,
      seed: request.seed ?? 42,
      durationSeconds: 1.0,
      modelID: supportedModels.first?.id ?? "mock-model"
    )
  }

  // MARK: - LoRA

  func loadLoRA(at path: URL, scale: Float) async throws {
    calls.append(.loadLoRA(path.lastPathComponent, scale))
    if let error = loadLoRAError {
      throw error
    }
  }

  func unloadLoRA() async {
    calls.append(.unloadLoRA)
  }

  // MARK: - Model Management

  nonisolated func download(
    _ model: any ModelDescriptor,
    progress: @Sendable (DownloadProgress) -> Void
  ) async throws {
    // Note: nonisolated async, so we cannot record calls here
    // in the actor-isolated `calls` array without isolation.
    // For download testing, check downloadError.
    if let error = downloadError {
      throw error
    }
    progress(DownloadProgress(fraction: 0.5, message: "Downloading..."))
    progress(DownloadProgress(fraction: 1.0, message: "Done"))
  }

  nonisolated func isAvailable(_ model: any ModelDescriptor) -> Bool {
    return isAvailableResult
  }

  func delete(_ model: any ModelDescriptor) async throws {
    calls.append(.delete(model.id))
    if let error = deleteError {
      throw error
    }
  }

  nonisolated func diskSize(of model: any ModelDescriptor) -> Int64? {
    return diskSizeResult
  }

  nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation {
    return validateMemoryResult
  }

  // MARK: - Helpers

  /// Creates a minimal 1x1 pixel CGImage for testing.
  static func create1x1Image() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
      data: nil,
      width: 1,
      height: 1,
      bitsPerComponent: 8,
      bytesPerRow: 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
  }
}

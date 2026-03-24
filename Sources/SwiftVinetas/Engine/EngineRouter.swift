import Foundation

/// A registry that maps model descriptors to engine instances.
///
/// `EngineRouter` is the single point through which generation requests
/// are dispatched to the correct engine. It replaces the previous hardcoded
/// `VinetasModel` to `Flux2Pipeline` mapping in `VinetasPipeline`.
///
/// The router is an actor for safe concurrent access to the engine registry.
/// It is `Sendable` and safe to share across actors.
///
/// ## Usage
///
/// ```swift
/// let router = EngineRouter(engines: [Flux2Engine()])
/// let models = await router.allModels
/// let engine = try await router.engine(for: someModel)
/// ```
public actor EngineRouter {

  /// The registered engines, keyed by engine ID for O(1) lookup.
  private let enginesByID: [String: any ImageGenerationEngine]

  /// All registered engines.
  private let engines: [any ImageGenerationEngine]

  /// Initialize the router with one or more engine instances.
  ///
  /// Each engine's `engineID` must be unique. If duplicate IDs are provided,
  /// the last engine with that ID wins.
  ///
  /// - Parameter engines: The engines to register.
  public init(engines: [any ImageGenerationEngine]) {
    self.engines = engines
    var map: [String: any ImageGenerationEngine] = [:]
    for engine in engines {
      map[engine.engineID] = engine
    }
    self.enginesByID = map
  }

  // MARK: - Model Catalog

  /// All model descriptors across all registered engines, sorted by `displayName`.
  public var allModels: [any ModelDescriptor] {
    engines
      .flatMap { $0.supportedModels }
      .sorted { $0.displayName < $1.displayName }
  }

  // MARK: - Engine Lookup

  /// Returns the engine that owns the given model descriptor.
  ///
  /// Looks up the engine by the model's `engineID` property.
  ///
  /// - Parameter model: The model descriptor to resolve.
  /// - Returns: The engine that supports this model.
  /// - Throws: `VinetasError.engineNotFound` if no engine is registered
  ///           with the model's `engineID`.
  public func engine(for model: any ModelDescriptor) throws -> any ImageGenerationEngine {
    guard let engine = enginesByID[model.engineID] else {
      throw VinetasError.engineNotFound(engineID: model.engineID)
    }
    return engine
  }

  /// Returns the engine registered with the given engine ID.
  ///
  /// - Parameter engineID: The unique engine identifier to look up.
  /// - Returns: The engine registered with this ID.
  /// - Throws: `VinetasError.engineNotFound` if no engine is registered
  ///           with the given ID.
  public func engine(forEngineID engineID: String) throws -> any ImageGenerationEngine {
    guard let engine = enginesByID[engineID] else {
      throw VinetasError.engineNotFound(engineID: engineID)
    }
    return engine
  }
}

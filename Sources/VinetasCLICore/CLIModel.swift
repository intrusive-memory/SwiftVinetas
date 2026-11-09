import ArgumentParser
import Foundation
import SwiftVinetas

// MARK: - CLIModel

/// A `--model` value resolved to something the CLI can generate with.
///
/// The on-device models keep their short names (`klein4b`, `pixart-sigma`,
/// via the legacy ``VinetasModel`` enum); cloud models are addressed by their
/// full catalog id (`openai-gpt-image-2.5-flare`, `bfl-flux-2-pro`, …) and
/// resolve to a ``CloudModelDescriptor``. Every command that takes `--model`
/// goes through ``resolve(_:)`` so the accepted vocabulary — and the
/// "unknown model" message — is the same everywhere.
public struct CLIModel: Sendable {

  /// The descriptor handed to ``VinetasClient``.
  public let descriptor: any ModelDescriptor

  /// The legacy enum case for an on-device model; `nil` for a cloud model.
  /// `ProGate`, `Vinetas.download(model:)` and the storyboard planner still
  /// key on it.
  public let local: VinetasModel?

  /// The name the user typed (and the one printed back): the short name for
  /// on-device models, the full id for cloud models.
  public var name: String { local?.rawValue ?? descriptor.cliName }

  /// The cloud descriptor, when this model runs on a ``CloudProvider``.
  public var cloud: CloudModelDescriptor? { descriptor as? CloudModelDescriptor }

  /// `true` for API-key-backed models that never touch local weights.
  public var isCloud: Bool { cloud != nil }

  init(local: VinetasModel) {
    self.local = local
    self.descriptor = local.descriptor
  }

  init(cloud: CloudModelDescriptor) {
    self.local = nil
    self.descriptor = cloud
  }

  /// FLUX.2 Klein 4B (on-device, Pro-gated).
  public static let klein4b = CLIModel(local: .klein4b)

  /// PixArt-Sigma XL (on-device, free).
  public static let pixartSigma = CLIModel(local: .pixartSigma)

  /// Resolve a `--model` value: on-device short names first, then any cloud
  /// model id from ``CloudModelDescriptor/all``.
  public static func resolve(_ name: String) -> CLIModel? {
    if let local = VinetasModel(rawValue: name) { return CLIModel(local: local) }
    if let cloud = CloudModelDescriptor.byID[name] { return CLIModel(cloud: cloud) }
    return nil
  }

  /// The on-device names (`klein4b`, `pixart-sigma`).
  public static var localNames: [String] { VinetasModel.allCases.map(\.rawValue) }

  /// Every cloud model id, in provider → model order.
  public static var cloudNames: [String] { CloudModelDescriptor.all.map(\.id) }

  /// The `ValidationError` every `--model` site throws for an unrecognised
  /// value. Lists the on-device names inline and points at `vinetas list`
  /// for the cloud catalog, which is too long to repeat in an error.
  public static func unknownModelError(_ name: String) -> ValidationError {
    ValidationError(
      "Unknown model '\(name)'. On-device models: \(localNames.joined(separator: ", ")). "
        + "Cloud models (bring your own API key): \(cloudNames.joined(separator: ", ")). "
        + "Run `vinetas list` for key status.")
  }
}

extension CLIModel: Hashable {
  public static func == (lhs: CLIModel, rhs: CLIModel) -> Bool {
    lhs.descriptor.id == rhs.descriptor.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(descriptor.id)
  }
}

// MARK: - Cloud capability warnings

/// One `warning:` line per flag the cloud model does not honour. Cloud
/// vendors ignore (rather than reject) these, so the CLI says so once, up
/// front, instead of silently dropping them — but never fails the run.
///
/// Pure so it can be tested without stdio; callers print each line to
/// stderr.
func cloudCapabilityWarnings(
  for model: CloudModelDescriptor,
  steps: Int?,
  guidance: Float?,
  seed: UInt64?,
  negative: String?,
  aspect: AspectRatio? = nil,
  fromPromptsFile: Bool = false
) -> [String] {
  // A prompts file names these as YAML keys, not flags.
  func label(_ flag: String, _ key: String) -> String {
    fromPromptsFile ? key : flag
  }
  var lines: [String] = []
  if steps != nil, !model.supportsSteps {
    lines.append(
      "warning: \(model.id) does not take a step count; \(label("--steps", "style.steps")) ignored")
  }
  if guidance != nil, !model.supportsGuidance {
    lines.append(
      "warning: \(model.id) does not take a guidance scale; "
        + "\(label("--guidance", "style.guidance")) ignored")
  }
  if seed != nil, !model.supportsSeed {
    lines.append(
      "warning: \(model.id) does not take a seed; \(label("--seed", "seed")) ignored and the "
        + "output is not reproducible")
  }
  if let negative, !negative.isEmpty, !model.supportsNegativePrompt {
    // Not dropped: the prompt bundle writes it into the prompt as an
    // "Avoid:" line, which instruction-following models honour loosely.
    lines.append(
      "note: \(model.id) has no negative-prompt field; "
        + "\(label("--negative", "style.negative")) is sent in the prompt as an \"Avoid:\" line")
  }
  if let aspect, !model.supportedAspectRatios.contains(aspect) {
    let supported = model.supportedAspectRatios.map(\.rawValue).joined(separator: ", ")
    lines.append(
      "warning: \(model.id) does not support the '\(aspect.rawValue)' aspect; the vendor will "
        + "use its closest ratio (supported: \(supported))")
  }
  return lines
}

/// The up-front stderr lines describing what a generation will request.
///
/// On-device models render exactly the requested size and step count, so both
/// are logged. A cloud vendor takes neither as given: it snaps to its own
/// aspect presets (the real size is logged once the image arrives, see
/// ``cloudOutputSizeLine(width:height:)``) and most take no step count.
func requestLogLines(
  for model: CLIModel, style: StyleConfig, aspect: AspectRatio?
) -> [String] {
  guard let cloud = model.cloud else {
    return [
      "[vinetas] Dimensions: \(style.width)x\(style.height)",
      "[vinetas] Steps: \(style.steps)",
    ]
  }
  var lines: [String] = []
  let ratio =
    aspect
    ?? AspectRatio.allCases.first {
      $0.width == style.width && $0.height == style.height
    }
  if let ratio {
    lines.append("[vinetas] Aspect: \(ratio.rawValue) (the vendor chooses the pixel size)")
  } else {
    lines.append(
      "[vinetas] Aspect: \(style.width):\(style.height) (the vendor chooses the pixel size)")
  }
  if cloud.supportsSteps { lines.append("[vinetas] Steps: \(style.steps)") }
  return lines
}

/// The size the vendor actually returned, logged after generation.
func cloudOutputSizeLine(width: Int, height: Int) -> String {
  "[vinetas] Output size: \(width)x\(height)"
}

// MARK: - Download

/// Fetch an on-device model's weights unless `CLIEnvironment.skipDownload`
/// is set; a cloud model has nothing to fetch and says so.
///
/// Routes through ``CLIEnvironment/downloadModel`` so tests can bind a stub.
func downloadIfNeeded(_ model: CLIModel) async throws {
  if model.isCloud {
    stderrPrint("[vinetas] \(model.name) is a cloud model — nothing to download.")
    return
  }
  guard let local = model.local, !CLIEnvironment.skipDownload else { return }
  stderrPrint("[vinetas] Checking model cache: \(local.rawValue)...")
  try await CLIEnvironment.downloadModel(local) { progress in
    stderrPrint(
      "[vinetas] Downloading \(local.rawValue): \(String(format: "%.1f", progress.overallProgress * 100))%"
    )
  }
}

// MARK: - Cloud key status

/// Whether a key resolves for `model` in `client`'s router, and a key-free
/// description of where it came from. `(false, nil)` when no cloud engine is
/// registered for the model or no key is set.
func cloudKeyStatus(
  for model: CloudModelDescriptor, client: VinetasClient
) async -> (configured: Bool, source: String?) {
  guard let engine = try? await client.router.engine(for: model) else { return (false, nil) }
  if let cloud = engine as? CloudImageEngine {
    let source = cloud.keyStore.keySource(for: model.provider)
    return (source != nil, source)
  }
  let available = await engine.isAvailable(model)
  return (available, available ? "configured" : nil)
}

// MARK: - Exit codes

/// Process exit codes for cloud failures, so an agent driving the CLI can
/// branch without parsing stderr. Values follow `sysexits(3)`.
public enum CLIExitCode {
  /// No API key resolved for the vendor (`EX_CONFIG`).
  public static let missingAPIKey: Int32 = 78
  /// The vendor's safety filter declined the prompt or output (`EX_DATAERR`).
  public static let moderated: Int32 = 65
  /// The vendor returned an error, timed out, or sent something undecodable
  /// (`EX_UNAVAILABLE`).
  public static let vendorError: Int32 = 69

  static func code(for error: CloudEngineError) -> Int32 {
    switch error {
    case .missingAPIKey: return missingAPIKey
    case .moderated: return moderated
    case .httpStatus, .invalidResponse, .timedOut, .imageDecodingFailed: return vendorError
    case .noModelLoaded, .unsupportedModel, .unsupportedFeature:
      return ExitCode.validationFailure.rawValue
    }
  }
}

/// Run `body`, translating a ``CloudEngineError`` into its exit code.
///
/// The error's description — the vendor's own message, verbatim, for an HTTP
/// failure — is written to stderr as `error: …` and the process exits with
/// ``CLIExitCode``'s value for that case. Every other error propagates
/// unchanged (ArgumentParser prints it and exits 1).
func reportingCloudErrors<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch let error as CloudEngineError {
    stderrPrint("error: \(error.description(keySource: .environmentOnly))")
    throw ExitCode(CLIExitCode.code(for: error))
  }
}

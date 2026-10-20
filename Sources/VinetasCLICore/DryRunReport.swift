import Foundation
import SwiftVinetas

/// What `vinetas generate --dry-run` prints: a ``PreparedPanel`` flattened
/// into stable, documented JSON (keys sorted on output).
///
/// `promptSent` is the exact text the engine receives. `native` holds the
/// parameters sent as their own fields; for a cloud model only the ones the
/// vendor accepts are actually transmitted, which `nativeAccepted` lists.
struct DryRunReport: Encodable {

  struct Native: Encodable {
    let width: Int
    let height: Int
    let steps: Int
    let guidance: Float
    let seed: UInt64?
    let negative: String?
  }

  let model: String
  let engine: String
  let mode: String
  let promptSent: String
  let bundle: PromptBundle
  let native: Native
  /// For a cloud model, the `native` keys the vendor accepts; `nil`
  /// on-device, where every native parameter is used.
  let nativeAccepted: [String]?
  let references: [ImageOutput.ReferenceRecord]
  let lora: ImageOutput.LoRAEntry?
  let character: String?

  init(_ prepared: PreparedPanel, character: Character?) {
    let request = prepared.request
    model = prepared.modelID
    engine = prepared.engineID
    mode = prepared.references.isEmpty ? "textToImage" : "imageToImage"
    promptSent = prepared.promptSent
    bundle = prepared.bundle
    native = Native(
      width: request.width,
      height: request.height,
      steps: request.steps,
      guidance: request.guidanceScale,
      seed: request.seed,
      negative: request.negativePrompt.flatMap { $0.isEmpty ? nil : $0 })
    nativeAccepted = CloudModelDescriptor.byID[prepared.modelID].map { cloud in
      // Every vendor takes the frame in some form (explicit size or an
      // aspect preset derived from width/height).
      var keys = ["width", "height"]
      if cloud.supportsSteps { keys.append("steps") }
      if cloud.supportsGuidance { keys.append("guidance") }
      if cloud.supportsSeed { keys.append("seed") }
      if cloud.supportsNegativePrompt { keys.append("negative") }
      return keys
    }
    references = prepared.references.map {
      ImageOutput.ReferenceRecord($0, engineID: prepared.engineID)
    }
    lora = prepared.lora
    self.character = character?.slug
  }
}

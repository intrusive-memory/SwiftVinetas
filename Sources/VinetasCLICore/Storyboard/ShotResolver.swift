import Foundation
import GlosaCore

/// Folds GlosaCore's parse-and-carry `<shot>` stream into the list of shots that
/// should actually render a panel, applying the "empty-prompt sets defaults"
/// convention.
///
/// GlosaCore emits **every** `<shot>` in `documentIndex` order and never computes
/// effective shots (see `GlosaCore.Shot`'s type documentation). `ShotResolver` is
/// the downstream Vinetas orchestrator's implementation of that fold:
///
/// - A `<shot>` **with an empty `prompt`** renders nothing. Each attribute it
///   names **replaces** that entry in the active default set, going forward in
///   document order. Attributes it does not name leave the current default
///   untouched (defaults accumulate; they are not reset).
/// - A `<shot>` **with a non-empty `prompt`** renders a panel. For any attribute
///   it does not set it inherits the active default; its own attributes win
///   per-attribute.
///
/// The result is the ordered list of renderable shots with defaults already
/// folded in, ready to map 1:1 onto a single-panel generation.
public enum ShotResolver {

  /// Resolve the `<shot>` stream into renderable shots with defaults folded in.
  ///
  /// - Parameter shots: shots as emitted by GlosaCore (any order; re-sorted by
  ///   `documentIndex` internally so the defaults convention is deterministic).
  /// - Returns: only shots whose `prompt` is non-empty, in `documentIndex`
  ///   order, each carrying the active defaults for every attribute it did not
  ///   set itself.
  public static func resolve(_ shots: [Shot]) -> [Shot] {
    let ordered = shots.sorted { $0.documentIndex < $1.documentIndex }

    // Carrier for the active default attribute set. Its own `prompt` /
    // `documentIndex` are irrelevant — only the optional attributes are read.
    var defaults = Shot(documentIndex: -1, prompt: "")
    var renderable: [Shot] = []

    for shot in ordered {
      if isDefaultsShot(shot) {
        // Each named attribute replaces that entry in the default set; unnamed
        // attributes keep their current default (merge falls back to `base`).
        defaults = merge(base: defaults, override: shot)
      } else {
        // Renderable: inherit defaults for unset attributes; own attributes win.
        renderable.append(merge(base: defaults, override: shot))
      }
    }

    return renderable
  }

  /// A `<shot>` sets defaults (renders nothing) when its `prompt` is empty or
  /// whitespace-only. Because an empty prompt is meaningful here, GlosaCore's
  /// validator does not flag it.
  static func isDefaultsShot(_ shot: Shot) -> Bool {
    shot.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Per-attribute merge: `override` wins for every attribute it sets, otherwise
  /// the value falls back to `base`. Non-optional identity fields (`prompt`,
  /// `documentIndex`) always come from `override` so a renderable shot keeps its
  /// own prompt and position.
  static func merge(base: Shot, override: Shot) -> Shot {
    Shot(
      documentIndex: override.documentIndex,
      prompt: override.prompt,
      style: override.style ?? base.style,
      model: override.model ?? base.model,
      aspect: override.aspect ?? base.aspect,
      width: override.width ?? base.width,
      height: override.height ?? base.height,
      steps: override.steps ?? base.steps,
      guidance: override.guidance ?? base.guidance,
      seed: override.seed ?? base.seed,
      negative: override.negative ?? base.negative,
      lora: override.lora ?? base.lora,
      loraScale: override.loraScale ?? base.loraScale,
      output: override.output ?? base.output,
      preview: override.preview ?? base.preview,
      telemetry: override.telemetry ?? base.telemetry
    )
  }
}

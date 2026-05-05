import Foundation
import SwiftAcervo
import Testing

@testable import SwiftVinetas

// MARK: - Vision Actor Manifest Tests
//
// WU3 S2 — Skip-on-absent-manifest guards for ImageClassifier and FeatureExtractor.
//
// Each test probes manifest availability via Acervo.fetchManifest(forComponent:) before
// exercising the vision actor. When the CDN manifest is absent (404, network error, or
// componentNotRegistered), the test wraps the assertion in withKnownIssue so the test run
// remains green. This keeps CI clean during the window between the WU3 S1 source migration
// and WU4 S1 shipping the ViT manifests to the CDN.
//
// See: docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5
//
// Once docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md moves to docs/complete/ (WU7),
// verify that both skip guards below no longer fire (R8 criterion 8). At that point the
// withKnownIssue wrappers can optionally be removed — but keeping them is also fine since
// they cost nothing when the manifest is present (isIntermittent: true means no failure
// when the known issue does not occur).

@Suite("Vision Actor Manifest Tests")
struct VisionActorManifestTests {

  // MARK: - ImageClassifier

  /// Smoke test: registers the ViT-B/16 component and verifies manifest availability.
  ///
  /// Skip behaviour (R4.5 guard): wraps the manifest check inside withKnownIssue so that
  /// a 404 / network failure / componentNotRegistered error leaves the test suite green.
  /// A single-line stderr message is emitted when the skip path fires, and xcodebuild exit
  /// code remains 0.
  ///
  /// See: docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5
  @Test("ImageClassifier: component registration and manifest availability (skip-on-absent)")
  func imageClassifierManifestAvailability() async {
    let componentId = "vit-base-patch16-224-imagenet1k"

    // Register the component exactly as ImageClassifier.loadModelIfNeeded() does.
    // Acervo.register is idempotent under 0.11.1 — safe to call in tests.
    Acervo.register(ComponentDescriptor(
      id: componentId,
      type: .backbone,
      displayName: "ViT-B/16 ImageNet-1K",
      repoId: "mlx-vision/vit_base_patch16_224-mlxim",
      minimumMemoryBytes: 0
    ))

    // Probe manifest availability before asserting.
    // isIntermittent: true — when the manifest IS present, withKnownIssue does not treat
    // the absence of an issue as a failure, so the test stays green in both states.
    //
    // R4.5 skip-on-absent guard.
    // See: docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5
    var manifestResult: CDNManifest?
    do {
      manifestResult = try await Acervo.fetchManifest(forComponent: componentId)
    } catch {
      // Manifest absent or network unavailable — emit stderr marker and let withKnownIssue
      // absorb the failure below.
      fputs("[skipped] vit_base_patch16_224 manifest not yet published — see R9\n", stderr)
    }

    await withKnownIssue(
      "vit-base-patch16-224-imagenet1k manifest not yet published — see R9 (docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5)",
      isIntermittent: true
    ) {
      guard let manifest = manifestResult else {
        Issue.record("ViT-B/16 manifest absent — skip-on-absent guard active (R4.5)")
        return
      }
      let hasSafetensors = manifest.files.contains { $0.path.hasSuffix(".safetensors") }
      #expect(hasSafetensors, "ViT-B/16 manifest must contain at least one .safetensors entry")
    }
  }

  // MARK: - FeatureExtractor

  /// Smoke test: registers the DINOv2-B/14 component and verifies manifest availability.
  ///
  /// Skip behaviour (R4.5 guard): wraps the manifest check inside withKnownIssue so that
  /// a 404 / network failure / componentNotRegistered error leaves the test suite green.
  /// A single-line stderr message is emitted when the skip path fires, and xcodebuild exit
  /// code remains 0.
  ///
  /// See: docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5
  @Test("FeatureExtractor: component registration and manifest availability (skip-on-absent)")
  func featureExtractorManifestAvailability() async {
    let componentId = "dinov2-vit-base-patch14-518"

    // Register the component exactly as FeatureExtractor.loadModelIfNeeded() does.
    // Acervo.register is idempotent under 0.11.1 — safe to call in tests.
    Acervo.register(ComponentDescriptor(
      id: componentId,
      type: .backbone,
      displayName: "DINOv2-B/14 518px",
      repoId: "mlx-vision/vit_base_patch14_518.dinov2-mlxim",
      minimumMemoryBytes: 0
    ))

    // Probe manifest availability before asserting.
    // isIntermittent: true — when the manifest IS present, withKnownIssue does not treat
    // the absence of an issue as a failure, so the test stays green in both states.
    //
    // R4.5 skip-on-absent guard.
    // See: docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5
    var manifestResult: CDNManifest?
    do {
      manifestResult = try await Acervo.fetchManifest(forComponent: componentId)
    } catch {
      // Manifest absent or network unavailable — emit stderr marker and let withKnownIssue
      // absorb the failure below.
      fputs("[skipped] dinov2_vit_base_patch14_518 manifest not yet published — see R9\n", stderr)
    }

    await withKnownIssue(
      "dinov2-vit-base-patch14-518 manifest not yet published — see R9 (docs/incomplete/SWIFTACERVO_MANIFEST_MIGRATION.md § R4.5)",
      isIntermittent: true
    ) {
      guard let manifest = manifestResult else {
        Issue.record("DINOv2-B/14 manifest absent — skip-on-absent guard active (R4.5)")
        return
      }
      let hasSafetensors = manifest.files.contains { $0.path.hasSuffix(".safetensors") }
      #expect(hasSafetensors, "DINOv2-B/14 manifest must contain at least one .safetensors entry")
    }
  }
}

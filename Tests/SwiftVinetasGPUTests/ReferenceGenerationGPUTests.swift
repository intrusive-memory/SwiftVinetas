import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

/// Klein 4B reference-image (image-to-image) generation, end to end, on real
/// weights. LOCAL ONLY — this suite is never a CI gate (`make test-gpu`).
///
/// Covers the GPU acceptance items of the reference-images requirements:
/// - 1 and 3 references at 1024×512 / 4 steps produce exactly 1024×512 output.
/// - Metadata records each reference's sha256 in order, plus the actual seed.
/// - Reproducibility: metadata read back out of the embedded PNG `iTXt` chunk is
///   sufficient to regenerate a byte-identical image in the same process with
///   the same loaded engine.
/// - A DINOv2 reference↔output similarity score is logged (informational only).
///
/// Weights resolve through `ACERVO_MODELS_DIR` (set by `make test-gpu`), into
/// which `make link-test-models` mirrors the Klein 4B and Qwen3-4B slug trees.
/// Presence gate: Klein 4B transformer, Qwen3-4B encoder and VAE all on disk.
private func klein4BAvailableForReferenceTests() async -> Bool {
  let model = Flux2ModelDescriptor.klein4B
  guard let engine = try? await VinetasClient.shared.router.engine(for: model) else {
    return false
  }
  return await engine.isAvailable(model)
}

@Suite(
  "Reference Generation GPU Tests",
  .tags(.integration, .gpu, .flux2),
  .serialized,
  .enabled(if: !ciSkipsGPUTests),
  .enabled("Klein 4B weights (transformer + Qwen3 encoder + VAE) are cached") {
    await klein4BAvailableForReferenceTests()
  }
)
struct ReferenceGenerationGPUTests {

  static let model = Flux2ModelDescriptor.klein4B
  static let width = 1024
  static let height = 512
  static let steps = 4
  static let prompt = "a lighthouse on a rocky cliff at dusk, waves below"
  static let stylePrompt = "comic panel, bold ink lines"

  // MARK: - 1 reference

  @Test("Klein 4B, 1 reference, 1024×512 @ 4 steps", .timeLimit(.minutes(20)))
  func oneReference() async throws {
    try await runReferenceGeneration(referenceCount: 1, seed: 1_234)
  }

  // MARK: - 3 references

  @Test("Klein 4B, 3 references, 1024×512 @ 4 steps", .timeLimit(.minutes(20)))
  func threeReferences() async throws {
    try await runReferenceGeneration(referenceCount: 3, seed: 5_678)
  }

  // MARK: - Reproducibility from embedded metadata

  /// First generation uses NO seed, so the only way to reproduce it is the
  /// actual seed the library recorded in metadata.
  @Test("Reproducible from embedded PNG metadata (byte-equal pixels)", .timeLimit(.minutes(20)))
  func reproducibleFromEmbeddedMetadata() async throws {
    let client = VinetasClient.shared
    let dir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let refs = try Self.writeReferences(count: 1, into: dir)

    let style = StyleConfig(
      stylePrompt: Self.stylePrompt,
      steps: Self.steps,
      guidanceScale: Self.model.defaultGuidance,
      seed: nil,
      width: Self.width,
      height: Self.height
    )
    let first = try await timed("repro: first generation") {
      try await client.generate(
        PanelRequest(prompt: Self.prompt, style: style, model: Self.model, references: refs))
    }

    // Round-trip the metadata through the embedded PNG iTXt chunk.
    let png = try ImageOutput.pngData(image: first.image, metadata: first.metadata)
    let md = try #require(
      ImageOutput.readEmbeddedMetadata(from: png), "embedded metadata missing from PNG")
    #expect(md == first.metadata, "embedded metadata did not round-trip")
    print("[ReferenceGenerationGPUTests] repro: recorded actual seed = \(md.seed)")

    // Rebuild the request purely from metadata.
    let allModels = await client.router.allModels
    let rebuiltModel = try #require(
      allModels.first { $0.id == md.model }, "no registered model with id \(md.model)")
    let records = try #require(md.references, "metadata has no references")
    let rebuiltRefs = try records.map { try ReferenceImage.load(path: $0.source) }
    #expect(rebuiltRefs.map(\.sha256) == records.map(\.sha256))
    let rebuiltStyle = StyleConfig(
      stylePrompt: md.style ?? "",
      negativePrompt: md.negative,
      steps: md.steps,
      guidanceScale: md.guidance,
      seed: md.seed,
      width: md.width,
      height: md.height
    )
    let rebuilt = PanelRequest(
      prompt: md.prompt, style: rebuiltStyle, model: rebuiltModel, references: rebuiltRefs)

    let second = try await timed("repro: second generation") {
      try await client.generate(rebuilt)
    }
    #expect(second.metadata.seed == md.seed)
    #expect(second.metadata.composedPrompt == md.composedPrompt)

    let a = try #require(Self.rgbaBytes(first.image), "could not render first image")
    let b = try #require(Self.rgbaBytes(second.image), "could not render second image")
    #expect(first.image.width == second.image.width && first.image.height == second.image.height)
    if a != b {
      let diff = Self.diffSummary(a, b)
      print(
        "[ReferenceGenerationGPUTests] repro MISMATCH: first differing offset=\(diff.firstOffset.map(String.init) ?? "n/a") "
          + "differing bytes=\(diff.count) of \(max(a.count, b.count))")
    } else {
      print("[ReferenceGenerationGPUTests] repro: \(a.count) RGBA bytes identical")
    }
    #expect(a == b, "regenerated pixels differ from the original")
  }

  // MARK: - Shared body

  private func runReferenceGeneration(referenceCount: Int, seed: UInt64) async throws {
    let client = VinetasClient.shared
    let dir = try Self.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let refs = try Self.writeReferences(count: referenceCount, into: dir)

    let style = StyleConfig(
      stylePrompt: Self.stylePrompt,
      steps: Self.steps,
      guidanceScale: Self.model.defaultGuidance,
      seed: seed,
      width: Self.width,
      height: Self.height
    )
    let panel = try await timed("\(referenceCount) ref(s): generation") {
      try await client.generate(
        PanelRequest(prompt: Self.prompt, style: style, model: Self.model, references: refs))
    }

    #expect(panel.image.width == Self.width, "width \(panel.image.width) != \(Self.width)")
    #expect(panel.image.height == Self.height, "height \(panel.image.height) != \(Self.height)")
    assertImageNotGarbage(panel.image)

    let md = panel.metadata
    #expect(md.mode == .imageToImage)
    #expect(md.seed == seed, "metadata seed \(md.seed) != requested \(seed)")
    #expect(md.steps == Self.steps)
    #expect(md.width == Self.width && md.height == Self.height)
    let records = try #require(md.references, "metadata.references is nil")
    #expect(
      records.map(\.sha256) == refs.map(\.sha256), "reference sha256s out of order/mismatched")
    #expect(records.map(\.source) == refs.map(\.source.description))
    #expect(Set(refs.map(\.sha256)).count == referenceCount, "test references are not distinct")

    // Informational only: DINOv2 similarity between each reference and output.
    for (i, ref) in refs.enumerated() {
      do {
        let score = try await Vinetas.similarity(between: ref.image, and: panel.image)
        print(
          "[ReferenceGenerationGPUTests] \(referenceCount) ref(s): DINOv2 similarity ref[\(i)]↔output = "
            + String(format: "%.4f", score))
      } catch {
        print(
          "[ReferenceGenerationGPUTests] \(referenceCount) ref(s): DINOv2 similarity unavailable: \(error)"
        )
      }
    }
  }

  // MARK: - Helpers

  private func timed<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
    let clock = ContinuousClock()
    let start = clock.now
    let value = try await body()
    print("[ReferenceGenerationGPUTests] \(label) took \(clock.now - start)")
    return value
  }

  static func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("vinetas-refgen-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Writes `count` distinct deterministic pattern PNGs and loads them.
  static func writeReferences(count: Int, into dir: URL) throws -> [ReferenceImage] {
    try (0..<count).map { index in
      let image = try #require(pattern(index: index), "could not draw pattern \(index)")
      let data = try #require(ImageOutput.pngData(from: image), "could not encode pattern \(index)")
      let url = dir.appendingPathComponent("ref-\(index).png")
      try data.write(to: url)
      return try ReferenceImage.load(path: url.path)
    }
  }

  /// 512×512 deterministic patterns: 0 = checkerboard, 1 = concentric rings,
  /// 2 = diagonal stripes. Each uses a different palette.
  static func pattern(index: Int) -> CGImage? {
    let size = 512
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let palettes: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0.9, 0.2, 0.2, 0.1, 0.1, 0.4),
      (0.1, 0.6, 0.3, 0.95, 0.9, 0.6),
      (0.2, 0.3, 0.9, 0.95, 0.6, 0.1),
    ]
    let p = palettes[index % palettes.count]
    let c1 = CGColor(colorSpace: space, components: [p.0, p.1, p.2, 1])!
    let c2 = CGColor(colorSpace: space, components: [p.3, p.4, p.5, 1])!
    ctx.setFillColor(c2)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setFillColor(c1)
    switch index % 3 {
    case 0:
      let cell = 64
      for y in stride(from: 0, to: size, by: cell) {
        for x in stride(from: 0, to: size, by: cell) where ((x + y) / cell) % 2 == 0 {
          ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
        }
      }
    case 1:
      for r in stride(from: 256, to: 0, by: -48) {
        ctx.setFillColor((r / 48) % 2 == 0 ? c1 : c2)
        ctx.fillEllipse(in: CGRect(x: 256 - r, y: 256 - r, width: 2 * r, height: 2 * r))
      }
    default:
      ctx.setLineWidth(24)
      ctx.setStrokeColor(c1)
      for o in stride(from: -size, to: size, by: 64) {
        ctx.move(to: CGPoint(x: o, y: 0))
        ctx.addLine(to: CGPoint(x: o + size, y: size))
      }
      ctx.strokePath()
    }
    return ctx.makeImage()
  }

  /// Renders into an 8-bit sRGB premultiplied-RGBA buffer with fixed layout.
  static func rgbaBytes(_ image: CGImage) -> [UInt8]? {
    let w = image.width
    let h = image.height
    let bytesPerRow = w * 4
    var buffer = [UInt8](repeating: 0, count: h * bytesPerRow)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
      guard
        let ctx = CGContext(
          data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
          bytesPerRow: bytesPerRow, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.interpolationQuality = .none
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }
    return ok ? buffer : nil
  }

  static func diffSummary(_ a: [UInt8], _ b: [UInt8]) -> (firstOffset: Int?, count: Int) {
    var first: Int?
    var count = abs(a.count - b.count)
    for i in 0..<min(a.count, b.count) where a[i] != b[i] {
      if first == nil { first = i }
      count += 1
    }
    return (first, count)
  }
}

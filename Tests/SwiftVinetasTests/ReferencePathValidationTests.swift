import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftVinetas

/// Sortie 8: the pre-existing reference paths (`generateSequence`, reference
/// sheets) validate reference counts before any model load, and reference-sheet
/// source photos decode through ``ReferenceImage/load(path:)`` (not PNG-only).
@Suite("ReferencePathValidationTests")
struct ReferencePathValidationTests {

  // MARK: - generateSequence

  @Test("generateSequence with too many references throws before load and generate")
  func generateSequenceTooManyReferences() async throws {
    let mock = MockEngine(maxReferenceImages: 1)
    let client = VinetasClient(router: EngineRouter(engines: [mock]))
    let refs = [MockEngine.create1x1Image(), MockEngine.create1x1Image()]

    do {
      _ = try await client.generateSequence(
        prompts: ["panel one", "panel two"],
        referenceImages: refs,
        model: MockModelDescriptor()
      )
      Issue.record("Expected tooManyReferences")
    } catch let error as VinetasError {
      guard case .tooManyReferences(let model, let max, let got) = error else {
        Issue.record("Unexpected VinetasError: \(error)")
        return
      }
      #expect(model == "mock-model")
      #expect(max == 1)
      #expect(got == 2)
    }

    #expect(await mock.loadModelCallCount == 0)
    #expect(await mock.generateCallCount == 0)
  }

  @Test("generateSequence with references within the limit still generates")
  func generateSequenceWithinLimit() async throws {
    let mock = MockEngine(maxReferenceImages: 3)
    let client = VinetasClient(router: EngineRouter(engines: [mock]))

    let images = try await client.generateSequence(
      prompts: ["panel one", "panel two"],
      referenceImages: [MockEngine.create1x1Image()],
      model: MockModelDescriptor()
    )

    #expect(images.count == 2)
    #expect(await mock.loadModelCallCount == 1)
    #expect(await mock.generateCallCount == 2)
  }

  // MARK: - ReferenceSheetGenerator

  @Test("ReferenceSheetGenerator.generate on an engine with no reference support throws before load")
  func referenceSheetUnsupportedEngine() async throws {
    let mock = MockEngine(maxReferenceImages: 0)
    let router = EngineRouter(engines: [mock])
    let character = Character(name: "Sortie Eight Probe")

    do {
      _ = try await ReferenceSheetGenerator.generate(
        for: character,
        views: [.front],
        sourceImage: MockEngine.create1x1Image(),
        model: MockModelDescriptor(),
        router: router
      )
      Issue.record("Expected referencesUnsupported")
    } catch VinetasError.referencesUnsupported(let engineID) {
      #expect(engineID == "mock")
    }

    #expect(await mock.loadModelCallCount == 0)
    #expect(await mock.generateCallCount == 0)
  }

  // MARK: - Source photo decoding

  /// Encodes a small solid-color image with ImageIO using the given UTI.
  private static func encode(_ uti: String, width: Int = 40, height: Int = 30) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data as CFMutableData, uti as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    #expect(CGImageDestinationFinalize(dest))
    return data as Data
  }

  /// Creates a temp characters root containing `<slug>/<photoName>` with `data`.
  private static func makeCharacterDirectory(
    slug: String, photoName: String, data: Data?
  ) throws -> CharacterManager {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ReferencePathValidationTests-\(UUID().uuidString)", isDirectory: true)
    let manager = CharacterManager(baseDirectory: root)
    let dir = manager.characterDirectory(slug: slug)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let data {
      try data.write(to: dir.appendingPathComponent(photoName))
    }
    return manager
  }

  @Test("JPEG source photo in a character directory decodes via ReferenceImage.load(path:)")
  func jpegSourcePhotoLoads() throws {
    let character = Character(name: "Jpeg Probe", sourcePhotos: ["source.jpg"])
    let manager = try Self.makeCharacterDirectory(
      slug: character.slug, photoName: "source.jpg", data: Self.encode("public.jpeg"))
    defer { try? FileManager.default.removeItem(at: manager.baseDirectory) }

    let source = try Vinetas.loadReferenceSheetSource(for: character, manager: manager)

    #expect(source.originalSize == ReferenceImage.Size(width: 40, height: 30))
    #expect(source.image.width == 40)
    let expectedPath = manager.characterDirectory(slug: character.slug)
      .appendingPathComponent("source.jpg").path
    #expect(source.source == .file(path: expectedPath))
  }

  @Test("Missing source photo throws referenceNotFound")
  func missingSourcePhotoThrows() throws {
    let character = Character(name: "Missing Probe", sourcePhotos: ["absent.png"])
    let manager = try Self.makeCharacterDirectory(
      slug: character.slug, photoName: "absent.png", data: nil)
    defer { try? FileManager.default.removeItem(at: manager.baseDirectory) }

    #expect(throws: VinetasError.self) {
      _ = try Vinetas.loadReferenceSheetSource(for: character, manager: manager)
    }
  }
}

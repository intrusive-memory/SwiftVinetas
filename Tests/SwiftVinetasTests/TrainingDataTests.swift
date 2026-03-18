import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - Caption Composition Tests

@Suite("TrainingDataPreparer Caption Composition")
struct TrainingCaptionTests {

  private var testCharacter: Character {
    Character(
      name: "Detective Vale",
      description: "male 40s angular jaw short dark hair"
    )
  }

  @Test("Caption with view contains trigger word")
  func captionWithViewContainsTriggerWord() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .front)
    #expect(caption.contains(testCharacter.triggerWord))
  }

  @Test("Caption with front view contains 'front view'")
  func captionWithFrontViewContainsFrontView() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .front)
    #expect(caption.contains("front view"))
  }

  @Test("Caption with back view contains 'back view'")
  func captionWithBackViewContainsBackView() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .back)
    #expect(caption.contains("back view"))
  }

  @Test("Caption with left view contains 'left view'")
  func captionWithLeftViewContainsLeftView() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .left)
    #expect(caption.contains("left view"))
  }

  @Test("Caption with right view contains 'right view'")
  func captionWithRightViewContainsRightView() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .right)
    #expect(caption.contains("right view"))
  }

  @Test("Caption without view contains trigger word")
  func captionWithoutViewContainsTriggerWord() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: nil)
    #expect(caption.contains(testCharacter.triggerWord))
  }

  @Test("Caption without view does NOT contain a view suffix")
  func captionWithoutViewHasNoViewSuffix() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: nil)
    #expect(!caption.contains("front view"))
    #expect(!caption.contains("left view"))
    #expect(!caption.contains("right view"))
    #expect(!caption.contains("back view"))
  }

  @Test("Caption contains character description")
  func captionContainsDescription() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .front)
    #expect(caption.contains(testCharacter.description))
  }

  @Test("Caption format matches expected pattern with view")
  func captionFormatWithView() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: .front)
    let expected = "\(testCharacter.triggerWord), \(testCharacter.description), front view"
    #expect(caption == expected)
  }

  @Test("Caption format matches expected pattern without view")
  func captionFormatWithoutView() {
    let caption = TrainingDataPreparer.composeCaption(for: testCharacter, view: nil)
    let expected = "\(testCharacter.triggerWord), \(testCharacter.description)"
    #expect(caption == expected)
  }
}

// MARK: - Image Resize Tests

@Suite("TrainingDataPreparer Image Resize")
struct TrainingResizeTests {

  /// Create a CGImage with the given dimensions.
  private func makeImage(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    )!
    return context.makeImage()!
  }

  @Test("100x100 image resized to 96x96 (nearest multiple of 16 below)")
  func resizeNonDivisible() {
    let image = makeImage(width: 100, height: 100)
    let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)
    #expect(resized.width == 96)
    #expect(resized.height == 96)
    #expect(resized.width % 16 == 0)
    #expect(resized.height % 16 == 0)
  }

  @Test("1024x1024 image stays 1024x1024 (already divisible by 16)")
  func resizeAlreadyDivisible() {
    let image = makeImage(width: 1024, height: 1024)
    let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)
    #expect(resized.width == 1024)
    #expect(resized.height == 1024)
  }

  @Test("Asymmetric dimensions both rounded down to multiple of 16")
  func resizeAsymmetric() {
    let image = makeImage(width: 130, height: 200)
    let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)
    #expect(resized.width == 128)
    #expect(resized.height == 192)
    #expect(resized.width % 16 == 0)
    #expect(resized.height % 16 == 0)
  }

  @Test("512x512 image stays 512x512")
  func resize512() {
    let image = makeImage(width: 512, height: 512)
    let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)
    #expect(resized.width == 512)
    #expect(resized.height == 512)
  }

  @Test("Resized dimensions are always divisible by 16")
  func resizedDivisibleBy16() {
    // Test several odd sizes
    for size in [33, 47, 63, 99, 255, 1000] {
      let image = makeImage(width: size, height: size)
      let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)
      #expect(
        resized.width % 16 == 0, "Width \(resized.width) not divisible by 16 for input \(size)")
      #expect(
        resized.height % 16 == 0, "Height \(resized.height) not divisible by 16 for input \(size)")
    }
  }
}

// MARK: - TrainingPair Tests

@Suite("TrainingPair Properties")
struct TrainingPairTests {

  @Test("TrainingPair has expected properties")
  func trainingPairProperties() {
    let pair = TrainingDataPreparer.TrainingPair(
      imagePath: "/tmp/training/front.png",
      captionPath: "/tmp/training/front.txt",
      caption: "sks_detective-vale, male 40s angular jaw, front view"
    )
    #expect(pair.imagePath == "/tmp/training/front.png")
    #expect(pair.captionPath == "/tmp/training/front.txt")
    #expect(pair.caption == "sks_detective-vale, male 40s angular jaw, front view")
  }

  @Test("TrainingPair image and caption share base name")
  func trainingPairMatchingBaseNames() {
    let pair = TrainingDataPreparer.TrainingPair(
      imagePath: "/tmp/training/front.png",
      captionPath: "/tmp/training/front.txt",
      caption: "test caption"
    )
    let imageBase = URL(fileURLWithPath: pair.imagePath).deletingPathExtension().lastPathComponent
    let captionBase = URL(fileURLWithPath: pair.captionPath).deletingPathExtension()
      .lastPathComponent
    #expect(imageBase == captionBase)
  }
}

// MARK: - Full Preparation Integration Tests

@Suite("TrainingDataPreparer Prepare")
struct TrainingPreparationTests {

  /// Create a CGImage with the given dimensions.
  private func makeImage(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    )!
    return context.makeImage()!
  }

  /// Set up a temp character directory with reference images.
  private func makeTempCharacterDir() throws -> (Character, URL) {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftVinetasTests-\(UUID().uuidString)", isDirectory: true)
    let fm = FileManager.default

    // Create directory structure
    let referencesDir = tmp.appendingPathComponent("references", isDirectory: true)
    let trainingDir = tmp.appendingPathComponent("training", isDirectory: true)
    let sourceDir = tmp.appendingPathComponent("source", isDirectory: true)
    try fm.createDirectory(at: referencesDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: trainingDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)

    // Write test reference images (front and back only)
    let testImage = makeImage(width: 100, height: 100)
    try ImageOutput.writePNG(
      image: testImage, to: referencesDir.appendingPathComponent("front.png"))
    try ImageOutput.writePNG(image: testImage, to: referencesDir.appendingPathComponent("back.png"))

    // Write a source photo
    try ImageOutput.writePNG(
      image: testImage, to: sourceDir.appendingPathComponent("test-photo-01.png"))

    let character = Character(
      name: "Test Character",
      slug: "test-character",
      sourcePhotos: ["source/test-photo-01.png"],
      description: "male 40s angular jaw short dark hair"
    )

    return (character, tmp)
  }

  @Test("Prepare creates training pairs for existing reference images")
  func prepareCreatesTrainingPairs() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()
    let pairs = try preparer.prepare(
      for: character,
      includeSourcePhotos: false,
      characterDirectory: charDir
    )

    // We only wrote front.png and back.png references
    #expect(pairs.count == 2)
  }

  @Test("Prepare skips missing reference images")
  func prepareSkipsMissingReferences() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()
    let pairs = try preparer.prepare(
      for: character,
      includeSourcePhotos: false,
      characterDirectory: charDir
    )

    // left.png and right.png don't exist so should be skipped
    let imagePaths = pairs.map(\.imagePath)
    #expect(!imagePaths.contains { $0.contains("left.png") })
    #expect(!imagePaths.contains { $0.contains("right.png") })
  }

  @Test("Every training pair caption contains trigger word")
  func allCaptionsContainTriggerWord() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()
    let pairs = try preparer.prepare(
      for: character,
      includeSourcePhotos: true,
      characterDirectory: charDir
    )

    for pair in pairs {
      #expect(
        pair.caption.contains(character.triggerWord),
        "Caption '\(pair.caption)' missing trigger word '\(character.triggerWord)'")
    }
  }

  @Test("Each PNG has a matching TXT with the same base name")
  func eachPNGHasMatchingTXT() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()
    let pairs = try preparer.prepare(
      for: character,
      includeSourcePhotos: false,
      characterDirectory: charDir
    )

    let fm = FileManager.default
    for pair in pairs {
      #expect(fm.fileExists(atPath: pair.imagePath))
      #expect(fm.fileExists(atPath: pair.captionPath))

      let imageBase = URL(fileURLWithPath: pair.imagePath)
        .deletingPathExtension().lastPathComponent
      let captionBase = URL(fileURLWithPath: pair.captionPath)
        .deletingPathExtension().lastPathComponent
      #expect(imageBase == captionBase)
    }
  }

  @Test("Training images have dimensions divisible by 16")
  func trainingImagesDivisibleBy16() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()
    let pairs = try preparer.prepare(
      for: character,
      includeSourcePhotos: false,
      characterDirectory: charDir
    )

    for pair in pairs {
      guard let provider = CGDataProvider(url: URL(fileURLWithPath: pair.imagePath) as CFURL),
        let image = CGImage(
          pngDataProviderSource: provider,
          decode: nil,
          shouldInterpolate: true,
          intent: .defaultIntent
        )
      else {
        Issue.record("Could not load training image at \(pair.imagePath)")
        continue
      }
      #expect(image.width % 16 == 0, "Width \(image.width) not divisible by 16")
      #expect(image.height % 16 == 0, "Height \(image.height) not divisible by 16")
    }
  }

  @Test("Include source photos adds extra training pairs")
  func includeSourcePhotosAddsExtra() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()

    let withoutSource = try preparer.prepare(
      for: character,
      includeSourcePhotos: false,
      characterDirectory: charDir
    )
    let withSource = try preparer.prepare(
      for: character,
      includeSourcePhotos: true,
      characterDirectory: charDir
    )

    #expect(withSource.count > withoutSource.count)
  }

  @Test("Source photo captions do not contain view suffix")
  func sourcePhotoCaptionsNoViewSuffix() throws {
    let (character, charDir) = try makeTempCharacterDir()
    let preparer = TrainingDataPreparer()
    let pairs = try preparer.prepare(
      for: character,
      includeSourcePhotos: true,
      characterDirectory: charDir
    )

    // Source photo pairs have "source-" prefix in their path
    let sourcePairs = pairs.filter { $0.imagePath.contains("source-") }
    #expect(!sourcePairs.isEmpty)
    for pair in sourcePairs {
      #expect(!pair.caption.contains("front view"))
      #expect(!pair.caption.contains("left view"))
      #expect(!pair.caption.contains("right view"))
      #expect(!pair.caption.contains("back view"))
    }
  }
}

// MARK: - Vinetas Public API Compilation Test

@Suite("Vinetas Training Data API")
struct VinetasTrainingDataAPITests {

  @Test("Vinetas.prepareTrainingData compiles and has correct signature")
  func prepareTrainingDataSignatureCompiles() {
    // Verify the method reference compiles with the expected signature
    let _fn: (Character, Bool) throws -> [TrainingDataPreparer.TrainingPair] =
      Vinetas.prepareTrainingData(for:includeSourcePhotos:)
    _ = _fn
  }
}

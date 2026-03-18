import CoreGraphics
import Foundation

// MARK: - TrainingDataPreparer

/// Assembles training datasets from character reference sheets and source photos.
///
/// For each reference image in the character's `references/` directory, the preparer:
/// 1. Resizes the image so both dimensions are divisible by 16 (VAE requirement).
/// 2. Copies it to `training/<view>.png`.
/// 3. Creates a caption file at `training/<view>.txt` containing the character's
///    trigger word, description, and view label.
///
/// When `includeSourcePhotos` is true, source photos from `source/` are also
/// copied to `training/` with simpler captions (no view suffix).
public struct TrainingDataPreparer: Sendable {

  // MARK: - TrainingPair

  /// A single image–caption pair ready for LoRA training.
  public struct TrainingPair: Sendable {
    /// Absolute path to the training image PNG file.
    public let imagePath: String

    /// Absolute path to the caption text file.
    public let captionPath: String

    /// The caption string written to the text file.
    public let caption: String
  }

  // MARK: - Preparation

  /// Prepare a training dataset for the given character.
  ///
  /// Scans the character's `references/` directory for reference sheet images
  /// (front.png, left.png, right.png, back.png), resizes each to VAE-compatible
  /// dimensions, writes them to `training/`, and creates matching caption files.
  ///
  /// - Parameters:
  ///   - character: The character whose training data to prepare.
  ///   - includeSourcePhotos: Whether to also include the character's source photos.
  ///   - characterDirectory: Root directory for this character on disk.
  /// - Returns: Array of `TrainingPair` values, one per processed image.
  /// - Throws: File I/O errors or image processing errors.
  public func prepare(
    for character: Character,
    includeSourcePhotos: Bool,
    characterDirectory: URL
  ) throws -> [TrainingPair] {
    let fm = FileManager.default
    let referencesDir = characterDirectory.appendingPathComponent("references", isDirectory: true)
    let trainingDir = characterDirectory.appendingPathComponent("training", isDirectory: true)

    // Ensure training directory exists
    try fm.createDirectory(at: trainingDir, withIntermediateDirectories: true)

    var pairs: [TrainingPair] = []

    // Process reference sheet images
    for view in ReferenceView.allCases {
      let sourceURL = referencesDir.appendingPathComponent("\(view.rawValue).png")
      guard fm.fileExists(atPath: sourceURL.path) else { continue }

      guard let image = loadImage(at: sourceURL) else { continue }

      let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)

      // Write resized image to training/
      let destImageURL = trainingDir.appendingPathComponent("\(view.rawValue).png")
      try ImageOutput.writePNG(image: resized, to: destImageURL)

      // Write caption file
      let caption = TrainingDataPreparer.composeCaption(for: character, view: view)
      let destCaptionURL = trainingDir.appendingPathComponent("\(view.rawValue).txt")
      try caption.write(to: destCaptionURL, atomically: true, encoding: .utf8)

      pairs.append(
        TrainingPair(
          imagePath: destImageURL.path,
          captionPath: destCaptionURL.path,
          caption: caption
        ))
    }

    // Optionally include source photos
    if includeSourcePhotos {
      let sourceDir = characterDirectory.appendingPathComponent("source", isDirectory: true)
      for (index, relativePath) in character.sourcePhotos.enumerated() {
        let photoURL = characterDirectory.appendingPathComponent(relativePath)
        guard fm.fileExists(atPath: photoURL.path) else { continue }
        guard let image = loadImage(at: photoURL) else { continue }

        let resized = TrainingDataPreparer.resizeToMultipleOf16(image: image)

        let baseName = "source-\(String(format: "%02d", index + 1))"
        let destImageURL = trainingDir.appendingPathComponent("\(baseName).png")
        try ImageOutput.writePNG(image: resized, to: destImageURL)

        let caption = TrainingDataPreparer.composeCaption(for: character, view: nil)
        let destCaptionURL = trainingDir.appendingPathComponent("\(baseName).txt")
        try caption.write(to: destCaptionURL, atomically: true, encoding: .utf8)

        pairs.append(
          TrainingPair(
            imagePath: destImageURL.path,
            captionPath: destCaptionURL.path,
            caption: caption
          ))
      }
    }

    return pairs
  }

  // MARK: - Caption Composition

  /// Compose a training caption for a character, optionally including a view label.
  ///
  /// With a view: `"<triggerWord>, <description>, <view> view"`
  /// Without a view: `"<triggerWord>, <description>"`
  ///
  /// - Parameters:
  ///   - character: The character whose trigger word and description to use.
  ///   - view: Optional reference view to append as a suffix.
  /// - Returns: The composed caption string.
  public static func composeCaption(for character: Character, view: ReferenceView?) -> String {
    var parts = "\(character.triggerWord), \(character.description)"
    if let view {
      parts += ", \(view.rawValue) view"
    }
    return parts
  }

  // MARK: - Image Resizing

  /// Resize an image so both width and height are divisible by 16.
  ///
  /// Dimensions are rounded DOWN to the nearest multiple of 16.
  /// If both dimensions are already divisible by 16, the image is returned unchanged.
  ///
  /// - Parameter image: The source `CGImage` to resize.
  /// - Returns: A new `CGImage` with VAE-compatible dimensions, or the original if already valid.
  public static func resizeToMultipleOf16(image: CGImage) -> CGImage {
    let originalWidth = image.width
    let originalHeight = image.height

    let newWidth = (originalWidth / 16) * 16
    let newHeight = (originalHeight / 16) * 16

    // Already valid dimensions — return as-is
    if newWidth == originalWidth && newHeight == originalHeight {
      return image
    }

    // Clamp to minimum of 16
    let finalWidth = max(newWidth, 16)
    let finalHeight = max(newHeight, 16)

    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

    // Use a known-good bitmap configuration (RGBA, premultiplied alpha) to avoid
    // CGContext creation failures from unsupported bitmapInfo combinations when
    // the source image comes from a decoded PNG or JPEG.
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard
      let context = CGContext(
        data: nil,
        width: finalWidth,
        height: finalHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
      )
    else {
      // Fallback: return the original image if context creation fails
      return image
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight))

    return context.makeImage() ?? image
  }

  // MARK: - Private Helpers

  /// Load a CGImage from a file URL.
  private func loadImage(at url: URL) -> CGImage? {
    guard let dataProvider = CGDataProvider(url: url as CFURL) else { return nil }

    // Try PNG first, then fall back to JPEG
    if let image = CGImage(
      pngDataProviderSource: dataProvider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    ) {
      return image
    }

    if let image = CGImage(
      jpegDataProviderSource: dataProvider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    ) {
      return image
    }

    return nil
  }
}

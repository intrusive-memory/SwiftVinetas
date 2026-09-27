import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Where a reference image's bytes came from.
public enum ReferenceSource: Sendable, Equatable, Hashable, CustomStringConvertible {
  /// A file on disk, identified by the path exactly as the caller supplied it.
  case file(path: String)
  /// Standard input.
  case stdin

  /// The path for `.file`, or the literal `stdin`.
  public var description: String {
    switch self {
    case .file(let path): return path
    case .stdin: return "stdin"
    }
  }
}

/// A decoded reference (conditioning) image plus the facts needed to
/// validate, report, and record it.
public struct ReferenceImage: Sendable {

  /// Integer pixel dimensions.
  public struct Size: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
      self.width = width
      self.height = height
    }

    public var description: String { "\(width)x\(height)" }
  }

  /// Where the bytes came from.
  public let source: ReferenceSource
  /// Lowercase hex SHA-256 of the raw (undecoded) bytes.
  public let sha256: String
  /// The decoded image.
  public let image: CGImage
  /// Decoded pixel dimensions.
  public let originalSize: Size
  /// The size FLUX.2 actually conditions on after downscale and snap-to-32.
  /// See ``flux2EffectiveSize(width:height:)``.
  public let effectiveSize: Size

  // MARK: - Loading

  /// Loads and decodes a reference image from disk.
  ///
  /// - Throws: ``VinetasError/referenceNotFound(path:)`` if nothing readable exists at
  ///   `path`, ``VinetasError/referenceEmpty(source:)`` for a zero-byte file, and
  ///   ``VinetasError/referenceUndecodable(source:)`` if ImageIO cannot decode the bytes.
  public static func load(path: String) throws -> ReferenceImage {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw VinetasError.referenceNotFound(path: path)
    }
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw VinetasError.referenceNotFound(path: path)
    }
    return try load(data: data, source: .file(path: path))
  }

  /// Decodes a reference image from raw bytes (PNG, JPEG, HEIC, or anything
  /// else ImageIO can read).
  ///
  /// - Throws: ``VinetasError/referenceEmpty(source:)`` for empty data and
  ///   ``VinetasError/referenceUndecodable(source:)`` if ImageIO cannot decode it.
  public static func load(data: Data, source: ReferenceSource) throws -> ReferenceImage {
    guard !data.isEmpty else {
      throw VinetasError.referenceEmpty(source: source)
    }
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(imageSource) > 0,
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      image.width > 0, image.height > 0
    else {
      throw VinetasError.referenceUndecodable(source: source)
    }
    let effective = flux2EffectiveSize(width: image.width, height: image.height)
    return ReferenceImage(
      source: source,
      sha256: sha256Hex(of: data),
      image: image,
      originalSize: Size(width: image.width, height: image.height),
      effectiveSize: Size(width: effective.width, height: effective.height)
    )
  }

  // MARK: - Hashing

  /// Lowercase hex SHA-256 of `data`.
  static func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Effective size

  /// The dimensions FLUX.2 resizes a reference image to before VAE encoding.
  ///
  /// Reproduces, exactly, the per-image sizing in the pinned dependency
  /// `flux-2-swift-mlx` v3.4.2 (`857dd73`),
  /// `Sources/Flux2Core/Pipeline/Flux2Pipeline.swift:2204-2233`:
  ///
  /// 1. If `width * height > 1024 * 1024`, scale both sides by
  ///    `sqrt(1024² / (width * height))`, truncating each to `Int`.
  /// 2. Floor each side to a multiple of 32.
  /// 3. Clamp each side to at least 32.
  ///
  /// Keep this in lockstep with that file when the flux pin moves.
  public static func flux2EffectiveSize(width: Int, height: Int) -> (width: Int, height: Int) {
    let maxImageArea = 1024 * 1024
    let multipleOf = 32

    var targetWidth = width
    var targetHeight = height
    let pixelCount = targetWidth * targetHeight

    if pixelCount > maxImageArea {
      let scale = sqrt(Double(maxImageArea) / Double(pixelCount))
      targetWidth = Int(Double(targetWidth) * scale)
      targetHeight = Int(Double(targetHeight) * scale)
    }

    targetWidth = (targetWidth / multipleOf) * multipleOf
    targetHeight = (targetHeight / multipleOf) * multipleOf

    targetWidth = max(targetWidth, multipleOf)
    targetHeight = max(targetHeight, multipleOf)

    return (targetWidth, targetHeight)
  }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Utilities for encoding generated panel images and writing metadata sidecars.
///
/// Provides PNG encoding via `CGImageDestination` and JSON metadata sidecar
/// generation for reproducibility and pipeline traceability.
public enum ImageOutput {

  // MARK: - PNG Encoding

  /// Encode a `CGImage` as PNG data.
  ///
  /// - Parameter image: The image to encode.
  /// - Returns: PNG-encoded `Data`, or `nil` if encoding fails.
  public static func pngData(from image: CGImage) -> Data? {
    let mutableData = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        mutableData as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return mutableData as Data
  }

  /// Write a `CGImage` as a PNG file to the given URL.
  ///
  /// - Parameters:
  ///   - image: The image to write.
  ///   - url: Destination file URL (must include the `.png` extension).
  /// - Throws: `VinetasError.generationFailed` if PNG encoding fails, or a
  ///           file I/O error if the write fails.
  public static func writePNG(image: CGImage, to url: URL) throws {
    guard let data = pngData(from: image) else {
      throw VinetasError.generationFailed("PNG encoding failed for image at \(url.path)")
    }
    try data.write(to: url, options: .atomic)
  }

  // MARK: - Metadata Sidecar

  /// Metadata written alongside each generated panel PNG.
  ///
  /// The same JSON is written to the `<name>.json` sidecar and embedded in the
  /// PNG as an uncompressed `iTXt` chunk with keyword `vinetas` (see
  /// ``pngData(image:metadata:)``). Every field added after the original schema
  /// is optional and omitted from the JSON when `nil`, so files written by older
  /// versions still decode.
  public struct PanelMetadata: Codable, Sendable, Equatable {

    /// Whether the image was generated from text alone or conditioned on references.
    public enum Mode: String, Codable, Sendable, Equatable {
      case textToImage
      case imageToImage
    }

    /// The caller's prompt as supplied, before style/character composition.
    /// The final prompt sent to the engine is ``composedPrompt``.
    ///
    /// Legacy writers (``ImageOutput/metadata(for:style:)``) record
    /// `PanelOutput.prompt` here, which is already composed.
    public let prompt: String

    /// The model variant used (e.g., "klein4b").
    public let model: String

    /// The seed used for this generation (for reproducibility).
    public let seed: UInt64

    /// Inference step count.
    public let steps: Int

    /// Classifier-free guidance scale.
    public let guidance: Float

    /// Output image width in pixels.
    public let width: Int

    /// Output image height in pixels.
    public let height: Int

    /// Wall-clock generation time in seconds.
    public let durationSeconds: Double

    /// LoRA adapters actually *applied* during generation, if any. Adapters that
    /// were requested but skipped (e.g. incompatible with the model) are not listed.
    public let loras: [LoRAEntry]?

    /// ISO 8601 timestamp when the image was generated.
    public let generatedAt: String

    /// Generation mode, `textToImage` or `imageToImage`.
    public let mode: Mode?

    /// The engine that produced the image (e.g. "flux2", "pixart").
    public let engine: String?

    /// Reference (conditioning) images used, in the order supplied.
    public let references: [ReferenceRecord]?

    /// Style name or preset applied to the prompt, if any.
    public let style: String?

    /// The final prompt sent to the engine after style/character composition.
    public let composedPrompt: String?

    /// The negative prompt the caller supplied, if any.
    public let negative: String?

    /// Whether the engine actually honoured ``negative``. `false` for engines
    /// that ignore negative prompts (e.g. FLUX.2).
    public let negativeApplied: Bool?

    public init(
      prompt: String,
      model: String,
      seed: UInt64,
      steps: Int,
      guidance: Float,
      width: Int,
      height: Int,
      durationSeconds: Double,
      loras: [LoRAEntry]? = nil,
      generatedAt: String,
      mode: Mode? = nil,
      engine: String? = nil,
      references: [ReferenceRecord]? = nil,
      style: String? = nil,
      composedPrompt: String? = nil,
      negative: String? = nil,
      negativeApplied: Bool? = nil
    ) {
      self.prompt = prompt
      self.model = model
      self.seed = seed
      self.steps = steps
      self.guidance = guidance
      self.width = width
      self.height = height
      self.durationSeconds = durationSeconds
      self.loras = loras
      self.generatedAt = generatedAt
      self.mode = mode
      self.engine = engine
      self.references = references
      self.style = style
      self.composedPrompt = composedPrompt
      self.negative = negative
      self.negativeApplied = negativeApplied
    }
  }

  /// Provenance for one reference image recorded in ``PanelMetadata``.
  public struct ReferenceRecord: Codable, Sendable, Equatable {
    /// The path as supplied by the caller, or `stdin`.
    public let source: String

    /// Lowercase hex SHA-256 of the raw reference bytes.
    public let sha256: String

    /// Decoded width in pixels.
    public let originalWidth: Int

    /// Decoded height in pixels.
    public let originalHeight: Int

    /// Width the engine actually conditioned on.
    public let effectiveWidth: Int

    /// Height the engine actually conditioned on.
    public let effectiveHeight: Int

    public init(
      source: String,
      sha256: String,
      originalWidth: Int,
      originalHeight: Int,
      effectiveWidth: Int,
      effectiveHeight: Int
    ) {
      self.source = source
      self.sha256 = sha256
      self.originalWidth = originalWidth
      self.originalHeight = originalHeight
      self.effectiveWidth = effectiveWidth
      self.effectiveHeight = effectiveHeight
    }

    /// Builds a record from a loaded ``ReferenceImage``.
    public init(_ reference: ReferenceImage) {
      self.init(
        source: reference.source.description,
        sha256: reference.sha256,
        originalWidth: reference.originalSize.width,
        originalHeight: reference.originalSize.height,
        effectiveWidth: reference.effectiveSize.width,
        effectiveHeight: reference.effectiveSize.height
      )
    }
  }

  /// An individual LoRA entry recorded in metadata.
  public struct LoRAEntry: Codable, Sendable, Equatable {
    /// File path of the LoRA safetensors file.
    public let path: String

    /// Scale applied to this adapter.
    public let scale: Float

    /// Optional activation keyword injected into the prompt.
    public let activationKeyword: String?

    public init(path: String, scale: Float, activationKeyword: String? = nil) {
      self.path = path
      self.scale = scale
      self.activationKeyword = activationKeyword
    }
  }

  // MARK: - Sidecar Writing

  /// Build a `PanelMetadata` from a `PanelOutput` and a `StyleConfig`.
  ///
  /// - Parameters:
  ///   - output: The panel output containing generation results.
  ///   - style: The style config used during generation (for steps, guidance, LoRA info).
  /// - Returns: A populated `PanelMetadata` ready for JSON serialisation.
  public static func metadata(
    for output: PanelOutput,
    style: StyleConfig
  ) -> PanelMetadata {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]

    let loraEntries: [LoRAEntry]? = {
      guard let path = style.loraPath else { return nil }
      return [LoRAEntry(path: path, scale: style.loraScale ?? 1.0)]
    }()

    return PanelMetadata(
      prompt: output.prompt,
      model: output.modelID,
      seed: output.seed,
      steps: style.steps,
      guidance: style.guidanceScale,
      width: output.width,
      height: output.height,
      durationSeconds: output.durationSeconds,
      loras: loraEntries,
      generatedAt: isoFormatter.string(from: Date())
    )
  }

  /// Write a JSON metadata sidecar alongside a PNG file.
  ///
  /// The sidecar is written to the same directory as the PNG, with the same
  /// base name and a `.json` extension (e.g., `panel-001.png` → `panel-001.json`).
  ///
  /// - Parameters:
  ///   - output: The panel output containing generation results.
  ///   - pngURL: The URL of the PNG file already written to disk.
  ///   - style: The style config used during generation.
  /// - Throws: A file I/O error if the JSON write fails.
  public static func writeMetadata(
    for output: PanelOutput,
    to pngURL: URL,
    style: StyleConfig
  ) throws {
    let data = try metadataJSON(metadata(for: output, style: style))
    try data.write(to: sidecarURL(for: pngURL), options: .atomic)
  }

  /// Write a PNG with embedded `vinetas` iTXt metadata and its JSON sidecar.
  ///
  /// The sidecar bytes are byte-identical to the JSON embedded in the PNG.
  ///
  /// - Parameters:
  ///   - output: The panel output to write.
  ///   - url: Destination PNG file URL.
  ///   - style: The style config used during generation.
  /// - Throws: `VinetasError.generationFailed` if PNG encoding fails, or a
  ///           file I/O error if a write fails.
  public static func writePanel(
    _ output: PanelOutput,
    to url: URL,
    style: StyleConfig
  ) throws {
    try writePanel(image: output.image, metadata: metadata(for: output, style: style), to: url)
  }

  /// Write `image` as a PNG with `metadata` embedded as `vinetas` iTXt, plus
  /// the byte-identical JSON sidecar (`<name>.json`).
  ///
  /// Use this with ``GeneratedPanel/metadata`` so the file records what was
  /// actually used (real seed, duration, references, …).
  ///
  /// - Throws: `VinetasError.generationFailed` if PNG encoding fails, or a
  ///           file I/O error if a write fails.
  public static func writePanel(image: CGImage, metadata: PanelMetadata, to url: URL) throws {
    let json = try metadataJSON(metadata)
    let png = try pngData(image: image, metadataJSON: json)
    try png.write(to: url, options: .atomic)
    try json.write(to: sidecarURL(for: url), options: .atomic)
  }

  /// The sidecar URL for a PNG: same directory and base name, `.json` extension.
  static func sidecarURL(for pngURL: URL) -> URL {
    pngURL.deletingPathExtension().appendingPathExtension("json")
  }

  // MARK: - Embedded Metadata (PNG iTXt)

  /// The iTXt keyword under which panel metadata is embedded.
  public static let metadataKeyword = "vinetas"

  /// Encode metadata as JSON exactly as it is written to the sidecar and the
  /// embedded iTXt chunk (pretty-printed, sorted keys).
  public static func metadataJSON(_ metadata: PanelMetadata) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(metadata)
  }

  /// Encode `image` as PNG with `metadata` embedded as one uncompressed
  /// `iTXt` chunk (keyword `vinetas`) immediately before `IEND`.
  ///
  /// - Throws: `VinetasError.generationFailed` if PNG encoding fails, or an
  ///           `EncodingError` if the metadata cannot be serialised.
  public static func pngData(image: CGImage, metadata: PanelMetadata) throws -> Data {
    try pngData(image: image, metadataJSON: metadataJSON(metadata))
  }

  static func pngData(image: CGImage, metadataJSON json: Data) throws -> Data {
    guard let png = pngData(from: image) else {
      throw VinetasError.generationFailed("PNG encoding failed")
    }
    guard let embedded = insertITXt(into: png, keyword: metadataKeyword, text: json) else {
      throw VinetasError.generationFailed("PNG encoder produced no IEND chunk")
    }
    return embedded
  }

  /// Read the ``PanelMetadata`` embedded by ``pngData(image:metadata:)``.
  ///
  /// - Returns: The decoded metadata, or `nil` if `data` is not a PNG, has no
  ///   uncompressed `vinetas` iTXt chunk, or its text does not decode.
  public static func readEmbeddedMetadata(from data: Data) -> PanelMetadata? {
    guard let json = embeddedMetadataJSON(from: data) else { return nil }
    return try? JSONDecoder().decode(PanelMetadata.self, from: json)
  }

  /// The raw JSON bytes of the first uncompressed `vinetas` iTXt chunk.
  static func embeddedMetadataJSON(from data: Data) -> Data? {
    for chunk in pngChunks(data) where chunk.type == "iTXt" {
      if let text = parseITXt(chunk.data, keyword: metadataKeyword) {
        return text
      }
    }
    return nil
  }

  // MARK: - PNG chunk plumbing

  static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

  struct PNGChunk {
    /// Offset of the chunk's length field within the PNG.
    let offset: Int
    let type: String
    let data: Data
  }

  /// Walk the chunks of a PNG. Stops at the first malformed chunk.
  static func pngChunks(_ png: Data) -> [PNGChunk] {
    let bytes = [UInt8](png)
    guard bytes.count >= 8, Array(bytes[0..<8]) == pngSignature else { return [] }
    var chunks: [PNGChunk] = []
    var offset = 8
    while offset + 12 <= bytes.count {
      let length =
        Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
        | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
      let dataStart = offset + 8
      guard length >= 0, dataStart + length + 4 <= bytes.count else { break }
      let type = String(decoding: bytes[(offset + 4)..<dataStart], as: UTF8.self)
      chunks.append(
        PNGChunk(offset: offset, type: type, data: Data(bytes[dataStart..<(dataStart + length)])))
      offset = dataStart + length + 4
      if type == "IEND" { break }
    }
    return chunks
  }

  /// Serialise one PNG chunk: length, type, data, CRC-32 over type + data.
  static func makeChunk(type: String, data: Data) -> Data {
    var out = Data()
    let length = UInt32(data.count)
    out.append(contentsOf: withUnsafeBytes(of: length.bigEndian, Array.init))
    var typeAndData = Data(type.utf8)
    typeAndData.append(data)
    out.append(typeAndData)
    out.append(contentsOf: withUnsafeBytes(of: crc32(typeAndData).bigEndian, Array.init))
    return out
  }

  /// Build the data of an uncompressed iTXt chunk with empty language tag and
  /// translated keyword.
  static func makeITXtData(keyword: String, text: Data) -> Data {
    var d = Data(keyword.utf8)
    d.append(0)  // keyword terminator
    d.append(0)  // compression flag: uncompressed
    d.append(0)  // compression method
    d.append(0)  // empty language tag + terminator
    d.append(0)  // empty translated keyword + terminator
    d.append(text)
    return d
  }

  /// Parse iTXt chunk data; returns the text if the keyword matches and the
  /// chunk is uncompressed.
  static func parseITXt(_ data: Data, keyword: String) -> Data? {
    let bytes = [UInt8](data)
    guard let kwEnd = bytes.firstIndex(of: 0),
      String(decoding: bytes[0..<kwEnd], as: UTF8.self) == keyword,
      kwEnd + 2 < bytes.count,
      bytes[kwEnd + 1] == 0  // uncompressed only
    else { return nil }
    var i = kwEnd + 3
    guard let langEnd = bytes[i...].firstIndex(of: 0) else { return nil }
    i = langEnd + 1
    guard i <= bytes.count, let transEnd = bytes[i...].firstIndex(of: 0) else { return nil }
    return Data(bytes[(transEnd + 1)...])
  }

  /// Insert an iTXt chunk immediately before `IEND`. Returns `nil` if `png`
  /// has no `IEND` chunk.
  static func insertITXt(into png: Data, keyword: String, text: Data) -> Data? {
    guard let iend = pngChunks(png).first(where: { $0.type == "IEND" }) else { return nil }
    var out = Data(png.prefix(iend.offset))
    out.append(makeChunk(type: "iTXt", data: makeITXtData(keyword: keyword, text: text)))
    out.append(png.suffix(from: png.startIndex + iend.offset))
    return out
  }

  // MARK: - CRC-32

  private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 {
      c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
    }
    return c
  }

  /// CRC-32/ISO-HDLC (the PNG/zlib CRC; reflected polynomial `0xEDB88320`).
  static func crc32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
    var c: UInt32 = 0xFFFF_FFFF
    for b in bytes {
      c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
    }
    return c ^ 0xFFFF_FFFF
  }
}

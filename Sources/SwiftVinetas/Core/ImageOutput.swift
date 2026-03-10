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
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
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
    public struct PanelMetadata: Codable, Sendable {
        /// The composed prompt used to generate the image.
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

        /// LoRA adapters applied during generation, if any.
        public let loras: [LoRAEntry]?

        /// ISO 8601 timestamp when the image was generated.
        public let generatedAt: String

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
            generatedAt: String
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
        }
    }

    /// An individual LoRA entry recorded in metadata.
    public struct LoRAEntry: Codable, Sendable {
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
            model: output.model.rawValue,
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
        let sidecarURL = pngURL.deletingPathExtension().appendingPathExtension("json")
        let meta = metadata(for: output, style: style)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meta)
        try data.write(to: sidecarURL, options: .atomic)
    }

    /// Write both a PNG and its JSON metadata sidecar in one call.
    ///
    /// - Parameters:
    ///   - output: The panel output to write.
    ///   - url: Destination PNG file URL.
    ///   - style: The style config used during generation.
    /// - Throws: Any error from `writePNG(image:to:)` or `writeMetadata(for:to:style:)`.
    public static func writePanel(
        _ output: PanelOutput,
        to url: URL,
        style: StyleConfig
    ) throws {
        try writePNG(image: output.image, to: url)
        try writeMetadata(for: output, to: url, style: style)
    }
}

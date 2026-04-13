import Foundation

/// Information about a FLUX.2 model, including runtime metadata.
///
/// Provides details about a model's cache state, disk usage, and download date.
/// Unlike `VinetasModel` (which describes model capabilities), `VinetasModelInfo`
/// describes the on-disk state of a model.
public struct VinetasModelInfo: Sendable, Equatable {
  /// The model identifier (HuggingFace repository ID).
  public let name: String

  /// Size of the model on disk in bytes. Zero if not downloaded.
  public let size: Int64

  /// Date when the model was downloaded. Nil if not downloaded.
  public let downloadDate: Date?

  /// Whether the model has been downloaded and is available for use.
  public let isDownloaded: Bool

  public init(
    name: String,
    size: Int64,
    downloadDate: Date?,
    isDownloaded: Bool
  ) {
    self.name = name
    self.size = size
    self.downloadDate = downloadDate
    self.isDownloaded = isDownloaded
  }

  /// Human-readable size string (e.g., "2.4 GB").
  public var formattedSize: String {
    let bytes = Double(size)
    let kb = 1024.0
    let mb = kb * 1024.0
    let gb = mb * 1024.0

    if size == 0 {
      return isDownloaded ? "Unknown" : "Not downloaded"
    } else if bytes < kb {
      return "\(size) bytes"
    } else if bytes < mb {
      return String(format: "%.1f KB", bytes / kb)
    } else if bytes < gb {
      return String(format: "%.1f MB", bytes / mb)
    } else {
      return String(format: "%.1f GB", bytes / gb)
    }
  }
}

import Foundation
import SwiftAcervo

// MARK: - AcervoEventCodable
//
// Flattens each `AcervoTelemetryEvent` case to a JSON object with a top-level
// "case" discriminant key plus the case's named fields at the same level.
//
// Example output:
//   {"case":"cacheHit","modelID":"flux2-klein-4b","fileName":"transformer.safetensors",…}
//
// Covers all 13 top-level cases of AcervoTelemetryEvent.

public struct AcervoEventCodable: Encodable {
  public let event: AcervoTelemetryEvent

  public init(event: AcervoTelemetryEvent) {
    self.event = event
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch event {

    // MARK: - Lifecycle

    case let .downloadOperationStart(modelID, requestedFiles, offlineMode):
      try container.encode("downloadOperationStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(requestedFiles, forKey: .requestedFiles)
      try container.encode(offlineMode, forKey: .offlineMode)

    case let .downloadOperationComplete(modelID, totalBytes, durationSeconds):
      try container.encode("downloadOperationComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(totalBytes, forKey: .totalBytes)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Per-component download

    case let .componentDownloadStart(modelID, fileName, expectedBytes, sourceURL):
      try container.encode("componentDownloadStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(fileName, forKey: .fileName)
      try container.encodeIfPresent(expectedBytes, forKey: .expectedBytes)
      try container.encode(sourceURL, forKey: .sourceURL)

    case let .componentDownloadComplete(
      modelID, fileName, actualBytes, durationSeconds, throughputMBps
    ):
      try container.encode("componentDownloadComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(fileName, forKey: .fileName)
      try container.encode(actualBytes, forKey: .actualBytes)
      try container.encode(durationSeconds, forKey: .durationSeconds)
      try container.encode(throughputMBps, forKey: .throughputMBps)

    // MARK: - Manifest fetch

    case let .manifestFetchStart(modelID, manifestURL):
      try container.encode("manifestFetchStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(manifestURL, forKey: .manifestURL)

    case let .manifestFetchComplete(modelID, manifestVersion, fileCount, totalDeclaredBytes):
      try container.encode("manifestFetchComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(manifestVersion, forKey: .manifestVersion)
      try container.encode(fileCount, forKey: .fileCount)
      try container.encode(totalDeclaredBytes, forKey: .totalDeclaredBytes)

    // MARK: - Integrity

    case let .integrityVerifyStart(modelID, fileName, expectedSHA, declaredBytes):
      try container.encode("integrityVerifyStart", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(fileName, forKey: .fileName)
      try container.encode(expectedSHA, forKey: .expectedSHA)
      try container.encode(declaredBytes, forKey: .declaredBytes)

    case let .integrityVerifyComplete(
      modelID, fileName, actualSHA, actualBytes, passed, durationSeconds
    ):
      try container.encode("integrityVerifyComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(fileName, forKey: .fileName)
      try container.encode(actualSHA, forKey: .actualSHA)
      try container.encode(actualBytes, forKey: .actualBytes)
      try container.encode(passed, forKey: .passed)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    // MARK: - Cache

    case let .cacheHit(modelID, fileName, onDiskBytes, ageSeconds):
      try container.encode("cacheHit", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(fileName, forKey: .fileName)
      try container.encode(onDiskBytes, forKey: .onDiskBytes)
      try container.encode(ageSeconds, forKey: .ageSeconds)

    case let .cacheMiss(modelID, fileName, reason):
      try container.encode("cacheMiss", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(fileName, forKey: .fileName)
      try container.encode(reason.rawValue, forKey: .reason)

    // MARK: - CDN HTTP

    case let .cdnRequest(method, url, statusCode, latencyMS, byteCount):
      try container.encode("cdnRequest", forKey: .case)
      try container.encode(method, forKey: .method)
      try container.encode(url, forKey: .url)
      try container.encode(statusCode, forKey: .statusCode)
      try container.encode(latencyMS, forKey: .latencyMS)
      try container.encodeIfPresent(byteCount, forKey: .byteCount)

    // MARK: - Boundary memory events

    case let .modelLoadComplete(modelID, totalSizeMB, componentCount):
      try container.encode("modelLoadComplete", forKey: .case)
      try container.encode(modelID, forKey: .modelID)
      try container.encode(totalSizeMB, forKey: .totalSizeMB)
      try container.encode(componentCount, forKey: .componentCount)

    // MARK: - Error side-channel

    case let .errorThrown(phase, errorDescription, modelID, fileName):
      try container.encode("errorThrown", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(errorDescription, forKey: .errorDescription)
      try container.encodeIfPresent(modelID, forKey: .modelID)
      try container.encodeIfPresent(fileName, forKey: .fileName)
    }
  }

  // MARK: - CodingKeys

  private enum CodingKeys: String, CodingKey {
    case `case`
    case modelID
    case requestedFiles
    case offlineMode
    case totalBytes
    case durationSeconds
    case fileName
    case expectedBytes
    case sourceURL
    case actualBytes
    case throughputMBps
    case manifestURL
    case manifestVersion
    case fileCount
    case totalDeclaredBytes
    case expectedSHA
    case declaredBytes
    case actualSHA
    case passed
    case onDiskBytes
    case ageSeconds
    case reason
    case method
    case url
    case statusCode
    case latencyMS
    case byteCount
    case totalSizeMB
    case componentCount
    case phase
    case errorDescription
  }
}

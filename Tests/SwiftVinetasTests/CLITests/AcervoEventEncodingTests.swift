import Foundation
import SwiftAcervo
import Testing
import VinetasCLICore

// MARK: - AcervoEventEncodingTests (Sortie 11h)
//
// Round-trip tests for the cases of AcervoTelemetryEvent via AcervoEventCodable.
// Covers the SwiftAcervo 0.13.1+ component-keyed events and the 0.17.0+
// inFlightDownloadRegistered/Cleared diagnostic pair.
// For each case:
//  - Encodes via the same JSONEncoder config the sink uses
//  - Re-decodes via JSONSerialization
//  - Asserts the "case" discriminant string
//  - Asserts each associated-value field

@Suite("AcervoEventEncoding round-trips")
struct AcervoEventEncodingTests {

  // MARK: - Helpers

  private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    return enc
  }()

  private func roundTrip(_ event: AcervoTelemetryEvent) throws -> [String: Any] {
    let data = try encoder.encode(AcervoEventCodable(event: event))
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Issue.record("Round-trip did not produce a JSON object for \(event)")
      return [:]
    }
    return dict
  }

  // MARK: - Case 1: downloadOperationStart

  @Test("downloadOperationStart encodes discriminant and all associated values")
  func testDownloadOperationStart() throws {
    let dict = try roundTrip(
      .downloadOperationStart(
        modelID: "flux2-klein-4b",
        requestedFiles: ["transformer.safetensors", "vae.safetensors"],
        offlineMode: false
      )
    )
    #expect((dict["case"] as? String) == "downloadOperationStart")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect(
      (dict["requestedFiles"] as? [String]) == ["transformer.safetensors", "vae.safetensors"])
    #expect((dict["offlineMode"] as? Bool) == false)
  }

  // MARK: - Case 2: downloadOperationComplete

  @Test("downloadOperationComplete encodes discriminant and all associated values")
  func testDownloadOperationComplete() throws {
    let dict = try roundTrip(
      .downloadOperationComplete(
        modelID: "flux2-klein-4b", totalBytes: 4_294_967_296, durationSeconds: 60.5
      )
    )
    #expect((dict["case"] as? String) == "downloadOperationComplete")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect(dict["totalBytes"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 60.5)
  }

  // MARK: - Case 3: componentDownloadStart

  @Test("componentDownloadStart encodes discriminant and present expectedBytes")
  func testComponentDownloadStart() throws {
    let dict = try roundTrip(
      .componentDownloadStart(
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors",
        expectedBytes: 4_294_967_296,
        sourceURL: "https://cdn.example.com/transformer.safetensors"
      )
    )
    #expect((dict["case"] as? String) == "componentDownloadStart")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
    #expect(dict["expectedBytes"] != nil)
    #expect((dict["sourceURL"] as? String) == "https://cdn.example.com/transformer.safetensors")
  }

  @Test("componentDownloadStart encodes nil expectedBytes as absent")
  func testComponentDownloadStartNilExpectedBytes() throws {
    let dict = try roundTrip(
      .componentDownloadStart(
        modelID: "flux2-klein-4b",
        fileName: "config.json",
        expectedBytes: nil,
        sourceURL: "https://cdn.example.com/config.json"
      )
    )
    #expect(dict["expectedBytes"] == nil, "expectedBytes should be absent when nil")
  }

  // MARK: - Case 4: componentDownloadComplete

  @Test("componentDownloadComplete encodes discriminant and all associated values")
  func testComponentDownloadComplete() throws {
    let dict = try roundTrip(
      .componentDownloadComplete(
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors",
        actualBytes: 4_294_967_296,
        durationSeconds: 45.2,
        throughputMBps: 95.5
      )
    )
    #expect((dict["case"] as? String) == "componentDownloadComplete")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
    #expect(dict["actualBytes"] != nil)
    #expect((dict["durationSeconds"] as? Double) == 45.2)
    #expect(dict["throughputMBps"] != nil)
  }

  // MARK: - Case 5: manifestFetchStart

  @Test("manifestFetchStart encodes discriminant and all associated values")
  func testManifestFetchStart() throws {
    let dict = try roundTrip(
      .manifestFetchStart(
        modelID: "flux2-klein-4b",
        manifestURL: "https://cdn.example.com/manifest.json"
      )
    )
    #expect((dict["case"] as? String) == "manifestFetchStart")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["manifestURL"] as? String) == "https://cdn.example.com/manifest.json")
  }

  // MARK: - Case 6: manifestFetchComplete

  @Test("manifestFetchComplete encodes discriminant and all associated values")
  func testManifestFetchComplete() throws {
    let dict = try roundTrip(
      .manifestFetchComplete(
        modelID: "flux2-klein-4b",
        manifestVersion: "1.2.0",
        fileCount: 5,
        totalDeclaredBytes: 8_589_934_592
      )
    )
    #expect((dict["case"] as? String) == "manifestFetchComplete")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["manifestVersion"] as? String) == "1.2.0")
    #expect((dict["fileCount"] as? Int) == 5)
    #expect(dict["totalDeclaredBytes"] != nil)
  }

  // MARK: - Case 7: integrityVerifyStart

  @Test("integrityVerifyStart encodes discriminant and all associated values")
  func testIntegrityVerifyStart() throws {
    let dict = try roundTrip(
      .integrityVerifyStart(
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors",
        expectedSHA: "abc123def456",
        declaredBytes: 4_294_967_296
      )
    )
    #expect((dict["case"] as? String) == "integrityVerifyStart")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
    #expect((dict["expectedSHA"] as? String) == "abc123def456")
    #expect(dict["declaredBytes"] != nil)
  }

  // MARK: - Case 8: integrityVerifyComplete

  @Test("integrityVerifyComplete encodes discriminant and all associated values")
  func testIntegrityVerifyComplete() throws {
    let dict = try roundTrip(
      .integrityVerifyComplete(
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors",
        actualSHA: "abc123def456",
        actualBytes: 4_294_967_296,
        passed: true,
        durationSeconds: 12.3
      )
    )
    #expect((dict["case"] as? String) == "integrityVerifyComplete")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
    #expect((dict["actualSHA"] as? String) == "abc123def456")
    #expect(dict["actualBytes"] != nil)
    #expect((dict["passed"] as? Bool) == true)
    #expect((dict["durationSeconds"] as? Double) == 12.3)
  }

  // MARK: - Case 9: cacheHit

  @Test("cacheHit encodes discriminant and all associated values")
  func testCacheHit() throws {
    let dict = try roundTrip(
      .cacheHit(
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors",
        onDiskBytes: 4_294_967_296,
        ageSeconds: 86400.0
      )
    )
    #expect((dict["case"] as? String) == "cacheHit")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
    #expect(dict["onDiskBytes"] != nil)
    #expect((dict["ageSeconds"] as? Double) == 86400.0)
  }

  // MARK: - Case 10: cacheMiss

  @Test("cacheMiss encodes discriminant, reason rawValue, and all associated values")
  func testCacheMiss() throws {
    let dict = try roundTrip(
      .cacheMiss(
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors",
        reason: .notPresent
      )
    )
    #expect((dict["case"] as? String) == "cacheMiss")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
    #expect((dict["reason"] as? String) == "notPresent")
  }

  @Test("cacheMiss encodes all CacheMissReason rawValues")
  func testCacheMissAllReasons() throws {
    let reasonsAndExpected: [(AcervoTelemetryEvent.CacheMissReason, String)] = [
      (.notPresent, "notPresent"),
      (.shaChangedRemote, "shaChangedRemote"),
      (.sizeChangedRemote, "sizeChangedRemote"),
      (.corrupted, "corrupted"),
      (.forcedRefresh, "forcedRefresh"),
    ]
    for (reason, rawValue) in reasonsAndExpected {
      let dict = try roundTrip(
        .cacheMiss(modelID: "model", fileName: "file.bin", reason: reason)
      )
      #expect(
        (dict["reason"] as? String) == rawValue,
        "CacheMissReason.\(reason) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 11: cdnRequest

  @Test("cdnRequest encodes discriminant and all associated values (with byteCount)")
  func testCdnRequestWithByteCount() throws {
    let dict = try roundTrip(
      .cdnRequest(
        method: "GET",
        url: "https://cdn.example.com/transformer.safetensors",
        statusCode: 200,
        latencyMS: 145.5,
        byteCount: 4_294_967_296
      )
    )
    #expect((dict["case"] as? String) == "cdnRequest")
    #expect((dict["method"] as? String) == "GET")
    #expect((dict["url"] as? String) == "https://cdn.example.com/transformer.safetensors")
    #expect((dict["statusCode"] as? Int) == 200)
    #expect(dict["latencyMS"] != nil)
    #expect(dict["byteCount"] != nil)
  }

  @Test("cdnRequest encodes nil byteCount as absent")
  func testCdnRequestWithoutByteCount() throws {
    let dict = try roundTrip(
      .cdnRequest(
        method: "HEAD",
        url: "https://cdn.example.com/manifest.json",
        statusCode: 200,
        latencyMS: 30.0,
        byteCount: nil
      )
    )
    #expect(dict["byteCount"] == nil, "byteCount should be absent when nil")
    #expect((dict["method"] as? String) == "HEAD")
  }

  // MARK: - Case 12: modelLoadComplete

  @Test("modelLoadComplete encodes discriminant and all associated values")
  func testModelLoadComplete() throws {
    let dict = try roundTrip(
      .modelLoadComplete(modelID: "flux2-klein-4b", totalSizeMB: 4096.0, componentCount: 5)
    )
    #expect((dict["case"] as? String) == "modelLoadComplete")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["totalSizeMB"] as? Double) == 4096.0)
    #expect((dict["componentCount"] as? Int) == 5)
  }

  // MARK: - Case 13: errorThrown

  @Test("errorThrown encodes discriminant, phase rawValue, and present optional fields")
  func testErrorThrown() throws {
    let dict = try roundTrip(
      .errorThrown(
        phase: .fileDownload,
        errorDescription: "connection reset",
        modelID: "flux2-klein-4b",
        fileName: "transformer.safetensors"
      )
    )
    #expect((dict["case"] as? String) == "errorThrown")
    #expect((dict["phase"] as? String) == "fileDownload")
    #expect((dict["errorDescription"] as? String) == "connection reset")
    #expect((dict["modelID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileName"] as? String) == "transformer.safetensors")
  }

  @Test("errorThrown encodes nil optional fields as absent")
  func testErrorThrownNilOptionals() throws {
    let dict = try roundTrip(
      .errorThrown(phase: .other, errorDescription: "unknown", modelID: nil, fileName: nil)
    )
    #expect(dict["modelID"] == nil, "modelID should be absent when nil")
    #expect(dict["fileName"] == nil, "fileName should be absent when nil")
    #expect((dict["phase"] as? String) == "other")
  }

  @Test("errorThrown encodes all ErrorPhase rawValues")
  func testErrorThrownAllPhases() throws {
    let phasesAndExpected: [(AcervoTelemetryEvent.ErrorPhase, String)] = [
      (.manifestDownload, "manifestDownload"),
      (.manifestDecode, "manifestDecode"),
      (.manifestVersionUnsupported, "manifestVersionUnsupported"),
      (.manifestIntegrity, "manifestIntegrity"),
      (.fileDownload, "fileDownload"),
      (.fileDownloadSize, "fileDownloadSize"),
      (.fileDownloadIntegrity, "fileDownloadIntegrity"),
      (.directoryCreation, "directoryCreation"),
      (.offlineMode, "offlineMode"),
      (.s3Request, "s3Request"),
      (.other, "other"),
    ]
    for (phase, rawValue) in phasesAndExpected {
      let dict = try roundTrip(
        .errorThrown(phase: phase, errorDescription: "test", modelID: nil, fileName: nil)
      )
      #expect(
        (dict["phase"] as? String) == rawValue,
        "ErrorPhase.\(phase) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 14: componentResolveStart (0.13.1+)

  @Test("componentResolveStart encodes discriminant, componentID, and repoID")
  func testComponentResolveStart() throws {
    let dict = try roundTrip(
      .componentResolveStart(componentID: "transformer", repoID: "flux2-klein-4b")
    )
    #expect((dict["case"] as? String) == "componentResolveStart")
    #expect((dict["componentID"] as? String) == "transformer")
    #expect((dict["repoID"] as? String) == "flux2-klein-4b")
  }

  // MARK: - Case 15: componentResolveComplete (0.13.1+)

  @Test("componentResolveComplete encodes discriminant, cacheState rawValue, and bytes")
  func testComponentResolveComplete() throws {
    let dict = try roundTrip(
      .componentResolveComplete(
        componentID: "transformer",
        repoID: "flux2-klein-4b",
        fileCount: 3,
        totalBytes: 4_294_967_296,
        cacheState: .alreadyReady,
        durationSeconds: 0.012
      )
    )
    #expect((dict["case"] as? String) == "componentResolveComplete")
    #expect((dict["componentID"] as? String) == "transformer")
    #expect((dict["repoID"] as? String) == "flux2-klein-4b")
    #expect((dict["fileCount"] as? Int) == 3)
    #expect(dict["totalBytes"] != nil)
    #expect((dict["cacheState"] as? String) == "alreadyReady")
    #expect((dict["durationSeconds"] as? Double) == 0.012)
  }

  @Test("componentResolveComplete encodes all ComponentCacheState rawValues")
  func testComponentResolveCompleteAllCacheStates() throws {
    let statesAndExpected: [(AcervoTelemetryEvent.ComponentCacheState, String)] = [
      (.alreadyReady, "alreadyReady"),
      (.downloaded, "downloaded"),
      (.hydratedOnly, "hydratedOnly"),
    ]
    for (state, rawValue) in statesAndExpected {
      let dict = try roundTrip(
        .componentResolveComplete(
          componentID: "c", repoID: "r", fileCount: 1,
          totalBytes: 1, cacheState: state, durationSeconds: 0.0
        )
      )
      #expect(
        (dict["cacheState"] as? String) == rawValue,
        "ComponentCacheState.\(state) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 16: componentFileAccessOpened (0.13.1+)

  @Test("componentFileAccessOpened encodes discriminant and access metadata")
  func testComponentFileAccessOpened() throws {
    let dict = try roundTrip(
      .componentFileAccessOpened(
        componentID: "transformer",
        repoID: "flux2-klein-4b",
        baseDirectory: "/tmp/cache/flux2-klein-4b",
        fileCount: 3
      )
    )
    #expect((dict["case"] as? String) == "componentFileAccessOpened")
    #expect((dict["componentID"] as? String) == "transformer")
    #expect((dict["repoID"] as? String) == "flux2-klein-4b")
    #expect((dict["baseDirectory"] as? String) == "/tmp/cache/flux2-klein-4b")
    #expect((dict["fileCount"] as? Int) == 3)
  }

  // MARK: - Case 18: inFlightDownloadRegistered (0.17+)

  @Test("inFlightDownloadRegistered encodes discriminant, role rawValue, and componentID")
  func testInFlightDownloadRegistered() throws {
    let dict = try roundTrip(
      .inFlightDownloadRegistered(
        modelID: "intrusive-memory/t5-xxl-int4-mlx",
        componentID: "t5-xxl-encoder-int4",
        role: .originator
      )
    )
    #expect((dict["case"] as? String) == "inFlightDownloadRegistered")
    #expect((dict["modelID"] as? String) == "intrusive-memory/t5-xxl-int4-mlx")
    #expect((dict["componentID"] as? String) == "t5-xxl-encoder-int4")
    #expect((dict["role"] as? String) == "originator")
  }

  @Test("inFlightDownloadRegistered encodes nil componentID as absent")
  func testInFlightDownloadRegisteredNilComponentID() throws {
    let dict = try roundTrip(
      .inFlightDownloadRegistered(
        modelID: "intrusive-memory/t5-xxl-int4-mlx",
        componentID: nil,
        role: .joiner
      )
    )
    #expect((dict["case"] as? String) == "inFlightDownloadRegistered")
    #expect(dict["componentID"] == nil, "nil componentID should be absent from JSON")
    #expect((dict["role"] as? String) == "joiner")
  }

  @Test("inFlightDownloadRegistered encodes all InFlightRole rawValues")
  func testInFlightDownloadRegisteredAllRoles() throws {
    let rolesAndExpected: [(AcervoTelemetryEvent.InFlightRole, String)] = [
      (.originator, "originator"),
      (.joiner, "joiner"),
    ]
    for (role, rawValue) in rolesAndExpected {
      let dict = try roundTrip(
        .inFlightDownloadRegistered(modelID: "m", componentID: "c", role: role)
      )
      #expect(
        (dict["role"] as? String) == rawValue,
        "InFlightRole.\(role) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 19: inFlightDownloadCleared (0.17+)

  @Test("inFlightDownloadCleared encodes discriminant, outcome rawValue, and componentID")
  func testInFlightDownloadCleared() throws {
    let dict = try roundTrip(
      .inFlightDownloadCleared(
        modelID: "intrusive-memory/t5-xxl-int4-mlx",
        componentID: "t5-xxl-encoder-int4",
        outcome: .success
      )
    )
    #expect((dict["case"] as? String) == "inFlightDownloadCleared")
    #expect((dict["modelID"] as? String) == "intrusive-memory/t5-xxl-int4-mlx")
    #expect((dict["componentID"] as? String) == "t5-xxl-encoder-int4")
    #expect((dict["outcome"] as? String) == "success")
  }

  @Test("inFlightDownloadCleared encodes all InFlightOutcome rawValues")
  func testInFlightDownloadClearedAllOutcomes() throws {
    let outcomesAndExpected: [(AcervoTelemetryEvent.InFlightOutcome, String)] = [
      (.success, "success"),
      (.failure, "failure"),
    ]
    for (outcome, rawValue) in outcomesAndExpected {
      let dict = try roundTrip(
        .inFlightDownloadCleared(modelID: "m", componentID: "c", outcome: outcome)
      )
      #expect(
        (dict["outcome"] as? String) == rawValue,
        "InFlightOutcome.\(outcome) should encode as '\(rawValue)'"
      )
    }
  }
}

import Foundation
import PixArtBackbone
import Testing
import Tuberia
import VinetasCLICore

// MARK: - PixArtEventEncodingTests (Sortie 11f)
//
// Round-trip tests for all 7 cases of PixArtTelemetryEvent via PixArtEventCodable
// (PixArtBackbone 0.7.2+: backboneForwardComplete(stat:)).
// For each case:
//  - Encodes via the same JSONEncoder config the sink uses
//  - Re-decodes via JSONSerialization
//  - Asserts the "case" discriminant string
//  - Asserts each associated-value field

@Suite("PixArtEventEncoding round-trips")
struct PixArtEventEncodingTests {

  // MARK: - Helpers

  private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    return enc
  }()

  private func roundTrip(_ event: PixArtTelemetryEvent) throws -> [String: Any] {
    let data = try encoder.encode(PixArtEventCodable(event: event))
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      Issue.record("Round-trip did not produce a JSON object for \(event)")
      return [:]
    }
    return dict
  }

  private func makeStat() -> TuberiaTensorStat {
    TuberiaTensorStat(
      shape: [1, 512, 512, 4], dtype: "float32",
      min: -1.5, max: 1.5, mean: 0.01, std: 0.8,
      hasNaN: false, hasInf: false
    )
  }

  // MARK: - Case 1: weightLoadComplete

  @Test("weightLoadComplete encodes discriminant, component rawValue, and all associated values")
  func testWeightLoadComplete() throws {
    let dict = try roundTrip(
      .weightLoadComplete(component: .dit, paramCount: 611_000_000, durationSeconds: 4.2)
    )
    #expect((dict["case"] as? String) == "weightLoadComplete")
    #expect((dict["component"] as? String) == "dit")
    #expect((dict["paramCount"] as? Int) == 611_000_000)
    #expect((dict["durationSeconds"] as? Double) == 4.2)
  }

  // MARK: - Case 2: weightUnloadComplete

  @Test("weightUnloadComplete encodes discriminant only")
  func testWeightUnloadComplete() throws {
    let dict = try roundTrip(.weightUnloadComplete)
    #expect((dict["case"] as? String) == "weightUnloadComplete")
    #expect(
      dict.count == 1, "weightUnloadComplete should have exactly 1 key, got \(dict.keys.sorted())")
  }

  // MARK: - Case 3: recipeValidated

  @Test("recipeValidated encodes discriminant and all associated values")
  func testRecipeValidated() throws {
    let dict = try roundTrip(
      .recipeValidated(name: "pixart-sigma-fp16", checksPassed: 4)
    )
    #expect((dict["case"] as? String) == "recipeValidated")
    #expect((dict["name"] as? String) == "pixart-sigma-fp16")
    #expect((dict["checksPassed"] as? Int) == 4)
  }

  // MARK: - Case 4: recipeValidationFailed

  @Test("recipeValidationFailed encodes discriminant and all associated values")
  func testRecipeValidationFailed() throws {
    let dict = try roundTrip(
      .recipeValidationFailed(
        name: "pixart-sigma-fp16",
        check: "backbone-vae-compatibility",
        reason: "VAE output channels do not match backbone expectations"
      )
    )
    #expect((dict["case"] as? String) == "recipeValidationFailed")
    #expect((dict["name"] as? String) == "pixart-sigma-fp16")
    #expect((dict["check"] as? String) == "backbone-vae-compatibility")
    #expect((dict["reason"] as? String) == "VAE output channels do not match backbone expectations")
  }

  // MARK: - Case 5: numericalAnomaly

  @Test("numericalAnomaly encodes discriminant, phase rawValue, kind rawValue, and stat")
  func testNumericalAnomaly() throws {
    let dict = try roundTrip(
      .numericalAnomaly(phase: .ditForward, kind: .nan, stat: makeStat())
    )
    #expect((dict["case"] as? String) == "numericalAnomaly")
    #expect((dict["phase"] as? String) == "ditForward")
    #expect((dict["kind"] as? String) == "nan")
    #expect(dict["stat"] != nil, "stat should be encoded verbatim")
  }

  @Test("numericalAnomaly encodes AnomalyPhase.weightLoad and AnomalyKind.inf")
  func testNumericalAnomalyWeightLoadInf() throws {
    let dict = try roundTrip(
      .numericalAnomaly(phase: .weightLoad, kind: .inf, stat: makeStat())
    )
    #expect((dict["phase"] as? String) == "weightLoad")
    #expect((dict["kind"] as? String) == "inf")
  }

  @Test("numericalAnomaly encodes AnomalyKind.zeroLatent and AnomalyKind.outOfRange")
  func testNumericalAnomalyAllKinds() throws {
    let kindsAndExpected: [(PixArtTelemetryEvent.AnomalyKind, String)] = [
      (.zeroLatent, "zeroLatent"),
      (.outOfRange, "outOfRange"),
    ]
    for (kind, rawValue) in kindsAndExpected {
      let dict = try roundTrip(.numericalAnomaly(phase: .ditForward, kind: kind, stat: makeStat()))
      #expect(
        (dict["kind"] as? String) == rawValue,
        "AnomalyKind.\(kind) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 6: errorThrown

  @Test("errorThrown encodes discriminant, phase rawValue, and errorDescription")
  func testErrorThrown() throws {
    let dict = try roundTrip(
      .errorThrown(phase: .forward, errorDescription: "DiT forward pass failed")
    )
    #expect((dict["case"] as? String) == "errorThrown")
    #expect((dict["phase"] as? String) == "forward")
    #expect((dict["errorDescription"] as? String) == "DiT forward pass failed")
  }

  @Test("errorThrown encodes all ErrorPhase rawValues")
  func testErrorThrownAllPhases() throws {
    let phasesAndExpected: [(PixArtTelemetryEvent.ErrorPhase, String)] = [
      (.weightLoad, "weightLoad"),
      (.forward, "forward"),
      (.recipeValidation, "recipeValidation"),
      (.other, "other"),
    ]
    for (phase, rawValue) in phasesAndExpected {
      let dict = try roundTrip(.errorThrown(phase: phase, errorDescription: "test"))
      #expect(
        (dict["phase"] as? String) == rawValue,
        "ErrorPhase.\(phase) should encode as '\(rawValue)'"
      )
    }
  }

  // MARK: - Case 7: backboneForwardComplete (0.7.2+)

  @Test("backboneForwardComplete encodes discriminant and stat verbatim")
  func testBackboneForwardComplete() throws {
    let dict = try roundTrip(.backboneForwardComplete(stat: makeStat()))
    #expect((dict["case"] as? String) == "backboneForwardComplete")
    #expect(dict["stat"] != nil, "stat should be encoded verbatim")
  }
}

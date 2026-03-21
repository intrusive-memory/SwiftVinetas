import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasModel Tests")
struct VinetasModelTests {

  // MARK: - CaseIterable

  @Test("CaseIterable includes all models")
  func caseIterable() {
    let allCases = VinetasModel.allCases
    #expect(allCases.count == 3)
    #expect(allCases.contains(.klein4b))
    #expect(allCases.contains(.klein9b))
    #expect(allCases.contains(.pixartSigma))
  }

  // MARK: - Raw Values

  @Test("Raw values match expected strings")
  func rawValues() {
    #expect(VinetasModel.klein4b.rawValue == "klein4b")
    #expect(VinetasModel.klein9b.rawValue == "klein9b")
  }

  @Test("Init from raw value")
  func initFromRawValue() {
    #expect(VinetasModel(rawValue: "klein4b") == .klein4b)
    #expect(VinetasModel(rawValue: "klein9b") == .klein9b)
    #expect(VinetasModel(rawValue: "invalid") == nil)
  }

  // MARK: - HuggingFace Repo

  @Test("Klein 4B HuggingFace repo")
  func klein4bRepo() {
    #expect(VinetasModel.klein4b.huggingFaceRepo == "black-forest-labs/FLUX.2-klein-4B")
  }

  @Test("Klein 9B HuggingFace repo")
  func klein9bRepo() {
    #expect(VinetasModel.klein9b.huggingFaceRepo == "black-forest-labs/FLUX.2-klein-9B")
  }

  // MARK: - Minimum Memory

  @Test("Klein 4B requires 16 GB minimum")
  func klein4bMemory() {
    #expect(VinetasModel.klein4b.minimumMemoryGB == 16)
  }

  @Test("Klein 9B requires 24 GB minimum")
  func klein9bMemory() {
    #expect(VinetasModel.klein9b.minimumMemoryGB == 24)
  }

  // MARK: - Quantization

  @Test("Klein 4B uses int4 quantization")
  func klein4bQuantization() {
    #expect(VinetasModel.klein4b.quantization == "int4")
  }

  @Test("Klein 9B uses qint8 quantization")
  func klein9bQuantization() {
    #expect(VinetasModel.klein9b.quantization == "qint8")
  }

  // MARK: - Estimated Time

  @Test("Klein 4B estimated time is 26 seconds")
  func klein4bTime() {
    #expect(VinetasModel.klein4b.estimatedSecondsPerImage == 26)
  }

  @Test("Klein 9B estimated time is 62 seconds")
  func klein9bTime() {
    #expect(VinetasModel.klein9b.estimatedSecondsPerImage == 62)
  }

  // MARK: - Sendable

  @Test("VinetasModel is Sendable")
  func sendable() async {
    let model: VinetasModel = .klein4b
    // Verify Sendable by passing across an async boundary
    let result = await Task { model }.value
    #expect(result == .klein4b)
  }
}

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
    #expect(VinetasModel.klein4b.repoId == "black-forest-labs/FLUX.2-klein-4B")
  }

  @Test("Klein 9B HuggingFace repo")
  func klein9bRepo() {
    #expect(VinetasModel.klein9b.repoId == "black-forest-labs/FLUX.2-klein-9B")
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

  // MARK: - PixArt Sigma Case

  @Test("PixArt Sigma raw value")
  func pixartSigmaRawValue() {
    #expect(VinetasModel.pixartSigma.rawValue == "pixart-sigma")
  }

  @Test("PixArt Sigma minimum memory is 8 GB")
  func pixartSigmaMemory() {
    #expect(VinetasModel.pixartSigma.minimumMemoryGB == 8)
  }

  @Test("PixArt Sigma estimated time is 10 seconds")
  func pixartSigmaTime() {
    #expect(VinetasModel.pixartSigma.estimatedSecondsPerImage == 10)
  }

  @Test("PixArt Sigma quantization is int4")
  func pixartSigmaQuantization() {
    #expect(VinetasModel.pixartSigma.quantization == "int4")
  }

  @Test("PixArt Sigma HuggingFace repo")
  func pixartSigmaRepo() {
    #expect(VinetasModel.pixartSigma.repoId == "PixArt-alpha/PixArt-Sigma-XL-2-1024-MS")
  }

  @Test("PixArt Sigma init from raw value")
  func pixartSigmaInitFromRawValue() {
    #expect(VinetasModel(rawValue: "pixart-sigma") == .pixartSigma)
  }

  // MARK: - Descriptor Bridge

  @Test("klein4b descriptor bridges to Flux2ModelDescriptor.klein4B")
  func klein4bDescriptorBridge() {
    let descriptor = VinetasModel.klein4b.descriptor
    #expect(descriptor.id == "flux2-klein-4b")
    #expect(descriptor.engineID == "flux2")
  }

  @Test("klein9b descriptor bridges to Flux2ModelDescriptor.klein9B")
  func klein9bDescriptorBridge() {
    let descriptor = VinetasModel.klein9b.descriptor
    #expect(descriptor.id == "flux2-klein-9b")
    #expect(descriptor.engineID == "flux2")
  }

  @Test("pixartSigma descriptor bridges to PixArtModelDescriptor.sigmaXL")
  func pixartSigmaDescriptorBridge() {
    let descriptor = VinetasModel.pixartSigma.descriptor
    #expect(descriptor.id == "pixart-sigma-xl")
    #expect(descriptor.engineID == "pixart-sigma")
  }

  @Test("All cases produce non-nil descriptors")
  func allCasesHaveDescriptors() {
    for model in VinetasModel.allCases {
      let descriptor: any ModelDescriptor = model.descriptor
      #expect(!descriptor.id.isEmpty)
      #expect(!descriptor.engineID.isEmpty)
    }
  }

  @Test("Descriptor minimumMemoryGB matches VinetasModel minimumMemoryGB for Klein 4B")
  func klein4bDescriptorMemoryMatches() {
    let descriptor = VinetasModel.klein4b.descriptor
    #expect(descriptor.minimumMemoryGB == VinetasModel.klein4b.minimumMemoryGB)
  }

  @Test("Descriptor minimumMemoryGB matches VinetasModel minimumMemoryGB for Klein 9B")
  func klein9bDescriptorMemoryMatches() {
    let descriptor = VinetasModel.klein9b.descriptor
    #expect(descriptor.minimumMemoryGB == VinetasModel.klein9b.minimumMemoryGB)
  }

  @Test("Descriptor estimatedSecondsPerImage matches VinetasModel for Klein 4B")
  func klein4bDescriptorTimeMatches() {
    let descriptor = VinetasModel.klein4b.descriptor
    #expect(descriptor.estimatedSecondsPerImage == VinetasModel.klein4b.estimatedSecondsPerImage)
  }

  @Test("Descriptor estimatedSecondsPerImage matches VinetasModel for PixArt Sigma")
  func pixartSigmaDescriptorTimeMatches() {
    let descriptor = VinetasModel.pixartSigma.descriptor
    #expect(
      descriptor.estimatedSecondsPerImage == VinetasModel.pixartSigma.estimatedSecondsPerImage)
  }
}

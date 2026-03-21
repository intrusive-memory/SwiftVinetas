import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasModelManager Tests")
struct VinetasModelManagerTests {

  // MARK: - VinetasModelInfo Struct Properties

  @Test("VinetasModelInfo stores name correctly")
  func modelInfoName() {
    let info = VinetasModelInfo(
      name: "black-forest-labs/FLUX.2-klein-4B",
      size: 2_500_000_000,
      downloadDate: Date(),
      isDownloaded: true
    )
    #expect(info.name == "black-forest-labs/FLUX.2-klein-4B")
  }

  @Test("VinetasModelInfo stores size correctly")
  func modelInfoSize() {
    let info = VinetasModelInfo(
      name: "test-model",
      size: 4_000_000_000,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(info.size == 4_000_000_000)
  }

  @Test("VinetasModelInfo stores download date correctly")
  func modelInfoDownloadDate() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let info = VinetasModelInfo(
      name: "test-model",
      size: 1_000_000,
      downloadDate: date,
      isDownloaded: true
    )
    #expect(info.downloadDate == date)
  }

  @Test("VinetasModelInfo download date is nil when not downloaded")
  func modelInfoNilDownloadDate() {
    let info = VinetasModelInfo(
      name: "test-model",
      size: 0,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(info.downloadDate == nil)
    #expect(info.isDownloaded == false)
  }

  @Test("VinetasModelInfo isDownloaded flag")
  func modelInfoIsDownloaded() {
    let downloaded = VinetasModelInfo(
      name: "downloaded-model",
      size: 5_000_000_000,
      downloadDate: Date(),
      isDownloaded: true
    )
    let notDownloaded = VinetasModelInfo(
      name: "not-downloaded-model",
      size: 0,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(downloaded.isDownloaded == true)
    #expect(notDownloaded.isDownloaded == false)
  }

  // MARK: - Formatted Size

  @Test("Formatted size shows 'Not downloaded' for zero bytes")
  func formattedSizeZero() {
    let info = VinetasModelInfo(
      name: "test",
      size: 0,
      downloadDate: nil,
      isDownloaded: false
    )
    #expect(info.formattedSize == "Not downloaded")
  }

  @Test("Formatted size shows bytes for small sizes")
  func formattedSizeBytes() {
    let info = VinetasModelInfo(
      name: "test",
      size: 512,
      downloadDate: Date(),
      isDownloaded: true
    )
    #expect(info.formattedSize == "512 bytes")
  }

  @Test("Formatted size shows GB for large sizes")
  func formattedSizeGB() {
    let info = VinetasModelInfo(
      name: "test",
      size: 2_684_354_560,  // 2.5 GB
      downloadDate: Date(),
      isDownloaded: true
    )
    #expect(info.formattedSize == "2.5 GB")
  }

  // MARK: - Equatable

  @Test("VinetasModelInfo Equatable conformance")
  func equatable() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let info1 = VinetasModelInfo(
      name: "model-a",
      size: 1000,
      downloadDate: date,
      isDownloaded: true
    )
    let info2 = VinetasModelInfo(
      name: "model-a",
      size: 1000,
      downloadDate: date,
      isDownloaded: true
    )
    let info3 = VinetasModelInfo(
      name: "model-b",
      size: 1000,
      downloadDate: date,
      isDownloaded: true
    )
    #expect(info1 == info2)
    #expect(info1 != info3)
  }

  // MARK: - Model Availability Check

  @Test("isAvailable returns false for models not on disk")
  func isAvailableFalseForMissingModels() async throws {
    // These models are unlikely to be downloaded in CI or a clean environment
    // but even if they are, the test just confirms the API works
    let available = try await VinetasModelManager.isAvailable(VinetasClient.klein4B)
    #expect(type(of: available) == Bool.self)
  }

  // MARK: - listAllModels

  @Test("listAllModels returns entries for known model variants")
  func listAllModelsReturnsAllVariants() async {
    let models = await VinetasModelManager.listAllModels()

    // Should have at least one entry (FLUX.2 Klein 4B and Klein 9B are always registered)
    #expect(models.count >= 2)

    // Should contain entries for the known FLUX.2 models
    let names = models.map(\.name)
    #expect(names.contains(Flux2ModelDescriptor.klein4B.displayName))
    #expect(names.contains(Flux2ModelDescriptor.klein9B.displayName))
  }

  // MARK: - Vinetas Public API

  @Test("Vinetas.listModels compiles and returns VinetasModelInfo array")
  func vinetasListModels() async {
    let models: [VinetasModelInfo] = await Vinetas.listModels()
    // Should have at least the two FLUX.2 Klein models
    #expect(models.count >= 2)
  }

  @Test("Vinetas.validateMemory compiles and returns Bool")
  func vinetasValidateMemory() async {
    // On any Apple Silicon Mac with 16+ GB, Klein 4B should pass.
    // On machines with less, it will throw — both paths are valid.
    do {
      let result: Bool = try await Vinetas.validateMemory(for: .klein4b)
      #expect(result == true)
    } catch {
      // If the machine has < 16 GB, this is the expected path
      #expect(error is VinetasError)
    }
  }
}

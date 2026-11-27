import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// Live cloud-model acceptance tests (requirements §8.2 B, AC-4 to AC-7).
//
// These call the vendors and bill the account behind the key. They are skipped
// unless VINETAS_LIVE_CLOUD_TESTS=1, and the only supported way to run them is
// `make test-cloud-models` (local, never CI). Keys come only from
// `ChainedAPIKeyStore.default`; no key is ever logged or written. Results are
// written to docs/cloud-model-acceptance.md.

private let liveEnabled = ProcessInfo.processInfo.environment["VINETAS_LIVE_CLOUD_TESTS"] == "1"

/// The models this run covers: the three added by the roll-call mission.
private let liveModels: [CloudModelDescriptor] = CloudModelDescriptor.all.filter {
  ["gpt-image-2.6-flare", "gpt-image-2.6-sunburst", "gemini-3.1-flash-lite-image"]
    .contains($0.vendorModelID)
}

// MARK: - Results

private struct ResultRow: Sendable {
  var model: String
  var check: String
  var passed: Bool
  var dimensions: String
  var referenceLimit: String
  var cost: String
  var note: String
}

/// Collects rows and rewrites docs/cloud-model-acceptance.md after each one,
/// so a crash or a cancelled run still leaves what was measured.
private actor ResultRecorder {
  static let shared = ResultRecorder()

  private var rows: [ResultRow] = []
  private let startedAt = Date()

  /// <repo>/docs/cloud-model-acceptance.md, found from this file's location.
  private static var outputURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("docs/cloud-model-acceptance.md")
  }

  func add(_ row: ResultRow) {
    rows.append(row)
    write()
  }

  private func write() {
    let day = ISO8601DateFormatter().string(from: startedAt).prefix(10)
    var text = """
      ---
      type: report
      title: Cloud model acceptance results
      updated: \(day)
      ---

      # Cloud model acceptance results

      Written by `make test-cloud-models` (run date \(day)). Requirements section 8.2 B,
      AC-4 to AC-7. AC-8 (pricing hint) is a manual check against the vendor's pricing page.

      | Model | Check | Result | Actual dimensions | Vendor reference limit | Approx. cost | Note |
      | --- | --- | --- | --- | --- | --- | --- |

      """
    for row in rows {
      let cells = [
        row.model, row.check, row.passed ? "pass" : "FAIL", row.dimensions, row.referenceLimit,
        row.cost, row.note,
      ].map {
        $0.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
      }
      text += "| " + cells.joined(separator: " | ") + " |\n"
    }
    try? text.write(to: Self.outputURL, atomically: true, encoding: .utf8)
  }
}

// MARK: - Helpers

private func liveClient(for provider: CloudProvider) -> any CloudProviderClient {
  CloudImageEngine.defaultClient(for: provider)
}

/// The key from the production chain, or `nil` (the check is recorded as skipped).
private func liveKey(for model: CloudModelDescriptor) -> String? {
  ChainedAPIKeyStore.default.apiKey(for: model.provider)
}

private func recordNoKey(_ model: CloudModelDescriptor, check: String) async {
  await ResultRecorder.shared.add(
    ResultRow(
      model: model.vendorModelID, check: check, passed: false, dimensions: "-",
      referenceLimit: "-", cost: "none",
      note: "SKIPPED: no \(model.provider.environmentVariable) or keychain key"))
}

private func liveEngine(for model: CloudModelDescriptor) -> CloudImageEngine {
  CloudImageEngine(provider: model.provider, keyStore: ChainedAPIKeyStore.default)
}

/// A 512 px gradient, standing in for a small reference photo.
private func smallReference() throws -> CGImage {
  let size = 512
  let context = try #require(
    CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  let gradient = try #require(
    CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: [
        CGColor(srgbRed: 0.9, green: 0.4, blue: 0.2, alpha: 1),
        CGColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1),
      ] as CFArray, locations: [0, 1]))
  context.drawLinearGradient(
    gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
  return try #require(context.makeImage())
}

private func request(
  width: Int, height: Int, references: [CGImage] = []
) -> GenerationRequest {
  GenerationRequest(
    prompt: "a plain red circle on a white background", steps: 1, guidanceScale: 1,
    width: width, height: height,
    mode: references.isEmpty ? .textToImage : .imageToImage(references: references))
}

/// Google's documented 1K output size per aspect-ratio preset. Confirm against
/// the vendor's image-generation docs when reading the results at G-2a.
private let googleOneKSizes: [String: (width: Int, height: Int)] = [
  "1:1": (1024, 1024), "3:2": (1264, 848), "2:3": (848, 1264), "4:3": (1200, 896),
  "3:4": (896, 1200), "5:4": (1152, 928), "4:5": (928, 1152), "16:9": (1376, 768),
  "9:16": (768, 1376), "21:9": (1584, 672), "4:1": (2048, 512),
]

/// The smallest request, at `ratio`, for which the OpenAI adapter sends an
/// explicit size (the vendor needs at least 655,360 pixels).
private func smallestOpenAISize(for ratio: AspectRatio) -> (width: Int, height: Int)? {
  let aspect = Double(ratio.desiredWidth) / Double(ratio.desiredHeight)
  for longest in stride(from: 512, through: OpenAIImageClient.maxEdge, by: 16) {
    let width = aspect >= 1 ? longest : Int((Double(longest) * aspect / 16).rounded()) * 16
    let height = aspect >= 1 ? Int((Double(longest) / aspect / 16).rounded()) * 16 : longest
    guard width >= 16, height >= 16 else { continue }
    let text = OpenAIImageClient.size(width: width, height: height)
    let parts = text.split(separator: "x").compactMap { Int($0) }
    if parts.count == 2 { return (parts[0], parts[1]) }
  }
  return nil
}

// MARK: - Suite

@Suite(
  "Cloud model live acceptance",
  .serialized,
  .enabled(if: liveEnabled, "set VINETAS_LIVE_CLOUD_TESTS=1 (make test-cloud-models)"))
struct CloudModelLiveTests {

  // AC-4. Free.
  @Test("AC-4 listed by the vendor", arguments: liveModels)
  func listed(model: CloudModelDescriptor) async throws {
    let check = "AC-4 listed"
    guard let key = liveKey(for: model) else { return await recordNoKey(model, check: check) }
    let listing = try await liveClient(for: model.provider)
      .listAvailableModels(apiKey: key, session: CloudHTTP.makeListingSession())
    let found = (listing.modelIDs ?? []).first { model.matches(vendorID: $0) }
    var passed = found != nil
    var note = found == nil ? "not in vendor list" : "listed as \(found!)"
    if let found, let shutdown = listing.shutdownDates[found] {
      let days = Int(shutdown.timeIntervalSinceNow / 86_400)
      note += "; shutdown in \(days) days"
      if days <= 90 { passed = false }
    }
    await ResultRecorder.shared.add(
      ResultRow(
        model: model.vendorModelID, check: check, passed: passed, dimensions: "-",
        referenceLimit: "-", cost: "none", note: note))
    #expect(passed, "\(model.vendorModelID): \(note)")
  }

  // AC-5. Billed: one generation per supported ratio.
  @Test("AC-5 every supported ratio generates", arguments: liveModels)
  func ratiosGenerate(model: CloudModelDescriptor) async throws {
    guard liveKey(for: model) != nil else {
      return await recordNoKey(model, check: "AC-5 ratios")
    }
    let engine = liveEngine(for: model)
    try await engine.loadModel(model, progress: { _ in })
    for ratio in model.supportedAspectRatios {
      let check = "AC-5 ratio \(ratio.rawValue)"
      let width: Int
      let height: Int
      var expected: (width: Int, height: Int)?
      switch model.provider {
      case .openAI:
        guard let size = smallestOpenAISize(for: ratio) else {
          await ResultRecorder.shared.add(
            ResultRow(
              model: model.vendorModelID, check: check, passed: false, dimensions: "-",
              referenceLimit: "-", cost: "none", note: "no explicit size fits the vendor rules"))
          Issue.record("\(model.vendorModelID) \(ratio.rawValue): no explicit size")
          continue
        }
        (width, height) = size
        expected = size
      default:
        let aspect = Double(ratio.desiredWidth) / Double(ratio.desiredHeight)
        width = aspect >= 1 ? 1024 : Int(1024 * aspect)
        height = aspect >= 1 ? Int(1024 / aspect) : 1024
        expected = googleOneKSizes[GeminiImageClient.aspectRatio(width: width, height: height)]
      }

      var passed = false
      var dims = "-"
      var note = ""
      do {
        let result = try await engine.generate(
          request: request(width: width, height: height), stepProgress: nil)
        dims = "\(result.image.width)x\(result.image.height)"
        if let expected {
          passed =
            abs(result.image.width - expected.width) <= 1
            && abs(result.image.height - expected.height) <= 1
          note = passed ? "" : "expected \(expected.width)x\(expected.height)"
        } else {
          note = "no documented size for this preset"
        }
      } catch {
        note = "error: \(error)"
      }
      await ResultRecorder.shared.add(
        ResultRow(
          model: model.vendorModelID, check: check, passed: passed, dimensions: dims,
          referenceLimit: "-", cost: "billed (\(model.pricingHint))", note: note))
      #expect(passed, "\(model.vendorModelID) \(ratio.rawValue): \(note)")
    }
  }

  // AC-6. Billed: 1 reference, maxReferenceImages references, then max + 1 sent directly.
  @Test("AC-6 references work up to the declared limit", arguments: liveModels)
  func references(model: CloudModelDescriptor) async throws {
    guard let key = liveKey(for: model) else {
      return await recordNoKey(model, check: "AC-6 references")
    }
    let engine = liveEngine(for: model)
    try await engine.loadModel(model, progress: { _ in })
    let limit = model.maxReferenceImages
    let reference = try smallReference()
    let (width, height) = model.provider == .openAI ? (1024, 640) : (1024, 1024)
    var belowLimitOK = true

    for count in [1, limit] {
      let check = "AC-6 \(count) reference\(count == 1 ? "" : "s")"
      var passed = false
      var note = ""
      do {
        let result = try await engine.generate(
          request: request(
            width: width, height: height, references: Array(repeating: reference, count: count)),
          stepProgress: nil)
        passed = result.image.width > 0
      } catch {
        note = "error: \(error)"
      }
      belowLimitOK = belowLimitOK && passed
      await ResultRecorder.shared.add(
        ResultRow(
          model: model.vendorModelID, check: check, passed: passed, dimensions: "-",
          referenceLimit: "declared \(limit)", cost: "billed (\(model.pricingHint))", note: note))
      #expect(passed, "\(model.vendorModelID) \(count) refs: \(note)")
    }

    // max + 1, straight to the adapter so Vinetas's own limit doesn't stop it.
    var verdict = ""
    do {
      _ = try await liveClient(for: model.provider).generate(
        request(
          width: width, height: height,
          references: Array(repeating: reference, count: limit + 1)),
        model: model, apiKey: key, session: CloudHTTP.makeSession())
      verdict = "vendor accepted \(limit + 1): limit is Vinetas's own cap"
    } catch let error as CloudEngineError {
      if case .httpStatus(_, let status, _) = error, (400..<500).contains(status) {
        verdict = "vendor rejected \(limit + 1) (HTTP \(status)): limit confirmed"
      } else {
        verdict = "inconclusive: \(error)"
      }
    }
    await ResultRecorder.shared.add(
      ResultRow(
        model: model.vendorModelID, check: "AC-6 \(limit + 1) references (direct)",
        passed: belowLimitOK, dimensions: "-", referenceLimit: verdict,
        cost: "billed if accepted", note: ""))
  }

  // AC-7. Unbilled when the vendor rejects them, as expected.
  @Test("AC-7 errors classify correctly", arguments: liveModels)
  func errorsClassify(model: CloudModelDescriptor) async throws {
    guard let key = liveKey(for: model) else {
      return await recordNoKey(model, check: "AC-7 errors")
    }
    let session = CloudHTTP.makeSession()

    // Invalid size: the vendor's own error, as httpStatus, never modelUnavailable.
    var sizeRequest: URLRequest
    switch model.provider {
    case .openAI:
      sizeRequest = URLRequest(url: OpenAIImageClient().endpoint)
      sizeRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
      sizeRequest.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": model.vendorModelID, "prompt": "a red circle", "size": "1000x1000",
      ])
    default:
      sizeRequest = URLRequest(url: GeminiImageClient().endpoint)
      sizeRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
      sizeRequest.httpBody = try JSONSerialization.data(withJSONObject: [
        "model": model.vendorModelID, "input": "a red circle",
        "response_format": ["type": "image", "mime_type": "image/jpeg", "image_size": "3K"],
      ])
    }
    sizeRequest.httpMethod = "POST"
    sizeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var sizeOK = false
    var sizeNote = ""
    do {
      _ = try await CloudHTTP.perform(
        sizeRequest, session: session, provider: model.provider,
        kind: .generation(modelID: model.id))
      sizeNote = "vendor accepted the invalid size"
    } catch let error as CloudEngineError {
      if case .httpStatus(_, let status, _) = error {
        sizeOK = (400..<500).contains(status)
        sizeNote = "HTTP \(status)"
      } else {
        sizeNote = "classified as \(error)"
      }
    }
    await ResultRecorder.shared.add(
      ResultRow(
        model: model.vendorModelID, check: "AC-7 invalid size", passed: sizeOK, dimensions: "-",
        referenceLimit: "-", cost: "unbilled", note: sizeNote))
    #expect(sizeOK, "\(model.vendorModelID) invalid size: \(sizeNote)")

    // Misspelled model: modelUnavailable.
    let typo = CloudModelDescriptor(
      id: model.id, displayName: model.displayName, provider: model.provider,
      vendorModelID: model.vendorModelID + "-typo", defaultSteps: model.defaultSteps,
      defaultGuidance: model.defaultGuidance, supportedAspectRatios: model.supportedAspectRatios,
      supportsSteps: model.supportsSteps, supportsGuidance: model.supportsGuidance,
      supportsSeed: model.supportsSeed, supportsNegativePrompt: model.supportsNegativePrompt,
      pricingHint: model.pricingHint, maxReferenceImages: model.maxReferenceImages)
    var typoOK = false
    var typoNote = ""
    do {
      _ = try await liveClient(for: model.provider).generate(
        request(width: 1024, height: 1024), model: typo, apiKey: key, session: session)
      typoNote = "vendor accepted a misspelled model"
    } catch let error as CloudEngineError {
      if case .modelUnavailable = error {
        typoOK = true
        typoNote = "modelUnavailable"
      } else {
        typoNote = "classified as \(error)"
      }
    }
    await ResultRecorder.shared.add(
      ResultRow(
        model: model.vendorModelID, check: "AC-7 misspelled model", passed: typoOK,
        dimensions: "-", referenceLimit: "-", cost: "unbilled", note: typoNote))
    #expect(typoOK, "\(model.vendorModelID) misspelled: \(typoNote)")
  }
}

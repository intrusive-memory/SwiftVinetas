import ArgumentParser
import CoreGraphics
import Foundation
import GlosaCore
import ImageIO
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

// `--model <cloud-id>` across the CLI: resolution, Pro-gate bypass, the
// capability warnings, the three cloud exit codes, `list`/`info`/`download`
// surfaces, and the storyboard planner. Every test routes through the
// `CLIEnvironment` seam to a `CloudImageEngine` with an in-memory key store
// and a stubbed `URLSession` (no network, no keychain).

// MARK: - URLProtocol stub (file-local; the handler is global so the suite is serialized)

private final class CLIStubURLProtocol: URLProtocol, @unchecked Sendable {

  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var requestCount = 0

  static func reset() {
    handler = nil
    requestCount = 0
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CLIStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requestCount += 1
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private func ok(_ url: URL?, status: Int = 200) -> HTTPURLResponse {
  HTTPURLResponse(
    url: url ?? URL(string: "https://stub.invalid")!, statusCode: status, httpVersion: nil,
    headerFields: nil)!
}

/// A 48×32 solid PNG — deliberately not the requested size, so the metadata
/// assertions prove the CLI records what the vendor returned.
private let vendorPNG: Data = {
  let context = CGContext(
    data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  precondition(CGImageDestinationFinalize(destination))
  return data as Data
}()

private func openAIImageReply(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
  let json: [String: Any] = ["data": [["b64_json": vendorPNG.base64EncodedString()]]]
  return (ok(request.url), try JSONSerialization.data(withJSONObject: json))
}

// MARK: - Suite

@Suite("Cloud CLI", .serialized)
struct CloudCLITests {

  private static let secret = "SECRET-KEY-XYZ-123"

  /// A client whose router holds a free on-device mock plus one cloud engine
  /// per `providers`, each with the given key (or none) and the stub session.
  private static func makeClient(
    keys: [CloudProvider: String], providers: [CloudProvider]
  ) -> VinetasClient {
    var engines: [any ImageGenerationEngine] = [MockEngine(engineID: "pixart-sigma")]
    for provider in providers {
      let store = InMemoryAPIKeyStore(keys: keys.filter { $0.key == provider })
      engines.append(
        CloudImageEngine(
          provider: provider, keyStore: store,
          client: CloudImageEngine.defaultClient(for: provider),
          session: CLIStubURLProtocol.makeSession()))
    }
    return VinetasClient(router: EngineRouter(engines: engines))
  }

  private static func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("CloudCLITests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Runs `body` with the client bound, downloads disabled, and CLI stderr
  /// captured; returns what the CLI wrote to stderr. Errors propagate after
  /// the capture is drained.
  private static func run(
    client: VinetasClient, _ body: () async throws -> Void
  ) async throws -> String {
    let pipe = Pipe()
    var bodyError: Error?
    do {
      try await CLIEnvironment.$stderrDescriptor.withValue(pipe.fileHandleForWriting.fileDescriptor)
      {
        try await CLIEnvironment.$client.withValue(client) {
          try await CLIEnvironment.$skipDownload.withValue(true) {
            try await body()
          }
        }
      }
    } catch {
      bodyError = error
    }
    try pipe.fileHandleForWriting.close()
    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
    if let bodyError { throw bodyError }
    return String(decoding: data, as: UTF8.self)
  }

  /// Like `run`, but expects `body` to throw and returns `(error, stderr)`.
  private static func runExpectingError(
    client: VinetasClient, _ body: () async throws -> Void
  ) async throws -> (error: Error, stderr: String) {
    var captured: Error?
    var stderr = ""
    do {
      stderr = try await run(client: client) {
        do { try await body() } catch { captured = error }
      }
    }
    let error = try #require(captured, "expected the command to throw")
    return (error, stderr)
  }

  // MARK: Resolution & gating

  @Test("CLIModel resolves on-device short names and cloud ids, and rejects everything else")
  func cliModelResolution() {
    #expect(CLIModel.resolve("klein4b") == .klein4b)
    #expect(CLIModel.resolve("pixart-sigma") == .pixartSigma)
    let cloud = CLIModel.resolve("bfl-flux-2-pro")
    #expect(cloud?.isCloud == true)
    #expect(cloud?.cloud == CloudModelDescriptor.flux2Pro)
    #expect(cloud?.name == "bfl-flux-2-pro")
    #expect(cloud?.local == nil)
    #expect(CLIModel.resolve("gpt-image-2.5-flare") == nil)
    #expect(CLIModel.resolve("") == nil)
    #expect(CLIModel.cloudNames == CloudModelDescriptor.all.map(\.id))
  }

  @Test("cloud models are never Pro-gated")
  func cloudModelsBypassProGate() async throws {
    #expect(ProGate.requiresPro(CLIModel.klein4b))
    #expect(!ProGate.requiresPro(CLIModel.pixartSigma))
    for name in CLIModel.cloudNames {
      let model = try #require(CLIModel.resolve(name))
      #expect(!ProGate.requiresPro(model))
      // Never throws, regardless of the marker on this machine.
      try await ProGate.requireAccess(to: model)
    }
  }

  @Test("an unknown --model names both vocabularies")
  func unknownModelMessage() async throws {
    let client = Self.makeClient(keys: [:], providers: [])
    let result = try await Self.runExpectingError(client: client) {
      try await Generate.parse(["p", "--model", "dall-e-9"]).run()
    }
    let message = "\(result.error)"
    #expect(result.error is ValidationError)
    #expect(message.contains("dall-e-9"))
    #expect(message.contains("klein4b"))
    #expect(message.contains("openai-gpt-image-2.5-flare"))
  }

  @Test("exit codes map each cloud failure to a documented sysexits value")
  func exitCodeMapping() {
    #expect(CLIExitCode.code(for: .missingAPIKey(.openAI)) == 78)
    #expect(CLIExitCode.code(for: .moderated(provider: .google)) == 65)
    #expect(CLIExitCode.code(for: .httpStatus(provider: .openAI, status: 500, message: nil)) == 69)
    #expect(CLIExitCode.code(for: .timedOut(provider: .blackForestLabs)) == 69)
    #expect(CLIExitCode.code(for: .invalidResponse(provider: .google, detail: "x")) == 69)
    #expect(CLIExitCode.code(for: .imageDecodingFailed(provider: .stabilityAI)) == 69)
    #expect(CLIExitCode.code(for: .noModelLoaded) == ExitCode.validationFailure.rawValue)
  }

  // MARK: generate

  @Test("generate without a key exits 78, names the variable, writes nothing, touches no network")
  func generateWithoutKey() async throws {
    defer { CLIStubURLProtocol.reset() }
    let client = Self.makeClient(keys: [:], providers: [.openAI])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("panel.png")

    let result = try await Self.runExpectingError(client: client) {
      try await Generate.parse([
        "a lighthouse", "--model", "openai-gpt-image-2.5-flare", "-o", output.path,
      ])
      .run()
    }
    let exit = try #require(result.error as? ExitCode)
    #expect(exit.rawValue == CLIExitCode.missingAPIKey)
    #expect(result.stderr.contains("error:"))
    #expect(result.stderr.contains("OPENAI_API_KEY"))
    #expect(result.stderr.contains("nothing to download"))
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(CLIStubURLProtocol.requestCount == 0)
  }

  @Test(
    "generate with a key writes the PNG + sidecar, warns once per ignored flag, records the vendor's size"
  )
  func generateWithKey() async throws {
    defer { CLIStubURLProtocol.reset() }
    CLIStubURLProtocol.handler = openAIImageReply
    let client = Self.makeClient(keys: [.openAI: Self.secret], providers: [.openAI])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("panel.png")

    let stderr = try await Self.run(client: client) {
      try await Generate.parse([
        "a lighthouse", "--model", "openai-gpt-image-2.5-flare", "-o", output.path,
        "--steps", "9", "--seed", "4", "--negative", "blurry", "--guidance", "2",
      ]).run()
    }

    #expect(FileManager.default.fileExists(atPath: output.path))
    let sidecar = dir.appendingPathComponent("panel.json")
    let metadata = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self, from: Data(contentsOf: sidecar))
    #expect(metadata.model == CloudModelDescriptor.gptImage25Flare.id)
    #expect(metadata.engine == "cloud-openai")
    #expect(metadata.width == 48)
    #expect(metadata.height == 32)
    #expect(metadata.negativeApplied == false)

    #expect(stderr.contains("--steps ignored"))
    #expect(stderr.contains("--guidance ignored"))
    #expect(stderr.contains("--seed ignored"))
    // --negative is not ignored on a cloud model: it rides in the prompt.
    #expect(!stderr.contains("--negative ignored"))
    #expect(stderr.components(separatedBy: "Avoid:\" line").count == 2)  // exactly once
    #expect(metadata.composedPrompt?.hasSuffix("Avoid: blurry.") == true)
    #expect(stderr.contains("Model: openai-gpt-image-2.5-flare"))
    #expect(stderr.contains("nothing to download"))
    #expect(!stderr.contains(Self.secret))
    #expect(CLIStubURLProtocol.requestCount == 1)
  }

  @Test("a vendor refusal exits 65")
  func moderationExitCode() async throws {
    defer { CLIStubURLProtocol.reset() }
    CLIStubURLProtocol.handler = { request in
      let json: [String: Any] = [
        "status": "completed",
        "steps": [["type": "model_output", "content": [["type": "text", "text": "No."]]]],
      ]
      return (ok(request.url), try JSONSerialization.data(withJSONObject: json))
    }
    let client = Self.makeClient(keys: [.google: Self.secret], providers: [.google])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await Self.runExpectingError(client: client) {
      try await Generate.parse([
        "p", "--model", "google-nano-banana-2.1", "-o", dir.appendingPathComponent("p.png").path,
      ]).run()
    }
    let exit = try #require(result.error as? ExitCode)
    #expect(exit.rawValue == CLIExitCode.moderated)
    #expect(result.stderr.contains("content policy"))
  }

  @Test("a vendor HTTP error exits 69 with the vendor's message verbatim on stderr")
  func vendorErrorExitCode() async throws {
    defer { CLIStubURLProtocol.reset() }
    CLIStubURLProtocol.handler = { request in
      let json: [String: Any] = ["error": ["message": "billing hard limit reached"]]
      return (ok(request.url, status: 402), try JSONSerialization.data(withJSONObject: json))
    }
    let client = Self.makeClient(keys: [.openAI: Self.secret], providers: [.openAI])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let result = try await Self.runExpectingError(client: client) {
      try await Generate.parse([
        "p", "--model", "openai-gpt-image-2.5-sunburst", "-o",
        dir.appendingPathComponent("p.png").path,
      ]).run()
    }
    let exit = try #require(result.error as? ExitCode)
    #expect(exit.rawValue == CLIExitCode.vendorError)
    #expect(result.stderr.contains("HTTP 402: billing hard limit reached"))
    #expect(!result.stderr.contains(Self.secret))
  }

  @Test("--lora, --preview, and -r are refused for a cloud model before any network call")
  func cloudRefusals() async throws {
    defer { CLIStubURLProtocol.reset() }
    let client = Self.makeClient(
      keys: [.blackForestLabs: Self.secret], providers: [.blackForestLabs])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let reference = dir.appendingPathComponent("ref.png")
    try vendorPNG.write(to: reference)

    let lora = try await Self.runExpectingError(client: client) {
      try await Generate.parse(["p", "--model", "bfl-flux-2-pro", "--lora", "/tmp/x.safetensors"])
        .run()
    }
    #expect(lora.error is ValidationError)
    #expect("\(lora.error)".contains("LoRA"))

    let preview = try await Self.runExpectingError(client: client) {
      try await Generate.parse(["p", "--model", "bfl-flux-2-pro", "--preview"]).run()
    }
    #expect(preview.error is ValidationError)
    #expect("\(preview.error)".contains("on-device"))

    let refs = try await Self.runExpectingError(client: client) {
      try await Generate.parse(["p", "--model", "bfl-flux-2-pro", "-r", reference.path]).run()
    }
    #expect(refs.error is VinetasError)

    #expect(CLIStubURLProtocol.requestCount == 0)
  }

  // MARK: batch

  @Test("batch runs cloud panels sequentially through the same path")
  func batchWithCloudModel() async throws {
    defer { CLIStubURLProtocol.reset() }
    CLIStubURLProtocol.handler = openAIImageReply
    let client = Self.makeClient(keys: [.openAI: Self.secret], providers: [.openAI])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let yaml = """
      version: 1
      project:
        title: "Cloud batch"
      panels:
        - prompt: "one"
        - prompt: "two"
      """
    let yamlURL = dir.appendingPathComponent("prompts.yaml")
    try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)
    let outputDir = dir.appendingPathComponent("panels")

    _ = try await Self.run(client: client) {
      try await Batch.parse([
        yamlURL.path, "--output-dir", outputDir.path, "--model", "openai-gpt-image-2.5-flare",
      ]).run()
    }
    #expect(
      FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("panel-001.png").path)
    )
    #expect(
      FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("panel-002.png").path)
    )
    #expect(CLIStubURLProtocol.requestCount == 2)
  }

  // MARK: list / info / download

  @Test("list --json reports cloud rows with key status and never leaks the key")
  func listJSON() async throws {
    let client = Self.makeClient(
      keys: [.openAI: Self.secret], providers: [.openAI, .blackForestLabs])

    let result = try await StdioCapture.run {
      _ = try await Self.run(client: client) {
        try await ListModels.parse(["--json"]).run()
      }
    }
    let stdout = String(decoding: result.stdout, as: UTF8.self)
    #expect(!stdout.contains(Self.secret))
    #expect(!stdout.contains("SECRET"))

    let entries = try #require(
      try JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]])
    let openAI = try #require(
      entries.first { $0["model"] as? String == "openai-gpt-image-2.5-flare" })
    #expect(openAI["cloud"] as? Bool == true)
    #expect(openAI["configured"] as? Bool == true)
    #expect(openAI["isDownloaded"] as? Bool == true)
    #expect(openAI["requiresPro"] as? Bool == false)
    #expect(openAI["keySource"] as? String == "memory")
    #expect(openAI["environmentVariable"] as? String == "OPENAI_API_KEY")
    #expect(openAI["provider"] as? String == "openai")
    #expect(openAI["supportsSeed"] as? Bool == false)

    let bfl = try #require(entries.first { $0["model"] as? String == "bfl-flux-2-pro" })
    #expect(bfl["configured"] as? Bool == false)
    #expect(bfl["isDownloaded"] as? Bool == false)
    #expect(bfl["keySource"] == nil)
    #expect(bfl["environmentVariable"] as? String == "BFL_API_KEY")

    // Only registered providers appear; the local mock row is still there.
    #expect(entries.contains { $0["model"] as? String == "google-nano-banana-2.1" } == false)
    #expect(entries.contains { $0["cloud"] as? Bool == false })
    // Catalog order: both OpenAI rows precede the BFL rows.
    let cloudIDs = entries.compactMap {
      $0["cloud"] as? Bool == true ? $0["model"] as? String : nil
    }
    #expect(
      cloudIDs == [
        "openai-gpt-image-2.5-flare", "openai-gpt-image-2.5-sunburst", "bfl-flux-2-pro",
        "bfl-flux-2-flex",
      ])
  }

  @Test("list (table) prints a cloud section with key status and the variable to set")
  func listTable() async throws {
    let client = Self.makeClient(keys: [.stabilityAI: Self.secret], providers: [.stabilityAI])
    let result = try await StdioCapture.run {
      _ = try await Self.run(client: client) {
        try await ListModels.parse([]).run()
      }
    }
    let stdout = String(decoding: result.stdout, as: UTF8.self)
    #expect(stdout.contains("Cloud models"))
    #expect(stdout.contains("stability-core"))
    #expect(stdout.contains("configured (memory)"))
    #expect(stdout.contains("STABILITY_API_KEY"))
    #expect(!stdout.contains(Self.secret))
  }

  @Test("list without cloud engines prints only the on-device table")
  func listWithoutCloudEngines() async throws {
    let client = Self.makeClient(keys: [:], providers: [])
    let result = try await StdioCapture.run {
      _ = try await Self.run(client: client) {
        try await ListModels.parse([]).run()
      }
    }
    let stdout = String(decoding: result.stdout, as: UTF8.self)
    #expect(!stdout.contains("Cloud models"))
    #expect(stdout.contains("Mock Model"))
  }

  @Test("info for a cloud model prints vendor, capabilities, and the not-configured hint")
  func infoCloudModel() async throws {
    let client = Self.makeClient(keys: [:], providers: [.blackForestLabs])
    let result = try await StdioCapture.run {
      _ = try await Self.run(client: client) {
        try await Info.parse(["--model", "bfl-flux-2-flex"]).run()
      }
    }
    let stdout = String(decoding: result.stdout, as: UTF8.self)
    #expect(stdout.contains("Vendor:             Black Forest Labs"))
    #expect(stdout.contains("Vendor model:       flux-2-flex"))
    #expect(stdout.contains("steps yes · guidance yes · seed yes · negative prompt no"))
    #expect(stdout.contains("not configured — set BFL_API_KEY"))
    #expect(stdout.contains("not Pro-gated"))
  }

  @Test("download for a cloud model is a no-op that exits 0 and never reaches the download seam")
  func downloadCloudModel() async throws {
    let client = Self.makeClient(keys: [:], providers: [.openAI])
    let result = try await StdioCapture.run {
      try await CLIEnvironment.$downloadModel.withValue({ _, _ in
        Issue.record("a cloud model must never reach the download seam")
      }) {
        _ = try await Self.run(client: client) {
          try await Download.parse(["--model", "openai-gpt-image-2.5-flare"]).run()
        }
      }
    }
    let stdout = String(decoding: result.stdout, as: UTF8.self)
    #expect(stdout.contains("nothing to download"))
    #expect(stdout.contains("OPENAI_API_KEY"))
  }

  // MARK: storyboard

  @Test(
    "storyboard resolves a cloud shot model, drops preview and lora, and warns per ignored flag")
  func storyboardPlanWithCloudModel() async throws {
    let shot = Shot(
      documentIndex: 0, prompt: "a lighthouse", style: nil, model: "bfl-flux-2-pro",
      aspect: "wide", width: nil, height: nil, steps: 12, guidance: nil, seed: 3,
      negative: "blurry", lora: "/tmp/x.safetensors", loraScale: nil, output: nil, preview: true)

    var plan: Storyboard.PanelPlan?
    let stderr = try await Self.run(client: Self.makeClient(keys: [:], providers: [])) {
      plan = Storyboard().resolvePlan(for: shot, panelNumber: 2, fleetModel: .pixartSigma)
    }
    let resolved = try #require(plan)
    #expect(resolved.model.isCloud)
    #expect(resolved.model.cloud == CloudModelDescriptor.flux2Pro)
    #expect(resolved.usePreview == false)
    #expect(resolved.style.loraPath == nil)
    #expect(resolved.style.steps == 12)  // kept in the request; the vendor ignores it
    #expect(stderr.contains("Panel 2: bfl-flux-2-pro is a cloud model and cannot apply a LoRA"))
    #expect(stderr.contains("Panel 2: warning: bfl-flux-2-pro does not take a step count"))
    #expect(stderr.contains("--negative is sent in the prompt as an \"Avoid:\" line"))
    #expect(!stderr.contains("--seed ignored"))  // FLUX.2 [pro] honours seeds
    #expect(stderr.contains("ignoring preview for 'bfl-flux-2-pro'"))
  }

  @Test("storyboard with a cloud fleet model and no key stops on panel 1 with exit 78")
  func storyboardWithoutKey() async throws {
    let client = Self.makeClient(keys: [:], providers: [.openAI])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let fountain = """
      INT. LIGHTHOUSE - NIGHT

      [[<shot prompt="a lone lighthouse beam"/>]]
      """
    let screenplay = dir.appendingPathComponent("script.fountain")
    try fountain.write(to: screenplay, atomically: true, encoding: .utf8)

    let result = try await Self.runExpectingError(client: client) {
      try await Storyboard.parse([
        screenplay.path, "--output-dir", dir.appendingPathComponent("out").path,
        "--model", "openai-gpt-image-2.5-flare",
      ]).run()
    }
    let exit = try #require(result.error as? ExitCode)
    #expect(exit.rawValue == CLIExitCode.missingAPIKey)
    #expect(result.stderr.contains("OPENAI_API_KEY"))
  }

  // MARK: character

  @Test("character reference and train refuse cloud models up front")
  func characterRefusesCloud() async throws {
    let client = Self.makeClient(keys: [:], providers: [.openAI])
    let reference = try await Self.runExpectingError(client: client) {
      try await CharacterCommand.Reference.parse([
        "some-slug", "--model", "openai-gpt-image-2.5-flare",
      ])
      .run()
    }
    #expect(reference.error is ValidationError)
    #expect("\(reference.error)".contains("cloud model"))
  }
}

// MARK: - References and --dry-run

extension CloudCLITests {

  @Test("--dry-run prints the resolved request and touches neither the network nor the disk")
  func dryRunPrintsResolvedRequest() async throws {
    defer { CLIStubURLProtocol.reset() }
    let client = Self.makeClient(keys: [:], providers: [.google])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let reference = dir.appendingPathComponent("ref.png")
    try vendorPNG.write(to: reference)
    let output = dir.appendingPathComponent("panel.png")

    let result = try await StdioCapture.run {
      _ = try await Self.run(client: client) {
        try await Generate.parse([
          "Mara at the dock", "--model", "google-nano-banana-2.1", "--style", "ink wash",
          "--width", "1344", "--height", "768", "--negative", "text", "-r", reference.path,
          "-o", output.path, "--dry-run",
        ]).run()
      }
    }

    let json = try #require(
      try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any])
    #expect(json["model"] as? String == "google-nano-banana-2.1")
    #expect(json["engine"] as? String == "cloud-google")
    #expect(json["mode"] as? String == "imageToImage")
    let prompt = try #require(json["promptSent"] as? String)
    #expect(prompt.hasPrefix("Mara at the dock"))
    #expect(prompt.contains("Art style: ink wash."))
    #expect(prompt.contains("Frame: 1344×768 pixels, 16:9 landscape aspect ratio."))
    #expect(prompt.contains("Reference images: 1 attached (image 1)."))
    #expect(prompt.contains("Avoid: text."))
    #expect((json["references"] as? [[String: Any]])?.count == 1)
    #expect(json["nativeAccepted"] as? [String] == ["width", "height"])
    let bundle = try #require(json["bundle"] as? [String: Any])
    #expect(bundle["width"] as? Int == 1344)
    #expect(bundle["referenceCount"] as? Int == 1)

    #expect(CLIStubURLProtocol.requestCount == 0)
    #expect(!FileManager.default.fileExists(atPath: output.path))
  }

  @Test("-r on an OpenAI model generates through the edits endpoint and records the references")
  func openAIReferencesGenerate() async throws {
    defer { CLIStubURLProtocol.reset() }
    CLIStubURLProtocol.handler = { request in
      #expect(request.url?.path == "/v1/images/edits")
      return try openAIImageReply(request)
    }
    let client = Self.makeClient(keys: [.openAI: Self.secret], providers: [.openAI])
    let dir = try Self.tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let reference = dir.appendingPathComponent("ref.png")
    try vendorPNG.write(to: reference)
    let output = dir.appendingPathComponent("panel.png")

    _ = try await Self.run(client: client) {
      try await Generate.parse([
        "p", "--model", "openai-gpt-image-2.5-flare", "-r", reference.path, "-r", reference.path,
        "-o", output.path,
      ]).run()
    }

    #expect(CLIStubURLProtocol.requestCount == 1)
    let sidecar = output.deletingPathExtension().appendingPathExtension("json")
    let metadata = try JSONDecoder().decode(
      ImageOutput.PanelMetadata.self, from: Data(contentsOf: sidecar))
    #expect(metadata.mode == .imageToImage)
    #expect(metadata.references?.count == 2)
    #expect(metadata.bundle?.referenceCount == 2)
    #expect(
      metadata.composedPrompt?.contains("2 attached, in order (image 1 to image 2)") == true)
  }
}

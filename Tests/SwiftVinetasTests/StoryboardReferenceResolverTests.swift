import CoreGraphics
import Foundation
import GlosaCore
import ImageIO
import Testing

@testable import SwiftVinetas
@testable import VinetasCLICore

/// Counts every request that reaches the (stubbed) network; reference-limit
/// tests assert it stays at zero.
private final class CountingStubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var hits = 0
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.hits += 1
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  override func stopLoading() {}
}

private func tinyPNG() -> Data {
  let context = CGContext(
    data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  precondition(CGImageDestinationFinalize(destination))
  return data as Data
}

@Suite("Storyboard — reference resolution", .serialized)
struct StoryboardReferenceResolverTests {

  /// A throwaway project tree: `<tmp>/project/PROJECT.md`, `<tmp>/project/scripts/`,
  /// and an isolated Vinetas characters folder.
  private struct Tree {
    let base: URL
    var project: URL { base.appendingPathComponent("project", isDirectory: true) }
    var scripts: URL { project.appendingPathComponent("scripts", isDirectory: true) }
    var characterStore: URL { base.appendingPathComponent("vinetas-characters", isDirectory: true) }
    var manager: CharacterManager { CharacterManager(baseDirectory: characterStore) }

    init() throws {
      base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("refresolver-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
      try Data("# test project\n".utf8).write(to: project.appendingPathComponent("PROJECT.md"))
    }

    func write(_ relative: String, in root: URL? = nil) throws -> URL {
      let url = (root ?? project).appendingPathComponent(relative)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try tinyPNG().write(to: url)
      return url
    }

    func resolver() -> StoryboardReferenceResolver {
      StoryboardReferenceResolver(documentFolder: scripts, characters: manager)
    }

    func cleanup() { try? FileManager.default.removeItem(at: base) }
  }

  @Test func testRule1AbsolutePath() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    let file = try tree.write("elsewhere/abs.png", in: tree.base)
    #expect(try tree.resolver().resolve(file.path).map(\.path) == [file.path])
  }

  @Test func testRule2RelativeToProjectRoot() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    let file = try tree.write("art/hero.png")
    let resolved = try tree.resolver().resolve("art/hero.png")
    #expect(resolved.map(\.lastPathComponent) == ["hero.png"])
    #expect(resolved.first?.path == file.standardizedFileURL.path)
  }

  @Test func testRule2FallsBackToScreenplayFolder() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    // No PROJECT.md anywhere above: the screenplay's folder is the root.
    let loose = tree.base.appendingPathComponent("loose", isDirectory: true)
    let file = try tree.write("local.png", in: loose)
    let resolver = StoryboardReferenceResolver(documentFolder: loose, characters: tree.manager)
    #expect(try resolver.resolve("local.png").map(\.path) == [file.standardizedFileURL.path])
  }

  @Test func testRule3CharacterFolderPrefersPortrait() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    _ = try tree.write("characters/ALICE/aaa.png")
    let portrait = try tree.write("characters/ALICE/portrait.png")
    _ = try tree.write("characters/ALICE/ref-portrait.png")
    #expect(
      try tree.resolver().resolve("ALICE").map(\.lastPathComponent)
        == [portrait.lastPathComponent])
  }

  @Test func testRule3FallsBackToRefPortraitThenAlphabetical() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    _ = try tree.write("characters/BOB/zzz.png")
    _ = try tree.write("characters/BOB/mmm.jpg")
    #expect(try tree.resolver().resolve("BOB").map(\.lastPathComponent) == ["mmm.jpg"])
    _ = try tree.write("characters/BOB/ref-portrait.png")
    #expect(try tree.resolver().resolve("BOB").map(\.lastPathComponent) == ["ref-portrait.png"])
  }

  @Test func testRule4VinetasCharacterSlug() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    try tree.manager.createCharacter(name: "Test Hero", slug: "test-hero", description: "tall")
    let sheet = tree.characterStore.appendingPathComponent("test-hero/references/front.png")
    try tinyPNG().write(to: sheet)
    let resolved = try tree.resolver().resolve("test-hero")
    #expect(resolved.map(\.lastPathComponent) == ["front.png"])
  }

  @Test func testRule2BeatsRule3() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    // A project file literally named ALICE wins over characters/ALICE/.
    let direct = try tree.write("ALICE")
    _ = try tree.write("characters/ALICE/portrait.png")
    #expect(
      try tree.resolver().resolve("ALICE").map(\.path) == [direct.standardizedFileURL.path])
  }

  @Test func testRule3BeatsRule4() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    try tree.manager.createCharacter(name: "ALICE", slug: "ALICE")
    try tinyPNG().write(
      to: tree.characterStore.appendingPathComponent("ALICE/references/front.png"))
    _ = try tree.write("characters/ALICE/portrait.png")
    #expect(try tree.resolver().resolve("ALICE").map(\.lastPathComponent) == ["portrait.png"])
  }

  @Test func testUnresolvedRefMessageNamesEntryAndSearchedPlaces() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    do {
      _ = try tree.resolver().resolve("MISSING-NAME")
      Issue.record("expected an unresolved-reference error")
    } catch let error as StoryboardPanelError {
      let message = error.message
      #expect(message.contains("'MISSING-NAME'"))
      let projectPath = tree.project.standardizedFileURL.path
      let scriptsPath = tree.scripts.standardizedFileURL.path
      let places = [
        "\(projectPath)/MISSING-NAME",
        "\(scriptsPath)/MISSING-NAME",
        "\(projectPath)/characters/MISSING-NAME/",
        "character slug 'MISSING-NAME'",
      ]
      var cursor = message.startIndex
      for place in places {
        let range = message.range(of: place, range: cursor..<message.endIndex)
        #expect(range != nil, "missing or out of order: \(place)")
        if let range { cursor = range.upperBound }
      }
    }
  }

  @Test func testProjectRootIsNearestProjectMD() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    #expect(
      StoryboardReferenceResolver.discoverProjectRoot(documentFolder: tree.scripts).path
        == tree.project.standardizedFileURL.path)
    // A nested PROJECT.md is nearer, so it wins.
    let nested = tree.scripts.appendingPathComponent("episode", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data().write(to: nested.appendingPathComponent("PROJECT.md"))
    #expect(
      StoryboardReferenceResolver.discoverProjectRoot(documentFolder: nested).path
        == nested.standardizedFileURL.path)
    // No PROJECT.md above: the folder itself.
    let loose = tree.base.appendingPathComponent("loose", isDirectory: true)
    try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
    #expect(
      StoryboardReferenceResolver.discoverProjectRoot(documentFolder: loose).path
        == loose.standardizedFileURL.path)
  }

  // MARK: - panelInputs (per-panel wiring)

  private func plan(_ shot: Shot) -> Storyboard.PanelPlan {
    Storyboard().resolvePlan(for: shot, panelNumber: 3, fleetModel: .klein4b)
  }

  @Test func testPanelInputsLoadsRefsInOrderAndCharacter() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    _ = try tree.write("characters/ALICE/portrait.png")
    _ = try tree.write("art/prop.png")
    try tree.manager.createCharacter(name: "Test Hero", slug: "test-hero")
    let shot = Shot(
      documentIndex: 0, prompt: "a room", ref: ["art/prop.png", "ALICE"], character: "test-hero")
    let inputs = try Storyboard().panelInputs(for: plan(shot), resolver: tree.resolver())
    #expect(inputs.references.count == 2)
    #expect(inputs.character?.slug == "test-hero")
  }

  @Test func testPanelInputsUnknownCharacterNamesSlug() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    let shot = Shot(documentIndex: 0, prompt: "a room", character: "no-such-slug")
    #expect {
      try Storyboard().panelInputs(for: plan(shot), resolver: tree.resolver())
    } throws: { error in
      (error as? StoryboardPanelError)?.message.contains("'no-such-slug'") == true
    }
  }

  @Test func testPanelInputsUnresolvedRefNamesPanel() throws {
    let tree = try Tree()
    defer { tree.cleanup() }
    let shot = Shot(documentIndex: 0, prompt: "a room", ref: ["NOPE"])
    #expect {
      try Storyboard().panelInputs(for: plan(shot), resolver: tree.resolver())
    } throws: { error in
      let message = (error as? StoryboardPanelError)?.message ?? ""
      return message.hasPrefix("panel 3:") && message.contains("'NOPE'")
    }
  }

  // MARK: - Reference limits (existing ReferenceValidator, no network)

  private func stubbedClient(_ provider: CloudProvider) -> VinetasClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CountingStubURLProtocol.self]
    let engine = CloudImageEngine(
      provider: provider,
      keyStore: InMemoryAPIKeyStore(keys: [provider: "secret-key"]),
      session: URLSession(configuration: config))
    return VinetasClient(router: EngineRouter(engines: [engine]))
  }

  private func references(_ count: Int) throws -> [ReferenceImage] {
    try (0..<count).map { _ in try ReferenceImage.load(data: tinyPNG(), source: .stdin) }
  }

  @Test func testZeroLimitCloudModelThrowsReferencesUnsupported() async throws {
    CountingStubURLProtocol.hits = 0
    let client = stubbedClient(.blackForestLabs)
    do {
      _ = try await client.generate(
        PanelRequest(
          prompt: "a room", model: CloudModelDescriptor.flux2Pro,
          references: try references(1)))
      Issue.record("expected referencesUnsupported")
    } catch let error as VinetasError {
      guard case .referencesUnsupported = error else {
        Issue.record("wrong error: \(error)")
        return
      }
    }
    #expect(CountingStubURLProtocol.hits == 0)
  }

  @Test func testOverLimitCloudModelThrowsTooManyReferences() async throws {
    CountingStubURLProtocol.hits = 0
    let client = stubbedClient(.openAI)
    let limit = CloudModelDescriptor.gptImage25Flare.maxReferenceImages
    do {
      _ = try await client.generate(
        PanelRequest(
          prompt: "a room", model: CloudModelDescriptor.gptImage25Flare,
          references: try references(limit + 1)))
      Issue.record("expected tooManyReferences")
    } catch let error as VinetasError {
      guard case .tooManyReferences(_, let max, let got) = error else {
        Issue.record("wrong error: \(error)")
        return
      }
      #expect(max == limit)
      #expect(got == limit + 1)
    }
    #expect(CountingStubURLProtocol.hits == 0)
  }
}

import Crypto
import Foundation
import SwiftASN1
import SwiftVinetas
import Testing
import X509

@testable import VinetasCLICore

// MARK: - ProGateTests
//
// The CLI ships inside the Vinetas app bundle and reaches the same models the
// GUI does, so without a gate it is a way around the FLUX.2 in-app purchase.
// These tests pin the two properties that matter:
//
//   1. Which models are gated (FLUX.2 yes, PixArt no).
//   2. That a marker file only counts if Apple actually signed it — a user with
//      a text editor must not be able to mint one.
//
// Chain validation is exercised against a locally generated root so the tests
// stay hermetic; the production path pins Apple Root CA G3 instead.

@Suite("ProGate — which models need the unlock")
struct ProGateModelTests {

  @Test("FLUX.2 models require Pro")
  func fluxRequiresPro() {
    #expect(ProGate.requiresPro(.klein4b))
    #expect(ProGate.requiresPro(.klein9b))
  }

  @Test("PixArt is free")
  func pixartIsFree() {
    #expect(!ProGate.requiresPro(.pixartSigma))
  }

  @Test("Every model is classified as exactly one of gated or free")
  func everyModelClassified() {
    // Guards against a future model landing in neither branch because the
    // engine id changed.
    for model in VinetasModel.allCases {
      let engine = model.descriptor.engineID
      #expect(
        engine == "flux2" || engine == "pixart-sigma",
        "unclassified engine '\(engine)' for \(model.rawValue) — update ProGate"
      )
    }
  }
}

@Suite("SignedTransaction — a marker only counts if Apple signed it")
struct SignedTransactionTests {

  // MARK: Fixtures

  /// A throwaway CA plus a leaf it signs, standing in for Apple's chain.
  struct TestChain {
    let rootDER: [UInt8]
    let leafBase64: String
    let leafKey: P256.Signing.PrivateKey
  }

  static func makeChain() throws -> TestChain {
    let rootKey = P256.Signing.PrivateKey()
    let rootName = try DistinguishedName { CommonName("Test Root") }
    let now = Date()
    let root = try Certificate(
      version: .v3,
      serialNumber: Certificate.SerialNumber(),
      publicKey: Certificate.PublicKey(rootKey.publicKey),
      notValidBefore: now.addingTimeInterval(-3600),
      notValidAfter: now.addingTimeInterval(86400),
      issuer: rootName,
      subject: rootName,
      signatureAlgorithm: .ecdsaWithSHA256,
      extensions: try Certificate.Extensions {
        Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
        Critical(KeyUsage(keyCertSign: true))
      },
      issuerPrivateKey: Certificate.PrivateKey(rootKey)
    )

    let leafKey = P256.Signing.PrivateKey()
    let leaf = try Certificate(
      version: .v3,
      serialNumber: Certificate.SerialNumber(),
      publicKey: Certificate.PublicKey(leafKey.publicKey),
      notValidBefore: now.addingTimeInterval(-3600),
      notValidAfter: now.addingTimeInterval(86400),
      issuer: rootName,
      subject: try DistinguishedName { CommonName("Test Leaf") },
      signatureAlgorithm: .ecdsaWithSHA256,
      extensions: try Certificate.Extensions {
        Critical(BasicConstraints.notCertificateAuthority)
      },
      issuerPrivateKey: Certificate.PrivateKey(rootKey)
    )

    var rootSerializer = DER.Serializer()
    try rootSerializer.serialize(root)
    var leafSerializer = DER.Serializer()
    try leafSerializer.serialize(leaf)

    return TestChain(
      rootDER: rootSerializer.serializedBytes,
      leafBase64: Data(leafSerializer.serializedBytes).base64EncodedString(),
      leafKey: leafKey
    )
  }

  static func b64url(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Build a JWS signed by `chain`'s leaf. `sign: false` produces a
  /// structurally valid but unsigned token.
  static func makeJWS(
    chain: TestChain,
    payload: [String: Any],
    sign: Bool = true
  ) throws -> String {
    let header: [String: Any] = ["alg": "ES256", "x5c": [chain.leafBase64]]
    let headerPart = b64url(try JSONSerialization.data(withJSONObject: header))
    let payloadPart = b64url(try JSONSerialization.data(withJSONObject: payload))
    let signingInput = Data("\(headerPart).\(payloadPart)".utf8)
    let signature: Data
    if sign {
      signature = try chain.leafKey.signature(for: SHA256.hash(data: signingInput))
        .rawRepresentation
    } else {
      signature = Data(repeating: 0, count: 64)
    }
    return "\(headerPart).\(payloadPart).\(b64url(signature))"
  }

  /// Built fresh per call: a `[String: Any]` static would not be Sendable.
  static func validPayload() -> [String: Any] {
    [
      "productId": ProGate.proProductID,
      "bundleId": ProGate.expectedBundleID,
      "type": "Non-Consumable",
    ]
  }

  // MARK: Accepting a genuine token

  @Test("A properly signed transaction verifies")
  func genuineTokenVerifies() async throws {
    let chain = try Self.makeChain()
    let jws = try Self.makeJWS(chain: chain, payload: Self.validPayload())

    let transaction = try await SignedTransaction.verify(jws: jws, rootDER: chain.rootDER)

    #expect(transaction.productID == ProGate.proProductID)
    #expect(transaction.bundleID == ProGate.expectedBundleID)
    #expect(transaction.revocationDate == nil)
  }

  @Test("A revocation date is carried through")
  func revocationParsed() async throws {
    let chain = try Self.makeChain()
    var payload = Self.validPayload()
    // StoreKit reports milliseconds since the epoch.
    payload["revocationDate"] = 1_700_000_000_000.0
    let jws = try Self.makeJWS(chain: chain, payload: payload)

    let transaction = try await SignedTransaction.verify(jws: jws, rootDER: chain.rootDER)

    #expect(transaction.revocationDate == Date(timeIntervalSince1970: 1_700_000_000))
  }

  // MARK: Rejecting forgeries

  @Test("A hand-written JSON file is not a JWS")
  func plainJSONRejected() async throws {
    await #expect(throws: SignedTransaction.VerificationError.self) {
      try await SignedTransaction.verify(jws: #"{"pro":true}"#)
    }
  }

  @Test("A structurally valid but unsigned token is rejected")
  func unsignedTokenRejected() async throws {
    let chain = try Self.makeChain()
    let jws = try Self.makeJWS(chain: chain, payload: Self.validPayload(), sign: false)

    await #expect(throws: SignedTransaction.VerificationError.self) {
      try await SignedTransaction.verify(jws: jws, rootDER: chain.rootDER)
    }
  }

  @Test("A token signed by an unrelated CA does not verify against our root")
  func foreignChainRejected() async throws {
    // The attacker mints their own perfectly valid chain — it just is not ours.
    let attacker = try Self.makeChain()
    let ours = try Self.makeChain()
    let jws = try Self.makeJWS(chain: attacker, payload: Self.validPayload())

    await #expect(throws: SignedTransaction.VerificationError.self) {
      try await SignedTransaction.verify(jws: jws, rootDER: ours.rootDER)
    }
  }

  @Test("A token with no certificate chain is rejected")
  func missingChainRejected() async throws {
    let headerPart = Self.b64url(
      try JSONSerialization.data(withJSONObject: ["alg": "ES256"]))
    let payloadPart = Self.b64url(
      try JSONSerialization.data(withJSONObject: Self.validPayload()))
    let jws = "\(headerPart).\(payloadPart).\(Self.b64url(Data(repeating: 0, count: 64)))"

    await #expect(throws: SignedTransaction.VerificationError.self) {
      try await SignedTransaction.verify(jws: jws)
    }
  }

  @Test("Algorithms other than ES256 are refused")
  func algorithmConfusionRejected() async throws {
    // `alg: none` is the classic JWT bypass; it must not be honoured.
    let header = Self.b64url(try JSONSerialization.data(withJSONObject: ["alg": "none"]))
    let payload = Self.b64url(
      try JSONSerialization.data(withJSONObject: Self.validPayload()))
    let jws = "\(header).\(payload)."

    await #expect(throws: SignedTransaction.VerificationError.self) {
      try await SignedTransaction.verify(jws: jws)
    }
  }

  // MARK: The local-StoreKit carve-out

  @Test("Environment is carried through verification")
  func environmentParsed() async throws {
    let chain = try Self.makeChain()
    var payload = Self.validPayload()
    payload["environment"] = "Production"
    let jws = try Self.makeJWS(chain: chain, payload: payload)

    let transaction = try await SignedTransaction.verify(jws: jws, rootDER: chain.rootDER)

    #expect(transaction.environment == "Production")
  }

  @Test("Unverified parsing exposes the environment so Xcode tokens are recognisable")
  func unverifiedParseReadsEnvironment() throws {
    // Xcode's StoreKit testing signs with a per-machine root, so such a token
    // can only ever be identified by reading it without verifying — which is
    // why the carve-out that consumes this is DEBUG-only.
    let chain = try Self.makeChain()
    var payload = Self.validPayload()
    payload["environment"] = SignedTransaction.xcodeTestEnvironment
    let jws = try Self.makeJWS(chain: chain, payload: payload, sign: false)

    let parsed = try #require(SignedTransaction.parseUnverifiedPayload(jws: jws))

    #expect(parsed.environment == SignedTransaction.xcodeTestEnvironment)
    #expect(parsed.productID == ProGate.proProductID)
  }

  @Test("Unverified parsing rejects malformed input rather than inventing a transaction")
  func unverifiedParseRejectsGarbage() {
    #expect(SignedTransaction.parseUnverifiedPayload(jws: "not-a-jws") == nil)
    #expect(SignedTransaction.parseUnverifiedPayload(jws: "a.b.c") == nil)
    // Structurally fine, but missing the fields an access decision needs.
    let payload = Self.b64url(Data(#"{"environment":"Xcode"}"#.utf8))
    #expect(SignedTransaction.parseUnverifiedPayload(jws: "x.\(payload).y") == nil)
  }

  @Test("Unverified parsing never claims a token is trustworthy")
  func unverifiedParseIsNotVerification() async throws {
    // The same token that parses must still fail real verification — the two
    // paths must not be confusable.
    let chain = try Self.makeChain()
    var payload = Self.validPayload()
    payload["environment"] = SignedTransaction.xcodeTestEnvironment
    let jws = try Self.makeJWS(chain: chain, payload: payload, sign: false)

    #expect(SignedTransaction.parseUnverifiedPayload(jws: jws) != nil)
    await #expect(throws: SignedTransaction.VerificationError.self) {
      try await SignedTransaction.verify(jws: jws, rootDER: chain.rootDER)
    }
  }

  @Test("The pinned Apple root is a parseable certificate")
  func pinnedRootParses() throws {
    let root = try Certificate(derEncoded: AppleRootCA.g3DER)
    #expect(root.subject.description.contains("Apple Root CA - G3"))
    // Self-signed root: issuer and subject match.
    #expect(root.issuer == root.subject)
  }
}

import Crypto
import Foundation
import X509

/// A StoreKit 2 `Transaction.jwsRepresentation`, parsed and cryptographically
/// verified against the pinned Apple root.
///
/// The Vinetas app writes its verified Pro transaction into the shared App
/// Group container; this type is how the CLI decides whether to believe it.
/// Because the payload is signed by Apple, a user cannot mint one by editing a
/// file — they would have to forge a signature chaining to Apple Root CA G3.
///
/// ## What this does not defend against
///
/// The JWS is a **bearer token**. Someone who genuinely bought Vinetas Pro
/// could publish their transaction and others could paste it into their own
/// container. That is a deliberate trade-off: closing it would mean binding the
/// entitlement to a device or account identity the CLI cannot check offline. The
/// bar this sets — a real purchase must exist somewhere — is the same one most
/// receipt-validating apps settle for, and it is enormously higher than the
/// nothing that came before it.
struct SignedTransaction: Sendable {

  /// The product this transaction grants.
  let productID: String
  /// The bundle the purchase was made in.
  let bundleID: String
  /// Set when Apple has revoked the purchase (refund, family sharing removal).
  let revocationDate: Date?

  enum VerificationError: Error, CustomStringConvertible {
    case malformedJWS(String)
    case unsupportedAlgorithm(String)
    case missingCertificateChain
    case untrustedChain
    case badSignature
    case malformedPayload(String)

    var description: String {
      switch self {
      case .malformedJWS(let detail):
        "the stored entitlement is not a well-formed JWS (\(detail))"
      case .unsupportedAlgorithm(let alg):
        "the stored entitlement uses an unsupported algorithm '\(alg)'"
      case .missingCertificateChain:
        "the stored entitlement carries no x5c certificate chain"
      case .untrustedChain:
        "the entitlement's certificate chain does not lead to the Apple root"
      case .badSignature:
        "the entitlement's signature does not verify"
      case .malformedPayload(let detail):
        "the entitlement payload is malformed (\(detail))"
      }
    }
  }

  // MARK: - Parsing + verification

  /// Parse and fully verify a compact JWS.
  ///
  /// Verification is: ES256 only, an `x5c` chain that validates to the pinned
  /// Apple Root CA G3 under RFC 5280, and a signature over
  /// `base64url(header).base64url(payload)` made by the leaf certificate's key.
  static func verify(
    jws: String,
    now: Date = Date(),
    rootDER: [UInt8] = AppleRootCA.g3DER
  ) async throws -> SignedTransaction {
    let parts = jws.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else {
      throw VerificationError.malformedJWS("expected 3 dot-separated segments, got \(parts.count)")
    }

    guard
      let headerData = base64URLDecode(String(parts[0])),
      let payloadData = base64URLDecode(String(parts[1])),
      let signatureData = base64URLDecode(String(parts[2]))
    else {
      throw VerificationError.malformedJWS("a segment is not valid base64url")
    }

    // --- header: algorithm + certificate chain -----------------------------

    guard
      let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
    else {
      throw VerificationError.malformedJWS("header is not a JSON object")
    }
    let alg = header["alg"] as? String ?? ""
    guard alg == "ES256" else { throw VerificationError.unsupportedAlgorithm(alg) }

    guard let x5c = header["x5c"] as? [String], !x5c.isEmpty else {
      throw VerificationError.missingCertificateChain
    }
    let chain: [Certificate] = try x5c.map { entry in
      guard let der = Data(base64Encoded: entry) else {
        throw VerificationError.malformedJWS("an x5c entry is not valid base64")
      }
      guard let certificate = try? Certificate(derEncoded: [UInt8](der)) else {
        throw VerificationError.malformedJWS("an x5c entry is not a valid certificate")
      }
      return certificate
    }
    guard let leaf = chain.first else { throw VerificationError.missingCertificateChain }
    let intermediates = CertificateStore(chain.dropFirst())

    // --- chain validation to the pinned root -------------------------------

    let root = try Certificate(derEncoded: rootDER)
    var verifier = Verifier(rootCertificates: CertificateStore([root])) {
      RFC5280Policy(validationTime: now)
    }
    let result = await verifier.validate(
      leafCertificate: leaf,
      intermediates: intermediates
    )
    guard case .validCertificate = result else {
      throw VerificationError.untrustedChain
    }

    // --- signature over the signing input ----------------------------------

    let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
    guard let publicKey = P256.Signing.PublicKey(leaf.publicKey) else {
      throw VerificationError.badSignature
    }
    // JWS ES256 signatures are the raw r||s concatenation, not DER.
    guard
      let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
      publicKey.isValidSignature(signature, for: SHA256.hash(data: signingInput))
    else {
      throw VerificationError.badSignature
    }

    // --- payload -----------------------------------------------------------

    guard
      let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    else {
      throw VerificationError.malformedPayload("payload is not a JSON object")
    }
    guard let productID = payload["productId"] as? String else {
      throw VerificationError.malformedPayload("no productId")
    }
    guard let bundleID = payload["bundleId"] as? String else {
      throw VerificationError.malformedPayload("no bundleId")
    }
    // StoreKit timestamps are milliseconds since the epoch.
    var revocationDate: Date?
    if let millis = payload["revocationDate"] as? Double {
      revocationDate = Date(timeIntervalSince1970: millis / 1000)
    }

    return SignedTransaction(
      productID: productID,
      bundleID: bundleID,
      revocationDate: revocationDate
    )
  }

  /// base64url → Data, restoring the padding JWS strips.
  static func base64URLDecode(_ string: String) -> Data? {
    var s = string.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let remainder = s.count % 4
    if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
    return Data(base64Encoded: s)
  }
}

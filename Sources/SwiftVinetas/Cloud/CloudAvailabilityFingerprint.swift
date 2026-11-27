import CryptoKit
import Foundation

/// A short salted hash of an API key, used only to notice that the key changed.
/// The key is an input to the hash and is never stored, logged or returned.
enum CloudAvailabilityFingerprint {

  /// Hex characters kept from the digest (64 bits).
  static let length = 16

  static func make(apiKey: String, salt: Data) -> String {
    var input = salt
    input.append(Data(apiKey.utf8))
    let digest = SHA256.hash(data: input)
    return String(digest.map { String(format: "%02x", $0) }.joined().prefix(length))
  }
}

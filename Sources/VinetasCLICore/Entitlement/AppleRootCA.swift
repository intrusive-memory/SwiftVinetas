import Foundation

/// The Apple Root CA - G3 certificate, pinned.
///
/// App Store `Transaction.jwsRepresentation` values are JWS objects whose `x5c`
/// header carries the signing chain. Verifying that chain is only meaningful if
/// it terminates in a root we trust *a priori* — otherwise an attacker simply
/// mints their own chain and puts it in the header. So the root is compiled in
/// rather than read from disk or the system trust store.
///
/// Source: https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
/// Subject/Issuer: CN=Apple Root CA - G3, O=Apple Inc., C=US (self-signed)
/// Valid: 2014-04-30 … 2039-04-30
/// SHA-256: 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:
///          7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
enum AppleRootCA {

  /// DER encoding of the root certificate, base64 (line breaks are stripped).
  static let g3Base64 = """
    MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9v
    dCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UE
    CgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2
    WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmlj
    YXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqG
    SM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxE
    tX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNC
    MEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P
    AQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3m
    eoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkL
    F1vLUagM6BgD56KyKA==
    """

  /// DER bytes of the pinned root.
  static var g3DER: [UInt8] {
    let compact = g3Base64.filter { !$0.isWhitespace }
    guard let data = Data(base64Encoded: compact) else {
      // Compiled-in constant: if this ever fails the build is corrupt.
      fatalError("VinetasCLI: pinned Apple root CA is not valid base64")
    }
    return [UInt8](data)
  }
}

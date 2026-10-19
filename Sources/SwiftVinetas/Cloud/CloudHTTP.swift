import CoreGraphics
import Foundation
import ImageIO

// Shared HTTP, image-decoding, and dimension helpers for the vendor adapters.

/// The decoded output of a vendor call.
struct CloudImageOutput: Sendable {
  let image: CGImage
  /// The seed the vendor reports (or the one we sent), when the vendor
  /// supports seeds at all.
  let seed: UInt64?
}

/// One vendor's request/response shaping. Implementations are stateless; the
/// engine supplies the key and session per call.
protocol CloudProviderClient: Sendable {
  var provider: CloudProvider { get }

  func generate(
    _ request: GenerationRequest,
    model: CloudModelDescriptor,
    apiKey: String,
    session: URLSession
  ) async throws -> CloudImageOutput
}

enum CloudHTTP {

  /// Back-off schedule for retryable statuses (429 Too Many Requests, 503
  /// Service Unavailable): two retries, one and two seconds apart, unless the
  /// vendor's `Retry-After` header asks for something else (capped at 30 s).
  static let defaultRetryDelays: [TimeInterval] = [1, 2]

  /// A session tuned for slow image endpoints: generous per-request timeout,
  /// no caching of responses that contain image bytes.
  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 120
    config.timeoutIntervalForResource = 600
    config.waitsForConnectivity = true
    return URLSession(configuration: config)
  }

  /// Performs `request`, returning the body and response, and maps non-2xx
  /// statuses to ``CloudEngineError/httpStatus(provider:status:message:)``.
  /// Rate-limit and transient-unavailable statuses are retried per
  /// `retryDelays` before the error surfaces.
  static func perform(
    _ request: URLRequest,
    session: URLSession,
    provider: CloudProvider,
    retryDelays: [TimeInterval] = defaultRetryDelays
  ) async throws -> (Data, HTTPURLResponse) {
    var attempt = 0
    while true {
      try Task.checkCancellation()
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw CloudEngineError.invalidResponse(provider: provider, detail: "non-HTTP response")
      }
      if (200..<300).contains(http.statusCode) {
        return (data, http)
      }
      if isRetryable(http.statusCode), attempt < retryDelays.count {
        let delay = retryAfter(http) ?? retryDelays[attempt]
        attempt += 1
        try await Task.sleep(for: .seconds(delay))
        continue
      }
      if http.statusCode == 401 || http.statusCode == 403 {
        throw CloudEngineError.httpStatus(
          provider: provider, status: http.statusCode,
          message: errorMessage(from: data)
            ?? "check the API key (\(provider.environmentVariable) or Vinetas → Settings → Cloud Engines)"
        )
      }
      throw CloudEngineError.httpStatus(
        provider: provider, status: http.statusCode, message: errorMessage(from: data))
    }
  }

  static func isRetryable(_ status: Int) -> Bool {
    status == 429 || status == 503
  }

  /// `Retry-After` in seconds when the vendor sent a numeric value, clamped
  /// to 0…30 so a hostile header cannot park the CLI.
  static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
    guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
      let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces))
    else { return nil }
    return min(30, max(0, seconds))
  }

  /// Best-effort extraction of a human-readable error from a vendor's JSON
  /// error body. Handles `{"error": {"message": …}}`, `{"error": "…"}`,
  /// `{"message": "…"}`, `{"errors": ["…"]}`, and `{"detail": …}`.
  static func errorMessage(from data: Data) -> String? {
    guard !data.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      let text = String(decoding: data.prefix(300), as: UTF8.self)
      return text.isEmpty ? nil : text
    }
    if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
      return message
    }
    if let error = object["error"] as? String { return error }
    if let message = object["message"] as? String { return message }
    if let errors = object["errors"] as? [String], !errors.isEmpty {
      return errors.joined(separator: "; ")
    }
    if let detail = object["detail"] as? String { return detail }
    if let detail = object["detail"] as? [[String: Any]],
      let first = detail.first, let message = first["msg"] as? String
    {
      return message
    }
    return nil
  }

  /// Decodes PNG/JPEG/WebP bytes into a `CGImage`.
  static func decodeImage(_ data: Data, provider: CloudProvider) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw CloudEngineError.imageDecodingFailed(provider: provider)
    }
    return image
  }

  /// Decodes a base64 string (with or without a `data:` prefix) into a `CGImage`.
  static func decodeBase64Image(_ base64: String, provider: CloudProvider) throws -> CGImage {
    var payload = base64
    if let comma = payload.firstIndex(of: ","), payload.hasPrefix("data:") {
      payload = String(payload[payload.index(after: comma)...])
    }
    guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
      throw CloudEngineError.imageDecodingFailed(provider: provider)
    }
    return try decodeImage(data, provider: provider)
  }

  /// Builds a `multipart/form-data` body from string fields.
  static func multipartBody(fields: [(name: String, value: String)], boundary: String) -> Data {
    var body = Data()
    for field in fields {
      body.append(Data("--\(boundary)\r\n".utf8))
      body.append(Data("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".utf8))
      body.append(Data(field.value.utf8))
      body.append(Data("\r\n".utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return body
  }
}

// MARK: - Dimensions

/// Maps the requested output dimensions onto what a vendor accepts.
enum CloudDimensions {

  /// Scales `(width, height)` so the longer edge is at most `maxEdge`,
  /// preserving aspect, then snaps both edges to a multiple of `multiple`
  /// and clamps to `minEdge`.
  static func fit(
    width: Int, height: Int,
    maxEdge: Int, minEdge: Int, multiple: Int
  ) -> (width: Int, height: Int) {
    let longest = Double(max(width, height))
    let scale = min(1.0, Double(maxEdge) / longest)
    func snap(_ value: Int) -> Int {
      let scaled = Double(value) * scale
      let snapped = Int((scaled / Double(multiple)).rounded()) * multiple
      return min(maxEdge, max(minEdge, snapped))
    }
    return (snap(width), snap(height))
  }

  /// Picks the candidate whose numeric ratio is closest to `width / height`.
  static func nearestRatio<Label>(
    width: Int, height: Int,
    candidates: [(label: Label, ratio: Double)]
  ) -> Label {
    precondition(!candidates.isEmpty)
    let target = Double(width) / Double(max(1, height))
    return candidates.min {
      abs(log($0.ratio) - log(target)) < abs(log($1.ratio) - log(target))
    }!.label
  }
}

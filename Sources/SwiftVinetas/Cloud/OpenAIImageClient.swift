import Foundation

/// OpenAI Images API adapter (`POST /v1/images/generations`).
///
/// The `gpt-image-2.5` models return base64 PNG data and accept an explicit
/// `WIDTHxHEIGHT` size: multiples of 16, aspect between 1:3 and 3:1, no edge
/// over 3840, and between 655,360 and 8,294,400 pixels. They take no steps,
/// guidance, seed, or negative prompt.
struct OpenAIImageClient: CloudProviderClient {

  let provider: CloudProvider = .openAI

  /// Overridable for tests; production uses the public endpoint.
  var endpoint = URL(string: "https://api.openai.com/v1/images/generations")!

  /// Output quality hint. `auto` lets the vendor pick; exposed so a future
  /// setting can trade cost for fidelity.
  var quality = "auto"

  /// Vendor constraints. The longest edge is capped at 2048 rather than the
  /// vendor's 3840 because larger outputs are billed per token and marked
  /// experimental above 2560×1440.
  static let dimensionMultiple = 16
  static let maxEdge = 2048
  static let minEdge = 512
  static let minPixels = 655_360
  static let maxPixels = 8_294_400
  static let maxRatio = 3.0

  func generate(
    _ request: GenerationRequest,
    model: CloudModelDescriptor,
    apiKey: String,
    session: URLSession
  ) async throws -> CloudImageOutput {
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "model": model.vendorModelID,
      "prompt": request.prompt,
      "n": 1,
      "size": Self.size(width: request.width, height: request.height),
      "quality": quality,
      "output_format": "png",
    ]
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await CloudHTTP.perform(urlRequest, session: session, provider: provider)

    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = object["data"] as? [[String: Any]],
      let first = items.first
    else {
      throw CloudEngineError.invalidResponse(provider: provider, detail: "missing data[0]")
    }

    if let b64 = first["b64_json"] as? String {
      return CloudImageOutput(
        image: try CloudHTTP.decodeBase64Image(b64, provider: provider), seed: nil)
    }
    if let urlString = first["url"] as? String, let url = URL(string: urlString) {
      let (bytes, _) = try await CloudHTTP.perform(
        URLRequest(url: url), session: session, provider: provider)
      return CloudImageOutput(
        image: try CloudHTTP.decodeImage(bytes, provider: provider), seed: nil)
    }
    throw CloudEngineError.invalidResponse(
      provider: provider, detail: "no b64_json or url in data[0]")
  }

  /// Fits the requested dimensions to the vendor's rules as an explicit
  /// `WIDTHxHEIGHT`, or `auto` when no conforming size preserves the aspect.
  static func size(width: Int, height: Int) -> String {
    let dims = CloudDimensions.fit(
      width: width, height: height,
      maxEdge: maxEdge, minEdge: minEdge, multiple: dimensionMultiple)
    let ratio = Double(dims.width) / Double(max(1, dims.height))
    let pixels = dims.width * dims.height
    guard ratio <= maxRatio, ratio >= 1.0 / maxRatio,
      pixels >= minPixels, pixels <= maxPixels
    else { return "auto" }
    return "\(dims.width)x\(dims.height)"
  }
}

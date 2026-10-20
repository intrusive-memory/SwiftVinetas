import Foundation

/// Google Gemini API adapter for the Nano Banana image models
/// (`POST /v1beta/interactions`).
///
/// The Interactions API takes the prompt as `input` and an image
/// `response_format` naming the MIME type (the vendor only emits
/// `image/jpeg`), an aspect-ratio preset, and a `1K` / `2K` / `4K` size
/// tier. The reply is a list of `steps`; the `model_output` step carries
/// base64 `image` content blocks. The vendor takes no steps, guidance, seed,
/// or negative prompt.
///
/// With reference images, `input` becomes a list of content blocks: one
/// `text` block carrying the prompt, then one inline base64 `image` block per
/// reference, in the order supplied.
struct GeminiImageClient: CloudProviderClient {

  let provider: CloudProvider = .google

  /// Overridable for tests; production uses the public endpoint.
  var endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!

  /// The vendor's aspect-ratio presets.
  static let aspectRatios: [(label: String, ratio: Double)] = [
    ("1:1", 1.0), ("3:2", 1.5), ("2:3", 2.0 / 3.0),
    ("4:3", 4.0 / 3.0), ("3:4", 0.75), ("5:4", 1.25), ("4:5", 0.8),
    ("16:9", 16.0 / 9.0), ("9:16", 9.0 / 16.0), ("21:9", 21.0 / 9.0),
  ]

  func generate(
    _ request: GenerationRequest,
    model: CloudModelDescriptor,
    apiKey: String,
    session: URLSession
  ) async throws -> CloudImageOutput {
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let input: Any
    if case .imageToImage(let references) = request.mode, !references.isEmpty {
      var blocks: [[String: Any]] = [["type": "text", "text": request.prompt]]
      for image in references {
        blocks.append([
          "type": "image",
          "mime_type": "image/jpeg",
          "data": try CloudHTTP.encodeReference(image, provider: provider).base64EncodedString(),
        ])
      }
      input = blocks
    } else {
      input = request.prompt
    }

    let body: [String: Any] = [
      "model": model.vendorModelID,
      "input": input,
      "response_format": [
        "type": "image",
        "mime_type": "image/jpeg",
        "aspect_ratio": Self.aspectRatio(width: request.width, height: request.height),
        "image_size": Self.imageSize(width: request.width, height: request.height),
      ],
    ]
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await CloudHTTP.perform(urlRequest, session: session, provider: provider)

    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CloudEngineError.invalidResponse(provider: provider, detail: "non-JSON body")
    }

    if let errors = object["errors"] as? [[String: Any]],
      let first = errors.first, let message = first["message"] as? String
    {
      throw CloudEngineError.invalidResponse(provider: provider, detail: message)
    }

    var sawText = false
    for step in object["steps"] as? [[String: Any]] ?? []
    where step["type"] as? String == "model_output" {
      for block in step["content"] as? [[String: Any]] ?? [] {
        switch block["type"] as? String {
        case "image":
          if let b64 = block["data"] as? String {
            return CloudImageOutput(
              image: try CloudHTTP.decodeBase64Image(b64, provider: provider), seed: nil)
          }
        case "text":
          sawText = true
        default:
          continue
        }
      }
    }

    // An image model that answers with prose instead of pixels has declined
    // the prompt; surface that as moderation rather than as a malformed reply.
    if sawText { throw CloudEngineError.moderated(provider: provider) }
    let status = object["status"] as? String ?? "unknown"
    throw CloudEngineError.invalidResponse(
      provider: provider, detail: "no image in model_output (status \(status))")
  }

  /// Nearest vendor preset for the requested dimensions.
  static func aspectRatio(width: Int, height: Int) -> String {
    CloudDimensions.nearestRatio(width: width, height: height, candidates: aspectRatios)
  }

  /// Size tier for the requested dimensions. `1K` is roughly a 1024-pixel
  /// longest edge, `2K` about 2048, `4K` about 4096; the thresholds sit
  /// midway so a preset rounds to the nearest tier it will actually fill.
  static func imageSize(width: Int, height: Int) -> String {
    let longest = max(width, height)
    if longest <= 1280 { return "1K" }
    if longest <= 2560 { return "2K" }
    return "4K"
  }
}

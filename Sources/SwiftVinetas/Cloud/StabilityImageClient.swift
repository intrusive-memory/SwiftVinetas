import Foundation

/// Stability AI Stable Image adapter
/// (`POST /v2beta/stable-image/generate/{core|ultra}`).
///
/// The request is `multipart/form-data`; with `Accept: image/*` the vendor
/// returns raw image bytes and reports the seed it used in a `seed` header.
/// Output size is controlled by an aspect-ratio preset, not pixel dimensions.
struct StabilityImageClient: CloudProviderClient {

  let provider: CloudProvider = .stabilityAI

  /// Overridable for tests.
  var baseURL = URL(string: "https://api.stability.ai/v2beta/stable-image/generate")!

  /// The vendor's aspect-ratio presets.
  static let aspectRatios: [(label: String, ratio: Double)] = [
    ("1:1", 1.0), ("16:9", 16.0 / 9.0), ("21:9", 21.0 / 9.0),
    ("3:2", 1.5), ("2:3", 2.0 / 3.0), ("5:4", 1.25), ("4:5", 0.8),
    ("9:16", 9.0 / 16.0), ("9:21", 9.0 / 21.0),
  ]

  func generate(
    _ request: GenerationRequest,
    model: CloudModelDescriptor,
    apiKey: String,
    session: URLSession
  ) async throws -> CloudImageOutput {
    var fields: [(name: String, value: String)] = [
      ("prompt", request.prompt),
      ("aspect_ratio", Self.aspectRatio(width: request.width, height: request.height)),
      ("output_format", "png"),
    ]
    if model.supportsNegativePrompt, let negative = request.negativePrompt, !negative.isEmpty {
      fields.append(("negative_prompt", negative))
    }
    if model.supportsSeed, let seed = request.seed {
      // Vendor range is 0…4294967294.
      fields.append(("seed", String(seed % 4_294_967_294)))
    }

    let boundary = "VinetasBoundary-\(UUID().uuidString)"
    var urlRequest = URLRequest(url: baseURL.appending(path: model.vendorModelID))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
    urlRequest.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = CloudHTTP.multipartBody(fields: fields, boundary: boundary)

    let (data, response) = try await CloudHTTP.perform(
      urlRequest, session: session, provider: provider)

    if let finish = response.value(forHTTPHeaderField: "finish-reason"),
      finish == "CONTENT_FILTERED"
    {
      throw CloudEngineError.moderated(provider: provider)
    }

    let image = try CloudHTTP.decodeImage(data, provider: provider)
    let seed = response.value(forHTTPHeaderField: "seed").flatMap { UInt64($0) }
    return CloudImageOutput(image: image, seed: seed)
  }

  /// Nearest vendor preset for the requested dimensions.
  static func aspectRatio(width: Int, height: Int) -> String {
    CloudDimensions.nearestRatio(width: width, height: height, candidates: aspectRatios)
  }
}

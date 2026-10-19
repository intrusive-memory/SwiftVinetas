import Foundation

/// Black Forest Labs FLUX API adapter.
///
/// Submission is `POST https://api.bfl.ai/v1/<model>` with an `x-key` header;
/// the response carries a `polling_url` that is polled until `status` is
/// `Ready`, at which point `result.sample` is a short-lived signed URL to the
/// image. The sample is downloaded immediately because those URLs expire.
struct BFLImageClient: CloudProviderClient {

  let provider: CloudProvider = .blackForestLabs

  /// Overridable for tests and for the EU/US regional hosts.
  var baseURL = URL(string: "https://api.bfl.ai/v1")!

  /// Seconds between polls and the overall polling budget.
  var pollInterval: TimeInterval = 1.0
  var pollTimeout: TimeInterval = 240

  /// The vendor accepts multiples of 16; 32 is used for extra headroom.
  /// Edges are kept within 256…1440 so every model variant accepts them.
  static let dimensionMultiple = 32
  static let maxEdge = 1440
  static let minEdge = 256

  func generate(
    _ request: GenerationRequest,
    model: CloudModelDescriptor,
    apiKey: String,
    session: URLSession
  ) async throws -> CloudImageOutput {
    let dims = CloudDimensions.fit(
      width: request.width, height: request.height,
      maxEdge: Self.maxEdge, minEdge: Self.minEdge, multiple: Self.dimensionMultiple)

    var body: [String: Any] = [
      "prompt": request.prompt,
      "width": dims.width,
      "height": dims.height,
      "output_format": "png",
      "safety_tolerance": 2,
    ]
    if model.supportsSeed, let seed = request.seed {
      // The vendor takes a 32-bit seed.
      body["seed"] = Int(seed % UInt64(Int32.max))
    }
    if model.supportsSteps { body["steps"] = request.steps }
    if model.supportsGuidance { body["guidance"] = request.guidanceScale }

    var submit = URLRequest(url: baseURL.appending(path: model.vendorModelID))
    submit.httpMethod = "POST"
    submit.setValue(apiKey, forHTTPHeaderField: "x-key")
    submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
    submit.setValue("application/json", forHTTPHeaderField: "Accept")
    submit.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (submitData, _) = try await CloudHTTP.perform(submit, session: session, provider: provider)
    guard let submitObject = try? JSONSerialization.jsonObject(with: submitData) as? [String: Any],
      let pollingString = submitObject["polling_url"] as? String,
      let pollingURL = URL(string: pollingString)
    else {
      throw CloudEngineError.invalidResponse(provider: provider, detail: "missing polling_url")
    }

    let sampleURL = try await poll(pollingURL, apiKey: apiKey, session: session)

    let (imageData, _) = try await CloudHTTP.perform(
      URLRequest(url: sampleURL), session: session, provider: provider)
    let image = try CloudHTTP.decodeImage(imageData, provider: provider)
    let seed = (body["seed"] as? Int).map(UInt64.init)
    return CloudImageOutput(image: image, seed: seed)
  }

  /// Polls until the job is `Ready` and returns the sample URL.
  private func poll(_ pollingURL: URL, apiKey: String, session: URLSession) async throws -> URL {
    let deadline = Date().addingTimeInterval(pollTimeout)
    while Date() < deadline {
      try Task.checkCancellation()
      try await Task.sleep(for: .seconds(pollInterval))

      var pollRequest = URLRequest(url: pollingURL)
      pollRequest.setValue(apiKey, forHTTPHeaderField: "x-key")
      pollRequest.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, _) = try await CloudHTTP.perform(pollRequest, session: session, provider: provider)

      guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let status = object["status"] as? String
      else {
        throw CloudEngineError.invalidResponse(provider: provider, detail: "missing status")
      }

      switch status {
      case "Ready":
        guard let result = object["result"] as? [String: Any],
          let sample = result["sample"] as? String,
          let url = URL(string: sample)
        else {
          throw CloudEngineError.invalidResponse(
            provider: provider, detail: "missing result.sample")
        }
        return url
      case "Pending", "Queued", "Processing", "Task not found":
        continue
      case "Request Moderated", "Content Moderated":
        throw CloudEngineError.moderated(provider: provider)
      case "Error", "Failed":
        let detail = (object["details"] as? [String: Any]).flatMap {
          try? JSONSerialization.data(withJSONObject: $0)
        }
        .map { String(decoding: $0, as: UTF8.self) }
        throw CloudEngineError.invalidResponse(provider: provider, detail: detail ?? "job failed")
      default:
        continue
      }
    }
    throw CloudEngineError.timedOut(provider: provider)
  }
}

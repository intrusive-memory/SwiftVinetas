// Diagnostic test (not part of regular CI runs).
//
// Goal: capture T5XXLEncoder's tokenization + embeddings for the canonical
// fixture prompt so they can be diffed tensor-to-tensor against the diffusers
// Python reference at /tmp/pixart-comparison/t5_reference.safetensors.
//
// Trigger:
//   xcodebuild test \
//     -scheme SwiftVinetas-Package \
//     -destination 'platform=macOS,arch=arm64' \
//     -derivedDataPath /tmp/SwiftVinetasBuild \
//     -only-testing:SwiftVinetasGPUTests/T5DiffuserComparisonDump
//
// Output:
//   /tmp/pixart-comparison/t5_swift.safetensors
//
// Loaded artifacts: tokens, mask (Float), embeddings (Float).
//
// This test is gated on the same TEST_RUNNER_VINETAS_TEST_MODELS_DIR plumbing
// as the rest of the GPU suite — Acervo.customBaseDirectory must point at the
// hard-linked /tmp/vinetas-test-models layout produced by `make link-test-models`.
import Foundation
import MLX
import SwiftAcervo
import Testing
@preconcurrency import Tokenizers
import Tuberia
import TuberiaCatalog

@testable import SwiftVinetas
import PixArtBackbone

@Suite("T5 Diffusers Comparison Dump", .serialized)
struct T5DiffuserComparisonDumpTests {

  /// Captures Swift T5 output for the fixture prompt.
  ///
  /// We replicate `DiffusionPipeline.loadModels`'s slice of T5 setup:
  ///   1. configureStorage — point Acervo at the test models dir
  ///   2. register PixArt components with Acervo
  ///   3. instantiate T5XXLEncoder from the recipe
  ///   4. loadTokenizer + WeightLoader.load + apply
  ///   5. encode() and dump
  @Test(
    "Capture Swift T5 tokens/mask/embeddings for diffusers comparison",
    .timeLimit(.minutes(5))
  )
  func dumpT5() async throws {
    // Sync Acervo's base directory to the test models dir (xctest can't read App Group).
    VinetasModelManager.configureStorage()

    // Trigger PixArt component registration with Acervo + TuberiaCatalog.
    // This must run before any Acervo.component(...) lookup, otherwise the
    // resolver throws componentNotRegistered.
    _ = PixArtComponents.registered

    let recipe = PixArtRecipe()

    // Instantiate the encoder and load the tokenizer.
    let encoder = try T5XXLEncoder(configuration: recipe.encoderConfig)

    // Mark the component as ready so WeightLoader.load can resolve files.
    // The pipeline normally does this via componentReadinessService inside
    // loadModels(); we replicate the static call here.
    try await Acervo.ensureComponentReady(recipe.encoderConfig.componentId)
    await encoder.loadTokenizer()

    // Load weights through the same WeightLoader the pipeline uses.
    let weights = try await WeightLoader.load(
      componentId: recipe.encoderConfig.componentId,
      keyMapping: encoder.keyMapping,
      tensorTransform: nil,
      quantization: recipe.quantizationFor(.encoder)
    )
    try encoder.apply(weights: weights)

    #expect(encoder.isLoaded, "T5XXLEncoder failed to load weights")

    // Per-layer activation capture: the modified T5TransformerEncoder calls
    // `debugTap` at every checkpoint (post-embedding, post-block-N for N=0..23,
    // post-final-norm). T5EncoderBlock additionally calls its own debugTap at
    // post_norm1/post_attn/post_residual1/post_norm2/post_ffn/post_residual2 —
    // we wire that up only for block 0 since post_block_0 is where divergence
    // already starts and we want sub-block resolution there.
    var taps: [(name: String, shape: [Int32], data: Data)] = []
    let appendTap: (String, MLXArray) -> Void = { name, tensor in
      let floats = tensor.asArray(Float.self)
      let shape = tensor.shape.map { Int32($0) }
      let bytes = floats.withUnsafeBufferPointer { Data(buffer: $0) }
      taps.append((name: "tap__\(name)", shape: shape, data: bytes))
    }
    encoder.transformer?.debugTap = appendTap
    encoder.transformer?.blocks[0].debugTap = { name, tensor in
      appendTap("block0_\(name)", tensor)
    }

    // Direct dump of the loaded RMSNorm gammas so we can compare against the
    // diffusers reference table without going through the activation.
    if let block0 = encoder.transformer?.blocks[0] {
      appendTap("block0_pre_attn_norm_gamma", block0.pre_attn_norm.weight)
      appendTap("block0_pre_ffn_norm_gamma", block0.pre_ffn_norm.weight)
    }
    if let finalNorm = encoder.transformer?.final_norm {
      appendTap("final_norm_gamma", finalNorm.weight)
    }

    // Encode the canonical fixture prompt at PixArt's training maxLength of 120.
    let prompt = "A red car parked on a cobblestone street"
    let output = try encoder.encode(.init(text: prompt, maxLength: 120))

    // Drop the taps so MLX doesn't keep alive the captured arrays past the test.
    encoder.transformer?.debugTap = nil
    encoder.transformer?.blocks[0].debugTap = nil

    // We need the token IDs for the bug-divergence-first comparison; encode()
    // doesn't return them. Replay the same AutoTokenizer load the encoder uses
    // so we get the same token IDs the transformer was fed.
    let tokenizerDir = try await AcervoManager.shared.withComponentAccess(
      recipe.encoderConfig.componentId
    ) { handle -> URL in
      handle.rootDirectoryURL
    }
    let tok = try await AutoTokenizer.from(directory: tokenizerDir)
    var tokenIds = tok.encode(text: prompt).map { Int32($0) }
    while tokenIds.count < 120 {
      tokenIds.append(0)
    }

    // Materialize MLX → Foundation buffers for safetensors writing.
    let embedFloats = output.embeddings.asArray(Float.self)
    let maskFloats = output.mask.asArray(Float.self)
    let embedShape = output.embeddings.shape.map { Int32($0) }
    let maskShape = output.mask.shape.map { Int32($0) }
    let tokenShape: [Int32] = [1, 120]

    // Write a "minimal safetensors" file: {header_len: u64 LE} + {header JSON} + {raw tensor bytes}.
    // Order must match the order tensors appear in the JSON header — we keep the
    // ordering explicit and verify the offsets at write time.
    var tensors: [(name: String, dtype: SafetensorsDtype, shape: [Int32], data: Data)] = [
      ("input_ids", .int32, tokenShape, tokenIds.withUnsafeBufferPointer { Data(buffer: $0) }),
      ("attention_mask", .float32, maskShape, maskFloats.withUnsafeBufferPointer { Data(buffer: $0) }),
      ("embeddings", .float32, embedShape, embedFloats.withUnsafeBufferPointer { Data(buffer: $0) }),
    ]
    for tap in taps {
      tensors.append((name: tap.name, dtype: .float32, shape: tap.shape, data: tap.data))
    }
    try writeSafetensors(
      url: URL(fileURLWithPath: "/tmp/pixart-comparison/t5_swift.safetensors"),
      tensors: tensors,
      metadata: [
        "prompt": prompt,
        "max_length": "120",
        "source": "T5XXLEncoder (Swift)",
      ]
    )
    print("[t5-dump] captured \(taps.count) intermediate taps")

    print(
      "[t5-dump] prompt='\(prompt)'",
      "tokens[0..<20]=\(Array(tokenIds.prefix(20)))",
      "mask.sum=\(maskFloats.reduce(0, +))"
    )
    print(
      "[t5-dump] embeddings shape=\(output.embeddings.shape)",
      "mean=\(meanOf(embedFloats))",
      "std=\(stdOf(embedFloats))",
      "min=\(embedFloats.min() ?? 0) max=\(embedFloats.max() ?? 0)"
    )
  }
}

// MARK: - Minimal safetensors writer (no extra dependency)

private enum SafetensorsDtype: String {
  case int32 = "I32"
  case float32 = "F32"
}

private func writeSafetensors(
  url: URL,
  tensors: [(name: String, dtype: SafetensorsDtype, shape: [Int32], data: Data)],
  metadata: [String: String]
) throws {
  // Compute byte offsets and JSON header.
  var offsets: [(start: Int, end: Int)] = []
  var cursor = 0
  for (_, _, _, data) in tensors {
    offsets.append((start: cursor, end: cursor + data.count))
    cursor += data.count
  }

  var headerObj: [String: Any] = ["__metadata__": metadata]
  for (i, t) in tensors.enumerated() {
    headerObj[t.name] = [
      "dtype": t.dtype.rawValue,
      "shape": t.shape.map { Int($0) },
      "data_offsets": [offsets[i].start, offsets[i].end],
    ] as [String: Any]
  }
  let headerJSON = try JSONSerialization.data(
    withJSONObject: headerObj,
    options: [.sortedKeys]
  )
  // safetensors requires the header to be 8-byte aligned in some readers; not strictly
  // needed for the Python `safetensors` package, which just reads the declared length.
  var headerLen = UInt64(headerJSON.count)
  var fileData = Data(capacity: 8 + headerJSON.count + cursor)
  fileData.append(Data(bytes: &headerLen, count: 8))
  fileData.append(headerJSON)
  for (_, _, _, data) in tensors {
    fileData.append(data)
  }
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try fileData.write(to: url)
}

// MARK: - Tiny stats helpers (avoid pulling Accelerate just for one print)

private func meanOf(_ xs: [Float]) -> Float {
  guard !xs.isEmpty else { return 0 }
  var sum: Double = 0
  for x in xs { sum += Double(x) }
  return Float(sum / Double(xs.count))
}

private func stdOf(_ xs: [Float]) -> Float {
  guard xs.count > 1 else { return 0 }
  let m = Double(meanOf(xs))
  var ss: Double = 0
  for x in xs { let d = Double(x) - m; ss += d * d }
  return Float((ss / Double(xs.count - 1)).squareRoot())
}

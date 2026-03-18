import MLX
import MLXNN

/// Vision Transformer (ViT) model for image classification and feature extraction.
///
/// Implements the standard ViT architecture:
/// 1. Patch embedding via Conv2d (NHWC input)
/// 2. Prepend learnable CLS token
/// 3. Add learnable positional embeddings
/// 4. Stack of EncoderBlock layers
/// 5. Final LayerNorm
/// 6. Optional classification head (Linear or Identity when numClasses=0)
///
/// When `numClasses` is 0, the classification head is omitted and the model
/// returns the raw CLS token embedding, suitable for feature extraction (e.g. DINOv2).
public class VisionTransformer: Module {

  @ModuleInfo(key: "patch_embed") var patchEmbedding: Conv2d
  @ParameterInfo(key: "cls_token") var clsToken: MLXArray
  @ParameterInfo(key: "pos_embed") var positionalEmbedding: MLXArray
  let blocks: [EncoderBlock]
  @ModuleInfo(key: "norm") var finalNorm: LayerNorm
  @ModuleInfo(key: "head") var classificationHead: Linear?

  /// Number of classes for the classification head. When 0, no head is applied.
  public let numClasses: Int

  /// Model embedding dimension.
  public let dim: Int

  /// Initialize a Vision Transformer.
  ///
  /// - Parameters:
  ///   - imageSize: Input image size (assumes square). Default 224.
  ///   - patchSize: Size of each image patch. Default 16.
  ///   - numClasses: Number of output classes. 0 means no classification head (feature extraction mode).
  ///   - dim: Embedding dimension. Default 768 for ViT-B.
  ///   - depth: Number of encoder blocks. Default 12 for ViT-B.
  ///   - numHeads: Number of attention heads. Default 12 for ViT-B.
  public init(
    imageSize: Int = 224,
    patchSize: Int = 16,
    numClasses: Int = 1000,
    dim: Int = 768,
    depth: Int = 12,
    numHeads: Int = 12
  ) {
    let numPatches = (imageSize / patchSize) * (imageSize / patchSize)
    let mlpDim = dim * 4

    self.numClasses = numClasses
    self.dim = dim

    // Patch embedding: Conv2d(3 -> dim, kernel=patchSize, stride=patchSize)
    // Input is NHWC format (channels last, as MLX expects)
    self._patchEmbedding.wrappedValue = Conv2d(
      inputChannels: 3,
      outputChannels: dim,
      kernelSize: IntOrPair(patchSize),
      stride: IntOrPair(patchSize),
      bias: true
    )

    // Learnable CLS token: [1, 1, dim]
    self._clsToken.wrappedValue = MLXRandom.normal([1, 1, dim]) * 0.02

    // Learnable positional embedding: [1, numPatches + 1, dim]
    // +1 for the CLS token
    self._positionalEmbedding.wrappedValue = MLXRandom.normal([1, numPatches + 1, dim]) * 0.02

    // Encoder blocks
    self.blocks = (0..<depth).map { _ in
      EncoderBlock(dim: dim, numHeads: numHeads, mlpDim: mlpDim)
    }

    // Final layer norm
    self._finalNorm.wrappedValue = LayerNorm(dimensions: dim)

    // Classification head: Linear if numClasses > 0, otherwise nil
    if numClasses > 0 {
      self._classificationHead.wrappedValue = Linear(dim, numClasses)
    } else {
      self._classificationHead.wrappedValue = nil
    }
  }

  /// Forward pass through the Vision Transformer.
  ///
  /// - Parameter x: Input image tensor of shape `[B, H, W, 3]` (NHWC format).
  /// - Returns: If `numClasses > 0`, logits of shape `[B, numClasses]`.
  ///            If `numClasses == 0`, CLS token embedding of shape `[B, dim]`.
  public func callAsFunction(_ x: MLXArray) -> MLXArray {
    let batch = x.dim(0)

    // Patch embedding: [B, H, W, 3] -> [B, H/P, W/P, dim]
    var patches = patchEmbedding(x)

    // Reshape to sequence: [B, H/P, W/P, dim] -> [B, numPatches, dim]
    let h = patches.dim(1)
    let w = patches.dim(2)
    patches = patches.reshaped([batch, h * w, dim])

    // Expand CLS token to match batch size: [1, 1, dim] -> [B, 1, dim]
    let expandedCls = broadcast(clsToken, to: [batch, 1, dim])

    // Prepend CLS token: [B, numPatches+1, dim]
    var tokens = concatenated([expandedCls, patches], axis: 1)

    // Add positional embedding (broadcasts over batch)
    tokens = tokens + positionalEmbedding

    // Apply encoder blocks
    for block in blocks {
      tokens = block(tokens)
    }

    // Final layer norm
    tokens = finalNorm(tokens)

    // Extract CLS token: [B, dim]
    let clsOutput = tokens[0..., 0, 0...]

    // Apply classification head if present, otherwise return raw embedding
    if let head = classificationHead {
      return head(clsOutput)
    }
    return clsOutput
  }
}

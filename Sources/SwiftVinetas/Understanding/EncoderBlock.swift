import MLX
import MLXNN

/// Pre-norm transformer encoder block for Vision Transformer.
///
/// Architecture: LayerNorm -> MultiHeadAttention -> residual -> LayerNorm -> MLP -> residual
///
/// The MLP expands from `dim` to `mlpDim` (typically 4x) with GELU activation,
/// then projects back down to `dim`.
public class EncoderBlock: Module, UnaryLayer {

  @ModuleInfo(key: "ln1") var norm1: LayerNorm
  @ModuleInfo(key: "ln2") var norm2: LayerNorm
  let attention: MultiHeadAttention
  @ModuleInfo(key: "linear1") var mlpLinear1: Linear
  @ModuleInfo(key: "linear2") var mlpLinear2: Linear
  let gelu: GELU

  /// Initialize an encoder block.
  ///
  /// - Parameters:
  ///   - dim: Model dimension (default 768 for ViT-B).
  ///   - numHeads: Number of attention heads (default 12 for ViT-B).
  ///   - mlpDim: Hidden dimension of the MLP (default 3072 = 4 * 768).
  public init(dim: Int = 768, numHeads: Int = 12, mlpDim: Int = 3072) {
    self._norm1.wrappedValue = LayerNorm(dimensions: dim)
    self._norm2.wrappedValue = LayerNorm(dimensions: dim)
    self.attention = MultiHeadAttention(dimensions: dim, numHeads: numHeads)
    self._mlpLinear1.wrappedValue = Linear(dim, mlpDim)
    self._mlpLinear2.wrappedValue = Linear(mlpDim, dim)
    self.gelu = GELU()
  }

  /// Forward pass through the encoder block.
  ///
  /// - Parameter x: Input tensor of shape `[B, N, D]`.
  /// - Returns: Output tensor of shape `[B, N, D]`.
  public func callAsFunction(_ x: MLXArray) -> MLXArray {
    // Pre-norm attention with residual
    var residual = x
    var out = norm1(x)
    out = attention(out, keys: out, values: out)
    out = out + residual

    // Pre-norm MLP with residual
    residual = out
    var mlpOut = norm2(out)
    mlpOut = mlpLinear1(mlpOut)
    mlpOut = gelu(mlpOut)
    mlpOut = mlpLinear2(mlpOut)
    out = mlpOut + residual

    return out
  }
}

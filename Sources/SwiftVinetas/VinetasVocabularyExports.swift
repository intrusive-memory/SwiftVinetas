/// Compatibility shim for `import SwiftVinetas` consumers.
///
/// `AspectRatio`, `ResolutionClamp` and `StyleConfig` live in the engine-free
/// `VinetasVocabulary` module. Re-exporting it here keeps every existing
/// `import SwiftVinetas` compiling without an extra import.
@_exported import VinetasVocabulary

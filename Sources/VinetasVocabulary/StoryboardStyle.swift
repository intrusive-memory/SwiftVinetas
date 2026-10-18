import Foundation

/// Preset visual styles for storyboard image generation.
///
/// Each case maps a human-readable display name to a prompt string
/// that guides the diffusion model toward a specific aesthetic, and
/// is associated with a representative film genre so the picker can
/// offer a brief caption to anchor the style in a familiar cinematic
/// reference.
///
/// The `rawValue`s, case order, ``promptText`` and ``negativePromptText``
/// are a frozen vocabulary: hosts persist them, and `FrozenVocabularyTests`
/// fails if any of them changes.
public enum StoryboardStyle: String, CaseIterable, Identifiable, Sendable {
  /// Mid-Century Modern Illustration.
  case midCenturyModern

  /// Pencil Sketch Comic Strip.
  case pencilSketchComic

  /// Dark Academic Learned Scholar.
  case darkAcademic

  /// 1940's Tinted Dust Bowl Photo.
  case dustBowlPhoto

  /// Noir Graphic Novel.
  case noirGraphicNovel

  /// Melodrama Watercolor.
  case watercolorStoryboard

  /// Japanese Scroll Illustration.
  case japaneseScroll

  /// Retro Sci-Fi Pulp Art.
  case retroSciFiPulp

  /// Pop Art Comic Book.
  case popArtComic

  /// Minimalist Line Art.
  case minimalistLineArt

  /// Photo Realistic.
  case photoRealistic

  /// 1970's Kodachrome.
  case kodachrome1970s

  /// German Expressionist.
  case germanExpressionist

  /// Spaghetti Western.
  case spaghettiWestern

  /// Anime Fantasy Watercolor.
  case watercolorAsianAnimation

  /// Symmetric Quirky Indie.
  case wesAndersonSymmetric

  /// Wuxia Ink Brush.
  case wuxiaInkBrush

  /// Giallo Horror.
  case gialloHorror

  /// Attic Red-Figure Illustration.
  case atticRedFigure

  /// "Other": the user supplies their own prompt and negative prompt.
  case custom

  /// The stable identifier, equal to ``rawValue``.
  public var id: String { rawValue }

  /// Display name shown in the picker.
  public var displayName: String { entry.displayName }

  /// Genre most typical of this visual style.
  ///
  /// Returns `nil` for `.custom`, where the user supplies their own description.
  public var genre: String? { entry.genre }

  /// Caption shown under the picker — the genre most typical of this visual
  /// style, e.g. "Film noir". Returns `nil` for `.custom`.
  public var caption: String? { genre }

  /// The prompt text sent to the generation model.
  ///
  /// For `.custom` this returns an empty string — the actual prompt text
  /// is provided by the user via a free-form text field.
  public var promptText: String { entry.promptText }

  /// Generic quality negatives shared by every preset, prepended to each
  /// style's tailored additions.
  static let baseNegative =
    "blurry, low quality, low resolution, distorted, deformed, disfigured, bad anatomy, extra limbs, extra fingers, text, watermark, signature, jpeg artifacts"

  /// Aesthetic-specific negatives that counter the failure modes most likely
  /// to break each style (e.g. color leaking into a black-and-white style,
  /// photorealism intruding on a flat illustration). Returns `""` for `.custom`.
  var styleSpecificNegative: String { entry.styleSpecificNegative }

  /// The default negative prompt applied when this style is selected.
  ///
  /// Picking a preset always replaces the negative prompt with this value —
  /// the shared quality `baseNegative` plus the style's tailored additions.
  /// For `.custom` this returns an empty string — the negative prompt is
  /// left entirely to the user's free-form text field.
  public var negativePromptText: String {
    let specific = styleSpecificNegative
    if specific.isEmpty { return "" }
    return "\(Self.baseNegative), \(specific)"
  }

  /// Sentinel value used as the Picker tag for the "Other" option.
  public static let customTag = "__custom__"

  /// Selectable preset styles (everything except `.custom`), sorted
  /// alphabetically by display name for stable, scannable picker ordering.
  public static var sortedPresets: [StoryboardStyle] {
    allCases
      .filter { $0 != .custom }
      .sorted {
        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
  }

  /// Find the style matching a prompt text, or nil if no match.
  public static func from(promptText: String) -> StoryboardStyle? {
    allCases.first { $0 != .custom && $0.promptText == promptText }
  }

  // MARK: - Style table

  /// The text a style carries. One row per case, in declaration order.
  private struct Entry: Sendable {
    let displayName: String
    let genre: String?
    let promptText: String
    let styleSpecificNegative: String
  }

  /// This style's row in ``entries``.
  private var entry: Entry {
    guard let entry = Self.entries[self] else {
      preconditionFailure("StoryboardStyle.\(rawValue) has no entry in the style table")
    }
    return entry
  }

  /// Every style's text, keyed by case. A dictionary rather than `switch`
  /// statements so the declaration list above is the only place a style is
  /// enumerated; `FrozenVocabularyTests` proves every case has a row.
  private static let entries: [StoryboardStyle: Entry] = [
    .midCenturyModern: Entry(
      displayName: "Mid-Century Modern Illustration",
      genre: "Advertising / corporate drama",
      promptText:
        "mid-century modern illustration, flat color planes, bold outlines, retro atomic age palette, stylized geometry",
      styleSpecificNegative:
        "photorealistic, 3d render, photographic, soft gradient shading, cluttered detail, busy background"
    ),
    .pencilSketchComic: Entry(
      displayName: "Pencil Sketch Comic Strip",
      genre: "Indie / coming-of-age",
      promptText:
        "pencil sketch comic strip, hand-drawn crosshatching, expressive linework, newspaper panel style",
      styleSpecificNegative:
        "color, photorealistic, 3d render, digital painting, smooth gradients, glossy"
    ),
    .darkAcademic: Entry(
      displayName: "Dark Academic Learned Scholar",
      genre: "Period gothic",
      promptText:
        "dark academic aesthetic, moody oil painting, leather-bound library, warm candlelight, rich earth tones",
      styleSpecificNegative:
        "bright flat lighting, neon, modern technology, cartoon, flat colors, oversaturated"
    ),
    .dustBowlPhoto: Entry(
      displayName: "1940's Tinted Dust Bowl Photo",
      genre: "American historical",
      promptText:
        "1940s tinted photograph, dust bowl era, sepia and muted color tones, grain texture, documentary realism",
      styleSpecificNegative:
        "vivid saturated colors, neon, modern clothing, digital art, cgi, clean and pristine"
    ),
    .noirGraphicNovel: Entry(
      displayName: "Noir Graphic Novel",
      genre: "Film noir",
      promptText:
        "noir graphic novel, high contrast black and white, dramatic shadows, rain-slicked streets, ink splatter",
      styleSpecificNegative:
        "color, bright lighting, soft shadows, pastel, cheerful, low contrast"
    ),
    .watercolorStoryboard: Entry(
      displayName: "Melodrama Watercolor",
      genre: "Domestic melodrama",
      promptText:
        "watercolor storyboard, loose wet-on-wet washes, soft bleeding edges, muted pastel palette",
      styleSpecificNegative:
        "hard edges, photorealistic, 3d render, harsh contrast, sharp digital lines, neon"
    ),
    .japaneseScroll: Entry(
      displayName: "Japanese Scroll Illustration",
      genre: "Jidaigeki / period samurai",
      promptText:
        "traditional Japanese hand scroll (emakimono) illustration, fine ink linework with delicate watercolor washes, gold-leaf accents, flat perspective with stylized clouds and mist, jidaigeki period drama composition",
      styleSpecificNegative:
        "western style, photorealistic, 3d render, modern clothing, harsh cast shadows, vivid neon"
    ),
    .retroSciFiPulp: Entry(
      displayName: "Retro Sci-Fi Pulp Art",
      genre: "1950s sci-fi",
      promptText:
        "retro sci-fi pulp art, 1950s space age, vivid saturated colors, ray guns and rocket ships, dramatic poses",
      styleSpecificNegative:
        "muted colors, photorealistic, modern technology, minimalist, monochrome, grayscale"
    ),
    .popArtComic: Entry(
      displayName: "Pop Art Comic Book",
      genre: "Comic-book adaptation",
      promptText:
        "pop art comic book, Ben-Day dots, bold primary colors, thick outlines, speech bubble aesthetic",
      styleSpecificNegative:
        "photorealistic, muted colors, soft gradients, realistic shading, grayscale, painterly"
    ),
    .minimalistLineArt: Entry(
      displayName: "Minimalist Line Art",
      genre: "Arthouse animation",
      promptText:
        "minimalist line art, single continuous stroke, clean vector aesthetic, generous white space, elegant simplicity",
      styleSpecificNegative:
        "detailed shading, heavy texture, photorealistic, busy background, color fill, clutter"
    ),
    .photoRealistic: Entry(
      displayName: "Photo Realistic",
      genre: "Contemporary realist",
      promptText:
        "photorealistic, ultra-detailed photograph, natural lighting, sharp focus, high dynamic range, lifelike textures",
      styleSpecificNegative:
        "illustration, painting, drawing, cartoon, anime, cgi, 3d render, sketch, flat colors"
    ),
    .kodachrome1970s: Entry(
      displayName: "1970's Kodachrome",
      genre: "New Hollywood (1970s)",
      promptText:
        "1970s Kodachrome film photograph, warm saturated reds and yellows, rich golden tones, slight grain, vintage analog warmth, nostalgic color rendition",
      styleSpecificNegative:
        "cool blue tones, digital, modern, neon, illustration, cartoon, washed out"
    ),
    .germanExpressionist: Entry(
      displayName: "German Expressionist",
      genre: "Silent horror",
      promptText:
        "German Expressionist silent-film aesthetic, sharply angular shadows, distorted architecture, painted theatrical sets, high-contrast black and white, Nosferatu and Caligari composition",
      styleSpecificNegative:
        "color, naturalistic lighting, soft shadows, photorealistic, cheerful, modern setting"
    ),
    .spaghettiWestern: Entry(
      displayName: "Spaghetti Western",
      genre: "Western",
      promptText:
        "spaghetti western cinematography, wide anamorphic framing alternated with extreme close-ups, sun-baked desert palette, dust and heat haze, weathered faces, golden hour",
      styleSpecificNegative:
        "cool blue tones, urban, modern, neon, overcast, cartoon, clean"
    ),
    .watercolorAsianAnimation: Entry(
      displayName: "Anime Fantasy Watercolor",
      genre: "Anime fantasy",
      promptText:
        "hand-painted anime watercolor background, soft cumulus clouds, lush green landscapes, gentle natural light, anime fantasy composition, painterly atmospheric perspective",
      styleSpecificNegative:
        "photorealistic, 3d render, harsh shadows, western cartoon, gritty, dark and gloomy"
    ),
    .wesAndersonSymmetric: Entry(
      displayName: "Symmetric Quirky Indie",
      genre: "Quirky indie",
      promptText:
        "symmetric composition, head-on framing with centered subject, pastel color palette, meticulous production design, flat staging, dollhouse precision",
      styleSpecificNegative:
        "asymmetric, cluttered, gritty, chaotic composition, dutch angle, dark and grimy"
    ),
    .wuxiaInkBrush: Entry(
      displayName: "Wuxia Ink Brush",
      genre: "Wuxia martial arts",
      promptText:
        "wuxia ink brush painting fused with cinematic color, sweeping silk fabrics, mountain mist, bold color-coded palettes, calligraphic motion lines, martial arts choreography",
      styleSpecificNegative:
        "western style, photorealistic, 3d render, modern clothing, flat lighting, neon"
    ),
    .gialloHorror: Entry(
      displayName: "Giallo Horror",
      genre: "Giallo horror",
      promptText:
        "Italian giallo horror cinematography, saturated red and electric blue lighting, baroque interiors, lurid saturated palette, theatrical chiaroscuro, glossy surfaces",
      styleSpecificNegative:
        "muted colors, flat lighting, minimalist, daytime, naturalistic, cartoon"
    ),
    .atticRedFigure: Entry(
      displayName: "Attic Red-Figure Illustration",
      genre: "Greek myth / antiquity",
      promptText:
        "ancient Greek Attic red-figure vase painting, flat reddish-orange terracotta silhouettes reserved against a solid deep-black background, two colors only, no shading or gradients, no perspective or cast shadows, crisp two-dimensional outlines, interior anatomy and texture drawn only with fine black relief lines, figures posed in clean profile with idealized archaic linework, hair and foliage as scrolled and stippled black masses, meander Greek-key palmette and laurel ornamental borders",
      styleSpecificNegative:
        "photorealistic, 3d render, shading, gradients, cel shading, ambient occlusion, drop shadow, cast shadow, highlights, depth of field, perspective, foreshortening, full color, blue, green, purple, white background, gray background, watercolor, oil painting, anime, cartoon, comic, crosshatching, halftone, black-figure technique, filled black figures, neon, glow, 3d bevel, embossing"
    ),
    .custom: Entry(
      displayName: "Other",
      genre: nil,
      promptText:
        "",
      styleSpecificNegative:
        ""
    ),
  ]
}

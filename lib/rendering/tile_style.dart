import 'package:flutter/painting.dart';

/// Visual parameters of a tile set. Geometry lives in the level; this is only
/// how a tile looks. Fractions are relative to the rendered face width
/// unless stated otherwise.
class TileStyle {
  const TileStyle({
    this.id = 'classic-ivory',
    this.faceAspect = 0.76,
    this.depthXFraction = 0.075,
    this.depthYFraction = 0.12,
    this.cornerRadiusFraction = 0.12,
    this.bevelFraction = 0.065,
    this.symbolInsetFraction = 0.055,
    this.symbolBrightness = 0.98,
    this.symbolSaturation = 1.3,
    this.symbolContrast = 1.08,
    this.backSplit = 0.42,
    this.faceHighlightColor = const Color(0xFFFFFBF0),
    this.faceColor = const Color(0xFFF4ECD8),
    this.faceShadeColor = const Color(0xFFE4D5B3),
    this.catchLightColor = const Color(0xFFFFF6DD),
    this.bevelShadeColor = const Color(0x66A07C3C),
    this.edgeColor = const Color(0xC2B48C42),
    this.sideColor = const Color(0xFFEDE1C3),
    this.sideShadeColor = const Color(0xFFC9B386),
    this.backColor = const Color(0xFF55702A),
    this.backShadeColor = const Color(0xFF1F3312),
    this.shadowColor = const Color(0x9E01140A),
    this.contactShadowColor = const Color(0x8C000A04),
    this.shadowOffsetFraction = 0.07,
    this.shadowBlurFraction = 0.09,
    this.raisedShadowColor = const Color(0x6B0A1606),
    this.raisedShadowOffsetFraction = 0.05,
    this.raisedShadowBlurFraction = 0.07,
    this.lowerLayerShade = 0.03,
    this.blockedDim = 0.11,
    this.glowColor = const Color(0xFFFFC94D),
    this.invalidColor = const Color(0xFFE5484D),
    this.invalidDuration = const Duration(milliseconds: 380),
  });

  static const TileStyle classicIvory = TileStyle();

  final String id;

  /// Face width / face height.
  final double faceAspect;

  /// Visible thickness right of the face, as a fraction of face width.
  final double depthXFraction;

  /// Visible thickness below the face, as a fraction of face height.
  final double depthYFraction;
  final double cornerRadiusFraction;
  final double bevelFraction;

  /// Padding between the face edge and the symbol artwork.
  final double symbolInsetFraction;

  /// Symbol brightness (1 = as authored). Applied at paint time together
  /// with [symbolSaturation] and [symbolContrast]; art files stay untouched.
  final double symbolBrightness;

  /// Symbol saturation (1 = as authored). Above 1 gives vivid colours.
  final double symbolSaturation;

  /// Symbol contrast around mid-grey (1 = as authored).
  final double symbolContrast;

  /// Share of the side wall drawn in the light side colour; the outer rest
  /// is the coloured back rim.
  final double backSplit;

  final Color faceHighlightColor;
  final Color faceColor;
  final Color faceShadeColor;

  /// Warm gold-white light on the top/left bevel.
  final Color catchLightColor;

  /// Honey shade on the bottom/right bevel.
  final Color bevelShadeColor;

  /// Thin gold line around the face and at the wall/base seam.
  final Color edgeColor;
  final Color sideColor;
  final Color sideShadeColor;
  final Color backColor;
  final Color backShadeColor;
  final Color shadowColor;

  /// Tight shadow where the base meets the felt.
  final Color contactShadowColor;
  final double shadowOffsetFraction;
  final double shadowBlurFraction;

  /// Extra shadow under upper-layer tiles, so raised tiles read as raised.
  final Color raisedShadowColor;
  final double raisedShadowOffsetFraction;
  final double raisedShadowBlurFraction;

  /// Darkening per layer below the top layer, for depth.
  final double lowerLayerShade;

  /// Darkening of tiles that cannot be picked (when the setting is on).
  final double blockedDim;

  /// Gold glow around a tile landing in the tray.
  final Color glowColor;
  final Color invalidColor;

  /// How long a blocked tile shakes.
  final Duration invalidDuration;

  /// How far body and shadow reach past the face, for fitting the board.
  double get edgeFraction =>
      (depthXFraction > depthYFraction / faceAspect ? depthXFraction : depthYFraction / faceAspect) +
      shadowOffsetFraction +
      shadowBlurFraction * 0.8;

  /// Colour filter for symbol art, or null when the art is drawn as authored.
  ColorFilter? get symbolColorFilter {
    if (symbolBrightness == 1 && symbolSaturation == 1 && symbolContrast == 1) return null;
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final s = symbolSaturation, k = symbolBrightness * symbolContrast;
    final sr = (1 - s) * r, sg = (1 - s) * g, sb = (1 - s) * b;
    // Contrast pivots on mid-grey; the offset column is in 0-255 units.
    final offset = 127.5 * (1 - symbolContrast) * symbolBrightness;
    return ColorFilter.matrix([
      (sr + s) * k, sg * k, sb * k, 0, offset, //
      sr * k, (sg + s) * k, sb * k, 0, offset,
      sr * k, sg * k, (sb + s) * k, 0, offset,
      0, 0, 0, 1, 0,
    ]);
  }

  static TileStyle forTileSet(String tileSetId) => classicIvory;

  /// Face colours a level can give single pairs (`LevelDefinition.faceColors`,
  /// the names of `kFaceColorNames`); every other tile has the ivory
  /// [faceColor]. All light, so dark and colourful symbols stay readable on
  /// a 31 px face; never green, so they stand out on the felt.
  static const Map<String, Color> namedFaceColors = {
    'gold': Color(0xFFECC98D),
    'sky': Color(0xFFBFDEF3),
    'blush': Color(0xFFF7CDD6),
    'lavender': Color(0xFFD9CDEF),
    'peach': Color(0xFFFACEB5),
  };

  /// The face colour named [name]; null (ivory) for null or a name this
  /// build does not know.
  static Color? faceColorNamed(String? name) => namedFaceColors[name];

  /// The shades of a tile whose face is [face]: this style's own (ivory)
  /// set for null or [faceColor], else a set derived from [face].
  TileFaceShades faceShades([Color? face]) => face == null || face == faceColor
      ? TileFaceShades(
          highlight: faceHighlightColor,
          face: faceColor,
          shade: faceShadeColor,
          catchLight: catchLightColor,
          bevelShade: bevelShadeColor,
          edge: edgeColor,
          side: sideColor,
          sideShade: sideShadeColor,
          dome: const Color(0x147A5A20),
          lift: const Color(0x40382A10),
        )
      : TileFaceShades.derive(face);
}

/// The colours a tile body takes from its face colour: the face gradient,
/// bevel light and shade, edge line, the wall under the face, and two faint
/// shadings (the domed centre, the hairline lifting the face off the wall).
/// The olive-green base is the same for every face.
class TileFaceShades {
  const TileFaceShades({
    required this.highlight,
    required this.face,
    required this.shade,
    required this.catchLight,
    required this.bevelShade,
    required this.edge,
    required this.side,
    required this.sideShade,
    required this.dome,
    required this.lift,
  });

  /// Shades of [face] with the ivory set's steps of lightness, saturation
  /// and hue (see [TileStyle.classicIvory]): lighter highlights, a deeper
  /// shade, an edge and bevel shade of the same hue.
  factory TileFaceShades.derive(Color face) {
    final hsl = HSLColor.fromColor(face);
    final l = hsl.lightness;
    Color tone({required double lightness, double hue = 0, double saturation = 1, double alpha = 1}) =>
        HSLColor.fromAHSL(
          alpha,
          (hsl.hue + hue) % 360,
          (hsl.saturation * saturation).clamp(0.0, 1.0),
          lightness.clamp(0.0, 1.0),
        ).toColor();
    return TileFaceShades(
      highlight: tone(lightness: l + 0.70 * (1 - l), saturation: 1.25),
      face: face.withValues(alpha: 1),
      shade: tone(lightness: l - 0.105, hue: -1, saturation: 0.9),
      catchLight: tone(lightness: l + 0.32 * (1 - l), saturation: 1.25),
      bevelShade: tone(lightness: l - 0.47, hue: -3, saturation: 0.8, alpha: 0.4),
      edge: tone(lightness: l - 0.42, hue: -3, saturation: 0.82, alpha: 0.76),
      side: tone(lightness: l - 0.055, saturation: 0.96),
      sideShade: tone(lightness: l - 0.245, hue: -2, saturation: 0.68),
      dome: tone(lightness: l - 0.60, hue: -3, alpha: 0.08),
      lift: tone(lightness: 0.141, hue: -3, alpha: 0.25),
    );
  }

  final Color highlight;
  final Color face;
  final Color shade;

  /// Light on the top/left bevel.
  final Color catchLight;

  /// Shade on the bottom/right bevel.
  final Color bevelShade;

  /// Thin line around the face and at the wall/base seam.
  final Color edge;

  /// The wall under the face, light and shaded.
  final Color side;
  final Color sideShade;

  /// Faint shade at the rim of the domed centre.
  final Color dome;

  /// Hairline shadow lifting the face off the wall.
  final Color lift;
}

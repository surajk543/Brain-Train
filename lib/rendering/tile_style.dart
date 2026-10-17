import 'package:flutter/painting.dart';

/// Visual parameters of a tile set. Geometry lives in the level; this is only
/// how a tile looks. Fractions are relative to the rendered face width
/// unless stated otherwise.
///
/// The face colour is one input, [faceColor] (warm ivory by default; see
/// [withFace]): the face's highlight and shade, its bevel and the light wall
/// under it all derive from it. The green base under the wall, the outline
/// and the shadows do not change with it.
class TileStyle {
  const TileStyle({
    this.id = 'classic-ivory',
    this.faceAspect = 0.76,
    this.depthXFraction = 0.075,
    this.depthYFraction = 0.12,
    this.edgeFraction = 0.2999,
    this.cornerRadiusFraction = 0.12,
    this.bevelFraction = 0.075,
    this.symbolInsetFraction = 0.055,
    this.symbolBrightness = 0.98,
    this.symbolSaturation = 1.3,
    this.symbolContrast = 1.08,
    this.backSplit = 0.5,
    this.faceColor = ivoryFace,
    this.backColor = const Color(0xFF5C9C3B),
    this.backShadeColor = const Color(0xFF2B6127),
    this.backLightColor = const Color(0xFFA6CF6E),
    this.outlineColor = const Color(0xE6082311),
    this.shadowColor = const Color(0xB3000804),
    this.contactShadowColor = const Color(0xB3000804),
    this.shadowOffsetFraction = 0.06,
    this.shadowOffsetXFraction = 0.085,
    this.shadowBlurFraction = 0.036,
    this.raisedShadowColor = const Color(0xB8000603),
    this.raisedShadowOffsetFraction = 0.11,
    this.raisedShadowBlurFraction = 0.06,
    this.lowerLayerShade = 0.03,
    this.blockedDim = 0.11,
    this.glowColor = const Color(0xFFFFC94D),
    this.invalidColor = const Color(0xFFE5484D),
    this.invalidDuration = const Duration(milliseconds: 380),
  });

  static const TileStyle classicIvory = TileStyle();

  /// The default face: warm ivory.
  static const Color ivoryFace = Color(0xFFFAF4E6);

  /// This style with a face of [face] (a coloured tile: gold, sky blue, ...);
  /// highlight, bevel and wall shades follow it.
  TileStyle withFace(Color face) => TileStyle(
    id: face == faceColor ? id : '$id@${face.toARGB32().toRadixString(16)}',
    faceAspect: faceAspect,
    depthXFraction: depthXFraction,
    depthYFraction: depthYFraction,
    edgeFraction: edgeFraction,
    cornerRadiusFraction: cornerRadiusFraction,
    bevelFraction: bevelFraction,
    symbolInsetFraction: symbolInsetFraction,
    symbolBrightness: symbolBrightness,
    symbolSaturation: symbolSaturation,
    symbolContrast: symbolContrast,
    backSplit: backSplit,
    faceColor: face,
    backColor: backColor,
    backShadeColor: backShadeColor,
    backLightColor: backLightColor,
    outlineColor: outlineColor,
    shadowColor: shadowColor,
    contactShadowColor: contactShadowColor,
    shadowOffsetFraction: shadowOffsetFraction,
    shadowOffsetXFraction: shadowOffsetXFraction,
    shadowBlurFraction: shadowBlurFraction,
    raisedShadowColor: raisedShadowColor,
    raisedShadowOffsetFraction: raisedShadowOffsetFraction,
    raisedShadowBlurFraction: raisedShadowBlurFraction,
    lowerLayerShade: lowerLayerShade,
    blockedDim: blockedDim,
    glowColor: glowColor,
    invalidColor: invalidColor,
    invalidDuration: invalidDuration,
  );

  final String id;

  /// Face width / face height.
  final double faceAspect;

  /// Visible thickness right of the face, as a fraction of face width.
  final double depthXFraction;

  /// Visible thickness below the face, as a fraction of face height.
  final double depthYFraction;

  /// How far body and shadows reach past the face (right and bottom), as a
  /// fraction of face width, for fitting the board. Fixed on purpose: board
  /// sizes, the 31-px face rule and the campaign generator
  /// (`kFitEdgeFraction`) depend on it, so retuning the look never moves a
  /// tile. Walls and the dense part of the shadows must stay inside it.
  final double edgeFraction;
  final double cornerRadiusFraction;

  /// Width of the face's soft rounded rim (light top-left, shade
  /// bottom-right), inside the face.
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

  /// Share of the side wall drawn in the face's (darker) colour, just under
  /// the face; the outer rest is the green base.
  final double backSplit;

  /// The face colour; every other face and wall shade derives from it.
  final Color faceColor;

  /// The green base: its top (by the light wall), its bottom (on the felt)
  /// and the light line along its top edge.
  final Color backColor;
  final Color backShadeColor;
  final Color backLightColor;

  /// Fine dark line around the whole tile (face top/left, base bottom/right),
  /// so neighbours and layers separate crisply.
  final Color outlineColor;

  /// Soft cast shadow, offset down-right.
  final Color shadowColor;

  /// Tight shadow where the base meets what is under it.
  final Color contactShadowColor;

  /// Offset of the soft shadow past the base: down, and right (further: the
  /// fit margin is widest on the right).
  final double shadowOffsetFraction;
  final double shadowOffsetXFraction;

  /// Blur sigma of the soft shadow.
  final double shadowBlurFraction;

  /// Extra, longer shadow under upper-layer tiles onto the tiles below, so
  /// raised tiles read as raised.
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

  /// Top-left light on the face.
  Color get faceHighlightColor => Color.lerp(faceColor, const Color(0xFFFFFFFF), 0.65)!;

  /// Bottom-right of the face.
  Color get faceShadeColor => _shade(faceColor, lightness: -0.055, saturation: 0.02);

  /// The face's rim where it rounds down into the wall (bottom/right).
  Color get bevelShadeColor => _shade(faceColor, lightness: -0.26, saturation: -0.12);

  /// The light wall just under the face, and where it meets the green base.
  Color get sideColor => _shade(faceColor, lightness: -0.1, saturation: -0.12);
  Color get sideShadeColor => _shade(faceColor, lightness: -0.25, saturation: -0.2);

  /// Crisp line between the face and its wall.
  Color get edgeColor => _shade(faceColor, lightness: -0.42, saturation: -0.15).withValues(alpha: 0.7);

  /// How far the soft shadow reaches past the base, down and right, as a
  /// fraction of face width (its offset plus where its blur fades out).
  double get shadowReachFraction => shadowOffsetFraction + shadowBlurFraction * 2.2;
  double get shadowReachXFraction => shadowOffsetXFraction + shadowBlurFraction * 2.2;

  /// How far the raised shadow reaches past the base (down and right).
  double get raisedShadowReachFraction => raisedShadowOffsetFraction + raisedShadowBlurFraction * 2.2;

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
}

/// [color] with its HSL lightness and saturation moved by the given amounts.
Color _shade(Color color, {double lightness = 0, double saturation = 0}) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness + lightness).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + saturation).clamp(0.0, 1.0))
      .toColor();
}

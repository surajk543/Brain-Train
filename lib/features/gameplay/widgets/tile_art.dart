import 'package:flutter/painting.dart';

import '../../../content/content_sources.dart';
import '../../../game_engine/models/level_definition.dart';
import '../../../game_engine/models/symbol_registry.dart';
import '../../../rendering/mahjong_tile_renderer.dart';
import '../../../rendering/symbol_art.dart';
import '../../../rendering/symbol_frames.dart';
import '../../../rendering/tile_style.dart';

/// One level's tiles pre-rendered at one face size, for drawing single
/// tiles off the board (the tray and tile flights) with the board's tile
/// body renderer and symbol art.
///
/// Tiles paint at any face size: the art is scaled, so load it at the
/// largest size it is shown at. Everything is an image: painting a tile is a
/// few textured draws, with no blur or vector work per frame.
class TileArt {
  TileArt({
    required this.style,
    required this.face,
    required this.body,
    required this.symbols,
    this.glow,
    this.faceBodies = const {},
    this.faceColors = const {},
    this.ownsBody = true,
  }) : renderer = MahjongTileRenderer(style);

  /// Renders the tile body (ivory, plus one per face colour of [level]'s
  /// coloured pairs) and glow at [face] and resolves the symbol art of every
  /// symbol in [level] (missing art falls back as on the board).
  static Future<TileArt> load({
    required LevelDefinition level,
    required SymbolRegistry registry,
    required ContentSource artwork,
    required SymbolArtCache symbolArt,
    required TileStyle style,
    required Size face,
    required double pixelRatio,
  }) async {
    final renderer = MahjongTileRenderer(style);
    final box = renderer.symbolRect(Offset.zero & face).size;
    final codes = [
      for (final code in {for (final tile in level.tiles) tile.symbolCode})
        if (registry[code] != null) code,
    ];
    final body = renderer.renderBody(face, pixelRatio);
    final faceBodies = renderer.renderFaceBodies(face, pixelRatio, level.faceColors);
    final glow = renderer.renderGlow(face, pixelRatio);
    final symbols = await Future.wait([
      for (final code in codes) symbolArt.resolve(registry[code]!, artwork, box, pixelRatio),
    ]);
    return TileArt(
      style: style,
      face: face,
      body: await body,
      faceBodies: await faceBodies,
      faceColors: level.faceColors,
      glow: await glow,
      symbols: {for (var i = 0; i < codes.length; i++) codes[i]: symbols[i]},
    );
  }

  final TileStyle style;

  /// The face size the art was rendered at.
  final Size face;

  /// The ivory tile body.
  final TileBodyImage body;

  /// Bodies with a coloured face, by colour name; the same size as [body].
  final Map<String, TileBodyImage> faceBodies;

  /// Symbol code -> face colour name (`LevelDefinition.faceColors`): a tile
  /// takes the colour of the symbol it shows.
  final Map<String, String> faceColors;

  /// Gold glow ring at full strength; null draws no glow.
  final TileBodyImage? glow;

  /// By symbol code. Owned by the [SymbolArtCache]; not disposed here.
  final Map<String, SymbolArt> symbols;

  /// False when [body] and [faceBodies] belong to someone else (the board),
  /// so [dispose] leaves them alone.
  final bool ownsBody;
  final MahjongTileRenderer renderer;

  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.medium;
  late final Paint _symbolPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = style.symbolColorFilter;

  /// The body of a tile showing [symbolCode]: its coloured face, or ivory.
  TileBodyImage bodyFor(String symbolCode) => faceBodies[faceColors[symbolCode]] ?? body;

  bool isAnimated(String symbolCode) => symbols[symbolCode]?.isAnimated ?? false;

  /// The animated art for [symbolCode], if it is animated.
  AnimatedSymbolArt? animatedArt(String symbolCode) => switch (symbols[symbolCode]) {
    final AnimatedSymbolArt art => art,
    _ => null,
  };

  bool get hasAnimatedSymbols => symbols.values.any((art) => art.isAnimated);

  /// The rounded face outline for a tile drawn at [face].
  RRect faceRRect(Rect face) => renderer.faceRRect(face);

  /// Paints the tile showing [symbolCode] with its face filling [face].
  ///
  /// An animated symbol shows its current frame from [atlas] when the atlas
  /// holds it, else the frame at [seconds] on a shared clock (vector work:
  /// keep that for short moments such as a flight), else its still poster.
  void paint(
    Canvas canvas,
    String symbolCode,
    Rect face, {
    double opacity = 1,
    SymbolFrameAtlas? atlas,
    double? seconds,
  }) {
    final scale = face.width / this.face.width;
    canvas
      ..save()
      ..translate(face.left, face.top);
    if (scale != 1) canvas.scale(scale);
    _imagePaint.color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    bodyFor(symbolCode).paint(canvas, Offset.zero, _imagePaint);
    final symbol = symbols[symbolCode];
    final box = renderer.symbolRect(Offset.zero & this.face);
    if (symbol is AnimatedSymbolArt && atlas != null && atlas.paint(canvas, symbol, box, _imagePaint)) {
      // Drawn from the atlas.
    } else if (symbol is AnimatedSymbolArt && seconds != null) {
      symbol.paintFrame(canvas, box, seconds, opacity: opacity, posterPaint: _imagePaint);
    } else if (symbol != null) {
      // As on the board: the colour filter is tuned for static art only.
      symbol.paint(canvas, box, symbol.isAnimated ? _imagePaint : (_symbolPaint..color = _imagePaint.color));
    }
    canvas.restore();
  }

  /// Paints the gold glow around a tile whose face is [face], at [strength].
  void paintGlow(Canvas canvas, Rect face, double strength) {
    final glow = this.glow;
    if (glow == null || strength <= 0) return;
    final scale = face.width / this.face.width;
    canvas
      ..save()
      ..translate(face.left, face.top);
    if (scale != 1) canvas.scale(scale);
    glow.paint(canvas, Offset.zero, Paint()..color = Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 1.0)));
    canvas.restore();
  }

  void dispose() {
    if (ownsBody) {
      body.dispose();
      for (final face in faceBodies.values) {
        face.dispose();
      }
    }
    glow?.dispose();
  }
}

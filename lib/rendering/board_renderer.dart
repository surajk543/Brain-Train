import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable, visibleForTesting;
import 'package:flutter/rendering.dart';

import '../game_engine/geometry/board_projection.dart';
import '../game_engine/models/level_definition.dart';
import '../game_engine/models/tile_definition.dart';
import 'mahjong_tile_renderer.dart';
import 'symbol_art.dart';
import 'symbol_frames.dart';
import 'tile_animation.dart';
import 'tile_style.dart';

/// Everything pre-rendered for one board at one size.
class BoardArt {
  const BoardArt({required this.body, required this.symbols, this.raisedShadow});

  final TileBodyImage body;

  /// Extra shadow stamped under upper-layer tiles; null for flat boards.
  final TileBodyImage? raisedShadow;

  /// By symbol code.
  final Map<String, SymbolArt> symbols;

  /// True when at least one symbol is drawn from an animation.
  bool get hasAnimatedSymbols => symbols.values.any((art) => art.isAnimated);

  void dispose() {
    body.dispose();
    raisedShadow?.dispose();
  }
}

/// Images a board keeps between frames; owned by the board widget, which
/// must [dispose] it.
///
/// * The static layer: the whole board as one image, every symbol a still
///   frame. Rebuilt only when the board changes (a move, an effect starting
///   or ending, a new size), in the background: the board
///   is drawn tile by tile until the new image is ready, then this notifies
///   its listeners (the painter) to switch to it.
/// * The [SymbolFrameAtlas] with the current frame of each animated symbol.
class BoardLayers extends ChangeNotifier {
  final SymbolFrameAtlas atlas = SymbolFrameAtlas();

  ui.Image? _image;
  Object? _key;
  double _pixelRatio = 1;
  Offset _origin = Offset.zero;
  _BoardPlan? _plan;
  Object? _pendingKey;
  Future<void>? _pending;
  bool _disposed = false;

  /// Completes once the static image being rendered (if any) is in place.
  @visibleForTesting
  Future<void> get ready => _pending ?? Future<void>.value();

  void _set(Object key, ui.Image? image, _BoardPlan plan, double pixelRatio, Offset origin) {
    _image?.dispose();
    _image = image;
    _key = key;
    _plan = plan;
    _pixelRatio = pixelRatio;
    _origin = origin;
  }

  /// Renders [picture] off the frame and installs it for [key].
  void _render(
    Object key,
    ui.Picture picture,
    int width,
    int height,
    _BoardPlan plan,
    double pixelRatio,
    Offset origin,
  ) {
    _pendingKey = key;
    final pending = picture
        .toImage(width, height)
        .then(
          (image) {
            if (_disposed || _pendingKey != key) {
              image.dispose();
              return;
            }
            _set(key, image, plan, pixelRatio, origin);
            notifyListeners();
          },
          onError: (Object _) {
            // Keep drawing tile by tile.
          },
        )
        .whenComplete(() {
          picture.dispose();
          if (_pendingKey == key) {
            _pendingKey = null;
            _pending = null;
          }
        });
    _pending = pending;
  }

  /// Ids of the tiles whose symbols are drawn moving over the static image.
  @visibleForTesting
  List<String> get debugMovingTiles => [for (final t in _plan?.live ?? const <_TileDraw>[]) t.tile.tileId];

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    _key = null;
    _plan = null;
    atlas.dispose();
    super.dispose();
  }
}

/// One tile as drawn this frame (effects applied).
class _TileDraw {
  _TileDraw(this.index, this.tile, this.rect, TileFx fx, this.shade) : invalidTint = fx.invalidTint;

  final int index;
  final TileDefinition tile;

  /// Face rectangle after the shake.
  final Rect rect;
  final double invalidTint;

  /// Darkening over the face (lower layer, blocked).
  final double shade;

  /// The animated symbol, when it is shown moving (nothing drawn later
  /// overlaps it); otherwise the tile shows the symbol's still frame.
  AnimatedSymbolArt? live;
}

/// The tiles to draw, in draw order, and which animate.
class _BoardPlan {
  _BoardPlan(this.tiles);

  final List<_TileDraw> tiles;

  Iterable<_TileDraw> get live => tiles.where((t) => t.live != null);

  Set<AnimatedSymbolArt> get liveArts => {for (final t in tiles) ?t.live};
}

/// Paints the whole board in geometry draw order.
///
/// Uses the same [BoardProjection] as hit testing. Repaints are driven by
/// [BoardEffects] and, for animated symbols, by [symbolClock]; game-state
/// changes arrive as a new painter instance.
///
/// With [layers], an idle board (no effect running) is one static image
/// plus, for each animated symbol shown moving, its current frame stamped
/// over it: a handful of draws per frame however many tiles there are.
/// While an effect runs (a blocked tile shaking) every tile is drawn live,
/// then the static image is rebuilt once it ends. A tile sent to the tray
/// disappears in the same frame: the move changes [stateVersion], which
/// draws the board live until the new static image is ready.
///
/// Animated symbols move only on tiles nothing drawn later overlaps; on a
/// covered or partly covered tile they show their still frame, so tiles in
/// front always stay in front.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.level,
    required this.projection,
    required this.art,
    required this.style,
    required this.effects,
    required this.isRemaining,
    required this.isFree,
    required this.dimBlocked,
    required this.stateVersion,
    this.symbolClock,
    this.layers,
    this.pixelRatio = 1,
    this.hidden = false,
  }) : renderer = MahjongTileRenderer(style),
       super(repaint: Listenable.merge([effects, symbolClock, layers]));

  final LevelDefinition level;
  final BoardProjection projection;
  final BoardArt art;
  final TileStyle style;
  final BoardEffects effects;
  final bool Function(int index) isRemaining;
  final bool Function(int index) isFree;
  final bool dimBlocked;

  /// Changes whenever the game state changes, to trigger a repaint.
  final int stateVersion;

  /// Time for animated symbols. Null, or [SymbolAnimationClock.motion]
  /// false: animated symbols show their still poster frame.
  final SymbolAnimationClock? symbolClock;

  /// Cached images; without them every tile is drawn on every paint.
  final BoardLayers? layers;

  /// Device pixels per logical pixel, for the cached images.
  final double pixelRatio;

  /// Draws nothing (the board intro shows the tiles meanwhile).
  final bool hidden;
  final MahjongTileRenderer renderer;

  bool get _animate => symbolClock?.motion ?? false;

  @override
  void paint(Canvas canvas, Size size) {
    if (hidden) return;
    final layers = this.layers;
    final seconds = _animate ? symbolClock!.seconds : 0.0;
    if (layers == null) {
      final plan = _planBoard();
      for (final t in plan.tiles) {
        _drawTile(canvas, t, seconds: seconds);
      }
      return;
    }
    // Everything the static image and the set of moving symbols depend on.
    final key = (stateVersion, effects.generation, projection, art, dimBlocked, size, pixelRatio, _animate);
    if (!effects.isAnimating && layers._key != key && layers._pendingKey != key) _buildStatic(layers, key);
    if (effects.isAnimating || layers._key != key) {
      // Effects running, or the new static image is not ready yet.
      final plan = _planBoard();
      if (_animate) layers.atlas.prepare(plan.liveArts, seconds);
      for (final t in plan.tiles) {
        _drawTile(canvas, t, atlas: _animate ? layers.atlas : null);
      }
      return;
    }
    final image = layers._image;
    if (image != null) {
      final origin = layers._origin;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(origin.dx, origin.dy, image.width / layers._pixelRatio, image.height / layers._pixelRatio),
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    if (!_animate) return;
    final plan = layers._plan!;
    layers.atlas.prepare(plan.liveArts, seconds);
    for (final t in plan.live) {
      _drawLiveSymbol(canvas, t, layers.atlas);
    }
  }

  /// Starts rendering the board with every symbol still into [layers]: an
  /// image just big enough for what the tiles paint (shadows included).
  void _buildStatic(BoardLayers layers, Object key) {
    final plan = _planBoard();
    Rect? bounds;
    for (final t in plan.tiles) {
      var painted = (t.rect.topLeft - art.body.faceOffset) & art.body.size;
      final raised = art.raisedShadow;
      if (t.tile.layer > 0 && raised != null) {
        painted = painted.expandToInclude((t.rect.topLeft - raised.faceOffset) & raised.size);
      }
      bounds = bounds?.expandToInclude(painted) ?? painted;
    }
    if (bounds == null) {
      layers._set(key, null, plan, pixelRatio, Offset.zero);
      return;
    }
    // On whole device pixels, so the image lands on the pixel grid.
    double down(double v) => (v * pixelRatio).floorToDouble() / pixelRatio;
    final origin = Offset(down(bounds.left), down(bounds.top));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-origin.dx, -origin.dy);
    for (final t in plan.tiles) {
      _drawTile(canvas, t);
    }
    layers._render(
      key,
      recorder.endRecording(),
      ((bounds.right - origin.dx) * pixelRatio).ceil(),
      ((bounds.bottom - origin.dy) * pixelRatio).ceil(),
      plan,
      pixelRatio,
      origin,
    );
  }

  /// Which tiles are drawn, where, and which animated symbols can move.
  _BoardPlan _planBoard() {
    final geometry = projection.geometry;
    final maxLayer = geometry.bounds.maxLayer;
    final tiles = <_TileDraw>[];
    for (final index in geometry.drawOrder) {
      final tile = level.tiles[index];
      if (!isRemaining(index) || effects.isHidden(tile.tileId)) continue;
      final fx = effects.fx(tile.tileId);
      final face = projection.faceRect(index);
      final rect = Rect.fromLTWH(face.left + fx.shakeX * face.width, face.top, face.width, face.height);
      final shade = boardTileShade(style, layer: tile.layer, maxLayer: maxLayer, blocked: dimBlocked && !isFree(index));
      tiles.add(_TileDraw(index, tile, rect, fx, shade));
    }
    if (_animate) {
      for (var i = 0; i < tiles.length; i++) {
        final symbol = art.symbols[tiles[i].tile.symbolCode];
        if (symbol is! AnimatedSymbolArt) continue;
        final area = renderer.symbolRect(tiles[i].rect);
        var covered = false;
        for (var j = i + 1; j < tiles.length && !covered; j++) {
          covered = _footprint(tiles[j]).overlaps(area);
        }
        if (!covered) tiles[i].live = symbol;
      }
    }
    return _BoardPlan(tiles);
  }

  /// Where [t] visibly paints: face, extruded walls and the dense part of
  /// its shadows.
  Rect _footprint(_TileDraw t) {
    final w = projection.faceWidth, h = projection.faceHeight;
    final r = t.rect;
    final reach = w * (style.shadowOffsetFraction + style.shadowBlurFraction);
    var right = r.right + w * style.depthXFraction + reach;
    var bottom = r.bottom + h * style.depthYFraction + reach;
    if (t.tile.layer > 0) {
      final raised = w * (style.raisedShadowOffsetFraction + style.raisedShadowBlurFraction);
      right += raised;
      bottom += raised;
    }
    return Rect.fromLTRB(r.left - w * 0.02, r.top - w * 0.02, right, bottom);
  }

  /// Draws one tile. A [TileDraw.live] symbol is drawn moving from [atlas]
  /// or, without one, straight from its animation at [seconds]; every other
  /// symbol as its still art.
  void _drawTile(Canvas canvas, _TileDraw t, {SymbolFrameAtlas? atlas, double? seconds}) => _paintTile(
    canvas,
    art,
    style,
    renderer,
    t.tile,
    t.rect,
    t.shade,
    invalidTint: t.invalidTint,
    live: t.live,
    atlas: atlas,
    seconds: seconds,
  );

  /// Redraws a moving symbol over the static layer: the face under it, the
  /// current frame, then the same shade the static layer has there, so the
  /// result matches drawing the tile live. Idle boards only (no effects).
  void _drawLiveSymbol(Canvas canvas, _TileDraw t, SymbolFrameAtlas atlas) {
    final area = renderer.symbolRect(t.rect);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    art.body.paintPart(canvas, t.rect.topLeft, area, paint);
    if (!atlas.paint(canvas, t.live!, area, paint)) return;
    final overlay = Paint();
    if (t.shade > 0) canvas.drawRect(area, overlay..color = _shadeColor(t.shade));
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.stateVersion != stateVersion ||
      old.projection != projection ||
      old.art != art ||
      old.dimBlocked != dimBlocked ||
      old.symbolClock != symbolClock ||
      old.layers != layers ||
      old.pixelRatio != pixelRatio ||
      old.hidden != hidden;
}

Color _shadeColor(double alpha) => Color.fromRGBO(24, 16, 4, alpha.clamp(0, 1));

/// Darkening over a tile's face as the board draws it: a little per layer
/// below the top one, more for a [blocked] tile.
double boardTileShade(TileStyle style, {required int layer, required int maxLayer, required bool blocked}) =>
    style.lowerLayerShade * (maxLayer - layer) + (blocked ? style.blockedDim : 0);

/// Draws [tile] with its face at [face], as the board does: raised shadow,
/// body, symbol ([live] from [atlas] or at [seconds], else still art), then
/// [shade] and [invalidTint].
void _paintTile(
  Canvas canvas,
  BoardArt art,
  TileStyle style,
  MahjongTileRenderer renderer,
  TileDefinition tile,
  Rect face,
  double shade, {
  double invalidTint = 0,
  AnimatedSymbolArt? live,
  SymbolFrameAtlas? atlas,
  double? seconds,
}) {
  final imagePaint = Paint()..filterQuality = FilterQuality.medium;
  if (tile.layer > 0) art.raisedShadow?.paint(canvas, face.topLeft, imagePaint);
  art.body.paint(canvas, face.topLeft, imagePaint);
  final symbol = art.symbols[tile.symbolCode];
  final symbolRect = renderer.symbolRect(face);
  if (live != null && atlas != null && atlas.paint(canvas, live, symbolRect, imagePaint)) {
    // Drawn from the atlas.
  } else if (live != null && seconds != null) {
    live.paintFrame(canvas, symbolRect, seconds, posterPaint: imagePaint);
  } else if (symbol != null) {
    // The colour filter is tuned for static art; animations are drawn as authored.
    symbol.paint(
      canvas,
      symbolRect,
      symbol.isAnimated
          ? imagePaint
          : (Paint()
              ..filterQuality = FilterQuality.medium
              ..colorFilter = style.symbolColorFilter),
    );
  }
  final rrect = renderer.faceRRect(face);
  final overlay = Paint();
  if (shade > 0) canvas.drawRRect(rrect, overlay..color = _shadeColor(shade));
  if (invalidTint > 0) {
    canvas.drawRRect(rrect, overlay..color = style.invalidColor.withValues(alpha: 0.32 * invalidTint));
  }
}

/// Every distinct look among some board tiles (symbol, raised or not,
/// shade), drawn exactly as the board draws them still, packed into one
/// image so a whole board can be drawn with a single `Canvas.drawRawAtlas`.
///
/// Animated symbols show their first frame. Sprites are uniform: a tile's
/// face plus its body, shadows and (for raised tiles) raised shadow. The
/// owner must [dispose] it.
class BoardSpriteAtlas {
  BoardSpriteAtlas._(this.image, this._sprites, this.anchor, this.face, this.pixelRatio, this.spriteCount);

  /// Renders the looks of [tiles] (indices into [level]) with faces of
  /// [face] size; [shadeOf] gives each tile's shade ([boardTileShade]).
  factory BoardSpriteAtlas.build({
    required LevelDefinition level,
    required BoardArt art,
    required TileStyle style,
    required Size face,
    required Iterable<int> tiles,
    required double Function(int index) shadeOf,
    required double pixelRatio,
  }) {
    final renderer = MahjongTileRenderer(style);
    // Sprite bounds around the face's top-left corner.
    var box = (-art.body.faceOffset) & art.body.size;
    final raised = art.raisedShadow;
    if (raised != null) box = box.expandToInclude((-raised.faceOffset) & raised.size);
    final looks = <(String, bool, int), int>{};
    final samples = <(TileDefinition, double)>[];
    final lookOf = <int, int>{};
    for (final index in tiles) {
      final tile = level.tiles[index];
      final shade = shadeOf(index);
      final key = (tile.symbolCode, tile.layer > 0, (shade * 1000).round());
      lookOf[index] = looks.putIfAbsent(key, () {
        samples.add((tile, shade));
        return looks.length;
      });
    }
    final count = math.max(1, samples.length);
    final columns = math.sqrt(count).ceil();
    final rows = (count / columns).ceil();
    // One pixel apart (and from the edge), so samples never bleed.
    final cellWidth = (box.width * pixelRatio).ceil() + 2;
    final cellHeight = (box.height * pixelRatio).ceil() + 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cells = <Rect>[];
    for (final (i, (tile, shade)) in samples.indexed) {
      final left = (i % columns) * cellWidth + 1.0, top = (i ~/ columns) * cellHeight + 1.0;
      cells.add(Rect.fromLTWH(left, top, box.width * pixelRatio, box.height * pixelRatio));
      canvas
        ..save()
        ..translate(left, top)
        ..scale(pixelRatio)
        ..translate(-box.left, -box.top);
      _paintTile(canvas, art, style, renderer, tile, Offset.zero & face, shade);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(columns * cellWidth, rows * cellHeight);
    picture.dispose();
    return BoardSpriteAtlas._(
      image,
      {for (final MapEntry(key: index, value: look) in lookOf.entries) index: cells[look]},
      Offset((face.width / 2 - box.left) * pixelRatio, (face.height / 2 - box.top) * pixelRatio),
      face,
      pixelRatio,
      samples.length,
    );
  }

  final ui.Image image;
  final Map<int, Rect> _sprites;

  /// The face centre inside every sprite, in image pixels.
  final Offset anchor;

  /// Face size the sprites were drawn at (logical pixels).
  final Size face;
  final double pixelRatio;

  /// Distinct looks rendered.
  final int spriteCount;

  /// The sprite of tile [index] (image pixels), or null if not included.
  Rect? spriteOf(int index) => _sprites[index];

  void dispose() => image.dispose();
}

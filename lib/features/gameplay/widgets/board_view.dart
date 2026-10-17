import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../content/content_sources.dart';
import '../../../game_engine/geometry/board_geometry.dart';
import '../../../game_engine/geometry/board_grid.dart';
import '../../../game_engine/geometry/board_projection.dart';
import '../../../game_engine/models/level_definition.dart';
import '../../../rendering/board_renderer.dart';
import '../../../rendering/mahjong_tile_renderer.dart';
import '../../../rendering/symbol_art.dart';
import '../../../rendering/tile_animation.dart';
import '../../../rendering/tile_style.dart';
import '../game_controller.dart';
import 'board_intro.dart';
import 'tile_art.dart';
import '../../../app/tablet_scale.dart';

/// How [BoardView] lays out [level] in a viewport of [size]: the fixed
/// board grid ([kBoardGridColumns] x [kBoardGridRows], [kBoardGridLayers]
/// layers) fills the area edge to edge (a small margin for shadows), so every
/// level has the same tile size; the board is centred in it. A board larger
/// than the grid (older content) is scaled down to fit.
BoardProjection boardProjectionFor(LevelDefinition level, BoardGeometry geometry, TileStyle style, Size size) =>
    BoardProjection.fit(
      geometry: geometry,
      tileWidth: level.board.tileWidth,
      tileHeight: level.board.tileHeight,
      width: size.width,
      height: size.height,
      faceAspect: style.faceAspect,
      edgeFraction: style.edgeFraction,
      layerOffsetX: level.board.layerOffsetX,
      layerOffsetY: level.board.layerOffsetY,
      padding: 4,
      grid: BoardGridSpan.campaign(tileWidth: level.board.tileWidth, tileHeight: level.board.tileHeight),
    );

/// The interactive Mahjong board.
///
/// One ticker drives both tile effects (every frame, while they run) and
/// animated symbols (a repaint per animation step, 30 a second, only while a
/// remaining tile shows one). Symbol animation pauses while the app is in
/// the background and, through [TickerMode], while the route is covered;
/// with [reduceMotion] or the platform's disable-animations setting, symbols
/// show a still frame and the board does not repaint for them at all.
///
/// When idle the board paints one cached image of all tiles plus the moving
/// symbols ([BoardLayers]); a move or effect rebuilds that image once. A
/// tile sent to the tray disappears at once; the tray flight draws it.
///
/// [BoardViewState.tileFaceRect] gives a tile's face on screen and
/// [BoardViewState.tileArt] the board's tile art, to fly a tile somewhere:
/// reach them with a `GlobalKey<BoardViewState>`.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.controller,
    required this.artwork,
    required this.symbolArt,
    required this.dimBlocked,
    required this.reduceMotion,
    this.onArtReady,
  });

  final GameController controller;
  final ContentSource artwork;
  final SymbolArtCache symbolArt;
  final bool dimBlocked;
  final bool reduceMotion;

  /// Runs each time new tile art is in place (first load, a new size).
  final VoidCallback? onArtReady;

  @override
  State<BoardView> createState() => BoardViewState();
}

class BoardViewState extends State<BoardView> with SingleTickerProviderStateMixin {
  late final TileStyle _style = TileStyle.forTileSet(widget.controller.level.tileSetId);
  late final BoardEffects _effects = BoardEffects(style: _style, reduceMotion: widget.reduceMotion);
  final SymbolAnimationClock _symbolClock = SymbolAnimationClock();
  final BoardLayers _layers = BoardLayers();
  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<BoardEvent>? _events;

  Size? _projectedSize;
  BoardProjection? _projection;
  String? _artKey;
  BoardArt? _art;
  Size _artFace = Size.zero;
  TileArt? _tileArt;

  /// Indices of tiles whose symbol art is animated (for the current art and
  /// the symbols the board shows now, see [_animatedSerial]).
  List<int> _animatedTiles = const [];

  /// The [GameController.symbolsSerial] [_animatedTiles] was worked out for.
  int _animatedSerial = -1;
  bool _effectsRunning = false;
  bool _foreground = true;
  bool _platformNoMotion = false;
  int _symbolStep = -1;

  bool get _noMotion => widget.reduceMotion || _platformNoMotion;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _syncSymbols();
      },
    );
    _events = widget.controller.events.listen(_onEvent);
    widget.controller.addListener(_syncSymbols);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _platformNoMotion = MediaQuery.disableAnimationsOf(context);
    _effects.reduceMotion = _noMotion;
    _syncSymbols();
  }

  @override
  void didUpdateWidget(BoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncSymbols);
      widget.controller.addListener(_syncSymbols);
    }
    _effects.reduceMotion = _noMotion;
    _syncSymbols();
  }

  void _onTick(Duration elapsed) {
    final effectsTicked = _effectsRunning;
    if (_effectsRunning) {
      // Repaints; the paint after the last effect ends caches the board.
      _effects.tick();
      _effectsRunning = _effects.isAnimating;
    }
    if (_symbolClock.isRunning) {
      // Repaint when the symbols' frame step changes (an effects tick
      // already repaints, reading the clock's current time).
      final step = _layers.atlas.stepAt(_symbolClock.seconds);
      if (step != _symbolStep) {
        _symbolStep = step;
        if (!effectsTicked) _symbolClock.tick();
      }
    } else if (!_effectsRunning) {
      _ticker.stop();
    }
  }

  void _startTicker() {
    if (_ticker.isActive) return;
    _symbolStep = -1;
    _ticker.start();
  }

  /// Runs the symbol clock exactly while an animated symbol is visible on
  /// the board and motion is allowed.
  void _syncSymbols() {
    if (_symbolClock.motion == _noMotion) {
      // Switch between moving and still symbols on the next frame.
      _symbolClock
        ..motion = !_noMotion
        ..tick();
    }
    final art = _art;
    if (art != null && _animatedSerial != widget.controller.symbolsSerial) _findAnimated(art);
    final engine = widget.controller.engine;
    final run = _foreground && !_noMotion && _animatedTiles.any(engine.isRemaining);
    if (run == _symbolClock.isRunning) return;
    if (run) {
      _symbolClock.start();
      _startTicker();
    } else {
      _symbolClock.pause();
      if (!_effectsRunning) _ticker.stop();
    }
  }

  void _onEvent(BoardEvent event) {
    switch (event) {
      case TileRejected(:final tileId):
        _effects.shake([tileId]);
      case BoardReset():
        _effects.reset();
      case TileToTray() || TrayPairCleared() || TrayFull() || TrayReturned() || MoveUndone():
        // Tiles leave at once; returning ones (revive, undo) are hidden and
        // revealed by the flight director ([hideTiles], [revealTile]).
        return;
      case BoardShuffled(:final changes):
        // The board already draws the new symbols ([GameController.boardLevel]);
        // the changed tiles turn over, in a wave from left to right.
        final projection = _projection;
        final engine = widget.controller.engine;
        final delays = <String, double>{};
        if (projection != null && changes.isNotEmpty) {
          final centers = {
            for (final id in changes.keys)
              if (engine.indexOf(id) case final index?) id: projection.faceRect(index).centerX,
          };
          if (centers.isNotEmpty) {
            final left = centers.values.reduce(math.min), right = centers.values.reduce(math.max);
            final span = math.max(1.0, right - left);
            for (final MapEntry(key: id, value: x) in centers.entries) {
              delays[id] = (x - left) / span;
            }
          }
        }
        _effects.flip({for (final MapEntry(key: id, value: (from, _)) in changes.entries) id: from}, delays: delays);
        if (!_effects.isAnimating) return;
      case TileHinted():
        // Drawn by the hint overlay above the board.
        return;
    }
    _effectsRunning = true;
    _startTicker();
  }

  BoardProjection _projectionFor(Size size) {
    if (_projection != null && _projectedSize == size) return _projection!;
    final level = widget.controller.level;
    _projectedSize = size;
    return _projection = boardProjectionFor(level, widget.controller.engine.geometry, _style, size);
  }

  /// Re-renders tile bodies and symbols when the face size changes.
  void _ensureArt(BoardProjection projection, double pixelRatio) {
    final key = '${projection.faceWidth.toStringAsFixed(1)}x${projection.faceHeight.toStringAsFixed(1)}@$pixelRatio';
    if (key == _artKey) return;
    _artKey = key;
    unawaited(_loadArt(key, Size(projection.faceWidth, projection.faceHeight), pixelRatio));
  }

  Future<void> _loadArt(String key, Size face, double pixelRatio) async {
    final renderer = MahjongTileRenderer(_style);
    final symbolBox = renderer.symbolRect(Offset.zero & face).size;
    final level = widget.controller.level;
    final registry = widget.controller.registry;
    final codes = {for (final tile in level.tiles) tile.symbolCode};
    final body = await renderer.renderBody(face, pixelRatio);
    // Coloured pairs: one body per face colour, baked once. Keyed by symbol,
    // so a tile keeps the colour of the symbol it shows.
    final faceBodies = await renderer.renderFaceBodies(face, pixelRatio, level.faceColors);
    final raised = level.tiles.any((t) => t.layer > 0) ? await renderer.renderRaisedShadow(face, pixelRatio) : null;
    final symbols = {
      for (final code in codes)
        code: await widget.symbolArt.resolve(registry[code]!, widget.artwork, symbolBox, pixelRatio),
    };
    final art = BoardArt(
      body: body,
      symbols: symbols,
      raisedShadow: raised,
      faceBodies: faceBodies,
      faceColors: level.faceColors,
    );
    if (!mounted || key != _artKey) {
      art.dispose();
      return;
    }
    final previous = _art;
    setState(() {
      _art = art;
      _artFace = face;
      _tileArt = null;
      _findAnimated(art);
    });
    _syncSymbols();
    if (previous != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    widget.onArtReady?.call();
  }

  /// The tiles whose symbol, as the board shows it now (after any shuffle),
  /// is animated in [art].
  void _findAnimated(BoardArt art) {
    final level = widget.controller.boardLevel;
    _animatedSerial = widget.controller.symbolsSerial;
    _animatedTiles = [
      for (var i = 0; i < level.tiles.length; i++)
        if (art.symbols[level.tiles[i].symbolCode]?.isAnimated ?? false) i,
    ];
  }

  /// True once the tile art has loaded.
  bool get hasArt => _art != null;

  /// The looks of [tiles] (board indices) exactly as the board draws them
  /// now (shading included, animated symbols at their first frame), in one
  /// image for the board intro; null before the art has loaded. The caller
  /// owns (and disposes) it.
  BoardSpriteAtlas? buildIntroAtlas(Iterable<int> tiles) {
    final art = _art, projection = _projection;
    if (art == null || projection == null) return null;
    final engine = widget.controller.engine;
    final maxLayer = engine.geometry.bounds.maxLayer;
    // A resumed game may have been shuffled: its tiles show those symbols.
    final level = widget.controller.boardLevel;
    return BoardSpriteAtlas.build(
      level: level,
      art: art,
      style: _style,
      face: _artFace,
      tiles: tiles,
      shadeOf: (i) => boardTileShade(
        _style,
        layer: level.tiles[i].layer,
        maxLayer: maxLayer,
        blocked: widget.dimBlocked && !engine.isFreeIndex(i),
      ),
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  /// The board's projection and its transform to global coordinates this
  /// frame (for the intro's landing places); null before layout.
  BoardIntroGeometry? introGeometry() {
    final projection = _projection;
    final box = context.findRenderObject();
    if (projection == null || box is! RenderBox || !box.hasSize || !box.attached) return null;
    return (projection: projection, transform: box.getTransformTo(TabletScale.canvasAbove(box)));
  }

  /// The board's tile art (tile body and symbols at the board's face size),
  /// for drawing its tiles elsewhere, e.g. in flight; null while it loads.
  /// It is replaced when the board re-renders at a new size, so read it
  /// each time rather than keeping it.
  TileArt? get tileArt {
    final art = _art;
    if (art == null) return null;
    return _tileArt ??= TileArt(
      style: _style,
      face: _artFace,
      body: art.body,
      symbols: art.symbols,
      faceBodies: art.faceBodies,
      faceColors: art.faceColors,
      ownsBody: false,
    );
  }

  /// Where the tile [tileId] shows its face right now, in global (screen)
  /// coordinates, including a shake; null before the board has laid out, or
  /// for an unknown tile. Works for tiles that have left the board too. Pass
  /// [ancestor] for coordinates relative to another render object instead.
  Rect? tileFaceRect(String tileId, {RenderObject? ancestor}) {
    final projection = _projection;
    final box = context.findRenderObject();
    if (projection == null || box is! RenderBox || !box.hasSize) return null;
    final index = widget.controller.level.tiles.indexWhere((t) => t.tileId == tileId);
    if (index < 0) return null;
    final face = projection.faceRect(index);
    final fx = _effects.fx(tileId);
    final local = Rect.fromLTWH(face.left + fx.shakeX * face.width, face.top, face.width, face.height);
    return MatrixUtils.transformRect(box.getTransformTo(ancestor ?? TabletScale.canvasAbove(box)), local);
  }

  /// Stops drawing [tileIds] (tiles flying back to the board) until each is
  /// revealed with [revealTile]. Taps are ignored meanwhile.
  void hideTiles(Iterable<String> tileIds) => _effects.hide(tileIds);

  /// Draws [tileId] again: it has landed back on the board.
  void revealTile(String tileId) => _effects.reveal(tileId);

  void _onTapUp(TapUpDetails details) {
    final projection = _projection;
    // While tiles fly back to the board, a shuffle turns tiles over, or the
    // intro plays, wait.
    if (projection == null ||
        _art == null ||
        _effects.hasHidden ||
        _effects.isFlipping ||
        widget.controller.introPlaying) {
      return;
    }
    final engine = widget.controller.engine;
    final index = TileHitTester(
      projection,
    ).hitTest(details.localPosition.dx, details.localPosition.dy, engine.isRemaining);
    if (index != null) widget.controller.tapTile(widget.controller.level.tiles[index].tileId);
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final projection = _projectionFor(constraints.biggest);
        _ensureArt(projection, pixelRatio);
        final art = _art;
        if (art == null) return const SizedBox.expand();
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            return Semantics(
              label: 'Mahjong board, ${controller.state.remaining.length} tiles remaining',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                child: CustomPaint(
                  size: constraints.biggest,
                  painter: BoardPainter(
                    // The symbols as they are now (a shuffle moves them).
                    level: controller.boardLevel,
                    projection: projection,
                    art: art,
                    style: _style,
                    effects: _effects,
                    isRemaining: controller.engine.isRemaining,
                    isFree: controller.engine.isFreeIndex,
                    dimBlocked: widget.dimBlocked,
                    stateVersion: controller.stateVersion,
                    symbolClock: art.hasAnimatedSymbols ? _symbolClock : null,
                    layers: _layers,
                    pixelRatio: pixelRatio,
                    // The intro draws the tiles until it hands over.
                    hidden: controller.introPlaying,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    widget.controller.removeListener(_syncSymbols);
    _lifecycle.dispose();
    _ticker.dispose();
    _effects.dispose();
    _symbolClock.dispose();
    _layers.dispose();
    _art?.dispose();
    super.dispose();
  }
}

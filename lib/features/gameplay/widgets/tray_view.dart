import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/brand.dart';
import '../../../content/content_sources.dart';
import '../../../game_engine/models/level_definition.dart';
import '../../../game_engine/models/symbol_registry.dart';
import '../../../game_engine/state/game_engine.dart';
import '../../../rendering/symbol_art.dart';
import '../../../rendering/symbol_frames.dart';
import '../../../rendering/tile_style.dart';
import '../../common/frosted_glass.dart';
import '../../common/static_layer.dart';
import 'tile_art.dart';
import 'tile_shatter.dart';
import '../../../app/tablet_scale.dart';

enum TrayItemPhase {
  /// Flying in from the board: its slot is reserved but drawn empty.
  incoming,

  /// Sitting in its slot.
  settled,

  /// Matched, both tiles in: striking and shattering (drawn by the shatter
  /// overlay, not the tray), then it leaves the tray.
  clearing,

  /// Flying back to the board (a revive): its slot shows empty.
  departed,
}

/// One tile in the tray's display.
class TrayItem {
  TrayItem._(this.tileId, this._phase, {required this.flew});

  final String tileId;
  TrayItemPhase _phase;

  /// Came in by a flight (plays the landing pop) rather than being restored.
  final bool flew;
  String? _partnerId;

  TrayItemPhase get phase => _phase;

  /// The tile this one matched, once matched; the two leave together.
  String? get partnerId => _partnerId;
}

/// What the tray shows. It can trail the engine's tray: a matched pair keeps
/// its slots until both tiles have landed and shattered, so tiles tapped
/// meanwhile queue after it and slide left once it has gone.
///
/// When both tiles of a pair are in, [onPairReady] runs: the owner plays the
/// strike (or, with `animate` false, just its feedback) and calls
/// [completeClear] when it is over. Without an owner the pair leaves at once.
///
/// Fed by `TrayFlightDirector` (game events and flight landings) and drawn by
/// [TrayView]. Holds at most [capacity] items: if rapid taps run out of room
/// while matched pairs are still on show, the oldest such pair leaves at once.
class TrayController extends ChangeNotifier {
  TrayController({this.capacity = GameEngine.defaultTrayCapacity});

  final int capacity;
  final List<TrayItem> _items = [];
  bool _full = false;

  /// Matched pairs leave as soon as both have landed, without a strike
  /// (reduced motion). [TrayView] keeps this in step with its motion setting.
  bool instantClears = false;

  /// Runs once per matched pair when both tiles are in ([animate] true:
  /// play the strike, then [completeClear]) or when the pair leaves
  /// without one ([animate] false: instant clears, or pushed out by rapid
  /// taps before it struck).
  void Function(String a, String b, {required bool animate})? onPairReady;
  int _impacts = 0;

  /// Counts strikes that hit: the tray gives a small shake on each.
  int get impacts => _impacts;

  /// In slot order.
  List<TrayItem> get items => UnmodifiableListView(_items);

  /// Display slot of [tileId], or -1.
  int indexOf(String tileId) => _items.indexWhere((item) => item.tileId == tileId);

  TrayItem? itemOf(String tileId) => _items.where((item) => item.tileId == tileId).firstOrNull;

  /// The game was lost with a full tray.
  bool get isFull => _full;

  /// Full and every tile has landed: time for the tray-full effect.
  bool get showsFull => _full && _items.every((item) => item.phase == TrayItemPhase.settled);

  /// Drawn in its slot by the tray: landed and not yet struck or gone.
  static bool isShown(TrayItem item) => item.phase == TrayItemPhase.settled;

  /// A tile is in flight or a matched pair is still bursting.
  bool get isBusy => _items.any((item) => item.phase != TrayItemPhase.settled);

  /// Shows [tileIds] settled in their slots, without effects (a resumed game).
  void restore(Iterable<String> tileIds) {
    _items
      ..clear()
      ..addAll([for (final id in tileIds) TrayItem._(id, TrayItemPhase.settled, flew: false)]);
    _full = false;
    notifyListeners();
  }

  void reset() => restore(const []);

  /// Reserves the next slot for [tileId], which is flying in, and returns
  /// its display slot (the flight's target).
  int expect(String tileId) {
    final existing = indexOf(tileId);
    if (existing >= 0) return existing;
    while (_items.length >= capacity) {
      final matched = _items.where((item) => item._partnerId != null).firstOrNull;
      if (matched == null) break;
      // Not struck yet (its partner still flying): it leaves without one.
      if (matched.phase != TrayItemPhase.clearing) onPairReady?.call(matched.tileId, matched._partnerId!, animate: false);
      _removePair(matched);
    }
    _items.add(TrayItem._(tileId, TrayItemPhase.incoming, flew: true));
    notifyListeners();
    return _items.length - 1;
  }

  /// [tileId]'s flight reached its slot. A matched pair strikes once both
  /// tiles are in.
  void land(String tileId) {
    final item = itemOf(tileId);
    if (item == null || item.phase != TrayItemPhase.incoming) return;
    item._phase = TrayItemPhase.settled;
    if (item._partnerId != null) _clearIfLanded(item);
    notifyListeners();
  }

  /// [arrivingTileId] matched [trayTileId]: both leave once they have landed
  /// and struck.
  void clearPair(String trayTileId, String arrivingTileId) {
    final first = itemOf(trayTileId), second = itemOf(arrivingTileId);
    if (first == null && second == null) return;
    first?._partnerId = arrivingTileId;
    second?._partnerId = trayTileId;
    _clearIfLanded((first ?? second)!);
    notifyListeners();
  }

  /// The strike of [tileId] (and so of its pair) is over: remove both.
  void completeClear(String tileId) {
    final item = itemOf(tileId);
    if (item == null) return;
    _removePair(item);
    notifyListeners();
  }

  /// A struck pair hit: the tray shakes a little.
  void impact() {
    _impacts++;
    notifyListeners();
  }

  /// A revive: the tray is no longer full, and its tiles are about to fly
  /// back to the board, each leaving its slot with [depart].
  void returnAll() {
    _full = false;
    notifyListeners();
  }

  /// [tileId] took off for the board: its slot empties in place (the others
  /// do not slide). Once every tile has gone, the tray is empty.
  void depart(String tileId) {
    final item = itemOf(tileId);
    if (item == null) return;
    item._phase = TrayItemPhase.departed;
    // Once only departed (or shattering, drawn elsewhere) tiles are left,
    // the departed ones no longer hold slots.
    if (_items.every((i) => i.phase == TrayItemPhase.departed || i.phase == TrayItemPhase.clearing)) {
      _items.removeWhere((i) => i.phase == TrayItemPhase.departed);
    }
    notifyListeners();
  }

  /// The tray filled without a match: the game is lost.
  void markFull() {
    if (_full) return;
    _full = true;
    notifyListeners();
  }

  void _clearIfLanded(TrayItem item) {
    final partner = item._partnerId == null ? null : itemOf(item._partnerId!);
    final pair = [item, ?partner];
    if (pair.any((i) => i.phase != TrayItemPhase.settled)) return;
    final animate = !instantClears && onPairReady != null;
    if (animate) {
      for (final i in pair) {
        i._phase = TrayItemPhase.clearing;
      }
    } else {
      _items.removeWhere(pair.contains);
    }
    onPairReady?.call(item.tileId, item._partnerId ?? item.tileId, animate: animate);
  }

  void _removePair(TrayItem item) {
    final partner = item._partnerId;
    _items.removeWhere((i) => i == item || (partner != null && i.tileId == partner));
  }
}

/// Where the tray's panel, slot wells and tile faces sit at a given width.
///
/// The panel is centred and only as wide as its [TrayController.capacity]
/// wells need; tile faces keep the board's face aspect.
class TrayLayout {
  TrayLayout._(this.size, this.panel, this.wells, this.faces);

  factory TrayLayout.fit({
    required double width,
    required int capacity,
    required TileStyle style,
    required double maxFaceWidth,
  }) {
    const padH = 14.0, padV = 9.0, gap = 9.0, inset = 4.0;
    final perWell = (width - 2 * padH - (capacity - 1) * gap) / capacity;
    final faceWidth = ((perWell - 2 * inset) / (1 + style.depthXFraction)).clamp(18.0, maxFaceWidth);
    final faceHeight = faceWidth / style.faceAspect;
    final wellWidth = faceWidth * (1 + style.depthXFraction) + 2 * inset;
    final wellHeight = faceHeight * (1 + style.depthYFraction) + 2 * inset;
    final panelWidth = capacity * wellWidth + (capacity - 1) * gap + 2 * padH;
    final panel = Rect.fromLTWH((width - panelWidth) / 2, 0, panelWidth, wellHeight + 2 * padV);
    final wells = <RRect>[], faces = <Rect>[];
    for (var i = 0; i < capacity; i++) {
      final well = Rect.fromLTWH(panel.left + padH + i * (wellWidth + gap), panel.top + padV, wellWidth, wellHeight);
      wells.add(RRect.fromRectAndRadius(well, Radius.circular(faceWidth * 0.18)));
      faces.add(Rect.fromLTWH(well.left + inset, well.top + inset, faceWidth, faceHeight));
    }
    return TrayLayout._(Size(width, panel.height), panel, wells, faces);
  }

  /// The whole tray widget.
  final Size size;
  final Rect panel;
  final List<RRect> wells;

  /// Tile face of each slot (the tile's depth and shadow extend past it).
  final List<Rect> faces;

  Size get faceSize => faces.first.size;
  double get panelRadius => panel.height * 0.3;
}

/// The matching tray: a dark-green glass panel with a fine gold border and
/// one recessed well per slot, at the top of the gameplay screen.
///
/// Draws [TrayController.items] with the board's tile renderer: arrivals
/// pop and settle, the rest slide left once a matched pair has gone (the
/// pair's strike and shatter are drawn by `TileShatterOverlay` from
/// [TrayViewState.snapshot] images; the tray shakes a little on impact),
/// and a full tray shakes with a red pulse. Animated symbols play here too, as
/// frames rendered once per step into a [SymbolFrameAtlas] (30 a second,
/// only while one is in the tray and motion is allowed).
///
/// Cheap while idle: the panel is one cached image ([StaticLayer], frosted
/// with [FrostedGlass]) and each tile a few image draws; nothing blurs or
/// replays vectors per frame.
///
/// Tile flights target [TrayViewState.targetRectFor]; reach it through a
/// `GlobalKey<TrayViewState>`.
class TrayView extends StatefulWidget {
  const TrayView({
    super.key,
    required this.controller,
    required this.level,
    required this.registry,
    required this.artwork,
    required this.symbolArt,
    this.reduceMotion = false,
    this.maxFaceWidth = 46,
    this.symbolClock,
  });

  final TrayController controller;
  final LevelDefinition level;
  final SymbolRegistry registry;
  final ContentSource artwork;
  final SymbolArtCache symbolArt;
  final bool reduceMotion;

  /// Largest tile face width; narrow screens get smaller tiles.
  final double maxFaceWidth;

  /// Clock for animated symbols, e.g. shared with tile flights so a tile
  /// keeps its frame when it lands. The tray starts and pauses it. Null: the
  /// tray uses its own.
  final SymbolAnimationClock? symbolClock;

  static const Duration popDuration = Duration(milliseconds: 260);

  /// The small shake when a struck pair hits.
  static const Duration impactShakeDuration = Duration(milliseconds: 160);
  static const Duration slideDuration = Duration(milliseconds: 220);
  static const Duration fullDuration = Duration(milliseconds: 900);

  static const Color fullColor = Color(0xFFE5484D);

  @override
  State<TrayView> createState() => TrayViewState();
}

class TrayViewState extends State<TrayView> with TickerProviderStateMixin {
  late final TileStyle _style = TileStyle.forTileSet(widget.level.tileSetId);
  late final Map<String, String> _symbolOf = {for (final tile in widget.level.tiles) tile.tileId: tile.symbolCode};
  late final bool _ownsClock = widget.symbolClock == null;
  late final SymbolAnimationClock _clock = widget.symbolClock ?? SymbolAnimationClock();
  final SymbolFrameAtlas _atlas = SymbolFrameAtlas();
  late final Ticker _symbolTicker;
  late final AnimationController _full;
  late final AnimationController _impact;
  late final AppLifecycleListener _lifecycle;
  int _impactsSeen = 0;

  double? _layoutWidth;
  TrayLayout? _layout;
  String? _artKey;
  TileArt? _art;
  bool _foreground = true;
  bool _platformNoMotion = false;
  bool _fullShown = false;
  int _symbolStep = -1;

  bool get _noMotion => widget.reduceMotion || _platformNoMotion;

  /// Time for animated symbols in the tray (and for tiles flying to it).
  SymbolAnimationClock get symbolClock => _clock;

  /// Tray tile art, once loaded.
  TileArt? get art => _art;

  /// Tile face size in the tray, once laid out.
  Size? get faceSize => _layout?.faceSize;

  /// Global rect of slot [index]'s tile face, once laid out.
  Rect? slotRect(int index) {
    final layout = _layout;
    final box = context.findRenderObject() as RenderBox?;
    if (layout == null || box == null || !box.hasSize || !box.attached) return null;
    final face = layout.faces[index.clamp(0, layout.faces.length - 1)];
    return MatrixUtils.transformRect(box.getTransformTo(TabletScale.canvasAbove(box)), face);
  }

  /// Global rect of the face where [tileId] sits (or is about to land) in
  /// the tray's current layout, or null when it is not in the tray.
  Rect? targetRectFor(String tileId) {
    final index = widget.controller.indexOf(tileId);
    return index < 0 ? null : slotRect(index);
  }

  @override
  void initState() {
    super.initState();
    _symbolTicker = createTicker(_onSymbolTick);
    _full = AnimationController(vsync: this, duration: TrayView.fullDuration);
    _impact = AnimationController(vsync: this, duration: TrayView.impactShakeDuration);
    _impactsSeen = widget.controller.impacts;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _syncSymbols();
      },
    );
    widget.controller.addListener(_onTrayChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _platformNoMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(TrayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTrayChanged);
      widget.controller.addListener(_onTrayChanged);
    }
    _syncMotion();
  }

  void _syncMotion() {
    widget.controller.instantClears = _noMotion;
    _syncSymbols();
  }

  void _onTrayChanged() {
    final controller = widget.controller;
    if (controller.impacts != _impactsSeen) {
      _impactsSeen = controller.impacts;
      if (!_noMotion) _impact.forward(from: 0);
    }
    if (controller.showsFull && !_fullShown) {
      _fullShown = true;
      if (_noMotion) {
        _full.value = 1;
      } else {
        _full.forward(from: 0);
      }
    } else if (!controller.isFull && _fullShown) {
      _fullShown = false;
      _full.value = 0;
    }
    setState(() {});
    _syncSymbols();
  }

  /// Animated symbols of the tiles shown in the tray.
  Set<AnimatedSymbolArt> _shownAnimated() {
    final art = _art;
    if (art == null) return const {};
    return {
      for (final item in widget.controller.items)
        if (TrayController.isShown(item)) ?art.animatedArt(_symbolOf[item.tileId] ?? ''),
    };
  }

  /// Runs the symbol clock exactly while an animated symbol is in the tray
  /// and motion is allowed, and keeps the atlas holding their frames.
  void _syncSymbols() {
    if (_clock.motion == _noMotion) {
      _clock
        ..motion = !_noMotion
        ..tick();
    }
    final shown = _shownAnimated();
    final run = _foreground && !_noMotion && shown.isNotEmpty;
    // A tile that just landed gets its frame now, not at the next step.
    if (run) _atlas.prepare(shown, _clock.seconds);
    if (run == _symbolTicker.isActive) return;
    if (run) {
      _clock.start();
      _symbolStep = -1;
      _symbolTicker.start();
    } else {
      // A shared clock keeps running for its other users.
      if (_ownsClock) _clock.pause();
      _symbolTicker.stop();
    }
  }

  /// Renders the next frame step into the atlas and repaints the animated
  /// tiles; between steps nothing happens.
  void _onSymbolTick(Duration _) {
    final step = _atlas.stepAt(_clock.seconds);
    if (step == _symbolStep) return;
    _symbolStep = step;
    _atlas.prepare(_shownAnimated(), _clock.seconds);
    _clock.tick();
  }

  TrayLayout _layoutFor(double width) {
    if (_layout != null && _layoutWidth == width) return _layout!;
    _layoutWidth = width;
    return _layout = TrayLayout.fit(
      width: width,
      capacity: widget.controller.capacity,
      style: _style,
      maxFaceWidth: widget.maxFaceWidth,
    );
  }

  void _ensureArt(TrayLayout layout, double pixelRatio) {
    final face = layout.faceSize;
    final key = '${face.width.toStringAsFixed(1)}x${face.height.toStringAsFixed(1)}@$pixelRatio';
    if (key == _artKey) return;
    _artKey = key;
    TileArt.load(
      level: widget.level,
      registry: widget.registry,
      artwork: widget.artwork,
      symbolArt: widget.symbolArt,
      style: _style,
      face: face,
      pixelRatio: pixelRatio,
    ).then((art) {
      if (!mounted || key != _artKey) {
        art.dispose();
        return;
      }
      final previous = _art;
      setState(() => _art = art);
      _syncSymbols();
      if (previous != null) SchedulerBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }, onError: (Object error) => debugPrint('tray art failed to render: $error'));
  }

  double _shake(double t) => t <= 0 || t >= 1 ? 0 : math.sin(t * math.pi * 8) * (1 - t) * 7;

  double _impactShake(double t) => t <= 0 || t >= 1 ? 0 : math.sin(t * math.pi * 4) * (1 - t) * 2.5;

  /// Renders the tile [tileId] as it looks in its slot now (an animated
  /// symbol at its current frame) to an image, with its face rect on screen,
  /// for the strike-and-shatter effect. Null when the tile is not in the
  /// tray or the art has not loaded.
  TileSnapshot? snapshot(String tileId) {
    final art = _art, face = targetRectFor(tileId);
    if (art == null || face == null) return null;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // The face and the tile's visible depth; its soft shadow is left out.
    final size = Size(
      (face.width * (1 + _style.depthXFraction)).ceilToDouble() + 1,
      (face.height * (1 + _style.depthYFraction)).ceilToDouble() + 1,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..clipRect(Offset.zero & size);
    art.paint(canvas, _symbolOf[tileId] ?? '', Offset.zero & face.size, atlas: _noMotion ? null : _atlas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    picture.dispose();
    return TileSnapshot(image: image, size: size, face: face, pixelRatio: pixelRatio);
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layoutFor(constraints.maxWidth);
        _ensureArt(layout, pixelRatio);
        final controller = widget.controller;
        final art = _art;
        final held = controller.items
            .where((item) => item.phase != TrayItemPhase.clearing && item.phase != TrayItemPhase.departed)
            .length;
        return Semantics(
          container: true,
          label: controller.isFull ? 'Tray full' : 'Tray, $held of ${controller.capacity} tiles',
          child: SizedBox.fromSize(
            size: layout.size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: layout.panel,
                  child: StaticLayer(
                    overflow: const EdgeInsets.fromLTRB(22, 16, 22, 30),
                    child: _TrayPanel(layout: layout),
                  ),
                ),
                if (controller.isFull)
                  Positioned.fromRect(
                    rect: layout.panel,
                    child: IgnorePointer(
                      child: CustomPaint(painter: _FullPulsePainter(_full, layout)),
                    ),
                  ),
                if (art != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_full, _impact]),
                        builder: (context, child) => Transform.translate(
                          offset: Offset(_shake(_full.value) + _impactShake(_impact.value), 0),
                          child: child,
                        ),
                        child: RepaintBoundary(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (final (index, item) in controller.items.indexed)
                                if (TrayController.isShown(item))
                                  AnimatedPositioned.fromRect(
                                    key: ValueKey(item.tileId),
                                    rect: layout.faces[math.min(index, layout.faces.length - 1)],
                                    duration: _noMotion ? Duration.zero : TrayView.slideDuration,
                                    curve: Curves.easeOutCubic,
                                    child: _TrayTile(
                                      art: art,
                                      symbolCode: _symbolOf[item.tileId] ?? '',
                                      pop: item.flew,
                                      animation: art.isAnimated(_symbolOf[item.tileId] ?? '') && !_noMotion
                                          ? (atlas: _atlas, clock: _clock)
                                          : null,
                                      reduceMotion: _noMotion,
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTrayChanged);
    _lifecycle.dispose();
    _symbolTicker.dispose();
    _full.dispose();
    _impact.dispose();
    if (_ownsClock) _clock.dispose();
    _atlas.dispose();
    _art?.dispose();
    super.dispose();
  }
}

/// Glass panel with the slot wells, styled like the bottom HUD's panel.
/// Static: drawn once into its [StaticLayer].
class _TrayPanel extends StatelessWidget {
  const _TrayPanel({required this.layout});

  final TrayLayout layout;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(layout.panelRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 8)),
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: FrostedGlass(
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _TrayPanelPainter(layout),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xD11A5638), Color(0xE00A3322)],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Gold border, top sheen and recessed wells; panel-local coordinates.
class _TrayPanelPainter extends CustomPainter {
  _TrayPanelPainter(this.layout);

  final TrayLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(bounds.deflate(0.75), Radius.circular(layout.panelRadius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)],
          stops: const [0, 0.5],
        ).createShader(bounds),
    );

    final shift = -layout.panel.topLeft;
    final wellFill = Paint()..color = const Color(0x8C021208);
    final innerShade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x99000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = BrandGold.deep.withValues(alpha: 0.7);
    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.08);
    for (final well in layout.wells) {
      final r = well.shift(shift);
      canvas
        ..drawRRect(r, wellFill)
        ..save()
        ..clipRRect(r)
        // Inner shadow from the top-left: the well reads as sunk in.
        ..drawRRect(r.shift(const Offset(1.2, 1.6)).inflate(1.5), innerShade)
        ..restore()
        ..drawRRect(r.shift(const Offset(0, 0.8)), lip)
        ..drawRRect(r, rim);
    }

    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandGold.light, BrandGold.base, BrandGold.deep, BrandGold.base, BrandGold.light],
            stops: [0, 0.3, 0.55, 0.8, 1],
          ).createShader(bounds),
      )
      ..drawRRect(
        rrect.deflate(1.8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.26), Colors.white.withValues(alpha: 0)],
            stops: const [0, 0.35],
          ).createShader(bounds),
      );
  }

  @override
  bool shouldRepaint(_TrayPanelPainter old) => old.layout != layout;
}

/// Red rim around a full tray: pulses while the shake runs, then stays
/// faintly lit. Plain strokes, no blur.
class _FullPulsePainter extends CustomPainter {
  _FullPulsePainter(this.animation, this.layout) : super(repaint: animation);

  final Animation<double> animation;
  final TrayLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final strength = t >= 1 ? 0.45 : 0.45 + 0.55 * math.sin(t * math.pi * 3).abs();
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(layout.panelRadius));
    const color = TrayView.fullColor;
    final shift = -layout.panel.topLeft;
    final tint = Paint()..color = color.withValues(alpha: 0.14 * strength);
    for (final well in layout.wells) {
      canvas.drawRRect(well.shift(shift), tint);
    }
    final stroke = Paint()..style = PaintingStyle.stroke;
    for (final (width, alpha) in [(7.0, 0.12), (4.0, 0.22), (1.5, 0.9)]) {
      canvas.drawRRect(
        rrect,
        stroke
          ..strokeWidth = width
          ..color = color.withValues(alpha: alpha * strength),
      );
    }
  }

  @override
  bool shouldRepaint(_FullPulsePainter old) => old.animation != animation || old.layout != layout;
}

/// Where an animated tray tile takes its frames from.
typedef _SymbolFrames = ({SymbolFrameAtlas atlas, SymbolAnimationClock clock});

/// One tray tile, with its landing pop.
class _TrayTile extends StatefulWidget {
  const _TrayTile({
    required this.art,
    required this.symbolCode,
    required this.pop,
    required this.animation,
    required this.reduceMotion,
  });

  final TileArt art;
  final String symbolCode;

  /// Play the landing pop when first shown.
  final bool pop;

  /// Only for animated symbols, while motion is allowed.
  final _SymbolFrames? animation;
  final bool reduceMotion;

  @override
  State<_TrayTile> createState() => _TrayTileState();
}

class _TrayTileState extends State<_TrayTile> with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    final animate = !widget.reduceMotion;
    _pop = AnimationController(vsync: this, duration: TrayView.popDuration, value: widget.pop && animate ? 0 : 1);
    if (_pop.value < 1) _pop.forward();
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TrayTilePainter(art: widget.art, symbolCode: widget.symbolCode, pop: _pop, frames: widget.animation),
  );
}

class _TrayTilePainter extends CustomPainter {
  _TrayTilePainter({required this.art, required this.symbolCode, required this.pop, required this.frames})
    : super(repaint: Listenable.merge([pop, frames?.clock]));

  final TileArt art;
  final String symbolCode;
  final Animation<double> pop;
  final _SymbolFrames? frames;

  @override
  void paint(Canvas canvas, Size size) {
    final face = Offset.zero & size;
    final p = pop.value;
    // Lands slightly large, dips under size and settles.
    final scale = p >= 1 ? 1.0 : 1 + 0.14 * (1 - Curves.easeOutBack.transform(p));
    canvas.save();
    if (scale != 1) {
      final c = face.center;
      canvas
        ..translate(c.dx, c.dy)
        ..scale(scale)
        ..translate(-c.dx, -c.dy);
    }
    if (p < 1) art.paintGlow(canvas, face, 0.85 * (1 - Curves.easeIn.transform(p)));
    art.paint(canvas, symbolCode, face, atlas: frames?.atlas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrayTilePainter old) =>
      old.art != art || old.symbolCode != symbolCode || old.frames != frames || old.pop != pop;
}

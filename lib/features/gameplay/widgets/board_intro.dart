import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../game_engine/campaign/campaign_config.dart';
import '../../../game_engine/geometry/board_projection.dart';
import '../../../rendering/board_renderer.dart';
import '../../../app/tablet_scale.dart';

/// How a level's intro mixes its tiles between flying in and settling.
enum IntroStyle {
  /// The cloud swirls; neighbouring tiles orbit opposite ways and cross.
  swirl,

  /// Tiles weave along a figure-8 (infinity) loop, half one way, half the
  /// other.
  weave,

  /// The cloud spirals in towards the centre and back out.
  spiral,

  /// Rows of tiles slide past each other, alternately left and right.
  waves;

  /// The style of the level [levelId], always the same for a level. Levels
  /// numbered one apart (`level-0007`, `level-0008`) never share a style;
  /// other ids pick one from their hash.
  static IntroStyle forLevel(String levelId) {
    final digits = RegExp(r'(\d+)$').firstMatch(levelId)?.group(1);
    final number = digits == null ? _fnv(levelId) : int.parse(digits);
    return _sequence[number % _sequence.length];
  }

  // No two neighbours (wrapping round) are the same.
  static const List<IntroStyle> _sequence = [swirl, weave, waves, spiral, weave, swirl, spiral, waves];
}

/// FNV-1a of [text]: a stable seed (String.hashCode is not).
int _fnv(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The choreography's seed for [levelId]: the same intro every time.
int introSeed(String levelId) => _fnv(levelId);

/// How long a level's intro runs, by its tier: bigger boards get longer so
/// every tile has time to fly in, mix and land.
abstract final class IntroTiming {
  static const Duration easy = Duration(milliseconds: 2000);
  static const Duration medium = Duration(milliseconds: 2300);
  static const Duration hard = Duration(milliseconds: 2600);
  static const Duration veryHard = Duration(milliseconds: 3000);

  /// For a level's tier (`1`..`10` from [easy] to [veryHard] in even steps,
  /// or `easy`, `medium`, `hard`, `veryHard`), or by its [tileCount] when it
  /// has none (or an unknown one).
  static Duration forLevel({String? difficulty, required int tileCount}) {
    final number = difficulty == null ? null : numericDifficulty(difficulty);
    if (number != null) {
      final span = veryHard.inMilliseconds - easy.inMilliseconds;
      return Duration(milliseconds: easy.inMilliseconds + (span * (number - 1) / (kMaxDifficulty - 1)).round());
    }
    return switch (difficulty) {
      'easy' => easy,
      'medium' => medium,
      'hard' => hard,
      'veryHard' => veryHard,
      _ => tileCount < 50 ? easy : (tileCount < 82 ? medium : (tileCount < 130 ? hard : veryHard)),
    };
  }
}

/// Where a tile is at one moment of the intro (overlay coordinates).
class IntroPose {
  const IntroPose(this.center, this.rotation, this.scale);

  final Offset center;

  /// Radians.
  final double rotation;

  /// Relative to the tile's size on the board.
  final double scale;
}

/// The screen and board an intro frame is laid out in (overlay
/// coordinates): targets are read again every frame, so a resize mid-intro
/// just bends the paths.
class IntroStage {
  const IntroStage({required this.screen, required this.board, required this.faceWidth});

  final Size screen;
  final Rect board;
  final double faceWidth;
}

/// The intro choreography for one board, deterministic for a seed (pure
/// maths, no Flutter state). For an intro of [total] seconds:
///
/// * Fly in, 0-0.8 s (always snappy): every tile enters from off-screen, a
///   quarter from each side (shuffled per tile), easing out into a loose
///   formation around the board centre with a little spin.
/// * Mix ([style]): the formation moves, so the tiles clearly mix. Longer
///   intros mostly lengthen this phase.
/// * Settle (0.7 s at 2 s, up to 1.0 s at 3 s): each tile flies to its board
///   place, lower layers first, with a small squash on landing. The last
///   [finalHold] seconds every tile is exactly in place, unrotated, at full
///   size, so the hand-over to the board has no jump.
class IntroChoreography {
  IntroChoreography({
    required this.layers,
    required int seed,
    this.style = IntroStyle.swirl,
    Duration duration = IntroTiming.easy,
  }) : total = duration.inMicroseconds / Duration.microsecondsPerSecond,
       _maxLayer = layers.fold(0, math.max) {
    final extra = math.max(0.0, total - 2.0);
    final settle = 0.7 + extra * 0.3;
    mixEnd = total - settle;
    layerSpread = 0.25 * settle / 0.7;
    final random = math.Random(seed);
    // Within a layer tiles leave a little apart, but never as late as the
    // next layer: lower layers always start, and land, first.
    final jitter = _maxLayer == 0 ? settleJitter : math.min(settleJitter, layerSpread / _maxLayer * 0.9);
    settleTime = settle - finalHold - layerSpread - settleJitter;
    final sides = [for (var i = 0; i < layers.length; i++) IntroSide.values[i % 4]]..shuffle(random);
    this.sides = List.unmodifiable(sides);
    for (var i = 0; i < layers.length; i++) {
      _along.add(0.08 + random.nextDouble() * 0.84);
      _delay.add(random.nextDouble() * 0.18);
      _cloudAngle.add(random.nextDouble() * 2 * math.pi);
      _cloudRadius.add(0.3 + 0.7 * math.sqrt(random.nextDouble()));
      final direction = (i.isEven ? 1 : -1) * (random.nextDouble() < 0.8 ? 1 : -1);
      _orbit.add(direction * (1.0 + random.nextDouble() * 0.9));
      _spin.add((random.nextBool() ? 1 : -1) * (0.5 + random.nextDouble() * 0.8));
      _spinMix.add((random.nextBool() ? 1 : -1) * (1.2 + random.nextDouble() * 1.6));
      _jitter.add(random.nextDouble() * jitter);
      _row.add(random.nextInt(_rows));
      _rowX.add(random.nextDouble() * 2 - 1);
    }
  }

  /// End of the fly-in (seconds), whatever the intro's length.
  static const double flyInEnd = 0.8;

  /// Extra random settle delay within a layer.
  static const double settleJitter = 0.06;

  /// Every tile is in its final pose this long before the end.
  static const double finalHold = 0.05;

  /// Tiles shrink a little while they mix.
  static const double cloudScale = 0.86;

  static const int _rows = 5;

  /// Board layer of each tile, in draw order.
  final List<int> layers;
  final IntroStyle style;

  /// Length of the intro (seconds).
  final double total;

  /// End of the mix (seconds): settling begins.
  late final double mixEnd;

  /// Settle starts this much later for the top layer than for layer 0.
  late final double layerSpread;

  /// Each tile's flight from the formation to its place (landing included).
  late final double settleTime;
  final int _maxLayer;
  late final List<IntroSide> sides;
  final List<double> _along = [], _delay = [], _cloudAngle = [], _cloudRadius = [];
  final List<double> _orbit = [], _spin = [], _spinMix = [], _jitter = [], _rowX = [];
  final List<int> _row = [];

  int get length => layers.length;

  /// When tile [i] leaves the formation for its place (seconds).
  double settleStart(int i) => mixEnd + (_maxLayer == 0 ? 0 : layerSpread * layers[i] / _maxLayer) + _jitter[i];

  /// When tile [i] has landed (seconds); never after [total] - [finalHold].
  double settleEnd(int i) => settleStart(i) + settleTime;

  /// When every tile of [layer] has landed (seconds); 0 for a layer with no
  /// tiles.
  double layerLanded(int layer) => _layerLanded[layer] ?? 0;

  late final Map<int, double> _layerLanded = () {
    final landed = <int, double>{};
    for (var i = 0; i < length; i++) {
      landed[layers[i]] = math.max(landed[layers[i]] ?? 0, settleEnd(i));
    }
    return landed;
  }();

  Offset _start(int i, IntroStage stage) {
    final reach = stage.faceWidth * 1.6;
    final s = stage.screen;
    return switch (sides[i]) {
      IntroSide.left => Offset(-reach, s.height * _along[i]),
      IntroSide.right => Offset(s.width + reach, s.height * _along[i]),
      IntroSide.top => Offset(s.width * _along[i], -reach),
      IntroSide.bottom => Offset(s.width * _along[i], s.height + reach),
    };
  }

  /// Formation radii around the board centre, kept on screen.
  Size _cloud(IntroStage stage) {
    final min = stage.faceWidth * 1.8;
    return Size(
      math.min(math.max(stage.board.width * 0.32, min), stage.screen.width * 0.42),
      math.min(math.max(stage.board.height * 0.3, min), stage.screen.height * 0.3),
    );
  }

  /// Mix progress at [t]: 0 when the mix starts, easing in to 1 at its end,
  /// then growing at the same rate for tiles that settle later (no jerk).
  double _mixProgress(double t) {
    final m = (t - flyInEnd) / (mixEnd - flyInEnd);
    if (m <= 0) return 0;
    return m >= 1 ? 1 + (m - 1) * math.pi / 2 : 1 - math.cos(math.pi * m / 2);
  }

  /// Where tile [i] is in the mixing formation at [t] (seconds, from
  /// [flyInEnd] on): the fly-in ends here, the settle starts from here.
  Offset _formation(int i, double t, IntroStage stage) {
    final cloud = _cloud(stage);
    final c = stage.board.center;
    final m = ((t - flyInEnd) / (mixEnd - flyInEnd)).clamp(0.0, 1.0);
    final p = _mixProgress(t);
    final r = _cloudRadius[i];
    switch (style) {
      case IntroStyle.swirl:
        final angle = _cloudAngle[i] + _orbit[i] * p;
        final radius = r * (1 + 0.18 * math.sin(math.pi * m));
        return c + Offset(math.cos(angle) * cloud.width * radius, math.sin(angle) * cloud.height * radius);
      case IntroStyle.weave:
        // A lemniscate of Gerono; each tile has its own place on the loop
        // and half the tiles run it backwards, so they weave through each
        // other at the crossing.
        final phase = _cloudAngle[i] + (_orbit[i] > 0 ? 1 : -1) * p * math.pi * 0.9;
        final spread = 0.75 + 0.25 * r;
        return c + Offset(math.cos(phase) * cloud.width * spread, math.sin(2 * phase) / 2 * cloud.height * 1.5 * spread);
      case IntroStyle.spiral:
        // Everyone turns the same way while the cloud draws in towards the
        // centre and opens out again.
        final angle = _cloudAngle[i] + p * 1.4 * math.pi;
        final radius = r * (1 - 0.72 * math.sin(math.pi * m));
        return c + Offset(math.cos(angle) * cloud.width * radius, math.sin(angle) * cloud.height * radius);
      case IntroStyle.waves:
        // Rows of a loose block; alternate rows slide left and right past
        // each other, with a gentle ripple.
        final row = _row[i];
        final y = ((row + 0.5) / _rows * 2 - 1) * cloud.height;
        final direction = row.isEven ? 1.0 : -1.0;
        final x = _rowX[i] * cloud.width + direction * cloud.width * 0.85 * math.sin(math.pi / 2 * math.min(p, 2.0));
        final ripple = math.sin(_rowX[i] * math.pi * 2 + p * math.pi * 2) * stage.faceWidth * 0.25;
        return c + Offset(x, y + ripple);
    }
  }

  double _mixRotation(int i, double t) {
    final m = ((t - flyInEnd) / (mixEnd - flyInEnd)).clamp(0.0, double.infinity);
    final turn = style == IntroStyle.waves ? 0.35 : 1.0;
    return _spin[i] * 0.3 + _spinMix[i] * turn * math.min(m, 1.4);
  }

  /// Tile [i] at [t] seconds, landing on [target] (its face centre).
  IntroPose poseAt(int i, double t, {required Offset target, required IntroStage stage}) {
    if (t >= settleEnd(i)) return IntroPose(target, 0, 1);
    if (t < flyInEnd) {
      final delay = _delay[i];
      final u = ((t - delay) / (flyInEnd - delay)).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(u);
      return IntroPose(
        Offset.lerp(_start(i, stage), _formation(i, flyInEnd, stage), e)!,
        _spin[i] * (1 - 0.7 * e),
        1 + (cloudScale - 1) * e,
      );
    }
    final s0 = settleStart(i);
    if (t < s0) return IntroPose(_formation(i, t, stage), _mixRotation(i, t), cloudScale);
    final v = (t - s0) / settleTime;
    final e = Curves.easeOutCubic.transform(v);
    var scale = cloudScale + (1 - cloudScale) * e;
    if (v > 0.75) scale *= 1 - 0.05 * math.sin(math.pi * (v - 0.75) / 0.25);
    return IntroPose(Offset.lerp(_formation(i, s0, stage), target, e)!, _mixRotation(i, s0) * (1 - e), scale);
  }
}

/// The side of the screen a tile flies in from.
enum IntroSide { left, right, top, bottom }

/// Where the board is this frame: its projection and its transform to
/// global coordinates.
typedef BoardIntroGeometry = ({BoardProjection projection, Matrix4 transform});

/// One run of the intro: the board's tile looks in a [BoardSpriteAtlas],
/// the tiles to animate (board indices, in draw order) and the
/// choreography. Owns the atlas.
class BoardIntro {
  BoardIntro({
    required this.atlas,
    required this.tiles,
    required List<int> layers,
    required int seed,
    IntroStyle style = IntroStyle.swirl,
    Duration duration = IntroTiming.easy,
    required this.geometry,
    this.onLayerLanded,
    this.onDone,
  }) : choreography = IntroChoreography(layers: layers, seed: seed, style: style, duration: duration),
       _transforms = Float32List(tiles.length * 4),
       _rects = Float32List(tiles.length * 4) {
    for (final (k, index) in tiles.indexed) {
      final sprite = atlas.spriteOf(index) ?? Rect.zero;
      _rects
        ..[k * 4] = sprite.left
        ..[k * 4 + 1] = sprite.top
        ..[k * 4 + 2] = sprite.right
        ..[k * 4 + 3] = sprite.bottom;
    }
    _layersLeft = {...layers};
  }

  final BoardSpriteAtlas atlas;
  final List<int> tiles;
  final IntroChoreography choreography;

  /// The board now, read every frame; null skips painting.
  final ValueGetter<BoardIntroGeometry?> geometry;
  final ValueChanged<int>? onLayerLanded;
  final VoidCallback? onDone;
  final Float32List _transforms;
  final Float32List _rects;
  late Set<int> _layersLeft;
  Duration? _startedAt;
  double _seconds = 0;
  bool _disposed = false;

  /// Seconds since the intro's first frame.
  double get seconds => _seconds;

  bool get isDisposed => _disposed;

  /// Draws every tile at [seconds] with one `drawRawAtlas`, in draw order
  /// (lower layers first). [origin] is the overlay's global position.
  void paint(Canvas canvas, Size size, Offset origin) {
    final board = geometry();
    if (board == null || _disposed) return;
    final projection = board.projection;
    final toLocal = Matrix4.translationValues(-origin.dx, -origin.dy, 0)..multiply(board.transform);
    final b = projection.boardRect;
    final stage = IntroStage(
      screen: size,
      board: MatrixUtils.transformRect(toLocal, Rect.fromLTWH(b.left, b.top, b.width, b.height)),
      faceWidth: projection.faceWidth,
    );
    final sizeScale = projection.faceWidth / atlas.face.width / atlas.pixelRatio;
    final ax = atlas.anchor.dx, ay = atlas.anchor.dy;
    for (final (k, index) in tiles.indexed) {
      final face = projection.faceRect(index);
      final target = MatrixUtils.transformPoint(toLocal, Offset(face.centerX, face.centerY));
      final pose = choreography.poseAt(k, _seconds, target: target, stage: stage);
      final scale = sizeScale * pose.scale;
      final scos = scale * math.cos(pose.rotation), ssin = scale * math.sin(pose.rotation);
      _transforms
        ..[k * 4] = scos
        ..[k * 4 + 1] = ssin
        ..[k * 4 + 2] = pose.center.dx - scos * ax + ssin * ay
        ..[k * 4 + 3] = pose.center.dy - ssin * ax - scos * ay;
    }
    canvas.drawRawAtlas(atlas.image, _transforms, _rects, null, null, null, Paint()..filterQuality = FilterQuality.medium);
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    atlas.dispose();
  }
}

/// Runs the board intro. [BoardIntroOverlay] ticks it every frame while it
/// runs and draws it; nothing runs otherwise.
class BoardIntroController extends ChangeNotifier {
  BoardIntro? _intro;

  BoardIntro? get intro => _intro;

  bool get isRunning => _intro != null;

  /// Starts [intro], replacing (and freeing) any running one.
  void play(BoardIntro intro) {
    _intro?._dispose();
    _intro = intro;
    notifyListeners();
  }

  /// Advances to [now] on the driving ticker's clock (the intro's clock
  /// starts at its first tick): reports layers as they land, and ends the
  /// intro after its choreography's [IntroChoreography.total].
  void tick(Duration now) {
    final intro = _intro;
    if (intro == null) return;
    final start = intro._startedAt ??= now;
    intro._seconds = (now - start).inMicroseconds / Duration.microsecondsPerSecond;
    final landed = [
      for (final layer in intro._layersLeft)
        if (intro._seconds >= intro.choreography.layerLanded(layer)) layer,
    ]..sort();
    intro._layersLeft.removeAll(landed);
    final done = intro._seconds >= intro.choreography.total;
    if (done) {
      _intro = null;
      intro._dispose();
    }
    notifyListeners();
    for (final layer in landed) {
      intro.onLayerLanded?.call(layer);
    }
    if (done) intro.onDone?.call();
  }

  /// Stops the intro without its callbacks (leaving, or a restart replaces
  /// it).
  void cancel() {
    final intro = _intro;
    if (intro == null) return;
    _intro = null;
    intro._dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    _intro?._dispose();
    _intro = null;
    super.dispose();
  }
}

/// Draws the board intro above the gameplay screen (tiles enter from every
/// side). Ignores touches; its ticker runs only while the intro does. Each
/// frame is one `drawRawAtlas` for every tile: no layers, no blur.
class BoardIntroOverlay extends StatefulWidget {
  const BoardIntroOverlay({super.key, required this.controller});

  final BoardIntroController controller;

  @override
  State<BoardIntroOverlay> createState() => _BoardIntroOverlayState();
}

class _BoardIntroOverlayState extends State<BoardIntroOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => widget.controller.tick(elapsed));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(BoardIntroOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final running = widget.controller.isRunning;
    if (running && !_ticker.isActive) {
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  Offset _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? Offset.zero : box.localToGlobal(Offset.zero, ancestor: TabletScale.canvasAbove(box));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: Size.infinite,
      painter: _IntroPainter(widget.controller, _origin),
    ),
  );
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.controller, this.origin) : super(repaint: controller);

  final BoardIntroController controller;
  final ValueGetter<Offset> origin;

  @override
  void paint(Canvas canvas, Size size) => controller.intro?.paint(canvas, size, origin());

  @override
  bool shouldRepaint(_IntroPainter old) => old.controller != controller;
}

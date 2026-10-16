import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/brand.dart';

/// The matched tiles slide into each other (a short wind-up, then faster).
const Duration kStrikeDuration = Duration(milliseconds: 180);

/// Contact: both tiles squash, a spark flashes where they meet.
const Duration kImpactDuration = Duration(milliseconds: 80);

/// Shards fly apart, spin, fall, shrink and fade.
const Duration kShatterDuration = Duration(milliseconds: 600);

/// A tile as it looked when its pair was struck, rendered once to an image.
///
/// [face] is its face rect on screen (global, logical pixels); the image
/// starts at the face's top-left and is [size] big (the face plus the
/// tile's visible depth), at [pixelRatio].
class TileSnapshot {
  TileSnapshot({required this.image, required this.size, required this.face, required this.pixelRatio});

  final ui.Image image;
  final Size size;
  final Rect face;
  final double pixelRatio;

  void dispose() => image.dispose();
}

/// One triangular shard of a tile: its corners in the tile's own logical
/// coordinates (also its texture coordinates), and how it flies.
class _Shard {
  _Shard(this.corners, this.centroid, this.direction, this.speed, this.spin);

  final List<Offset> corners;
  final Offset centroid;
  final Offset direction;
  final double speed;
  final double spin;
}

/// Two matched tiles striking each other and shattering: strike
/// ([kStrikeDuration]), impact ([kImpactDuration], when [onImpact] runs),
/// then shards ([kShatterDuration]); [onDone] runs at the end.
class PairShatter {
  PairShatter._(TileSnapshot a, TileSnapshot b, this._onImpact, this._onDone, int seed)
    : left = a.face.left <= b.face.left ? a : b,
      right = a.face.left <= b.face.left ? b : a {
    final width = left.face.width;
    contact = Offset((left.face.center.dx + right.face.center.dx) / 2, (left.face.center.dy + right.face.center.dy) / 2);
    _leftEnd = Offset(contact.dx - width / 2, contact.dy) - left.face.center;
    _rightEnd = Offset(contact.dx + right.face.width / 2, contact.dy) - right.face.center;
    final random = math.Random(seed);
    _leftShards = _cut(left, _leftEnd, random);
    _rightShards = _cut(right, _rightEnd, random);
  }

  static final Duration total = kStrikeDuration + kImpactDuration + kShatterDuration;

  final TileSnapshot left;
  final TileSnapshot right;
  final VoidCallback? _onImpact;
  final VoidCallback? _onDone;

  /// Where the tiles meet (global).
  late final Offset contact;
  late final Offset _leftEnd, _rightEnd;
  late final List<_Shard> _leftShards, _rightShards;
  late final Float32List _leftTexture = _texture(_leftShards), _rightTexture = _texture(_rightShards);
  Duration? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _impacted = false;

  /// Time since the strike began.
  Duration get elapsed => _elapsed;

  /// True once the tiles have met ([onImpact] has run).
  bool get impacted => _impacted;

  int get shardCount => _leftShards.length + _rightShards.length;

  /// Cuts a tile into 18 irregular triangles: a 3x3 grid with jittered
  /// inner points, each cell split along a random diagonal. Shards fly away
  /// from the contact point.
  List<_Shard> _cut(TileSnapshot tile, Offset end, math.Random random) {
    const cols = 3, rows = 3;
    final w = tile.size.width, h = tile.size.height;
    final cell = Size(w / cols, h / rows);
    final points = [
      for (var r = 0; r <= rows; r++)
        [
          for (var c = 0; c <= cols; c++)
            Offset(
              c * cell.width + (c > 0 && c < cols ? (random.nextDouble() - 0.5) * cell.width * 0.56 : 0),
              r * cell.height + (r > 0 && r < rows ? (random.nextDouble() - 0.5) * cell.height * 0.56 : 0),
            ),
        ],
    ];
    // The contact point in this tile's coordinates at impact.
    final origin = contact - (tile.face.topLeft + end);
    final shards = <_Shard>[];
    void add(Offset a, Offset b, Offset c) {
      final centroid = (a + b + c) / 3;
      var direction = centroid - origin;
      final angle = math.atan2(direction.dy, direction.dx) + (random.nextDouble() - 0.5) * 0.9;
      direction = Offset(math.cos(angle), math.sin(angle) - 0.35);
      shards.add(
        _Shard(
          [a, b, c],
          centroid,
          direction,
          tile.face.width * (2.4 + random.nextDouble() * 2.6),
          (random.nextBool() ? 1 : -1) * (3 + random.nextDouble() * 7),
        ),
      );
    }

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final p00 = points[r][c], p10 = points[r][c + 1], p01 = points[r + 1][c], p11 = points[r + 1][c + 1];
        if (random.nextBool()) {
          add(p00, p10, p11);
          add(p00, p11, p01);
        } else {
          add(p00, p10, p01);
          add(p10, p11, p01);
        }
      }
    }
    return shards;
  }

  static Float32List _texture(List<_Shard> shards) =>
      Float32List.fromList([for (final s in shards) for (final p in s.corners) ...[p.dx, p.dy]]);

  /// The strike offset of a tile ending its slide at [end]: pulls back a
  /// little, then accelerates in.
  static Offset _strikeOffset(Offset end, double width, double t) {
    const windUp = 0.3;
    final away = end.distance == 0 ? Offset.zero : -end / end.distance * width * 0.1;
    if (t < windUp) return away * math.sin(math.pi / 2 * t / windUp);
    final u = Curves.easeInCubic.transform((t - windUp) / (1 - windUp));
    return Offset.lerp(away, end, u)!;
  }

  void _paint(Canvas canvas, Offset shift) {
    final strike = _elapsed.inMicroseconds / kStrikeDuration.inMicroseconds;
    if (strike < 1) {
      _paintTile(canvas, left, _strikeOffset(_leftEnd, left.face.width, strike), 1, 1, shift);
      _paintTile(canvas, right, _strikeOffset(_rightEnd, right.face.width, strike), 1, 1, shift);
      return;
    }
    final afterStrike = _elapsed - kStrikeDuration;
    if (afterStrike < kImpactDuration) {
      final t = afterStrike.inMicroseconds / kImpactDuration.inMicroseconds;
      final k = math.sin(math.pi * t);
      _paintTile(canvas, left, _leftEnd, 1 - 0.1 * k, 1 + 0.06 * k, shift);
      _paintTile(canvas, right, _rightEnd, 1 - 0.1 * k, 1 + 0.06 * k, shift);
      _paintSpark(canvas, contact + shift, t, left.face.height);
      return;
    }
    final s = (afterStrike - kImpactDuration).inMicroseconds / Duration.microsecondsPerSecond;
    final t = (s * Duration.microsecondsPerSecond / kShatterDuration.inMicroseconds).clamp(0.0, 1.0);
    _paintShards(canvas, left, _leftEnd, _leftShards, _leftTexture, s, t, shift);
    _paintShards(canvas, right, _rightEnd, _rightShards, _rightTexture, s, t, shift);
    if (t < 0.25) _paintSpark(canvas, contact + shift, 1 + t * 4, left.face.height);
  }

  void _paintTile(Canvas canvas, TileSnapshot tile, Offset offset, double scaleX, double scaleY, Offset shift) {
    final topLeft = tile.face.topLeft + offset + shift;
    final center = topLeft + tile.face.size.center(Offset.zero);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scaleX, scaleY)
      ..translate(-center.dx, -center.dy)
      ..drawImageRect(
        tile.image,
        Rect.fromLTWH(0, 0, tile.image.width.toDouble(), tile.image.height.toDouble()),
        topLeft & tile.size,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }

  /// A short gold-white star where the tiles meet; [t] runs 0-2 (flash,
  /// then fade).
  static void _paintSpark(Canvas canvas, Offset at, double t, double size) {
    final strength = t <= 1 ? math.sin(math.pi / 2 * t) : (2 - t).clamp(0.0, 1.0);
    if (strength <= 0) return;
    final reach = size * (0.25 + 0.35 * math.min(t, 1.5));
    final ray = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = BrandGold.light.withValues(alpha: 0.95 * strength);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + math.pi / 8;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(at + dir * reach * 0.3, at + dir * reach * (i.isEven ? 1 : 0.65), ray);
    }
    canvas.drawCircle(at, size * 0.12 * strength, Paint()..color = Colors.white.withValues(alpha: 0.9 * strength));
  }

  void _paintShards(
    Canvas canvas,
    TileSnapshot tile,
    Offset end,
    List<_Shard> shards,
    Float32List texture,
    double seconds,
    double t,
    Offset shift,
  ) {
    if (t >= 1) return;
    final origin = tile.face.topLeft + end + shift;
    final gravity = tile.face.width * 24;
    final shrink = 1 - 0.5 * Curves.easeIn.transform(t);
    final positions = Float32List(texture.length);
    var i = 0;
    for (final shard in shards) {
      final travel = shard.direction * (shard.speed * seconds) + Offset(0, 0.5 * gravity * seconds * seconds);
      final angle = shard.spin * seconds;
      final cos = math.cos(angle), sin = math.sin(angle);
      for (final p in shard.corners) {
        final d = (p - shard.centroid) * shrink;
        final q = origin + shard.centroid + travel + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
        positions[i++] = q.dx;
        positions[i++] = q.dy;
      }
    }
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, positions, textureCoordinates: texture);
    final scale = 1 / tile.pixelRatio;
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, 1 - Curves.easeIn.transform(t))
        ..shader = ImageShader(
          tile.image,
          TileMode.clamp,
          TileMode.clamp,
          Float64List.fromList([scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
          filterQuality: FilterQuality.medium,
        ),
    );
    vertices.dispose();
  }

  void _dispose() {
    left.dispose();
    right.dispose();
  }
}

/// Runs pair shatters. [TileShatterOverlay] ticks it every frame while one
/// runs and draws them; nothing runs otherwise. Owns the snapshots it is
/// given and disposes them when a shatter ends or is cancelled.
class TileShatterController extends ChangeNotifier {
  final List<PairShatter> _shatters = [];
  int _seed = 0;

  List<PairShatter> get shatters => UnmodifiableListView(_shatters);

  bool get isRunning => _shatters.isNotEmpty;

  /// Starts [a] and [b] striking each other. [onImpact] runs when they meet,
  /// [onDone] when the last shard has gone.
  PairShatter start(TileSnapshot a, TileSnapshot b, {VoidCallback? onImpact, VoidCallback? onDone}) {
    final shatter = PairShatter._(a, b, onImpact, onDone, _seed++);
    _shatters.add(shatter);
    notifyListeners();
    return shatter;
  }

  /// Advances every shatter to [now] on the driving ticker's clock (its
  /// clock starts at its first tick), then runs impact and done callbacks.
  void tick(Duration now) {
    if (_shatters.isEmpty) return;
    final impacts = <PairShatter>[], done = <PairShatter>[];
    for (final shatter in _shatters) {
      final start = shatter._startedAt ??= now;
      shatter._elapsed = now - start;
      if (!shatter._impacted && shatter._elapsed >= kStrikeDuration) {
        shatter._impacted = true;
        impacts.add(shatter);
      }
      if (shatter._elapsed >= PairShatter.total) done.add(shatter);
    }
    _shatters.removeWhere(done.contains);
    notifyListeners();
    for (final shatter in impacts) {
      shatter._onImpact?.call();
    }
    for (final shatter in done) {
      shatter._dispose();
      shatter._onDone?.call();
    }
  }

  /// Drops every shatter without its callbacks (the level restarted).
  void cancelAll() {
    if (_shatters.isEmpty) return;
    for (final shatter in _shatters) {
      shatter._dispose();
    }
    _shatters.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final shatter in _shatters) {
      shatter._dispose();
    }
    _shatters.clear();
    super.dispose();
  }
}

/// Draws pair shatters above the whole gameplay screen (shards may fall
/// over the board). Ignores touches; its ticker runs only while a shatter
/// runs. Each frame is a few image draws: two tile images while striking,
/// then one `drawVertices` per tile for all its shards. No layers, no blur.
class TileShatterOverlay extends StatefulWidget {
  const TileShatterOverlay({super.key, required this.controller});

  final TileShatterController controller;

  @override
  State<TileShatterOverlay> createState() => _TileShatterOverlayState();
}

class _TileShatterOverlayState extends State<TileShatterOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => widget.controller.tick(elapsed));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(TileShatterOverlay oldWidget) {
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
    return box == null || !box.hasSize ? Offset.zero : box.localToGlobal(Offset.zero);
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
      painter: _ShatterPainter(widget.controller, _origin),
    ),
  );
}

class _ShatterPainter extends CustomPainter {
  _ShatterPainter(this.controller, this.origin) : super(repaint: controller);

  final TileShatterController controller;
  final ValueGetter<Offset> origin;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isRunning) return;
    final shift = -origin();
    for (final shatter in controller.shatters) {
      if (shatter._startedAt == null) {
        // Not ticked yet: the tiles still sit in their slots.
        shatter._paintTile(canvas, shatter.left, Offset.zero, 1, 1, shift);
        shatter._paintTile(canvas, shatter.right, Offset.zero, 1, 1, shift);
      } else {
        shatter._paint(canvas, shift);
      }
    }
  }

  @override
  bool shouldRepaint(_ShatterPainter old) => old.controller != controller;
}

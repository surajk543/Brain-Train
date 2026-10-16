import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ambient_clock.dart';

/// Leaves (and the odd gold leaf or cream petal) drifting slowly down and
/// across the screen with a gentle sway, spin and 3D flip. Far leaves are
/// small, soft, faint and slow; near leaves are larger, crisp and a little
/// faster.
///
/// Decorative only: place it behind content (glass panels then blur it) and
/// it never takes taps. One [AmbientClock] drives all leaves (display rate,
/// paused while the route is covered or the app is backgrounded); with
/// reduced motion it paints one still scatter. Leaves are stamped from one
/// sprite atlas (tool/assets/make_lobby_art.py) as textured quads in a single
/// draw call (the back-side tint and fade are vertex colours, so no per-leaf
/// colour filter or layer); positions are pure functions of time and the
/// vertex buffers are reused, so nothing is allocated per leaf.
class FlowingLeaves extends StatefulWidget {
  const FlowingLeaves({super.key, this.count = 14, this.opacity = 1, this.scale = 1, this.speed = 1, this.seed = 11});

  /// Sprite atlas: [spriteCount] cells of [cellSize] per row; row 0 crisp,
  /// row 1 softened. Columns 0-3 green, 4 gold, 5 cream petal.
  static const String atlasAsset = 'assets/lobby/leaf_sprites.webp';
  static const int spriteCount = 6;
  static const double cellSize = 160;

  /// Leaves on screen at once.
  final int count;

  /// Overall opacity (keep low behind gameplay).
  final double opacity;

  /// Leaf size multiplier.
  final double scale;

  /// Motion speed multiplier.
  final double speed;
  final int seed;

  @override
  State<FlowingLeaves> createState() => _FlowingLeavesState();
}

class _FlowingLeavesState extends State<FlowingLeaves> with SingleTickerProviderStateMixin {
  late final AmbientClock _time = AmbientClock(this);
  late List<_Leaf> _leaves = _generate();
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    setState(() {
      _atlas?.dispose();
      _atlas = info.image;
    });
  });
  ui.Image? _atlas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _time.reduceMotion = MediaQuery.disableAnimationsOf(context);
    final stream = const AssetImage(FlowingLeaves.atlasAsset).resolve(createLocalImageConfiguration(context));
    if (stream.key != _stream?.key) {
      _stream?.removeListener(_listener);
      _stream = stream..addListener(_listener);
    }
  }

  @override
  void didUpdateWidget(FlowingLeaves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count || oldWidget.seed != widget.seed) _leaves = _generate();
  }

  List<_Leaf> _generate() {
    final random = math.Random(widget.seed);
    final leaves = [
      for (var i = 0; i < widget.count; i++)
        () {
          final depth = math.pow(random.nextDouble(), 0.8).toDouble();
          // Mostly green; now and then a gold leaf or a cream petal.
          final pick = random.nextDouble();
          final sprite = pick < 0.1 ? 4 : (pick < 0.18 ? 5 : random.nextInt(4));
          return _Leaf(
            depth: depth,
            sprite: sprite,
            x: random.nextDouble(),
            y: random.nextDouble(),
            size: (20 + 38 * depth) * (0.85 + random.nextDouble() * 0.3),
            fall: (0.010 + 0.018 * depth) * (0.8 + random.nextDouble() * 0.4),
            drift: (0.003 + 0.008 * depth) * (random.nextBool() ? 1 : 0.4),
            sway: 0.012 + 0.03 * depth,
            swaySpeed: 0.35 + random.nextDouble() * 0.35,
            tilt: random.nextDouble() * math.pi * 2,
            spin: (random.nextDouble() - 0.5) * 0.25,
            flipSpeed: 0.35 + random.nextDouble() * 0.5,
            phase: random.nextDouble() * math.pi * 2,
          );
        }(),
    ]..sort((a, b) => a.depth.compareTo(b.depth));
    return leaves;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _atlas?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas;
    if (atlas == null) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LeafPainter(
          leaves: _leaves,
          time: _time,
          atlas: atlas,
          opacity: widget.opacity,
          scale: widget.scale,
          speed: widget.speed,
        ),
      ),
    );
  }
}

class _Leaf {
  const _Leaf({
    required this.depth,
    required this.sprite,
    required this.x,
    required this.y,
    required this.size,
    required this.fall,
    required this.drift,
    required this.sway,
    required this.swaySpeed,
    required this.tilt,
    required this.spin,
    required this.flipSpeed,
    required this.phase,
  });

  /// 0 = far (small, soft, slow), 1 = near.
  final double depth;
  final int sprite;

  /// Start position as a fraction of the area.
  final double x;
  final double y;

  /// Length in logical pixels.
  final double size;

  /// Fall and sideways drift, in areas per second.
  final double fall;
  final double drift;

  /// Sway amplitude (fraction of width) and angular speed (rad/s).
  final double sway;
  final double swaySpeed;
  final double tilt;
  final double spin;
  final double flipSpeed;
  final double phase;
}

class _LeafPainter extends CustomPainter {
  _LeafPainter({
    required this.leaves,
    required this.time,
    required this.atlas,
    required this.opacity,
    required this.scale,
    required this.speed,
  }) : _shader = ImageShader(atlas, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage),
       _positions = Float32List(leaves.length * 8),
       _uvs = Float32List(leaves.length * 8),
       _colors = Int32List(leaves.length * 4),
       _indices = Uint16List.fromList([
         for (var i = 0; i < leaves.length; i++) ...[i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3],
       ]),
       super(repaint: time);

  final List<_Leaf> leaves;
  final ValueListenable<double> time;
  final ui.Image atlas;
  final double opacity;
  final double scale;
  final double speed;
  final ImageShader _shader;

  // Reused every frame: one textured quad per leaf, all drawn in one call.
  final Float32List _positions;
  final Float32List _uvs;
  final Int32List _colors;
  final Uint16List _indices;

  /// The back of a leaf is a little darker (multiplies the sprite's RGB).
  static const _backR = 0.72, _backG = 0.78, _backB = 0.74;

  @override
  void paint(Canvas canvas, Size area) {
    if (area.isEmpty || leaves.isEmpty) return;
    final t = time.value * speed;
    const cell = FlowingLeaves.cellSize;
    for (var i = 0; i < leaves.length; i++) {
      final leaf = leaves[i];
      final size = leaf.size * scale;
      // Wrap around the area with a margin so leaves enter and leave
      // off-screen.
      final mx = size / area.width, my = size / area.height;
      final y = _wrap(leaf.y + t * leaf.fall, my) * area.height;
      final sway = math.sin(t * leaf.swaySpeed + leaf.phase) * leaf.sway;
      final x = (_wrap(leaf.x + t * leaf.drift, mx) + sway) * area.width;
      final angle = leaf.tilt + t * leaf.spin + math.sin(t * leaf.swaySpeed + leaf.phase + 0.8) * 0.55;
      // A slow 3D turn: never fully edge-on, darker when the back shows.
      final turn = math.cos(t * leaf.flipSpeed + leaf.phase * 1.7);
      final flip = (0.35 + 0.65 * turn.abs()) * (turn.isNegative ? -1 : 1);
      final alpha = (opacity * (0.5 + 0.5 * leaf.depth) * (0.75 + 0.25 * flip.abs())).clamp(0.0, 1.0);
      final soft = leaf.depth < 0.45;
      final half = size / 0.7 / 2; // the leaf spans 70% of its cell
      // Corners (-h,-h), (h,-h), (h,h), (-h,h), squashed by the turn, then
      // rotated and moved into place.
      final cos = math.cos(angle), sin = math.sin(angle);
      final ax = half * flip * cos, ay = half * flip * sin; // local +x
      final bx = -half * sin, by = half * cos; // local +y
      final p = i * 8;
      _positions
        ..[p] = x - ax - bx
        ..[p + 1] = y - ay - by
        ..[p + 2] = x + ax - bx
        ..[p + 3] = y + ay - by
        ..[p + 4] = x + ax + bx
        ..[p + 5] = y + ay + by
        ..[p + 6] = x - ax + bx
        ..[p + 7] = y - ay + by;
      final u0 = leaf.sprite * cell, v0 = soft ? cell : 0.0;
      _uvs
        ..[p] = u0
        ..[p + 1] = v0
        ..[p + 2] = u0 + cell
        ..[p + 3] = v0
        ..[p + 4] = u0 + cell
        ..[p + 5] = v0 + cell
        ..[p + 6] = u0
        ..[p + 7] = v0 + cell;
      final back = flip < 0;
      final color = Color.from(
        alpha: alpha,
        red: back ? _backR : 1,
        green: back ? _backG : 1,
        blue: back ? _backB : 1,
      ).toARGB32();
      final c = i * 4;
      _colors
        ..[c] = color
        ..[c + 1] = color
        ..[c + 2] = color
        ..[c + 3] = color;
    }
    final vertices = ui.Vertices.raw(
      VertexMode.triangles,
      _positions,
      textureCoordinates: _uvs,
      colors: _colors,
      indices: _indices,
    );
    // Sprite (paint) x vertex colour: tints the back and fades each leaf.
    canvas.drawVertices(
      vertices,
      BlendMode.modulate,
      Paint()
        ..shader = _shader
        ..filterQuality = FilterQuality.low,
    );
    vertices.dispose();
  }

  /// [v] wrapped into [-margin, 1 + margin).
  static double _wrap(double v, double margin) {
    final span = 1 + margin * 2;
    return (v + margin) % span - margin;
  }

  @override
  bool shouldRepaint(_LeafPainter old) =>
      old.leaves != leaves || old.atlas != atlas || old.opacity != opacity || old.scale != scale || old.speed != speed;
}

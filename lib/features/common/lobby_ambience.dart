import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'ambient_clock.dart';

/// Home's quiet extras over the night garden (premium mockup, 2026-10-23): the
/// lantern glows breathe a little ([LobbyTheme.lanternFlicker]) and a few
/// glowing butterflies ([LobbyTheme.butterflyCount]) drift around the hero
/// tiles and the title, clear of the buttons.
///
/// Cheap by design: one [AmbientClock] (like the fireflies: paused while the
/// route is covered or the app is in the background, a still frame with
/// reduced motion), glows stamped from one pre-rendered sprite with a single
/// `drawAtlas`, and each butterfly a few small paths. No blur, no layers.
/// [lanterns] are the lantern boxes in this widget's coordinates with their
/// glows.
class LobbyAmbience extends StatefulWidget {
  const LobbyAmbience({super.key, required this.lanterns, this.seed = 11});

  final List<(LobbyGlow, Rect)> lanterns;
  final int seed;

  @override
  State<LobbyAmbience> createState() => _LobbyAmbienceState();
}

class _LobbyAmbienceState extends State<LobbyAmbience> with SingleTickerProviderStateMixin {
  static ui.Image? _sprite;

  late final AmbientClock _time = AmbientClock(this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _time.reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  /// A soft white disc: bright core, long falloff (tinted per stamp).
  static ui.Image _glowSprite() {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      size / 2,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.35, 1],
        ).createShader(Rect.fromCircle(center: center, radius: size / 2)),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.toInt(), size.toInt());
    picture.dispose();
    return image;
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return CustomPaint(
      painter: _AmbiencePainter(
        time: _time,
        sprite: _sprite ??= _glowSprite(),
        lanterns: widget.lanterns,
        flicker: lobby.lanternFlicker,
        butterflies: _Butterfly.generate(lobby.butterflyCount, widget.seed),
        color: lobby.butterflyColor,
      ),
      size: Size.infinite,
    );
  }
}

/// One butterfly's flight: a slow figure over its home area (fractions of the
/// screen), wings beating in bursts with short glides.
@immutable
class _Butterfly {
  const _Butterfly({
    required this.x,
    required this.y,
    required this.rangeX,
    required this.rangeY,
    required this.speed,
    required this.phase,
    required this.size,
  });

  final double x;
  final double y;
  final double rangeX;
  final double rangeY;
  final double speed;
  final double phase;

  /// Wingspan as a fraction of the screen width.
  final double size;

  /// Home spots (fractions of the screen), clear of the hero tiles, the
  /// title, the buttons' labels, the lanterns and the round Play Games
  /// buttons: above the left tile, and low on the left beside the Play
  /// button's leaf (premium mockup), then right of the Settings button.
  static const List<Offset> _homes = [Offset(0.24, 0.15), Offset(0.08, 0.6), Offset(0.92, 0.7)];

  static List<_Butterfly> generate(int count, int seed) {
    final random = math.Random(seed);
    return [
      for (var i = 0; i < count; i++)
        _Butterfly(
          x: _homes[i % _homes.length].dx,
          y: _homes[i % _homes.length].dy,
          rangeX: 0.035 + random.nextDouble() * 0.02,
          rangeY: 0.03 + random.nextDouble() * 0.02,
          speed: 0.22 + random.nextDouble() * 0.1,
          phase: random.nextDouble() * math.pi * 2,
          size: 0.08 + random.nextDouble() * 0.015,
        ),
    ];
  }

  /// Position at time [t], as a fraction of the area.
  Offset at(double t) {
    final a = t * speed + phase;
    return Offset(
      x + math.sin(a) * rangeX + math.sin(a * 2.3 + 1.1) * rangeX * 0.25,
      y + math.sin(a * 1.7 + 0.6) * rangeY + math.cos(a * 3.1) * rangeY * 0.2,
    );
  }

  /// How open the wings are, 0.15 (folded up, seen edge-on) to 1 (flat).
  double wings(double t) {
    // Bursts of beating (~5 Hz), then a short glide with the wings open.
    final burst = (math.sin(t * 0.9 + phase * 3) + 1) / 2;
    final beat = (math.cos(t * math.pi * 2 * 5 + phase) + 1) / 2;
    return burst > 0.35 ? 0.15 + 0.85 * beat : 0.92;
  }
}

class _AmbiencePainter extends CustomPainter {
  _AmbiencePainter({
    required this.time,
    required this.sprite,
    required this.lanterns,
    required this.flicker,
    required this.butterflies,
    required this.color,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final ui.Image sprite;
  final List<(LobbyGlow, Rect)> lanterns;
  final double flicker;
  final List<_Butterfly> butterflies;
  final Color color;

  @override
  void paint(Canvas canvas, Size area) {
    final t = time.value;
    final spriteSize = sprite.width.toDouble();
    final src = Rect.fromLTWH(0, 0, spriteSize, spriteSize);
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    void stamp(Offset center, double radius, Color tint) {
      transforms.add(
        RSTransform.fromComponents(
          rotation: 0,
          scale: radius * 2 / spriteSize,
          anchorX: spriteSize / 2,
          anchorY: spriteSize / 2,
          translateX: center.dx,
          translateY: center.dy,
        ),
      );
      rects.add(src);
      colors.add(tint);
    }

    // Lanterns: a flame-like breathing on top of the scene's still glow.
    if (flicker > 0) {
      for (final (i, (glow, box)) in lanterns.indexed) {
        final n = 0.55 * math.sin(t * 2.3 + i * 1.7) + 0.3 * math.sin(t * 5.9 + i * 0.9) + 0.15 * math.sin(t * 11.3 + i);
        final level = ((n + 1) / 2).clamp(0.0, 1.0);
        final center = glow.center.withinRect(box);
        stamp(center, box.width * 0.9, glow.color.withValues(alpha: flicker * (0.35 + 0.65 * level)));
      }
    }
    final positions = [for (final b in butterflies) b.at(t).scale(area.width, area.height)];
    for (final (i, b) in butterflies.indexed) {
      stamp(positions[i], b.size * area.width * 1.4, color.withValues(alpha: 0.28));
    }
    if (transforms.isNotEmpty) {
      canvas.drawAtlas(sprite, transforms, rects, colors, BlendMode.modulate, null, Paint()..blendMode = BlendMode.plus);
    }
    for (final (i, b) in butterflies.indexed) {
      // Heading: along the flight (a moment later), head first.
      final ahead = b.at(t + 0.15).scale(area.width, area.height) - positions[i];
      final heading = ahead.distanceSquared < 1e-6 ? 0.0 : math.atan2(ahead.dy, ahead.dx) + math.pi / 2;
      _drawButterfly(canvas, positions[i], b.size * area.width, heading, b.wings(t));
    }
  }

  void _drawButterfly(Canvas canvas, Offset center, double span, double heading, double open) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(heading);
    final half = span / 2;
    final wing = Paint()
      ..shader = ui.Gradient.radial(Offset.zero, half, [
        Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!,
        color,
        Color.lerp(color, const Color(0xFFB07A2A), 0.5)!.withValues(alpha: 0.9),
      ], const [0, 0.55, 1]);
    for (final side in const [-1.0, 1.0]) {
      canvas.save();
      canvas.scale(side * open, 1);
      // Upper wing (forward) and the smaller lower wing.
      final upper = Path()
        ..moveTo(0, -half * 0.08)
        ..cubicTo(half * 0.35, -half * 0.95, half * 1.05, -half * 0.85, half * 0.92, -half * 0.25)
        ..cubicTo(half * 0.85, half * 0.02, half * 0.35, half * 0.06, 0, half * 0.04)
        ..close();
      final lower = Path()
        ..moveTo(0, half * 0.04)
        ..cubicTo(half * 0.45, half * 0.05, half * 0.78, half * 0.32, half * 0.6, half * 0.62)
        ..cubicTo(half * 0.45, half * 0.85, half * 0.12, half * 0.55, 0, half * 0.22)
        ..close();
      canvas.drawPath(upper, wing);
      canvas.drawPath(lower, wing);
      canvas.restore();
    }
    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, half * 0.08), width: span * 0.07, height: span * 0.5),
        Radius.circular(span * 0.04),
      ),
      Paint()..color = Color.lerp(color, const Color(0xFF3E2410), 0.6)!,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AmbiencePainter old) =>
      old.sprite != sprite ||
      old.flicker != flicker ||
      old.color != color ||
      !listEquals(old.lanterns, lanterns) ||
      old.butterflies.length != butterflies.length;
}

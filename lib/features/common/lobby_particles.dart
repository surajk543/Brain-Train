import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ambient_clock.dart';

/// Fireflies: softly glowing, blinking particles drifting over the lobby.
///
/// One [AmbientClock] drives every particle and repaints at most ~30 times
/// a second; it pauses while the route is covered or the app is in the
/// background, and with reduced motion the particles are still.
/// All particles are stamped from one pre-rendered glow sprite with a
/// single `drawAtlas` call.
class LobbyParticles extends StatefulWidget {
  const LobbyParticles({super.key, required this.count, required this.color, this.size = 2, this.seed = 7});

  final int count;
  final Color color;

  /// Core radius of an average particle, in logical pixels.
  final double size;
  final int seed;

  @override
  State<LobbyParticles> createState() => _LobbyParticlesState();
}

class _LobbyParticlesState extends State<LobbyParticles> with SingleTickerProviderStateMixin {
  static ui.Image? _sprite;

  late final AmbientClock _time = AmbientClock(this);
  late List<_Particle> _particles = _generate();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _time.reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(LobbyParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count || oldWidget.seed != widget.seed) _particles = _generate();
  }

  List<_Particle> _generate() {
    final random = math.Random(widget.seed);
    return [
      for (var i = 0; i < widget.count; i++)
        () {
          // Denser toward the sides, away from the title and buttons.
          final side = random.nextBool() ? 1 : -1;
          final x = 0.5 + side * 0.5 * math.pow(random.nextDouble(), 0.55);
          return _Particle(
            x: x.clamp(0.02, 0.98).toDouble(),
            y: 0.08 + random.nextDouble() * 0.86,
            radius: 0.65 + random.nextDouble() * 0.75,
            driftX: 0.012 + random.nextDouble() * 0.03,
            driftY: 0.01 + random.nextDouble() * 0.025,
            speed: 0.12 + random.nextDouble() * 0.22,
            blink: 0.35 + random.nextDouble() * 0.7,
            phase: random.nextDouble() * math.pi * 2,
          );
        }(),
    ];
  }

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
          colors: [Color(0xFFFFFFFF), Color(0xD9FFFFFF), Color(0x4DFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.1, 0.32, 1],
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
  Widget build(BuildContext context) => CustomPaint(
    painter: _ParticlePainter(
      particles: _particles,
      time: _time,
      sprite: _sprite ??= _glowSprite(),
      color: widget.color,
      size: widget.size,
    ),
    size: Size.infinite,
  );
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.driftX,
    required this.driftY,
    required this.speed,
    required this.blink,
    required this.phase,
  });

  /// Rest position as a fraction of the area.
  final double x;
  final double y;
  final double radius;

  /// Wander amplitude as a fraction of the area.
  final double driftX;
  final double driftY;
  final double speed;
  final double blink;
  final double phase;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.particles,
    required this.time,
    required this.sprite,
    required this.color,
    required this.size,
  }) : super(repaint: time);

  final List<_Particle> particles;
  final ValueListenable<double> time;
  final ui.Image sprite;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final t = time.value;
    final spriteSize = sprite.width.toDouble();
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    final src = Rect.fromLTWH(0, 0, spriteSize, spriteSize);
    for (final p in particles) {
      final a = t * p.speed + p.phase;
      final x = (p.x + math.sin(a) * p.driftX + math.sin(a * 0.37 + 1.3) * p.driftX * 0.6) * area.width;
      final y = (p.y + math.cos(a * 0.83) * p.driftY - math.sin(a * 0.21) * p.driftY) * area.height;
      final pulse = math.pow((math.sin(t * p.blink + p.phase * 2) + 1) / 2, 2).toDouble();
      final alpha = 0.18 + 0.82 * pulse;
      // The sprite's bright core is ~1/8 of its width.
      final scale = size * p.radius * 8 * (0.85 + 0.25 * pulse) / spriteSize;
      transforms.add(
        RSTransform.fromComponents(
          rotation: 0,
          scale: scale,
          anchorX: spriteSize / 2,
          anchorY: spriteSize / 2,
          translateX: x,
          translateY: y,
        ),
      );
      rects.add(src);
      colors.add(color.withValues(alpha: color.a * alpha));
    }
    canvas.drawAtlas(sprite, transforms, rects, colors, BlendMode.modulate, null, Paint()..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.particles != particles || old.color != color || old.size != size || old.sprite != sprite;
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The shadow (and optional warm glow) behind a glass shape, for
/// [CustomPaint.painter] inside a `StaticLayer`.
///
/// The shadow falls only outside the shape, so it never darkens the glass.
/// The glow is drawn inside the shape too (the frost covers that part) as a
/// radial light centred on it.
class GlassShadowPainter extends CustomPainter {
  const GlassShadowPainter({
    required this.radius,
    required this.color,
    this.glow,
    this.glowRadius = 0,
    this.blur,
    this.offsetY,
    this.glowBlur = 0,
  });

  /// Corner radius of the glass; larger than half the short side gives a
  /// stadium or circle.
  final double radius;
  final Color color;

  /// The warm light behind the glass, as seen through the frost.
  final Color? glow;
  final double glowRadius;

  /// Shadow blur sigma (default `radius * 0.6`) and drop (default
  /// `radius * 0.35`).
  final double? blur;
  final double? offsetY;

  /// Extra soft halo of [glow] around the shape (outside only); 0 for none.
  final double glowBlur;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(this.radius, size.shortestSide / 2);
    final panel = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect((Offset.zero & size).inflate(radius * 3 + glowBlur * 3)),
        Path()..addRRect(panel),
      ),
    );
    final glow = this.glow;
    if (glow != null && glowBlur > 0) {
      canvas.drawRRect(
        panel,
        Paint()
          ..color = glow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur),
      );
    }
    canvas.drawRRect(
      panel.shift(Offset(0, offsetY ?? radius * 0.35)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur ?? radius * 0.6),
    );
    canvas.restore();
    if (glow != null && glowRadius > 0) {
      canvas.drawRRect(
        panel,
        Paint()
          ..shader = RadialGradient(
            colors: [glow, glow.withValues(alpha: glow.a * 0.35), glow.withValues(alpha: 0)],
            stops: const [0, 0.42, 1],
          ).createShader(Rect.fromCircle(center: size.center(Offset.zero), radius: glowRadius)),
      );
    }
  }

  @override
  bool shouldRepaint(GlassShadowPainter old) =>
      old.radius != radius ||
      old.color != color ||
      old.glow != glow ||
      old.glowRadius != glowRadius ||
      old.blur != blur ||
      old.offsetY != offsetY ||
      old.glowBlur != glowBlur;
}

/// A fine gradient rim around a glass shape, for `CustomPaint.foregroundPainter`.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.colors, this.strokeWidth = 1.2});

  final double radius;
  final List<Color> colors;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2;
    final radius = math.min(this.radius, size.shortestSide / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(inset), Radius.circular(radius - inset)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.colors != colors || old.strokeWidth != strokeWidth;
}

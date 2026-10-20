import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../game_engine/models/level_definition.dart';

/// Palette used when a level does not define a backdrop.
const List<Color> kDefaultBackdrop = [Color(0xFF1E6B4E), Color(0xFF7FC8A9), Color(0xFFE9C46A)];

List<Color> backdropColors(LevelBackdrop? backdrop) {
  final colors = backdrop?.colors;
  if (colors == null || colors.length < 2) return kDefaultBackdrop;
  return [for (final hex in colors) Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000)];
}

/// A level's backdrop: deep base tone with large soft light orbs in the
/// level's palette, which the glass panels on top frost and refract.
///
/// Static: painted once and isolated in its own layer, so board animations
/// never repaint it.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.colors, required this.child});

  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(child: CustomPaint(painter: _OrbPainter(colors, BrainTrainPalette.of(context)))),
      child,
    ],
  );
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.colors, this.palette);

  final List<Color> colors;
  final BrainTrainPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Color.lerp(colors.first, palette.backdropBase, palette.backdropMix)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(base, colors.first, 0.18)!, base, Color.lerp(base, colors.last, 0.12)!],
        ).createShader(rect),
    );
    // Orbs: (colour index, centre as fraction of size, radius as fraction of
    // the shorter side, strength).
    final shortest = math.min(size.width, size.height);
    final orbs = <(int, Offset, double, double)>[
      (0, const Offset(0.12, 0.16), 0.75, 0.75),
      (1, const Offset(0.92, 0.38), 0.65, 0.6),
      (colors.length > 2 ? 2 : 0, const Offset(0.3, 0.86), 0.7, 0.55),
      (1, const Offset(0.78, 0.98), 0.45, 0.35),
    ];
    for (final (index, center, radius, strength) in orbs) {
      final c = Offset(center.dx * size.width, center.dy * size.height);
      final r = radius * shortest;
      final color = colors[index % colors.length];
      final alpha = strength * palette.orbStrength;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.colors != colors || old.palette != palette;
}

/// Frosted glass: blurs what is behind it, with a translucent tint, a light
/// edge and a top highlight. Use inside a [BackdropGroup] so panels on the
/// same screen share one backdrop read.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 22,
    this.blur = 18,
    this.tint = 0.10,
    this.shade = 0.0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  /// White tint strength (0-1).
  final double tint;

  /// Extra dark tint, for panels holding ivory tiles that need contrast.
  final double shade;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final borderRadius = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(Colors.black.withValues(alpha: shade), Colors.white.withValues(alpha: tint * 1.6)),
                Color.alphaBlend(Colors.black.withValues(alpha: shade), Colors.white.withValues(alpha: tint * 0.5)),
              ],
            ),
            border: Border.all(color: palette.glassBorder, width: 1),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: Stack(
            children: [
              // Light catching the top edge of the glass.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 1.2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped glass button for game actions.
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = BrainTrainPalette.of(context).text;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GlassPanel(
        radius: 18,
        tint: 0.14,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

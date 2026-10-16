import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/brand.dart';
import '../../../app/theme.dart';
import '../../common/flowing_leaves.dart';
import '../../common/frosted_glass.dart';
import '../../common/static_layer.dart';

/// Darkest felt tone, at the screen edges (also the Scaffold colour).
const Color kFeltEdge = Color(0xFF062618);

/// Gameplay background: deep emerald felt, warm ambient light tinted by the
/// level's palette, and botanical decoration at the edges.
///
/// The felt and foliage are flattened into one image by a [StaticLayer]
/// (re-rendered only when an image arrives or the size changes), so board
/// and leaf animation frames draw one image for it. That image, blurred
/// once, is the [FrostSource] for the HUD and result cards in [child].
///
/// A few faint leaves drift above the felt and below the board (their own
/// layer; see [FlowingLeaves]), kept sparse so the tiles stay readable.
class EmeraldBackdrop extends StatefulWidget {
  const EmeraldBackdrop({super.key, required this.accent, required this.child});

  /// The level's palette colour, used only to tint the ambient light.
  final Color accent;
  final Widget child;

  @override
  State<EmeraldBackdrop> createState() => _EmeraldBackdropState();
}

class _EmeraldBackdropState extends State<EmeraldBackdrop> {
  final FrostSource _frost = FrostSource(sigma: PremiumPanel.defaultBlur);

  @override
  void dispose() {
    _frost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decoration scales with the shorter side so tablets and landscape do
    // not get giant leaves.
    final unit = math.min(size.width, size.height * 0.5);
    // Offsets are in units of [unit], except [topOfHeight] (screen height).
    Widget decor(
      String name,
      double widthFraction, {
      double? left,
      double? right,
      double? top,
      double? topOfHeight,
      double? bottom,
    }) {
      final width = unit * widthFraction;
      return Positioned(
        left: left == null ? null : unit * left,
        right: right == null ? null : unit * right,
        top: top != null ? unit * top : (topOfHeight == null ? null : size.height * topOfHeight),
        bottom: bottom == null ? null : unit * bottom,
        width: width,
        child: IgnorePointer(
          child: Image.asset(
            'assets/decor/$name.webp',
            cacheWidth: (width * dpr).round(),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        StaticLayer(
          onRaster: _frost.update,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _FeltPainter(accent: widget.accent)),
              decor('foliage_right', 0.3, right: -0.06, topOfHeight: 0.19),
              decor('foliage_top_left', 0.7, left: -0.08, top: -0.07),
              decor('foliage_bottom_left', 0.7, left: -0.1, bottom: -0.08),
              decor('foliage_bottom_right', 0.72, right: -0.1, bottom: -0.09),
            ],
          ),
        ),
        const RepaintBoundary(child: FlowingLeaves(count: 8, opacity: 0.62, scale: 0.9, speed: 0.85, seed: 23)),
        FrostScope(source: _frost, child: widget.child),
      ],
    );
  }
}

class _FeltPainter extends CustomPainter {
  _FeltPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const center = Color(0xFF1B6B45);
    const mid = Color(0xFF0E4A2F);
    const edge = kFeltEdge;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 0.9,
          colors: const [center, mid, edge],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCenter(center: rect.center, width: size.shortestSide * 1.6, height: size.longestSide))
        ..isAntiAlias = false,
    );
    // Velvet texture: fine diagonal nap, drawn once (static layer).
    final nap = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.018);
    for (var x = -size.height; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), nap);
    }
    // Warm cinematic light from the top-right, tinted by the level palette.
    final light = Color.lerp(const Color(0xFFFFD98A), accent, 0.25)!;
    final glow = Rect.fromCircle(
      center: Offset(size.width * 0.92, size.height * 0.02),
      radius: size.longestSide * 0.62,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [light.withValues(alpha: 0.4), light.withValues(alpha: 0.11), light.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(glow),
    );
    // Vignette, so the edges fall off into deep green.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.85,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.34)],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCenter(center: rect.center, width: size.width * 1.15, height: size.height * 1.05)),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.accent != accent;
}

/// Dark translucent green panel with a fine gold border and top highlight,
/// shared by the HUD and result cards.
///
/// Frosted with [FrostedGlass]: the blurred backdrop comes from the nearest
/// [FrostScope] ([EmeraldBackdrop] provides one), so nothing is read back
/// or blurred per frame.
class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.frostTint,
  });

  /// Frost blur radius (sigma) of the backdrop copy behind these panels.
  static const double defaultBlur = 14;

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// See [FrostedGlass.tint].
  final Color? frostTint;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: FrostedGlass(
        borderRadius: borderRadius,
        tint: frostTint,
        child: CustomPaint(
          foregroundPainter: _GoldBorderPainter(radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xD11A5638), Color(0xE00A3322)],
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _GoldBorderPainter extends CustomPainter {
  _GoldBorderPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(bounds.deflate(0.75), Radius.circular(radius));
    canvas
      // Soft inner sheen along the top, like light on lacquer.
      ..drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)],
            stops: const [0, 0.5],
          ).createShader(bounds),
      )
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
      // Fine inner highlight along the top edge.
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
  bool shouldRepaint(_GoldBorderPainter old) => old.radius != radius;
}

/// The HUD's panel with small gold sprigs touching its corners.
///
/// The HUD is a bottom bar, so the sprigs are mirrored top-to-bottom: the
/// larger one hugs the bottom-left corner, the smaller one the top-right.
class PremiumHudFrame extends StatelessWidget {
  const PremiumHudFrame({super.key, required this.child, this.radius = 28});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      PremiumPanel(radius: radius, child: child),
      Positioned(left: -9, bottom: -9, child: Transform.flip(flipY: true, child: const GoldSprig(size: 58))),
      Positioned(right: -9, top: -9, child: Transform.flip(flipY: true, child: const GoldSprig(size: 50, turns: 2))),
    ],
  );
}

/// A small gold vine sprig that curls around a corner. Purely decorative.
class GoldSprig extends StatelessWidget {
  const GoldSprig({super.key, this.size = 56, this.turns = 0});

  final double size;

  /// Quarter turns clockwise; 0 hugs a top-left corner.
  final int turns;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RotatedBox(
      quarterTurns: turns,
      // A dozen blurred shadows: rendered once, not on every frame.
      child: StaticLayer(
        overflow: const EdgeInsets.all(4),
        child: CustomPaint(size: Size.square(size), painter: const _SprigPainter()),
      ),
    ),
  );
}

class _SprigPainter extends CustomPainter {
  const _SprigPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.scale(s);
    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [BrandGold.light, BrandGold.base, BrandGold.deep],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    final shadow = Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    // Stem hugging the corner: from down the left side, round, along the top.
    final stem = Path()
      ..moveTo(12, 96)
      ..cubicTo(6, 60, 8, 22, 26, 13)
      ..cubicTo(42, 5, 70, 8, 98, 12);
    final curl = Path()
      ..moveTo(26, 13)
      ..cubicTo(30, 26, 22, 34, 16, 28)
      ..cubicTo(11, 23, 18, 18, 21, 23);
    final stemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..shader = gold.shader;
    canvas
      ..save()
      ..translate(0.8, 1.6)
      ..drawPath(
        stem,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = const Color(0x55000000),
      )
      ..restore()
      ..drawPath(stem, stemPaint)
      ..drawPath(curl, stemPaint..strokeWidth = 1.4);

    // Leaves: (x, y, angle in degrees, length).
    const leaves = [
      (13.0, 70.0, 200.0, 17.0),
      (10.0, 50.0, -20.0, 16.0),
      (14.0, 30.0, 230.0, 14.0),
      (44.0, 8.0, -70.0, 15.0),
      (62.0, 9.0, 60.0, 15.0),
      (80.0, 11.0, -60.0, 12.0),
    ];
    for (final (x, y, angle, length) in leaves) {
      final leaf = _leaf(length);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(angle * math.pi / 180);
      canvas
        ..save()
        ..translate(0.6, 1.4)
        ..drawPath(leaf, shadow)
        ..restore()
        ..drawPath(leaf, gold)
        ..drawLine(
          Offset.zero,
          Offset(length * 0.8, 0),
          Paint()
            ..strokeWidth = 0.7
            ..color = const Color(0x998E6C2A),
        )
        ..restore();
    }
    // Tiny berries.
    for (final (x, y) in const [(31.0, 20.0), (72.0, 5.0)]) {
      canvas.drawCircle(Offset(x, y), 2.2, gold);
    }
  }

  static Path _leaf(double length) {
    final w = length * 0.42;
    return Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.45, -w, length, 0)
      ..quadraticBezierTo(length * 0.45, w, 0, 0)
      ..close();
  }

  @override
  bool shouldRepaint(_SprigPainter old) => false;
}

/// Circular outlined back button.
class PremiumBackButton extends StatelessWidget {
  const PremiumBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Back',
    excludeSemantics: true,
    onTap: onPressed,
    child: Tooltip(
      message: 'Back',
      excludeFromSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: BrainTrainColors.ivory.withValues(alpha: 0.7), width: 1.3),
              gradient: RadialGradient(
                colors: [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.02)],
              ),
            ),
            child: const Icon(Icons.chevron_left_rounded, color: BrainTrainColors.ivory, size: 32),
          ),
        ),
      ),
    ),
  );
}

/// Serif text button in three weights: gold-filled [primary], gold-outlined
/// (default) and borderless [quiet].
class PremiumButton extends StatelessWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.quiet = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool quiet;

  /// Fills the available width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(26);
    final textColor = primary ? BrainTrainColors.ink : (quiet ? BrandGold.light : BrainTrainColors.ivory);
    final decoration = primary
        ? BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [BrandGold.light, BrandGold.warm, BrandGold.base],
            ),
            border: Border.all(color: const Color(0xFFFFF1C4), width: 0.8),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
          )
        : quiet
        ? BoxDecoration(borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: BrandGold.base.withValues(alpha: 0.85), width: 1.1),
          );
    return Semantics(
      button: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: quiet ? 44 : 50, minWidth: expand ? double.infinity : 108),
        child: DecoratedBox(
          decoration: decoration,
          child: Material(
            type: MaterialType.transparency,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              splashColor: (primary ? BrainTrainColors.ink : BrandGold.base).withValues(alpha: 0.16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: displayText(quiet ? 17 : 19, color: textColor, weight: FontWeight.w600, spacing: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round gold-ringed medallion with an icon, for result cards.
class PremiumEmblem extends StatelessWidget {
  const PremiumEmblem({super.key, required this.icon, this.size = 72});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [BrandGold.warm.withValues(alpha: 0.32), BrandGold.warm.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: BrandGold.base, width: 1.4),
        boxShadow: [BoxShadow(color: BrandGold.warm.withValues(alpha: 0.25), blurRadius: 24)],
      ),
      child: Icon(icon, color: BrandGold.light, size: size * 0.5),
    ),
  );
}

/// A small caps label over a large tabular value, for HUD statistics.
class PremiumStat extends StatelessWidget {
  const PremiumStat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: displayText(
              10.5,
              color: BrainTrainColors.ivory.withValues(alpha: 0.78),
              weight: FontWeight.w500,
              spacing: 1.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(value, style: displayText(22, weight: FontWeight.w500)),
        ],
      ),
    ),
  );
}

/// Thin gold divider: vertical between HUD statistics, or [horizontal].
class PremiumDivider extends StatelessWidget {
  const PremiumDivider({super.key, this.horizontal = false});

  final bool horizontal;

  @override
  Widget build(BuildContext context) => Container(
    width: horizontal ? double.infinity : 1,
    height: horizontal ? 1 : 38,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: [
          BrandGold.base.withValues(alpha: 0),
          BrandGold.base.withValues(alpha: 0.75),
          BrandGold.base.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

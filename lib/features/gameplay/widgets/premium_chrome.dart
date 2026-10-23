import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/brand.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../common/flowing_leaves.dart';
import '../../common/frosted_glass.dart';
import '../../common/lobby_background.dart';
import '../../common/static_layer.dart';

/// The darkest felt tone, at the screen edges (`BrainTrainPalette.feltEdge`).
const Color kFeltEdge = Color(0xFF062618);

/// Gameplay background: deep emerald felt, warm ambient light tinted by the
/// level's palette, botanical decoration at the edges, and (premium pass) a
/// faint cobblestone path under the action bar and two small glowing lanterns
/// at the edges, where the board seldom reaches: beside the tray on the left,
/// low on the right.
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
    final palette = BrainTrainPalette.of(context);
    final foliage = palette.feltFoliage;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decoration scales with the shorter side so tablets and landscape do
    // not get giant leaves.
    final unit = math.min(size.width, size.height * 0.5);
    // Offsets are in units of [unit], except [topOfHeight] (screen height).
    Widget decor(
      String asset,
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
            asset,
            cacheWidth: (width * dpr).round(),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      );
    }

    Widget lantern(Rect box, {bool flipX = false}) => Positioned.fromRect(
      rect: box,
      child: IgnorePointer(
        child: Transform.flip(
          flipX: flipX,
          child: Image.asset(
            foliage.lantern,
            fit: BoxFit.fill,
            cacheWidth: (box.width * dpr).round(),
            excludeFromSemantics: true,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    // The two lanterns' boxes (for their glows): image aspect 820 / 360.
    const lanternAspect = 820 / 360;
    final leftLantern = Rect.fromLTWH(-unit * 0.04, size.height * 0.12, unit * 0.15, unit * 0.15 * lanternAspect);
    final rightLantern = Rect.fromLTWH(
      size.width - unit * 0.13,
      size.height * 0.86 - unit * 0.16 * lanternAspect,
      unit * 0.16,
      unit * 0.16 * lanternAspect,
    );

    // Light status bar icons over the felt.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kStatusBarLightIcons,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StaticLayer(
            onRaster: _frost.update,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _FeltPainter(accent: widget.accent, palette: palette)),
                Positioned(
                  left: -size.width * 0.02,
                  right: -size.width * 0.02,
                  bottom: -size.width * 0.12,
                  child: IgnorePointer(
                    // Faint: the image's own paint alpha, not an Opacity layer.
                    child: Image.asset(
                      foliage.path,
                      fit: BoxFit.fitWidth,
                      opacity: const AlwaysStoppedAnimation(0.5),
                      cacheWidth: (size.width * 1.04 * dpr).round(),
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                decor(foliage.right, 0.3, right: -0.06, topOfHeight: 0.19),
                decor(foliage.topLeft, 0.7, left: -0.08, top: -0.07),
                decor(foliage.bottomLeft, 0.7, left: -0.1, bottom: -0.08),
                decor(foliage.bottomRight, 0.72, right: -0.1, bottom: -0.09),
                // The lanterns hang in front of the leaves, lighting them.
                CustomPaint(
                  painter: _LanternGlowPainter(color: foliage.lanternGlow, lanterns: [leftLantern, rightLantern]),
                ),
                lantern(leftLantern, flipX: true),
                lantern(rightLantern),
              ],
            ),
          ),
          const RepaintBoundary(child: FlowingLeaves(count: 8, opacity: 0.62, scale: 0.9, speed: 0.85, seed: 23)),
          FrostScope(source: _frost, child: widget.child),
        ],
      ),
    );
  }
}

/// Warm light around the backdrop's lanterns (screen blend, drawn once in the
/// static layer).
class _LanternGlowPainter extends CustomPainter {
  _LanternGlowPainter({required this.color, required this.lanterns});

  final Color color;
  final List<Rect> lanterns;

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in lanterns) {
      // The flame sits a little below the lantern's middle.
      final center = Offset(box.center.dx, box.top + box.height * 0.62);
      final radius = box.width * 1.7;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: color.a * 0.4), color.withValues(alpha: 0)],
            stops: const [0, 0.4, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_LanternGlowPainter old) => old.color != color || old.lanterns.length != lanterns.length ||
      [for (var i = 0; i < lanterns.length; i++) old.lanterns[i] != lanterns[i]].any((changed) => changed);
}

class _FeltPainter extends CustomPainter {
  _FeltPainter({required this.accent, required this.palette});

  final Color accent;

  /// Felt colours, light and vignette.
  final BrainTrainPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 0.9,
          colors: [palette.feltCenter, palette.feltMid, palette.feltEdge],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCenter(center: rect.center, width: size.shortestSide * 1.6, height: size.longestSide))
        ..isAntiAlias = false,
    );
    // Velvet texture: fine diagonal nap, drawn once (static layer).
    final nap = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: palette.feltNap);
    for (var x = -size.height; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), nap);
    }
    // Warm cinematic light from the top-right, tinted by the level palette.
    final light = Color.lerp(palette.feltGlow, accent, 0.25)!;
    final strength = palette.feltGlowStrength;
    final glow = Rect.fromCircle(
      center: Offset(size.width * 0.92, size.height * 0.02),
      radius: size.longestSide * 0.62,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            light.withValues(alpha: strength),
            light.withValues(alpha: strength * 0.275),
            light.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(glow),
    );
    // Vignette, so the edges fall off into deep green.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.85,
          colors: [Colors.transparent, Colors.black.withValues(alpha: palette.feltVignette)],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCenter(center: rect.center, width: size.width * 1.15, height: size.height * 1.05)),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.accent != accent || old.palette != palette;
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
    final palette = BrainTrainPalette.of(context);
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: palette.panelShadows),
      child: FrostedGlass(
        borderRadius: borderRadius,
        tint: frostTint,
        child: CustomPaint(
          foregroundPainter: _GoldBorderPainter(radius, palette),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: palette.panelFill,
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
  _GoldBorderPainter(this.radius, this.palette);

  final double radius;

  /// Rim gold, sheen and highlight of the current look.
  final BrainTrainPalette palette;

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
            colors: [palette.panelSheen, palette.panelSheen.withValues(alpha: 0)],
            stops: const [0, 0.5],
          ).createShader(bounds),
      )
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette.panelRim,
            stops: _rimStops(palette.panelRim.length),
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
            colors: [palette.panelHighlight, palette.panelHighlight.withValues(alpha: 0)],
            stops: const [0, 0.35],
          ).createShader(bounds),
      );
  }

  /// The rim's gold bands: light, base, deep, base, light at the stops the
  /// rim was designed with; other lengths spread evenly.
  static List<double>? _rimStops(int length) => length == 5 ? const [0, 0.3, 0.55, 0.8, 1] : null;

  @override
  bool shouldRepaint(_GoldBorderPainter old) => old.radius != radius || old.palette != palette;
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

/// Text button (Manrope Bold, redesign 1.1.0) in three weights: gold-filled
/// [primary], gold-outlined (default) and borderless [quiet]. [onPressed]
/// null = disabled (dimmer colours rather than an Opacity layer, not
/// tappable).
class PremiumButton extends StatelessWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.quiet = false,
    this.expand = false,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool quiet;

  /// Fills the available width.
  final bool expand;

  /// Shown before the label.
  final IconData? icon;

  /// Shown at the right end (e.g. a chevron), the label staying centred.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final palette = BrainTrainPalette.of(context);
    final radius = BorderRadius.circular(26);
    final ink = primary
        ? palette.primaryButtonText
        : (quiet ? palette.quietButtonText : palette.secondaryButtonText);
    final textColor = enabled ? ink : ink.withValues(alpha: primary ? 0.55 : 0.45);
    final border = palette.secondaryButtonBorder;
    final decoration = primary
        ? BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                for (final color in palette.primaryButtonFill)
                  enabled ? color : color.withValues(alpha: color.a * 0.38),
              ],
            ),
            border: Border.all(
              color: palette.primaryButtonEdge.withValues(alpha: palette.primaryButtonEdge.a * (enabled ? 1 : 0.4)),
              width: 0.8,
            ),
            boxShadow: enabled
                ? [BoxShadow(color: palette.primaryButtonShadow, blurRadius: 10, offset: const Offset(0, 4))]
                : null,
          )
        : quiet
        ? BoxDecoration(borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            color: palette.secondaryButtonFill,
            border: Border.all(color: border.withValues(alpha: border.a * (enabled ? 0.85 : 0.35)), width: 1.1),
          );
    final fontSize = quiet ? 16.0 : 17.0;
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: BrainTrainType.button(size: fontSize, color: textColor).copyWith(
        fontWeight: quiet ? FontWeight.w600 : FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
    final trailing = trailingIcon;
    return Semantics(
      button: true,
      enabled: enabled,
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
              splashColor: (primary ? palette.primaryButtonText : border).withValues(alpha: 0.16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: trailing == null ? 18 : 40, vertical: 12),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: icon == null
                          ? text
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: fontSize * 1.2, color: textColor),
                                const SizedBox(width: 8),
                                Flexible(child: text),
                              ],
                            ),
                    ),
                  ),
                  if (trailing != null)
                    Positioned(right: 16, child: Icon(trailing, size: fontSize * 1.3, color: textColor)),
                ],
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

/// Thin gold divider: vertical between HUD statistics, or [horizontal].
class PremiumDivider extends StatelessWidget {
  const PremiumDivider({super.key, this.horizontal = false});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final gold = BrainTrainPalette.of(context).hudSeparator;
    return Container(
      width: horizontal ? double.infinity : 1,
      height: horizontal ? 1 : 38,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
          end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
          colors: [gold.withValues(alpha: 0), gold.withValues(alpha: gold.a * 0.75), gold.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

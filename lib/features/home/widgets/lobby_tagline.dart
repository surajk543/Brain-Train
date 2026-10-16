import 'package:flutter/material.dart';

import '../../../app/brand.dart';
import '../../../app/theme.dart';
import '../../common/frosted_glass.dart';
import '../../common/glass_painters.dart';
import '../../common/static_layer.dart';

/// "Train your brain" on a frosted-glass panel: the forest and lantern
/// light, blurred, show through a translucent tint, with a gradient rim, an inner top
/// highlight, a soft shadow, a warm glow behind it and leaves peeking out at
/// its sides.
///
/// It fades and rises in once when the home screen first appears (skipped
/// when the platform asks for reduced motion). Screen readers hear one
/// header, "Train your brain".
class LobbyTagline extends StatefulWidget {
  const LobbyTagline({super.key, required this.width, required this.fontSize});

  static const String text = 'Train your brain';

  /// Panel width in logical pixels.
  final double width;

  /// Size of the large "brain"; "Train your" is set smaller above it.
  final double fontSize;

  @override
  State<LobbyTagline> createState() => _LobbyTaglineState();
}

class _LobbyTaglineState extends State<LobbyTagline> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final size = widget.fontSize;
    final leadSize = size * 0.4;
    final gold = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: lobby.taglineGradient,
      stops: const [0, 0.4, 0.62, 1],
    );
    TextStyle brainStyle({Color? color, List<Shadow>? shadows}) => TextStyle(
      fontFamily: kDisplayFont,
      fontFamilyFallback: kDisplayFontFallback,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: size * 0.02,
      color: color,
      shadows: shadows,
    );
    // The letters, and under them a copy that paints only their glow and
    // shadow (a RichText with the style Text would use, so it lays out
    // identically and is not a second "brain" Text).
    final brain = Text(
      'brain',
      maxLines: 1,
      softWrap: false,
      textScaler: TextScaler.noScaling,
      style: brainStyle(color: const Color(0xFFFFFFFF)),
    );
    final defaults = DefaultTextStyle.of(context);
    var shadowStyle = defaults.style.merge(
      brainStyle(
        color: const Color(0x00000000),
        shadows: [
          Shadow(color: lobby.taglineTextGlow, blurRadius: size * 0.35),
          Shadow(color: lobby.textShadow, blurRadius: size * 0.08, offset: Offset(0, size * 0.04)),
        ],
      ),
    );
    if (MediaQuery.boldTextOf(context)) shadowStyle = shadowStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    final brainShadow = RichText(
      text: TextSpan(text: 'brain', style: shadowStyle),
      maxLines: 1,
      softWrap: false,
      textHeightBehavior: defaults.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
    );
    final words = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Train your',
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: displayText(leadSize, color: lobby.taglineLead, weight: FontWeight.w500, spacing: leadSize * 0.08)
              .copyWith(
                fontStyle: FontStyle.italic,
                height: 1.15,
                shadows: [Shadow(color: lobby.textShadow, blurRadius: 8, offset: const Offset(0, 2))],
              ),
        ),
        // Glow and shadow under gold letters. The gradient is masked onto
        // the letters in their own box, so it lines up wherever they sit.
        Stack(
          children: [
            brainShadow,
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => gold.createShader(Rect.fromLTWH(0, size * 0.22, size, size * 0.78)),
              child: brain,
            ),
          ],
        ),
      ],
    );

    final leafHeight = size * 0.7;
    final leafWidth = leafHeight / lobby.buttonLeafAspect;
    Widget leaf({required bool right}) => Transform.flip(
      flipX: right,
      child: Image.asset(
        lobby.buttonLeafAsset,
        width: leafWidth,
        height: leafHeight,
        cacheWidth: (leafWidth * dpr).round(),
        excludeFromSemantics: true,
      ),
    );

    final glowRadius = widget.width * 0.72;
    return Semantics(
      header: true,
      label: LobbyTagline.text,
      excludeSemantics: true,
      child: SizedBox(
        width: widget.width,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Warm light behind the glass.
            Positioned(
              width: glowRadius * 2,
              height: glowRadius * 2,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        lobby.taglineGlow,
                        lobby.taglineGlow.withValues(alpha: lobby.taglineGlow.a * 0.35),
                        lobby.taglineGlow.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _curve,
              builder: (context, child) => Opacity(
                opacity: _curve.value.clamp(0, 1).toDouble(),
                child: Transform.translate(offset: Offset(0, (1 - _curve.value) * size * 0.3), child: child),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(left: -leafWidth * 0.8, child: leaf(right: false)),
                  Positioned(right: -leafWidth * 0.8, child: leaf(right: true)),
                  _GlassPanel(
                    radius: size * 0.34,
                    glowRadius: glowRadius,
                    padding: EdgeInsets.fromLTRB(size * 0.3, size * 0.2, size * 0.3, size * 0.26),
                    child: SizedBox(
                      width: double.infinity,
                      child: FittedBox(fit: BoxFit.scaleDown, child: words),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted glass: the blurred scene behind it ([FrostedGlass]), the warm
/// light seen through it, a tint, a gradient rim, an inner top highlight and
/// a shadow that falls only outside the panel.
///
/// Everything but the frost is static, so it is one [StaticLayer] image: the
/// blurred text shadows and the shadow blur are rendered once, not every
/// frame.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.radius, required this.glowRadius, required this.padding, required this.child});

  final double radius;

  /// Radius of the warm light behind the panel (centred on it).
  final double glowRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final borderRadius = BorderRadius.circular(radius);
    return FrostedGlass(
      borderRadius: borderRadius,
      child: StaticLayer(
        overflow: EdgeInsets.fromLTRB(radius * 2, radius * 2, radius * 2, radius * 2.5),
        child: CustomPaint(
          painter: GlassShadowPainter(
            radius: radius,
            color: lobby.glassShadow,
            glow: lobby.taglineGlow,
            glowRadius: glowRadius,
          ),
          foregroundPainter: GlassRimPainter(radius: radius, colors: lobby.glassBorder),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: lobby.glassFill),
              ),
              child: Stack(
                children: [
                  // Light catching the top of the glass.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: radius * 1.6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [lobby.glassHighlight, lobby.glassHighlight.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                  Padding(padding: padding, child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

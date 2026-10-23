import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../common/frosted_glass.dart';
import '../../common/glass_painters.dart';
import '../../common/static_layer.dart';

/// Leaves tucked behind a lobby button's end.
class _EndLeaf extends StatelessWidget {
  const _EndLeaf({required this.height, required this.flip});

  final double height;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final width = height / lobby.buttonLeafAspect;
    return Transform.flip(
      flipX: flip,
      child: Image.asset(
        lobby.buttonLeafAsset,
        width: width,
        height: height,
        cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        excludeFromSemantics: true,
      ),
    );
  }
}

/// The one glass structure behind every lobby button: [FrostedGlass]
/// (outside) -> one [StaticLayer] with shadow, glow and rim -> tint -> top
/// highlight -> ink and [child].
///
/// Everything but the frost is static, so the blurred shadows are rendered
/// once (and again only while the ink animates). [radius] larger than half the
/// short side makes a stadium or a circle.
class _LobbyGlass extends StatelessWidget {
  const _LobbyGlass({
    required this.radius,
    required this.fill,
    required this.rim,
    required this.rimWidth,
    required this.shadow,
    required this.shadowBlur,
    required this.shadowDrop,
    required this.highlight,
    required this.highlightHeight,
    required this.overflow,
    required this.splash,
    required this.onPressed,
    required this.child,
    this.glow,
    this.glowBlur = 0,
  });

  final double radius;
  final List<Color> fill;
  final List<Color> rim;
  final double rimWidth;
  final Color shadow;
  /// Shadow blur is a mask-filter sigma (not a BoxShadow blurRadius, which is
  /// about twice as wide); the drop is its vertical offset.
  final double shadowBlur;
  final double shadowDrop;

  /// Warm halo around the glass (outside only).
  final Color? glow;
  final double glowBlur;
  final Color highlight;
  final double highlightHeight;
  final EdgeInsets overflow;
  final Color splash;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return FrostedGlass(
      borderRadius: borderRadius,
      child: StaticLayer(
        overflow: overflow,
        child: CustomPaint(
          painter: GlassShadowPainter(
            radius: radius,
            color: shadow,
            blur: shadowBlur,
            offsetY: shadowDrop,
            glow: glow,
            glowBlur: glowBlur,
          ),
          foregroundPainter: GlassRimPainter(radius: radius, colors: rim, strokeWidth: rimWidth),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill),
              ),
              child: Stack(
                children: [
                  // Light catching the top edge.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: highlightHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [highlight, highlight.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: onPressed,
                      splashColor: splash.withValues(alpha: 0.22),
                      highlightColor: splash.withValues(alpha: 0.1),
                      child: child,
                    ),
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

/// Shared pill: glass, semantics, leaves at the ends and a minimum height
/// that grows with the text scale.
class _LobbyPill extends StatelessWidget {
  const _LobbyPill({
    required this.semanticLabel,
    required this.onPressed,
    required this.height,
    required this.fill,
    required this.rim,
    required this.rimWidth,
    required this.splash,
    required this.child,
    required this.leftLeaf,
    required this.rightLeaf,
    this.glow,
    this.glowBlur = 0,
    this.shadowBlur = 12,
    this.shadowDrop = 5,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;
  final double height;
  final List<Color> fill;
  final List<Color> rim;
  final double rimWidth;
  final Color splash;
  final Widget child;
  final bool leftLeaf;
  final bool rightLeaf;
  final Color? glow;
  final double glowBlur;
  final double shadowBlur;
  final double shadowDrop;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final leaf = height * 0.78;
    final leafWidth = leaf / lobby.buttonLeafAspect;
    // Shadows and glow reach ~3 sigma past the pill; the leaves stick out.
    final reach = math.max(44.0, leafWidth * 0.62 + 4);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (leftLeaf)
            Positioned(
              left: -leafWidth * 0.62,
              child: _EndLeaf(height: leaf, flip: false),
            ),
          if (rightLeaf)
            Positioned(
              right: -leafWidth * 0.62,
              child: _EndLeaf(height: leaf, flip: true),
            ),
          _LobbyGlass(
            radius: 1000,
            fill: fill,
            rim: rim,
            rimWidth: rimWidth,
            shadow: lobby.glassShadow,
            shadowBlur: shadowBlur,
            shadowDrop: shadowDrop,
            glow: glow,
            glowBlur: glowBlur,
            highlight: lobby.glassHighlight,
            highlightHeight: height * 0.5,
            overflow: EdgeInsets.symmetric(horizontal: reach, vertical: 44),
            splash: splash,
            onPressed: onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The main call to action ("Continue · Level 2"): gold glass with a bright
/// gold rim and a soft glow, a dark-green play mark, Manrope label and
/// chevron, leaves at both ends. It presses in a little under the finger.
class LobbyPrimaryButton extends StatelessWidget {
  const LobbyPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.height = 62,
  });

  final String label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final fontSize = (height * 0.3).clamp(17.0, 21.0);
    final pill = _LobbyPill(
      semanticLabel: semanticLabel ?? label,
      onPressed: onPressed,
      height: height,
      leftLeaf: true,
      rightLeaf: true,
      splash: Colors.white,
      fill: lobby.primaryGlassFill,
      rim: lobby.primaryGlassRim,
      rimWidth: 1.6,
      glow: lobby.primaryGlassGlow,
      glowBlur: 14,
      shadowBlur: 14,
      shadowDrop: 6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Label centred on the pill, on one line (scaled down if needed).
          Padding(
            padding: EdgeInsets.symmetric(horizontal: height * 0.3 + fontSize * 1.7, vertical: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: BrainTrainType.button(size: fontSize, color: lobby.primaryGlassText).copyWith(
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.white.withValues(alpha: 0.45), offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
          Positioned(
            left: height * 0.3,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(Icons.play_arrow_rounded, size: fontSize * 1.6, color: lobby.primaryGlassText),
            ),
          ),
          Positioned(
            right: height * 0.3,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(Icons.chevron_right_rounded, size: fontSize * 1.3, color: lobby.primaryGlassText),
            ),
          ),
        ],
      ),
    );
    return _PressIn(enabled: onPressed != null, child: pill);
  }
}

/// Shrinks [child] a little while a finger is down on it (press feedback),
/// and springs back. Instant with reduced motion; no ticker otherwise.
class _PressIn extends StatefulWidget {
  const _PressIn({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PressIn> createState() => _PressInState();
}

class _PressInState extends State<_PressIn> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => _set(true) : null,
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}

/// Secondary lobby action (Levels, Settings): dark-green frosted glass, fine
/// gold rim, gold icon, ivory Manrope label, gold chevron.
class LobbySecondaryButton extends StatelessWidget {
  const LobbySecondaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.height = 54,
  });

  final String label;
  final IconData icon;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final fontSize = (height * 0.3).clamp(16.0, 19.0);
    return _LobbyPill(
      semanticLabel: semanticLabel ?? label,
      onPressed: onPressed,
      height: height,
      leftLeaf: false,
      rightLeaf: false,
      splash: lobby.secondaryIcon,
      fill: lobby.secondaryGlassFill,
      rim: lobby.secondaryGlassRim,
      rimWidth: 1.2,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: height * 0.42, vertical: 6),
        child: Row(
          children: [
            // Icon and label together in the middle (reference), the
            // chevron at the end; the empty box on the left balances it.
            SizedBox(width: fontSize * 1.3),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: fontSize * 1.4, color: lobby.secondaryIcon),
                  SizedBox(width: fontSize * 0.9),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrainTrainType.button(size: fontSize, color: lobby.secondaryText).copyWith(
                        letterSpacing: 0.4,
                        shadows: [Shadow(color: lobby.textShadow, blurRadius: 4, offset: const Offset(0, 1.5))],
                      ),
                    ),
                  ),
                  // Optical centring: the icon's weight is on the left.
                  SizedBox(width: fontSize * 1.2),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: fontSize * 1.3, color: lobby.secondaryIcon),
          ],
        ),
      ),
    );
  }
}

/// Small round lobby action (Achievements, Leaderboards): the secondary
/// button's dark-green glass and fine gold rim as a circle with a gold icon.
class LobbyRoundButton extends StatelessWidget {
  const LobbyRoundButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.size = 48,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: _LobbyGlass(
        radius: size / 2,
        fill: lobby.secondaryGlassFill,
        rim: lobby.secondaryGlassRim,
        rimWidth: 1.2,
        shadow: lobby.glassShadow,
        shadowBlur: 10,
        shadowDrop: 4,
        highlight: lobby.glassHighlight,
        highlightHeight: size * 0.5,
        overflow: const EdgeInsets.all(32),
        splash: lobby.secondaryIcon,
        onPressed: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: size * 0.5, color: lobby.secondaryIcon),
        ),
      ),
    );
  }
}

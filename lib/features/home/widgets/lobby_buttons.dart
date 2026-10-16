import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/brand.dart';
import '../../../app/theme.dart';
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

/// Shared pill: decorations, ink, semantics and a minimum height that grows
/// with the text scale.
class _LobbyPill extends StatelessWidget {
  const _LobbyPill({
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    required this.height,
    required this.decoration,
    required this.splash,
    required this.child,
    required this.leftLeaf,
    required this.rightLeaf,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double height;
  final Decoration decoration;
  final Color splash;
  final Widget child;
  final bool leftLeaf;
  final bool rightLeaf;

  @override
  Widget build(BuildContext context) {
    final leaf = height * 0.78;
    final leafWidth = leaf / LobbyTheme.of(context).buttonLeafAspect;
    // Shadows and glow reach ~3 sigma past the pill; the leaves stick out.
    final reach = math.max(44.0, leafWidth * 0.62 + 4);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      // Rendered once (and again only while its ink animates), not on every
      // frame of the leaves and fireflies behind it.
      child: StaticLayer(
        overflow: EdgeInsets.symmetric(horizontal: reach, vertical: 44),
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
            DecoratedBox(
              decoration: decoration,
              child: Material(
                type: MaterialType.transparency,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  splashColor: splash.withValues(alpha: 0.22),
                  highlightColor: splash.withValues(alpha: 0.1),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The main call to action ("Continue · Level 2"): warm gold pill, dark
/// green serif label, chevron, leaves at both ends.
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
    final fontSize = (height * 0.34).clamp(17.0, 23.0);
    return _LobbyPill(
      label: label,
      semanticLabel: semanticLabel ?? label,
      onPressed: onPressed,
      height: height,
      leftLeaf: true,
      rightLeaf: true,
      splash: Colors.white,
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: lobby.primaryEdge, width: 1.4)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: lobby.primaryFill),
        shadows: [
          BoxShadow(color: lobby.primaryGlow, blurRadius: 22, spreadRadius: 1),
          BoxShadow(color: lobby.primaryShadow, blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glossy highlight across the top half.
          Positioned(
            left: height * 0.4,
            right: height * 0.4,
            top: 2,
            height: height * 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          // Label centred on the pill, on one line (scaled down if needed).
          Padding(
            padding: EdgeInsets.symmetric(horizontal: height * 0.3 + fontSize * 1.4, vertical: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: displayText(fontSize, color: lobby.primaryText, weight: FontWeight.w700, spacing: 0.3).copyWith(
                  shadows: [Shadow(color: Colors.white.withValues(alpha: 0.45), offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
          Positioned(
            right: height * 0.3,
            top: 0,
            bottom: 0,
            child: Center(
              child: Icon(Icons.chevron_right_rounded, size: fontSize * 1.3, color: lobby.primaryText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Secondary lobby action (Levels, Settings): deep translucent green pill,
/// thin gold border, gold icon, ivory serif label, chevron, leaf at the
/// left end.
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
    final fontSize = (height * 0.34).clamp(16.0, 21.0);
    return _LobbyPill(
      label: label,
      semanticLabel: semanticLabel ?? label,
      onPressed: onPressed,
      height: height,
      leftLeaf: true,
      rightLeaf: false,
      splash: lobby.secondaryIcon,
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: lobby.secondaryBorder, width: 1.2)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: lobby.secondaryFill),
        shadows: [BoxShadow(color: lobby.secondaryShadow, blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: height * 0.5, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: fontSize * 1.2, color: lobby.secondaryIcon),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: displayText(fontSize, color: lobby.secondaryText, weight: FontWeight.w600, spacing: 0.4),
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
/// button's green glass and thin gold border as a circle with a gold icon.
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
      // Rendered once (and again only while its ink animates).
      child: StaticLayer(
        overflow: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: CircleBorder(side: BorderSide(color: lobby.secondaryBorder, width: 1.2)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: lobby.secondaryFill),
            shadows: [BoxShadow(color: lobby.secondaryShadow, blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              splashColor: lobby.secondaryIcon.withValues(alpha: 0.22),
              highlightColor: lobby.secondaryIcon.withValues(alpha: 0.1),
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon, size: size * 0.5, color: lobby.secondaryIcon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

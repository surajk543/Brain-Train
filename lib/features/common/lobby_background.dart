import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'flowing_leaves.dart';
import 'frosted_glass.dart';
import 'lobby_particles.dart';
import 'static_layer.dart';

/// Which screen the lobby scene sits behind.
enum LobbySceneVariant {
  /// Home: full scene, calm vignette behind the title and buttons, fireflies.
  home,

  /// Levels and Settings: the same scene, shaded for long lists of text.
  subScreen,
}

/// The night garden behind the home, Levels and Settings screens, as
/// described by [LobbyTheme]: bundled art layers, Flutter-drawn lighting
/// (lantern glow, calm centre, vignette), drifting leaves and, on home,
/// fireflies. All of it stays behind the child and never takes taps.
///
/// Everything is bundled, so the scene is complete offline; a gradient in
/// the scene's colours shows for the first frames while the art decodes.
/// The art and lighting are flattened into one image by a [StaticLayer]
/// (re-rendered only when an image arrives or the size changes), so each
/// animation frame draws one image, the leaves and the fireflies. That image,
/// blurred once, is the [FrostSource] for glass panels in [child].
class LobbyBackground extends StatefulWidget {
  const LobbyBackground({super.key, this.variant = LobbySceneVariant.home, this.child});

  final LobbySceneVariant variant;
  final Widget? child;

  @override
  State<LobbyBackground> createState() => _LobbyBackgroundState();
}

class _LobbyBackgroundState extends State<LobbyBackground> {
  late final FrostSource _frost = FrostSource(sigma: LobbyTheme.night.glassBlur);

  @override
  void dispose() {
    _frost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final home = widget.variant == LobbySceneVariant.home;
    final child = widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        StaticLayer(
          onRaster: _frost.update,
          child: _Scene(lobby: lobby, home: home),
        ),
        RepaintBoundary(
          child: FlowingLeaves(
            count: home ? lobby.leafCount : lobby.subScreenLeafCount,
            opacity: lobby.leafOpacity * (home ? 1 : 0.8),
          ),
        ),
        if (home && lobby.particleCount > 0)
          IgnorePointer(
            child: RepaintBoundary(
              child: LobbyParticles(count: lobby.particleCount, color: lobby.particleColor, size: lobby.particleSize),
            ),
          ),
        if (child != null) FrostScope(source: _frost, child: child),
      ],
    );
  }
}

class _Scene extends StatelessWidget {
  const _Scene({required this.lobby, required this.home});

  final LobbyTheme lobby;
  final bool home;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // Cover fit: the base is scaled by whichever side needs more.
      final baseWidth = math.max(size.width, size.height / lobby.baseAspect);
      final placed = [for (final decor in lobby.decor) _place(decor, size)];
      return Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: lobby.baseFallback,
              ),
            ),
          ),
          Image.asset(
            lobby.baseAsset,
            fit: BoxFit.cover,
            cacheWidth: (baseWidth * dpr).round(),
            gaplessPlayback: true,
            excludeFromSemantics: true,
          ),
          for (final (decor, rect) in placed)
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: decor.opacity,
                child: Transform.flip(
                  flipX: decor.flipX,
                  child: Image.asset(
                    decor.asset,
                    fit: BoxFit.fill,
                    cacheWidth: (rect.width * dpr).round(),
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          CustomPaint(
            painter: _LightingPainter(
              lights: lobby.lights,
              decorGlows: [
                for (final (decor, rect) in placed)
                  if (decor.glow case final glow?) (glow, rect),
              ],
              scrim: home ? lobby.contentScrim : null,
              vignette: lobby.edgeVignette,
              shade: home ? null : lobby.subScreenScrim,
            ),
          ),
        ],
      );
    },
  );

  static (LobbyDecor, Rect) _place(LobbyDecor decor, Size size) {
    final w = decor.width * size.width;
    final h = w * decor.aspect;
    final dx = decor.dx * size.width;
    final dy = decor.dy * size.height;
    final (left, top) = switch (decor.anchor) {
      LobbyAnchor.topLeft => (dx, dy),
      LobbyAnchor.topRight => (size.width - w - dx, dy),
      LobbyAnchor.bottomLeft => (dx, size.height - h - dy),
      LobbyAnchor.bottomRight => (size.width - w - dx, size.height - h - dy),
      LobbyAnchor.bottomCenter => ((size.width - w) / 2, size.height - h - dy),
    };
    return (decor, Rect.fromLTWH(left, top, w, h));
  }
}

/// Lighting above the art: lantern and ambient glows (screen blend), a calm
/// vignette behind the content, and darker edges.
class _LightingPainter extends CustomPainter {
  _LightingPainter({
    required this.lights,
    required this.decorGlows,
    required this.scrim,
    required this.vignette,
    this.shade,
  });

  final List<LobbyGlow> lights;
  final List<(LobbyGlow, Rect)> decorGlows;
  final Color? scrim;
  final Color vignette;
  final Color? shade;

  void _glow(Canvas canvas, LobbyGlow glow, Rect box, {BlendMode blend = BlendMode.screen}) {
    final center = glow.center.withinRect(box);
    final radius = glow.radius * box.width;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, glow.squash);
    final circle = Rect.fromCircle(center: Offset.zero, radius: radius);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..blendMode = blend
        ..shader = RadialGradient(
          colors: [
            glow.color,
            glow.color.withValues(alpha: glow.color.a * 0.45),
            glow.color.withValues(alpha: 0),
          ],
          stops: const [0, 0.4, 1],
        ).createShader(circle),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shade = this.shade;
    if (shade != null) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              shade,
              shade.withValues(alpha: shade.a * 0.75),
              shade,
            ],
          ).createShader(rect),
      );
    }
    final scrim = this.scrim;
    if (scrim != null) {
      // Calm oval behind the title and buttons.
      _glow(
        canvas,
        LobbyGlow(
          center: const Alignment(0, 0.22),
          radius: 0.78,
          color: scrim,
          squash: size.height / size.width * 0.62,
        ),
        rect,
        blend: BlendMode.srcOver,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [vignette.withValues(alpha: 0), vignette],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCenter(center: rect.center, width: size.width * 1.2, height: size.height)),
    );
    for (final light in lights) {
      _glow(canvas, light, rect);
    }
    for (final (glow, box) in decorGlows) {
      _glow(canvas, glow, box);
    }
  }

  @override
  bool shouldRepaint(_LightingPainter old) =>
      old.lights != lights ||
      old.scrim != scrim ||
      old.vignette != vignette ||
      old.shade != shade ||
      old.decorGlows.length != decorGlows.length ||
      [for (var i = 0; i < decorGlows.length; i++) old.decorGlows[i] != decorGlows[i]].any((changed) => changed);
}

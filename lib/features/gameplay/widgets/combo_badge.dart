import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../common/static_layer.dart';
import '../game_controller.dart';

const double _pillHeight = 24;

/// "COMBO ×N · Best ×M" gold pill (from ×2) floating on the tray's bottom
/// edge; with no combo running, a small "Best ×M" chip once a combo of 2 or
/// more has happened. Hidden during the board intro. The time left in the
/// combo window is the [ComboTimerBar] under the HUD (redesign 1.1.0), so
/// the pill itself never ticks.
///
/// The glow (×3) is static; the spark burst (×4) and shimmer (×5) are
/// one-shot controllers that stop when done. Draws no blur filter, no
/// `Opacity`, no layers beyond one [StaticLayer].
class ComboBadge extends StatefulWidget {
  const ComboBadge({super.key, required this.controller, required this.reduceMotion});

  final GameController controller;
  final bool reduceMotion;

  @override
  State<ComboBadge> createState() => _ComboBadgeState();
}

class _ComboBadgeState extends State<ComboBadge> with TickerProviderStateMixin {
  late final AnimationController _sparks;
  late final AnimationController _shimmer;

  /// The combo shown at the last update (0 below ×2), to fire each intensity
  /// effect once when the combo first reaches its level.
  int _lastCombo = 0;

  @override
  void initState() {
    super.initState();
    // Made here, not lazily: a controller first made in dispose would look up
    // the (deactivated) tree.
    _sparks = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _lastCombo = widget.controller.activeCombo >= 2 ? widget.controller.activeCombo : 0;
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ComboBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (widget.reduceMotion) {
      _sparks.stop();
      _shimmer.stop();
    }
  }

  void _changed() {
    final combo = widget.controller.activeCombo;
    if (combo < 2) {
      _lastCombo = 0;
    } else {
      if (!widget.reduceMotion) {
        if (combo >= 4 && _lastCombo < 4) _sparks.forward(from: 0);
        if (combo >= 5 && _lastCombo < 5) _shimmer.forward(from: 0);
      }
      _lastCombo = combo;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _sparks.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final combo = widget.controller.activeCombo;
    final best = widget.controller.scoring.bestCombo;
    if (widget.controller.introPlaying || (combo < 2 && best < 2)) return const SizedBox.shrink();
    return IgnorePointer(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: combo >= 2 ? _pill(context, combo, best) : _bestChip(context, best),
      ),
    );
  }

  /// A dark chip, so it reads over ivory tiles as well as felt.
  Widget _bestChip(BuildContext context, int best) {
    final palette = BrainTrainPalette.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: palette.hudFill.last.withValues(alpha: 0.9),
        shape: StadiumBorder(side: BorderSide(color: palette.accent.withValues(alpha: 0.45), width: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Text('Best ×$best', style: BrainTrainType.hudLabel(size: 10.5, color: palette.accentLight).copyWith(letterSpacing: 0.4)),
      ),
    );
  }

  Widget _pill(BuildContext context, int combo, int best) {
    final palette = BrainTrainPalette.of(context);
    final warm = combo >= 3;
    final rim = warm ? palette.accent : palette.accentLight;
    return Semantics(
      label: 'Combo times $combo',
      liveRegion: true,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (warm)
            Positioned.fill(left: -14, right: -14, top: -10, bottom: -10, child: CustomPaint(painter: _GlowPainter(palette.accent))),
          StaticLayer(
            overflow: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Container(
              height: _pillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [for (final c in palette.primaryButtonFill) c.withValues(alpha: 0.94)],
                ),
                shape: StadiumBorder(side: BorderSide(color: rim, width: 1.2)),
                shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Text(
                'COMBO ×$combo · Best ×${math.max(best, combo)}',
                maxLines: 1,
                softWrap: false,
                style: BrainTrainType.combo(size: 11.5, color: palette.textOnGold).copyWith(letterSpacing: 0.9, height: 1.1),
              ),
            ),
          ),
          if (_sparks.isAnimating)
            Positioned.fill(left: -16, right: -16, top: -14, bottom: -14, child: RepaintBoundary(child: CustomPaint(painter: _SparksPainter(_sparks, palette.accentLight)))),
          if (_shimmer.isAnimating) Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _ShimmerPainter(_shimmer)))),
        ],
      ),
    );
  }
}

/// Soft golden halo around the pill: a radial gradient, no blur filter.
class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.gold);

  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [gold.withValues(alpha: 0.42), gold.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.gold != gold;
}

/// Seven small gold sparks flying out of the pill, fading as they go.
class _SparksPainter extends CustomPainter {
  _SparksPainter(this.t, this.gold) : super(repaint: t);

  final Animation<double> t;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Curves.easeOut.transform(t.value);
    final centre = size.center(Offset.zero);
    final rx = size.width / 2;
    final ry = size.height / 2;
    final paint = Paint();
    for (var i = 0; i < 7; i++) {
      final angle = 2 * math.pi * i / 7 - math.pi / 2;
      final reach = 0.62 + 0.38 * p;
      final at = centre + Offset(math.cos(angle) * rx * reach, math.sin(angle) * ry * reach);
      paint.color = gold.withValues(alpha: (1 - t.value).clamp(0.0, 1.0));
      canvas.drawCircle(at, 2.4 - 1.2 * p, paint);
    }
  }

  @override
  bool shouldRepaint(_SparksPainter old) => old.t != t || old.gold != gold;
}

/// A light band sweeping across the pill, clipped to its stadium shape.
class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final pill = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(pill);
    final band = size.width * 0.45;
    final x = -band + (size.width + 2 * band) * Curves.easeInOut.transform(t.value);
    final rect = Rect.fromLTWH(x, 0, band, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}

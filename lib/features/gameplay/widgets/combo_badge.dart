import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/brand.dart';
import '../../common/static_layer.dart';
import '../game_controller.dart';

const Color _ink = Color(0xFF183D2D);
const double _pillHeight = 28;

/// "COMBO ×N" pill (from ×2) with a ring that drains with the combo window,
/// and "Best ×N" under it once a combo of 2 or more has happened.
///
/// Nothing ticks without a combo: the ring ticker runs only while a combo is
/// active, the clock runs and motion is allowed; the glow (×3) is static, the
/// spark burst (×4) and shimmer (×5) are one-shot controllers that stop when
/// done. Draws no blur filter, no `Opacity`, no layers beyond one
/// [StaticLayer].
class ComboBadge extends StatefulWidget {
  const ComboBadge({super.key, required this.controller, required this.reduceMotion});

  final GameController controller;
  final bool reduceMotion;

  @override
  State<ComboBadge> createState() => _ComboBadgeState();
}

class _ComboBadgeState extends State<ComboBadge> with TickerProviderStateMixin {
  /// The ring's sweep, 1 (full window) to 0.
  final ValueNotifier<double> _ring = ValueNotifier(1);
  late final Ticker _ringTicker = createTicker((_) => _ring.value = _fraction());
  late final AnimationController _sparks = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  /// The combo shown at the last update (0 below ×2), to fire each intensity
  /// effect once when the combo first reaches its level.
  int _lastCombo = 0;

  @override
  void initState() {
    super.initState();
    _lastCombo = widget.controller.activeCombo >= 2 ? widget.controller.activeCombo : 0;
    widget.controller.addListener(_changed);
    _ring.value = _fraction();
    _syncTicker();
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
    _syncTicker();
  }

  double _fraction() {
    final left = widget.controller.comboTimeLeft;
    if (left == null) return 0;
    final window = widget.controller.scoring.rules.comboWindow.inMicroseconds;
    return (left.inMicroseconds / window).clamp(0.0, 1.0);
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
    _ring.value = _fraction();
    _syncTicker();
    if (mounted) setState(() {});
  }

  void _syncTicker() {
    final run = widget.controller.activeCombo >= 2 && widget.controller.clockRunning && !widget.reduceMotion;
    if (run && !_ringTicker.isActive) {
      _ringTicker.start();
    } else if (!run && _ringTicker.isActive) {
      _ringTicker.stop();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _ringTicker.dispose();
    _sparks.dispose();
    _shimmer.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final combo = widget.controller.activeCombo;
    final best = widget.controller.scoring.bestCombo;
    final children = <Widget>[
      if (combo >= 2) _pill(combo),
      if (best >= 2)
        Padding(
          padding: EdgeInsets.only(top: combo >= 2 ? 3 : 0),
          child: Text(
            'Best ×$best',
            style: displayText(
              11,
              color: BrandGold.light.withValues(alpha: 0.85),
              weight: FontWeight.w600,
            ).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 2)]),
          ),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _pill(int combo) {
    final warm = combo >= 3;
    final rim = warm ? BrandGold.warm : BrandGold.light;
    return Semantics(
      label: 'Combo times $combo',
      liveRegion: true,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (warm)
            Positioned.fill(left: -14, right: -14, top: -10, bottom: -10, child: const CustomPaint(painter: _GlowPainter())),
          StaticLayer(
            child: Container(
              height: _pillHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: ShapeDecoration(
                gradient: const LinearGradient(colors: [Color(0xE6F8DA8C), Color(0xD9D8B25E)]),
                shape: StadiumBorder(side: BorderSide(color: rim, width: 1.2)),
                shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'COMBO ×$combo',
                    style: displayText(13, color: _ink, weight: FontWeight.w800, spacing: 1.2),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 18, height: 18),
                ],
              ),
            ),
          ),
          // The ring sits in the space the pill leaves for it, on the right.
          Positioned(
            right: 14,
            child: RepaintBoundary(
              child: CustomPaint(size: const Size(18, 18), painter: _RingPainter(_ring)),
            ),
          ),
          if (_sparks.isAnimating)
            Positioned.fill(left: -16, right: -16, top: -14, bottom: -14, child: CustomPaint(painter: _SparksPainter(_sparks))),
          if (_shimmer.isAnimating) Positioned.fill(child: CustomPaint(painter: _ShimmerPainter(_shimmer))),
        ],
      ),
    );
  }
}

/// Arc that drains clockwise from the top as the window closes.
class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction) : super(repaint: fraction);

  final ValueListenable<double> fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.1);
    final sweep = 2 * math.pi * fraction.value;
    if (sweep <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = _ink.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

/// Soft golden halo around the pill: a radial gradient, no blur filter.
class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [BrandGold.warm.withValues(alpha: 0.42), BrandGold.warm.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}

/// Seven small gold sparks flying out of the pill, fading as they go.
class _SparksPainter extends CustomPainter {
  _SparksPainter(this.t) : super(repaint: t);

  final Animation<double> t;

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
      paint.color = BrandGold.light.withValues(alpha: (1 - t.value).clamp(0.0, 1.0));
      canvas.drawCircle(at, 2.4 - 1.2 * p, paint);
    }
  }

  @override
  bool shouldRepaint(_SparksPainter old) => old.t != t;
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

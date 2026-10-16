import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/brand.dart';
import '../../../game_engine/scoring/score_format.dart';
import '../game_controller.dart';

const Duration _popIn = Duration(milliseconds: 120);
const double _rise = 28;
const Color _penaltyColor = Color(0xFFE59A9A);

/// "+250 / ×2 · +50 fast" rising from the tray slot where a pair struck, and a
/// small "−1" over a blocked tile. Each popup pops in (scale 0.6 to 1), then
/// rises and fades. Drawn by one painter with [TextPainter]s whose colours
/// carry the alpha; the ticker runs only while a popup lives. Wrap it in
/// `IgnorePointer` (the screen does, and it ignores touches itself too).
///
/// With reduced motion there are no popups: the HUD number just changes.
class ScorePopupOverlay extends StatefulWidget {
  const ScorePopupOverlay({
    super.key,
    required this.controller,
    required this.traySlotRect,
    required this.tileRect,
    required this.reduceMotion,
  });

  final GameController controller;

  /// Global rect of the tray slot's tile face, or null when not laid out.
  final Rect? Function(int slot) traySlotRect;

  /// Global rect of a board tile's face, or null.
  final Rect? Function(String tileId) tileRect;
  final bool reduceMotion;

  @override
  State<ScorePopupOverlay> createState() => ScorePopupOverlayState();
}

class _PopupLine {
  _PopupLine(this.text, this.style, this.shadow) : painter = TextPainter(textDirection: TextDirection.ltr);

  final String text;
  final TextStyle style;
  final bool shadow;
  final TextPainter painter;

  /// The alpha step (of 32) the painter is laid out for, -1 before the first layout.
  int _step = -1;

  /// Lays the line out in [alpha] of its colours, only when the alpha moved by
  /// a 1/32 step since the last layout. The shadow is a hard 1-px offset (no
  /// blur), so a layout is cheap and the paint has no blur pass.
  void layout(double alpha) {
    final step = (alpha * 32).round();
    if (step == _step) return;
    _step = step;
    alpha = step / 32;
    final color = (style.color ?? const Color(0xFFFFFFFF)).withValues(alpha: alpha);
    painter
      ..text = TextSpan(
        text: text,
        style: style.copyWith(
          color: color,
          shadows: shadow ? [Shadow(color: const Color(0xFF000000).withValues(alpha: 0.7 * alpha), blurRadius: 0, offset: const Offset(0, 1))] : null,
        ),
      )
      ..layout();
  }
}

class _Popup {
  _Popup({required this.origin, required this.lines, required this.start, required this.life, required this.direction});

  /// Local anchor: just above the centre of a slot (awards) or the centre of
  /// a tile (penalties).
  final Offset origin;
  final List<_PopupLine> lines;
  final Duration start;

  /// The fade-and-rise time after the pop-in.
  final Duration life;

  /// -1: rises upward (awards over the tray frame, penalties over the board).
  final double direction;

  Duration get total => _popIn + life;

  void dispose() {
    for (final line in lines) {
      line.painter.dispose();
    }
  }
}

class ScorePopupOverlayState extends State<ScorePopupOverlay> with SingleTickerProviderStateMixin {
  final List<_Popup> _popups = [];
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  StreamSubscription<ScoreEvent>? _subscription;
  Duration _now = Duration.zero;

  /// Popups alive right now.
  @visibleForTesting
  int get popupCount => _popups.length;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _subscription = widget.controller.scoreEvents.listen(_onEvent);
  }

  @override
  void didUpdateWidget(ScorePopupOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription?.cancel());
      _subscription = widget.controller.scoreEvents.listen(_onEvent);
    }
    if (widget.reduceMotion) _clear();
  }

  Offset? _toLocal(Rect? global, {required Offset Function(Rect) anchor}) {
    final box = context.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize || !box.attached) return null;
    return box.globalToLocal(anchor(global));
  }

  void _onEvent(ScoreEvent event) {
    if (widget.reduceMotion || !mounted) return;
    switch (event) {
      case ScoreAwarded(:final score, :final traySlot):
        final origin = _toLocal(widget.traySlotRect(traySlot), anchor: (r) => r.center - const Offset(0, 6));
        if (origin == null) return;
        _add(
          _Popup(
            origin: origin,
            start: _now,
            life: const Duration(milliseconds: 700),
            direction: -1,
            lines: [
              _PopupLine('+${formatScore(score.points)}', displayText(20, color: BrandGold.light, weight: FontWeight.w800), true),
              _PopupLine(
                '×${score.multiplier}${score.speedBonus > 0 ? ' · +${score.speedBonus} fast' : ''}',
                displayText(12, color: BrandGold.light, weight: FontWeight.w600),
                true,
              ),
            ],
          ),
        );
      case ScorePenalty(:final tileId, :final points):
        final origin = _toLocal(widget.tileRect(tileId), anchor: (r) => r.center);
        if (origin == null) return;
        _add(
          _Popup(
            origin: origin,
            start: _now,
            life: const Duration(milliseconds: 500),
            direction: -1,
            lines: [_PopupLine('−$points', displayText(16, color: _penaltyColor, weight: FontWeight.w700), true)],
          ),
        );
    }
  }

  void _add(_Popup popup) {
    if (_popups.isEmpty) {
      // The ticker's clock starts at zero each time it starts.
      _now = Duration.zero;
    }
    _popups.add(popup);
    if (!_ticker.isActive) _ticker.start();
    _frame.value++;
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    _popups.removeWhere((p) {
      final done = elapsed - p.start >= p.total;
      if (done) p.dispose();
      return done;
    });
    if (_popups.isEmpty && _ticker.isActive) _ticker.stop();
    _frame.value++;
  }

  void _clear() {
    for (final popup in _popups) {
      popup.dispose();
    }
    _popups.clear();
    if (_ticker.isActive) _ticker.stop();
    _frame.value++;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _ticker.dispose();
    for (final popup in _popups) {
      popup.dispose();
    }
    _popups.clear();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _PopupPainter(this, _frame), size: Size.infinite),
    ),
  );
}

class _PopupPainter extends CustomPainter {
  _PopupPainter(this.state, ValueListenable<int> repaint) : super(repaint: repaint);

  final ScorePopupOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    for (final popup in state._popups) {
      final age = state._now - popup.start;
      final scale = age >= _popIn
          ? 1.0
          : 0.6 + 0.4 * Curves.easeOutBack.transform((age.inMicroseconds / _popIn.inMicroseconds).clamp(0.0, 1.0));
      final t = age <= _popIn ? 0.0 : ((age - _popIn).inMicroseconds / popup.life.inMicroseconds).clamp(0.0, 1.0);
      final alpha = 1 - Curves.easeIn.transform(t);
      if (alpha <= 0) continue;
      var height = 0.0;
      for (final line in popup.lines) {
        line.layout(alpha);
        height += line.painter.height;
      }
      // Centred on the anchor, rising.
      final top = -height / 2;
      final dy = popup.direction * _rise * Curves.easeOut.transform(t);
      canvas.save();
      canvas.translate(popup.origin.dx, popup.origin.dy + dy);
      canvas.scale(scale);
      var y = top;
      for (final line in popup.lines) {
        line.painter.paint(canvas, Offset(-line.painter.width / 2, y));
        y += line.painter.height;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PopupPainter old) => false;
}

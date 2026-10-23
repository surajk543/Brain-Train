import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../content/level_manifest.dart';
import '../../../game_engine/scoring/score_format.dart';
import '../../../game_engine/state/game_state.dart';
import '../game_controller.dart';
import '../../common/static_layer.dart';
import 'premium_chrome.dart';

/// Minutes and seconds of a game clock: `0:45`, `12:03`.
String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The gameplay HUD (redesign 1.1.0, reference board): a compact dark-green
/// panel with a fine gold rim at the top of the screen. Back (a round
/// gold-rimmed button), `Level N` over the level's name, then SCORE, COMBO,
/// PAIRS and TIME in tabular Manrope figures between fine gold separators,
/// and Pause at the right end (owner, 2026-10-23; when [onPause] is set: on
/// only while [canPause] answers true, re-asked when [pauseListenable] or the
/// controller changes).
///
/// Narrow screens: the statistics take at most [_statsShare] of the width
/// and shrink (never wrap) before the name gets too small; the name shrinks
/// to [_LevelTitle.minScale] of its size, then ends in an ellipsis. Text
/// scales with the platform setting up to 1.3x (the panel has a fixed
/// height, like the rest of the game's chrome).
///
/// Only the statistics rebuild on moves, and only the clock every second.
class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.entry,
    required this.controller,
    required this.onBack,
    this.onPause,
    this.canPause,
    this.pauseListenable,
    this.compact = false,
  });

  final LevelManifestEntry entry;
  final GameController controller;
  final VoidCallback onBack;

  /// Opens the pause card; null: no Pause button.
  final VoidCallback? onPause;

  /// Whether Pause is on now (null: always).
  final bool Function()? canPause;

  /// Changes that may turn Pause on or off, besides the controller's.
  final Listenable? pauseListenable;

  /// Short screens: smaller type (see `GameLayout.compact`).
  final bool compact;

  /// The statistics' largest share of the panel's width.
  static const double _statsShare = 0.64;

  /// They shrink to leave the name this share at most (then it ellipsizes),
  /// and never below [_statsMinShare].
  static const double _titleShare = 0.36;
  static const double _statsMinShare = 0.46;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: Stack(
      children: [
        // The panel (frost, rim, shadows) is drawn once into an image: the
        // leaves drifting behind it would otherwise redraw its shadow blurs
        // every frame. The figures above it are plain text.
        Positioned.fill(
          child: StaticLayer(
            overflow: const EdgeInsets.fromLTRB(26, 16, 26, 36),
            child: PremiumPanel(radius: compact ? 16 : 18, child: const SizedBox.expand()),
          ),
        ),
        _content(),
      ],
    ),
  );

  Widget _content() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final back = _HudRoundButton.boxWidth(compact);
      final pause = onPause == null ? 0.0 : back;
      // The name at its smallest size, capped at its share: the statistics
      // take the rest (shrinking a little for a long name).
      final title = math.min(_LevelTitle.minWidth(context, entry, compact: compact), width * _titleShare);
      final stats = (width - back - pause - (compact ? 10 : 16) - title).clamp(
        width * _statsMinShare,
        width * _statsShare,
      );
      return Row(
        children: [
          _HudRoundButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onPressed: onBack,
            compact: compact,
            key: const ValueKey('hud-back'),
          ),
          Expanded(child: _LevelTitle(entry: entry, compact: compact)),
          SizedBox(width: compact ? 4 : 8),
          const _HudSeparator(),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: stats),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<int>(
                          tween: IntTween(end: controller.score),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          builder: (context, value, _) =>
                              HudStat(label: 'Score', value: formatScore(value), compact: compact),
                        ),
                        const _HudSeparator(),
                        _ComboStat(combo: controller.activeCombo, compact: compact),
                        const _HudSeparator(),
                        HudStat(
                          label: 'Pairs',
                          value: '${controller.state.matchedPairs}/${controller.state.totalPairs}',
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                  const _HudSeparator(),
                  // Ticks every second; keep that repaint to the clock.
                  RepaintBoundary(child: _ClockStat(controller: controller, compact: compact)),
                ],
              ),
            ),
          ),
          if (onPause case final onPause?)
            ListenableBuilder(
              listenable: Listenable.merge([controller, pauseListenable]),
              builder: (context, _) => _HudRoundButton(
                key: const ValueKey('hud-pause'),
                icon: Icons.pause_rounded,
                label: 'Pause',
                gold: true,
                compact: compact,
                onPressed: (canPause?.call() ?? true) ? onPause : null,
              ),
            )
          else
            SizedBox(width: compact ? 4 : 6),
        ],
      );
    },
  );
}

/// A round HUD button (Back, Pause): a dark disc with a fine gold rim and an
/// ivory icon ([gold]: a gold icon), in a 44-px target. [onPressed] null:
/// off, dimmed (colours, not an Opacity layer).
class _HudRoundButton extends StatelessWidget {
  const _HudRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.compact,
    this.gold = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  final bool gold;

  /// The button's box in the HUD row.
  static double boxWidth(bool compact) => compact ? 40 : 48;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final enabled = onPressed != null;
    final disc = compact ? 32.0 : 36.0;
    final ink = (gold ? palette.accentLight : palette.text).withValues(alpha: enabled ? 1 : 0.35);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onPressed,
            radius: 22,
            highlightShape: BoxShape.circle,
            child: SizedBox(
              width: boxWidth(compact),
              height: 44,
              child: Center(
                child: Container(
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.4),
                      colors: [
                        palette.hudFill.first.withValues(alpha: 0.95),
                        palette.hudFill.last.withValues(alpha: 0.98),
                      ],
                    ),
                    border: Border.all(color: palette.accent.withValues(alpha: enabled ? 0.9 : 0.3), width: 1.4),
                  ),
                  child: Icon(icon, color: ink, size: disc * 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Level N` (small gold caps) over the level's name (Playfair).
class _LevelTitle extends StatelessWidget {
  const _LevelTitle({required this.entry, required this.compact});

  final LevelManifestEntry entry;
  final bool compact;

  /// The smallest the name shrinks to before it ends in an ellipsis.
  static const double minScale = 0.72;

  double get _titleSize => compact ? 15.5 : 18;

  static TextStyle _base(BuildContext context, {required bool compact}) => BrainTrainType.levelName(
    size: compact ? 15.5 : 18,
    color: BrainTrainPalette.of(context).hudValue,
  ).copyWith(height: 1.12);

  /// The width the name needs at its smallest ([minScale]), with a little
  /// room to spare.
  static double minWidth(BuildContext context, LevelManifestEntry entry, {required bool compact}) {
    final base = _base(context, compact: compact);
    final painter = TextPainter(
      text: TextSpan(text: entry.title, style: base.copyWith(fontSize: base.fontSize! * minScale)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 4;
  }

  /// One line: the name at full size if it fits, else shrunk to fit (down to
  /// [minScale]), then ellipsized.
  TextStyle _fit(BuildContext context, TextStyle base, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: entry.title, style: base),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    if (width <= maxWidth) return base;
    return base.copyWith(fontSize: _titleSize * math.max(minScale, maxWidth / width * 0.98));
  }

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final base = _base(context, compact: compact);
    return LayoutBuilder(
      builder: (context, constraints) => Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Level ${entry.order}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: BrainTrainType.button(size: compact ? 11 : 12.5, color: palette.accent).copyWith(
                letterSpacing: 0.4,
                height: 1.15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 1 : 2),
            Text(
              entry.title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _fit(context, base, constraints.maxWidth),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small caps label over a tabular value: one HUD statistic.
class HudStat extends StatelessWidget {
  const HudStat({super.key, required this.label, required this.value, this.compact = false, this.valueColor, this.minWidth});

  final String label;
  final String value;
  final bool compact;

  /// Gold for the combo while one runs; the HUD's ivory otherwise.
  final Color? valueColor;

  /// Keeps a cell's width when its value changes length.
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(), style: BrainTrainType.hudLabel(size: compact ? 9.5 : 10.5, color: palette.hudLabel)),
              SizedBox(height: compact ? 1 : 2),
              Text(
                value,
                style: BrainTrainType.scoreValue(size: compact ? 16 : 19, color: valueColor ?? palette.hudValue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// COMBO ×N: gold on a faint gold cell while a combo of 2 or more runs,
/// a quiet ×1 otherwise.
class _ComboStat extends StatelessWidget {
  const _ComboStat({required this.combo, required this.compact});

  final int combo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final on = combo >= 2;
    final stat = HudStat(
      label: 'Combo',
      value: '×${math.max(1, combo)}',
      compact: compact,
      minWidth: compact ? 52 : 60,
      valueColor: on ? palette.accent : palette.hudValue.withValues(alpha: 0.62),
    );
    if (!on) return stat;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.accent.withValues(alpha: 0.26), palette.accentDeep.withValues(alpha: 0.18)],
        ),
        border: Border.all(color: palette.accent.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: stat),
    );
  }
}

/// A fine vertical gold line, faded at both ends.
class _HudSeparator extends StatelessWidget {
  const _HudSeparator();

  @override
  Widget build(BuildContext context) {
    final gold = BrainTrainPalette.of(context).hudSeparator;
    return Container(
      width: 1,
      height: 30,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gold.withValues(alpha: 0), gold.withValues(alpha: gold.a * 0.7), gold.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Rebuilds once a second; only this widget, not the board.
class _ClockStat extends StatefulWidget {
  const _ClockStat({required this.controller, required this.compact});

  final GameController controller;
  final bool compact;

  @override
  State<_ClockStat> createState() => _ClockStatState();
}

class _ClockStatState extends State<_ClockStat> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Restart resets the clock at once rather than on the next tick.
    widget.controller.addListener(_tick);
  }

  void _tick() => setState(() {});

  @override
  void dispose() {
    _timer.cancel();
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HudStat(
    label: 'Time',
    value: formatDuration(widget.controller.elapsed),
    compact: widget.compact,
    minWidth: widget.compact ? 46 : 54,
  );
}

/// The combo window as a draining gold bar with the seconds left ("2.1s"),
/// under the HUD (reference board). Bound to the game's own combo window
/// ([GameController.comboTimeLeft], the [ScoreKeeper] on the game clock):
/// no timer of its own, so it pauses with the clock and can never disagree
/// with the score.
///
/// Shown only while a match can still extend the streak (from the first
/// match until its window closes) during play; nothing otherwise. Its
/// ticker runs only while it shows and the clock runs; with reduced motion
/// it repaints only when the tenths change.
class ComboTimerBar extends StatefulWidget {
  const ComboTimerBar({super.key, required this.controller, this.compact = false});

  final GameController controller;
  final bool compact;

  @override
  State<ComboTimerBar> createState() => ComboTimerBarState();
}

class ComboTimerBarState extends State<ComboTimerBar> with SingleTickerProviderStateMixin {
  /// Seconds left (0 when hidden), repainted by the ticker.
  final ValueNotifier<double> _left = ValueNotifier(0);
  late final Ticker _ticker;
  bool _shown = false;

  /// Whether the bar's ticker runs (for tests).
  @visibleForTesting
  bool get ticking => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(ComboTimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    _sync();
  }

  bool get _visible {
    final game = widget.controller;
    return game.comboTimeLeft != null && game.state.status == GameStatus.playing && !game.introPlaying;
  }

  double _seconds() {
    final left = widget.controller.comboTimeLeft;
    return left == null ? 0 : math.max(0, left.inMicroseconds / 1e6);
  }

  void _sync() {
    if (!mounted) return;
    final visible = _visible;
    if (visible != _shown) setState(() => _shown = visible);
    _left.value = _seconds();
    final run = visible && widget.controller.clockRunning;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration _) {
    if (!_visible) {
      _sync();
      return;
    }
    final seconds = _seconds();
    // Reduced motion: only when the shown tenths change.
    if (MediaQuery.disableAnimationsOf(context) && (seconds * 10).ceil() == (_left.value * 10).ceil()) return;
    _left.value = seconds;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    final palette = BrainTrainPalette.of(context);
    final window = widget.controller.scoring.rules.comboWindow.inMicroseconds / 1e6;
    final height = widget.compact ? 12.0 : 16.0;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1,
      child: Semantics(
        label: 'Combo time left',
        child: SizedBox(
          width: widget.compact ? 168 : 214,
          height: height,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _TimerBarPainter(
                left: _left,
                window: window,
                palette: palette,
                label: BrainTrainType.scoreValue(size: widget.compact ? 10 : 11.5, color: palette.accentLight),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark pill with a fine gold rim, a gold bar that drains to the left, and
/// the seconds left on the right. Plain fills and strokes, no blur.
class _TimerBarPainter extends CustomPainter {
  _TimerBarPainter({required this.left, required this.window, required this.palette, required this.label})
    : super(repaint: left);

  final ValueNotifier<double> left;
  final double window;
  final BrainTrainPalette palette;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = left.value;
    final text = TextPainter(
      text: TextSpan(text: '${seconds.toStringAsFixed(1)}s', style: label),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final pill = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas
      ..drawRRect(
        pill,
        Paint()..color = palette.hudFill.last.withValues(alpha: 0.88),
      )
      ..drawRRect(
        pill.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = palette.accent.withValues(alpha: 0.55),
      );
    final inset = size.height * 0.3;
    final trackRight = size.width - text.width - inset * 2.2;
    final track = Rect.fromLTRB(inset, inset, trackRight, size.height - inset);
    final radius = Radius.circular(track.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(track, radius), Paint()..color = const Color(0x40000000));
    final fraction = window <= 0 ? 0.0 : (seconds / window).clamp(0.0, 1.0);
    if (fraction > 0) {
      final bar = Rect.fromLTWH(track.left, track.top, math.max(track.height, track.width * fraction), track.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, radius),
        Paint()
          ..shader = LinearGradient(
            colors: [palette.accentDeep, palette.accent, palette.accentLight],
            stops: const [0, 0.55, 1],
          ).createShader(bar),
      );
    }
    text
      ..paint(canvas, Offset(size.width - text.width - inset * 1.2, (size.height - text.height) / 2))
      ..dispose();
  }

  @override
  bool shouldRepaint(_TimerBarPainter old) =>
      old.left != left || old.window != window || old.palette != palette || old.label != label;
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/brand.dart';
import '../../../app/tablet_scale.dart';
import '../../../app/theme.dart';
import '../../../game_engine/state/game_engine.dart';
import '../../../game_engine/state/game_state.dart';
import '../../../game_engine/state/hint_finder.dart';
import '../../../game_engine/validation/solver.dart';
import '../../../rendering/tile_style.dart';
import '../game_controller.dart';
import 'premium_chrome.dart';

/// The first-play tutorial's steps, in order.
enum TutorialStep {
  /// Tap the highlighted free tile.
  tapTile,

  /// It dropped into the tray (highlighted). Next.
  tray,

  /// Tap its twin: the pair strikes and clears.
  tapTwin,

  /// A tray that fills without a match ends the round. Next.
  keepClear,

  /// Clear every pair to win. Let's play.
  win,
}

/// The pair the tutorial teaches with on [engine]'s board: two free tiles
/// that match, the one to tap first first. Null when the tray is not empty
/// (a resumed game) or no pair is free.
///
/// Prefers a symbol whose remaining tiles are all free: taking two of them
/// never makes the board harder (freedom only grows as tiles leave; see
/// [MahjongSolver], [HintFinder.safePairs]). Otherwise the first pair of a
/// short solver search, and failing that any free pair.
TilePair? tutorialPairFor(GameEngine engine) {
  if (engine.state.status != GameStatus.playing || engine.state.tray.isNotEmpty) return null;
  final level = engine.level;
  TilePair pairOf(int a, int b) => (level.tiles[a].tileId, level.tiles[b].tileId);
  final safe = HintFinder.safePairs(engine);
  if (safe.isNotEmpty) return pairOf(safe.first.$1, safe.first.$2);
  // Small boards solve in a few dozen nodes; the budget keeps this quick.
  final solver = MahjongSolver(geometry: engine.geometry, rules: engine.rules, maxNodes: 2000);
  final solved = solver.solve(engine.remainingMask);
  if (solved.solution.isNotEmpty) return pairOf(solved.solution.first.$1, solved.solution.first.$2);
  final freeByKey = <String, List<int>>{};
  for (var index = 0; index < level.tiles.length; index++) {
    if (engine.isFreeIndex(index)) (freeByKey[engine.rules.keyOf(index)] ??= []).add(index);
  }
  for (final free in freeByKey.values) {
    if (free.length >= 2) return pairOf(free[0], free[1]);
  }
  return null;
}

/// Runs the first-play tutorial on the game in play: which step shows, and
/// which tile the player may tap ([GameController.tutorialTarget]). The
/// game's clock waits from [start] until [finish].
///
/// Steps 1 and 3 wait for the player's tap on [pair]'s tiles; those are real
/// moves. After each, the card waits ([waiting]) until the tile has landed
/// or the pair has shattered ([isBusy] false).
class FirstPlayTutorialController extends ChangeNotifier {
  FirstPlayTutorialController({
    required this.game,
    required this.pair,
    required this.isBusy,
    required this.motion,
    required this.onDone,
  });

  final GameController game;

  /// The free matching pair taught with: the first tile, then its twin.
  final TilePair pair;

  /// A tile is in the air, or the tray or a shatter is still moving.
  final bool Function() isBusy;

  /// Notifies when [isBusy] may have changed.
  final Listenable motion;

  /// Runs once, when the tutorial is finished or skipped.
  final VoidCallback onDone;

  TutorialStep _step = TutorialStep.tapTile;
  TutorialStep _after = TutorialStep.tapTile;
  bool _waiting = false;
  bool _started = false;
  bool _done = false;
  bool _disposed = false;

  TutorialStep get step => _step;

  /// A tapped tile is on its way (flight, strike): no card until it is still.
  bool get waiting => _waiting;

  bool get done => _done;

  /// The tile the player should tap now (steps 1 and 3), else null.
  String? get target => _waiting || _done
      ? null
      : switch (_step) {
          TutorialStep.tapTile => pair.$1,
          TutorialStep.tapTwin => pair.$2,
          _ => null,
        };

  /// Holds the game (clock stopped, only [target] tappable) and shows step 1.
  void start() {
    if (_started) return;
    _started = true;
    game
      ..beginTutorial()
      ..tutorialTarget = target
      ..addListener(_onGame);
    motion.addListener(_onMotion);
    notifyListeners();
  }

  void _onGame() {
    if (_done || _waiting) return;
    final state = game.state;
    if (state.status != GameStatus.playing) {
      finish();
    } else if (_step == TutorialStep.tapTile && state.tray.contains(pair.$1)) {
      _waitFor(TutorialStep.tray);
    } else if (_step == TutorialStep.tapTwin && !state.remaining.contains(pair.$2)) {
      _waitFor(TutorialStep.keepClear);
    }
  }

  void _waitFor(TutorialStep next) {
    _waiting = true;
    _after = next;
    game.tutorialTarget = null;
    notifyListeners();
    // The flight starts from the game's event, just after the tap; look
    // again after the next frame in case nothing moves (reduced motion).
    SchedulerBinding.instance.addPostFrameCallback((_) => _onMotion());
  }

  void _onMotion() {
    if (!_waiting || _done || _disposed || isBusy()) return;
    _waiting = false;
    _step = _after;
    game.tutorialTarget = target;
    notifyListeners();
  }

  /// Next on the tray steps; Let's play on the last one.
  void next() {
    if (_done || _waiting) return;
    switch (_step) {
      case TutorialStep.tray:
        _step = TutorialStep.tapTwin;
      case TutorialStep.keepClear:
        _step = TutorialStep.win;
      case TutorialStep.win:
        finish();
        return;
      case TutorialStep.tapTile || TutorialStep.tapTwin:
        return;
    }
    game.tutorialTarget = target;
    notifyListeners();
  }

  /// Let's play, Skip or Android back: normal play goes on (the clock runs).
  void finish() {
    if (_done) return;
    _done = true;
    _waiting = false;
    _detach();
    game.endTutorial();
    notifyListeners();
    onDone();
  }

  void _detach() {
    if (!_started) return;
    game.removeListener(_onGame);
    motion.removeListener(_onMotion);
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_done) _detach();
    super.dispose();
  }
}

/// Coach marks over the real board for [FirstPlayTutorialController]: a dim
/// scrim with rounded, gold-rimmed holes around the tile to tap and/or the
/// tray, and a small card (title, a line or two, Next or Let's play, Skip)
/// placed clear of them.
///
/// Taps reach the board only through the hole of a tile to tap; the rest of
/// the screen is held back (the card's buttons work). Android back skips.
///
/// Static apart from one thin ring that pulses out of a tile's hole (none
/// with [reduceMotion]); the scrim is a path and a few strokes, no blur or
/// layers, and the board below never repaints for it.
class FirstPlayTutorialOverlay extends StatefulWidget {
  const FirstPlayTutorialOverlay({
    super.key,
    required this.controller,
    required this.tileRect,
    required this.trayRect,
    required this.tileStyle,
    required this.reduceMotion,
  });

  final FirstPlayTutorialController controller;

  /// A board tile's face in global (canvas) coordinates, or null before
  /// layout (`BoardViewState.tileFaceRect`).
  final Rect? Function(String tileId) tileRect;

  /// The tray's panel in global (canvas) coordinates (`TrayViewState.panelRect`).
  final Rect? Function() trayRect;

  /// The board's tile style: a tile's hole covers its depth too.
  final TileStyle tileStyle;
  final bool reduceMotion;

  /// The dim around the hole (also the card's frost tint).
  static const Color scrim = Color(0xB0020D08);

  static const String skipLabel = 'Skip';

  /// The pulsing ring around a tile to tap (absent with reduced motion).
  static const Key pulseKey = ValueKey('first-play-tutorial-pulse');

  @override
  State<FirstPlayTutorialOverlay> createState() => _FirstPlayTutorialOverlayState();
}

class _FirstPlayTutorialOverlayState extends State<FirstPlayTutorialOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// The holes, in this overlay's coordinates: first the one to look at (the
  /// tile to tap, or the tray), then the tray while its tile's twin is
  /// wanted. Empty: the last step lights nothing.
  List<RRect> _holes = const [];

  /// Whether [_holes] is known for the current step (nothing shows before).
  bool _ready = false;

  FirstPlayTutorialController get _tutorial => widget.controller;

  @override
  void initState() {
    super.initState();
    _tutorial.addListener(_changed);
  }

  @override
  void didUpdateWidget(FirstPlayTutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _tutorial.removeListener(_changed);
    _pulse.dispose();
    super.dispose();
  }

  /// A new step (or a tap): the board and tray are laid out already, so the
  /// new holes come with the new card, in the same frame.
  void _changed() {
    if (!mounted) return;
    final holes = _measureHoles();
    setState(() {
      _ready = holes != null;
      _holes = holes ?? const [];
    });
    _syncPulse();
  }

  /// Null while the board or tray has not laid out.
  List<RRect>? _measureHoles() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: TabletScale.canvasAbove(box));
    RRect? tray() {
      final panel = widget.trayRect();
      if (panel == null) return null;
      return RRect.fromRectAndRadius(panel.shift(-origin).inflate(4), Radius.circular(panel.height * 0.3 + 4));
    }

    final target = _tutorial.target;
    if (target != null) {
      final face = widget.tileRect(target);
      if (face == null) return null;
      final style = widget.tileStyle;
      final body = Rect.fromLTRB(
        face.left,
        face.top,
        face.right + face.width * style.depthXFraction,
        face.bottom + face.height * style.depthYFraction,
      ).shift(-origin);
      final tile = RRect.fromRectAndRadius(body.inflate(6), Radius.circular(face.width * 0.16 + 6));
      if (_tutorial.step != TutorialStep.tapTwin) return [tile];
      // Its partner waits in the tray: light that too.
      final lit = tray();
      return lit == null ? null : [tile, lit];
    }
    if (!_tutorial.waiting && _tutorial.step == TutorialStep.win) return const [];
    // The tray steps, and while a tile flies to the tray or a pair strikes.
    final lit = tray();
    return lit == null ? null : [lit];
  }

  /// After each frame: follows layout changes, and waits for a first layout.
  void _measure() {
    if (!mounted) return;
    final holes = _measureHoles();
    final ready = holes != null;
    if (ready != _ready || (ready && !listEquals(holes, _holes))) {
      setState(() {
        _ready = ready;
        _holes = holes ?? const [];
      });
    } else if (!ready) {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => _measure())
        ..scheduleFrame();
    }
    _syncPulse();
  }

  /// The ring pulses only around a tile to tap, and never with reduced motion.
  void _syncPulse() {
    final run = _ready && _holes.isNotEmpty && _tutorial.target != null && !widget.reduceMotion;
    if (run && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!run && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rects come from the board and tray after layout: check after paint.
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
    final tutorial = _tutorial;
    final holes = _ready ? _holes : const <RRect>[];
    final focus = holes.firstOrNull;
    final padding = MediaQuery.paddingOf(context);
    final tapStep = tutorial.target != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) tutorial.finish();
      },
      child: _TutorialBarrier(
        passThrough: tapStep ? focus?.outerRect : null,
        child: !_ready
            ? const SizedBox.expand()
            : Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _ScrimPainter(holes: holes)),
                    ),
                  ),
                  if (focus != null && tapStep && !widget.reduceMotion)
                    IgnorePointer(
                      child: RepaintBoundary(
                        key: FirstPlayTutorialOverlay.pulseKey,
                        child: CustomPaint(
                          painter: _PulsePainter(hole: focus, animation: _pulse),
                        ),
                      ),
                    ),
                  if (!tutorial.waiting)
                    CustomSingleChildLayout(
                      delegate: _CardLayout(
                        avoid: [for (final hole in holes) hole.outerRect],
                        insets: EdgeInsets.fromLTRB(16, padding.top + 10, 16, padding.bottom + 10),
                      ),
                      child: _Entrance(
                        key: ValueKey(tutorial.step),
                        reduceMotion: widget.reduceMotion,
                        child: _TutorialCard(step: tutorial.step, onNext: tutorial.next, onSkip: tutorial.finish),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Holds back every pointer except in [passThrough] (the hole of a tile to
/// tap), where it lets the tap reach the board below. Children (the card)
/// are hit first.
class _TutorialBarrier extends SingleChildRenderObjectWidget {
  const _TutorialBarrier({required this.passThrough, required super.child});

  final Rect? passThrough;

  @override
  _RenderTutorialBarrier createRenderObject(BuildContext context) => _RenderTutorialBarrier(passThrough);

  @override
  void updateRenderObject(BuildContext context, _RenderTutorialBarrier renderObject) {
    renderObject.passThrough = passThrough;
  }
}

class _RenderTutorialBarrier extends RenderProxyBox {
  _RenderTutorialBarrier(this.passThrough);

  Rect? passThrough;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (hitTestChildren(result, position: position)) return true;
    if (passThrough?.contains(position) ?? false) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// Puts the card, centred across, in a free band between the holes
/// ([avoid], the first one to look at): the band next to that hole where
/// the card fits (the roomier side if both do; failing that the roomiest
/// band), inside [insets]. Centred on screen without holes.
class _CardLayout extends SingleChildLayoutDelegate {
  _CardLayout({required this.avoid, required this.insets});

  final List<Rect> avoid;
  final EdgeInsets insets;

  static const double gap = 16;
  static const double maxWidth = 380;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: math.max(0, math.min(maxWidth, constraints.maxWidth - insets.horizontal)),
    maxHeight: math.max(0, constraints.maxHeight - insets.vertical),
  );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final top = insets.top, bottom = size.height - insets.bottom, height = child.height;
    var y = top + (bottom - top - height) / 2;
    if (avoid.isNotEmpty) {
      // Free bands between the holes (each with a gap around it), top down.
      final spans = [for (final rect in avoid) (rect.top - gap, rect.bottom + gap)]
        ..sort((a, b) => a.$1.compareTo(b.$1));
      final bands = <(double, double)>[];
      var from = top;
      for (final (start, end) in spans) {
        if (start > from) bands.add((from, start));
        from = math.max(from, end);
      }
      if (bottom > from) bands.add((from, bottom));
      final focus = avoid.first;
      double room((double, double) band) => band.$2 - band.$1;
      double distance((double, double) band) =>
          band.$1 >= focus.center.dy ? band.$1 - focus.bottom - gap : focus.top - gap - band.$2;
      final fitting = bands.where((band) => room(band) >= height).toList()
        ..sort((a, b) {
          final byDistance = distance(a).abs().compareTo(distance(b).abs());
          return byDistance != 0 ? byDistance : room(b).compareTo(room(a));
        });
      final band = fitting.firstOrNull ?? (bands..sort((a, b) => room(b).compareTo(room(a)))).firstOrNull;
      // Hug the focus hole: just below it, or just above it.
      if (band != null) y = band.$1 >= focus.center.dy ? band.$1 : band.$2 - height;
    }
    return Offset((size.width - child.width) / 2, y.clamp(top, math.max(top, bottom - height)));
  }

  @override
  bool shouldRelayout(_CardLayout old) => !listEquals(old.avoid, avoid) || old.insets != insets;
}

/// Each step's card rises in a little (a transform only; none with reduced
/// motion).
class _Entrance extends StatelessWidget {
  const _Entrance({super.key, required this.reduceMotion, required this.child});

  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) => Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    child: child,
  );
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({required this.step, required this.onNext, required this.onSkip});

  final TutorialStep step;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (step) {
      TutorialStep.tapTile => (
        'Tap a free tile',
        'A tile is free when nothing covers it and its left or right side is open.',
      ),
      TutorialStep.tray => ('It drops into your tray', 'Every tile you tap goes into the tray at the top.'),
      TutorialStep.tapTwin => ('Find its twin', 'Two matching tiles in the tray clear together.'),
      TutorialStep.keepClear => (
        'Keep your tray clear',
        'If the tray fills up without a match, the round is over — you can Revive or Restart.',
      ),
      TutorialStep.win => ('Clear every pair to win', 'Match quickly for combos and a higher score. Have fun!'),
    };
    final action = switch (step) {
      TutorialStep.tray || TutorialStep.keepClear => 'Next',
      TutorialStep.win => "Let's play",
      TutorialStep.tapTile || TutorialStep.tapTwin => null,
    };
    final last = step == TutorialStep.win;
    return PremiumPanel(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 18),
      frostTint: FirstPlayTutorialOverlay.scrim,
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  _StepDots(current: step.index, count: TutorialStep.values.length),
                  const Spacer(),
                  // Let's play ends the last step; no Skip beside it.
                  if (!last) _SkipButton(onPressed: onSkip),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(right: 12, top: last ? 0 : 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: _WrappedText(
                      title,
                      balance: true,
                      style: displayText(23, weight: FontWeight.w600).copyWith(height: 1.15),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _WrappedText(
                    body,
                    style: displayText(
                      15.5,
                      color: BrainTrainColors.ivory.withValues(alpha: 0.86),
                      weight: FontWeight.w400,
                    ).copyWith(height: 1.38),
                  ),
                  if (action == null) ...[const SizedBox(height: 12), const _TapHint()],
                  if (action != null) ...[
                    const SizedBox(height: 16),
                    PremiumButton(label: action, primary: true, expand: true, onPressed: onNext),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text that never leaves one word alone on its last line (as narrow cards
/// and large text sizes would): [balance] wraps a title into lines of even
/// length (the narrowest width that keeps its line count); otherwise the
/// width shrinks only as far as it takes to bring a second word down.
class _WrappedText extends StatelessWidget {
  const _WrappedText(this.text, {required this.style, this.balance = false});

  final String text;
  final TextStyle style;
  final bool balance;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final span = TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style));
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);

      /// Line count at [width], and whether the last line holds one word.
      (int, bool) wrapAt(double width) {
        final painter = TextPainter(text: span, textDirection: direction, textScaler: scaler)..layout(maxWidth: width);
        final lines = painter.computeLineMetrics().length;
        final last = painter.getLineBoundary(TextPosition(offset: text.length - 1));
        painter.dispose();
        return (lines, !text.substring(last.start, last.end).trim().contains(' '));
      }

      final max = constraints.maxWidth;
      var width = max;
      final (lines, alone) = max.isFinite ? wrapAt(max) : (1, false);
      if (lines > 1 && balance) {
        var narrow = max / (lines + 1);
        for (var i = 0; i < 10; i++) {
          final mid = (narrow + width) / 2;
          if (wrapAt(mid).$1 <= lines) {
            width = mid;
          } else {
            narrow = mid;
          }
        }
        width = math.min(max, width + 1);
      } else if (lines > 1 && alone) {
        for (var w = max - 4; w > max * 0.6; w -= 4) {
          final (n, stillAlone) = wrapAt(w);
          if (n > lines) break;
          if (!stillAlone) {
            width = w;
            break;
          }
        }
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: width,
          child: Text(text, style: style),
        ),
      );
    },
  );
}

/// "Tap the glowing tile", under the steps that wait for a tap.
class _TapHint extends StatelessWidget {
  const _TapHint();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.touch_app_rounded, size: 19, color: BrandGold.warm),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          'Tap the glowing tile',
          style: displayText(14.5, color: BrandGold.light, weight: FontWeight.w600, spacing: 0.3),
        ),
      ),
    ],
  );
}

/// Where the player is: one gold pill for this step, dots for the others.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step ${current + 1} of $count',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == current ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i == current
                  ? BrandGold.warm
                  : i < current
                  ? BrandGold.base.withValues(alpha: 0.6)
                  : BrainTrainColors.ivory.withValues(alpha: 0.22),
            ),
          ),
      ],
    ),
  );
}

/// A small gold text button, top right of the card.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Skip tutorial',
    excludeSemantics: true,
    onTap: onPressed,
    child: Material(
      type: MaterialType.transparency,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        splashColor: BrandGold.base.withValues(alpha: 0.16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                FirstPlayTutorialOverlay.skipLabel,
                maxLines: 1,
                style: displayText(15.5, color: BrandGold.light, weight: FontWeight.w600, spacing: 0.4),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The dim with its holes: rounded cut-outs, each ringed by a soft gold
/// halo (layered strokes, no blur) and a fine gold rim.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.holes});

  final List<RRect> holes;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    for (final hole in holes) {
      dim.addRRect(hole);
    }
    canvas.drawPath(dim, Paint()..color = FirstPlayTutorialOverlay.scrim);
    for (final hole in holes) {
      for (final (width, alpha) in const [(12.0, 0.05), (7.0, 0.1), (3.5, 0.2)]) {
        canvas.drawRRect(
          hole.inflate(width / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = BrandGold.warm.withValues(alpha: alpha),
        );
      }
      canvas.drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandGold.light, BrandGold.base, BrandGold.warm, BrandGold.light],
          ).createShader(hole.outerRect),
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => !listEquals(old.holes, holes);
}

/// One thin gold ring that grows out of the hole and fades, then rests.
class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.hole, required this.animation}) : super(repaint: animation);

  final RRect hole;
  final Animation<double> animation;

  /// The share of each cycle the ring is visible; the rest is a pause.
  static const double _active = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t >= _active) return;
    final p = t / _active;
    final grow = Curves.easeOutCubic.transform(p);
    canvas.drawRRect(
      hole.inflate(2 + 12 * grow),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 - 1.6 * p
        ..color = BrandGold.light.withValues(alpha: 0.6 * (1 - p) * (1 - p)),
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.hole != hole || old.animation != animation;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/rewarded_ads_controller.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../game_engine/state/game_actions.dart';
import '../../../game_engine/state/game_state.dart';
import '../../common/static_layer.dart';
import '../game_controller.dart';

/// Icon and label of each helper action.
extension GameActionLook on GameAction {
  IconData get icon => switch (this) {
    GameAction.undo => Icons.undo_rounded,
    GameAction.hint => Icons.lightbulb_outline_rounded,
    GameAction.shuffle => Icons.shuffle_rounded,
  };

  String get label => switch (this) {
    GameAction.undo => 'Undo',
    GameAction.hint => 'Hint',
    GameAction.shuffle => 'Shuffle',
  };

  /// "hints", "undos", "shuffles": for "You have no hints left".
  String get plural => switch (this) {
    GameAction.undo => 'undos',
    GameAction.hint => 'hints',
    GameAction.shuffle => 'shuffles',
  };
}

/// How long a spent action's button takes to fade out (at once with reduce
/// motion).
const Duration kSpentFadeDuration = Duration(milliseconds: 240);

/// The bottom action bar (redesign 1.1.0, reference board): Undo, Hint and
/// Shuffle as gold-outlined round buttons with their labels and a badge with
/// the uses left; with none left the badge shows a play mark (a rewarded ad
/// gives one more; a "+" in builds without ads). Restart sits at the right
/// end as a smaller, quieter round button without a badge (it asks first).
///
/// A spent action ([GameController.isSpent]: its free use and its one use
/// for an ad are both gone; owner, 2026-10-17) has no button until a restart:
/// it fades out and leaves an empty place of the same size, so the other
/// buttons never move under the player's finger.
///
/// A button is on only while its action makes sense now
/// ([GameController.isAvailable]: not during the intro, the tutorial or a
/// result card, not with nothing to undo, ...) and no card is open
/// ([blocked]); off buttons are dimmed (colours, not an Opacity layer).
///
/// [compact] (short screens): smaller labels. Labels sit beside the buttons
/// when [compact] or with a [disc] size (one row as tall as the disc), else
/// under them.
class GameActionBar extends StatelessWidget {
  const GameActionBar({
    super.key,
    required this.controller,
    required this.ads,
    required this.blocked,
    required this.onAction,
    required this.onRestart,
    this.compact = false,
    this.disc,
  });

  final GameController controller;

  /// For the badge at 0 uses: an ad mark, or "+" when this build has none.
  final RewardedAdsController ads;

  /// True while a card is open over the board (restart, ad offer).
  final ValueListenable<bool> blocked;
  final ValueChanged<GameAction> onAction;
  final VoidCallback onRestart;
  final bool compact;

  /// Disc diameter of the action buttons (labels beside); null: the
  /// [compact] or roomy default.
  final double? disc;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: ListenableBuilder(
      listenable: Listenable.merge([controller, blocked, ads]),
      builder: (context, _) {
        final open = !blocked.value;
        final restartOn =
            open && controller.state.status == GameStatus.playing && !controller.introPlaying;
        final buttons = [
          for (final action in GameAction.values)
            _ActionSlot(
              key: ValueKey('slot-${action.name}'),
              spent: controller.isSpent(action),
              // The live button (fade null), or its spent look fading out:
              // off, no badge, keyed apart so finders see it is gone.
              button: (fade) => GameActionButton(
                key: ValueKey(fade == null ? 'action-${action.name}' : 'action-${action.name}-spent'),
                icon: action.icon,
                label: action.label,
                usesLeft: fade == null ? controller.usesLeft(action) : null,
                adRefill: !ads.off,
                compact: compact,
                disc: disc,
                fade: fade ?? 1,
                onPressed: fade == null && open && controller.isAvailable(action) ? () => onAction(action) : null,
              ),
            ),
        ];
        final restart = GameActionButton(
          key: const ValueKey('action-restart'),
          icon: Icons.restart_alt_rounded,
          label: 'Restart',
          tooltip: 'Restart',
          semanticsLabel: 'Restart level',
          quiet: true,
          compact: compact,
          disc: disc,
          onPressed: restartOn ? onRestart : null,
        );
        // Drawn once into an image until a button changes (or its ink
        // plays, or a spent one fades out): the leaves drifting behind would
        // otherwise redraw the buttons' shadows and text every frame.
        return StaticLayer(
          overflow: const EdgeInsets.all(12),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                for (final button in buttons) Expanded(child: Center(child: button)),
                SizedBox(width: compact || disc != null ? 50 : 70, child: Center(child: restart)),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// One action's place in the bar: its live button, or once the action is
/// spent a placeholder of the same size (the button's spent look, laid out
/// but never painted, with no taps, no ink and no semantics), so the other
/// buttons and Restart stay put. Spent during play, the button first fades
/// out over [kSpentFadeDuration] (its colours, not an Opacity layer; the
/// ticker runs only then); with reduce motion, or already spent when the
/// bar is built (a resumed save), it is gone at once. Back after a restart.
class _ActionSlot extends StatefulWidget {
  const _ActionSlot({super.key, required this.spent, required this.button});

  final bool spent;

  /// The live button for a null fade, else the spent look at that fade (1
  /// shown, 0 gone).
  final Widget Function(double? fade) button;

  @override
  State<_ActionSlot> createState() => _ActionSlotState();
}

class _ActionSlotState extends State<_ActionSlot> with SingleTickerProviderStateMixin {
  /// The spent look's fade: 0 (gone) unless it is fading out.
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: kSpentFadeDuration);
  }

  @override
  void didUpdateWidget(_ActionSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spent == oldWidget.spent) return;
    if (widget.spent && !MediaQuery.disableAnimationsOf(context)) {
      _fade.reverse(from: 1);
    } else {
      _fade.value = 0;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.spent) return widget.button(null);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _fade,
          // Laid out at 0 (keeps the place), painted only while fading.
          builder: (context, _) => Visibility(
            visible: _fade.value > 0,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: widget.button(_fade.value),
          ),
        ),
      ),
    );
  }
}

/// A gold-outlined round button with a label (under it, or beside it when
/// [compact]) and, unless [quiet], a gold badge with [usesLeft] (a play mark
/// at 0 with [adRefill], else "+"). [quiet]: smaller, a fainter rim, no
/// badge and no visible label ([tooltip] and [semanticsLabel] name it).
/// [onPressed] null: off, dimmed.
class GameActionButton extends StatelessWidget {
  const GameActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.usesLeft,
    this.adRefill = true,
    this.quiet = false,
    this.compact = false,
    this.disc,
    this.fade = 1,
    this.tooltip,
    this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Uses left (the badge); null: no badge.
  final int? usesLeft;

  /// At 0 uses, the badge offers an ad (a play mark) rather than a "+".
  final bool adRefill;
  final bool quiet;
  final bool compact;

  /// Disc diameter (labels beside); null: the [compact] or roomy default.
  final double? disc;

  /// How much of the button shows: 1 fully, down to 0 as a spent action's
  /// button fades out (its colours' alpha, not an Opacity layer).
  final double fade;
  final String? tooltip;
  final String? semanticsLabel;

  bool get _beside => compact || disc != null;

  double get _disc => switch (disc) {
    final double d => quiet ? d - 6 : d,
    null => quiet ? (compact ? 34 : 40) : (compact ? 36 : 50),
  };

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final enabled = onPressed != null;
    final gold = palette.accent;
    Color faded(Color c) => fade >= 1 ? c : c.withValues(alpha: c.a * fade.clamp(0, 1));
    final rim = faded(
      quiet ? palette.text.withValues(alpha: enabled ? 0.5 : 0.2) : gold.withValues(alpha: enabled ? 0.95 : 0.32),
    );
    final ink = faded(
      quiet
          ? palette.text.withValues(alpha: enabled ? 0.82 : 0.3)
          : palette.accentLight.withValues(alpha: enabled ? 1 : 0.35),
    );
    final uses = usesLeft;
    final discWidget = SizedBox.square(
      dimension: _disc,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: [
                    faded(palette.hudFill.first.withValues(alpha: quiet ? 0.6 : 0.92)),
                    faded(palette.hudFill.last.withValues(alpha: quiet ? 0.7 : 0.96)),
                  ],
                ),
                border: Border.all(color: rim, width: quiet ? 1.1 : 1.6),
                boxShadow: enabled && !quiet ? [BoxShadow(color: palette.shadow, blurRadius: 8, offset: const Offset(0, 3))] : null,
              ),
              child: Icon(icon, color: ink, size: _disc * (quiet ? 0.52 : 0.5)),
            ),
          ),
          if (!quiet && uses != null)
            Positioned(
              right: compact ? -5 : -4,
              top: compact ? -5 : -4,
              child: _UsesBadge(uses: uses, adRefill: adRefill, enabled: enabled, size: compact ? 17 : 20),
            ),
        ],
      ),
    );
    final text = quiet
        ? null
        : Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: BrainTrainType.button(
              size: compact ? 12.5 : 13.5,
              color: faded(palette.text.withValues(alpha: enabled ? 0.95 : 0.4)),
            ).copyWith(
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: faded(palette.textShadow), blurRadius: 3, offset: const Offset(0, 1))],
            ),
          );
    final content = text == null
        ? discWidget
        : _beside
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              discWidget,
              const SizedBox(width: 6),
              // Shrinks rather than clips on a narrow phone at a large text size.
              Flexible(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: FittedBox(fit: BoxFit.scaleDown, child: text),
                ),
              ),
            ],
          )
        : Column(mainAxisSize: MainAxisSize.min, children: [discWidget, const SizedBox(height: 4), text]);
    final semantics = semanticsLabel ??
        (uses == null
            ? label
            : uses > 0
            ? '$label, $uses left'
            : adRefill
            ? '$label, watch an ad for one more'
            : '$label, none left');
    // A round ripple from the tap, unclipped: the theme's sparkle would fill
    // the button's whole box (disc and label) as a pale rectangle.
    final button = InkResponse(
      onTap: onPressed,
      radius: _disc * 0.75,
      splashFactory: InkRipple.splashFactory,
      splashColor: gold.withValues(alpha: 0.22),
      highlightColor: const Color(0x00000000),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4, vertical: disc != null ? 2 : 4),
        child: content,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantics,
      excludeSemantics: true,
      onTap: onPressed,
      // Only the quiet button has no visible label to repeat.
      child: quiet || tooltip != null
          ? Tooltip(message: tooltip ?? label, excludeFromSemantics: true, child: button)
          : button,
    );
  }
}

/// The gold disc on a button's corner: the uses left, or (none left) a play
/// mark for a rewarded ad or a "+".
class _UsesBadge extends StatelessWidget {
  const _UsesBadge({required this.uses, required this.adRefill, required this.enabled, required this.size});

  final int uses;
  final bool adRefill;
  final bool enabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final fill = palette.primaryButtonFill;
    final ink = palette.textOnGold.withValues(alpha: enabled ? 1 : 0.6);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [for (final c in fill) enabled ? c : c.withValues(alpha: c.a * 0.5)],
        ),
        border: Border.all(color: palette.primaryButtonEdge.withValues(alpha: enabled ? 0.9 : 0.4), width: 0.8),
      ),
      alignment: Alignment.center,
      child: uses > 0
          ? Text(
              '$uses',
              // A digit in a small disc: it grows a little with the text size.
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
              style: BrainTrainType.scoreValue(size: size * 0.62, color: ink).copyWith(height: 1),
            )
          : Icon(adRefill ? Icons.play_arrow_rounded : Icons.add_rounded, size: size * 0.82, color: ink),
    );
  }
}

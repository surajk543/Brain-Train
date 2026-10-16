import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/rewarded_ads_controller.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../data/progress_repository.dart';
import '../../../game_engine/scoring/score_format.dart';
import '../../../game_engine/state/game_actions.dart';
import '../../../platform/rewarded_ads.dart';
import '../game_controller.dart';
import 'action_bar.dart';
import 'game_hud.dart';
import 'premium_chrome.dart';
import 'win_trophy.dart';

/// Notes under the Tray full card's Revive button while it waits for an ad.
const String kReviveLoadingNote = 'Loading an ad…';
const String kReviveOfflineNote = 'Connect to the internet to watch an ad and revive';
const String kReviveDismissedNote = 'Watch the ad to the end to revive.';

/// Notes on the "Watch an ad for +1 …?" card while it waits for an ad.
const String kRefillLoadingNote = 'Loading an ad…';
const String kRefillOfflineNote = 'Connect to the internet to watch an ad';

/// The note after an ad for [action] closed before its reward.
String refillDismissedNote(GameAction action) => 'Watch the ad to the end to get +1 ${action.label}.';

/// A card over the dimmed board: the scrim fades in from the top, the card
/// (a [PremiumPanel], or the bare [child] for [bare] screens such as Level
/// Complete) is centred and scrolls if the screen is too short.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({super.key, required this.child, this.bare = false, this.topInset = 0, this.maxWidth = 380});

  final Widget child;

  /// No card panel: [child] sits straight on a deeper scrim with a warm
  /// light behind its top (the Level Complete screen).
  final bool bare;

  /// Status bar height the overlay extends under; the content stays below.
  final double topInset;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final scrim = palette.overlayScrim;
    final content = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, (bare ? 8 : 16) + topInset, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: bare
              ? child
              : PremiumPanel(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                  // The scrim is between the backdrop and the card.
                  frostTint: scrim.withValues(alpha: scrim.a * 0.95),
                  child: child,
                ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bare
              ? [
                  scrim.withValues(alpha: 0.9),
                  scrim.withValues(alpha: 0.82),
                  scrim.withValues(alpha: 0.9),
                ]
              : [scrim.withValues(alpha: scrim.a * 0.7), scrim, scrim],
          stops: bare ? const [0, 0.5, 1] : const [0, 0.02, 1],
        ),
      ),
      child: CustomPaint(
        // Warm light behind the trophy (a gradient, no blur).
        painter: bare ? _WarmLightPainter(palette.accent) : null,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarmLightPainter extends CustomPainter {
  const _WarmLightPainter(this.gold);

  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.2);
    final radius = size.shortestSide * 0.75;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [gold.withValues(alpha: 0.24), gold.withValues(alpha: 0.07), gold.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_WarmLightPainter old) => old.gold != gold;
}

/// A card's heading (Playfair, ivory) and its line of text (Manrope).
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PremiumEmblem(icon: icon, size: 64),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: BrainTrainType.heading(size: 26, color: palette.text),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: BrainTrainType.body(size: 15, color: palette.textMuted),
        ),
        const SizedBox(height: 14),
        const PremiumDivider(horizontal: true),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// A note under a button that waits for an ad: a spinner while it loads.
class _AdNote extends StatelessWidget {
  const _AdNote({required this.note, required this.loading, required this.reduceMotion});

  final String note;
  final bool loading;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading && !reduceMotion) ...[
              // Its own layer: the spinner never repaints the card.
              RepaintBoundary(
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: palette.accentLight),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                note,
                textAlign: TextAlign.center,
                style: BrainTrainType.body(size: 14, color: palette.accentLight, weight: FontWeight.w600)
                    .copyWith(height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The note for an ad's [status] (null: none), and whether it is loading.
(String?, bool) _adNoteFor(
  RewardedAdStatus status, {
  required bool busy,
  required bool dismissed,
  required String loading,
  required String offline,
  required String dismissedNote,
}) {
  if (busy) return (null, false);
  return switch (status) {
    RewardedAdStatus.loading => (loading, true),
    RewardedAdStatus.offline => (offline, false),
    RewardedAdStatus.ready when dismissed => (dismissedNote, false),
    _ => (null, false),
  };
}

/// The Level Complete screen (reference board): the trophy, "Level
/// Complete!" in large gold Playfair, a dark translucent results panel with
/// a fine gold rim (final score and best combo in gold) from the game's
/// [GameController.winSummary], then Next Level (gold), Level Select and a
/// quiet Replay. The last level says every level is done instead of Next
/// Level. Each button works once (the screen guards against double taps).
class LevelCompleteView extends StatelessWidget {
  const LevelCompleteView({
    super.key,
    required this.controller,
    required this.hasNext,
    required this.onNext,
    required this.onLevelSelect,
    required this.onReplay,
    this.compact = false,
  });

  final GameController controller;
  final bool hasNext;
  final VoidCallback? onNext;
  final VoidCallback? onLevelSelect;
  final VoidCallback? onReplay;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    // The saved record lands a moment after the win: until then, the live
    // figures (the same numbers, without the record).
    final summary = controller.winSummary ?? controller.summary;
    final record = summary.record;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WinTrophy(width: compact ? 132 : 180),
        Semantics(
          header: true,
          child: Text(
            'Level Complete!',
            textAlign: TextAlign.center,
            style: BrainTrainType.title(size: compact ? 32 : 38).copyWith(
              // Bright gold from the top, deepening toward the baseline.
              foreground: Paint()
                ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFFFFF1C8), palette.accent, const Color(0xFFD49A3A)],
                  stops: const [0.18, 0.55, 0.95],
                ).createShader(Rect.fromLTWH(0, 0, 10, (compact ? 32 : 38) * 1.15)),
              shadows: [Shadow(color: palette.textShadow, blurRadius: 6, offset: const Offset(0, 2))],
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        _ResultsPanel(summary: summary, record: record, compact: compact),
        SizedBox(height: compact ? 14 : 18),
        if (hasNext)
          PremiumButton(
            label: 'Next Level',
            primary: true,
            expand: true,
            trailingIcon: Icons.chevron_right_rounded,
            onPressed: onNext,
          )
        else
          // The last level: every level is done (owner: say new ones are coming).
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'You have completed every level!\nNew levels are coming soon.',
              textAlign: TextAlign.center,
              style: BrainTrainType.body(size: 15.5, color: palette.accentLight, weight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 10),
        PremiumButton(
          label: 'Level Select',
          expand: true,
          trailingIcon: Icons.chevron_right_rounded,
          onPressed: onLevelSelect,
        ),
        const SizedBox(height: 2),
        PremiumButton(label: 'Replay', primary: false, quiet: hasNext, expand: true, onPressed: onReplay),
      ],
    );
  }
}

/// Final score, time, best combo, pairs and the helpers used, one row each
/// between fine gold separators.
class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({required this.summary, required this.record, required this.compact});

  final GameSummary summary;
  final LevelRecord? record;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = BrainTrainPalette.of(context);
    final rowHeight = compact ? 30.0 : 36.0;
    final label = BrainTrainType.body(size: compact ? 14.5 : 15.5, color: palette.text.withValues(alpha: 0.9));
    final value = BrainTrainType.scoreValue(size: compact ? 16 : 17.5, color: palette.text).copyWith(
      fontWeight: FontWeight.w700,
    );
    final gold = value.copyWith(color: palette.accent, fontWeight: FontWeight.w800);
    Widget row(String name, String figure, {Widget? lead, TextStyle? style, Key? key}) => ConstrainedBox(
      key: key,
      constraints: BoxConstraints(minHeight: rowHeight),
      child: Semantics(
        label: '$name $figure',
        excludeSemantics: true,
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 8)],
            Expanded(child: Text(name, style: label)),
            const SizedBox(width: 12),
            Text(figure, style: style ?? value),
          ],
        ),
      ),
    );
    final best = record?.bestScore;
    final newBest = summary.newBestScore;
    final rows = <Widget>[
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 50 : 60),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Final Score', style: BrainTrainType.levelName(size: compact ? 19 : 21, color: palette.text)),
                  if (newBest)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'New best!',
                        style: BrainTrainType.hudLabel(size: 11, color: palette.accentLight).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  // The level's best when this game did not reach it.
                  else if (best != null && best > summary.score)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Best ${formatScore(best)}', style: BrainTrainType.body(size: 12.5, color: palette.textMuted)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: 'Final score ${formatScore(summary.score)}',
              excludeSemantics: true,
              child: Text(
                formatScore(summary.score),
                style: BrainTrainType.scoreValue(size: compact ? 26 : 30, color: palette.accent),
              ),
            ),
          ],
        ),
      ),
      row('Completion Time', formatDuration(summary.time)),
      row(
        'Best Combo',
        '×${summary.bestCombo}',
        lead: CustomPaint(size: const Size(18, 14), painter: _CrownPainter(palette.accent)),
        style: gold,
      ),
      row('Pairs Matched', '${summary.matchedPairs} / ${summary.totalPairs}'),
      row('Hints Used', '${summary.hintsUsed}'),
      row('Shuffles Used', '${summary.shufflesUsed}'),
      row('Undos Used', '${summary.undosUsed}'),
    ];
    return PremiumPanel(
      radius: 18,
      padding: EdgeInsets.fromLTRB(18, compact ? 4 : 6, 18, compact ? 4 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const PremiumDivider(horizontal: true),
            row,
          ],
        ],
      ),
    );
  }
}

/// A small gold crown (Best Combo), drawn: three points on a band.
class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.gold);

  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final crown = Path()
      ..moveTo(w * 0.06, h * 0.28)
      ..lineTo(w * 0.3, h * 0.55)
      ..lineTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.7, h * 0.55)
      ..lineTo(w * 0.94, h * 0.28)
      ..lineTo(w * 0.84, h * 0.82)
      ..lineTo(w * 0.16, h * 0.82)
      ..close();
    canvas
      ..drawPath(crown, Paint()..color = gold)
      ..drawRect(Rect.fromLTRB(w * 0.16, h * 0.88, w * 0.84, h), Paint()..color = gold);
    for (final x in [0.06, 0.5, 0.94]) {
      canvas.drawCircle(Offset(w * x, x == 0.5 ? h * 0.08 : h * 0.28), w * 0.07, Paint()..color = gold);
    }
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.gold != gold;
}

/// Shown when the tray fills up: revive (the tray's tiles go back to the
/// board) or start the level again. The HUD's Back button stays available.
///
/// Revive plays a rewarded ad first (owner): it is off while no ad is loaded
/// (a note says it is loading, or that the internet is needed) and while one
/// is on screen. Restart always works.
class TrayFullCard extends StatelessWidget {
  const TrayFullCard({
    super.key,
    required this.ads,
    required this.adInFlight,
    required this.lastAd,
    required this.reduceMotion,
    required this.onRevive,
    required this.onRestart,
  });

  final RewardedAdsController ads;
  final ValueListenable<bool> adInFlight;
  final ValueListenable<RewardedAdResult?> lastAd;
  final bool reduceMotion;
  final VoidCallback onRevive;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ads, adInFlight, lastAd]),
    builder: (context, _) {
      final status = ads.status;
      final busy = adInFlight.value;
      final canRevive = !busy && (status == RewardedAdStatus.off || status == RewardedAdStatus.ready);
      final (note, loading) = _adNoteFor(
        status,
        busy: busy,
        dismissed: lastAd.value == RewardedAdResult.dismissed,
        loading: kReviveLoadingNote,
        offline: kReviveOfflineNote,
        dismissedNote: kReviveDismissedNote,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(
            icon: Icons.inventory_2_outlined,
            title: 'Tray full',
            body: ads.off
                ? 'The tray filled up without a match. Revive to put these tiles back on the board, or start again.'
                : 'The tray filled up without a match. Watch a short ad to revive and put these tiles back on the board, or start again.',
          ),
          PremiumButton(
            label: 'Revive',
            icon: ads.off ? null : Icons.ondemand_video_rounded,
            primary: true,
            expand: true,
            onPressed: canRevive ? onRevive : null,
          ),
          if (note != null) _AdNote(note: note, loading: loading, reduceMotion: reduceMotion),
          const SizedBox(height: 10),
          PremiumButton(label: 'Restart', expand: true, onPressed: onRestart),
        ],
      );
    },
  );
}

/// Asks before starting the level over: moves, tray and time are lost.
class RestartConfirmCard extends StatelessWidget {
  const RestartConfirmCard({super.key, required this.onRestart, required this.onKeepPlaying});

  final VoidCallback onRestart;
  final VoidCallback onKeepPlaying;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _CardHeader(
        icon: Icons.restart_alt_rounded,
        title: 'Restart this level?',
        body: 'Your score and time start over.',
      ),
      PremiumButton(label: 'Restart', primary: true, expand: true, onPressed: onRestart),
      const SizedBox(height: 4),
      PremiumButton(label: 'Keep playing', quiet: true, expand: true, onPressed: onKeepPlaying),
    ],
  );
}

/// "Watch an ad for +1 Hint?": an Undo, Hint or Shuffle with no use left
/// offers one more for a rewarded ad (owner, 1.1.0). Like Revive: the button
/// is off while no ad is loaded (a note says it is loading, or that the
/// internet is needed) and while one is on screen; the use is granted only
/// once the reward is earned.
class ActionRefillCard extends StatelessWidget {
  const ActionRefillCard({
    super.key,
    required this.action,
    required this.ads,
    required this.adInFlight,
    required this.lastAd,
    required this.reduceMotion,
    required this.onWatch,
    required this.onCancel,
  });

  final GameAction action;
  final RewardedAdsController ads;
  final ValueListenable<bool> adInFlight;
  final ValueListenable<RewardedAdResult?> lastAd;
  final bool reduceMotion;
  final VoidCallback onWatch;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ads, adInFlight, lastAd]),
    builder: (context, _) {
      final status = ads.status;
      final busy = adInFlight.value;
      final (note, loading) = _adNoteFor(
        status,
        busy: busy,
        dismissed: lastAd.value == RewardedAdResult.dismissed,
        loading: kRefillLoadingNote,
        offline: kRefillOfflineNote,
        dismissedNote: refillDismissedNote(action),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardHeader(
            icon: action.icon,
            title: 'Watch an ad for +1 ${action.label}?',
            body: 'You have no ${action.plural} left in this level.',
          ),
          PremiumButton(
            label: 'Watch ad',
            icon: Icons.ondemand_video_rounded,
            primary: true,
            expand: true,
            onPressed: !busy && status == RewardedAdStatus.ready ? onWatch : null,
          ),
          if (note != null) _AdNote(note: note, loading: loading, reduceMotion: reduceMotion),
          const SizedBox(height: 4),
          PremiumButton(label: 'Not now', quiet: true, expand: true, onPressed: busy ? null : onCancel),
        ],
      );
    },
  );
}

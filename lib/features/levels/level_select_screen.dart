import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../app/typography.dart';
import '../../content/content_snapshot.dart';
import '../../content/level_manifest.dart';
import '../../data/progress_repository.dart';
import '../common/all_levels_complete_note.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';
import '../common/static_layer.dart';
import '../gameplay/game_screen.dart' show formatDuration;
import '../../game_engine/models/level_rules.dart';
import '../../game_engine/scoring/score_format.dart';
import '../home/home_screen.dart';
import 'difficulty_style.dart';
import 'level_loader.dart';

enum LevelState { open, inProgress, completed, locked }

/// Levels (the lobby's Levels button): the level to play next in a panel at
/// the top, and below it only the levels already completed (owner: no list
/// of all levels, no locked levels), in order, as a lazily built list to
/// replay from, each with its best time and when it was completed. A level
/// unlocks when the previous one is won. Every colour comes from
/// [LobbyTheme].
///
/// Each row is flattened by its own [StaticLayer] (the leaves keep moving
/// behind the list), and only the rows on screen are built.
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  /// Each level's state under the lock rule: the first level, a won level
  /// and the level after a won level are playable.
  static List<LevelState> statesFor(
    List<LevelManifestEntry> entries,
    Map<String, LevelRecord> completed,
    String? inProgressLevelId,
  ) => [
    for (var i = 0; i < entries.length; i++)
      if (completed.containsKey(entries[i].levelId))
        LevelState.completed
      else if (i != 0 && !completed.containsKey(entries[i - 1].levelId))
        LevelState.locked
      else if (entries[i].levelId == inProgressLevelId)
        LevelState.inProgress
      else
        LevelState.open,
  ];

  /// The level to offer: the game in progress, else the first unlocked level
  /// not yet won, else the last level.
  static int focusIndex(List<LevelState> states) {
    final inProgress = states.indexOf(LevelState.inProgress);
    if (inProgress >= 0) return inProgress;
    final open = states.indexOf(LevelState.open);
    return open >= 0 ? open : math.max(0, states.length - 1);
  }

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  static const double _padding = 16, _spacing = 10;

  bool _navigating = false;

  Future<void> _open(WidgetBuilder builder) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    } finally {
      if (mounted) _navigating = false;
    }
  }

  // Downloads the level first when it is not on the device.
  void _play(ContentSnapshot snapshot, LevelManifestEntry entry, SavedGame? resume) =>
      _open((_) => LevelLoaderScreen(entry: entry, resume: resume));

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final lobby = LobbyTheme.of(context);
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      extendBodyBehindAppBar: true,
      appBar: const LobbyAppBar(title: 'Levels'),
      body: LobbyBackground(
        variant: LobbySceneVariant.subScreen,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([services.content, services.progress]),
            builder: (context, _) {
              final snapshot = services.content.snapshot;
              final entries = snapshot.playableEntries;
              final completed = services.progress.completed();
              final resume = HomeScreen.resumable(services);
              final states = LevelSelectScreen.statesFor(entries, completed, resume?.$1.levelId);
              final focus = LevelSelectScreen.focusIndex(states);
              final done = [
                for (var i = 0; i < entries.length; i++)
                  if (states[i] == LevelState.completed) i,
              ];
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      if (entries.isNotEmpty && done.length == entries.length)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(_padding, 8, _padding, 6),
                          child: AllLevelsCompleteNote(levelCount: entries.length),
                        )
                      else if (entries.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(_padding, 8, _padding, 6),
                          child: _FocusPanel(
                            entry: entries[focus],
                            state: states[focus],
                            // Manifest metadata: the level file may not be on the device.
                            tileCount: entries[focus].tileCount ?? 0,
                            trayCapacity: entries[focus].trayCapacity ?? kDefaultTrayCapacity,
                            won: completed.length,
                            total: entries.length,
                            onTap: () => _play(
                              snapshot,
                              entries[focus],
                              states[focus] == LevelState.inProgress ? resume!.$2 : null,
                            ),
                          ),
                        ),
                      if (done.isNotEmpty) const _SectionLabel('Completed'),
                      Expanded(
                        child: done.isEmpty
                            ? const _NoneCompleted()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(_padding, 2, _padding, 28),
                                // Each row is its own StaticLayer (a repaint boundary).
                                addRepaintBoundaries: false,
                                itemExtent: math.max(84, 60 + 26 * textScale),
                                itemCount: done.length,
                                itemBuilder: (context, k) {
                                  final entry = entries[done[k]];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: _spacing),
                                    child: CompletedLevelRow(
                                      key: ValueKey(entry.levelId),
                                      entry: entry,
                                      record: completed[entry.levelId]!,
                                      tileCount: entry.tileCount ?? 0,
                                      onTap: () => _play(snapshot, entry, null),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One completed level: number, title, tier and size, the best time it was
/// finished in and when it was last completed. Tapping it replays the level.
class CompletedLevelRow extends StatelessWidget {
  const CompletedLevelRow({super.key, required this.entry, required this.record, required this.tileCount, this.onTap});

  final LevelManifestEntry entry;
  final LevelRecord record;
  final int tileCount;
  final VoidCallback? onTap;

  /// "Oct 16, 2026 · 11:33 AM" in the device's locale and clock format.
  static String completedLabel(BuildContext context, DateTime at) {
    final l10n = MaterialLocalizations.of(context);
    final local = at.toLocal();
    final time = l10n.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '${l10n.formatShortMonthDay(local)}, ${l10n.formatYear(local)} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final difficulty = entry.difficulty == null ? null : DifficultyStyle.of(entry.difficulty!);
    final time = formatDuration(Duration(milliseconds: record.bestTimeMs));
    final when = completedLabel(context, record.completedAt);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: lobby.panelBorder),
    );
    final detail = BrainTrainType.body(size: 11.5, color: lobby.panelMuted).copyWith(height: 1.25, letterSpacing: 0.2);
    return Semantics(
      button: true,
      label:
          'Level ${entry.order}, ${entry.title}${difficulty == null ? '' : ', ${difficulty.label}'}, completed, '
          'best time $time, best score ${record.bestScore ?? 'none'}, completed $when',
      excludeSemantics: true,
      child: StaticLayer(
        overflow: const EdgeInsets.fromLTRB(8, 6, 8, 12),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(lobby.panelFill, const Color(0xFFFFFFFF), 0.05)!, lobby.panelFill],
            ),
            shadows: [BoxShadow(color: lobby.secondaryShadow, blurRadius: 6, offset: const Offset(0, 3))],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              splashColor: lobby.panelAccent.withValues(alpha: 0.18),
              highlightColor: lobby.panelAccent.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            child: Text(
                              '${entry.order}',
                              style: BrainTrainType.scoreValue(size: 21, color: lobby.panelText),
                            ),
                          ),
                          Icon(Icons.check_circle_rounded, size: 14, color: lobby.panelAccent),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.title,
                            style: BrainTrainType.levelName(size: 16, color: lobby.panelText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              if (difficulty != null) ...[
                                DifficultyBadge(label: difficulty.label, color: difficulty.color),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  '$tileCount tiles',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: detail,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Scales down rather than overflow with large text or wide
                    // date formats.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 124),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, size: 15, color: lobby.panelAccent),
                                const SizedBox(width: 4),
                                Text(time, style: BrainTrainType.scoreValue(size: 16, color: lobby.panelAccent)),
                              ],
                            ),
                            Text(
                              record.bestScore == null ? '—' : formatScore(record.bestScore!),
                              style: BrainTrainType.scoreValue(size: 12.5, color: lobby.panelAccent).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(when, maxLines: 1, style: detail.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small outlined pill with the tier's label in its colour.
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.label, required this.color, this.fontSize = 9.5});

  final String label;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: color.withValues(alpha: 0.14),
      border: Border.all(color: color.withValues(alpha: 0.7), width: 0.9),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: BrainTrainType.body(size: fontSize, color: color, weight: FontWeight.w800).copyWith(letterSpacing: 0.6),
      ),
    ),
  );
}

/// The level to play next, above the grid: number, title, tier, board size
/// and overall progress. Tapping it plays the level.
class _FocusPanel extends StatelessWidget {
  const _FocusPanel({
    required this.entry,
    required this.state,
    required this.tileCount,
    required this.trayCapacity,
    required this.won,
    required this.total,
    required this.onTap,
  });

  final LevelManifestEntry entry;
  final LevelState state;
  final int tileCount;
  final int trayCapacity;
  final int won;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final difficulty = entry.difficulty == null ? null : DifficultyStyle.of(entry.difficulty!);
    final action = switch (state) {
      LevelState.inProgress => 'Continue',
      LevelState.completed => 'Replay',
      _ => 'Play',
    };
    return Semantics(
      button: true,
      label: '$action level ${entry.order}, ${entry.title}. $won of $total levels won',
      excludeSemantics: true,
      child: LobbyPanel(
        onTap: onTap,
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            _Medallion(order: entry.order),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: BrainTrainType.levelName(size: 20, color: lobby.panelText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (difficulty != null)
                        DifficultyBadge(label: difficulty.label, color: difficulty.color, fontSize: 10),
                      Text(
                        '$tileCount tiles · $trayCapacity-slot tray',
                        style: BrainTrainType.body(size: 12.5, color: lobby.panelMuted).copyWith(letterSpacing: 0.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$won of $total won',
                    style: BrainTrainType.body(size: 11.5, color: lobby.panelMuted).copyWith(letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_fill_rounded, color: lobby.panelAccent, size: 30),
          ],
        ),
      ),
    );
  }
}

/// "COMPLETED" above the list of completed levels.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: BrainTrainType.hudLabel(size: 12, color: lobby.panelAccent).copyWith(
              shadows: [Shadow(color: lobby.textShadow, blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: lobby.panelBorder.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

/// Shown below the panel before any level is won.
class _NoneCompleted extends StatelessWidget {
  const _NoneCompleted();

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: Text(
          'No levels completed yet.\nWin a level and it shows up here.',
          textAlign: TextAlign.center,
          style: BrainTrainType.body(size: 14, color: lobby.panelMuted).copyWith(
            shadows: [Shadow(color: lobby.textShadow, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

/// Gold coin with the level number.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.order});

  final int order;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: lobby.primaryFill),
        border: Border.all(color: lobby.primaryEdge, width: 1.2),
        boxShadow: [BoxShadow(color: lobby.textShadow, blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          child: Text(
            '$order',
            style: BrainTrainType.scoreValue(size: 19, color: lobby.primaryText),
          ),
        ),
      ),
    );
  }
}

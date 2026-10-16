import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../content/level_manifest.dart';
import '../../data/progress_repository.dart';
import '../common/all_levels_complete_note.dart';
import '../common/lobby_background.dart';
import '../levels/level_loader.dart';
import '../levels/level_select_screen.dart';
import '../settings/settings_screen.dart';
import 'widgets/lobby_buttons.dart';
import 'widgets/lobby_footer.dart';
import 'widgets/lobby_play_games.dart';
import 'widgets/lobby_tagline.dart';

/// The lobby: "Train your brain" on frosted glass, Play/Continue, Levels
/// and Settings, and the content status, over the night garden.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// A resumable saved game in the current content, if any. Only the highest
  /// level ([nextLevel]) resumes; a save of any other level is ignored.
  static (LevelManifestEntry, SavedGame)? resumable(AppServices services) {
    final saved = services.progress.savedGame();
    if (saved == null) return null;
    final entry = services.content.snapshot.manifest.entry(saved.levelId);
    if (entry == null || entry.levelId != nextLevel(services).levelId || entry.ref.url != saved.levelUrl) return null;
    // Resumable even when its file is not on the device yet: the loader gets it.
    if (services.content.snapshot.levelErrors.containsKey(entry.levelId)) return null;
    return (entry, saved);
  }

  /// The first playable level not yet completed (or the last one).
  static LevelManifestEntry nextLevel(AppServices services) {
    final entries = services.content.snapshot.playableEntries;
    final completed = services.progress.completed();
    return entries.firstWhere((e) => !completed.containsKey(e.levelId), orElse: () => entries.last);
  }

  /// Whether every playable level has been won (owner: then say new levels
  /// are coming soon).
  static bool allCompleted(AppServices services) {
    final entries = services.content.snapshot.playableEntries;
    final completed = services.progress.completed();
    return entries.isNotEmpty && entries.every((e) => completed.containsKey(e.levelId));
  }

  /// "Continue · Level N" for a resumable game, else "Play · Level N"
  /// ("Replay · Level N" once every level is won).
  static String playLabel(AppServices services) {
    final resume = resumable(services);
    if (resume != null) return 'Continue · Level ${resume.$1.order}';
    return '${allCompleted(services) ? 'Replay' : 'Play'} · Level ${nextLevel(services).order}';
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// True while a pushed route is open (or opening), so rapid taps cannot
  /// open a screen twice.
  bool _navigating = false;

  /// Play Games and ads start once, after the first frame.
  bool _servicesScheduled = false;

  Future<void> _open(WidgetBuilder builder) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    } finally {
      if (mounted) _navigating = false;
    }
  }

  void _play(AppServices services) {
    // Resolved at tap time, so it always matches the latest progress/content.
    final resume = HomeScreen.resumable(services);
    final entry = resume?.$1 ?? HomeScreen.nextLevel(services);
    // Straight into the game when the level is on the device, else it is
    // downloaded first.
    _open((_) => LevelLoaderScreen(entry: entry, resume: resume?.$2));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_servicesScheduled) return;
    _servicesScheduled = true;
    final services = AppScope.of(context);
    // After the first frame: the lobby never waits for Play Games or ads
    // (SDK start, consent, the first rewarded ad).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      services.playGames.start();
      services.ads.start(services.settings.ageGroup);
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final lobby = LobbyTheme.of(context);
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      body: LobbyBackground(
        child: SafeArea(
          minimum: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
          child: LayoutBuilder(
            builder: (context, constraints) => ListenableBuilder(
              listenable: Listenable.merge([services.content, services.progress, services.playGames]),
              builder: (context, _) => _layout(context, services, constraints.biggest),
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, AppServices services, Size size) {
    final w = size.width, h = size.height;
    final side = (w * 0.075).clamp(16.0, 40.0);
    final contentWidth = math.min(w - side * 2, 440.0);
    // Vertical rhythm (fractions of the safe height): breathing room under
    // the status bar, then the tagline in the upper area and the buttons
    // just below the middle; spare height is split 2:3 above the tagline and
    // above the footer. Short screens and large text scroll instead of
    // overflowing.
    final topGap = h * 0.04;
    final taglineWidth = math.min(contentWidth * 0.9, 340.0);
    final taglineSize = math.min(taglineWidth * 0.3, h * 0.1);
    final primaryHeight = (h * 0.074).clamp(54.0, 68.0);
    final secondaryHeight = (h * 0.064).clamp(48.0, 60.0);
    final gap = (h * 0.018).clamp(10.0, 18.0);
    final buttonWidth = math.min(contentWidth * 0.9, 360.0);
    final label = HomeScreen.playLabel(services);

    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, topGap, side, math.max(10, h * 0.018)),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: LobbyPlayGamesButtons(controller: services.playGames),
                ),
                const Spacer(flex: 2),
                LobbyTagline(width: taglineWidth, fontSize: taglineSize),
                SizedBox(height: h * 0.065),
                if (HomeScreen.allCompleted(services) && HomeScreen.resumable(services) == null) ...[
                  SizedBox(
                    width: buttonWidth,
                    child: AllLevelsCompleteNote(levelCount: services.content.snapshot.playableEntries.length),
                  ),
                  SizedBox(height: gap * 1.25),
                ],
                SizedBox(
                  width: buttonWidth,
                  child: LobbyPrimaryButton(
                    key: const ValueKey('lobby-play'),
                    label: label,
                    semanticLabel: label.replaceAll(' · ', ', '),
                    height: primaryHeight,
                    onPressed: () => _play(services),
                  ),
                ),
                SizedBox(height: gap * 1.25),
                SizedBox(
                  width: buttonWidth * 0.92,
                  child: LobbySecondaryButton(
                    key: const ValueKey('lobby-levels'),
                    label: 'Completed Levels',
                    icon: Icons.emoji_events_rounded,
                    height: secondaryHeight,
                    onPressed: () => _open((_) => const LevelSelectScreen()),
                  ),
                ),
                SizedBox(height: gap),
                SizedBox(
                  width: buttonWidth * 0.92,
                  child: LobbySecondaryButton(
                    key: const ValueKey('lobby-settings'),
                    label: 'Settings',
                    icon: Icons.settings_rounded,
                    height: secondaryHeight,
                    onPressed: () => _open((_) => const SettingsScreen()),
                  ),
                ),
                const Spacer(flex: 3),
                if (services.playGames.notice case final notice?)
                  LobbyNoticeText(notice)
                else
                  LobbyContentFooter(snapshot: services.content.snapshot, status: services.content.status),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

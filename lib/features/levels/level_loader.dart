import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../content/content_coordinator.dart';
import '../../content/content_exception.dart';
import '../../content/level_manifest.dart';
import '../../data/progress_repository.dart';
import '../common/lobby_background.dart';
import '../common/lobby_chrome.dart';
import '../gameplay/game_screen.dart';
import '../home/home_screen.dart';
import '../home/widgets/lobby_buttons.dart';
import 'difficulty_style.dart';

/// Shown while a level that is not on the device yet downloads.
const String kDownloadingLevelText = 'Downloading level…';

/// Shown when such a level is opened without an internet connection.
const String kConnectToDownloadText = 'Connect to the internet to download this level';

/// The way into a game. When the level and its art are on the device (the
/// usual case: the next five levels are kept ready, and played levels stay)
/// it is the [GameScreen] itself, at once. Otherwise it downloads them first
/// ("Downloading level…"), or, offline, says that the level needs the
/// internet, with Try again.
///
/// Opened without [resume], it still resumes the highest level's saved game
/// when [entry] is that level (e.g. "Next level" after a replay), so no path
/// into the highest level starts over it. Completed levels have no resumable
/// save and start fresh.
class LevelLoaderScreen extends StatefulWidget {
  const LevelLoaderScreen({super.key, required this.entry, this.resume});

  final LevelManifestEntry entry;
  final SavedGame? resume;

  @override
  State<LevelLoaderScreen> createState() => _LevelLoaderScreenState();
}

enum _LoadState { loading, offline, failed }

class _LevelLoaderScreenState extends State<LevelLoaderScreen> {
  ReadyLevel? _ready;
  _LoadState _state = _LoadState.loading;
  bool _started = false;
  SavedGame? _resume;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    final resumable = widget.resume == null ? HomeScreen.resumable(services) : null;
    _resume = widget.resume ?? (resumable?.$1.levelId == widget.entry.levelId ? resumable?.$2 : null);
    final content = services.content;
    final snapshot = content.snapshot;
    final level = snapshot.levels[widget.entry.levelId];
    if (level != null && snapshot.isReady(widget.entry.levelId)) {
      // On the device: straight into the game, no loading frame.
      _ready = (snapshot: snapshot, entry: widget.entry, level: level);
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_state != _LoadState.loading) setState(() => _state = _LoadState.loading);
    try {
      final ready = await AppScope.of(context).content.ensureLevel(widget.entry);
      if (mounted) setState(() => _ready = ready);
    } on ContentException catch (error) {
      if (mounted) setState(() => _state = error.isTransient ? _LoadState.offline : _LoadState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready != null) {
      return GameScreen(snapshot: ready.snapshot, entry: ready.entry, resume: _resume);
    }
    final lobby = LobbyTheme.of(context);
    final entry = widget.entry;
    final difficulty = entry.difficulty == null ? null : DifficultyStyle.of(entry.difficulty!);
    final message = switch (_state) {
      _LoadState.loading => kDownloadingLevelText,
      _LoadState.offline => kConnectToDownloadText,
      _LoadState.failed => 'This level could not be loaded. Please try again later.',
    };
    return Scaffold(
      backgroundColor: lobby.baseFallback.last,
      extendBodyBehindAppBar: true,
      appBar: LobbyAppBar(title: 'Level ${entry.order}'),
      body: LobbyBackground(
        variant: LobbySceneVariant.subScreen,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: '${entry.title}. $message',
                      excludeSemantics: true,
                      child: LobbyPanel(
                        radius: 20,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                          children: [
                            Icon(
                              _state == _LoadState.loading ? Icons.cloud_download_rounded : Icons.wifi_off_rounded,
                              color: lobby.panelAccent,
                              size: 34,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              entry.title,
                              textAlign: TextAlign.center,
                              style: lobbyHeading(context, 22),
                            ),
                            if (difficulty != null) ...[
                              const SizedBox(height: 8),
                              _Badge(label: difficulty.label, color: difficulty.color),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: lobby.panelText, fontSize: 15, height: 1.35, letterSpacing: 0.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Outside the panel's StaticLayer: the spinner moves.
                    if (_state == _LoadState.loading)
                      SizedBox.square(
                        dimension: 30,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: lobby.panelAccent),
                      )
                    else ...[
                      if (_state == _LoadState.offline)
                        LobbyPrimaryButton(label: 'Try again', height: 56, onPressed: () => unawaited(_load())),
                      const SizedBox(height: 12),
                      LobbySecondaryButton(
                        label: 'Back',
                        icon: Icons.arrow_back_rounded,
                        height: 50,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: color.withValues(alpha: 0.14),
      border: Border.all(color: color.withValues(alpha: 0.7), width: 0.9),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
    ),
  );
}

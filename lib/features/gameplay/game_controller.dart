import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../../content/level_manifest.dart';
import '../../data/progress_repository.dart';
import '../../app/sound_effects.dart';
import '../../data/settings_repository.dart';
import '../../game_engine/geometry/board_geometry.dart';
import '../../game_engine/models/level_definition.dart';
import '../../game_engine/models/symbol_registry.dart';
import '../../game_engine/rules/match_rules.dart';
import '../../game_engine/state/game_engine.dart';
import '../../game_engine/state/game_state.dart';

/// Visual events for the board and the tray, emitted after the engine has
/// changed state. Per accepted tap: [TileToTray], then [TrayPairCleared] or
/// [TrayFull] when that tap matched or lost. A revive: [TrayReturned].
sealed class BoardEvent {
  const BoardEvent();
}

/// [tileId] left the board for engine tray slot [slot] (the tray's length
/// before the tap). The board stops drawing it at once; the tray shows it
/// when its flight lands.
class TileToTray extends BoardEvent {
  const TileToTray(this.tileId, this.slot);

  final String tileId;
  final int slot;
}

/// The tile that just went to the tray ([tileId], landing in [slot]) matched
/// the tray tile [partnerId] in [partnerSlot]; both are destroyed and the
/// tray re-packs. Follows the [TileToTray] for [tileId].
class TrayPairCleared extends BoardEvent {
  const TrayPairCleared({required this.tileId, required this.slot, required this.partnerId, required this.partnerSlot});

  final String tileId;
  final int slot;
  final String partnerId;
  final int partnerSlot;

  /// Tray tile first, arriving tile second.
  TilePair get pair => (partnerId, tileId);
}

/// The tray filled with [tileIds] (slot order) and none matched: the game
/// is lost. Follows the [TileToTray] of the last tile.
class TrayFull extends BoardEvent {
  const TrayFull(this.tileIds);

  final List<String> tileIds;
}

/// Revive: the tiles that filled the tray ([tileIds], from tray slots
/// [fromSlots]) are back in their places on the board and the tray is empty.
/// The board shows them as they land (the director flies them back).
class TrayReturned extends BoardEvent {
  const TrayReturned(this.tileIds);

  final List<String> tileIds;

  /// Tray slot each of [tileIds] left.
  List<int> get fromSlots => [for (var i = 0; i < tileIds.length; i++) i];
}

/// A covered or side-blocked tile was tapped; it stays on the board.
class TileRejected extends BoardEvent {
  const TileRejected(this.tileId);

  final String tileId;
}

/// Level restarted: board, tray and counters are back to the start.
class BoardReset extends BoardEvent {
  const BoardReset();
}

/// Glue between the rules engine and the UI: input, timer, autosave, wins,
/// sounds and haptics.
class GameController extends ChangeNotifier {
  GameController({
    required this.entry,
    required this.level,
    required this.registry,
    required this.progress,
    required this.settings,
    this.sounds,
    SavedGame? resume,
    int? trayCapacity,
    this.arrivalFeedbackDelay = Duration.zero,
    this.matchFeedbackOnImpact = false,
    this.winSoundDelay = Duration.zero,
    this.playIntro = false,
  }) : trayCapacity = trayCapacity ?? level.rules.trayCapacity {
    final rules = MatchRules(level: level, registry: registry);
    engine = GameEngine(level: level, rules: rules, geometry: BoardGeometry.build(level), trayCapacity: this.trayCapacity);
    if (resume != null && resume.levelId == level.levelId && resume.levelUrl == entry.ref.url) {
      // A save that no longer replays on this level starts over. (Saves are
      // cleared when a game ends, so a resumed game is normally in play.)
      if (engine.replay(resume.history)) {
        _baseElapsed = Duration(milliseconds: resume.elapsedMs);
      } else {
        engine.restart();
      }
    }
    if (playIntro && engine.state.status == GameStatus.playing) {
      _introPlaying = true;
    } else if (engine.state.status == GameStatus.playing) {
      _stopwatch.start();
    }
  }

  final LevelManifestEntry entry;
  final LevelDefinition level;
  final SymbolRegistry registry;
  final ProgressRepository progress;
  final SettingsRepository settings;

  /// Tray slots: the level's `rules.trayCapacity` (4 unless the level asks
  /// for 5) unless a test overrides it.
  final int trayCapacity;

  /// How long after a tap its outcome is felt and heard (match, win, lose):
  /// set it to the tray flight time so the feedback lands with the tile.
  /// The tap itself always sounds at once ([Sfx.tap]).
  final Duration arrivalFeedbackDelay;

  /// True when the UI plays matched pairs striking each other: the match
  /// (or win) sound and haptic then wait for [pairImpact] instead of the
  /// tile's arrival.
  final bool matchFeedbackOnImpact;

  /// How long after the last pair's strike sound the win sound plays (set it
  /// so the win lands while the shards fly instead of on top of the hit).
  final Duration winSoundDelay;

  /// Whether each game (a new one, a restart, a resumed save) opens with the
  /// board intro: taps are ignored and the clock waits until [endIntro].
  final bool playIntro;

  /// Null plays no sounds (tests).
  final SoundEffects? sounds;
  late final GameEngine engine;

  final Stopwatch _stopwatch = Stopwatch();
  Duration _baseElapsed = Duration.zero;
  final StreamController<BoardEvent> _events = StreamController.broadcast();
  final Set<Timer> _pendingFeedback = {};
  int _pendingImpacts = 0;
  bool _introPlaying = false;
  int _introSerial = 0;
  int _stateVersion = 0;
  bool _disposed = false;

  /// The result saved when the level was won in this session.
  LevelRecord? winRecord;

  Stream<BoardEvent> get events => _events.stream;
  GameState get state => engine.state;
  int get stateVersion => _stateVersion;
  Duration get elapsed => _baseElapsed + _stopwatch.elapsed;

  /// True while the board intro plays: the board is not drawn, taps are
  /// ignored and the clock has not started.
  bool get introPlaying => _introPlaying;

  /// Changes each time a game starts with an intro (restart included), so
  /// the screen can tell a new intro from the one already playing.
  int get introSerial => _introSerial;

  /// The board intro finished (or could not play): play begins and the
  /// clock starts.
  void endIntro() {
    if (!_introPlaying) return;
    _introPlaying = false;
    if (state.status == GameStatus.playing) _stopwatch.start();
    _changed();
  }

  /// A layer of tiles landed during the intro: one soft tick.
  void introLayerLanded() => sounds?.play(Sfx.select);

  void tapTile(String tileId) {
    if (_introPlaying) return;
    final result = engine.tap(tileId);
    switch (result.outcome) {
      case TapOutcome.ignored:
        return;
      case TapOutcome.blocked:
        // A clear vibration (not just a haptic tick) so a wrong tap is felt.
        _vibrate(const Duration(milliseconds: 120));
        sounds?.play(Sfx.invalid);
        _emit(TileRejected(tileId));
        return;
      case TapOutcome.toTray:
        _tapFeedback();
        _emit(TileToTray(tileId, result.slot!));
      case TapOutcome.matched:
        _tapFeedback();
        _emit(TileToTray(tileId, result.slot!));
        _emit(
          TrayPairCleared(
            tileId: tileId,
            slot: result.slot!,
            partnerId: result.partnerTileId!,
            partnerSlot: result.partnerSlot!,
          ),
        );
        if (matchFeedbackOnImpact) {
          _pendingImpacts++;
        } else {
          final won = state.status == GameStatus.won;
          _afterArrival(() => _matchFeedback(won: won));
        }
      case TapOutcome.trayFull:
        _tapFeedback();
        _emit(TileToTray(tileId, result.slot!));
        _emit(TrayFull(state.tray));
        _afterArrival(() {
          _haptic(HapticFeedback.heavyImpact);
          sounds?.play(Sfx.lose);
        });
    }
    _afterMove();
    _changed();
  }

  /// A matched pair's tiles hit each other on screen (with
  /// [matchFeedbackOnImpact]): the match sound and haptic, or the win sound
  /// for the last pair of a won game.
  void pairImpact() {
    if (_pendingImpacts > 0) _pendingImpacts--;
    _matchFeedback(won: state.status == GameStatus.won && _pendingImpacts == 0);
  }

  void _matchFeedback({required bool won}) {
    _haptic(HapticFeedback.mediumImpact);
    sounds?.play(Sfx.match);
    if (won) _later(winSoundDelay, () => sounds?.play(Sfx.win));
  }

  /// Revives a game lost with a full tray: its tiles go back to the board,
  /// the clock runs again and the game is saved. Not a move. Returns false
  /// when there is nothing to revive.
  bool revive() {
    final returned = engine.revive();
    if (returned == null) return false;
    _cancelFeedback();
    _stopwatch.start();
    _emit(TrayReturned(returned));
    // One soft sound as the tiles land.
    _afterArrival(() => sounds?.play(Sfx.select));
    _afterMove();
    _changed();
    return true;
  }

  void restart() {
    engine.restart();
    _cancelFeedback();
    _pendingImpacts = 0;
    _baseElapsed = Duration.zero;
    // reset() alone keeps a running watch running.
    _stopwatch
      ..stop()
      ..reset();
    if (playIntro) {
      // The new game opens with its intro; the clock starts after it.
      _introPlaying = true;
      _introSerial++;
    } else {
      _stopwatch.start();
    }
    winRecord = null;
    _emit(const BoardReset());
    unawaited(progress.clearSavedGame());
    _changed();
  }

  void pauseClock() => _stopwatch.stop();

  void resumeClock() {
    if (state.status == GameStatus.playing && !_introPlaying) _stopwatch.start();
  }

  /// Every accepted tap: one subtle tap sound (a blocked tap plays only
  /// [Sfx.invalid]).
  void _tapFeedback() {
    _haptic(HapticFeedback.selectionClick);
    sounds?.play(Sfx.tap);
  }

  void _afterArrival(VoidCallback feedback) => _later(arrivalFeedbackDelay, feedback);

  /// Runs [feedback] after [delay] (at once for zero); restart and revive
  /// drop it if it has not run yet.
  void _later(Duration delay, VoidCallback feedback) {
    if (delay == Duration.zero) {
      feedback();
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _pendingFeedback.remove(timer);
      if (!_disposed) feedback();
    });
    _pendingFeedback.add(timer);
  }

  void _cancelFeedback() {
    for (final timer in _pendingFeedback) {
      timer.cancel();
    }
    _pendingFeedback.clear();
  }

  void _afterMove() {
    switch (state.status) {
      case GameStatus.won:
        _stopwatch.stop();
        unawaited(_recordWin());
      case GameStatus.trayFull:
        // Saved anyway: the game can still be revived after an app restart.
        _stopwatch.stop();
        _save();
      case GameStatus.playing:
        _save();
    }
  }

  void _save() => unawaited(
    progress.saveGame(
      SavedGame(
        levelId: level.levelId,
        levelUrl: entry.ref.url,
        history: state.history,
        moveCount: state.moveCount,
        elapsedMs: elapsed.inMilliseconds,
      ),
    ),
  );

  Future<void> _recordWin() async {
    winRecord = await progress.recordWin(level.levelId, moves: state.moveCount, timeMs: elapsed.inMilliseconds);
    await progress.clearSavedGame();
    if (!_disposed) notifyListeners();
  }

  void _haptic(Future<void> Function() feedback) {
    if (settings.haptics) unawaited(feedback());
  }

  /// Vibrates the phone for [duration] (Vibration setting permitting). Falls
  /// back to a strong haptic where a vibrator is unavailable; never throws.
  void _vibrate(Duration duration) {
    if (!settings.haptics) return;
    unawaited(() async {
      try {
        // Vibrate directly: vibration 3.x `hasVibrator` answers false on any
        // non-physical device (emulators), which would skip a real vibrator.
        await Vibration.vibrate(duration: duration.inMilliseconds);
        return;
      } on Object {
        // No plugin (tests): fall through to haptics.
      }
      try {
        await HapticFeedback.heavyImpact();
      } on Object {
        // Ignore.
      }
    }());
  }

  void _emit(BoardEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _changed() {
    _stateVersion++;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelFeedback();
    _stopwatch.stop();
    unawaited(_events.close());
    super.dispose();
  }
}

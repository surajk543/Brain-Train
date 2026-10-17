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
import '../../game_engine/scoring/score_keeper.dart';
import '../../game_engine/scoring/scoring_rules.dart';
import '../../game_engine/state/game_actions.dart';
import '../../game_engine/state/game_engine.dart';
import '../../game_engine/state/game_state.dart';

/// Visual events for the board and the tray, emitted after the engine has
/// changed state. Per accepted tap: [TileToTray], then [TrayPairCleared] or
/// [TrayFull] when that tap matched or lost. A revive: [TrayReturned]. The
/// helper actions: [MoveUndone], [TileHinted], [BoardShuffled].
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

/// Undo: the last tap is taken back. [tileId] is back in its board place:
/// it left engine tray slot [fromSlot] (or was still flying there); play it
/// flying from the tray to the board. If that tap had cleared a pair,
/// [partnerId] is back in engine tray slot [partnerSlot] and the pair's
/// strike is called off: [GameController.pairImpact] ignores it from now on.
/// [tray] is the engine's tray after the undo, slot order.
class MoveUndone extends BoardEvent {
  const MoveUndone({
    required this.tileId,
    required this.fromSlot,
    required this.tray,
    this.partnerId,
    this.partnerSlot,
    this.pointsTakenBack = 0,
  });

  final String tileId;
  final int fromSlot;
  final String? partnerId;
  final int? partnerSlot;
  final List<String> tray;

  /// Score the undo took back (the undone match's points; 0 for a plain tap).
  final int pointsTakenBack;

  bool get undidMatch => partnerId != null;
}

/// A hint was used: [hint] names the board tile to tap (and its twin when
/// known). Nothing moved; show it on the board.
class TileHinted extends BoardEvent {
  const TileHinted(this.hint);

  final Hint hint;
}

/// Shuffle: the board tiles in [changes] (tile id → old and new symbol code)
/// show other symbols now; places, layers, ids and the tray are unchanged.
/// Draw the board from [GameController.boardLevel] from now on.
class BoardShuffled extends BoardEvent {
  const BoardShuffled(this.changes, {required this.seed});

  final Map<String, (String from, String to)> changes;
  final int seed;
}

/// Score feedback for the screen (popups). The score itself is already
/// updated when these arrive.
sealed class ScoreEvent {
  const ScoreEvent();
}

/// A matched pair scored [score]; it struck in tray slot [traySlot].
class ScoreAwarded extends ScoreEvent {
  const ScoreAwarded(this.score, this.traySlot);

  final MatchScore score;
  final int traySlot;
}

/// A blocked-tile tap on [tileId] cost [points] (never 0).
class ScorePenalty extends ScoreEvent {
  const ScorePenalty(this.tileId, this.points);

  final String tileId;
  final int points;
}

/// What the result card shows for a game: score, time, moves and the helper
/// actions used (owner, 1.1.0).
class GameSummary {
  const GameSummary({
    required this.score,
    required this.bestCombo,
    required this.time,
    required this.moves,
    required this.matchedPairs,
    required this.totalPairs,
    required this.undosUsed,
    required this.hintsUsed,
    required this.shufflesUsed,
    this.newBestScore = false,
    this.record,
  });

  final int score;
  final int bestCombo;
  final Duration time;
  final int moves;
  final int matchedPairs;
  final int totalPairs;
  final int undosUsed;
  final int hintsUsed;
  final int shufflesUsed;

  /// The win beat this level's previous best score.
  final bool newBestScore;

  /// The level's saved record after this win (null until it is saved).
  final LevelRecord? record;
}

/// Glue between the rules engine and the UI: input, timer, autosave, wins,
/// sounds and haptics, and the helper actions (Undo, Hint, Shuffle and their
/// uses; see [isAvailable], [undo], [useHint], [shuffle], [grant]).
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
    Stopwatch? stopwatch,
    ScoringRules scoringRules = const ScoringRules(),
  }) : trayCapacity = trayCapacity ?? level.rules.trayCapacity,
       _stopwatch = stopwatch ?? Stopwatch(),
       scoring = ScoreKeeper(rules: scoringRules) {
    final rules = MatchRules(level: level, registry: registry);
    engine = GameEngine(level: level, rules: rules, geometry: BoardGeometry.build(level), trayCapacity: this.trayCapacity);
    if (resume != null && resume.levelId == level.levelId && resume.levelUrl == entry.ref.url) {
      // A save that no longer replays on this level starts over. (Saves are
      // cleared when a game ends, so a resumed game is normally in play.)
      if (engine.replay(resume.history)) {
        _baseElapsed = Duration(milliseconds: resume.elapsedMs);
        _restoreScoring(resume.scoring);
      } else {
        engine.restart();
      }
    }
    if (playIntro && engine.state.status == GameStatus.playing) {
      _introPlaying = true;
    } else if (engine.state.status == GameStatus.playing) {
      _stopwatch.start();
    }
    // A resumed active combo needs its expiry timer too (no intro to start it).
    _scheduleComboEnd();
  }

  /// The saved score, or (no or unreadable data) base points per matched
  /// pair.
  void _restoreScoring(Map<String, Object?>? json) {
    if (json != null) {
      try {
        final saved = ScoreKeeper.fromJson(json, rules: scoring.rules);
        if (saved.totalPairsMatched == state.matchedPairs) {
          scoring
            ..reset()
            ..restoreFrom(saved);
          return;
        }
        debugPrint('Saved score disagrees with the board, rebuilt from the board');
      } on FormatException catch (error) {
        debugPrint('Saved score unreadable, rebuilt from the board ($error)');
      }
    }
    scoring.restoreLegacy(state.matchedPairs);
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

  final Stopwatch _stopwatch;
  Duration _baseElapsed = Duration.zero;
  final StreamController<BoardEvent> _events = StreamController.broadcast();

  /// Delayed feedback, by the tile whose move it belongs to (null: none).
  final Map<Timer, String?> _pendingFeedback = {};

  /// The game's score and combo.
  final ScoreKeeper scoring;
  final StreamController<ScoreEvent> _scoreEvents = StreamController.broadcast();

  /// Matches whose strike has not hit yet ([pairImpact]), oldest first.
  final List<_Unstruck> _unstruck = [];
  Timer? _comboTimer;
  int _symbolsSerial = 0;

  /// True when the last win beat this level's previous best score.
  bool newBestScore = false;

  /// The won game's summary for the result card, once its record is saved.
  GameSummary? winSummary;
  bool _introPlaying = false;
  int _introSerial = 0;
  int _stateVersion = 0;
  bool _disposed = false;

  /// The result saved when the level was won in this session.
  LevelRecord? winRecord;

  Stream<BoardEvent> get events => _events.stream;
  Stream<ScoreEvent> get scoreEvents => _scoreEvents.stream;
  int get score => scoring.score;

  /// The running combo (0 once its window has passed).
  int get activeCombo => scoring.isComboActive(elapsed) ? scoring.currentCombo : 0;

  /// Time left in the combo window, or null when no combo runs.
  Duration? get comboTimeLeft => activeCombo == 0 ? null : scoring.comboExpiresAt! - elapsed;

  bool get clockRunning => _stopwatch.isRunning;
  GameState get state => engine.state;

  /// The level as the board shows it now: tiles carry their symbols after
  /// any shuffle (the level itself until one). Rebuild drawings from it when
  /// [symbolsSerial] changes.
  LevelDefinition get boardLevel => engine.boardLevel;

  /// Changes whenever tiles change symbols (a shuffle, or a restart after
  /// one).
  int get symbolsSerial => _symbolsSerial;

  /// The symbol [tileId] shows now.
  String symbolCodeOf(String tileId) {
    final index = engine.indexOf(tileId);
    return index == null ? '' : engine.symbolCodeOf(index);
  }

  /// Uses left and used of each action in this game.
  ActionCounts get actions => state.actions;

  /// Uses of [action] left in this game.
  int usesLeft(GameAction action) => engine.usesLeft(action);

  /// Extra uses of [action] a rewarded ad can still give in this level
  /// attempt ([kMaxGrantsPerAction] in all; a restart starts over, a revive
  /// changes nothing).
  int grantsLeft(GameAction action) => engine.grantsLeft(action);

  /// [action] has no use left and no grant to be had (owner, 2026-10-17: 1
  /// free use + at most 1 for an ad): its button leaves the action bar and no
  /// ad is loaded or offered for it until a restart or another level.
  bool isSpent(GameAction action) => engine.isSpent(action);

  /// Whether [action] makes sense now, uses aside: the game is in play (not
  /// over, no intro, no tutorial) and Undo has a tap to take back (not past
  /// a Revive or a Shuffle), Hint a tap to recommend, Shuffle two symbols
  /// to swap. With no use left the UI can offer a rewarded ad ([grant])
  /// unless the action [isSpent].
  bool isAvailable(GameAction action) {
    if (_disposed || _introPlaying || _tutorialActive || state.status != GameStatus.playing) return false;
    return switch (action) {
      GameAction.undo => _canUndoNow,
      GameAction.hint => _hintExists,
      GameAction.shuffle => engine.canShuffleBoard,
    };
  }

  /// [action] is available and has a use left.
  bool canUse(GameAction action) => isAvailable(action) && usesLeft(action) > 0;

  bool get _canUndoNow {
    if (!engine.undoAvailable) return false;
    if (engine.undoWouldUnmatch != true) return true;
    // A match's score comes back from the keeper's checkpoint; a game resumed
    // from a 1.0 save has none for its earlier matches.
    return scoring.pairsBeforeUndo == state.matchedPairs - 1;
  }

  /// A hint exists exactly when some tap neither fills the tray nor loses:
  /// a free tile that matches the tray, or any free tile while there is room.
  bool get _hintExists {
    final tray = state.tray;
    if (tray.length + 1 < trayCapacity) return true;
    final rules = engine.rules;
    final waiting = [for (final id in tray) engine.indexOf(id)!];
    return state.free.any((id) {
      final index = engine.indexOf(id)!;
      return waiting.any((other) => rules.matches(other, index));
    });
  }

  /// The game's figures now (the result card reads [winSummary]).
  GameSummary get summary => GameSummary(
    score: scoring.score,
    bestCombo: scoring.bestCombo,
    time: elapsed,
    moves: state.moveCount,
    matchedPairs: state.matchedPairs,
    totalPairs: state.totalPairs,
    undosUsed: actions.undosUsed,
    hintsUsed: actions.hintsUsed,
    shufflesUsed: actions.shufflesUsed,
    newBestScore: newBestScore,
    record: winRecord,
  );

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
    _scheduleComboEnd();
    _changed();
  }

  /// A layer of tiles landed during the intro: one soft tick.
  void introLayerLanded() => sounds?.play(Sfx.select);

  /// True while the first-play tutorial runs: the clock (and with it the
  /// combo window) waits, and only [tutorialTarget] can be tapped.
  bool get tutorialActive => _tutorialActive;
  bool _tutorialActive = false;

  /// The one tile the tutorial lets the player tap now; null: none.
  String? tutorialTarget;

  /// Holds the game for the first-play tutorial: the clock stops and other
  /// taps are ignored until [endTutorial].
  void beginTutorial() {
    if (_tutorialActive) return;
    _tutorialActive = true;
    pauseClock();
  }

  /// The tutorial is over (finished or skipped): every tile can be tapped
  /// again and the clock runs.
  void endTutorial() {
    if (!_tutorialActive) return;
    _tutorialActive = false;
    tutorialTarget = null;
    resumeClock();
  }

  void tapTile(String tileId) {
    if (_introPlaying || (_tutorialActive && tileId != tutorialTarget)) return;
    final result = engine.tap(tileId);
    switch (result.outcome) {
      case TapOutcome.ignored:
        return;
      case TapOutcome.blocked:
        // A clear vibration (not just a haptic tick) so a wrong tap is felt.
        _vibrate(const Duration(milliseconds: 120));
        sounds?.play(Sfx.invalid);
        _emit(TileRejected(tileId));
        final taken = scoring.onBlockedTap();
        _scheduleComboEnd();
        if (taken > 0) {
          _emitScore(ScorePenalty(tileId, taken));
          if (state.status == GameStatus.playing) _save();
        }
        if (!_disposed) notifyListeners();
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
        final award = ScoreAwarded(scoring.onMatch(elapsed), result.partnerSlot!);
        if (!matchFeedbackOnImpact) _emitScore(award);
        _unstruck.add(
          _Unstruck(
            tileId,
            result.partnerTileId!,
            award: matchFeedbackOnImpact ? award : null,
            awaitsImpact: matchFeedbackOnImpact,
          ),
        );
        _scheduleComboEnd();
        if (!matchFeedbackOnImpact) {
          final won = state.status == GameStatus.won;
          _afterArrival(() => _matchFeedback(won: won), move: tileId);
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
  /// for the last pair of a won game, and its score popup.
  ///
  /// Name the pair ([tileId], and [otherTileId] if known, in any order) so a
  /// strike of a pair that no longer exists (undone, or from before a
  /// restart) does nothing: no feedback, no score. Without names the oldest
  /// waiting match strikes.
  void pairImpact([String? tileId, String? otherTileId]) {
    _Unstruck? match;
    if (tileId == null) {
      if (_unstruck.isNotEmpty) match = _unstruck.removeAt(0);
    } else {
      final at = _unstruck.indexWhere((m) => m.involves(tileId) || (otherTileId != null && m.involves(otherTileId)));
      if (at < 0) return;
      match = _unstruck.removeAt(at);
    }
    if (match?.award case final award?) _emitScore(award);
    _matchFeedback(won: state.status == GameStatus.won && !_unstruck.any((m) => m.awaitsImpact));
  }

  void _matchFeedback({required bool won}) {
    _haptic(HapticFeedback.mediumImpact);
    sounds?.play(Sfx.match);
    if (won) _later(winSoundDelay, () => sounds?.play(Sfx.win));
  }

  /// Revives left in this level attempt ([kMaxRevivesPerLevel] in all; a
  /// restart starts over, free revives count too).
  int get revivesLeft => engine.revivesLeft;

  /// The game is lost with a full tray and a revive is left: the Tray full
  /// card offers Revive (else Restart only, and no ad).
  bool get canRevive => !_disposed && engine.canRevive;

  /// Revives a game lost with a full tray: its tiles go back to the board,
  /// the clock runs again and the game is saved. Not a move. Returns false
  /// when there is nothing to revive or no revive left ([canRevive]).
  bool revive() {
    final returned = engine.revive();
    if (returned == null) return false;
    _cancelFeedback();
    scoring
      ..endCombo()
      ..sealUndo();
    for (final match in _unstruck) {
      match.award = null;
    }
    _scheduleComboEnd();
    _stopwatch.start();
    _emit(TrayReturned(returned));
    // One soft sound as the tiles land.
    _afterArrival(() => sounds?.play(Sfx.select));
    _afterMove();
    _changed();
    return true;
  }

  /// Takes back the last tap, using one Undo ([canUse]): the tile goes back
  /// to its board place; a tap that had cleared a pair also brings its twin
  /// back to the tray and takes back that match's score and combo (blocked-tap
  /// penalties since stay). The clock runs on. Emits [MoveUndone]; a strike
  /// of the undone pair still on screen is ignored ([pairImpact]). Null when
  /// Undo cannot be used now.
  UndoResult? undo() {
    if (!canUse(GameAction.undo)) return null;
    final scoreBefore = scoring.score;
    final result = engine.undo();
    if (result == null) return null;
    _cancelFeedbackFor(result.tileId);
    if (result.undidMatch) {
      scoring.undoMatch();
      final at = _unstruck.lastIndexWhere((m) => m.tileId == result.tileId);
      if (at >= 0) _unstruck.removeAt(at);
    }
    _scheduleComboEnd();
    _haptic(HapticFeedback.selectionClick);
    _emit(
      MoveUndone(
        tileId: result.tileId,
        fromSlot: result.fromSlot,
        partnerId: result.partnerTileId,
        partnerSlot: result.partnerSlot,
        tray: state.tray,
        pointsTakenBack: scoreBefore - scoring.score,
      ),
    );
    // One soft sound as the tile lands.
    _afterArrival(() => sounds?.play(Sfx.select));
    _afterMove();
    _changed();
    return result;
  }

  /// Uses one Hint ([canUse]): returns the recommended tap (see
  /// `HintFinder`) and emits [TileHinted]; nothing moves and nothing scores.
  /// Null (no use spent) when Hint cannot be used now.
  Hint? useHint() {
    if (!canUse(GameAction.hint)) return null;
    final hint = engine.useHint();
    if (hint == null) return null;
    sounds?.play(Sfx.select);
    _emit(TileHinted(hint));
    _save();
    _changed();
    return hint;
  }

  /// Uses one Shuffle ([canUse]): the board's symbols move to other board
  /// tiles (places, the tray and the score stay) into a position that can
  /// be won; the combo ends and Undo cannot reach earlier taps. Emits
  /// [BoardShuffled]. Anything but [ShuffleOutcome.shuffled] spends no use
  /// and changes nothing.
  ShuffleResult shuffle({int? seed}) {
    if (!isAvailable(GameAction.shuffle)) {
      final playing = !_disposed && !_introPlaying && !_tutorialActive && state.status == GameStatus.playing;
      return ShuffleResult(playing ? ShuffleOutcome.nothingToShuffle : ShuffleOutcome.unavailable);
    }
    if (usesLeft(GameAction.shuffle) <= 0) return const ShuffleResult(ShuffleOutcome.noCharges);
    final result = engine.shuffle(seed: seed);
    if (!result.shuffled) return result;
    scoring
      ..endCombo()
      ..sealUndo();
    _symbolsSerial++;
    _scheduleComboEnd();
    _haptic(HapticFeedback.selectionClick);
    sounds?.play(Sfx.select);
    _emit(BoardShuffled(result.changes, seed: result.seed!));
    _save();
    _changed();
    return result;
  }

  /// One more use of [action] (its rewarded ad paid out, or free when no ad
  /// could be had while online). Saved with the game; false once the game is
  /// won or when [action] has no grant left ([grantsLeft]).
  bool grant(GameAction action) {
    if (_disposed || !engine.grant(action)) return false;
    _save();
    _changed();
    return true;
  }

  void restart() {
    final shuffled = state.actions.shufflesUsed > 0;
    engine.restart();
    _cancelFeedback();
    scoring.reset();
    _unstruck.clear();
    if (shuffled) _symbolsSerial++;
    newBestScore = false;
    winSummary = null;
    _scheduleComboEnd();
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
    unawaited(progress.clearSavedGame(levelId: level.levelId));
    _changed();
  }

  void pauseClock() {
    _stopwatch.stop();
    _scheduleComboEnd();
    if (!_disposed) notifyListeners();
  }

  void resumeClock() {
    if (state.status == GameStatus.playing && !_introPlaying && !_tutorialActive) _stopwatch.start();
    _scheduleComboEnd();
    if (!_disposed) notifyListeners();
  }

  /// Every accepted tap: one subtle tap sound (a blocked tap plays only
  /// [Sfx.invalid]).
  void _tapFeedback() {
    _haptic(HapticFeedback.selectionClick);
    sounds?.play(Sfx.tap);
  }

  void _afterArrival(VoidCallback feedback, {String? move}) => _later(arrivalFeedbackDelay, feedback, move: move);

  /// Runs [feedback] after [delay] (at once for zero); restart and revive
  /// drop it if it has not run yet, and so does an undo of [move] (the
  /// tapped tile's id).
  void _later(Duration delay, VoidCallback feedback, {String? move}) {
    if (delay == Duration.zero) {
      feedback();
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _pendingFeedback.remove(timer);
      if (!_disposed) feedback();
    });
    _pendingFeedback[timer] = move;
  }

  void _cancelFeedback() {
    for (final timer in _pendingFeedback.keys) {
      timer.cancel();
    }
    _pendingFeedback.clear();
  }

  void _cancelFeedbackFor(String move) {
    _pendingFeedback.removeWhere((timer, tag) {
      if (tag != move) return false;
      timer.cancel();
      return true;
    });
  }

  void _afterMove() {
    switch (state.status) {
      case GameStatus.won:
        _stopwatch.stop();
        _scheduleComboEnd();
        unawaited(_recordWin());
      case GameStatus.trayFull:
        // Saved anyway: the game can still be revived after an app restart.
        _stopwatch.stop();
        _scheduleComboEnd();
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
        scoring: scoring.toJson(),
      ),
    ),
  );

  Future<void> _recordWin() async {
    final previousBest = progress.completed()[level.levelId]?.bestScore;
    winRecord = await progress.recordWin(
      level.levelId,
      moves: state.moveCount,
      timeMs: elapsed.inMilliseconds,
      score: scoring.score,
      bestCombo: scoring.bestCombo,
    );
    newBestScore = previousBest != null && scoring.score > previousBest;
    winSummary = summary;
    await progress.clearSavedGame(levelId: level.levelId);
    if (!_disposed) notifyListeners();
  }

  /// One timer for the moment the running combo's window closes (so the
  /// badge goes away); none while the clock is stopped.
  void _scheduleComboEnd() {
    _comboTimer?.cancel();
    _comboTimer = null;
    final left = comboTimeLeft;
    if (left == null || !_stopwatch.isRunning || _disposed) return;
    _comboTimer = Timer(left + const Duration(milliseconds: 1), () {
      _comboTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _emitScore(ScoreEvent event) {
    if (!_scoreEvents.isClosed) _scoreEvents.add(event);
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
    _comboTimer?.cancel();
    _stopwatch.stop();
    unawaited(_events.close());
    unawaited(_scoreEvents.close());
    super.dispose();
  }
}

/// A match whose strike has not hit yet.
class _Unstruck {
  _Unstruck(this.tileId, this.partnerId, {required this.award, required this.awaitsImpact});

  /// The tapped tile, and the tray tile it cleared.
  final String tileId;
  final String partnerId;

  /// Its score popup, shown at the strike (null: shown already, or dropped).
  ScoreAwarded? award;

  /// Its sound waits for the strike ([GameController.matchFeedbackOnImpact]).
  final bool awaitsImpact;

  bool involves(String id) => id == tileId || id == partnerId;
}

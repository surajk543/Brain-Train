import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LevelRecord {
  const LevelRecord({
    required this.bestMoves,
    required this.bestTimeMs,
    required this.completedAt,
    this.bestScore,
    this.bestCombo,
  });

  factory LevelRecord.fromJson(Map<String, Object?> json) => LevelRecord(
    bestMoves: json['bestMoves']! as int,
    bestTimeMs: json['bestTimeMs']! as int,
    completedAt: DateTime.parse(json['completedAt']! as String),
    bestScore: json['bestScore'] as int?,
    bestCombo: json['bestCombo'] as int?,
  );

  final int bestMoves;
  /// Fastest win, in milliseconds of play.
  final int bestTimeMs;

  /// When the fastest win ([bestTimeMs]) happened.
  final DateTime completedAt;

  /// Highest score and longest combo over all wins; null for wins from
  /// before scoring.
  final int? bestScore;
  final int? bestCombo;

  Map<String, Object?> toJson() => {
    'bestMoves': bestMoves,
    'bestTimeMs': bestTimeMs,
    'completedAt': completedAt.toIso8601String(),
    if (bestScore != null) 'bestScore': bestScore,
    if (bestCombo != null) 'bestCombo': bestCombo,
  };

  /// The best of this record and [other] (the same level won on another
  /// device, or before a reinstall), kept as [ProgressRepository.recordWin]
  /// keeps a replay: the fastest time with its date, and the fewest moves,
  /// highest score and longest combo each on their own.
  LevelRecord merge(LevelRecord other) {
    final faster = other.bestTimeMs < bestTimeMs;
    int? higher(int? a, int? b) => a == null ? b : (b == null ? a : math.max(a, b));
    return LevelRecord(
      bestMoves: math.min(bestMoves, other.bestMoves),
      bestTimeMs: faster ? other.bestTimeMs : bestTimeMs,
      completedAt: faster ? other.completedAt : completedAt,
      bestScore: higher(bestScore, other.bestScore),
      bestCombo: higher(bestCombo, other.bestCombo),
    );
  }
}

/// A game in progress, saved after every accepted tap (and every Undo,
/// Hint, Shuffle and granted use) so it survives restarts.
///
/// Stored as `progress.current.v3` (1.1.0+): the same JSON shape as v2, but
/// [history] may hold the action markers of `GameEngine` (`!undo`, `!hint`,
/// `!shuffle:1:<seed>`, `!grant:<action>`) besides taps and `!revive`, and
/// [scoring] may hold the score keeper's undo checkpoints. A 1.0 build would
/// not replay those, so the key changed; a v2 save (taps and revives only)
/// is still read and moves to v3.
class SavedGame {
  SavedGame({
    required this.levelId,
    required this.levelUrl,
    required this.history,
    int? moveCount,
    required this.elapsedMs,
    this.scoring,
  }) : moveCount = moveCount ?? history.length;

  factory SavedGame.fromJson(Map<String, Object?> json) => SavedGame(
    levelId: json['levelId']! as String,
    levelUrl: json['levelUrl']! as String,
    history: [for (final tileId in json['history']! as List<Object?>) tileId! as String],
    moveCount: json['moveCount']! as int,
    elapsedMs: json['elapsedMs']! as int,
    scoring: json['scoring'] as Map<String, Object?>?,
  );

  final String levelId;

  /// Versioned level path; a saved game only resumes on the same revision.
  final String levelUrl;

  /// Tapped tile ids and markers (revives, undos, hints, shuffles, granted
  /// uses) in order; replaying them rebuilds the board, the tray and the
  /// actions' uses.
  final List<String> history;
  final int moveCount;
  final int elapsedMs;

  /// The game's score keeper state, stored as an opaque map (see
  /// `ScoreKeeper.toJson`); null for saves from before scoring.
  final Map<String, Object?>? scoring;

  Map<String, Object?> toJson() => {
    'levelId': levelId,
    'levelUrl': levelUrl,
    'history': history,
    'moveCount': moveCount,
    'elapsedMs': elapsedMs,
    if (scoring != null) 'scoring': scoring,
  };
}

/// Local progress: completed levels with best results, and the current game.
/// Notifies listeners when either changes.
class ProgressRepository extends ChangeNotifier {
  ProgressRepository(this._prefs);

  static Future<ProgressRepository> open() async {
    final prefs = await SharedPreferences.getInstance();
    // Saves from before the tray hold matched pairs, not taps: drop them.
    if (prefs.containsKey(_legacySavedGameKey)) await prefs.remove(_legacySavedGameKey);
    // A 1.0 save (taps and revives) is a valid v3 save: move it over.
    final v2 = prefs.getString(_v2SavedGameKey);
    if (v2 != null) {
      if (!prefs.containsKey(_savedGameKey)) await prefs.setString(_savedGameKey, v2);
      await prefs.remove(_v2SavedGameKey);
    }
    return ProgressRepository(prefs);
  }

  final SharedPreferences _prefs;

  static const _completedKey = 'progress.completed.v1';
  static const _savedGameKey = 'progress.current.v3';

  /// 1.0 builds' save: no action markers. Read while there is no v3 save.
  static const _v2SavedGameKey = 'progress.current.v2';
  static const _legacySavedGameKey = 'progress.current.v1';

  Map<String, LevelRecord> completed() {
    final raw = _prefs.getString(_completedKey);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return {for (final e in json.entries) e.key: LevelRecord.fromJson(e.value! as Map<String, Object?>)};
    } on Object {
      return {};
    }
  }

  bool isCompleted(String levelId) => completed().containsKey(levelId);

  /// Records a won game. A level played again keeps its fastest time
  /// (owner), and [LevelRecord.completedAt] is when that fastest win
  /// happened, so the time and the date shown always belong together. Best
  /// moves, best score and best combo are each kept on their own.
  Future<LevelRecord> recordWin(
    String levelId, {
    required int moves,
    required int timeMs,
    int? score,
    int? bestCombo,
  }) async {
    final all = completed();
    final previous = all[levelId];
    final faster = previous == null || timeMs < previous.bestTimeMs;
    int? higher(int? a, int? b) => a == null ? b : (b == null ? a : (a > b ? a : b));
    final record = LevelRecord(
      bestMoves: previous == null || moves < previous.bestMoves ? moves : previous.bestMoves,
      bestTimeMs: faster ? timeMs : previous.bestTimeMs,
      completedAt: faster ? DateTime.now() : previous.completedAt,
      bestScore: higher(previous?.bestScore, score),
      bestCombo: higher(previous?.bestCombo, bestCombo),
    );
    all[levelId] = record;
    await _writeCompleted(all);
    notifyListeners();
    return record;
  }

  /// Adds [other]'s wins (the cloud save's) to this device's: new levels
  /// as they are, levels won on both with the best of each
  /// ([LevelRecord.merge]). Notifies and returns true only when something
  /// changed.
  Future<bool> mergeCompleted(Map<String, LevelRecord> other) async {
    final all = completed();
    var changed = false;
    for (final MapEntry(key: levelId, value: record) in other.entries) {
      final previous = all[levelId];
      final merged = previous == null ? record : previous.merge(record);
      if (previous != null && jsonEncode(merged.toJson()) == jsonEncode(previous.toJson())) continue;
      all[levelId] = merged;
      changed = true;
    }
    if (!changed) return false;
    await _writeCompleted(all);
    notifyListeners();
    return true;
  }

  Future<void> _writeCompleted(Map<String, LevelRecord> all) =>
      _prefs.setString(_completedKey, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));

  SavedGame? savedGame() {
    final raw = _prefs.getString(_savedGameKey) ?? _prefs.getString(_v2SavedGameKey);
    if (raw == null) return null;
    try {
      return SavedGame.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  /// Saves [game] unless its level is already completed: a replay never
  /// overwrites the saved game of the highest level (owner).
  Future<void> saveGame(SavedGame game) async {
    if (isCompleted(game.levelId)) return;
    await _prefs.setString(_savedGameKey, jsonEncode(game.toJson()));
    if (_prefs.containsKey(_v2SavedGameKey)) await _prefs.remove(_v2SavedGameKey);
    notifyListeners();
  }

  /// Removes the saved game only if it belongs to [levelId].
  Future<void> clearSavedGame({required String levelId}) async {
    if (savedGame()?.levelId != levelId) return;
    await _prefs.remove(_savedGameKey);
    await _prefs.remove(_v2SavedGameKey);
    notifyListeners();
  }
}

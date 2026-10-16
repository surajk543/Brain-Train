import 'dart:convert';

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
}

/// A game in progress, saved after every accepted tap so it survives
/// restarts.
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

  /// Tapped tile ids (and revive markers) in order; replaying them rebuilds
  /// the board and tray.
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
    return ProgressRepository(prefs);
  }

  final SharedPreferences _prefs;

  static const _completedKey = 'progress.completed.v1';
  static const _savedGameKey = 'progress.current.v2';
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
    await _prefs.setString(_completedKey, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
    notifyListeners();
    return record;
  }

  SavedGame? savedGame() {
    final raw = _prefs.getString(_savedGameKey);
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
    notifyListeners();
  }

  /// Removes the saved game only if it belongs to [levelId].
  Future<void> clearSavedGame({required String levelId}) async {
    if (savedGame()?.levelId != levelId) return;
    await _prefs.remove(_savedGameKey);
    notifyListeners();
  }
}

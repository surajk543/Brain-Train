import 'dart:math' as math;

import '../data/progress_repository.dart';
import '../game_engine/campaign/campaign_config.dart';
import '../platform/game_services_ids.dart';
import '../platform/play_games.dart';

/// A won game, as the leaderboards and achievements see it.
class WonGame {
  const WonGame({
    required this.difficulty,
    required this.score,
    required this.time,
    this.hintsUsed = 0,
    this.undosUsed = 0,
    this.shufflesUsed = 0,
  });

  /// The level's tier id from the manifest (`1`..`10`, or a named tier).
  final String? difficulty;
  final int score;
  final Duration time;
  final int hintsUsed;
  final int undosUsed;
  final int shufflesUsed;

  bool get usedHelpers => hintsUsed > 0 || undosUsed > 0 || shufflesUsed > 0;
}

/// What to send: leaderboard scores (the service keeps each player's best)
/// and the achievements earned.
class PlayGamesReport {
  const PlayGamesReport({required this.scores, required this.achievements});

  final List<(GameLeaderboard, int)> scores;
  final List<GameAchievement> achievements;
}

/// A time as a Fastest Time leaderboard takes it: milliseconds on Play Games
/// (Duration format), hundredths of a second on Game Center ("Elapsed Time -
/// To the Hundredth of a Second").
int leaderboardTime(int milliseconds, GamesService service) =>
    service == GamesService.gameCenter ? milliseconds ~/ 10 : milliseconds;

/// A win (replays too), reported once its record is saved ([completed]
/// holds it): this game's score and time on its tier's Best Score and
/// Fastest Time boards (none for a named or unknown tier), the totals of all
/// wins, and the achievements the progress and this game have earned.
PlayGamesReport reportForWin(WonGame game, Map<String, LevelRecord> completed, GamesService service) {
  final difficulty = game.difficulty == null ? null : numericDifficulty(game.difficulty!);
  final bestScore = difficulty == null ? null : GameLeaderboard.bestScore(difficulty);
  final fastestTime = difficulty == null ? null : GameLeaderboard.fastestTime(difficulty);
  return PlayGamesReport(
    scores: [
      if (bestScore != null) (bestScore, game.score),
      if (fastestTime != null) (fastestTime, leaderboardTime(game.time.inMilliseconds, service)),
      ..._totals(completed),
    ],
    achievements: [
      ..._progressAchievements(completed, service),
      if (difficulty == GameAchievement.summitDifficulty) GameAchievement.summit,
      if (difficulty != null && difficulty >= GameAchievement.pureSkillMinDifficulty && !game.usedHelpers)
        GameAchievement.pureSkill,
    ],
  );
}

/// The catch-up after sign-in: what the stored progress has already earned.
/// Each tier's best score and fastest time over its won levels
/// ([difficulties]: the manifest's tier per level id; levels it does not
/// know count only in the totals), the totals, the level-count and combo
/// achievements, and Summit when a difficulty-10 level was won. Pure Skill
/// needs a game's helper uses, which records do not keep: wins only.
PlayGamesReport reportForProgress(
  Map<String, LevelRecord> completed,
  Map<String, String?> difficulties,
  GamesService service,
) {
  final bestScores = <int, int>{};
  final fastestTimes = <int, int>{};
  var summit = false;
  for (final MapEntry(key: levelId, value: record) in completed.entries) {
    final tier = difficulties[levelId];
    final difficulty = tier == null ? null : numericDifficulty(tier);
    if (difficulty == null) continue;
    if (difficulty == GameAchievement.summitDifficulty) summit = true;
    if (record.bestScore case final score?) {
      bestScores.update(difficulty, (best) => math.max(best, score), ifAbsent: () => score);
    }
    if (record.bestTimeMs > 0) {
      fastestTimes.update(difficulty, (best) => math.min(best, record.bestTimeMs), ifAbsent: () => record.bestTimeMs);
    }
  }
  return PlayGamesReport(
    scores: [
      for (var d = 1; d <= kMaxDifficulty; d++) ...[
        if (bestScores[d] case final score?) (GameLeaderboard.bestScore(d)!, score),
        if (fastestTimes[d] case final time?) (GameLeaderboard.fastestTime(d)!, leaderboardTime(time, service)),
      ],
      ..._totals(completed),
    ],
    achievements: [..._progressAchievements(completed, service), if (summit) GameAchievement.summit],
  );
}

/// Total Score (sum of the best scores of all won levels), Levels Completed
/// and Best Combo (the longest of any record); nothing before the first win.
List<(GameLeaderboard, int)> _totals(Map<String, LevelRecord> completed) {
  if (completed.isEmpty) return const [];
  final combo = _bestCombo(completed);
  return [
    (GameLeaderboard.totalScore, completed.values.fold(0, (sum, record) => sum + (record.bestScore ?? 0))),
    (GameLeaderboard.levelsCompleted, completed.length),
    if (combo > 0) (GameLeaderboard.bestCombo, combo),
  ];
}

/// The level-count and combo achievements reached that [service] has (Play
/// Games only those with an ID there).
List<GameAchievement> _progressAchievements(Map<String, LevelRecord> completed, GamesService service) {
  final bestCombo = _bestCombo(completed);
  bool reached(GameAchievement achievement) => switch (achievement) {
    GameAchievement(levelsWon: final target?) => completed.length >= target,
    GameAchievement(combo: final target?) => bestCombo >= target,
    _ => false,
  };
  return [
    for (final achievement in GameAchievement.values)
      if ((service == GamesService.gameCenter || achievement.androidId != null) && reached(achievement)) achievement,
  ];
}

int _bestCombo(Map<String, LevelRecord> completed) =>
    completed.values.fold(0, (best, record) => math.max(best, record.bestCombo ?? 0));

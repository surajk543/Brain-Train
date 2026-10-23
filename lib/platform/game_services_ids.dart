/// Brain Train's achievements and leaderboards: every ID in one place, the
/// Google Play Games ID (Play Console, Games Services project 923515226118)
/// and the Apple Game Center ID (App Store Connect: `bt.ach.<key>`,
/// `bt.lb.<key>`) of each. Pure Dart; the plugin picks the ID of the
/// platform it runs on.
library;

/// The achievements (all plain unlocks, none incremental).
enum GameAchievement {
  /// First Match: complete your first level.
  firstWin('CgkIhpCwrvAaEAIQAw', 'bt.ach.first_win', levelsWon: 1),

  /// Getting Started: complete 10 levels.
  levels10('CgkIhpCwrvAaEAIQBA', 'bt.ach.levels_10', levelsWon: 10),

  /// Tile Collector: complete 50 levels.
  levels50('CgkIhpCwrvAaEAIQBQ', 'bt.ach.levels_50', levelsWon: 50),

  /// Complete 75, 150, 200, 300, 350, 400 or 600 levels (owner, 2026-10-23;
  /// Path Finder, Park Ranger, Double Century, Tile Sage, Grove Guardian,
  /// Puzzle Veteran, Park Legend). Game Center only.
  levels75(null, 'bt.ach.levels_75', levelsWon: 75),

  /// Centurion: complete 100 levels.
  levels100('CgkIhpCwrvAaEAIQBg', 'bt.ach.levels_100', levelsWon: 100),
  levels150(null, 'bt.ach.levels_150', levelsWon: 150),
  levels200(null, 'bt.ach.levels_200', levelsWon: 200),

  /// Garden Keeper: complete 250 levels.
  levels250('CgkIhpCwrvAaEAIQBw', 'bt.ach.levels_250', levelsWon: 250),
  levels300(null, 'bt.ach.levels_300', levelsWon: 300),
  levels350(null, 'bt.ach.levels_350', levelsWon: 350),
  levels400(null, 'bt.ach.levels_400', levelsWon: 400),

  /// Grand Master: complete 500 levels.
  levels500('CgkIhpCwrvAaEAIQCA', 'bt.ach.levels_500', levelsWon: 500),
  levels600(null, 'bt.ach.levels_600', levelsWon: 600),

  /// Total score (the sum of the best scores of all won levels, the Total
  /// Score leaderboard) of 2k to 50k (owner, 2026-10-23; "2K Club" to "50K
  /// Club"). Game Center only.
  score2k(null, 'bt.ach.score_2k', totalScore: 2000),
  score5k(null, 'bt.ach.score_5k', totalScore: 5000),
  score8k(null, 'bt.ach.score_8k', totalScore: 8000),
  score10k(null, 'bt.ach.score_10k', totalScore: 10000),
  score12k(null, 'bt.ach.score_12k', totalScore: 12000),
  score15k(null, 'bt.ach.score_15k', totalScore: 15000),
  score20k(null, 'bt.ach.score_20k', totalScore: 20000),
  score25k(null, 'bt.ach.score_25k', totalScore: 25000),
  score30k(null, 'bt.ach.score_30k', totalScore: 30000),
  score35k(null, 'bt.ach.score_35k', totalScore: 35000),
  score40k(null, 'bt.ach.score_40k', totalScore: 40000),
  score50k(null, 'bt.ach.score_50k', totalScore: 50000),

  /// Combo Master: reach a x5 combo.
  combo5('CgkIhpCwrvAaEAIQCQ', 'bt.ach.combo_5', combo: 5),

  /// Combo x6 to x15 (owner, 2026-10-23): reach that combo. Game Center
  /// only; Play Games has no such achievements yet.
  combo6(null, 'bt.ach.combo_6', combo: 6),
  combo7(null, 'bt.ach.combo_7', combo: 7),
  combo8(null, 'bt.ach.combo_8', combo: 8),
  combo9(null, 'bt.ach.combo_9', combo: 9),
  combo10(null, 'bt.ach.combo_10', combo: 10),
  combo11(null, 'bt.ach.combo_11', combo: 11),
  combo12(null, 'bt.ach.combo_12', combo: 12),
  combo13(null, 'bt.ach.combo_13', combo: 13),
  combo14(null, 'bt.ach.combo_14', combo: 14),
  combo15(null, 'bt.ach.combo_15', combo: 15),

  /// Summit: complete a level of difficulty 10.
  summit('CgkIhpCwrvAaEAIQCg', 'bt.ach.summit'),

  /// Pure Skill: complete a level of difficulty 7+ without Hint, Undo or
  /// Shuffle.
  pureSkill('CgkIhpCwrvAaEAIQCw', 'bt.ach.pure_skill');

  const GameAchievement(this.androidId, this.iosId, {this.levelsWon, this.combo, this.totalScore});

  /// Google Play Games ID; null when Play Games does not have it.
  final String? androidId;

  /// Apple Game Center ID.
  final String iosId;

  /// For the level-count achievements: the number of won levels that earns
  /// it; null for the others.
  final int? levelsWon;

  /// For the combo achievements: the best combo that earns it; null for the
  /// others.
  final int? combo;

  /// For the score achievements: the total score (sum of the best scores of
  /// all won levels) that earns it; null for the others.
  final int? totalScore;

  /// Lowest difficulty a level needs for [pureSkill].
  static const int pureSkillMinDifficulty = 7;

  /// Difficulty of the levels that earn [summit].
  static const int summitDifficulty = 10;
}

/// The leaderboards. Scores are whole numbers, higher is better, except the
/// Fastest Time boards (lower is better): Play Games' format there is
/// Duration (milliseconds), Game Center's "Elapsed Time - To the Hundredth of
/// a Second" (hundredths).
enum GameLeaderboard {
  /// Sum of the best scores of all won levels.
  totalScore('CgkIhpCwrvAaEAIQDA', 'bt.lb.total_score'),

  /// Number of won levels.
  levelsCompleted('CgkIhpCwrvAaEAIQDQ', 'bt.lb.levels'),

  /// Longest combo of any game.
  bestCombo('CgkIhpCwrvAaEAIQDg', 'bt.lb.best_combo'),

  /// Best Score · Difficulty 1 to 10: one game's score.
  scoreD1('CgkIhpCwrvAaEAIQDw', 'bt.lb.score_d1'),
  scoreD2('CgkIhpCwrvAaEAIQEA', 'bt.lb.score_d2'),
  scoreD3('CgkIhpCwrvAaEAIQEQ', 'bt.lb.score_d3'),
  scoreD4('CgkIhpCwrvAaEAIQEg', 'bt.lb.score_d4'),
  scoreD5('CgkIhpCwrvAaEAIQEw', 'bt.lb.score_d5'),
  scoreD6('CgkIhpCwrvAaEAIQFA', 'bt.lb.score_d6'),
  scoreD7('CgkIhpCwrvAaEAIQFQ', 'bt.lb.score_d7'),
  scoreD8('CgkIhpCwrvAaEAIQFg', 'bt.lb.score_d8'),
  scoreD9('CgkIhpCwrvAaEAIQFw', 'bt.lb.score_d9'),
  scoreD10('CgkIhpCwrvAaEAIQGA', 'bt.lb.score_d10'),

  /// Fastest Time · Difficulty 1 to 10: one game's time (see the enum).
  timeD1('CgkIhpCwrvAaEAIQGQ', 'bt.lb.time_d1'),
  timeD2('CgkIhpCwrvAaEAIQGg', 'bt.lb.time_d2'),
  timeD3('CgkIhpCwrvAaEAIQGw', 'bt.lb.time_d3'),
  timeD4('CgkIhpCwrvAaEAIQHA', 'bt.lb.time_d4'),
  timeD5('CgkIhpCwrvAaEAIQHQ', 'bt.lb.time_d5'),
  timeD6('CgkIhpCwrvAaEAIQHg', 'bt.lb.time_d6'),
  timeD7('CgkIhpCwrvAaEAIQHw', 'bt.lb.time_d7'),
  timeD8('CgkIhpCwrvAaEAIQIA', 'bt.lb.time_d8'),
  timeD9('CgkIhpCwrvAaEAIQIQ', 'bt.lb.time_d9'),
  timeD10('CgkIhpCwrvAaEAIQIg', 'bt.lb.time_d10');

  const GameLeaderboard(this.androidId, this.iosId);

  /// Google Play Games ID.
  final String androidId;

  /// Apple Game Center ID.
  final String iosId;

  static const List<GameLeaderboard> _bestScores = [
    scoreD1, scoreD2, scoreD3, scoreD4, scoreD5, scoreD6, scoreD7, scoreD8, scoreD9, scoreD10,
  ];

  static const List<GameLeaderboard> _fastestTimes = [
    timeD1, timeD2, timeD3, timeD4, timeD5, timeD6, timeD7, timeD8, timeD9, timeD10,
  ];

  /// Best Score · Difficulty [difficulty] (1 to 10), else null.
  static GameLeaderboard? bestScore(int difficulty) =>
      difficulty >= 1 && difficulty <= _bestScores.length ? _bestScores[difficulty - 1] : null;

  /// Fastest Time · Difficulty [difficulty] (1 to 10), else null.
  static GameLeaderboard? fastestTime(int difficulty) =>
      difficulty >= 1 && difficulty <= _fastestTimes.length ? _fastestTimes[difficulty - 1] : null;
}

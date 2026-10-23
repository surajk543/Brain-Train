import 'package:brain_train/app/play_games_reports.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/platform/game_services_ids.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter_test/flutter_test.dart';

LevelRecord _record({int timeMs = 60000, int? score = 1000, int? combo = 2}) =>
    LevelRecord(bestMoves: 10, bestTimeMs: timeMs, completedAt: DateTime(2026, 10, 17), bestScore: score, bestCombo: combo);

/// [count] won levels `level-0001`.. with the same record.
Map<String, LevelRecord> _wins(int count, {int? score = 1000, int? combo = 2}) => {
  for (var i = 1; i <= count; i++) 'level-${'$i'.padLeft(4, '0')}': _record(score: score, combo: combo),
};

WonGame _game({String? difficulty = '3', int hints = 0, int undos = 0, int shuffles = 0}) => WonGame(
  difficulty: difficulty,
  score: 2450,
  time: const Duration(minutes: 1, seconds: 2, milliseconds: 345),
  hintsUsed: hints,
  undosUsed: undos,
  shufflesUsed: shuffles,
);

Map<GameLeaderboard, int> _scores(PlayGamesReport report) => {for (final (board, value) in report.scores) board: value};

void main() {
  group('IDs', () {
    test('every ID is set, unique, and Game Center IDs follow bt.ach.<key> / bt.lb.<key>', () {
      final android = [
        for (final a in GameAchievement.values) ?a.androidId,
        for (final b in GameLeaderboard.values) b.androidId,
      ];
      expect(android.toSet(), hasLength(android.length));
      expect(android, everyElement(startsWith('CgkIhpCwrvAaEAIQ')));
      expect(GameAchievement.values.map((a) => a.iosId), everyElement(matches(RegExp(r'^bt\.ach\.[a-z0-9_]+$'))));
      expect(GameAchievement.values.map((a) => a.iosId).toSet(), hasLength(GameAchievement.values.length));
      expect(GameLeaderboard.values.map((b) => b.iosId), everyElement(matches(RegExp(r'^bt\.lb\.[a-z0-9_]+$'))));
      expect(GameAchievement.values, hasLength(38));
      // Combo x5 to x15; Play Games has only x5.
      final combos = [for (final a in GameAchievement.values) if (a.combo != null) a];
      expect([for (final a in combos) a.combo], [for (var n = 5; n <= 15; n++) n]);
      expect([for (final a in combos) a.iosId], [for (var n = 5; n <= 15; n++) 'bt.ach.combo_$n']);
      // Level counts in order; Play Games has 1, 10, 50, 100, 250 and 500.
      const playGamesLevels = [1, 10, 50, 100, 250, 500];
      final levels = [for (final a in GameAchievement.values) if (a.levelsWon != null) a];
      expect([for (final a in levels) a.levelsWon], [1, 10, 50, 75, 100, 150, 200, 250, 300, 350, 400, 500, 600]);
      for (final a in levels.skip(1)) {
        expect(a.iosId, 'bt.ach.levels_${a.levelsWon}');
      }
      // Total score 2k to 50k.
      final scores = [for (final a in GameAchievement.values) if (a.totalScore != null) a];
      const thousands = [2, 5, 8, 10, 12, 15, 20, 25, 30, 35, 40, 50];
      expect([for (final a in scores) a.totalScore], [for (final k in thousands) k * 1000]);
      expect([for (final a in scores) a.iosId], [for (final k in thousands) 'bt.ach.score_${k}k']);
      // Game Center only: combo x6+, the new level counts, every score one.
      expect([for (final a in GameAchievement.values) if (a.androidId == null) a], unorderedEquals([
        ...combos.skip(1),
        for (final a in levels) if (!playGamesLevels.contains(a.levelsWon)) a,
        ...scores,
      ]));
      expect(GameLeaderboard.values, hasLength(23));
      expect(GameAchievement.pureSkill.iosId, 'bt.ach.pure_skill');
      expect(GameLeaderboard.levelsCompleted.iosId, 'bt.lb.levels');
    });

    test('per-difficulty boards for 1 to 10 only', () {
      for (var d = 1; d <= 10; d++) {
        expect(GameLeaderboard.bestScore(d)!.iosId, 'bt.lb.score_d$d');
        expect(GameLeaderboard.fastestTime(d)!.iosId, 'bt.lb.time_d$d');
      }
      expect(GameLeaderboard.bestScore(0), isNull);
      expect(GameLeaderboard.fastestTime(11), isNull);
    });
  });

  group('a win', () {
    test("its tier's Best Score and Fastest Time, and the totals of all wins", () {
      final completed = {
        'level-0001': _record(score: 1200, combo: 3),
        'level-0002': _record(score: 2450, combo: 4),
        'level-0003': _record(score: null, combo: null),
      };
      final report = reportForWin(_game(), completed, GamesService.googlePlayGames);
      expect(_scores(report), {
        GameLeaderboard.scoreD3: 2450,
        GameLeaderboard.timeD3: 62345,
        GameLeaderboard.totalScore: 3650,
        GameLeaderboard.levelsCompleted: 3,
        GameLeaderboard.bestCombo: 4,
      });
    });

    test('times: milliseconds on Play Games, hundredths on Game Center', () {
      final completed = _wins(1);
      expect(_scores(reportForWin(_game(), completed, GamesService.googlePlayGames))[GameLeaderboard.timeD3], 62345);
      expect(_scores(reportForWin(_game(), completed, GamesService.gameCenter))[GameLeaderboard.timeD3], 6234);
      expect(leaderboardTime(999, GamesService.gameCenter), 99);
      expect(leaderboardTime(999, GamesService.googlePlayGames), 999);
    });

    test('a named or unknown tier: no per-difficulty boards, totals still', () {
      for (final tier in ['veryHard', null, '11', '07']) {
        final report = reportForWin(_game(difficulty: tier), _wins(2), GamesService.googlePlayGames);
        expect(_scores(report).keys, [GameLeaderboard.totalScore, GameLeaderboard.levelsCompleted, GameLeaderboard.bestCombo], reason: '$tier');
      }
    });

    test('level-count achievements at 1, 10, 50, 100, 250 and 500 wins', () {
      List<GameAchievement> earned(int count) => reportForWin(_game(), _wins(count), GamesService.googlePlayGames).achievements;
      expect(earned(1), [GameAchievement.firstWin]);
      expect(earned(9), [GameAchievement.firstWin]);
      expect(earned(10), [GameAchievement.firstWin, GameAchievement.levels10]);
      expect(earned(49), [GameAchievement.firstWin, GameAchievement.levels10]);
      expect(earned(50), [GameAchievement.firstWin, GameAchievement.levels10, GameAchievement.levels50]);
      expect(earned(100), contains(GameAchievement.levels100));
      expect(earned(249), isNot(contains(GameAchievement.levels250)));
      expect(earned(250), contains(GameAchievement.levels250));
      expect(earned(499), isNot(contains(GameAchievement.levels500)));
      expect(earned(500), [
        GameAchievement.firstWin,
        GameAchievement.levels10,
        GameAchievement.levels50,
        GameAchievement.levels100,
        GameAchievement.levels250,
        GameAchievement.levels500,
      ]);
    });

    test('Combo Master from a best combo of 5', () {
      expect(reportForWin(_game(), _wins(3, combo: 4), GamesService.googlePlayGames).achievements, isNot(contains(GameAchievement.combo5)));
      expect(reportForWin(_game(), _wins(3, combo: 5), GamesService.googlePlayGames).achievements, contains(GameAchievement.combo5));
      expect(reportForWin(_game(), _wins(3, combo: 9), GamesService.googlePlayGames).achievements, contains(GameAchievement.combo5));
    });

    test('more level counts and the total-score ladder on Game Center only', () {
      List<GameAchievement> earned(int count, {int score = 1000, GamesService service = GamesService.gameCenter}) => [
        for (final a in reportForWin(_game(), _wins(count, score: score), service).achievements)
          if (a.levelsWon != null || a.totalScore != null) a,
      ];
      // 160 wins of 1,000 points: levels up to 150, total 160,000.
      expect(earned(160), [
        GameAchievement.firstWin,
        GameAchievement.levels10,
        GameAchievement.levels50,
        GameAchievement.levels75,
        GameAchievement.levels100,
        GameAchievement.levels150,
        for (final a in GameAchievement.values)
          if (a.totalScore != null) a,
      ]);
      // 3 wins of 3,000 points: 9,000 in total.
      expect([for (final a in earned(3, score: 3000)) if (a.totalScore != null) a],
          [GameAchievement.score2k, GameAchievement.score5k, GameAchievement.score8k]);
      expect(earned(1, score: 1999), [GameAchievement.firstWin]);
      expect(earned(600, score: 100), contains(GameAchievement.levels600));
      expect(earned(160, service: GamesService.googlePlayGames),
          [GameAchievement.firstWin, GameAchievement.levels10, GameAchievement.levels50, GameAchievement.levels100]);
    });

    test('combo x6 to x15 on Game Center only', () {
      List<GameAchievement> combos(int best, GamesService service) => [
        for (final a in reportForWin(_game(), _wins(3, combo: best), service).achievements)
          if (a.combo != null) a,
      ];
      expect(combos(9, GamesService.gameCenter), [
        GameAchievement.combo5,
        GameAchievement.combo6,
        GameAchievement.combo7,
        GameAchievement.combo8,
        GameAchievement.combo9,
      ]);
      expect(combos(15, GamesService.gameCenter), hasLength(11));
      expect(combos(40, GamesService.gameCenter).last, GameAchievement.combo15);
      expect(combos(4, GamesService.gameCenter), isEmpty);
      expect(combos(15, GamesService.googlePlayGames), [GameAchievement.combo5]);
    });

    test('Pure Skill: difficulty 7+ without Hint, Undo or Shuffle', () {
      bool pure(WonGame game) => reportForWin(game, _wins(1), GamesService.googlePlayGames).achievements.contains(GameAchievement.pureSkill);
      expect(pure(_game(difficulty: '7')), isTrue);
      expect(pure(_game(difficulty: '10')), isTrue);
      expect(pure(_game(difficulty: '6')), isFalse);
      expect(pure(_game(difficulty: '7', hints: 1)), isFalse);
      expect(pure(_game(difficulty: '8', undos: 1)), isFalse);
      expect(pure(_game(difficulty: '9', shuffles: 2)), isFalse);
      expect(pure(_game(difficulty: 'veryHard')), isFalse);
    });

    test('Summit: a difficulty-10 win only', () {
      bool summit(String tier) => reportForWin(_game(difficulty: tier), _wins(1), GamesService.googlePlayGames).achievements.contains(GameAchievement.summit);
      expect(summit('10'), isTrue);
      expect(summit('9'), isFalse);
      expect(summit('veryHard'), isFalse);
    });
  });

  group('the catch-up', () {
    test("each tier's best score and fastest time over its wins, then the totals", () {
      final completed = {
        'a': _record(score: 900, timeMs: 50000, combo: 2),
        'b': _record(score: 1500, timeMs: 70000, combo: 6),
        'c': _record(score: 400, timeMs: 30010, combo: 1),
        'named': _record(score: 5000, timeMs: 1000),
        'gone': _record(score: 100, timeMs: 1000),
        'old': _record(score: null, timeMs: 40000, combo: null),
      };
      const tiers = {'a': '2', 'b': '2', 'c': '10', 'named': 'veryHard', 'old': '5'};
      final android = reportForProgress(completed, tiers, GamesService.googlePlayGames);
      expect(android.scores, [
        (GameLeaderboard.scoreD2, 1500),
        (GameLeaderboard.timeD2, 50000),
        (GameLeaderboard.timeD5, 40000),
        (GameLeaderboard.scoreD10, 400),
        (GameLeaderboard.timeD10, 30010),
        (GameLeaderboard.totalScore, 7900),
        (GameLeaderboard.levelsCompleted, 6),
        (GameLeaderboard.bestCombo, 6),
      ]);
      expect(android.achievements, [GameAchievement.firstWin, GameAchievement.combo5, GameAchievement.summit]);
      final iOS = reportForProgress(completed, tiers, GamesService.gameCenter);
      expect(iOS.achievements, [
        GameAchievement.firstWin,
        GameAchievement.score2k,
        GameAchievement.score5k,
        GameAchievement.combo5,
        GameAchievement.combo6,
        GameAchievement.summit,
      ]);
      expect(_scores(iOS)[GameLeaderboard.timeD10], 3001);
      expect(_scores(iOS)[GameLeaderboard.timeD2], 5000);
    });

    test('no Summit without a difficulty-10 win; never Pure Skill', () {
      final report = reportForProgress(_wins(12, combo: 5), {for (final id in _wins(12).keys) id: '9'}, GamesService.googlePlayGames);
      expect(report.achievements, [GameAchievement.firstWin, GameAchievement.levels10, GameAchievement.combo5]);
    });

    test('nothing before the first win', () {
      final report = reportForProgress(const {}, const {'level-0001': '1'}, GamesService.googlePlayGames);
      expect(report.scores, isEmpty);
      expect(report.achievements, isEmpty);
    });
  });
}

import 'dart:async';

import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/app/play_games_reports.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/platform/game_services_ids.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_play_games.dart';
import 'package:brain_train/data/age_group.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlayGames fake;
  late PlayGamesController controller;

  setUp(() {
    fake = FakePlayGames();
    controller = PlayGamesController(fake, noticeDuration: const Duration(milliseconds: 30));
  });

  tearDown(() => controller.dispose());

  test('unavailable: not available, start does nothing', () {
    final none = PlayGamesController(const UnavailablePlayGames());
    expect(none.available, isFalse);
    none.start(AgeGroup.thirteenPlus);
    none.dispose();
  });

  test('start runs the silent check once and follows the status', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    controller
      ..start(AgeGroup.thirteenPlus)
      ..start(AgeGroup.thirteenPlus);
    expect(fake.refreshes, 1);
    fake.emit(const PlayGamesSignedIn('Ann'));
    await _settle();
    expect(controller.status, const PlayGamesSignedIn('Ann'));
    expect(notified, 1);
  });

  test('under 13 (or no answer yet): never started, no buttons, no sign-in on tap', () async {
    for (final age in [AgeGroup.under13, null]) {
      final local = FakePlayGames();
      final child = PlayGamesController(local);
      child.start(age);
      expect(child.available, isFalse, reason: '$age');
      expect(local.refreshes, 0, reason: '$age: no silent sign-in check');
      await child.openAchievements();
      expect(local.calls, isEmpty, reason: '$age: no sign-in dialog');
      child.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(local.refreshes, 0);
      child.dispose();
    }
  });

  test('resume checks again', () {
    controller.start(AgeGroup.thirteenPlus);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(fake.refreshes, 2);
  });

  test('signed in: opens the screen', () async {
    fake.emit(const PlayGamesSignedIn('Ann'));
    await controller.openAchievements();
    await controller.openLeaderboards();
    expect(fake.calls, ['achievements', 'leaderboards']);
    expect(controller.notice, isNull);
  });

  test('signed out: signs in, then opens the screen', () async {
    await controller.openAchievements();
    expect(fake.calls, ['signIn', 'achievements']);
  });

  test('opens the screen after sign-in even before a status event', () async {
    fake.emitOnSignIn = false;
    await controller.openLeaderboards();
    expect(fake.calls, ['signIn', 'leaderboards']);
  });

  test('cancelled sign-in: nothing else, no notice', () async {
    fake.signInResult = PlayGamesSignIn.cancelled;
    await controller.openAchievements();
    expect(fake.calls, ['signIn']);
    expect(controller.notice, isNull);
  });

  test('failed sign-in or screen: notice, then it clears', () async {
    fake.signInResult = PlayGamesSignIn.failed;
    await controller.openAchievements();
    expect(fake.calls, ['signIn']);
    expect(controller.notice, PlayGamesController.failedNotice);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.notice, isNull);

    fake
      ..signInResult = PlayGamesSignIn.signedIn
      ..showResult = false;
    await controller.openLeaderboards();
    expect(controller.notice, PlayGamesController.failedNotice);
  });

  test('taps during a call are ignored', () async {
    fake.gate = Completer<void>();
    final first = controller.openAchievements();
    expect(controller.busy, isTrue);
    unawaited(controller.openAchievements());
    unawaited(controller.openLeaderboards());
    fake.gate!.complete();
    await first;
    expect(fake.calls, ['signIn', 'achievements']);
    expect(controller.busy, isFalse);
  });

  test('a resume during sign-in still opens one screen', () async {
    controller.start(AgeGroup.thirteenPlus);
    fake.gate = Completer<void>();
    final open = controller.openAchievements();
    await _settle();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    fake.gate!.complete();
    await open;
    expect(fake.calls, ['signIn', 'achievements']);
    expect(fake.refreshes, 2);
  });

  test('notice timer after dispose is harmless', () async {
    final local = PlayGamesController(FakePlayGames()..signInResult = PlayGamesSignIn.failed,
        noticeDuration: const Duration(milliseconds: 10));
    await local.openAchievements();
    expect(local.notice, isNotNull);
    local.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test('dispose disposes the PlayGames', () {
    final local = FakePlayGames();
    PlayGamesController(local).dispose();
    expect(local.disposed, isTrue);
  });

  test('Game Center: its own failure notice', () async {
    fake
      ..service = GamesService.gameCenter
      ..signInResult = PlayGamesSignIn.failed;
    await controller.openLeaderboards();
    expect(controller.notice, PlayGamesController.gameCenterFailedNotice);
  });

  group('reports', () {
    late ProgressRepository progress;
    late int difficultyReads;
    const tiers = {'level-0001': '1', 'level-0002': '7', 'level-0003': '10', 'level-0004': 'veryHard'};

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      progress = await ProgressRepository.open();
      difficultyReads = 0;
      controller.attachProgress(
        progress,
        difficulties: () {
          difficultyReads++;
          return tiers;
        },
      );
    });

    /// Difficulty 7, no helper used: Pure Skill.
    const pureWin = WonGame(difficulty: '7', score: 3000, time: Duration(seconds: 90, milliseconds: 456));

    /// Records the win as the game does, then reports it.
    Future<void> win(String levelId, WonGame game, {int combo = 2}) async {
      await progress.recordWin(levelId, moves: 20, timeMs: game.time.inMilliseconds, score: game.score, bestCombo: combo);
      controller.reportWin(game);
      await _settle();
    }

    Future<void> signIn() async {
      controller.start(AgeGroup.thirteenPlus);
      fake.emit(const PlayGamesSignedIn('Ann'));
      await _settle();
    }

    test("a win, signed in at 13+: its tier's boards, the totals, the achievements with banners", () async {
      await signIn();
      expect(fake.unlocks, isEmpty, reason: 'nothing to catch up yet');
      expect(fake.scores, isEmpty);
      await win('level-0002', pureWin, combo: 5);
      expect(fake.unlocks, [
        (GameAchievement.firstWin, true),
        (GameAchievement.combo5, true),
        (GameAchievement.pureSkill, true),
      ]);
      expect(fake.scores, [
        (GameLeaderboard.scoreD7, 3000),
        (GameLeaderboard.timeD7, 90456),
        (GameLeaderboard.totalScore, 3000),
        (GameLeaderboard.levelsCompleted, 1),
        (GameLeaderboard.bestCombo, 5),
      ]);
    });

    test('Game Center: Fastest Time in hundredths of a second', () async {
      fake.service = GamesService.gameCenter;
      await signIn();
      await win('level-0002', pureWin);
      expect(fake.submitted[GameLeaderboard.timeD7], 9045);
      expect(fake.submitted[GameLeaderboard.scoreD7], 3000);
    });

    test('helpers used or a lower tier: no Pure Skill; a difficulty-10 win: Summit', () async {
      await signIn();
      await win('level-0002', const WonGame(difficulty: '7', score: 900, time: Duration(seconds: 50), hintsUsed: 1));
      await win('level-0001', const WonGame(difficulty: '1', score: 800, time: Duration(seconds: 20)));
      expect(fake.unlocked, [GameAchievement.firstWin]);
      await win('level-0003', const WonGame(difficulty: '10', score: 5000, time: Duration(minutes: 4), undosUsed: 1));
      expect(fake.unlocked, [GameAchievement.firstWin, GameAchievement.summit]);
    });

    test('a named tier: totals only; replays report again, achievements go once per run', () async {
      await signIn();
      await win('level-0004', const WonGame(difficulty: 'veryHard', score: 700, time: Duration(seconds: 30)));
      expect(fake.submitted.keys, [GameLeaderboard.totalScore, GameLeaderboard.levelsCompleted, GameLeaderboard.bestCombo]);
      fake.scores.clear();
      await win('level-0004', const WonGame(difficulty: 'veryHard', score: 900, time: Duration(seconds: 40)));
      expect(fake.unlocked, [GameAchievement.firstWin]);
      expect(fake.submitted, {
        GameLeaderboard.totalScore: 900,
        GameLeaderboard.levelsCompleted: 1,
        GameLeaderboard.bestCombo: 2,
      });
    });

    test('signed out: nothing', () async {
      controller.start(AgeGroup.thirteenPlus);
      await win('level-0002', pureWin);
      expect(fake.unlocks, isEmpty);
      expect(fake.scores, isEmpty);
    });

    test('under 13, no age answer or never started: nothing, even signed in', () async {
      for (final age in [AgeGroup.under13, null]) {
        final local = FakePlayGames(const PlayGamesSignedIn('Kid'));
        final child = PlayGamesController(local)
          ..attachProgress(progress, difficulties: () => tiers)
          ..start(age);
        local.emit(const PlayGamesSignedIn('Kid'));
        await progress.recordWin('level-0003', moves: 9, timeMs: 1000, score: 100, bestCombo: 5);
        child.reportWin(pureWin);
        await _settle();
        expect(local.unlocks, isEmpty, reason: '$age');
        expect(local.scores, isEmpty, reason: '$age');
        child.dispose();
      }
      final notStarted = FakePlayGames(const PlayGamesSignedIn('Ann'));
      final idle = PlayGamesController(notStarted)..attachProgress(progress, difficulties: () => tiers);
      idle.reportWin(pureWin);
      await _settle();
      expect(notStarted.scores, isEmpty);
      idle.dispose();
    });

    group('catch-up after sign-in', () {
      Future<void> earlierWins() async {
        await progress.recordWin('level-0001', moves: 9, timeMs: 21000, score: 1100, bestCombo: 3);
        await progress.recordWin('level-0003', moves: 30, timeMs: 240000, score: 4000, bestCombo: 6);
        await progress.recordWin('level-0099', moves: 30, timeMs: 1000, score: 50);
      }

      test('what the progress earned, silently, exactly once per run', () async {
        await earlierWins();
        controller.start(AgeGroup.thirteenPlus);
        await _settle();
        expect(fake.scores, isEmpty, reason: 'not signed in yet');
        fake.emit(const PlayGamesSignedIn('Ann'));
        await _settle();
        expect(fake.unlocks, [
          (GameAchievement.firstWin, false),
          (GameAchievement.combo5, false),
          (GameAchievement.summit, false),
        ]);
        expect(fake.scores, [
          (GameLeaderboard.scoreD1, 1100),
          (GameLeaderboard.timeD1, 21000),
          (GameLeaderboard.scoreD10, 4000),
          (GameLeaderboard.timeD10, 240000),
          (GameLeaderboard.totalScore, 5150),
          (GameLeaderboard.levelsCompleted, 3),
          (GameLeaderboard.bestCombo, 6),
        ]);
        expect(difficultyReads, 1);

        // Signed out and in again, a resume: no second catch-up.
        fake
          ..emit(const PlayGamesSignedOut())
          ..emit(const PlayGamesSignedIn('Ann'));
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _settle();
        expect(fake.unlocks, hasLength(3));
        expect(fake.scores, hasLength(7));
        expect(difficultyReads, 1);
      });

      test('already signed in at start: at once; a later win unlocks only what is new', () async {
        await earlierWins();
        final local = FakePlayGames(const PlayGamesSignedIn('Ann'));
        final signedIn = PlayGamesController(local)
          ..attachProgress(progress, difficulties: () => tiers)
          ..start(AgeGroup.thirteenPlus);
        await _settle();
        expect(local.unlocked, [GameAchievement.firstWin, GameAchievement.combo5, GameAchievement.summit]);
        local.unlocks.clear();
        await progress.recordWin('level-0002', moves: 20, timeMs: 90456, score: 3000, bestCombo: 2);
        signedIn.reportWin(pureWin);
        await _settle();
        expect(local.unlocks, [(GameAchievement.pureSkill, true)]);
        signedIn.dispose();
      });

      test('a manual sign-in from the lobby starts it too', () async {
        await earlierWins();
        controller.start(AgeGroup.thirteenPlus);
        await controller.openAchievements();
        await _settle();
        expect(fake.calls, ['signIn', 'achievements']);
        expect(fake.unlocked, [GameAchievement.firstWin, GameAchievement.combo5, GameAchievement.summit]);
      });
    });

    test('failures are swallowed; a failed unlock is tried again by the next win', () async {
      await signIn();
      fake.reportError = StateError('plugin gone');
      await win('level-0002', pureWin);
      expect(fake.unlocked, [GameAchievement.firstWin, GameAchievement.pureSkill]);
      expect(fake.scores, hasLength(5), reason: 'one failure does not stop the rest');
      fake
        ..reportError = null
        ..reportResult = false;
      await win('level-0001', const WonGame(difficulty: '1', score: 100, time: Duration(seconds: 9)));
      expect(fake.unlocked, [GameAchievement.firstWin, GameAchievement.pureSkill, GameAchievement.firstWin]);
      fake.reportResult = true;
      await win('level-0002', pureWin);
      expect(fake.unlocked.skip(3), [GameAchievement.firstWin, GameAchievement.pureSkill]);
      await win('level-0002', pureWin);
      expect(fake.unlocked, hasLength(5), reason: 'unlocked now: not sent again');
    });

    test('a catch-up whose tiers cannot be read is swallowed', () async {
      await progress.recordWin('level-0001', moves: 9, timeMs: 21000, score: 1100, bestCombo: 3);
      final local = FakePlayGames();
      final broken = PlayGamesController(local)
        ..attachProgress(progress, difficulties: () => throw StateError('no manifest'))
        ..start(AgeGroup.thirteenPlus);
      local.emit(const PlayGamesSignedIn('Ann'));
      await _settle();
      expect(local.scores, isEmpty);
      broken.reportWin(const WonGame(difficulty: '1', score: 100, time: Duration(seconds: 9)));
      await _settle();
      expect(local.unlocked, [GameAchievement.firstWin]);
      broken.dispose();
    });
  });
}

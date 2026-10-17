import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/platform/game_services_ids.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_play_games.dart';
import 'lobby_support.dart';
import 'package:brain_train/data/age_group.dart';

const _achievements = ValueKey('lobby-achievements');
const _leaderboards = ValueKey('lobby-leaderboards');

Future<AppServices> _services(WidgetTester tester, PlayGames playGames) async {
  late AppServices services;
  await tester.runAsync(() async {
    services = await testServices(playGames: PlayGamesController(playGames), ageGroup: AgeGroup.thirteenPlus);
  });
  return services;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Brain Train',
      packageName: 'com.sungamestudio.braintrain',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('no Play Games: no buttons', (tester) async {
    final services = await _services(tester, const UnavailablePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.byKey(_achievements), findsNothing);
    expect(find.byKey(_leaderboards), findsNothing);
    await _leave(tester);
  });

  testWidgets('signed out or in: both buttons, with labels; the lobby starts the check', (tester) async {
    final fake = FakePlayGames();
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.byKey(_achievements), findsOneWidget);
    expect(find.byKey(_leaderboards), findsOneWidget);
    expect(find.bySemanticsLabel('Achievements'), findsOneWidget);
    expect(find.bySemanticsLabel('Leaderboards'), findsOneWidget);
    expect(fake.refreshes, 1);
    fake.emit(const PlayGamesSignedIn('Ann'));
    await tester.pump();
    expect(find.byKey(_achievements), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('signed in: a tap opens the screen', (tester) async {
    final fake = FakePlayGames(const PlayGamesSignedIn('Ann'));
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _achievements);
    await _tap(tester, _leaderboards);
    expect(fake.calls, ['achievements', 'leaderboards']);
    await _leave(tester);
  });

  testWidgets('signed out: a tap signs in, then opens the screen', (tester) async {
    final fake = FakePlayGames();
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _leaderboards);
    expect(fake.calls, ['signIn', 'leaderboards']);
    await _leave(tester);
  });

  testWidgets('a failure shows the notice in the footer, then it goes', (tester) async {
    final fake = FakePlayGames()..signInResult = PlayGamesSignIn.failed;
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _achievements);
    expect(find.text(PlayGamesController.failedNotice), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text(PlayGamesController.failedNotice), findsNothing);
    await _leave(tester);
  });

  testWidgets('a cancelled sign-in shows nothing', (tester) async {
    final fake = FakePlayGames()..signInResult = PlayGamesSignIn.cancelled;
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _achievements);
    expect(fake.calls, ['signIn']);
    expect(find.text(PlayGamesController.failedNotice), findsNothing);
    await _leave(tester);
  });

  testWidgets("sign-in catches up the stored wins once, on the manifest's tiers", (tester) async {
    final fake = FakePlayGames();
    final services = await _services(tester, fake);
    final levels = services.content.snapshot.manifest.levels;
    final first = levels.first;
    final top = levels.firstWhere((level) => level.difficulty == '10');
    await tester.runAsync(() async {
      await services.progress.recordWin(first.levelId, moves: 30, timeMs: 45000, score: 2100, bestCombo: 3);
      await services.progress.recordWin(top.levelId, moves: 90, timeMs: 300000, score: 9000, bestCombo: 4);
    });
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(fake.scores, isEmpty, reason: 'not signed in yet');
    fake.emit(const PlayGamesSignedIn('Ann'));
    await tester.pump();
    final firstTier = int.parse(first.difficulty!);
    expect(fake.unlocks, [(GameAchievement.firstWin, false), (GameAchievement.summit, false)]);
    expect(fake.submitted, {
      GameLeaderboard.bestScore(firstTier)!: 2100,
      GameLeaderboard.fastestTime(firstTier)!: 45000,
      GameLeaderboard.scoreD10: 9000,
      GameLeaderboard.timeD10: 300000,
      GameLeaderboard.totalScore: 11100,
      GameLeaderboard.levelsCompleted: 2,
      GameLeaderboard.bestCombo: 4,
    });
    fake
      ..emit(const PlayGamesSignedOut())
      ..emit(const PlayGamesSignedIn('Ann'));
    await tester.pump();
    expect(fake.scores, hasLength(7), reason: 'once per run');
    await _leave(tester);
  });

  testWidgets('small phone with large text lays out', (tester) async {
    final services = await _services(tester, FakePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_achievements), findsOneWidget);
    expect(find.byKey(const ValueKey('lobby-play')), findsOneWidget);
    await _leave(tester);
  });
}

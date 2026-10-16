import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/features/home/home_screen.dart';
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

  testWidgets('small phone with large text lays out', (tester) async {
    final services = await _services(tester, FakePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_achievements), findsOneWidget);
    expect(find.byKey(const ValueKey('lobby-play')), findsOneWidget);
    await _leave(tester);
  });
}

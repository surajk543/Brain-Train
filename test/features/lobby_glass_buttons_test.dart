import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/features/common/frosted_glass.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_play_games.dart';
import 'lobby_support.dart';

Future<AppServices> _services(WidgetTester tester, PlayGames playGames) async {
  late AppServices services;
  await tester.runAsync(() async {
    services = await testServices(playGames: PlayGamesController(playGames));
  });
  return services;
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Finder _glassIn(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(FrostedGlass));

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

  testWidgets('Play, Levels and Settings are frosted glass', (tester) async {
    final services = await _services(tester, const UnavailablePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen());
    for (final key in ['lobby-play', 'lobby-levels', 'lobby-settings']) {
      expect(_glassIn(key), findsOneWidget, reason: key);
    }
    expect(find.byType(BackdropFilter), findsNothing);
    await _leave(tester);
  });

  testWidgets('the round Play Games buttons are frosted glass', (tester) async {
    final services = await _services(tester, FakePlayGames(const PlayGamesSignedIn('Tester')));
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(_glassIn('lobby-achievements'), findsOneWidget);
    expect(_glassIn('lobby-leaderboards'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    await _leave(tester);
  });

  testWidgets('taps and semantics are unchanged', (tester) async {
    final services = await _services(tester, const UnavailablePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.bySemanticsLabel('Completed Levels'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lobby-settings')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('small phone with large text lays out', (tester) async {
    final services = await _services(tester, FakePlayGames(const PlayGamesSignedIn('Tester')));
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(_glassIn('lobby-play'), findsOneWidget);
    await _leave(tester);
  });
}

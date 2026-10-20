// Renders the real lobby (home, Levels, Settings) in the Night look at phone
// and tablet sizes (redesign 1.1.0, reference board panels 1-2 and Settings).
//
// Always checks that layout succeeds without exceptions or overflow. When
// CAPTURE_DIR is set, also writes PNG screenshots there for visual review:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/lobby_capture_test.dart
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/intro/age_screen.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:brain_train/features/home/widgets/lobby_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/lobby_support.dart';
import '../platform/fake_play_games.dart';
import '../platform/fake_rewarded_ads.dart';
import 'package:brain_train/data/age_group.dart';

/// Level 1 won and level 2 in progress, as in the reference ("Continue · Level 2").
Future<void> _midway(AppServices services) async {
  final entries = services.content.snapshot.playableEntries;
  await services.progress.recordWin(entries[0].levelId, moves: 8, timeMs: 41000);
  await services.progress.saveGame(
    SavedGame(levelId: entries[1].levelId, levelUrl: entries[1].ref.url, history: const [], moveCount: 0, elapsedMs: 0),
  );
}

void main() {
  setUpAll(loadCaptureFonts);

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

  const look = 'night';

  for (final phone in [smallPhone, midPhone, largePhone, tallPhone, ipad13]) {
    testWidgets('$look lobby ${phone.name}: home, levels, settings', (tester) async {
      late AppServices services;
      await tester.runAsync(() async {
        // Content up to date (the host serves the starter pack): the
        // status line shows the ready levels, not a notice.
        services = await testServices(client: starterHost);
        await _midway(services);
        await services.content.topUp();
      });
      await pumpLobby(tester, services: services, home: const HomeScreen(), phone: phone);
      expect(tester.takeException(), isNull);
      expect(find.text('Continue · Level 2'), findsOneWidget);
      expect(find.byType(LobbyHero), findsOneWidget);
      expect(find.bySemanticsLabel('Tile Park'), findsOneWidget);
      // Levels 2-6 are the window; level 6 is not on the device.
      expect(find.text('4 levels ready · v${services.content.snapshot.contentVersion}'), findsOneWidget);
      await captureLobby(tester, '$look-home-${phone.name}', phone.dpr);

      await tester.tap(find.text('Levels'));
      await settleLobby(tester);
      expect(tester.takeException(), isNull);
      // Level 2 is in progress: it is the level offered above the list.
      expect(find.text(services.content.snapshot.playableEntries[1].title), findsOneWidget);
      await captureLobby(tester, '$look-levels-${phone.name}', phone.dpr);
      await tester.pageBack();
      await settleLobby(tester);

      await tester.tap(find.text('Settings'));
      await settleLobby(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Sound Effects'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      await captureLobby(tester, '$look-settings-${phone.name}', phone.dpr);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('$look lobby 360x640 at 1.3x text: no overflow', (tester) async {
    late AppServices services;
    await tester.runAsync(() async {
      services = await testServices();
      await _midway(services);
    });
    await pumpLobby(
      tester,
      services: services,
      home: const HomeScreen(),
      phone: smallPhone,
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Continue · Level 2'), findsOneWidget);
    await captureLobby(tester, '$look-home-360x640-text130', smallPhone.dpr);
    await tester.tap(find.text('Levels'));
    await settleLobby(tester);
    expect(tester.takeException(), isNull);
    await captureLobby(tester, '$look-levels-360x640-text130', smallPhone.dpr);
    await tester.pageBack();
    await settleLobby(tester);
    await tester.tap(find.text('Settings'));
    await settleLobby(tester);
    expect(tester.takeException(), isNull);
    await captureLobby(tester, '$look-settings-360x640-text130', smallPhone.dpr);
    await tester.pumpWidget(const SizedBox());
  });

  for (final phone in [largePhone, smallPhone, tallPhone]) {
    testWidgets('lobby ${phone.name}: Play Games buttons', (tester) async {
      late AppServices services;
      await tester.runAsync(() async {
        services = await testServices(
          playGames: PlayGamesController(FakePlayGames(const PlayGamesSignedIn('Tester'))),
          ageGroup: AgeGroup.thirteenPlus,
        );
        await _midway(services);
      });
      await pumpLobby(tester, services: services, home: const HomeScreen(), phone: phone);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('lobby-achievements')), findsOneWidget);
      await captureLobby(tester, 'lobby-play-games-${phone.name}', phone.dpr);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  for (final phone in [largePhone, smallPhone, tallPhone]) {
    testWidgets('age screen ${phone.name}: decades, then years', (tester) async {
      late AppServices services;
      await tester.runAsync(() async => services = await testServices());
      await pumpLobby(
        tester,
        services: services,
        home: AgeScreen(onAnswered: (_) {}, now: () => DateTime(2026, 10, 16)),
        phone: phone,
      );
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'age-decades-${phone.name}', phone.dpr);
      await tester.tap(find.text('1990s'));
      await settleLobby(tester);
      await tester.tap(find.text('1994'));
      await settleLobby(tester);
      expect(find.byKey(const ValueKey('age-continue')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'age-years-${phone.name}', phone.dpr);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('settings with Privacy choices (EEA/UK)', (tester) async {
    late AppServices services;
    await tester.runAsync(
      () async => services = await testServices(ads: RewardedAdsController(FakeRewardedAds()..setPrivacyOptionsRequired(true))),
    );
    await pumpLobby(tester, services: services, home: const SettingsScreen(), phone: smallPhone);
    expect(find.text('Privacy choices'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureLobby(tester, 'settings-privacy-360x640', smallPhone.dpr);
    await tester.pumpWidget(const SizedBox());
  });
}

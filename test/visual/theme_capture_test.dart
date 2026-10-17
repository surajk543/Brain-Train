// Renders the existing screens in both looks (Day and Night, redesign 1.1.0)
// at phone sizes: the lobby (home, Levels, Settings), the age
// screen and gameplay (mid-game, Level Complete, Tray full).
//
// Always checks that layout succeeds without exceptions or overflow and that
// each screen got its look's tokens. When CAPTURE_DIR is set, also writes
// `<look>-<screen>-<phone>.png` there for visual review:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/theme_capture_test.dart
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/intro/age_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/lobby_support.dart';
import 'gameplay_support.dart';

/// Level 1 won and level 2 in progress ("Continue · Level 2").
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

  for (final (look, mode) in [('day', ThemeMode.light), ('night', ThemeMode.dark)]) {
    void expectLook(WidgetTester tester, Type screen) {
      final palette = BrainTrainPalette.of(tester.element(find.byType(screen)));
      expect(palette.isNight, look == 'night', reason: '$screen in $look');
    }

    for (final phone in [smallPhone, largePhone]) {
      testWidgets('$look lobby ${phone.name}: home, levels, settings', (tester) async {
        late AppServices services;
        await tester.runAsync(() async {
          services = await testServices();
          await _midway(services);
        });
        await pumpLobby(tester, services: services, home: const HomeScreen(), phone: phone, themeMode: mode);
        expect(find.text('Continue · Level 2'), findsOneWidget);
        expectLook(tester, HomeScreen);
        expect(tester.takeException(), isNull);
        await captureLobby(tester, '$look-home-${phone.name}', phone.dpr);

        await tester.tap(find.text('Levels'));
        await settleLobby(tester);
        expect(tester.takeException(), isNull);
        await captureLobby(tester, '$look-levels-${phone.name}', phone.dpr);
        await tester.pageBack();
        await settleLobby(tester);

        await tester.tap(find.text('Settings'));
        await settleLobby(tester);
        expect(find.text('Sound Effects'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureLobby(tester, '$look-settings-${phone.name}', phone.dpr);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$look gameplay ${phone.name}: playing, tray full, level complete', (tester) async {
        late AppServices services;
        late LevelManifestEntry meadow;
        await tester.runAsync(() async {
          services = await testServices();
          // A difficulty-4 level: 4-slot tray.
          meadow = services.content.snapshot.playableEntries.firstWhere((e) => e.difficulty == '4');
        });
        final snapshot = services.content.snapshot;

        await pumpLobby(
          tester,
          services: services,
          home: GameScreen(snapshot: snapshot, entry: meadow, resume: solvedSave(snapshot, meadow, pairs: 2)),
          phone: phone,
          themeMode: mode,
        );
        await finishIntro(tester);
        expectLook(tester, GameScreen);
        expect(find.text(meadow.title), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureLobby(tester, '$look-gameplay-${phone.name}', phone.dpr);
        await tester.pumpWidget(const SizedBox());

        final (save, last) = nearlyFullSave(snapshot, meadow);
        await pumpLobby(
          tester,
          services: services,
          home: GameScreen(snapshot: snapshot, entry: meadow, resume: save),
          phone: phone,
          themeMode: mode,
        );
        await finishIntro(tester);
        await tapBoardTile(tester, snapshot, meadow, save.history, last);
        await settleLobby(tester);
        await settleLobby(tester);
        expect(find.text('Tray full'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureLobby(tester, '$look-tray-full-${phone.name}', phone.dpr);
        await tester.pumpWidget(const SizedBox());

        await pumpLobby(
          tester,
          services: services,
          home: GameScreen(snapshot: snapshot, entry: meadow, resume: solvedSave(snapshot, meadow, elapsedMs: 83000)),
          phone: phone,
          themeMode: mode,
        );
        await settleLobby(tester);
        expect(find.text('Level Complete!'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureLobby(tester, '$look-win-${phone.name}', phone.dpr);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('$look age screen 360x640', (tester) async {
      late AppServices services;
      await tester.runAsync(() async => services = await testServices());
      await pumpLobby(
        tester,
        services: services,
        home: AgeScreen(onAnswered: (_) {}, now: () => DateTime(2026, 10, 16)),
        phone: smallPhone,
        themeMode: mode,
      );
      expectLook(tester, AgeScreen);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, '$look-age-${smallPhone.name}', smallPhone.dpr);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

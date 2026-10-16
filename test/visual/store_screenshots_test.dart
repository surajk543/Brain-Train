// Store screenshots: the six store scenes at Google Play phone (1080 x 1920
// px), App Store iPhone 6.9" (1320 x 2868 px) and iPad 13" (2064 x 2752 px),
// portrait, on the starter pack (levels 1-5) with a fake content host.
//
// Skipped unless STORE_DIR is set; then writes $STORE_DIR/phone/,
// $STORE_DIR/ios/iphone-6.9/ and $STORE_DIR/ios/ipad-13/ (0N-<scene>.png):
//
//   STORE_DIR=art/store flutter test test/visual/store_screenshots_test.dart
//
// The captures are RGBA (fully opaque); art/store/ holds them flattened to
// RGB, and tool/store/make_store_shots.py frames them for the listings:
//
//   python3 -c "import sys; from PIL import Image
//   [Image.open(p).convert('RGB').save(p, optimize=True) for p in sys.argv[1:]]" \
//     art/store/phone/*.png art/store/ios/*/*.png
import 'dart:io';

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/score_popups.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/lobby_support.dart';
import '../helpers/fake_stopwatch.dart';
import 'gameplay_support.dart';

final String? _storeDir = Platform.environment['STORE_DIR'];

/// Level 2 (a 5-slot tray) and level 4 (difficulty 4, a 4-slot tray).
LevelManifestEntry _level(AppServices services, int order) =>
    services.content.snapshot.playableEntries.firstWhere((e) => e.order == order);

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

  for (final (device, dir) in [(playPhone, 'phone'), (iphone69, 'ios/iphone-6.9'), (ipad13, 'ios/ipad-13')]) {
    Future<void> shoot(WidgetTester tester, String name) async {
      expect(tester.takeException(), isNull);
      await captureLobby(tester, name, device.dpr, dir: '$_storeDir/$dir');
    }

    Future<AppServices> services(WidgetTester tester) async {
      late AppServices services;
      await tester.runAsync(() async {
        services = await testServices(client: starterHost);
        await _midway(services);
      });
      return services;
    }

    Future<void> pumpGame(WidgetTester tester, AppServices services, LevelManifestEntry entry, {SavedGame? resume, Stopwatch? stopwatch}) async {
      final snapshot = services.content.snapshot;
      await pumpLobby(
        tester,
        services: services,
        home: GameScreen(snapshot: snapshot, entry: entry, resume: resume, stopwatch: stopwatch),
        phone: device,
      );
      await finishIntro(tester);
    }

    group(device.name, skip: _storeDir == null ? 'set STORE_DIR to write store screenshots' : null, () {
      testWidgets('01 lobby, 06 completed levels', (tester) async {
        final app = await services(tester);
        await pumpLobby(tester, services: app, home: const HomeScreen(), phone: device);
        expect(find.text('Continue · Level 2'), findsOneWidget);
        expect(find.textContaining('Offline'), findsNothing, reason: 'the content is up to date: no lobby notice');
        await shoot(tester, '01-lobby');
        await tester.tap(find.text('Completed Levels'));
        await settleLobby(tester);
        expect(find.text(_level(app, 2).title), findsOneWidget);
        expect(find.text('1 of ${app.content.snapshot.manifest.levels.length} won'), findsOneWidget);
        await shoot(tester, '06-completed-levels');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('02 tray gameplay', (tester) async {
        final app = await services(tester);
        final entry = _level(app, 2);
        final (save, _) = nearlyFullSave(app.content.snapshot, entry);
        await pumpGame(tester, app, entry, resume: save);
        expect(find.bySemanticsLabel('Tray, 4 of 5 tiles'), findsOneWidget);
        await shoot(tester, '02-tray-gameplay');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('03 combo', (tester) async {
        final app = await services(tester);
        final entry = _level(app, 2);
        final clock = FakeStopwatch();
        await pumpGame(tester, app, entry, stopwatch: clock);
        final game = gameOf(tester);
        final level = app.content.snapshot.levels[entry.levelId]!;
        final solution = MahjongSolver(
          geometry: game.engine.geometry,
          rules: game.engine.rules,
        ).solve(TileMask.all(level.tiles.length)).solution;
        for (final (a, b) in solution.take(2)) {
          game
            ..tapTile(level.tiles[a].tileId)
            ..tapTile(level.tiles[b].tileId);
          clock.advance(const Duration(milliseconds: 600));
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Flights land, the pairs shatter, the score popups fade.
        final popups = tester.state<ScorePopupOverlayState>(find.byType(ScorePopupOverlay));
        for (var i = 0; i < 60 || popups.popupCount > 0; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget);
        await shoot(tester, '03-combo');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('04 level complete', (tester) async {
        final app = await services(tester);
        final entry = _level(app, 4);
        await pumpGame(tester, app, entry, resume: solvedSave(app.content.snapshot, entry, elapsedMs: 83000));
        expect(find.text('Level Complete!'), findsOneWidget);
        await shoot(tester, '04-level-complete');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('05 tray full, revive', (tester) async {
        final app = await services(tester);
        final entry = _level(app, 4);
        final (save, last) = nearlyFullSave(app.content.snapshot, entry);
        await pumpGame(tester, app, entry, resume: save);
        await tapBoardTile(tester, app.content.snapshot, entry, save.history, last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await settleLobby(tester);
        expect(find.text('Tray full'), findsOneWidget);
        expect(find.text('Revive'), findsOneWidget);
        await shoot(tester, '05-tray-full-revive');
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}

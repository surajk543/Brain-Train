import 'package:brain_train/app/app.dart';
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/features/home/widgets/lobby_tagline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_support.dart';

void main() {
  // The age screen was answered at an earlier launch (see age_screen_test).
  setUp(() => SharedPreferences.setMockInitialValues({SettingsRepository.ageGroupKey: AgeGroup.thirteenPlus.storageValue}));

  test('playing a level to the end records the win and clears the save', () async {
    final services = await testServices();
    final ContentSnapshot snapshot = services.content.snapshot;
    final entry = snapshot.playableEntries.first;
    final controller = GameController(
      entry: entry,
      level: snapshot.levels[entry.levelId]!,
      registry: snapshot.registry,
      progress: services.progress,
      settings: services.settings,
    );
    final solution = MahjongSolver(
      geometry: controller.engine.geometry,
      rules: controller.engine.rules,
    ).solve(TileMask.all(controller.level.tiles.length)).solution;

    // A pair-removal order plays as taps: each second tile clears the first.
    final (a, b) = solution.first;
    controller
      ..tapTile(controller.level.tiles[a].tileId)
      ..tapTile(controller.level.tiles[b].tileId);
    await Future<void>.delayed(Duration.zero);
    expect(services.progress.savedGame()!.history, [controller.level.tiles[a].tileId, controller.level.tiles[b].tileId]);

    for (final (a, b) in solution.skip(1)) {
      controller
        ..tapTile(controller.level.tiles[a].tileId)
        ..tapTile(controller.level.tiles[b].tileId);
    }
    expect(controller.state.status, GameStatus.won);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(services.progress.isCompleted(entry.levelId), isTrue);
    // One move per tile tapped.
    expect(services.progress.completed()[entry.levelId]!.bestMoves, solution.length * 2);
    expect(services.progress.savedGame(), isNull);
    controller.dispose();
  });

  test('a saved game resumes on the same level revision only', () async {
    final services = await testServices();
    final snapshot = services.content.snapshot;
    final entry = snapshot.playableEntries.first;
    final level = snapshot.levels[entry.levelId]!;
    final first = GameController(
      entry: entry,
      level: level,
      registry: snapshot.registry,
      progress: services.progress,
      settings: services.settings,
    );
    final (a, b) = MahjongSolver(
      geometry: first.engine.geometry,
      rules: first.engine.rules,
    ).solve(TileMask.all(level.tiles.length)).solution.first;
    final free = first.state.free.firstWhere((id) => id != level.tiles[a].tileId && id != level.tiles[b].tileId);
    first
      ..tapTile(level.tiles[a].tileId)
      ..tapTile(level.tiles[b].tileId)
      ..tapTile(free);
    await Future<void>.delayed(Duration.zero);
    final saved = services.progress.savedGame()!;
    expect(saved.history.length, 3);
    first.dispose();

    final resumed = GameController(
      entry: entry,
      level: level,
      registry: snapshot.registry,
      progress: services.progress,
      settings: services.settings,
      resume: saved,
    );
    expect(resumed.state.matchedPairs, 1);
    expect(resumed.state.tray, [free], reason: 'the tray is restored too');
    expect(resumed.state.moveCount, 3);
    resumed.dispose();

    final stale = SavedGame(
      levelId: saved.levelId,
      levelUrl: 'levels/level-0001-v0.json',
      history: saved.history,
      moveCount: 1,
      elapsedMs: 0,
    );
    final fresh = GameController(
      entry: entry,
      level: level,
      registry: snapshot.registry,
      progress: services.progress,
      settings: services.settings,
      resume: stale,
    );
    expect(fresh.state.matchedPairs, 0);
    fresh.dispose();
  });

  test('sound and vibration settings persist and default to on', () async {
    final settings = await SettingsRepository.open();
    expect(settings.sound, isTrue);
    expect(settings.haptics, isTrue);
    await settings.setSound(false);
    await settings.setHaptics(false);
    final reopened = await SettingsRepository.open();
    expect(reopened.sound, isFalse);
    expect(reopened.haptics, isFalse);
  });

  testWidgets('settings shows only sound, vibration and the version', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Brain Train',
      packageName: 'com.sungamestudio.braintrain',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    late AppServices services;
    await tester.runAsync(() async => services = await testServices());
    await tester.pumpWidget(BrainTrainApp(servicesFactory: () async => services, showIntro: false));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in ['Sound', 'Vibration', 'Brain Train · Version 1.0.0 (1)']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final removed in [
      'Appearance',
      'System',
      'Day',
      'Night',
      'Dim blocked tiles',
      'Show timer',
      'Reduce motion',
      'Content version',
      'Check for new levels',
    ]) {
      expect(find.text(removed), findsNothing, reason: removed);
    }
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(find.byType(SegmentedButton<ThemeMode>), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // Day / Night / System and the theme tokens: test/app/appearance_test.dart.

  testWidgets('launch: intro (unplayable here) falls through to the logo, then home', (tester) async {
    late AppServices services;
    await tester.runAsync(() async => services = await testServices());
    await tester.pumpWidget(
      BrainTrainApp(servicesFactory: () async => services, logoDuration: const Duration(milliseconds: 300)),
    );
    // No video plugin in tests: the intro gives up and hands over to the logo.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.bySemanticsLabel('Brain Train'), findsWidgets);
    expect(find.text('Completed Levels'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Completed Levels'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the app starts offline on bundled content and opens level 1', (tester) async {
    late AppServices services;
    await tester.runAsync(() async => services = await testServices());
    await tester.pumpWidget(BrainTrainApp(servicesFactory: () async => services, showIntro: false));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byType(LobbyTagline), findsOneWidget);
    expect(find.text('Play · Level 1'), findsOneWidget);

    final first = services.content.snapshot.playableEntries.first;
    final pairs = services.content.snapshot.levels[first.levelId]!.pairCount;
    await tester.tap(find.text('Play · Level 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(first.title), findsOneWidget);
    expect(find.text('0/$pairs'), findsOneWidget);
    // The HUD (with Back) on top, the action bar below the board (owner,
    // 1.1.0): Undo, Hint, Shuffle and an icon-only Restart.
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Restart'), findsNothing);
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(find.text('Hint'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    // Leave the game so its timers stop before the test ends.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
  });
}

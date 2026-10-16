import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/common/static_layer.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/levels/difficulty_style.dart';
import 'package:brain_train/features/levels/level_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_support.dart';

Future<AppServices> _start(WidgetTester tester, {int won = 0, bool resumeNext = false}) async {
  late AppServices services;
  await tester.runAsync(() async {
    services = await testServices();
    final entries = services.content.snapshot.playableEntries;
    for (final entry in entries.take(won)) {
      await services.progress.recordWin(entry.levelId, moves: 10, timeMs: 30000);
    }
    if (resumeNext) {
      final next = entries[won];
      await services.progress.saveGame(
        SavedGame(levelId: next.levelId, levelUrl: next.ref.url, history: const [], moveCount: 0, elapsedMs: 0),
      );
    }
  });
  return services;
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
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

  test('lock rule: level 1, won levels and the level after a won one are open', () {
    final entries = List.generate(5, (i) => i);
    LevelState at(int i, Set<int> won, {int? playing}) => LevelSelectScreen.statesFor(
      [for (final i in entries) _entry(i)],
      {for (final i in won) _entry(i).levelId: LevelRecord(bestMoves: 1, bestTimeMs: 1, completedAt: DateTime(2026))},
      playing == null ? null : _entry(playing).levelId,
    )[i];
    expect([for (final i in entries) at(i, {})], [
      LevelState.open,
      LevelState.locked,
      LevelState.locked,
      LevelState.locked,
      LevelState.locked,
    ]);
    expect([for (final i in entries) at(i, {0, 1}, playing: 2)], [
      LevelState.completed,
      LevelState.completed,
      LevelState.inProgress,
      LevelState.locked,
      LevelState.locked,
    ]);
    // A won level stays open even when an earlier one is not won (older progress).
    expect(at(3, {3}), LevelState.completed);
    expect(LevelSelectScreen.focusIndex([LevelState.completed, LevelState.open, LevelState.locked]), 1);
    expect(LevelSelectScreen.focusIndex([LevelState.completed, LevelState.completed]), 1);
  });

  test('difficulty styles: four tiers with their own colours, unknown ids still labelled', () {
    final styles = [for (final id in ['easy', 'medium', 'hard', 'veryHard']) DifficultyStyle.of(id)];
    expect(styles.map((s) => s.label), ['Easy', 'Medium', 'Hard', 'Very Hard']);
    expect(styles.map((s) => s.color).toSet(), hasLength(4));
    expect(DifficultyStyle.of('expert').label, 'Expert');
    expect(DifficultyStyle.of('expert').color, DifficultyStyle.of('expert').color);
  });

  for (final phone in [smallPhone, largePhone]) {
    testWidgets('nothing won yet: the next level on top, no grid of all levels at ${phone.name}', (tester) async {
      final services = await _start(tester);
      final entries = services.content.snapshot.playableEntries;
      expect(entries, hasLength(200));
      await pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: phone);
      expect(tester.takeException(), isNull);

      expect(find.bySemanticsLabel(RegExp(r'^Play level 1, ')), findsOneWidget);
      expect(find.text(entries.first.title), findsOneWidget);
      expect(find.text('0 of 200 won'), findsOneWidget);
      expect(find.text('Completed Levels'), findsOneWidget);
      expect(find.textContaining('No levels completed yet'), findsOneWidget);
      expect(find.byType(CompletedLevelRow), findsNothing, reason: 'only completed levels are listed');
      expect(find.byType(BackdropFilter), findsNothing);

      // The panel plays the next level.
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Play level 1, ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GameScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await _leave(tester);
    });
  }

  testWidgets('midway: only the completed levels, in a lazy grid; the panel continues the next one', (tester) async {
    final services = await _start(tester, won: 56, resumeNext: true);
    final entries = services.content.snapshot.playableEntries;
    await pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: smallPhone);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(RegExp(r'^Continue level 57, ')), findsOneWidget);
    expect(find.text('56 of 200 won'), findsOneWidget);
    expect(find.text('Completed Levels'), findsOneWidget);

    // Completed levels from level 1, each flattened, never behind an opacity layer.
    expect(find.bySemanticsLabel(RegExp(r'^Level 1, .*, completed, best time 0:30, completed ')), findsOneWidget);
    final built = find.byType(CompletedLevelRow).evaluate().length;
    expect(built, greaterThan(4));
    expect(built, lessThan(30));
    expect(find.text('0:30'), findsWidgets, reason: 'best time per completed level');
    expect(find.descendant(of: find.byType(CompletedLevelRow), matching: find.byType(StaticLayer)), findsWidgets);
    expect(find.descendant(of: find.byType(ListView), matching: find.byType(Opacity)), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('EASY'), findsWidgets);
    await captureLobby(tester, 'levels-midway-360x640', smallPhone.dpr);

    // The last completed level is built on demand; nothing after it is listed.
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp(r'^Level 56, ')),
      600,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel(RegExp(r'^Level 56, .*, completed, best time 0:30, completed ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Level 57, ')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Level 58, ')), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);

    // A completed level replays.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Level 56, ')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text(entries[55].title), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));

    // The panel continues the game in progress.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Continue level 57, ')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text(entries[56].title), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await _leave(tester);
  });
}

LevelManifestEntry _entry(int i) => LevelManifestEntry(
  levelId: 'level-$i',
  order: i + 1,
  title: 'Level $i',
  ref: ContentRef(url: 'levels/level-$i.json'),
);

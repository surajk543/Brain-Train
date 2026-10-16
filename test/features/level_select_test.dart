import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/common/static_layer.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/levels/difficulty_style.dart';
import 'package:brain_train/features/levels/level_loader.dart';
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

  test('difficulty styles: 1-10 read N/10 with their own colours; named and unknown ids still labelled', () {
    final numeric = [for (var d = 1; d <= 10; d++) DifficultyStyle.of('$d')];
    expect(numeric.map((s) => s.label), [for (var d = 1; d <= 10; d++) '$d/10']);
    expect(numeric.map((s) => s.color).toSet(), hasLength(10));
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
      final total = entries.length;
      expect(total, greaterThanOrEqualTo(100));
      await pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: phone);
      expect(tester.takeException(), isNull);

      expect(find.bySemanticsLabel(RegExp(r'^Play level 1, ')), findsOneWidget);
      expect(find.text(entries.first.title), findsOneWidget);
      expect(find.text('0 of $total won'), findsOneWidget);
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
    final total = entries.length;
    await pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: smallPhone);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(RegExp(r'^Continue level 57, ')), findsOneWidget);
    expect(find.text('56 of $total won'), findsOneWidget);
    expect(find.text('Completed Levels'), findsOneWidget);

    // Completed levels from level 1, each flattened, never behind an opacity layer.
    expect(find.bySemanticsLabel(RegExp(r'^Level 1, .*, completed, best time 0:30, best score none, completed ')), findsOneWidget);
    final built = find.byType(CompletedLevelRow).evaluate().length;
    expect(built, greaterThan(4));
    expect(built, lessThan(30));
    expect(find.text('0:30'), findsWidgets, reason: 'best time per completed level');
    expect(find.descendant(of: find.byType(CompletedLevelRow), matching: find.byType(StaticLayer)), findsWidgets);
    expect(find.descendant(of: find.byType(ListView), matching: find.byType(Opacity)), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('1/10'), findsWidgets);
    await captureLobby(tester, 'levels-midway-360x640', smallPhone.dpr);

    // A completed level that is on the device (the starter pack) replays offline.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Level 1, ')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text(entries[0].title), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));

    // The last completed level is built on demand; nothing after it is listed.
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp(r'^Level 56, ')),
      600,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel(RegExp(r'^Level 56, .*, completed, best time 0:30, best score none, completed ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Level 57, ')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Level 58, ')), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);

    // These services are offline and level 56 was never downloaded on this
    // device: the loader asks for the internet instead of opening the game.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Level 56, ')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text(kConnectToDownloadText), findsOneWidget);
    expect(find.text(entries[55].title), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(kConnectToDownloadText), findsNothing);

    // The panel's Continue goes through the same loader.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Continue level 57, ')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(kConnectToDownloadText), findsOneWidget);
    expect(find.text(entries[56].title), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await _leave(tester);
  });

  testWidgets('every level won: a "new levels are coming soon" note instead of the next level', (tester) async {
    final services = await _start(tester, won: 1 << 20);
    final total = services.content.snapshot.playableEntries.length;
    await pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: smallPhone);
    expect(tester.takeException(), isNull);
    expect(find.text('All $total levels complete!'), findsOneWidget);
    expect(find.text('New levels are coming soon. Stay tuned!'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^(Play|Continue|Replay) level ')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Level 1, .*, completed, ')), findsOneWidget);
    await captureLobby(tester, 'levels-all-complete-360x640', smallPhone.dpr);
    await _leave(tester);
  });
}

LevelManifestEntry _entry(int i) => LevelManifestEntry(
  levelId: 'level-$i',
  order: i + 1,
  title: 'Level $i',
  ref: ContentRef(url: 'levels/level-$i.json'),
);

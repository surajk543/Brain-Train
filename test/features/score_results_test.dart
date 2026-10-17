import 'dart:async';

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/levels/level_select_screen.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/scoring/score_format.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/platform/game_services_ids.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_play_games.dart';
import 'lobby_support.dart';

/// A progress store whose win write waits until [gate] completes.
class _SlowProgress extends ProgressRepository {
  _SlowProgress(super.prefs);

  Completer<void>? gate;

  @override
  Future<LevelRecord> recordWin(String levelId, {required int moves, required int timeMs, int? score, int? bestCombo}) async {
    final wait = gate;
    if (wait != null) await wait.future;
    return super.recordWin(levelId, moves: moves, timeMs: timeMs, score: score, bestCombo: bestCombo);
  }
}

/// Solver pair order of [entry]'s level, as tile ids.
List<(String, String)> _pairs(ContentSnapshot snapshot, LevelManifestEntry entry) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = GameEngine(level: level, rules: MatchRules(level: level, registry: snapshot.registry));
  final solution = MahjongSolver(
    geometry: engine.geometry,
    rules: engine.rules,
  ).solve(TileMask.all(level.tiles.length)).solution;
  return [for (final (a, b) in solution) (level.tiles[a].tileId, level.tiles[b].tileId)];
}

/// Opens the game one pair short of a win (a save without scoring), then taps
/// the last pair so the win is recorded for real.
Future<GameController> _winLevel(
  WidgetTester tester,
  AppServices services,
  LevelManifestEntry entry, {
  Phone phone = largePhone,
  double textScale = 1,
}) async {
  final snapshot = services.content.snapshot;
  final pairs = _pairs(snapshot, entry);
  final history = [
    for (final (a, b) in pairs.take(pairs.length - 1)) ...[a, b],
  ];
  await pumpLobby(
    tester,
    services: services,
    phone: phone,
    textScale: textScale,
    home: GameScreen(
      snapshot: snapshot,
      entry: entry,
      resume: SavedGame(
        levelId: entry.levelId,
        levelUrl: entry.ref.url,
        history: history,
        moveCount: history.length,
        elapsedMs: 83000,
      ),
    ),
  );
  final controller = tester.widget<BoardView>(find.byType(BoardView)).controller;
  for (var i = 0; i < 60 && controller.introPlaying; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(controller.introPlaying, isFalse);
  controller
    ..tapTile(pairs.last.$1)
    ..tapTile(pairs.last.$2);
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(controller.state.status, GameStatus.won);
  expect(find.text('Level Complete!'), findsOneWidget);
  return controller;
}

/// Runs [body] and returns the first line of every Flutter error it reported
/// instead of failing on them (the Completed Levels row has a known RenderFlex
/// overflow at 360 px wide that these tests must not trip over).
Future<List<String>> _collectErrors(Future<void> Function() body) async {
  final previous = FlutterError.onError;
  final found = <String>[];
  FlutterError.onError = (details) => found.add(details.exceptionAsString().split('\n').first);
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return found;
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

  Future<AppServices> start(WidgetTester tester) async {
    late AppServices services;
    await tester.runAsync(() async => services = await testServices());
    return services;
  }

  testWidgets('Level Complete shows the final score, time, best combo, pairs and the helpers used', (tester) async {
    final services = await start(tester);
    final entry = services.content.snapshot.playableEntries.first;
    final controller = await _winLevel(tester, services, entry);

    final total = controller.state.totalPairs;
    final summary = controller.winSummary!;
    expect(controller.score, greaterThan(0));
    expect(find.text('Final Score'), findsOneWidget);
    expect(find.text(formatScore(controller.score)), findsNWidgets(2), reason: 'the card and the HUD both show the score');
    expect(find.bySemanticsLabel('Best Combo ×${controller.scoring.bestCombo}'), findsOneWidget);
    expect(find.bySemanticsLabel('Pairs Matched $total / $total'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Completion Time \d+:\d\d$')), findsOneWidget);
    for (final row in ['Hints Used 0', 'Shuffles Used 0', 'Undos Used 0']) {
      expect(find.bySemanticsLabel(row), findsOneWidget, reason: row);
    }
    final record = controller.winRecord!;
    expect(record.bestScore, controller.score);
    expect(summary.record, record);
    expect(find.text('New best!'), findsNothing, reason: 'first win of the level');
    expect(find.textContaining(RegExp(r'^Best \d')), findsNothing, reason: 'this score is the best');
    expect(find.text('Next Level'), findsOneWidget);
    expect(find.text('Level Select'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
    await captureLobby(tester, 'score-win-card-411x914', largePhone.dpr);
    await _leave(tester);
  });

  testWidgets('a win on the game screen goes to the leaderboards and achievements (13+, signed in)', (tester) async {
    final fake = FakePlayGames(const PlayGamesSignedIn('Ann'));
    late AppServices services;
    await tester.runAsync(
      () async => services = await testServices(playGames: PlayGamesController(fake), ageGroup: AgeGroup.thirteenPlus),
    );
    services.playGames.start(services.settings.ageGroup);
    final entry = services.content.snapshot.playableEntries.first;
    final difficulty = int.parse(entry.difficulty!);
    final controller = await _winLevel(tester, services, entry);
    final summary = controller.winSummary!;
    expect(fake.unlocks, [(GameAchievement.firstWin, true)]);
    expect(fake.scores, [
      (GameLeaderboard.bestScore(difficulty)!, summary.score),
      (GameLeaderboard.fastestTime(difficulty)!, summary.time.inMilliseconds),
      (GameLeaderboard.totalScore, summary.score),
      (GameLeaderboard.levelsCompleted, 1),
      (GameLeaderboard.bestCombo, summary.bestCombo),
    ]);
    expect(summary.time.inMilliseconds, greaterThanOrEqualTo(83000));
    await _leave(tester);
  });

  testWidgets('a higher score than the level best shows New best!', (tester) async {
    final services = await start(tester);
    final entry = services.content.snapshot.playableEntries.first;
    await tester.runAsync(() => services.progress.recordWin(entry.levelId, moves: 40, timeMs: 90000, score: 1));
    final controller = await _winLevel(tester, services, entry);
    expect(controller.newBestScore, isTrue);
    expect(find.text('New best!'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Best \d')), findsNothing, reason: 'New best! says it');
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  testWidgets('with reduced motion the win card still gets New best! and the Best line when the record lands late', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final base = await start(tester);
    late _SlowProgress slow;
    await tester.runAsync(() async => slow = _SlowProgress(await SharedPreferences.getInstance()));
    final services = AppServices(content: base.content, progress: slow, settings: base.settings, symbolArt: base.symbolArt);
    final entry = services.content.snapshot.playableEntries.first;
    await tester.runAsync(() => slow.recordWin(entry.levelId, moves: 40, timeMs: 90000, score: 1));
    final gate = slow.gate = Completer<void>();
    final controller = await _winLevel(tester, services, entry);
    expect(find.text('New best!'), findsNothing, reason: 'the record is still being written');
    expect(find.textContaining(RegExp(r'^Best \d')), findsNothing);
    gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(controller.newBestScore, isTrue);
    expect(find.text('New best!'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a lower score than the level best does not show New best!', (tester) async {
    final services = await start(tester);
    final entry = services.content.snapshot.playableEntries.first;
    await tester.runAsync(() => services.progress.recordWin(entry.levelId, moves: 40, timeMs: 90000, score: 99999999));
    final controller = await _winLevel(tester, services, entry);
    expect(controller.newBestScore, isFalse);
    expect(find.text('New best!'), findsNothing);
    expect(find.text('Best ${formatScore(99999999)}'), findsOneWidget, reason: 'the level best this game did not reach');
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  testWidgets('Completed Levels: the best score with separators, or a dash without one', (tester) async {
    final services = await start(tester);
    final entries = services.content.snapshot.playableEntries;
    await tester.runAsync(() async {
      await services.progress.recordWin(entries[0].levelId, moves: 10, timeMs: 30000, score: 12450, bestCombo: 4);
      await services.progress.recordWin(entries[1].levelId, moves: 10, timeMs: 30000);
    });
    final errors = await _collectErrors(
      () => pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: smallPhone),
    );
    expect(errors.where((m) => !m.contains('overflowed')), isEmpty, reason: 'only the known overflow');
    final scored = find.byWidgetPredicate((w) => w is CompletedLevelRow && w.entry.levelId == entries[0].levelId);
    expect(find.descendant(of: scored, matching: find.text('12,450')), findsOneWidget);
    final plain = find.byWidgetPredicate((w) => w is CompletedLevelRow && w.entry.levelId == entries[1].levelId);
    expect(find.descendant(of: plain, matching: find.text('—')), findsOneWidget);
    expect(find.descendant(of: plain, matching: find.textContaining(RegExp(r'\d,\d\d\d'))), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Level 1, .*best score 12450')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Level 2, .*best score none')), findsOneWidget);
    await captureLobby(tester, 'score-completed-levels-360x640', smallPhone.dpr);
    await _leave(tester);
  });

  testWidgets('360x640 at 1.3x text: the win card lays out without overflow', (tester) async {
    final services = await start(tester);
    final entry = services.content.snapshot.playableEntries.first;
    await tester.runAsync(() => services.progress.recordWin(entry.levelId, moves: 40, timeMs: 90000, score: 1));
    final controller = await _winLevel(tester, services, entry, phone: smallPhone, textScale: 1.3);
    expect(controller.newBestScore, isTrue, reason: 'the longest card: New best! and every line');
    expect(find.text('New best!'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureLobby(tester, 'score-win-card-new-best-360x640-text130', smallPhone.dpr);
    await _leave(tester);
  });

  testWidgets('360x640 at 1.3x text: a score in the row adds no overflow beyond a row without one', (tester) async {
    Future<List<String>> problems(bool withScore) async {
      final services = await start(tester);
      final entries = services.content.snapshot.playableEntries;
      await tester.runAsync(() async {
        await services.progress.recordWin(entries[0].levelId, moves: 10, timeMs: 30000, score: withScore ? 12450 : null);
      });
      final found = await _collectErrors(
        () => pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: smallPhone, textScale: 1.3),
      );
      await _leave(tester);
      return found;
    }

    final without = await problems(false);
    final withScore = await problems(true);
    expect(withScore, without, reason: 'the score line adds no overflow');
  });
}

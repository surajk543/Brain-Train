import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_support.dart';

GameController _gameOf(WidgetTester tester) => tester.widget<BoardView>(find.byType(BoardView)).controller;

/// Real time for tile art decoding, then pumps until the intro has handed over.
Future<void> _finishIntro(WidgetTester tester) async {
  for (var i = 0; i < 80 && _gameOf(tester).introPlaying; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_gameOf(tester).introPlaying, isFalse, reason: 'the intro handed over');
  await tester.pump();
}

/// A difficulty-4 level resumed after two pairs (4 moves, 0:17 on the clock),
/// pushed over a stand-in lobby (the first route).
Future<void> _pumpGame(WidgetTester tester, AppServices services, {bool waitIntro = true}) async {
  const phone = largePhone;
  tester.view
    ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
    ..devicePixelRatio = phone.dpr
    ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
    ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
  addTearDown(tester.view.reset);
  final snapshot = services.content.snapshot;
  final entry = snapshot.playableEntries.firstWhere((e) => e.difficulty == '4');
  final level = snapshot.levels[entry.levelId]!;
  final probe = GameController(
    entry: entry,
    level: level,
    registry: snapshot.registry,
    progress: services.progress,
    settings: services.settings,
  );
  final solution = MahjongSolver(
    geometry: probe.engine.geometry,
    rules: probe.engine.rules,
  ).solve(TileMask.all(level.tiles.length)).solution;
  probe.dispose();
  final history = [
    for (final (a, b) in solution.take(2)) ...[level.tiles[a].tileId, level.tiles[b].tileId],
  ];
  final saved = SavedGame(
    levelId: level.levelId,
    levelUrl: entry.ref.url,
    history: history,
    moveCount: history.length,
    elapsedMs: 17000,
  );
  // On disk too, as after those moves in the app.
  await tester.runAsync(() => services.progress.saveGame(saved));
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: buildBrainTrainTheme(),
        home: const Scaffold(body: Text('stand-in lobby')),
      ),
    ),
  );
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => GameScreen(snapshot: snapshot, entry: entry, resume: saved),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (waitIntro) {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _finishIntro(tester);
  }
}

Future<void> _real(WidgetTester tester, [int ms = 250]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
}

Future<void> _openPause(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Pause'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Paused'), findsOneWidget);
}

void main() {
  late AppServices services;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async => services = await testServices());
  }

  testWidgets('the HUD has a Pause button: off during the intro, on after', (tester) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    await _pumpGame(tester, services, waitIntro: false);
    expect(_gameOf(tester).introPlaying, isTrue);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pause')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    await tester.tap(find.byTooltip('Pause'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Paused'), findsNothing);
    await _finishIntro(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pause')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
    );
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('Pause stops the clock and offers Resume, Restart and Lobby', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    await _openPause(tester);
    expect(find.text('The clock waits until you resume.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pause-resume')), findsOneWidget);
    expect(find.byKey(const ValueKey('pause-restart')), findsOneWidget);
    expect(find.byKey(const ValueKey('pause-lobby')), findsOneWidget);
    final frozen = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, frozen, reason: 'the clock is paused');
    expect(game.state.moveCount, 4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Resume closes the card and the clock runs again', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    await _openPause(tester);
    await tester.tap(find.byKey(const ValueKey('pause-resume')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paused'), findsNothing);
    final before = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, greaterThan(before), reason: 'the clock runs again');
    expect(game.state.moveCount, 4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Back while paused resumes and stays in the game', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    await _openPause(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paused'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
    final before = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Restart on the Pause card asks first, the clock still stopped', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    final total = game.level.tiles.length;
    await _openPause(tester);
    await tester.tap(find.byKey(const ValueKey('pause-restart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paused'), findsNothing);
    expect(find.text('Restart this level?'), findsOneWidget);
    final frozen = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, frozen);
    await tester.tap(find.widgetWithText(PremiumButton, 'Restart'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.state.moveCount, 0);
    expect(game.state.remaining.length, total);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Lobby on the Pause card goes back to the first route; the game stays saved', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    await _openPause(tester);
    await tester.tap(find.byKey(const ValueKey('pause-lobby')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('stand-in lobby'), findsOneWidget);
    expect(services.progress.savedGame()?.moveCount, 4);
    await tester.pumpWidget(const SizedBox());
  });
}

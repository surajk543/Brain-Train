import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_support.dart';

const _restart = 'Restart level';

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

/// A medium level resumed after two pairs (4 moves, 0:17 on the clock).
Future<void> _pumpGame(
  WidgetTester tester,
  AppServices services, {
  Phone phone = largePhone,
  bool waitIntro = true,
  bool reduceMotion = false,
}) async {
  tester.view
    ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
    ..devicePixelRatio = phone.dpr
    ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
    ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
  addTearDown(tester.view.reset);
  if (reduceMotion) tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final snapshot = services.content.snapshot;
  final entry = snapshot.playableEntries.firstWhere((e) => e.difficulty == 'medium');
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
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: buildBrainTrainTheme(Brightness.dark),
        home: GameScreen(
          snapshot: snapshot,
          entry: entry,
          resume: SavedGame(
            levelId: level.levelId,
            levelUrl: entry.ref.url,
            history: history,
            moveCount: history.length,
            elapsedMs: 17000,
          ),
        ),
      ),
    ),
  );
  if (waitIntro) {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!reduceMotion) await _finishIntro(tester);
  }
}

Future<void> _real(WidgetTester tester, [int ms = 250]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
}

Future<void> _openConfirm(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Restart'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Restart this level?'), findsOneWidget);
}

void main() {
  late AppServices services;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async => services = await testServices());
  }

  testWidgets('the HUD has a Restart button: disabled during the intro, enabled after', (tester) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    await _pumpGame(tester, services, waitIntro: false);
    expect(_gameOf(tester).introPlaying, isTrue);
    expect(find.bySemanticsLabel(_restart), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_restart)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    await tester.tap(find.byIcon(Icons.restart_alt_rounded).first, warnIfMissed: false);
    await tester.pump();
    expect(find.text('Restart this level?'), findsNothing);
    await _finishIntro(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_restart)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
    );
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(find.text('Restart'), findsNothing, reason: 'icon only');
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('Restart asks first and the clock stops while the card is open', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    expect(game.state.moveCount, 4);
    await _openConfirm(tester);
    expect(find.text('Your score and time start over.'), findsOneWidget);
    expect(find.text('Keep playing'), findsOneWidget);
    final frozen = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, frozen, reason: 'the clock is paused');
    expect(game.state.moveCount, 4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Keep playing closes the card, keeps the game and restarts the clock', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    final remaining = game.state.remaining.length;
    await _openConfirm(tester);
    await tester.tap(find.text('Keep playing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Restart this level?'), findsNothing);
    expect(game.state.moveCount, 4);
    expect(game.state.remaining.length, remaining);
    final before = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, greaterThan(before), reason: 'the clock runs again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Restart on the card starts the level over', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    final total = game.level.tiles.length;
    expect(game.state.remaining.length, total - 4);
    await _openConfirm(tester);
    await tester.tap(find.widgetWithText(PremiumButton, 'Restart'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Restart this level?'), findsNothing);
    expect(game.state.moveCount, 0);
    expect(game.state.remaining.length, total);
    expect(game.elapsed, lessThan(const Duration(seconds: 1)));
    expect(game.introPlaying, isTrue, reason: 'the intro replays');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Restart is disabled while a result card is up', (tester) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    await _pumpGame(tester, services, reduceMotion: true);
    final game = _gameOf(tester);
    // Fill the tray with tiles that never match each other.
    while (game.state.status == GameStatus.playing) {
      final tray = game.state.tray;
      final next = (game.state.free.toList()..sort()).firstWhere(
        (id) => !tray.any((t) => game.engine.rules.matches(game.engine.indexOf(t)!, game.engine.indexOf(id)!)),
      );
      game.tapTile(next);
    }
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tray full'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_restart)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    await tester.tap(find.byIcon(Icons.restart_alt_rounded).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Restart this level?'), findsNothing);
    expect(game.state.status, GameStatus.trayFull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('Back while the card is open closes it and stays in the game', (tester) async {
    await start(tester);
    await _pumpGame(tester, services);
    final game = _gameOf(tester);
    await _openConfirm(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Restart this level?'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(game.state.moveCount, 4, reason: 'untouched');
    final before = game.elapsed;
    await _real(tester, 300);
    expect(game.elapsed, greaterThan(before), reason: 'the clock runs again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('360x640: the HUD fits with the extra button and shows the clock', (tester) async {
    await start(tester);
    await _pumpGame(tester, services, phone: smallPhone);
    expect(tester.takeException(), isNull);
    final clock = find.textContaining('0:');
    expect(clock, findsWidgets);
    final hud = tester.getRect(find.byType(PremiumHudFrame));
    final button = tester.getRect(find.byTooltip('Restart'));
    final time = tester.getRect(find.text('TIME'));
    expect(time.right, lessThanOrEqualTo(button.left), reason: 'the clock sits left of the button');
    expect(time.left, greaterThanOrEqualTo(hud.left));
    expect(button.right, lessThanOrEqualTo(hud.right));
    await tester.pumpWidget(const SizedBox());
  });
}

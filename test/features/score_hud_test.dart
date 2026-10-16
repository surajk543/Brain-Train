import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/combo_badge.dart';
import 'package:brain_train/features/gameplay/widgets/game_hud.dart';
import 'package:brain_train/features/gameplay/widgets/score_popups.dart';
import 'package:brain_train/features/gameplay/widgets/tray_view.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/scoring/score_format.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_stopwatch.dart';
import 'lobby_support.dart';

GameController _gameOf(WidgetTester tester) => tester.widget<BoardView>(find.byType(BoardView)).controller;

ScorePopupOverlayState _popupsOf(WidgetTester tester) => tester.state<ScorePopupOverlayState>(find.byType(ScorePopupOverlay));

/// Real time for tile art decoding, then pumps until the intro has handed over.
Future<void> _finishIntro(WidgetTester tester) async {
  for (var i = 0; i < 80 && _gameOf(tester).introPlaying; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_gameOf(tester).introPlaying, isFalse, reason: 'the intro handed over');
  await tester.pump();
}

/// A fresh medium level on a hand-driven clock; returns its solver pairs as
/// (tileId, tileId) in a playable order.
Future<List<(String, String)>> _pumpGame(
  WidgetTester tester,
  AppServices services,
  FakeStopwatch clock, {
  Phone phone = largePhone,
  bool reduceMotion = false,
  double textScale = 1,
  Map<String, Object?>? savedScoring,
}) async {
  tester.view
    ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
    ..devicePixelRatio = phone.dpr
    ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
    ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  }
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: buildBrainTrainTheme(Brightness.dark),
        home: GameScreen(
          snapshot: snapshot,
          entry: entry,
          stopwatch: clock,
          resume: savedScoring == null
              ? null
              : SavedGame(
                  levelId: level.levelId,
                  levelUrl: entry.ref.url,
                  history: [for (final (a, b) in solution.take(2)) ...[level.tiles[a].tileId, level.tiles[b].tileId]],
                  elapsedMs: 17000,
                  scoring: savedScoring,
                ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!reduceMotion) await _finishIntro(tester);
  return [for (final (a, b) in solution) (level.tiles[a].tileId, level.tiles[b].tileId)];
}

/// Taps one pair (the first tile goes to the tray, the second clears it).
void _match(WidgetTester tester, (String, String) pair) {
  _gameOf(tester)
    ..tapTile(pair.$1)
    ..tapTile(pair.$2);
}

/// Plays frames until a popup shows (the strike lands after the flights),
/// returning the most popups seen at once.
Future<int> _watchPopups(WidgetTester tester, {int frames = 60}) async {
  var most = 0;
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
    final count = _popupsOf(tester).popupCount;
    if (count > most) most = count;
  }
  return most;
}

void main() {
  late AppServices services;
  late FakeStopwatch clock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = FakeStopwatch();
  });

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async => services = await testServices());
  }

  test('formatScore groups thousands', () {
    expect(formatScore(0), '0');
    expect(formatScore(1250), '1,250');
    expect(formatScore(1234567), '1,234,567');
  });

  testWidgets('the HUD shows SCORE instead of Moves', (tester) async {
    await start(tester);
    await _pumpGame(tester, services, clock);
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('MOVES'), findsNothing);
    expect(find.text('0'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the score counts up to its new value after a match', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock);
    _match(tester, pairs[0]);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('100'), findsNothing, reason: 'still counting up');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('100'), findsOneWidget);
    await _watchPopups(tester, frames: 40);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the combo badge appears at ×2 and goes when the window closes', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock);
    expect(find.textContaining('COMBO ×'), findsNothing);
    _match(tester, pairs[0]);
    await tester.pump();
    expect(find.textContaining('COMBO ×'), findsNothing, reason: 'one match is no combo');
    expect(find.textContaining('Best'), findsNothing);
    clock.advance(const Duration(milliseconds: 500));
    _match(tester, pairs[1]);
    await tester.pump();
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget);
    expect(find.textContaining('Best ×2'), findsOneWidget);
    clock.advance(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5)); // the window's timer fires
    expect(find.text('COMBO ×2 · Best ×2'), findsNothing);
    expect(find.text('Best ×2'), findsOneWidget, reason: 'the chip alone once the combo ended');
    await tester.pumpWidget(const SizedBox());
  });

  for (final phone in [smallPhone, midPhone, largePhone]) {
    testWidgets('${phone.name}: the combo badge hangs on the tray\'s bottom edge, clear of the wells', (tester) async {
      await start(tester);
      final pairs = await _pumpGame(tester, services, clock, phone: phone);
      _match(tester, pairs[0]);
      clock.advance(const Duration(milliseconds: 500));
      _match(tester, pairs[1]);
      await tester.pump();
      final pill = tester.getRect(
        find.ancestor(of: find.text('COMBO ×2 · Best ×2'), matching: find.byType(Container)).first,
      );
      final tray = tester.state<TrayViewState>(find.byType(TrayView));
      final wells = tray.wellRect(0)!;
      final frame = tray.panelRect()!;
      expect(pill.top, greaterThanOrEqualTo(wells.bottom), reason: 'the pill leaves the wells uncovered');
      expect(pill.top, lessThan(frame.bottom), reason: 'it still sits on the frame\'s edge');
      expect(pill.bottom, greaterThan(frame.bottom));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the HUD\'s COMBO cell shows the running multiplier; the badge never ticks', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: find.byType(ComboBadge), matching: find.byType(CustomPaint)), findsNothing, reason: 'no badge');
    expect(find.bySemanticsLabel('Combo ×1'), findsOneWidget);
    _match(tester, pairs[0]);
    clock.advance(const Duration(milliseconds: 500));
    _match(tester, pairs[1]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget);
    expect(find.bySemanticsLabel('Combo ×2'), findsOneWidget, reason: 'the HUD cell');
    // The window's countdown is the timer bar's (ComboTimerBar), not the badge's.
    expect(tester.state<ComboTimerBarState>(find.byType(ComboTimerBar)).ticking, isTrue);
    clock.advance(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await _watchPopups(tester, frames: 40);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('COMBO ×2 · Best ×2'), findsNothing);
    expect(find.bySemanticsLabel('Combo ×1'), findsOneWidget);
    expect(tester.state<ComboTimerBarState>(find.byType(ComboTimerBar)).ticking, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pair that strikes shows a score popup', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock);
    expect(_popupsOf(tester).popupCount, 0);
    _match(tester, pairs[0]);
    expect(await _watchPopups(tester), greaterThan(0));
    await _watchPopups(tester, frames: 30);
    expect(_popupsOf(tester).popupCount, 0, reason: 'popups end');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('popups never block taps', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock);
    _match(tester, pairs[0]);
    expect(find.byType(ScorePopupOverlay), findsOneWidget);
    final ignore = find.ancestor(of: find.byType(ScorePopupOverlay), matching: find.byType(IgnorePointer));
    expect(tester.widgetList<IgnorePointer>(ignore).any((w) => w.ignoring), isTrue);
    var frames = 0;
    while (_popupsOf(tester).popupCount == 0 && frames++ < 60) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_popupsOf(tester).popupCount, greaterThan(0), reason: 'a popup is on screen');
    // A touch in the middle of the screen reaches the board, not the overlay.
    final result = tester.hitTestOnBinding(tester.getCenter(find.byType(BoardView)));
    final overlay = tester.renderObject(find.byType(ScorePopupOverlay));
    expect(result.path.any((entry) => entry.target == overlay), isFalse);
    expect(result.path.any((entry) => entry.target is RenderObject && entry.target == tester.renderObject(find.byType(BoardView))), isTrue);
    await _watchPopups(tester, frames: 30);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: no popups, numbers update in place', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock, reduceMotion: true);
    _match(tester, pairs[0]);
    await tester.pump();
    expect(await _watchPopups(tester, frames: 20), 0);
    expect(find.text('100'), findsOneWidget);
    clock.advance(const Duration(milliseconds: 500));
    _match(tester, pairs[1]);
    await tester.pump();
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget, reason: 'the badge still shows, without effects');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the combo timer stops while the clock is paused and runs again after resume', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock);
    await _watchPopups(tester, frames: 1);
    final idle = tester.binding.transientCallbackCount;
    _match(tester, pairs[0]);
    clock.advance(const Duration(milliseconds: 500));
    _match(tester, pairs[1]);
    await _watchPopups(tester, frames: 60);
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget);
    expect(_popupsOf(tester).popupCount, 0);
    final running = tester.binding.transientCallbackCount;
    expect(running, greaterThan(idle), reason: 'the timer bar ticks during a combo');
    _gameOf(tester).pauseClock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_gameOf(tester).clockRunning, isFalse);
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget, reason: 'the badge stays while paused');
    expect(tester.binding.transientCallbackCount, idle, reason: 'the timer bar stopped with the clock');
    _gameOf(tester).resumeClock();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_gameOf(tester).clockRunning, isTrue);
    expect(tester.binding.transientCallbackCount, running, reason: 'the timer bar ticks again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 5-digit score fits at 360x640 and 1.3x text', (tester) async {
    await start(tester);
    await _pumpGame(
      tester,
      services,
      clock,
      phone: smallPhone,
      textScale: 1.3,
      savedScoring: const {'score': 12450, 'combo': 0, 'bestCombo': 3, 'pairs': 2, 'lastMatchAtMs': null},
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('12,450'), findsOneWidget);
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('360x640 at 1.3x text: no overflow with SCORE and Restart', (tester) async {
    await start(tester);
    final pairs = await _pumpGame(tester, services, clock, phone: smallPhone, textScale: 1.3);
    _match(tester, pairs[0]);
    clock.advance(const Duration(milliseconds: 500));
    _match(tester, pairs[1]);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _watchPopups(tester, frames: 30);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

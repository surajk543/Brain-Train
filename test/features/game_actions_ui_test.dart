import 'dart:async';

// The redesigned gameplay screen's controls (1.1.0): the action bar (Undo,
// Hint, Shuffle, Restart) and its ad offers, the hint glow, the shuffled
// board's drawing, the combo timer bar, Level Complete's figures and buttons,
// and the layout at 360x640 (1.0x and 1.3x text) and on a tablet.
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/app/tablet_scale.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_layout.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/action_bar.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/game_hud.dart';
import 'package:brain_train/features/gameplay/widgets/hint_glow.dart';
import 'package:brain_train/features/gameplay/widgets/tray_view.dart';
import 'package:brain_train/features/levels/level_loader.dart';
import 'package:brain_train/features/levels/level_select_screen.dart';
import 'package:brain_train/game_engine/campaign/board_shapes.dart';
import 'package:brain_train/game_engine/scoring/score_format.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:brain_train/rendering/board_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_stopwatch.dart';
import '../platform/fake_rewarded_ads.dart';
import 'lobby_support.dart';

GameController _gameOf(WidgetTester tester) => tester.widget<BoardView>(find.byType(BoardView)).controller;

Finder _action(GameAction action) => find.byKey(ValueKey('action-${action.name}'));

GameActionButton _button(WidgetTester tester, GameAction action) => tester.widget<GameActionButton>(_action(action));

/// The board painter the screen draws with now.
BoardPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(of: find.byType(BoardView), matching: find.byType(CustomPaint)))
    .map((paint) => paint.painter)
    .whereType<BoardPainter>()
    .single;

Future<void> _settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const Phone _ipad = (name: 'ipad-13', width: 1032, height: 1376, dpr: 2, top: 24, bottom: 20);

void main() {
  late AppServices services;
  late FakeStopwatch clock;
  late FakeRewardedAds ads;
  late LevelManifestEntry entry;

  // Real glyphs: text widths as on a phone (the layout checks need them).
  setUpAll(loadCaptureFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = FakeStopwatch();
  });

  /// [adStatus] null: a build without ads.
  Future<void> start(WidgetTester tester, {RewardedAdStatus? adStatus}) async {
    await tester.runAsync(() async {
      ads = FakeRewardedAds(adStatus ?? RewardedAdStatus.ready);
      services = await testServices(ads: adStatus == null ? null : RewardedAdsController(ads));
      // A difficulty-4 level: 4-slot tray.
      entry = services.content.snapshot.playableEntries.firstWhere((e) => e.difficulty == '4');
    });
  }

  /// Opens [entry] (or [open]) on the hand-driven clock and waits for the
  /// intro to hand over; returns its solver pairs in a playable order.
  Future<List<(String, String)>> pumpGame(
    WidgetTester tester, {
    Phone phone = largePhone,
    double textScale = 1,
    SavedGame? resume,
    LevelManifestEntry? open,
    ThemeMode themeMode = ThemeMode.dark,
    bool overLobby = false,
  }) async {
    final game = open ?? entry;
    final navigator = GlobalKey<NavigatorState>();
    final snapshot = services.content.snapshot;
    tester.view
      ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
      ..devicePixelRatio = phone.dpr
      ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
      ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildBrainTrainTheme(Brightness.light),
          darkTheme: buildBrainTrainTheme(),
          themeMode: themeMode,
          navigatorKey: navigator,
          builder: (context, child) => TabletScale(child: child!),
          home: overLobby
              ? const Scaffold(body: Text('lobby stub'))
              : GameScreen(snapshot: snapshot, entry: game, stopwatch: clock, resume: resume),
        ),
      ),
    );
    if (overLobby) {
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => GameScreen(snapshot: snapshot, entry: game, stopwatch: clock, resume: resume),
      )));
    }
    await _settle(tester);
    for (var i = 0; i < 80 && _gameOf(tester).introPlaying; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_gameOf(tester).introPlaying, isFalse, reason: 'the intro handed over');
    await tester.pump();
    final level = snapshot.levels[game.levelId]!;
    final engine = _gameOf(tester).engine;
    final solution = MahjongSolver(geometry: engine.geometry, rules: engine.rules).solve(engine.remainingMask).solution;
    return [for (final (a, b) in solution) (level.tiles[a].tileId, level.tiles[b].tileId)];
  }

  Future<void> match(WidgetTester tester, (String, String) pair) async {
    _gameOf(tester)
      ..tapTile(pair.$1)
      ..tapTile(pair.$2);
    await tester.pump();
  }

  group('action bar', () {
    testWidgets('states: off in the intro, Undo once there is a tap, badges count down', (tester) async {
      await start(tester);
      await pumpGame(tester);
      expect(_button(tester, GameAction.undo).onPressed, isNull, reason: 'nothing to undo yet');
      expect(_button(tester, GameAction.hint).onPressed, isNotNull);
      expect(_button(tester, GameAction.shuffle).onPressed, isNotNull);
      for (final action in GameAction.values) {
        expect(_button(tester, action).usesLeft, 1, reason: '$action starts with one use');
        expect(find.descendant(of: _action(action), matching: find.text('1')), findsOneWidget);
      }
      expect(find.byTooltip('Restart'), findsOneWidget);

      final game = _gameOf(tester);
      game.tapTile((game.state.free.toList()..sort()).first);
      await _settle(tester, rounds: 6);
      expect(_button(tester, GameAction.undo).onPressed, isNotNull);
      await tester.tap(_action(GameAction.undo));
      await _settle(tester, rounds: 8);
      expect(game.state.tray, isEmpty);
      expect(_button(tester, GameAction.undo).usesLeft, 0);
      expect(find.descendant(of: _action(GameAction.undo), matching: find.text('1')), findsNothing);
      // A build without ads: a "+" where the play mark would offer an ad.
      expect(find.descendant(of: _action(GameAction.undo), matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
      expect(game.useHint(), isNotNull);
      await tester.pump();
      expect(_button(tester, GameAction.hint).usesLeft, 0);

      // A restart replays the intro: every button is off meanwhile.
      game.restart();
      await tester.pump();
      expect(game.introPlaying, isTrue);
      for (final action in GameAction.values) {
        expect(_button(tester, action).onPressed, isNull, reason: '$action during the intro');
      }
      expect(tester.widget<GameActionButton>(find.byKey(const ValueKey('action-restart'))).onPressed, isNull);
      // Then every action is back to one use.
      for (var i = 0; i < 80 && game.introPlaying; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.introPlaying, isFalse);
      await tester.pump();
      for (final action in GameAction.values) {
        expect(_button(tester, action).usesLeft, 1, reason: '$action after Restart');
        expect(find.descendant(of: _action(action), matching: find.text('1')), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Undo takes a match back: the HUD score and pairs drop, no extra popup', (tester) async {
      await start(tester);
      final pairs = await pumpGame(tester);
      await match(tester, pairs[0]);
      await _settle(tester);
      final game = _gameOf(tester);
      expect(game.score, 100);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('1/${game.state.totalPairs}'), findsOneWidget);
      await tester.tap(_action(GameAction.undo));
      await _settle(tester);
      expect(game.score, 0);
      expect(find.text('0/${game.state.totalPairs}'), findsOneWidget);
      expect(find.text('100'), findsNothing);
      expect(game.actions.undosUsed, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Hint lights the tile (and its twin) and goes on the next tap; it never taps', (tester) async {
      await start(tester);
      await pumpGame(tester);
      final game = _gameOf(tester);
      final moves = game.state.moveCount;
      await tester.tap(_action(GameAction.hint));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final overlay = tester.state<HintGlowOverlayState>(find.byType(HintGlowOverlay));
      final hint = overlay.hint;
      expect(hint, isNotNull);
      expect(game.state.moveCount, moves, reason: 'a hint does not move');
      expect(game.usesLeft(GameAction.hint), 0);
      expect(overlay.strength, greaterThan(0));
      game.tapTile(hint!.tileId);
      await tester.pump();
      expect(overlay.hint, isNull, reason: 'the next tap clears it');

      // Untouched, it fades out by itself (a second hint: the free one is
      // spent, so one is granted as a rewarded ad would).
      expect(game.grant(GameAction.hint), isTrue);
      await tester.pump();
      await tester.tap(_action(GameAction.hint));
      await tester.pump();
      expect(overlay.hint, isNotNull);
      await tester.pump(HintGlowOverlay.duration + const Duration(milliseconds: 100));
      await tester.pump();
      expect(overlay.hint, isNull);
      await _settle(tester, rounds: 4);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with reduced motion the hint is still and clears after a while', (tester) async {
      await start(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpGame(tester);
      await tester.tap(_action(GameAction.hint));
      await tester.pump();
      final overlay = tester.state<HintGlowOverlayState>(find.byType(HintGlowOverlay));
      expect(overlay.hint, isNotNull);
      expect(overlay.strength, 1);
      await tester.pump(HintGlowOverlay.duration + const Duration(milliseconds: 100));
      expect(overlay.hint, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Shuffle: the board draws the new symbols; tiles turn over, then play on', (tester) async {
      await start(tester);
      await pumpGame(tester);
      final game = _gameOf(tester);
      final original = {for (final tile in game.level.tiles) tile.tileId: tile.symbolCode};
      final serial = game.symbolsSerial;
      await tester.tap(_action(GameAction.shuffle));
      await tester.pump();
      expect(game.symbolsSerial, isNot(serial));
      expect(game.actions.shufflesUsed, 1);
      final painter = _painter(tester);
      expect(painter.level, same(game.boardLevel));
      final shown = {for (final tile in painter.level.tiles) tile.tileId: tile.symbolCode};
      for (final id in game.state.remaining) {
        expect(shown[id], game.symbolCodeOf(id), reason: id);
      }
      expect(shown.entries.where((e) => original[e.key] != e.value), isNotEmpty, reason: 'symbols moved');
      expect(painter.effects.isFlipping, isTrue, reason: 'the changed tiles turn over');
      // Taps wait while tiles turn.
      final before = game.state.moveCount;
      await tester.tapAt(tester.getCenter(find.byType(BoardView)));
      await tester.pump();
      expect(game.state.moveCount, before);
      // The turn runs on real time (like a blocked tile's shake).
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      await _settle(tester, rounds: 4);
      expect(_painter(tester).effects.isFlipping, isFalse);
      expect(_button(tester, GameAction.shuffle).usesLeft, 0);

      // A tile taken now flies to the tray showing its new symbol.
      final id = (game.state.free.toList()..sort()).first;
      game.tapTile(id);
      await _settle(tester, rounds: 8);
      final tray = tester.widget<TrayView>(find.byType(TrayView));
      expect(tray.symbolOf!(id), game.symbolCodeOf(id));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a resumed shuffled game draws its shuffled symbols from the start', (tester) async {
      await start(tester);
      await pumpGame(tester);
      final game = _gameOf(tester);
      game.tapTile((game.state.free.toList()..sort()).first);
      game.shuffle();
      final history = game.state.history;
      final symbols = {for (final id in game.state.remaining) id: game.symbolCodeOf(id)};
      await tester.pumpWidget(const SizedBox());
      await pumpGame(
        tester,
        resume: SavedGame(levelId: entry.levelId, levelUrl: entry.ref.url, history: history, elapsedMs: 9000),
      );
      final resumed = _gameOf(tester);
      final painter = _painter(tester);
      for (final MapEntry(key: id, value: code) in symbols.entries) {
        expect(resumed.symbolCodeOf(id), code);
        expect(painter.level.tiles.firstWhere((t) => t.tileId == id).symbolCode, code);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ad offer for one more use', () {
    Future<GameController> spendHints(WidgetTester tester) async {
      final game = _gameOf(tester);
      while (game.usesLeft(GameAction.hint) > 0) {
        expect(game.useHint(), isNotNull);
      }
      await tester.pump();
      return game;
    }

    testWidgets('at 0 the badge offers an ad; the reward grants +1, the clock waits meanwhile', (tester) async {
      await start(tester, adStatus: RewardedAdStatus.ready);
      await pumpGame(tester);
      final game = await spendHints(tester);
      expect(game.actions.hintsUsed, 1, reason: 'one free hint per level');
      expect(_button(tester, GameAction.hint).usesLeft, 0);
      expect(find.descendant(of: _action(GameAction.hint), matching: find.byIcon(Icons.play_arrow_rounded)), findsOneWidget);
      await tester.tap(_action(GameAction.hint));
      await _settle(tester, rounds: 4);
      expect(find.text('Watch an ad for +1 Hint?'), findsOneWidget);
      expect(game.clockRunning, isFalse, reason: 'the clock waits behind the card');
      expect(_button(tester, GameAction.undo).onPressed, isNull, reason: 'the bar is off behind a card');
      await tester.tap(find.text('Watch ad'));
      await _settle(tester, rounds: 4);
      expect(ads.shows, 1);
      expect(game.usesLeft(GameAction.hint), 1);
      expect(find.text('Watch an ad for +1 Hint?'), findsNothing);
      expect(game.clockRunning, isTrue);
      expect(game.state.moveCount, 0, reason: 'a grant uses nothing');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an ad closed early grants nothing; the card stays with a note', (tester) async {
      await start(tester, adStatus: RewardedAdStatus.ready);
      await pumpGame(tester);
      final game = await spendHints(tester);
      ads
        ..showResult = RewardedAdResult.dismissed
        ..afterShow = RewardedAdStatus.ready;
      await tester.tap(_action(GameAction.hint));
      await _settle(tester, rounds: 4);
      await tester.tap(find.text('Watch ad'));
      await _settle(tester, rounds: 4);
      expect(game.usesLeft(GameAction.hint), 0);
      expect(find.text(refillDismissedNote(GameAction.hint)), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await _settle(tester, rounds: 4);
      expect(find.text('Watch an ad for +1 Hint?'), findsNothing);
      expect(game.clockRunning, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('loading and offline: Watch ad is off with its note; Back closes the card', (tester) async {
      await start(tester, adStatus: RewardedAdStatus.loading);
      await pumpGame(tester);
      await spendHints(tester);
      await tester.tap(_action(GameAction.hint));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(kRefillLoadingNote), findsOneWidget);
      final watch = find.ancestor(of: find.text('Watch ad'), matching: find.byType(InkWell));
      expect(tester.widget<InkWell>(watch.first).onTap, isNull);
      ads.setStatus(RewardedAdStatus.offline);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(kRefillOfflineNote), findsOneWidget);
      expect(ads.shows, 0);
      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Watch an ad for +1 Hint?'), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget, reason: 'Back closed the card, not the game');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a build without ads grants at once (like Revive)', (tester) async {
      await start(tester);
      await pumpGame(tester);
      final game = await spendHints(tester);
      expect(find.descendant(of: _action(GameAction.hint), matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
      await tester.tap(_action(GameAction.hint));
      await tester.pump();
      expect(game.usesLeft(GameAction.hint), 1);
      expect(find.text('Watch an ad for +1 Hint?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('combo timer bar', () {
    testWidgets('follows the combo window on the game clock and hides when it closes', (tester) async {
      await start(tester);
      final pairs = await pumpGame(tester);
      expect(find.byType(ComboTimerBar), findsOneWidget);
      final bar = tester.state<ComboTimerBarState>(find.byType(ComboTimerBar));
      expect(find.descendant(of: find.byType(ComboTimerBar), matching: find.byType(CustomPaint)), findsNothing);
      await match(tester, pairs[0]);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.descendant(of: find.byType(ComboTimerBar), matching: find.byType(CustomPaint)), findsWidgets);
      expect(bar.ticking, isTrue);
      final game = _gameOf(tester);
      clock.advance(const Duration(milliseconds: 1900));
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.comboTimeLeft, const Duration(milliseconds: 2100));
      // The clock stops (a card, the background): the bar holds still.
      game.pauseClock();
      await tester.pump();
      expect(bar.ticking, isFalse);
      game.resumeClock();
      await tester.pump();
      expect(bar.ticking, isTrue);
      clock.advance(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(game.comboTimeLeft, isNull);
      expect(bar.ticking, isFalse);
      expect(find.descendant(of: find.byType(ComboTimerBar), matching: find.byType(CustomPaint)), findsNothing);
      await _settle(tester, rounds: 6);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Level Complete', () {
    testWidgets('shows the game\'s figures; Next Level opens once', (tester) async {
      await start(tester);
      final snapshot = services.content.snapshot;
      final level = snapshot.levels[entry.levelId]!;
      final pairs = await pumpGame(tester);
      final game = _gameOf(tester);
      game.useHint();
      game.tapTile(pairs[0].$1);
      game.undo();
      for (final pair in pairs) {
        await match(tester, pair);
        clock.advance(const Duration(milliseconds: 700));
      }
      await _settle(tester, rounds: 20);
      expect(game.state.status, GameStatus.won);
      expect(find.text('Level Complete!'), findsOneWidget);
      final summary = game.winSummary!;
      expect(summary.hintsUsed, 1);
      expect(summary.undosUsed, 1);
      expect(find.bySemanticsLabel('Final score ${formatScore(summary.score)}'), findsOneWidget);
      expect(find.bySemanticsLabel('Pairs Matched ${level.pairCount} / ${level.pairCount}'), findsOneWidget);
      expect(find.bySemanticsLabel('Hints Used 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Undos Used 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Shuffles Used 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Best Combo ×${summary.bestCombo}'), findsOneWidget);
      expect(find.bySemanticsLabel('Completion Time ${formatDuration(summary.time)}'), findsOneWidget);
      expect(find.text('Replay'), findsOneWidget);

      // Two quick taps: one navigation.
      final next = find.text('Next Level');
      await tester.tap(next);
      await tester.tap(next, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester, rounds: 4);
      expect(find.byType(LevelLoaderScreen, skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Level Select opens the Levels screen once', (tester) async {
      await start(tester);
      final total = services.content.snapshot.levels[entry.levelId]!.pairCount;
      final pairs = await pumpGame(tester);
      for (final pair in pairs.take(total)) {
        await match(tester, pair);
      }
      await _settle(tester, rounds: 20);
      expect(find.text('Level Select'), findsOneWidget);
      await tester.tap(find.text('Level Select'));
      await tester.tap(find.text('Level Select'), warnIfMissed: false);
      await _settle(tester, rounds: 8);
      expect(find.byType(LevelSelectScreen, skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Lobby closes the game and goes back to the first route once', (tester) async {
      await start(tester);
      final total = services.content.snapshot.levels[entry.levelId]!.pairCount;
      final pairs = await pumpGame(tester, overLobby: true);
      for (final pair in pairs.take(total)) {
        await match(tester, pair);
      }
      await _settle(tester, rounds: 20);
      expect(find.text('Lobby'), findsOneWidget);
      await tester.tap(find.text('Lobby'));
      await tester.tap(find.text('Lobby'), warnIfMissed: false);
      await _settle(tester, rounds: 8);
      expect(find.byType(GameScreen, skipOffstage: false), findsNothing);
      expect(find.byType(LevelSelectScreen, skipOffstage: false), findsNothing);
      expect(find.text('lobby stub'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('layout', () {
    testWidgets('360x640: HUD on top, the board keeps the campaign\'s room, the action bar at the bottom', (tester) async {
      await start(tester);
      await pumpGame(tester, phone: smallPhone);
      final layout = GameLayout.of(const Size(360, 640), const EdgeInsets.only(top: 24));
      expect(layout.compact, isTrue);
      final board = tester.getRect(find.byType(BoardView));
      final hud = tester.getRect(find.byType(GameHud));
      final tray = tester.getRect(find.byType(TrayView));
      final bar = tester.getRect(find.byType(GameActionBar));
      expect(hud.top, greaterThanOrEqualTo(24));
      expect(tray.top, greaterThan(hud.bottom));
      expect(board.top, greaterThanOrEqualTo(tray.bottom));
      expect(bar.top, greaterThanOrEqualTo(board.bottom));
      expect(bar.bottom, lessThanOrEqualTo(640));
      expect(board.width, greaterThanOrEqualTo(kSmallBoardWidth));
      expect(board.height, greaterThanOrEqualTo(kSmallBoardHeight), reason: 'the 31-px tile faces need this room');
      expect(board.height, closeTo(layout.boardHeight(const Size(360, 640), const EdgeInsets.only(top: 24)), 0.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final look in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('360x640 at 1.3x text (${look.name}): no overflow, the board keeps its room', (tester) async {
        await start(tester, adStatus: RewardedAdStatus.ready);
        await pumpGame(
          tester,
          phone: smallPhone,
          textScale: 1.3,
          themeMode: look,
          open: LevelManifestEntry(
            levelId: entry.levelId,
            order: 128,
            title: 'Moonlit Standing Stones',
            ref: entry.ref,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byType(BoardView)).height, greaterThanOrEqualTo(kSmallBoardHeight));
        expect(find.text('Level 128'), findsOneWidget);
        // Cards fit too.
        await tester.tap(find.byTooltip('Restart'));
        await _settle(tester, rounds: 4);
        expect(find.text('Restart this level?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Keep playing'));
        await _settle(tester, rounds: 4);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('tablet: the screen lays out on the 600-px canvas without overflow', (tester) async {
      await start(tester);
      await pumpGame(tester, phone: _ipad);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(GameScreen));
      final canvas = MediaQuery.sizeOf(context);
      expect(canvas.shortestSide, closeTo(600, 0.5));
      expect(GameLayout.of(canvas, MediaQuery.paddingOf(context)).compact, isFalse);
      expect(find.text('Undo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('every published level keeps 31-px faces on the measured 360x640 board', () {
    // The real board at 360x640 (GameLayout) is at least the size the
    // campaign was built for (test/content/published_content_test.dart
    // checks every level's faces at that size).
    final layout = GameLayout.of(const Size(360, 640), const EdgeInsets.only(top: 24));
    expect(layout.boardHeight(const Size(360, 640), const EdgeInsets.only(top: 24)), greaterThanOrEqualTo(kSmallBoardHeight));
  });
}

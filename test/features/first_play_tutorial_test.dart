import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/first_play_tutorial.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../visual/gameplay_support.dart';
import 'lobby_support.dart';

const _step1 = 'Tap a free tile';
const _step2 = 'It drops into your tray';
const _step3 = 'Find its twin';
const _step4 = 'Keep your tray clear';
const _step5 = 'Clear every pair to win';

void main() {
  late AppServices services;
  LevelManifestEntry first() => services.content.snapshot.playableEntries.first;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(WidgetTester tester, {bool tutorialDone = false}) async {
    await tester.runAsync(() async => services = await testServices(tutorialDone: tutorialDone));
  }

  /// Opens level 1 as a new game and waits for the intro to hand over (and
  /// the tutorial, if due, to measure its hole).
  Future<void> pumpFirstGame(WidgetTester tester, {bool reduceMotion = false}) async {
    const phone = largePhone;
    tester.view
      ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
      ..devicePixelRatio = phone.dpr
      ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
      ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
    addTearDown(tester.view.reset);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
    }
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildBrainTrainTheme(),
          home: GameScreen(snapshot: services.content.snapshot, entry: first()),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!reduceMotion) await finishIntro(tester);
    await tester.pump();
    await tester.pump();
  }

  FirstPlayTutorialController? tutorialOf(WidgetTester tester) {
    final overlay = find.byType(FirstPlayTutorialOverlay);
    return overlay.evaluate().isEmpty ? null : tester.widget<FirstPlayTutorialOverlay>(overlay).controller;
  }

  Future<void> tapTile(WidgetTester tester, String tileId) =>
      tapBoardTile(tester, services.content.snapshot, first(), gameOf(tester).state.history, tileId);

  /// Pumps (flights, strikes and shatters need frames, snapshots real time)
  /// until [text] shows.
  Future<void> pumpUntilText(WidgetTester tester, String text) async {
    for (var i = 0; i < 60 && find.text(text).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(text), findsOneWidget);
  }

  Future<bool> storedFlag(WidgetTester tester) async {
    late bool done;
    await tester.runAsync(() async => done = (await SettingsRepository.open()).firstPlayTutorialDone);
    return done;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  test('the pair is free, matching and safe to take on level 1', () async {
    final snapshot = (await testServices()).content.snapshot;
    final level = snapshot.levels[snapshot.playableEntries.first.levelId]!;
    final engine = engineFor(level, snapshot.registry);
    final pair = tutorialPairFor(engine)!;
    final (a, b) = (engine.indexOf(pair.$1)!, engine.indexOf(pair.$2)!);
    expect(engine.isFreeIndex(a) && engine.isFreeIndex(b), isTrue);
    expect(engine.rules.matches(a, b), isTrue);
    engine.tap(pair.$1);
    expect(tutorialPairFor(engine), isNull, reason: 'only with an empty tray');
    engine.tap(pair.$2);
    expect(engine.state.matchedPairs, 1);
  });

  testWidgets('shows on the first game, after the intro, with the clock held', (tester) async {
    await start(tester);
    await pumpFirstGame(tester);
    final game = gameOf(tester);
    expect(find.text(_step1), findsOneWidget);
    expect(find.text('A tile is free when nothing covers it and its left or right side is open.'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byKey(FirstPlayTutorialOverlay.pulseKey), findsOneWidget, reason: 'the ring pulses');
    expect(game.tutorialActive, isTrue);
    expect(game.clockRunning, isFalse);
    final frozen = game.elapsed;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(game.elapsed, frozen, reason: 'the clock waits for the tutorial');
    // Back from the background (the screen pauses, then resumes the clock): still held.
    game
      ..pauseClock()
      ..resumeClock();
    await tester.pump();
    expect(game.clockRunning, isFalse, reason: 'an app resume does not start the clock mid-tutorial');
    expect(find.text(_step1), findsOneWidget);
    expect(tester.takeException(), isNull);
    await leave(tester);
  });

  testWidgets('never shows once the flag is set', (tester) async {
    await start(tester, tutorialDone: true);
    await pumpFirstGame(tester);
    expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
    expect(find.text(_step1), findsNothing);
    expect(gameOf(tester).clockRunning, isTrue);
    await leave(tester);
  });

  testWidgets('a player who has won a level is done: no tutorial, and the flag is set', (tester) async {
    await start(tester);
    await tester.runAsync(() => services.progress.recordWin(first().levelId, moves: 30, timeMs: 60000));
    await pumpFirstGame(tester);
    expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
    expect(gameOf(tester).clockRunning, isTrue);
    expect(await storedFlag(tester), isTrue);
    await leave(tester);
  });

  testWidgets('step 1 ignores every tap but the highlighted tile', (tester) async {
    await start(tester);
    await pumpFirstGame(tester);
    final game = gameOf(tester);
    final pair = tutorialOf(tester)!.pair;
    // Another free tile: held back by the scrim (or, in the hole's margin, by the game).
    final other = (game.state.free.toList()..sort()).firstWhere((id) => id != pair.$1);
    await tapTile(tester, other);
    await tester.pump();
    expect(game.state.moveCount, 0);
    // A direct tap on the game is filtered too.
    game.tapTile(other);
    expect(game.state.moveCount, 0);
    // The HUD's Back is under the scrim.
    await tester.tap(find.byTooltip('Back'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text(_step1), findsOneWidget);

    await tapTile(tester, pair.$1);
    await tester.pump();
    expect(game.state.moveCount, 1);
    expect(game.state.tray, [pair.$1]);
    expect(find.text(_step1), findsNothing, reason: 'the card waits while the tile flies');
    await pumpUntilText(tester, _step2);
    expect(game.clockRunning, isFalse);
    await leave(tester);
  });

  testWidgets('the full walk-through ends with the flag set and the clock running', (tester) async {
    await start(tester);
    await pumpFirstGame(tester);
    final game = gameOf(tester);
    final pair = tutorialOf(tester)!.pair;

    await tapTile(tester, pair.$1);
    await pumpUntilText(tester, _step2);
    expect(find.text('Every tile you tap goes into the tray at the top.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await pumpUntilText(tester, _step3);
    expect(find.text('Two matching tiles in the tray clear together.'), findsOneWidget);

    await tapTile(tester, pair.$2);
    await pumpUntilText(tester, _step4);
    expect(game.state.matchedPairs, 1);
    expect(game.state.tray, isEmpty);
    expect(game.score, greaterThan(0), reason: 'the tutorial pair is a real match');
    expect(
      find.text('If the tray fills up without a match, the round is over — you can Revive or Restart.'),
      findsOneWidget,
    );
    expect(game.clockRunning, isFalse);
    await tester.tap(find.text('Next'));
    await pumpUntilText(tester, _step5);
    expect(find.text('Match quickly for combos and a higher score. Have fun!'), findsOneWidget);
    expect(find.text('Skip'), findsNothing, reason: "Let's play ends the last step");
    await tester.tap(find.text("Let's play"));
    await tester.pump();
    await tester.pump();

    expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
    expect(game.tutorialActive, isFalse);
    expect(game.clockRunning, isTrue);
    expect(services.settings.firstPlayTutorialDone, isTrue);
    expect(await storedFlag(tester), isTrue);
    // Normal play goes on, on the same board.
    final next = (game.state.free.toList()..sort()).first;
    game.tapTile(next);
    expect(game.state.moveCount, 3);
    expect(tester.takeException(), isNull);
    await leave(tester);
  });

  testWidgets('Skip ends the tutorial at once and sets the flag', (tester) async {
    await start(tester);
    await pumpFirstGame(tester);
    final game = gameOf(tester);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
    expect(game.tutorialActive, isFalse);
    expect(game.clockRunning, isTrue);
    expect(await storedFlag(tester), isTrue);
    expect(game.state.moveCount, 0);
    final any = (game.state.free.toList()..sort()).first;
    game.tapTile(any);
    expect(game.state.moveCount, 1, reason: 'every tile can be tapped again');
    await leave(tester);
  });

  testWidgets('Android back skips the tutorial and stays in the game', (tester) async {
    await start(tester);
    await pumpFirstGame(tester);
    final game = gameOf(tester);
    final pair = tutorialOf(tester)!.pair;
    await tapTile(tester, pair.$1);
    await pumpUntilText(tester, _step2);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump();
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
    expect(game.clockRunning, isTrue);
    expect(await storedFlag(tester), isTrue);
    expect(game.state.tray, [pair.$1], reason: 'the tutorial tap stays a real move');
    await leave(tester);
  });

  testWidgets('with reduced motion: no intro, no pulse, the steps still follow the taps', (tester) async {
    await start(tester);
    await pumpFirstGame(tester, reduceMotion: true);
    final game = gameOf(tester);
    expect(game.introPlaying, isFalse);
    expect(find.text(_step1), findsOneWidget);
    expect(find.byKey(FirstPlayTutorialOverlay.pulseKey), findsNothing, reason: 'a static highlight');
    expect(game.clockRunning, isFalse);
    final pair = tutorialOf(tester)!.pair;
    await tapTile(tester, pair.$1);
    await pumpUntilText(tester, _step2);
    await tester.tap(find.text('Next'));
    await pumpUntilText(tester, _step3);
    expect(find.byKey(FirstPlayTutorialOverlay.pulseKey), findsNothing);
    await tapTile(tester, pair.$2);
    await pumpUntilText(tester, _step4);
    expect(game.state.status, GameStatus.playing);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
    expect(game.clockRunning, isTrue);
    await leave(tester);
  });
}

// The redesigned gameplay screen (1.1.0) in both looks at phone and tablet
// sizes: mid-combo with the timer bar and a hint's glow, the Tray full card,
// the Restart confirm card, the ad offer for one more Hint and Level
// Complete; also 360x640 at 1.3x text.
//
// Always checks that layout succeeds without exceptions or overflow. When
// CAPTURE_DIR is set, also writes `gameplay-<look>-<scene>-<phone>.png`:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/gameplay_redesign_capture_test.dart
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/game_hud.dart';
import 'package:brain_train/features/gameplay/widgets/hint_glow.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/lobby_support.dart';
import '../helpers/fake_stopwatch.dart';
import '../platform/fake_rewarded_ads.dart';
import 'gameplay_support.dart';

const Phone _small = (name: '360x640', width: 360, height: 640, dpr: 2, top: 24, bottom: 0);
const Phone _iphone = (name: '393x852', width: 393, height: 852, dpr: 3, top: 59, bottom: 34);
const Phone _large = (name: '411x914', width: 411, height: 914, dpr: 2.625, top: 24, bottom: 16);
const Phone _ipad = (name: 'ipad-13', width: 1032, height: 1376, dpr: 2, top: 24, bottom: 20);

void main() {
  late AppServices services;
  late ContentSnapshot snapshot;
  late LevelManifestEntry meadow;
  late FakeRewardedAds ads;

  setUpAll(loadCaptureFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async {
      ads = FakeRewardedAds();
      services = await testServices(ads: RewardedAdsController(ads));
      snapshot = services.content.snapshot;
      // A difficulty-4 level: 4-slot tray.
      meadow = snapshot.playableEntries.firstWhere((e) => e.difficulty == '4');
    });
  }

  Future<void> open(
    WidgetTester tester,
    Phone phone,
    ThemeMode mode, {
    required SavedGame resume,
    Stopwatch? clock,
    double textScale = 1,
  }) async {
    await pumpLobby(
      tester,
      services: services,
      home: GameScreen(snapshot: snapshot, entry: meadow, resume: resume, stopwatch: clock),
      phone: phone,
      textScale: textScale,
      themeMode: mode,
    );
    await finishIntro(tester);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Plays [pairs] solver pairs from the current position, 0.6 s apart on
  /// the game clock (a combo).
  Future<void> playPairs(WidgetTester tester, FakeStopwatch clock, int pairs) async {
    final game = gameOf(tester);
    final level = game.level;
    final solution = MahjongSolver(geometry: game.engine.geometry, rules: game.engine.rules)
        .solve(game.engine.remainingMask)
        .solution;
    for (final (a, b) in solution.take(pairs)) {
      game
        ..tapTile(level.tiles[a].tileId)
        ..tapTile(level.tiles[b].tileId);
      clock.advance(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  final cases = [
    for (final look in ['night', 'day'])
      for (final phone in [_small, _iphone, _large, _ipad]) (look, phone, 1.0),
    ('night', _small, 1.3),
    ('day', _small, 1.3),
  ];

  for (final (look, phone) in [('night', _large), ('day', _small)]) {
    final mode = look == 'day' ? ThemeMode.light : ThemeMode.dark;
    testWidgets('$look shuffle turning tiles, then the shuffled board ${phone.name}', (tester) async {
      await start(tester);
      final clock = FakeStopwatch();
      await open(tester, phone, mode, resume: solvedSave(snapshot, meadow, pairs: 2), clock: clock);
      final game = gameOf(tester);
      final before = {for (final id in game.state.remaining) id: game.symbolCodeOf(id)};
      await tester.tap(find.byKey(const ValueKey('action-shuffle')));
      await tester.pump();
      // The turn runs on real time: catch it part-way.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-shuffle-turning-${phone.name}', phone.dpr);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      await settle(tester);
      expect(before.entries.where((e) => game.symbolCodeOf(e.key) != e.value), isNotEmpty);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-shuffled-${phone.name}', phone.dpr);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (look, phone, textScale) in cases) {
    final mode = look == 'day' ? ThemeMode.light : ThemeMode.dark;
    final suffix = '${phone.name}${textScale == 1 ? '' : '-text130'}';

    testWidgets('$look gameplay $suffix: combo, hint, cards, level complete', (tester) async {
      await start(tester);

      // Mid-combo: three quick pairs, then a hint.
      final clock = FakeStopwatch();
      await open(tester, phone, mode, resume: solvedSave(snapshot, meadow, pairs: 2), clock: clock, textScale: textScale);
      await playPairs(tester, clock, 3);
      await settle(tester);
      expect(gameOf(tester).activeCombo, 3);
      expect(find.byType(ComboTimerBar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('action-hint')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.state<HintGlowOverlayState>(find.byType(HintGlowOverlay)).hint, isNotNull);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-combo-hint-$suffix', phone.dpr);

      // Restart confirm.
      await tester.tap(find.byTooltip('Restart'));
      await settle(tester);
      expect(find.text('Restart this level?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-restart-confirm-$suffix', phone.dpr);
      await tester.tap(find.text('Keep playing'));
      await settle(tester);

      // The ad offer once the hints are gone.
      final game = gameOf(tester);
      while (game.usesLeft(GameAction.hint) > 0 && game.useHint() != null) {}
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('action-hint')));
      await settle(tester);
      expect(find.text('Watch an ad for +1 Hint?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-ad-offer-$suffix', phone.dpr);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());

      // Tray full.
      final (save, last) = nearlyFullSave(snapshot, meadow);
      await open(tester, phone, mode, resume: save, textScale: textScale);
      await tapBoardTile(tester, snapshot, meadow, save.history, last);
      await settle(tester);
      await settle(tester);
      expect(find.text('Tray full'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-tray-full-$suffix', phone.dpr);
      await tester.pumpWidget(const SizedBox());

      // Level Complete: the last pair played live (the record is saved).
      final total = snapshot.levels[meadow.levelId]!.pairCount;
      final winClock = FakeStopwatch();
      await open(
        tester,
        phone,
        mode,
        resume: solvedSave(snapshot, meadow, pairs: total - 1, elapsedMs: 134000),
        clock: winClock,
        textScale: textScale,
      );
      gameOf(tester).useHint();
      await playPairs(tester, winClock, 1);
      await settle(tester);
      await settle(tester);
      expect(find.text('Level Complete!'), findsOneWidget);
      expect(find.text('Next Level'), findsOneWidget);
      expect(find.text('Level Select'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureLobby(tester, 'gameplay-$look-level-complete-$suffix', phone.dpr);
      await tester.pumpWidget(const SizedBox());
      ads.setStatus(RewardedAdStatus.ready);
    });
  }
}

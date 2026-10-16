// Revive on the Tray full card plays a rewarded ad first (owner): only an
// earned reward revives; no ad (loading, offline) leaves Revive off with a
// note; Restart always works.
import 'dart:async';

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_rewarded_ads.dart';
import 'lobby_support.dart';

GameController _gameOf(WidgetTester tester) => tester.widget<BoardView>(find.byType(BoardView)).controller;

/// A saved game of [entry] lost with a full tray: free tiles taken one by
/// one, never a match, until the tray is full.
SavedGame _trayFullSave(ContentSnapshot snapshot, LevelManifestEntry entry) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = GameEngine(level: level, rules: MatchRules(level: level, registry: snapshot.registry));
  while (engine.state.status == GameStatus.playing) {
    final next = (engine.state.free.toList()..sort()).firstWhere(
      (id) => !engine.state.tray.any((t) => engine.rules.matches(engine.indexOf(t)!, engine.indexOf(id)!)),
    );
    engine.tap(next);
  }
  expect(engine.state.status, GameStatus.trayFull);
  return SavedGame(
    levelId: level.levelId,
    levelUrl: entry.ref.url,
    history: engine.state.history,
    moveCount: engine.state.moveCount,
    elapsedMs: 42000,
  );
}

/// Real time for art decoding plus fake time for the card's entrance.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

PremiumButton _revive(WidgetTester tester) => tester.widget<PremiumButton>(find.widgetWithText(PremiumButton, 'Revive'));

void main() {
  late AppServices services;
  late FakeRewardedAds ads;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Resumes a tray-full save of level 1 (as after an app restart) with the
  /// ads in [status]; the Tray full card is up.
  Future<void> open(WidgetTester tester, {RewardedAdStatus status = RewardedAdStatus.ready}) async {
    ads = FakeRewardedAds(status);
    await tester.runAsync(() async => services = await testServices(ads: RewardedAdsController(ads)));
    tester.view
      ..physicalSize = const Size(411 * 2.625, 914 * 2.625)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final snapshot = services.content.snapshot;
    final entry = snapshot.playableEntries.first;
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildBrainTrainTheme(Brightness.dark),
          home: GameScreen(snapshot: snapshot, entry: entry, resume: _trayFullSave(snapshot, entry)),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Tray full'), findsOneWidget);
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('opening a game preloads an ad, and so does the Tray full card', (tester) async {
    await open(tester);
    expect(ads.preloads, greaterThanOrEqualTo(2));
    expect(ads.shows, 0);
    await leave(tester);
  });

  testWidgets('reward earned: the ad plays with the clock stopped, then the tiles go back', (tester) async {
    await open(tester);
    final game = _gameOf(tester);
    final elapsed = game.elapsed;
    expect(_revive(tester).onPressed, isNotNull);
    expect(find.text(kReviveLoadingNote), findsNothing);
    ads.gate = Completer<void>();
    await tester.tap(find.text('Revive'));
    await tester.pump();
    // The ad is on screen: no revive yet, Revive off, the clock stopped.
    expect(ads.shows, 1);
    expect(game.state.status, GameStatus.trayFull);
    expect(_revive(tester).onPressed, isNull);
    expect(game.clockRunning, isFalse);
    await tester.pump(const Duration(seconds: 20));
    expect(game.elapsed, elapsed, reason: 'the clock does not run during the ad');
    ads.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(game.state.status, GameStatus.playing, reason: 'revived after the reward');
    expect(game.state.tray, isEmpty);
    expect(game.clockRunning, isTrue);
    await _settle(tester);
    expect(find.text('Tray full'), findsNothing);
    expect(ads.shows, 1);
    await leave(tester);
  });

  testWidgets('ad closed before the reward: no revive, the card stays, Revive shows another ad', (tester) async {
    await open(tester);
    final game = _gameOf(tester);
    ads
      ..showResult = RewardedAdResult.dismissed
      ..afterShow = RewardedAdStatus.ready;
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(game.state.status, GameStatus.trayFull);
    expect(find.text('Tray full'), findsOneWidget);
    expect(find.text(kReviveDismissedNote), findsOneWidget);
    expect(_revive(tester).onPressed, isNotNull);
    // Again, watched to the end this time.
    ads.showResult = RewardedAdResult.earned;
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(ads.shows, 2);
    expect(game.state.status, GameStatus.playing);
    await _settle(tester);
    await leave(tester);
  });

  testWidgets('an ad that fails to show does not revive', (tester) async {
    await open(tester);
    ads.showResult = RewardedAdResult.failed;
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(_gameOf(tester).state.status, GameStatus.trayFull);
    expect(find.text('Tray full'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('no ad loaded yet: Revive is off with a loading note, Restart works', (tester) async {
    await open(tester, status: RewardedAdStatus.loading);
    expect(_revive(tester).onPressed, isNull);
    expect(find.text(kReviveLoadingNote), findsOneWidget);
    await tester.tap(find.text('Revive'), warnIfMissed: false);
    await tester.pump();
    expect(ads.shows, 0);
    // The ad arrives: Revive comes on.
    ads.setStatus(RewardedAdStatus.ready);
    await tester.pump();
    expect(_revive(tester).onPressed, isNotNull);
    expect(find.text(kReviveLoadingNote), findsNothing);
    // Restart is always there.
    ads.setStatus(RewardedAdStatus.loading);
    await tester.pump();
    await tester.tap(find.text('Restart'));
    await _settle(tester);
    expect(find.text('Tray full'), findsNothing);
    expect(_gameOf(tester).state.status, GameStatus.playing);
    await leave(tester);
  });

  testWidgets('offline: Revive is off and says to connect', (tester) async {
    await open(tester, status: RewardedAdStatus.offline);
    expect(_revive(tester).onPressed, isNull);
    expect(find.text(kReviveOfflineNote), findsOneWidget);
    expect(find.text(kReviveLoadingNote), findsNothing);
    await tester.tap(find.text('Revive'), warnIfMissed: false);
    await tester.pump();
    expect(ads.shows, 0);
    expect(_gameOf(tester).state.status, GameStatus.trayFull);
    await leave(tester);
  });

  testWidgets('a build without ads revives at once, with no ad', (tester) async {
    await open(tester, status: RewardedAdStatus.off);
    expect(find.text(kReviveLoadingNote), findsNothing);
    expect(find.byIcon(Icons.ondemand_video_rounded), findsNothing);
    await tester.tap(find.text('Revive'));
    await tester.pump();
    expect(ads.shows, 0);
    expect(_gameOf(tester).state.status, GameStatus.playing);
    await _settle(tester);
    await leave(tester);
  });
}

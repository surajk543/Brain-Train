// Revive on the Tray full card plays a rewarded ad first (owner): only an
// earned reward revives; no ad (loading, offline) leaves Revive off with a
// note; Restart always works. Online with no ad to show, Revive is free after
// kAdFallbackDelay (at once after a failed load or a failed show; owner,
// 2026-10-17); offline it stays off. At most kMaxRevivesPerLevel revives per
// attempt, free ones included; then Restart only, and no ad.
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
/// one, never a match, until the tray is full; [revives] times revived and
/// filled again before that.
SavedGame _trayFullSave(ContentSnapshot snapshot, LevelManifestEntry entry, {int revives = 0}) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = GameEngine(level: level, rules: MatchRules(level: level, registry: snapshot.registry));
  for (var round = 0; round <= revives; round++) {
    if (round > 0) expect(engine.revive(), isNotNull);
    while (engine.state.status == GameStatus.playing) {
      final next = (engine.state.free.toList()..sort()).firstWhere(
        (id) => !engine.state.tray.any((t) => engine.rules.matches(engine.indexOf(t)!, engine.indexOf(id)!)),
      );
      engine.tap(next);
    }
  }
  expect(engine.state.status, GameStatus.trayFull);
  expect(engine.revivesUsed, revives);
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

  /// Resumes a tray-full save of level 1 (as after an app restart, after
  /// [revives] revives) with the ads in [status]; the Tray full card is up.
  Future<void> open(
    WidgetTester tester, {
    RewardedAdStatus status = RewardedAdStatus.ready,
    bool online = true,
    int revives = 0,
  }) async {
    ads = FakeRewardedAds(status)..online = online;
    // Built on the test's fake clock (not in runAsync): its stream callbacks
    // and the fallback's online check then run when the test pumps.
    final controller = RewardedAdsController(ads);
    await tester.runAsync(() async => services = await testServices(ads: controller));
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
          home: GameScreen(snapshot: snapshot, entry: entry, resume: _trayFullSave(snapshot, entry, revives: revives)),
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

  testWidgets('an ad that fails to show revives free (online)', (tester) async {
    await open(tester);
    ads.showResult = RewardedAdResult.failed;
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(ads.shows, 1);
    expect(ads.onlineChecks, 1);
    expect(_gameOf(tester).state.status, GameStatus.playing);
    await _settle(tester);
    expect(find.text('Tray full'), findsNothing);
    await leave(tester);
  });

  testWidgets('an ad that fails to show while offline does not revive', (tester) async {
    await open(tester, online: false);
    ads.showResult = RewardedAdResult.failed;
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(_gameOf(tester).state.status, GameStatus.trayFull);
    expect(find.text('Tray full'), findsOneWidget);
    expect(find.text(kReviveOfflineNote), findsOneWidget);
    expect(_revive(tester).onPressed, isNull);
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

  testWidgets('no ad loaded: after kAdFallbackDelay Revive is free, and the revive is saved like any other', (tester) async {
    await open(tester, status: RewardedAdStatus.loading);
    final game = _gameOf(tester);
    expect(_revive(tester).onPressed, isNull);
    expect(find.text(kReviveLoadingNote), findsOneWidget);
    await tester.pump(kAdFallbackDelay);
    await tester.pump();
    expect(find.text(kReviveLoadingNote), findsNothing);
    expect(find.text(kReviveFreeNote), findsOneWidget);
    expect(find.byIcon(Icons.ondemand_video_rounded), findsNothing, reason: 'no ad to watch');
    expect(_revive(tester).onPressed, isNotNull);
    final before = game.state.history;
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(ads.shows, 0);
    expect(game.state.status, GameStatus.playing);
    expect(game.state.tray, isEmpty);
    expect(game.state.history, [...before, GameEngine.reviveMarker], reason: 'the same engine path as an ad revive');
    expect(game.revivesLeft, kMaxRevivesPerLevel - 1, reason: 'a free revive counts');
    expect(game.clockRunning, isTrue);
    expect(services.progress.savedGame()!.history, game.state.history, reason: 'saved like an ad revive');
    await _settle(tester);
    expect(find.text('Tray full'), findsNothing);
    await leave(tester);
  });

  testWidgets('no fill (a failed load): Revive is free at once', (tester) async {
    await open(tester, status: RewardedAdStatus.loading);
    ads.failLoad();
    await tester.pump();
    await tester.pump();
    expect(find.text(kReviveFreeNote), findsOneWidget);
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(ads.shows, 0);
    expect(_gameOf(tester).state.status, GameStatus.playing);
    await _settle(tester);
    await leave(tester);
  });

  testWidgets('offline: Revive stays off however long the card is up', (tester) async {
    await open(tester, status: RewardedAdStatus.offline);
    await tester.pump(kAdFallbackDelay * 3);
    await tester.pump();
    expect(_revive(tester).onPressed, isNull);
    expect(find.text(kReviveOfflineNote), findsOneWidget);
    expect(find.text(kReviveFreeNote), findsNothing);
    // Loading while the online check fails: off, and it says to connect.
    ads
      ..online = false
      ..setStatus(RewardedAdStatus.loading);
    await tester.pump(kAdFallbackDelay);
    await tester.pump();
    expect(_revive(tester).onPressed, isNull);
    expect(find.text(kReviveOfflineNote), findsOneWidget);
    expect(ads.shows, 0);
    expect(_gameOf(tester).state.status, GameStatus.trayFull);
    await leave(tester);
  });

  testWidgets('rapid taps revive once: a free revive and an ad', (tester) async {
    await open(tester, status: RewardedAdStatus.loading);
    final game = _gameOf(tester);
    await tester.pump(kAdFallbackDelay);
    await tester.pump();
    final free = _revive(tester).onPressed!;
    free();
    free();
    free();
    await tester.pump();
    await tester.pump();
    expect(game.state.status, GameStatus.playing);
    expect(game.revivesLeft, kMaxRevivesPerLevel - 1);
    expect(game.state.history.where((h) => h == GameEngine.reviveMarker), hasLength(1));
    await leave(tester);

    await open(tester);
    final again = _gameOf(tester);
    ads.gate = Completer<void>();
    final watch = _revive(tester).onPressed!;
    watch();
    watch();
    await tester.pump();
    ads.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(ads.shows, 1);
    expect(again.state.status, GameStatus.playing);
    expect(again.revivesLeft, kMaxRevivesPerLevel - 1);
    await leave(tester);
  });

  testWidgets('no revives left (a resumed save with two): Restart only, with a note, and no ad', (tester) async {
    await open(tester, revives: kMaxRevivesPerLevel);
    final game = _gameOf(tester);
    expect(game.revivesLeft, 0);
    expect(game.canRevive, isFalse);
    expect(find.text('Revive'), findsNothing);
    expect(find.text(kNoRevivesLeftNote), findsOneWidget);
    expect(find.text(kReviveLoadingNote), findsNothing);
    expect(find.byIcon(Icons.ondemand_video_rounded), findsNothing);
    final restart = tester.widget<PremiumButton>(find.widgetWithText(PremiumButton, 'Restart'));
    expect(restart.primary, isTrue);
    // Even with an ad ready, none is offered.
    await tester.pump(kAdFallbackDelay);
    expect(ads.shows, 0);
    expect(ads.onlineChecks, 0);
    // Restart gives the revives back.
    await tester.tap(find.text('Restart'));
    await _settle(tester);
    expect(find.text('Tray full'), findsNothing);
    expect(game.revivesLeft, kMaxRevivesPerLevel);
    await leave(tester);
  });

  testWidgets('the second revive (free) is the last: the next full tray offers Restart only', (tester) async {
    await open(tester, status: RewardedAdStatus.loading, revives: 1);
    final game = _gameOf(tester);
    expect(game.revivesLeft, 1);
    ads.failLoad();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Revive'));
    await tester.pump();
    await tester.pump();
    expect(game.revivesLeft, 0);
    await _settle(tester);
    // Fill the tray again.
    while (game.state.status == GameStatus.playing) {
      final next = (game.state.free.toList()..sort()).firstWhere(
        (id) => !game.state.tray.any((t) => game.engine.rules.matches(game.engine.indexOf(t)!, game.engine.indexOf(id)!)),
      );
      game.tapTile(next);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settle(tester);
    await _settle(tester);
    expect(find.text('Tray full'), findsOneWidget);
    expect(find.text('Revive'), findsNothing);
    expect(find.text(kNoRevivesLeftNote), findsOneWidget);
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

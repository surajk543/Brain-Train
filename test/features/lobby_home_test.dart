import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/common/flowing_leaves.dart';
import 'package:brain_train/features/common/frosted_glass.dart';
import 'package:brain_train/features/common/lobby_particles.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/home/widgets/lobby_footer.dart';
import 'package:brain_train/features/levels/level_select_screen.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:brain_train/features/home/widgets/lobby_tagline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_support.dart';

SavedGame _savedOn(AppServices services, int index, {String? url}) {
  final entry = services.content.snapshot.playableEntries[index];
  return SavedGame(
    levelId: entry.levelId,
    levelUrl: url ?? entry.ref.url,
    history: const [],
    moveCount: 0,
    elapsedMs: 0,
  );
}

Future<AppServices> _start(WidgetTester tester, [Future<void> Function(AppServices services)? prepare]) async {
  late AppServices services;
  await tester.runAsync(() async {
    services = await testServices();
    await prepare?.call(services);
  });
  return services;
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
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

  group('play label', () {
    test('follows progress: next level, then a resumable game', () async {
      final services = await testServices();
      final entries = services.content.snapshot.playableEntries;
      expect(HomeScreen.playLabel(services), 'Play · Level 1');

      await services.progress.recordWin(entries[0].levelId, moves: 8, timeMs: 30000);
      expect(HomeScreen.playLabel(services), 'Play · Level 2');

      await services.progress.saveGame(_savedOn(services, 1));
      expect(HomeScreen.playLabel(services), 'Continue · Level 2');
      expect(HomeScreen.resumable(services)!.$1.levelId, entries[1].levelId);
    });

    test('a save from another level revision is not offered', () async {
      final services = await testServices();
      await services.progress.saveGame(_savedOn(services, 2, url: 'levels/level-0003-v0.json'));
      expect(HomeScreen.resumable(services), isNull);
      expect(HomeScreen.playLabel(services), 'Play · Level 1');
    });

    test('with every level won, Play offers a replay of the last level', () async {
      final services = await testServices();
      expect(HomeScreen.allCompleted(services), isFalse);
      for (final entry in services.content.snapshot.playableEntries) {
        await services.progress.recordWin(entry.levelId, moves: 10, timeMs: 1000);
      }
      final last = services.content.snapshot.playableEntries.last;
      expect(HomeScreen.allCompleted(services), isTrue);
      expect(HomeScreen.playLabel(services), 'Replay · Level ${last.order}');
    });
  });

  group('footer', () {
    test('says nothing in normal states, a notice with the content version otherwise', () async {
      final services = await testServices();
      final ContentSnapshot snapshot = services.content.snapshot;
      final count = snapshot.playableEntries.length;
      final version = snapshot.contentVersion;
      expect(count, greaterThan(0));
      expect(version, isNotEmpty);
      expect(LobbyContentFooter.label(snapshot, ContentSyncStatus.upToDate), isNull);
      expect(LobbyContentFooter.label(snapshot, ContentSyncStatus.idle), isNull);
      expect(LobbyContentFooter.label(snapshot, ContentSyncStatus.checking), isNull);
      expect(
        LobbyContentFooter.label(snapshot, ContentSyncStatus.offline),
        'Offline · playing saved levels · v$version',
      );
      expect(LobbyContentFooter.label(snapshot, ContentSyncStatus.updated), 'New content installed · v$version');
      expect(
        LobbyContentFooter.label(snapshot, ContentSyncStatus.rejected),
        'Update skipped · playing saved levels · v$version',
      );
    });
  });

  testWidgets('home works offline on bundled content', (tester) async {
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    final snapshot = services.content.snapshot;
    expect(snapshot.origin, ContentOrigin.bundled);
    expect(snapshot.playableEntries, hasLength(snapshot.manifest.levels.length));
    expect(services.content.status, ContentSyncStatus.offline);
    expect(find.byType(LobbyTagline), findsOneWidget);
    expect(find.text('Train your'), findsOneWidget);
    expect(find.text('brain'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(LobbyTagline), matching: find.byType(FrostedGlass)),
      findsOneWidget,
      reason: 'frosted glass',
    );
    expect(find.byType(BackdropFilter), findsNothing, reason: 'no live backdrop blur behind the ambient animation');
    expect(
      find.byType(Image).evaluate().where((e) => '${(e.widget as Image).image}'.contains('brain_train_logo')),
      isEmpty,
    );
    expect(find.text('Play · Level 1'), findsOneWidget);
    expect(find.text(LobbyContentFooter.label(snapshot, ContentSyncStatus.offline)!), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('the play label updates live when progress changes', (tester) async {
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.text('Play · Level 1'), findsOneWidget);
    await tester.runAsync(() => services.progress.saveGame(_savedOn(services, 0)));
    await tester.pump();
    expect(find.text('Continue · Level 1'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('every level won: the lobby says new levels are coming soon', (tester) async {
    final services = await _start(tester, (services) async {
      for (final entry in services.content.snapshot.playableEntries) {
        await services.progress.recordWin(entry.levelId, moves: 10, timeMs: 1000);
      }
    });
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone);
    final count = services.content.snapshot.playableEntries.length;
    expect(find.text('All $count levels complete!'), findsOneWidget);
    expect(find.text('New levels are coming soon. Stay tuned!'), findsOneWidget);
    expect(find.text('Replay · Level $count'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a small phone');
    await captureLobby(tester, 'home-all-complete-360x640', smallPhone.dpr);
    await _leave(tester);
  });

  testWidgets('Continue opens the saved game, once, however fast it is tapped', (tester) async {
    final services = await _start(tester, (services) async {
      await services.progress.recordWin(services.content.snapshot.playableEntries[0].levelId, moves: 8, timeMs: 1);
      await services.progress.saveGame(_savedOn(services, 1));
    });
    await pumpLobby(tester, services: services, home: const HomeScreen());
    final play = find.text('Continue · Level 2');
    await tester.tap(play);
    await tester.tap(play, warnIfMissed: false);
    await tester.pump();
    await tester.tap(play, warnIfMissed: false);
    await settleLobby(tester);
    expect(find.byType(GameScreen), findsOneWidget);
    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(game.entry.order, 2);
    expect(game.resume, isNotNull);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settleLobby(tester);
    expect(find.byType(GameScreen), findsNothing);
    await _leave(tester);
  });

  testWidgets('Levels and Settings open their screens and come back', (tester) async {
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());

    await tester.tap(find.text('Completed Levels'));
    await tester.tap(find.text('Completed Levels'), warnIfMissed: false);
    await settleLobby(tester);
    expect(find.byType(LevelSelectScreen), findsOneWidget);
    await tester.pageBack();
    await settleLobby(tester);
    expect(find.byType(LevelSelectScreen), findsNothing);

    await tester.tap(find.text('Settings'));
    await settleLobby(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    await tester.pageBack();
    await settleLobby(tester);
    expect(find.text('Continue · Level 1'), findsNothing);
    expect(find.text('Play · Level 1'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('buttons are labelled for screen readers and at least 48px tall', (tester) async {
    final handle = tester.ensureSemantics();
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone);
    expect(find.bySemanticsLabel('Play, Level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Completed Levels'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Train your brain'), findsOneWidget);
    for (final key in ['lobby-play', 'lobby-levels', 'lobby-settings']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height, greaterThanOrEqualTo(48), reason: key);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
    await _leave(tester);
  });

  testWidgets('ambient animation runs, pauses under another screen, and stays still with reduced motion', (
    tester,
  ) async {
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'fireflies and leaves running');
    bool homeTicking() => TickerMode.valuesOf(tester.element(find.byType(LobbyParticles, skipOffstage: false))).enabled;
    expect(homeTicking(), isTrue);

    await tester.tap(find.text('Completed Levels'));
    await settleLobby(tester);
    expect(homeTicking(), isFalse, reason: 'home covered: its tickers are muted');
    expect(find.byType(FlowingLeaves), findsOneWidget, reason: 'only the Levels leaves are on stage');
    await tester.pageBack();
    await settleLobby(tester);
    expect(homeTicking(), isTrue, reason: 'home visible again');
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await _leave(tester);

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(tester.binding.transientCallbackCount, 0, reason: 'reduced motion: nothing animates');
    expect(find.text('Play · Level 1'), findsOneWidget);
    await _leave(tester);
  });

  for (final phone in [smallPhone, largePhone, tallPhone]) {
    testWidgets('levels and settings fit ${phone.name} at 1.3x text', (tester) async {
      final services = await _start(tester);
      await pumpLobby(tester, services: services, home: const LevelSelectScreen(), phone: phone, textScale: 1.3);
      expect(find.text(services.content.snapshot.playableEntries.first.title), findsOneWidget);
      await pumpLobby(tester, services: services, home: const SettingsScreen(), phone: phone, textScale: 1.3);
      expect(find.text('Vibration'), findsOneWidget);
      await _leave(tester);
    });
  }
}

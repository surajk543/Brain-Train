import 'dart:io';

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_exception.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/common/flowing_leaves.dart';
import 'package:brain_train/features/common/lobby_particles.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/home/widgets/lobby_footer.dart';
import 'package:brain_train/features/levels/level_select_screen.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:brain_train/features/common/premium_mahjong_tile.dart';
import 'package:brain_train/features/home/widgets/lobby_hero.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 'lobby_support.dart';

/// Artwork for every path (any bytes do: the hero only checks presence).
class _AnyArtwork implements ContentSource {
  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) async => Uint8List(1);
}

/// No artwork on the device.
class _NoArtwork implements ContentSource {
  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) async =>
      throw ContentException(ContentErrorKind.notFound, 'missing', path: path);
}

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

    test('a legacy save on a completed level is not offered', () async {
      final entries = (await testServices()).content.snapshot.playableEntries;
      const record = '{"bestMoves":8,"bestTimeMs":1,"completedAt":"2026-10-01T10:00:00.000"}';
      SharedPreferences.setMockInitialValues({
        'progress.current.v2':
            '{"levelId":"${entries[0].levelId}","levelUrl":"${entries[0].ref.url}","history":[],"moveCount":0,"elapsedMs":0}',
        'progress.completed.v1': '{"${entries[0].levelId}":$record,"${entries[1].levelId}":$record}',
      });
      final services = await testServices();
      expect(services.progress.savedGame()!.levelId, entries[0].levelId);
      expect(HomeScreen.resumable(services), isNull);
      expect(HomeScreen.playLabel(services), 'Play · Level 3');
    });

    test('a replay of level 1 leaves "Continue · Level 2" alone', () async {
      final services = await testServices();
      final entries = services.content.snapshot.playableEntries;
      await services.progress.recordWin(entries[0].levelId, moves: 8, timeMs: 1);
      await services.progress.saveGame(_savedOn(services, 1));
      await services.progress.saveGame(_savedOn(services, 0));
      expect(HomeScreen.playLabel(services), 'Continue · Level 2');
      expect(services.progress.savedGame()!.levelId, entries[1].levelId);
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
    test('the ready levels and the content version; a notice takes the count\'s place', () async {
      final services = await testServices();
      final ContentSnapshot snapshot = services.content.snapshot;
      final version = snapshot.contentVersion;
      expect(version, isNotEmpty);
      String label(ContentSyncStatus status, int ready, [int window = 5]) =>
          LobbyContentFooter.label(snapshot, status, ready: ready, window: window);
      for (final status in [ContentSyncStatus.upToDate, ContentSyncStatus.idle, ContentSyncStatus.checking]) {
        expect(label(status, 5), '5 levels ready · v$version');
        expect(label(status, 1), '1 level ready · v$version');
        expect(label(status, 0), 'Getting levels ready · v$version');
        expect(label(status, 0, 0), 'v$version', reason: 'every level won: no next levels');
      }
      expect(label(ContentSyncStatus.offline, 4), 'Offline · playing saved levels · v$version');
      expect(label(ContentSyncStatus.updated, 5), 'New content installed · v$version');
      expect(label(ContentSyncStatus.rejected, 5), 'Update skipped · playing saved levels · v$version');
    });

    test('counts only the window levels on the device, never unavailable ones', () async {
      final services = await testServices();
      // The starter pack holds levels 1-5: the whole first window.
      expect(services.content.windowReadiness, (ready: 5, window: 5));
      final entries = services.content.snapshot.playableEntries;
      await services.progress.recordWin(entries[0].levelId, moves: 8, timeMs: 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Levels 2-6: level 6 is not bundled and the network is out of reach.
      expect(services.content.isReady(entries[5]), isFalse);
      expect(services.content.windowReadiness, (ready: 4, window: 5));
      for (final entry in entries) {
        await services.progress.recordWin(entry.levelId, moves: 8, timeMs: 1);
      }
      expect(services.content.windowReadiness, (ready: 0, window: 0));
    });
  });

  testWidgets('the footer shows the real ready count and content version, live', (tester) async {
    late AppServices services;
    // The host serves the starter pack: content is up to date, no notice.
    await tester.runAsync(() async => services = await testServices(client: starterHost));
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await tester.runAsync(() => services.content.topUp());
    await tester.pump();
    final version = services.content.snapshot.contentVersion;
    expect(services.content.status, ContentSyncStatus.upToDate);
    expect(find.text('5 levels ready · v$version'), findsOneWidget);
    await tester.runAsync(() async {
      await services.progress.recordWin(services.content.snapshot.playableEntries[0].levelId, moves: 8, timeMs: 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('4 levels ready · v$version'), findsOneWidget, reason: 'level 6 is not on the device');
    await _leave(tester);
  });

  group('hero tiles', () {
    test('reference symbols first, starter pack stand-ins when their art is not on the device', () async {
      final snapshot = (await testServices()).content.snapshot;
      // Offline on a fresh install: the bundled hero art (leaf, sunflower,
      // purple flower), never a network wait.
      expect(await LobbyHero.symbolsFor(snapshot), [for (final slot in LobbyHero.slots) slot.first]);
      // Only the starter pack's art (as if the registry's art for them had
      // changed and was not cached yet): its stand-ins.
      final starterOnly = ContentSnapshot(
        manifest: snapshot.manifest,
        manifestJson: snapshot.manifestJson,
        registry: snapshot.registry,
        origin: snapshot.origin,
        artwork: repoContent,
      );
      final codes = await LobbyHero.symbolsFor(starterOnly);
      expect(codes, hasLength(3));
      expect(codes.toSet(), hasLength(3));
      for (final (i, code) in codes.indexed) {
        expect(LobbyHero.slots[i], contains(code), reason: 'slot $i');
        expect(code, isNot(LobbyHero.slots[i].first), reason: 'slot $i: not in the starter pack');
        expect(snapshot.registry[code], isNotNull);
      }
      // With every reference symbol's art on the device: leaf, sunflower,
      // purple flower.
      final everything = ContentSnapshot(
        manifest: snapshot.manifest,
        manifestJson: snapshot.manifestJson,
        registry: snapshot.registry,
        origin: snapshot.origin,
        artwork: _AnyArtwork(),
      );
      expect(await LobbyHero.symbolsFor(everything), [for (final slot in LobbyHero.slots) slot.first]);
      // Nothing on the device at all: no tiles rather than a network wait.
      final nothing = ContentSnapshot(
        manifest: snapshot.manifest,
        manifestJson: snapshot.manifestJson,
        registry: snapshot.registry,
        origin: snapshot.origin,
        artwork: _NoArtwork(),
      );
      expect(await LobbyHero.symbolsFor(nothing), isEmpty);
    });

    test('the bundled hero art is the published files of the reference symbols', () async {
      final registry = (await testServices()).content.snapshot.registry;
      expect(File('pubspec.yaml').readAsStringSync(), contains('- ${kHeroArtPrefix}symbols/v1/'));
      final bundled = {
        for (final file in Directory('${kHeroArtPrefix}symbols/v1').listSync().whereType<File>())
          file.path.split('/').last,
      };
      final expected = <String>{};
      for (final slot in LobbyHero.slots) {
        final symbol = registry[slot.first]!;
        expect(symbol.type, SymbolType.image, reason: slot.first);
        expect(symbol.assetPath, startsWith('symbols/v1/'));
        expected.add(symbol.assetPath!.split('/').last);
        // Read like the app does: checked against the registry's sha256.
        final bytes = await BundledContentSource(
          (key) async => File(key).existsSync() ? File(key).readAsBytesSync() : null,
          prefix: kHeroArtPrefix,
        ).read(symbol.assetPath!, ContentKind.image, sha256: symbol.sha256);
        expect(bytes, isNotEmpty);
      }
      expect(bundled, expected, reason: 'exactly the three hero symbols');
    });
  });

  testWidgets('status bar icons: light over the night scene, on home and sub-screens', (tester) async {
    final services = await _start(tester);
    Brightness? iconsOf(Widget screen) => tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(of: find.byType(screen.runtimeType), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)),
        )
        .first
        .value
        .statusBarIconBrightness;
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(iconsOf(const HomeScreen()), Brightness.light, reason: 'home');
    await pumpLobby(tester, services: services, home: const SettingsScreen());
    expect(iconsOf(const SettingsScreen()), Brightness.light, reason: 'settings');
    await _leave(tester);
  });

  testWidgets('home works offline on bundled content', (tester) async {
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    final snapshot = services.content.snapshot;
    expect(snapshot.origin, ContentOrigin.bundled);
    expect(snapshot.playableEntries, hasLength(snapshot.manifest.levels.length));
    expect(services.content.status, ContentSyncStatus.offline);
    expect(find.byType(LobbyHero), findsOneWidget);
    expect(find.bySemanticsLabel('Tile Park: Puzzles'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(LobbyHero), matching: find.byType(PremiumMahjongTile)),
      findsNWidgets(3),
      reason: 'three hero tiles from the bundled art',
    );
    expect(find.byType(BackdropFilter), findsNothing, reason: 'no live backdrop blur behind the ambient animation');
    expect(
      find.byType(Image).evaluate().where((e) => '${(e.widget as Image).image}'.contains('tile_park_logo')),
      isEmpty,
    );
    expect(find.text('Play · Level 1'), findsOneWidget);
    expect(find.text('Offline · playing saved levels · v${snapshot.contentVersion}'), findsOneWidget);
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

  testWidgets('Play opens the highest level and ignores a legacy replay save', (tester) async {
    final services = await _start(tester, (services) async {
      final entries = services.content.snapshot.playableEntries;
      await services.progress.recordWin(entries[0].levelId, moves: 8, timeMs: 1);
      await services.progress.recordWin(entries[1].levelId, moves: 8, timeMs: 1);
      // A save of a completed level, as older builds wrote it.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'progress.current.v2',
        '{"levelId":"${entries[0].levelId}","levelUrl":"${entries[0].ref.url}",'
        '"history":[],"moveCount":0,"elapsedMs":0}',
      );
    });
    await pumpLobby(tester, services: services, home: const HomeScreen());
    final play = find.text('Play · Level 3');
    expect(play, findsOneWidget);
    await tester.tap(play);
    await settleLobby(tester);
    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(game.entry.order, 3);
    expect(game.resume, isNull);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settleLobby(tester);
    await _leave(tester);
  });

  testWidgets('Levels and Settings open their screens and come back', (tester) async {
    final services = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());

    await tester.tap(find.text('Levels'));
    await tester.tap(find.text('Levels'), warnIfMissed: false);
    await settleLobby(tester);
    expect(find.byType(LevelSelectScreen), findsOneWidget);
    await tester.pageBack();
    await settleLobby(tester);
    expect(find.byType(LevelSelectScreen), findsNothing);

    await tester.tap(find.text('Settings'));
    await settleLobby(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Sound Effects'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
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
    expect(find.bySemanticsLabel('Levels'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Tile Park: Puzzles'), findsOneWidget);
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

    await tester.tap(find.text('Levels'));
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

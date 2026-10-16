import 'dart:async';

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/levels/level_loader.dart';
import 'package:brain_train/features/levels/level_select_screen.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../content/fixture_content.dart';
import 'lobby_support.dart';

/// The fixture content (12 small levels, starter pack 1-5) behind a server
/// the test can take offline or hold.
class _Net {
  _Net(this.content);

  final FixtureContent content;
  bool online = true;
  Completer<void>? hold;
  final List<String> log = [];

  http.Client get client => content.server(
    log: log,
    online: () => online,
    before: () async {
      final gate = hold;
      if (gate != null) await gate.future;
    },
  );
}

Future<AppServices> _services(_Net net, {Future<void> Function(ProgressRepository progress)? setup}) async {
  final progress = await ProgressRepository.open();
  await setup?.call(progress);
  final f = fixtureCoordinator(server: net.client, bundle: net.content.starter());
  final content = ContentController(f.coordinator, progress: progress, autoRetry: false);
  await content.start();
  // As a returning player: the first-play tutorial does not open.
  final settings = await SettingsRepository.open();
  await settings.setFirstPlayTutorialDone();
  return AppServices(
    content: content,
    progress: progress,
    settings: settings,
    symbolArt: SymbolArtCache(),
  );
}

Future<void> _pump(WidgetTester tester, AppServices services, Widget home) async {
  tester.view
    ..physicalSize = const Size(411 * 2.625, 914 * 2.625)
    ..devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildBrainTrainTheme(), home: home),
    ),
  );
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  final content = FixtureContent();

  // Real glyphs: the test font's square glyphs are wider than real text.
  setUpAll(loadCaptureFonts);

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

  testWidgets('a level on the device opens at once, with no loading frame', (tester) async {
    final net = _Net(content)..online = false;
    late AppServices services;
    await tester.runAsync(() async => services = await _services(net));
    final entry = services.content.snapshot.manifest.entry(content.levelId(2))!;
    expect(services.content.isReady(entry), isTrue, reason: 'the starter window is warmed up at start');
    await _pump(tester, services, LevelLoaderScreen(entry: entry));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text(kDownloadingLevelText), findsNothing);
    await _leave(tester);
  });

  testWidgets('a level not on the device: "Downloading level…", then the game', (tester) async {
    final net = _Net(content);
    late AppServices services;
    await tester.runAsync(() async => services = await _services(net));
    net.hold = Completer<void>();
    final entry = services.content.snapshot.manifest.entry(content.levelId(9))!;
    expect(services.content.isReady(entry), isFalse);
    await _pump(tester, services, LevelLoaderScreen(entry: entry));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(kDownloadingLevelText), findsOneWidget);
    expect(find.text('Glade 9'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);

    net.hold!.complete();
    for (var i = 0; i < 10 && find.byType(GameScreen).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text(kDownloadingLevelText), findsNothing);
    expect(net.log, contains(content.levelPaths[9]));
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  testWidgets('offline and not on the device: "Connect to the internet…"; Try again once online', (tester) async {
    final net = _Net(content)..online = false;
    late AppServices services;
    await tester.runAsync(() async => services = await _services(net));
    final entry = services.content.snapshot.manifest.entry(content.levelId(10))!;
    await _pump(tester, services, LevelLoaderScreen(entry: entry));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(kConnectToDownloadText), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    expect(tester.takeException(), isNull);

    net.online = true;
    await tester.tap(find.text('Try again'));
    for (var i = 0; i < 10 && find.byType(GameScreen).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(GameScreen), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a win moves the window: the next level downloads in the background', (tester) async {
    final net = _Net(content);
    late AppServices services;
    await tester.runAsync(() async {
      services = await _services(net);
      // Start: manifest only (the window 1-5 is the starter pack).
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(net.log.where((p) => p.startsWith('levels/')), isEmpty);
    await tester.runAsync(() async {
      await services.progress.recordWin(content.levelId(1), moves: 6, timeMs: 1000);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(net.log.where((p) => p.startsWith('levels/')), [content.levelPaths[6]]);
    expect(services.content.snapshot.isReady(content.levelId(6)), isTrue);
  });

  testWidgets('Play, the panel and Completed Levels read the manifest, not level files', (tester) async {
    final net = _Net(content)..online = false;
    late AppServices services;
    await tester.runAsync(() async {
      services = await _services(
        net,
        setup: (progress) async {
          for (var n = 1; n <= 7; n++) {
            await progress.recordWin(content.levelId(n), moves: 6, timeMs: 30000);
          }
        },
      );
    });
    final snapshot = services.content.snapshot;
    // Levels 6-8 were never downloaded here, yet everything about them shows.
    for (final n in [6, 7, 8]) {
      expect(snapshot.levels.containsKey(content.levelId(n)), isFalse);
    }
    expect(HomeScreen.playLabel(services), 'Play · Level 8');

    await _pump(tester, services, const LevelSelectScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Glade 8'), findsOneWidget, reason: 'the next level in the panel');
    expect(find.text('6 tiles · 5-slot tray'), findsOneWidget, reason: 'level 8 has a 5-slot tray');
    expect(find.text('7 of 12 won'), findsOneWidget);
    expect(find.text('Glade 7'), findsOneWidget, reason: 'a completed level not on this device');
    await _leave(tester);
  });

  group('resume when opened without one (the win card\'s "Next level")', () {
    Future<SavedGame> saveOneTap(AppServices services, int order) async {
      final snapshot = services.content.snapshot;
      final entry = snapshot.manifest.entry(content.levelId(order))!;
      final probe = GameController(
        entry: entry,
        level: snapshot.levels[entry.levelId]!,
        registry: snapshot.registry,
        progress: services.progress,
        settings: services.settings,
      );
      final tile = probe.state.free.first;
      probe.dispose();
      final saved = SavedGame(
        levelId: entry.levelId,
        levelUrl: entry.ref.url,
        history: [tile],
        moveCount: 1,
        elapsedMs: 12345,
      );
      await services.progress.saveGame(saved);
      return saved;
    }

    testWidgets('the highest level resumes its save', (tester) async {
      final net = _Net(content)..online = false;
      late AppServices services;
      late SavedGame saved;
      await tester.runAsync(() async {
        services = await _services(net, setup: (p) => p.recordWin(content.levelId(1), moves: 8, timeMs: 1));
        saved = await saveOneTap(services, 2);
      });
      final entry = services.content.snapshot.manifest.entry(content.levelId(2))!;
      await _pump(tester, services, LevelLoaderScreen(entry: entry));
      final resume = tester.widget<GameScreen>(find.byType(GameScreen)).resume;
      expect(resume, isNotNull);
      expect(resume!.levelId, saved.levelId);
      expect(resume.history, saved.history);
      expect(resume.moveCount, 1);
      expect(resume.elapsedMs, 12345);
      await _leave(tester);
    });

    testWidgets('a replay of a completed level starts fresh and keeps the highest save', (tester) async {
      final net = _Net(content);
      late AppServices services;
      late SavedGame saved;
      await tester.runAsync(() async {
        services = await _services(net, setup: (p) => p.recordWin(content.levelId(1), moves: 8, timeMs: 1));
        saved = await saveOneTap(services, 2);
      });
      final entry = services.content.snapshot.manifest.entry(content.levelId(1))!;
      await _pump(tester, services, LevelLoaderScreen(entry: entry));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(tester.widget<GameScreen>(find.byType(GameScreen)).resume, isNull);
      expect(services.progress.savedGame()!.history, saved.history);
      await _leave(tester);
    });
  });
}

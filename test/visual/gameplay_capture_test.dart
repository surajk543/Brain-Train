// Renders the real gameplay screen at phone sizes (the app is night-only).
//
// Always checks that layout succeeds without exceptions or overflow. When
// CAPTURE_DIR is set, also writes PNG screenshots there for visual review:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/gameplay_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/content/asset_download_manager.dart';
import 'package:brain_train/content/content_cache.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_fetcher.dart';
import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/common/flowing_leaves.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/features/gameplay/widgets/tile_flight_overlay.dart';
import 'package:brain_train/features/gameplay/widgets/tray_view.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

final String? _captureDir = Platform.environment['CAPTURE_DIR'];

typedef _Phone = ({String name, double width, double height, double dpr, double top, double bottom});

const _Phone _large = (name: '411x914', width: 411, height: 914, dpr: 2.625, top: 24, bottom: 16);
const _Phone _small = (name: '360x640', width: 360, height: 640, dpr: 2, top: 24, bottom: 0);

Future<AppServices> _services() async {
  final config = ContentConfig(baseUrl: Uri.parse('https://content.test/'), allowedHosts: const {'content.test'});
  final offline = MockClient((r) async => throw http.ClientException('offline', r.url));
  final fetcher = ContentFetcher(client: offline, config: config, delay: (_) async {});
  final cache = ContentCache(MemoryContentStore());
  final resolver = RemoteAssetResolver(config);
  final content = ContentController(
    ContentCoordinator(
      cache: cache,
      bundled: repoContent,
      downloads: AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver),
      manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
    ),
  );
  await content.start();
  return AppServices(
    content: content,
    progress: await ProgressRepository.open(),
    settings: await SettingsRepository.open(),
    symbolArt: SymbolArtCache(),
  );
}

/// Real glyphs instead of test boxes, when the system fonts exist.
Future<void> _loadFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/snap/flutter/common/flutter';
  final families = {
    'serif': [
      '/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf',
    ],
    'Roboto': [
      '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
    ],
    'MaterialIcons': ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'],
  };
  for (final MapEntry(key: family, value: paths) in families.entries) {
    final files = [for (final path in paths) File(path)].where((f) => f.existsSync()).toList();
    if (files.isEmpty) continue;
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }
}

GameEngine _engine(LevelDefinition level, SymbolRegistry registry) => GameEngine(
  level: level,
  rules: MatchRules(level: level, registry: registry),
);

/// The first [pairs] pairs of a solver solution, as a resumable game (each
/// pair played as two taps through the tray).
SavedGame _progress(ContentSnapshot snapshot, LevelManifestEntry entry, {int? pairs, int elapsedMs = 17000}) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = _engine(level, snapshot.registry);
  final solution = MahjongSolver(
    geometry: engine.geometry,
    rules: engine.rules,
  ).solve(TileMask.all(level.tiles.length)).solution;
  final history = [
    for (final (a, b) in solution.take(pairs ?? solution.length)) ...[level.tiles[a].tileId, level.tiles[b].tileId],
  ];
  return SavedGame(
    levelId: level.levelId,
    levelUrl: entry.ref.url,
    history: history,
    moveCount: history.length,
    elapsedMs: elapsedMs,
  );
}

/// A line of play that leaves the tray one tile short of full (three of
/// four, four of five), plus a free board tile that fills it without a match.
(SavedGame, String) _nearlyFull(ContentSnapshot snapshot, LevelManifestEntry entry) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = _engine(level, snapshot.registry);
  String unmatched() => (engine.state.free.toList()..sort()).firstWhere(
    (id) => !engine.state.tray.any((t) => engine.rules.matches(engine.indexOf(t)!, engine.indexOf(id)!)),
  );
  while (engine.state.tray.length < engine.trayCapacity - 1) {
    engine.tap(unmatched());
  }
  final save = SavedGame(
    levelId: level.levelId,
    levelUrl: entry.ref.url,
    history: engine.state.history,
    elapsedMs: 94000,
  );
  return (save, unmatched());
}

final _boundary = GlobalKey();

Future<void> _pumpGame(
  WidgetTester tester, {
  required AppServices services,
  required LevelManifestEntry entry,
  required _Phone phone,
  SavedGame? resume,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
    ..devicePixelRatio = phone.dpr
    ..padding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr)
    ..viewPadding = FakeViewPadding(top: phone.top * phone.dpr, bottom: phone.bottom * phone.dpr);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: AppScope(
        services: services,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildBrainTrainTheme(Brightness.dark),
          home: GameScreen(snapshot: services.content.snapshot, entry: entry, resume: resume),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Lets tile bodies, symbol art and foliage decode (real async work).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _capture(WidgetTester tester, String name, double dpr) async {
  final dir = _captureDir;
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// Top to bottom: the tray just under the status bar, the board, and the
/// HUD in the bottom part of the screen, inside the bottom safe area.
void _expectBottomHud(WidgetTester tester, _Phone phone) {
  final hud = tester.getRect(find.byType(PremiumHudFrame));
  final board = tester.getRect(find.byType(BoardView));
  final tray = tester.getRect(find.byType(TrayView));
  expect(hud.top, greaterThan(phone.height * 0.7), reason: 'HUD in the bottom part');
  expect(hud.bottom, lessThanOrEqualTo(phone.height - phone.bottom), reason: 'HUD inside the bottom safe area');
  expect(tray.top, greaterThanOrEqualTo(phone.top), reason: 'tray below the status bar');
  expect(tray.top, lessThan(phone.top + 12), reason: 'tray at the top');
  expect(tray.height, lessThan(phone.height * 0.15), reason: 'tray leaves the board its room');
  expect(board.top, greaterThanOrEqualTo(tray.bottom), reason: 'board below the tray');
  expect(board.height, greaterThan(phone.height * 0.5), reason: 'board keeps most of the screen');
  expect(board.bottom, lessThanOrEqualTo(hud.top), reason: 'board ends above the HUD');
  expect(tester.getCenter(find.byTooltip('Back')).dy, greaterThan(hud.top));
}

/// Taps [tileId] on the board of a game resumed from [history].
Future<void> _tapTile(
  WidgetTester tester,
  ContentSnapshot snapshot,
  LevelManifestEntry entry,
  List<String> history,
  String tileId,
) async {
  final level = snapshot.levels[entry.levelId]!;
  final engine = _engine(level, snapshot.registry)..replay(history);
  final board = tester.getRect(find.byType(BoardView));
  final projection = boardProjectionFor(level, engine.geometry, TileStyle.forTileSet(level.tileSetId), board.size);
  final face = projection.faceRect(engine.indexOf(tileId)!);
  await tester.tapAt(board.topLeft + Offset(face.centerX, face.centerY));
}

/// The tile [tileId] is drawn in the tray.
Finder _inTray(String tileId) => find.descendant(of: find.byType(TrayView), matching: find.byKey(ValueKey(tileId)));

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  late AppServices services;
  late ContentSnapshot snapshot;
  late LevelManifestEntry meadow;
  int pairsOf(LevelManifestEntry entry) => snapshot.levels[entry.levelId]!.pairCount;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async {
      services = await _services();
      snapshot = services.content.snapshot;
      // A medium level: 4-slot tray, enough distinct symbols to fill it.
      meadow = snapshot.playableEntries.firstWhere((e) => e.difficulty == 'medium');
    });
  }

  for (final phone in [_large, _small]) {
    testWidgets('gameplay ${phone.name}', (tester) async {
      await start(tester);
      await _pumpGame(
        tester,
        services: services,
        entry: meadow,
        phone: phone,
        resume: _progress(snapshot, meadow, pairs: 2),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(meadow.title), findsOneWidget);
      expect(find.text('Level ${meadow.order}'), findsOneWidget);
      expect(find.text('2/${pairsOf(meadow)}'), findsOneWidget);
      expect(find.text('Restart'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byType(FlowingLeaves), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing, reason: 'the tray is frosted from the static backdrop');
      _expectBottomHud(tester, phone);
      expect(find.text('Hint'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      await _capture(tester, 'gameplay_night_${phone.name}', phone.dpr);
      await _leave(tester);
    });
  }

  testWidgets('a tapped tile flies from the board into the tray', (tester) async {
    await start(tester);
    final saved = _progress(snapshot, meadow, pairs: 2);
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: saved);
    final level = snapshot.levels[meadow.levelId]!;
    final engine = _engine(level, snapshot.registry)..replay(saved.history);
    // The free tile drawn last (topmost) is the clearest to tap.
    final index = engine.geometry.drawOrder.lastWhere((i) => engine.isRemaining(i) && engine.isFreeIndex(i));
    final id = level.tiles[index].tileId;
    await _tapTile(tester, snapshot, meadow, saved.history, id);
    await tester.pump();
    expect(
      find.bySemanticsLabel('Mahjong board, ${engine.state.remaining.length - 1} tiles remaining'),
      findsOneWidget,
      reason: 'the tile leaves the board at once',
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(_inTray(id), findsNothing, reason: 'still in the air');
    await _capture(tester, 'gameplay_night_411x914_flight', _large.dpr);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_inTray(id), findsOneWidget, reason: 'landed in slot 1');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Tray, 1 of 4 tiles'), findsOneWidget);
    expect(find.text('2/${pairsOf(meadow)}'), findsOneWidget);
    expect(find.text('5'), findsOneWidget, reason: 'one move per tap');
    await _capture(tester, 'gameplay_night_411x914_tray1', _large.dpr);
    await _leave(tester);
  });

  for (final phone in [_large, _small]) {
    testWidgets('a matching pair strikes and shatters in the tray ${phone.name}', (tester) async {
      await start(tester);
      final saved = _progress(snapshot, meadow, pairs: 2);
      await _pumpGame(tester, services: services, entry: meadow, phone: phone, resume: saved);
      final level = snapshot.levels[meadow.levelId]!;
      final engine = _engine(level, snapshot.registry);
      final (a, b) = MahjongSolver(
        geometry: engine.geometry,
        rules: engine.rules,
      ).solve(TileMask.all(level.tiles.length)).solution[2];
      final first = level.tiles[a].tileId, second = level.tiles[b].tileId;
      await _tapTile(tester, snapshot, meadow, saved.history, first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_inTray(first), findsOneWidget);
      await _tapTile(tester, snapshot, meadow, [...saved.history, first], second);
      await tester.pump();
      // The second tile lands next to its partner; then the strike begins.
      await tester.pump(kTileFlightDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_inTray(first), findsNothing, reason: 'the shatter overlay draws the pair now');
      await tester.pump(const Duration(milliseconds: 90));
      await _capture(tester, 'gameplay_night_${phone.name}_strike_1_prehit', phone.dpr);
      await tester.pump(const Duration(milliseconds: 130));
      await _capture(tester, 'gameplay_night_${phone.name}_strike_2_impact', phone.dpr);
      await tester.pump(const Duration(milliseconds: 200));
      await _capture(tester, 'gameplay_night_${phone.name}_strike_3_shatter', phone.dpr);
      await _settle(tester);
      expect(_inTray(first), findsNothing);
      expect(_inTray(second), findsNothing);
      expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
      expect(find.text('3/${pairsOf(meadow)}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_${phone.name}_strike_4_after', phone.dpr);
      await _leave(tester);
    });
  }

  testWidgets('taps during a strike keep working; the tray catches up', (tester) async {
    await start(tester);
    final saved = _progress(snapshot, meadow, pairs: 2);
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: saved);
    final level = snapshot.levels[meadow.levelId]!;
    final engine = _engine(level, snapshot.registry)..replay(saved.history);
    final (a, b) = MahjongSolver(
      geometry: engine.geometry,
      rules: engine.rules,
    ).solve(TileMask.all(level.tiles.length)).solution[2];
    final first = level.tiles[a].tileId, second = level.tiles[b].tileId;
    engine
      ..tap(first)
      ..tap(second);
    // Any other free tile, tapped while the pair strikes.
    final third = (engine.state.free.toList()..sort()).first;
    await _tapTile(tester, snapshot, meadow, saved.history, first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _tapTile(tester, snapshot, meadow, [...saved.history, first], second);
    await tester.pump();
    await tester.pump(kTileFlightDuration + const Duration(milliseconds: 100));
    await _tapTile(tester, snapshot, meadow, engine.state.history, third);
    await _settle(tester);
    expect(_inTray(third), findsOneWidget);
    expect(find.bySemanticsLabel('Tray, 1 of 4 tiles'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  for (final phone in [_large, _small]) {
    testWidgets('a tray holding three tiles ${phone.name}', (tester) async {
      await start(tester);
      final (save, _) = _nearlyFull(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: phone, resume: save);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Tray, 3 of 4 tiles'), findsOneWidget);
      final engine = _engine(snapshot.levels[meadow.levelId]!, snapshot.registry)..replay(save.history);
      for (final id in engine.state.tray) {
        expect(_inTray(id), findsOneWidget);
      }
      _expectBottomHud(tester, phone);
      await _capture(tester, 'gameplay_night_${phone.name}_tray3', phone.dpr);
      await _leave(tester);
    });
  }

  testWidgets('narrow phone with large text: no overflow', (tester) async {
    await start(tester);
    final longTitle = LevelManifestEntry(
      levelId: meadow.levelId,
      order: 128,
      title: 'The Very Long Winding Meadow Path',
      ref: meadow.ref,
    );
    await _pumpGame(
      tester,
      services: services,
      entry: longTitle,
      phone: _small,
      textScale: 1.3,
      resume: _progress(snapshot, meadow, pairs: 12, elapsedMs: 3723000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('12/${pairsOf(meadow)}'), findsOneWidget);
    _expectBottomHud(tester, _small);
    await _capture(tester, 'gameplay_night_360x640_text130', _small.dpr);
    await _leave(tester);
  });

  testWidgets('no Restart pill; the HUD is a bottom bar below the board', (tester) async {
    await start(tester);
    await _pumpGame(
      tester,
      services: services,
      entry: meadow,
      phone: _large,
      resume: _progress(snapshot, meadow, pairs: 3),
    );
    expect(find.text('3/${pairsOf(meadow)}'), findsOneWidget);
    expect(find.text('Restart'), findsNothing);
    expect(find.bySemanticsLabel('Restart level'), findsNothing);
    expect(find.text('Restart level?'), findsNothing);
    _expectBottomHud(tester, _large);
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  testWidgets('win overlay', (tester) async {
    await start(tester);
    await _pumpGame(
      tester,
      services: services,
      entry: meadow,
      phone: _large,
      resume: _progress(snapshot, meadow, elapsedMs: 83000),
    );
    expect(find.text('Level complete!'), findsOneWidget);
    expect(find.text('Next level'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('All levels'), findsOneWidget);
    // The result card sits over the board and leaves the HUD uncovered.
    _expectBottomHud(tester, _large);
    expect(tester.getRect(find.text('All levels')).bottom, lessThan(tester.getRect(find.byType(PremiumHudFrame)).top));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'gameplay_night_411x914_win', _large.dpr);
    await _leave(tester);
  });

  for (final (phone, textScale) in [(_small, 1.3), (_large, 1.0)]) {
    testWidgets('tray-full overlay ${phone.name} at ${textScale}x text', (tester) async {
      await start(tester);
      final (save, last) = _nearlyFull(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: phone, textScale: textScale, resume: save);
      // The fourth unmatched tile fills the tray: game over.
      await _tapTile(tester, snapshot, meadow, save.history, last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tray full'), findsNothing, reason: 'the tray shakes first');
      expect(find.bySemanticsLabel('Tray full'), findsOneWidget);
      await _capture(tester, 'gameplay_night_${phone.name}_tray_full_shake', phone.dpr);
      await _settle(tester);
      expect(find.text('Tray full'), findsOneWidget);
      // Exactly two choices; Back stays in the HUD.
      expect(find.text('Revive'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
      expect(find.text('All levels'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      _expectBottomHud(tester, phone);
      expect(tester.getRect(find.text('Restart')).bottom, lessThan(tester.getRect(find.byType(PremiumHudFrame)).top));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_${phone.name}_tray_full', phone.dpr);
      // Restart: empty tray, card gone.
      await tester.tap(find.text('Restart'));
      await _settle(tester);
      expect(find.text('Tray full'), findsNothing);
      expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
      expect(find.text('0/${pairsOf(meadow)}'), findsOneWidget);
      await _leave(tester);
    });
  }

  testWidgets('revive flies the tray tiles back to the board', (tester) async {
    await start(tester);
    final (save, last) = _nearlyFull(snapshot, meadow);
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: save);
    final level = snapshot.levels[meadow.levelId]!;
    final engine = _engine(level, snapshot.registry)..replay([...save.history, last]);
    final trayTiles = engine.state.tray;
    final onBoard = engine.state.remaining.length;
    await _tapTile(tester, snapshot, meadow, save.history, last);
    await _settle(tester);
    expect(find.text('Revive'), findsOneWidget);
    await tester.tap(find.text('Revive'));
    await tester.pump();
    expect(find.text('Tray full'), findsNothing, reason: 'the card goes at once');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-way: some tiles in the air, the board not yet showing them.
    expect(find.bySemanticsLabel('Mahjong board, ${onBoard + 4} tiles remaining'), findsOneWidget);
    await _capture(tester, 'gameplay_night_411x914_revive_flight', _large.dpr);
    await _settle(tester);
    for (final id in trayTiles) {
      expect(_inTray(id), findsNothing);
    }
    expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
    expect(find.text('4'), findsOneWidget, reason: 'a revive is not a move');
    expect(tester.takeException(), isNull);
    await _capture(tester, 'gameplay_night_411x914_revived', _large.dpr);
    // Play goes on: a returned tile can be tapped again.
    final free = engine..revive();
    final again = trayTiles.firstWhere((id) => free.isFreeIndex(free.indexOf(id)!));
    await _tapTile(tester, snapshot, meadow, free.state.history, again);
    await _settle(tester);
    expect(_inTray(again), findsOneWidget);
    await _leave(tester);
  });

  // One board per tier, the largest of each, at both phone sizes.
  for (final tier in ['easy', 'medium', 'hard', 'veryHard']) {
    for (final phone in [_small, _large]) {
      testWidgets('largest $tier board fits ${phone.name}', (tester) async {
        await start(tester);
        final entry = snapshot.playableEntries
            .where((e) => e.difficulty == tier)
            .reduce((a, b) => (a.tileCount ?? 0) >= (b.tileCount ?? 0) ? a : b);
        final level = snapshot.levels[entry.levelId]!;
        await _pumpGame(tester, services: services, entry: entry, phone: phone);
        // Big boards decode many symbols: give the art more time.
        for (var i = 0; i < 4; i++) {
          await _settle(tester);
        }
        expect(tester.takeException(), isNull);
        expect(find.text('0/${level.pairCount}'), findsOneWidget);
        final capacity = tier == 'hard' || tier == 'veryHard' ? 5 : 4;
        expect(find.bySemanticsLabel('Tray, 0 of $capacity tiles'), findsOneWidget);
        _expectBottomHud(tester, phone);
        // Tiles stay big enough to tap.
        final board = tester.getRect(find.byType(BoardView));
        final projection = boardProjectionFor(
          level,
          _engine(level, snapshot.registry).geometry,
          TileStyle.forTileSet(level.tileSetId),
          board.size,
        );
        expect(projection.faceWidth, greaterThanOrEqualTo(30), reason: '${entry.levelId}: ${level.tiles.length} tiles');
        await _capture(tester, 'tier_${tier}_${phone.name}_${entry.levelId}', phone.dpr);
        await _leave(tester);
      });
    }
  }

  // The 5-slot tray of hard and very hard levels.
  for (final (phone, textScale) in [(_small, 1.3), (_large, 1.0)]) {
    testWidgets('5-slot tray ${phone.name}: empty, four held, full', (tester) async {
      await start(tester);
      final entry = snapshot.playableEntries.firstWhere((e) => e.difficulty == 'hard');
      final level = snapshot.levels[entry.levelId]!;
      expect(level.rules.trayCapacity, 5);

      await _pumpGame(tester, services: services, entry: entry, phone: phone, textScale: textScale);
      expect(find.bySemanticsLabel('Tray, 0 of 5 tiles'), findsOneWidget);
      final tray = tester.getRect(find.byType(TrayView));
      expect(tray.left, greaterThanOrEqualTo(0));
      expect(tray.right, lessThanOrEqualTo(phone.width));
      _expectBottomHud(tester, phone);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'tray5_${phone.name}_empty', phone.dpr);
      await _leave(tester);

      final (save, last) = _nearlyFull(snapshot, entry);
      await _pumpGame(tester, services: services, entry: entry, phone: phone, textScale: textScale, resume: save);
      expect(find.bySemanticsLabel('Tray, 4 of 5 tiles'), findsOneWidget);
      final engine = _engine(level, snapshot.registry)..replay(save.history);
      final wells = <Rect>[for (final id in engine.state.tray) tester.getRect(_inTray(id))];
      expect(wells, hasLength(4));
      for (var i = 1; i < wells.length; i++) {
        expect(wells[i].left, greaterThan(wells[i - 1].right - 0.5), reason: 'slots do not overlap');
      }
      expect(wells.first.left, greaterThanOrEqualTo(0));
      _expectBottomHud(tester, phone);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'tray5_${phone.name}_four', phone.dpr);

      // The fifth unmatched tile fills the tray: game over.
      await _tapTile(tester, snapshot, entry, save.history, last);
      await _settle(tester);
      expect(find.text('Tray full'), findsOneWidget);
      expect(find.text('Revive'), findsOneWidget);
      expect(find.bySemanticsLabel('Tray full'), findsWidgets);
      _expectBottomHud(tester, phone);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'tray5_${phone.name}_full', phone.dpr);

      // Revive brings all five back.
      await tester.tap(find.text('Revive'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Tray, 0 of 5 tiles'), findsOneWidget);
      expect(
        // The engine above still holds four in the tray and the fifth on the board.
        find.bySemanticsLabel('Mahjong board, ${engine.state.remaining.length + 4} tiles remaining'),
        findsOneWidget,
        reason: 'the four held tiles and the fifth are back on the board',
      );
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });
  }
}

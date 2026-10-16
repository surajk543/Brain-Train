// Renders the real gameplay screen at phone sizes (the app is night-only).
//
// Always checks that layout succeeds without exceptions or overflow. When
// CAPTURE_DIR is set, also writes PNG screenshots there for visual review:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/gameplay_capture_test.dart
import 'dart:io';
import 'dart:math' as math;
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
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/common/flowing_leaves.dart';
import 'package:brain_train/features/gameplay/game_screen.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/widgets/board_intro.dart';
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

/// The full generated tree (gitignored; present where `dart run
/// tool/content.dart build` ran). Tests of levels beyond the starter pack
/// (very hard boards, every intro style) use it, and skip without it.
final bool _hasFullTree = File('content/brain-train/manifest.json').existsSync();
final BundledContentSource _fullTree = BundledContentSource((key) async {
  final file = File(key);
  return file.existsSync() ? file.readAsBytesSync() : null;
}, prefix: 'content/brain-train/');

/// Offline services on the starter pack (levels 1-5), or on every level
/// with [full].
Future<AppServices> _services({bool full = false}) async {
  final config = ContentConfig(baseUrl: Uri.parse('https://content.test/'), allowedHosts: const {'content.test'});
  final offline = MockClient((r) async => throw http.ClientException('offline', r.url));
  final fetcher = ContentFetcher(client: offline, config: config, delay: (_) async {});
  final cache = ContentCache(MemoryContentStore());
  final resolver = RemoteAssetResolver(config);
  final content = ContentController(
    ContentCoordinator(
      cache: cache,
      bundled: full ? _fullTree : repoContent,
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
  _IntroWait intro = _IntroWait.finish,
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
  if (intro == _IntroWait.start) {
    // Stop as soon as the intro's first frame is drawn.
    for (var i = 0; i < 80 && !_introOf(tester).isRunning; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    return;
  }
  await _settle(tester);
  if (intro == _IntroWait.finish) await _finishIntro(tester);
}

enum _IntroWait {
  /// Return once the board intro has handed over (most tests).
  finish,

  /// Return right after the intro starts.
  start,

  /// Just settle (there may be no intro).
  none,
}

/// The game screen's board intro.
BoardIntroController _introOf(WidgetTester tester) =>
    tester.widget<BoardIntroOverlay>(find.byType(BoardIntroOverlay)).controller;

/// The game screen's controller (through its board).
GameController _gameOf(WidgetTester tester) => tester.widget<BoardView>(find.byType(BoardView)).controller;

/// Pumps until the board intro has handed over to the board (big boards
/// may still be decoding their art, which needs real time).
Future<void> _finishIntro(WidgetTester tester) async {
  for (var i = 0; i < 80 && (_introOf(tester).isRunning || _gameOf(tester).introPlaying); i++) {
    if (!_introOf(tester).isRunning) await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(_gameOf(tester).introPlaying, isFalse, reason: 'the intro handed over');
  await tester.pump();
}

/// Pumps the running intro to [seconds] after its first frame.
Future<void> _introTo(WidgetTester tester, double seconds) async {
  final intro = _introOf(tester).intro;
  if (intro == null) return;
  final step = ((seconds - intro.seconds) * 1000000).round();
  if (step > 0) await tester.pump(Duration(microseconds: step));
}

/// Lets tile bodies, symbol art and foliage decode (real async work).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _capture(WidgetTester tester, String name, double dpr, {List<ui.Image>? keep}) async {
  final dir = _captureDir;
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: dpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (keep != null) {
      keep.add(image);
    } else {
      image.dispose();
    }
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// Writes [rows] of frames side by side, scaled down, as one PNG.
Future<void> _writeSheet(WidgetTester tester, String name, List<List<ui.Image>> rows) async {
  final dir = _captureDir;
  if (dir == null || rows.every((r) => r.isEmpty)) return;
  await tester.runAsync(() async {
    const scale = 0.32, gap = 12.0;
    final cellWidth = rows.expand((r) => r).map((i) => i.width * scale).reduce(math.max);
    final cellHeight = rows.expand((r) => r).map((i) => i.height * scale).reduce(math.max);
    final columns = rows.map((r) => r.length).reduce(math.max);
    final width = (columns * (cellWidth + gap) + gap).ceil(), height = (rows.length * (cellHeight + gap) + gap).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFF101410));
    for (final (r, row) in rows.indexed) {
      for (final (c, image) in row.indexed) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(gap + c * (cellWidth + gap), gap + r * (cellHeight + gap), image.width * scale, image.height * scale),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
    final picture = recorder.endRecording();
    final sheet = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
    sheet.dispose();
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  for (final image in rows.expand((r) => r)) {
    image.dispose();
  }
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

  Future<void> start(WidgetTester tester, {bool full = false}) async {
    await tester.runAsync(() async {
      services = await _services(full: full);
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
    expect(find.text('Completed Levels'), findsOneWidget);
    // The result card sits over the board and leaves the HUD uncovered.
    _expectBottomHud(tester, _large);
    expect(tester.getRect(find.text('Completed Levels')).bottom, lessThan(tester.getRect(find.byType(PremiumHudFrame)).top));
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
      expect(find.text('Completed Levels'), findsNothing);
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
    expect(_gameOf(tester).introPlaying, isFalse, reason: 'a revive does not replay the intro');
    expect(_introOf(tester).isRunning, isFalse);
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
      testWidgets('largest $tier board fits ${phone.name}', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
        await start(tester, full: true);
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

  group('board intro', () {
    LevelManifestEntry firstOf(String difficulty) =>
        snapshot.playableEntries.firstWhere((e) => e.difficulty == difficulty);

    /// Replays the intro from its start (everything already decoded) and
    /// captures it at 10, 30, 50, 70 and 90% of its length (0.2 ... 1.8 s
    /// for a 2 s intro) and after the hand-over at its end.
    Future<List<ui.Image>> sequence(WidgetTester tester, String name) async {
      final frames = <ui.Image>[];
      _gameOf(tester).restart();
      await tester.pump();
      await tester.pump();
      expect(_introOf(tester).isRunning, isTrue);
      final intro = _introOf(tester).intro!;
      expect(intro.seconds, 0);
      final total = intro.choreography.total;
      for (final f in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        await _introTo(tester, total * f);
        expect(tester.takeException(), isNull);
        await _capture(tester, '${name}_t${(total * f).toStringAsFixed(1)}', _large.dpr, keep: frames);
      }
      await _introTo(tester, total);
      await tester.pump();
      expect(_introOf(tester).isRunning, isFalse, reason: 'handed over to the board');
      expect(_gameOf(tester).introPlaying, isFalse);
      await _capture(tester, '${name}_t${total.toStringAsFixed(1)}', _large.dpr, keep: frames);
      return frames;
    }

    testWidgets('a contact sheet per mix style, on hard and very hard boards', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
      await start(tester, full: true);
      for (final style in IntroStyle.values) {
        final entry = snapshot.playableEntries.firstWhere(
          (e) => (e.difficulty == 'hard' || e.difficulty == 'veryHard') && IntroStyle.forLevel(e.levelId) == style,
        );
        await _pumpGame(tester, services: services, entry: entry, phone: _large);
        expect(_introOf(tester).isRunning, isFalse);
        final frames = await sequence(tester, 'intro_${style.name}_${entry.levelId}_411x914');
        await _writeSheet(tester, 'intro_sheet_${style.name}', [frames]);
        await _leave(tester);
      }
    });

    testWidgets('the clock starts after the tier\'s intro: 2.6 s on a hard board', (tester) async {
      await start(tester);
      final hard = firstOf('hard');
      await _pumpGame(tester, services: services, entry: hard, phone: _large);
      final game = _gameOf(tester);
      game.restart();
      await tester.pump();
      await tester.pump();
      expect(_introOf(tester).intro!.choreography.total, 2.6);
      await _introTo(tester, 2.5);
      expect(game.introPlaying, isTrue, reason: 'longer than an easy intro');
      expect(game.elapsed, Duration.zero);
      await _introTo(tester, 2.6);
      await tester.pump();
      expect(game.introPlaying, isFalse);
      // The clock is a real stopwatch: give it real time.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      expect(game.elapsed, greaterThan(Duration.zero), reason: 'running now');
      await _leave(tester);
    });

    testWidgets('frame sequence at 411x914: a very hard level and an easy one', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
      await start(tester, full: true);
      final hard = firstOf('veryHard');
      await _pumpGame(tester, services: services, entry: hard, phone: _large);
      expect(snapshot.levels[hard.levelId]!.tiles.length, greaterThan(140));
      final hardFrames = await sequence(tester, 'intro_${hard.levelId}_411x914');
      await _leave(tester);
      final easy = firstOf('easy');
      await _pumpGame(tester, services: services, entry: easy, phone: _large);
      final easyFrames = await sequence(tester, 'intro_${easy.levelId}_411x914');
      await _writeSheet(tester, 'intro_sheet', [hardFrames, easyFrames]);
      await _leave(tester);
    });

    testWidgets('taps wait for the intro, the clock starts after it, a restart replays it', (tester) async {
      await start(tester);
      await _pumpGame(tester, services: services, entry: meadow, phone: _large);
      final game = _gameOf(tester);
      game.restart();
      await tester.pump();
      await tester.pump();
      final level = snapshot.levels[meadow.levelId]!;
      final engine = _engine(level, snapshot.registry);
      final id = (engine.state.free.toList()..sort()).first;
      await _introTo(tester, 1.0);
      expect(game.elapsed, Duration.zero, reason: 'the intro is not play time');
      await _tapTile(tester, snapshot, meadow, const [], id);
      await tester.pump();
      expect(game.state.moveCount, 0, reason: 'taps are ignored during the intro');
      expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
      // A restart mid-intro starts it again.
      final serial = game.introSerial;
      game.restart();
      await tester.pump();
      await tester.pump();
      expect(game.introSerial, isNot(serial));
      expect(_introOf(tester).intro!.seconds, 0);
      await _introTo(tester, _introOf(tester).intro!.choreography.total);
      await tester.pump();
      expect(game.introPlaying, isFalse);
      await _tapTile(tester, snapshot, meadow, const [], id);
      await _settle(tester);
      expect(_inTray(id), findsOneWidget, reason: 'play is on after the intro');
      expect(game.elapsed, greaterThan(Duration.zero));
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('a resumed game: only board tiles fly, the tray shows its tiles at once', (tester) async {
      await start(tester);
      final (save, _) = _nearlyFull(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: save, intro: _IntroWait.start);
      final game = _gameOf(tester);
      final intro = _introOf(tester).intro!;
      expect(intro.tiles.length, game.state.remaining.length);
      expect(intro.tiles.toSet().intersection({for (final id in game.state.tray) game.engine.indexOf(id)!}), isEmpty);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (final id in game.state.tray) {
        expect(_inTray(id), findsOneWidget, reason: 'restored tray tiles just appear');
      }
      expect(game.elapsed, Duration(milliseconds: save.elapsedMs), reason: 'held at the saved time');
      await _finishIntro(tester);
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('leaving during the intro frees it cleanly', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
      await start(tester, full: true);
      await _pumpGame(tester, services: services, entry: firstOf('veryHard'), phone: _large, intro: _IntroWait.start);
      final intro = _introOf(tester).intro!;
      await _introTo(tester, 0.5);
      await _leave(tester);
      expect(intro.isDisposed, isTrue);
      expect(intro.atlas.image.debugDisposed, isTrue);
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('with reduced motion there is no intro', (tester) async {
      await start(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpGame(tester, services: services, entry: meadow, phone: _large, intro: _IntroWait.none);
      final game = _gameOf(tester);
      expect(game.introPlaying, isFalse);
      expect(_introOf(tester).isRunning, isFalse);
      final level = snapshot.levels[meadow.levelId]!;
      final id = (_engine(level, snapshot.registry).state.free.toList()..sort()).first;
      await _tapTile(tester, snapshot, meadow, const [], id);
      await _settle(tester);
      expect(_inTray(id), findsOneWidget);
      await _leave(tester);
    });
  });
}

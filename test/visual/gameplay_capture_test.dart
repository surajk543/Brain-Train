// Renders the real gameplay screen at phone sizes (Night; both looks and the
// redesigned cards: gameplay_redesign_capture_test.dart).
//
// Always checks that layout succeeds without exceptions or overflow. When
// CAPTURE_DIR is set, also writes PNG screenshots there for visual review:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/gameplay_capture_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
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
import 'package:brain_train/features/gameplay/widgets/board_intro.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/first_play_tutorial.dart';
import 'package:brain_train/features/gameplay/widgets/action_bar.dart';
import 'package:brain_train/features/gameplay/widgets/game_hud.dart';
import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/features/gameplay/widgets/tile_flight_overlay.dart';
import 'package:brain_train/features/gameplay/widgets/score_popups.dart';
import 'package:brain_train/features/gameplay/widgets/tray_view.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
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
import '../helpers/fake_stopwatch.dart';
import '../platform/fake_rewarded_ads.dart';
import 'gameplay_support.dart';
import 'package:brain_train/app/tablet_scale.dart';

final String? _captureDir = Platform.environment['CAPTURE_DIR'];

typedef _Phone = ({String name, double width, double height, double dpr, double top, double bottom});

const _Phone _large = (name: '411x914', width: 411, height: 914, dpr: 2.625, top: 24, bottom: 16);
const _Phone _small = (name: '360x640', width: 360, height: 640, dpr: 2, top: 24, bottom: 0);
const _Phone _ipad = (name: 'ipad-13', width: 1032, height: 1376, dpr: 2, top: 24, bottom: 20);
const _Phone _iphone = (name: '393x852', width: 393, height: 852, dpr: 3, top: 59, bottom: 34);

/// The full generated tree (gitignored; present where `dart run
/// tool/content.dart build` ran). Tests of levels beyond the starter pack
/// (very hard boards, every intro style) use it, and skip without it.
final bool _hasFullTree = File('content/brain-train/manifest.json').existsSync();
final BundledContentSource _fullTree = BundledContentSource((key) async {
  final file = File(key);
  return file.existsSync() ? file.readAsBytesSync() : null;
}, prefix: '$_treeRoot/');

/// `PREVIEW_TREE=<content root>` (with CAPTURE_DIR) captures every level of
/// that tree, or the PREVIEW_LEVELS=level-0001,... among them, at 393x852
/// and 360x640, or the PREVIEW_PHONES=393x852,360x640,ipad-13 given ("board
/// previews"); the full tree's tests then read it instead of
/// content/brain-train.
final String? _previewTree = Platform.environment['PREVIEW_TREE'];
final String _treeRoot = _previewTree ?? 'content/brain-train';

/// Offline services on the starter pack (levels 1-5), or on every level
/// with [full]. Games open as for a returning player (the first-play
/// tutorial done) unless [tutorialDone] is false.
Future<AppServices> _services({bool full = false, RewardedAds? ads, bool tutorialDone = true}) async {
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
  final settings = await SettingsRepository.open();
  if (tutorialDone) await settings.setFirstPlayTutorialDone();
  return AppServices(
    content: content,
    progress: await ProgressRepository.open(),
    settings: settings,
    symbolArt: SymbolArtCache(),
    ads: ads == null ? null : RewardedAdsController(ads),
  );
}

/// Real glyphs instead of test boxes: the bundled fonts, and system fonts
/// for the platform fallbacks when they exist.
Future<void> _loadFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/snap/flutter/common/flutter';
  final families = {
    'Playfair Display': [
      'assets/fonts/playfair_display/PlayfairDisplay-VariableFont_wght.ttf',
    ],
    'Manrope': ['assets/fonts/manrope/Manrope-VariableFont_wght.ttf'],
    'serif': [
      '/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSerif-Bold.ttf',
      '/System/Library/Fonts/Supplemental/Georgia.ttf',
      '/System/Library/Fonts/Supplemental/Georgia Bold.ttf',
    ],
    'Roboto': [
      '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
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

final _boundary = GlobalKey();

Future<void> _pumpGame(
  WidgetTester tester, {
  required AppServices services,
  required LevelManifestEntry entry,
  required _Phone phone,
  SavedGame? resume,
  double textScale = 1,
  _IntroWait intro = _IntroWait.finish,
  Stopwatch? stopwatch,
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
          theme: buildBrainTrainTheme(),
          builder: (context, child) => TabletScale(child: child!),
          home: GameScreen(snapshot: services.content.snapshot, entry: entry, resume: resume, stopwatch: stopwatch),
        ),
      ),
    ),
  );
  if (intro == _IntroWait.start) {
    // Stop as soon as the intro's first frame is drawn.
    for (var i = 0; i < 80 && !introOf(tester).isRunning; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    return;
  }
  await _settle(tester);
  if (intro == _IntroWait.finish) await finishIntro(tester);
}

enum _IntroWait {
  /// Return once the board intro has handed over (most tests).
  finish,

  /// Return right after the intro starts.
  start,

  /// Just settle (there may be no intro).
  none,
}

/// Pumps the running intro to [seconds] after its first frame.
Future<void> _introTo(WidgetTester tester, double seconds) async {
  final intro = introOf(tester).intro;
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

/// Top to bottom (redesign 1.1.0): the HUD just under the status bar, the
/// tray, the board and the action bar inside the bottom safe area.
void _expectLayout(WidgetTester tester, _Phone phone) {
  final hud = tester.getRect(find.byType(GameHud));
  final board = tester.getRect(find.byType(BoardView));
  final tray = tester.getRect(find.byType(TrayView));
  final bar = tester.getRect(find.byType(GameActionBar));
  expect(hud.top, greaterThanOrEqualTo(phone.top), reason: 'HUD below the status bar');
  expect(hud.top, lessThan(phone.top + 12), reason: 'HUD at the top');
  expect(tray.top, greaterThan(hud.bottom), reason: 'tray under the HUD (and the combo timer)');
  expect(tray.height, lessThan(phone.height * 0.15), reason: 'tray leaves the board its room');
  expect(board.top, greaterThanOrEqualTo(tray.bottom), reason: 'board below the tray');
  expect(board.height, greaterThan(phone.height * 0.5), reason: 'board keeps most of the screen');
  expect(bar.top, greaterThanOrEqualTo(board.bottom), reason: 'action bar below the board');
  expect(bar.bottom, lessThanOrEqualTo(phone.height - phone.bottom), reason: 'action bar inside the bottom safe area');
  expect(bar.top, greaterThan(phone.height * 0.8), reason: 'action bar at the bottom');
  expect(tester.getCenter(find.byTooltip('Back')).dy, lessThan(hud.bottom));
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

  Future<void> start(WidgetTester tester, {bool full = false, RewardedAds? ads}) async {
    await tester.runAsync(() async {
      services = await _services(full: full, ads: ads);
      snapshot = services.content.snapshot;
      // A difficulty-4 level: 4-slot tray, enough distinct symbols to fill it.
      meadow = snapshot.playableEntries.firstWhere((e) => e.difficulty == '4', orElse: () => snapshot.playableEntries.first);
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
        resume: solvedSave(snapshot, meadow, pairs: 2),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(meadow.title), findsOneWidget);
      expect(find.text('Level ${meadow.order}'), findsOneWidget);
      expect(find.text('2/${pairsOf(meadow)}'), findsOneWidget);
      expect(find.text('Restart'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byType(FlowingLeaves), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing, reason: 'the tray is frosted from the static backdrop');
      _expectLayout(tester, phone);
      // The action bar (owner, 1.1.0).
      expect(find.text('Hint'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      await _capture(tester, 'gameplay_night_${phone.name}', phone.dpr);
      await _leave(tester);
    });
  }

  testWidgets('a x3 combo badge floats on the tray edge, with a score popup', (tester) async {
    await start(tester);
    final clock = FakeStopwatch();
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, stopwatch: clock);
    final game = gameOf(tester);
    final level = snapshot.levels[meadow.levelId]!;
    final solution = MahjongSolver(
      geometry: game.engine.geometry,
      rules: game.engine.rules,
    ).solve(TileMask.all(level.tiles.length)).solution;
    for (final (a, b) in solution.take(3)) {
      game
        ..tapTile(level.tiles[a].tileId)
        ..tapTile(level.tiles[b].tileId);
      clock.advance(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.activeCombo, 3);
    final popups = tester.state<ScorePopupOverlayState>(find.byType(ScorePopupOverlay));
    for (var i = 0; i < 80 && popups.popupCount == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('COMBO ×3 · Best ×3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'gameplay_night_411x914_combo_popup', _large.dpr);
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(popups.popupCount, 0);
    expect(find.text('COMBO ×3 · Best ×3'), findsOneWidget, reason: 'the fake clock keeps the window open');
    await _capture(tester, 'gameplay_night_411x914_combo', _large.dpr);
    await _leave(tester);
  });

  testWidgets('a x2 combo on a 5-well board at 360x640: Best shows above the tiles', (tester) async {
    await start(tester);
    final clock = FakeStopwatch();
    final entry = snapshot.playableEntries.firstWhere((e) => e.trayCapacity == 5 && e.difficulty == '2');
    final level = snapshot.levels[entry.levelId]!;
    await _pumpGame(tester, services: services, entry: entry, phone: _small, stopwatch: clock);
    final game = gameOf(tester);
    final solution = MahjongSolver(
      geometry: game.engine.geometry,
      rules: game.engine.rules,
    ).solve(TileMask.all(level.tiles.length)).solution;
    for (final (a, b) in solution.take(2)) {
      game
        ..tapTile(level.tiles[a].tileId)
        ..tapTile(level.tiles[b].tileId);
      clock.advance(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.activeCombo, 2);
    // During a combo, Best is inline in the pill (no separate chip).
    expect(find.text('COMBO ×2 · Best ×2'), findsOneWidget);
    expect(find.text('Best ×2'), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'gameplay_night_360x640_hard_combo', _small.dpr);
    await _leave(tester);
  });

  testWidgets('a tapped tile flies from the board into the tray', (tester) async {
    await start(tester);
    final saved = solvedSave(snapshot, meadow, pairs: 2);
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: saved);
    final level = snapshot.levels[meadow.levelId]!;
    final engine = engineFor(level, snapshot.registry)..replay(saved.history);
    // The free tile drawn last (topmost) is the clearest to tap.
    final index = engine.geometry.drawOrder.lastWhere((i) => engine.isRemaining(i) && engine.isFreeIndex(i));
    final id = level.tiles[index].tileId;
    await tapBoardTile(tester, snapshot, meadow, saved.history, id);
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
    expect(gameOf(tester).state.moveCount, 5, reason: 'one move per tap (the HUD shows the score now)');
    await _capture(tester, 'gameplay_night_411x914_tray1', _large.dpr);
    await _leave(tester);
  });

  for (final phone in [_large, _small]) {
    testWidgets('a matching pair strikes and shatters in the tray ${phone.name}', (tester) async {
      await start(tester);
      final saved = solvedSave(snapshot, meadow, pairs: 2);
      await _pumpGame(tester, services: services, entry: meadow, phone: phone, resume: saved);
      final level = snapshot.levels[meadow.levelId]!;
      final engine = engineFor(level, snapshot.registry);
      final (a, b) = MahjongSolver(
        geometry: engine.geometry,
        rules: engine.rules,
      ).solve(TileMask.all(level.tiles.length)).solution[2];
      final first = level.tiles[a].tileId, second = level.tiles[b].tileId;
      await tapBoardTile(tester, snapshot, meadow, saved.history, first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_inTray(first), findsOneWidget);
      await tapBoardTile(tester, snapshot, meadow, [...saved.history, first], second);
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
    final saved = solvedSave(snapshot, meadow, pairs: 2);
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: saved);
    final level = snapshot.levels[meadow.levelId]!;
    final engine = engineFor(level, snapshot.registry)..replay(saved.history);
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
    await tapBoardTile(tester, snapshot, meadow, saved.history, first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tapBoardTile(tester, snapshot, meadow, [...saved.history, first], second);
    await tester.pump();
    await tester.pump(kTileFlightDuration + const Duration(milliseconds: 100));
    await tapBoardTile(tester, snapshot, meadow, engine.state.history, third);
    await _settle(tester);
    expect(_inTray(third), findsOneWidget);
    expect(find.bySemanticsLabel('Tray, 1 of 4 tiles'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  for (final phone in [_large, _small]) {
    testWidgets('a tray holding three tiles ${phone.name}', (tester) async {
      await start(tester);
      final (save, _) = nearlyFullSave(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: phone, resume: save);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Tray, 3 of 4 tiles'), findsOneWidget);
      final engine = engineFor(snapshot.levels[meadow.levelId]!, snapshot.registry)..replay(save.history);
      for (final id in engine.state.tray) {
        expect(_inTray(id), findsOneWidget);
      }
      _expectLayout(tester, phone);
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
      resume: solvedSave(snapshot, meadow, pairs: 12, elapsedMs: 3723000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('12/${pairsOf(meadow)}'), findsOneWidget);
    _expectLayout(tester, _small);
    await _capture(tester, 'gameplay_night_360x640_text130', _small.dpr);
    await _leave(tester);
  });

  testWidgets('no Restart pill; the HUD is on top, Restart an icon in the action bar', (tester) async {
    await start(tester);
    await _pumpGame(
      tester,
      services: services,
      entry: meadow,
      phone: _large,
      resume: solvedSave(snapshot, meadow, pairs: 3),
    );
    expect(find.text('3/${pairsOf(meadow)}'), findsOneWidget);
    expect(find.text('Restart'), findsNothing);
    // An icon only (no text label) opens the confirm card; no card at rest.
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(find.text('Restart level?'), findsNothing);
    _expectLayout(tester, _large);
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  for (final phone in [_large, _small]) {
    testWidgets('restart confirm card ${phone.name}', (tester) async {
      await start(tester);
      await _pumpGame(
        tester,
        services: services,
        entry: meadow,
        phone: phone,
        resume: solvedSave(snapshot, meadow, pairs: 3),
      );
      await tester.tap(find.byTooltip('Restart'));
      await tester.pump();
      await _settle(tester);
      expect(find.text('Restart this level?'), findsOneWidget);
      expect(find.text('Your score and time start over.'), findsOneWidget);
      expect(find.text('Keep playing'), findsOneWidget);
      _expectLayout(tester, phone);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_${phone.name}_restart_confirm', phone.dpr);
      await _leave(tester);
    });
  }

  testWidgets('win overlay', (tester) async {
    await start(tester);
    await _pumpGame(
      tester,
      services: services,
      entry: meadow,
      phone: _large,
      resume: solvedSave(snapshot, meadow, elapsedMs: 83000),
    );
    expect(find.text('Level Complete!'), findsOneWidget);
    expect(find.text('Next Level'), findsOneWidget);
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('Level Select'), findsOneWidget);
    // Level Complete covers the whole screen; its buttons stay inside it.
    _expectLayout(tester, _large);
    expect(tester.getRect(find.text('Replay')).bottom, lessThan(_large.height - _large.bottom));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'gameplay_night_411x914_win', _large.dpr);
    await _leave(tester);
  });

  for (final (phone, textScale) in [(_small, 1.3), (_large, 1.0)]) {
    testWidgets('tray-full overlay ${phone.name} at ${textScale}x text', (tester) async {
      await start(tester);
      final (save, last) = nearlyFullSave(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: phone, textScale: textScale, resume: save);
      // The fourth unmatched tile fills the tray: game over.
      await tapBoardTile(tester, snapshot, meadow, save.history, last);
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
      expect(find.text('Level Select'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      _expectLayout(tester, phone);
      expect(tester.getRect(find.text('Restart')).top, greaterThan(tester.getRect(find.byType(GameHud)).bottom));
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

  // Revive waits for a rewarded ad: the card with Revive off and its note,
  // at the tightest size.
  for (final (status, note) in [
    (RewardedAdStatus.loading, kReviveLoadingNote),
    (RewardedAdStatus.offline, kReviveOfflineNote),
    (RewardedAdStatus.ready, null),
  ]) {
    testWidgets('tray-full overlay, ad ${status.name}, 360x640 at 1.3x text', (tester) async {
      await start(tester, ads: FakeRewardedAds(status));
      final (save, last) = nearlyFullSave(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: _small, textScale: 1.3, resume: save);
      await tapBoardTile(tester, snapshot, meadow, save.history, last);
      await _settle(tester);
      expect(find.text('Tray full'), findsOneWidget);
      expect(find.text('Revive'), findsOneWidget);
      if (note != null) expect(find.text(note), findsOneWidget);
      expect(find.byIcon(Icons.ondemand_video_rounded), findsOneWidget);
      _expectLayout(tester, _small);
      expect(tester.getRect(find.text('Restart')).top, greaterThan(tester.getRect(find.byType(GameHud)).bottom));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_360x640_tray_full_ad_${status.name}', _small.dpr);
      await _leave(tester);
    });
  }

  for (final textScale in [1.0, 1.3]) {
    final text = textScale == 1 ? '' : '_text130';

    // Online with no ad to show: Revive is free after kAdFallbackDelay
    // (owner, 2026-10-17).
    testWidgets('tray-full overlay, no ad: a free revive, 360x640 at ${textScale}x text', (tester) async {
      await start(tester, ads: FakeRewardedAds(RewardedAdStatus.loading));
      final (save, last) = nearlyFullSave(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: _small, textScale: textScale, resume: save);
      await tapBoardTile(tester, snapshot, meadow, save.history, last);
      await _settle(tester);
      expect(find.text(kReviveLoadingNote), findsOneWidget);
      await tester.pump(kAdFallbackDelay);
      await tester.pump();
      expect(find.text(kReviveFreeNote), findsOneWidget);
      expect(find.byIcon(Icons.ondemand_video_rounded), findsNothing);
      expect(tester.widget<PremiumButton>(find.widgetWithText(PremiumButton, 'Revive')).onPressed, isNotNull);
      _expectLayout(tester, _small);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_360x640_tray_full_ad_free$text', _small.dpr);
      await _leave(tester);
    });

    // After kMaxRevivesPerLevel revives: Restart only, and no ad.
    testWidgets('tray-full overlay, no revives left, 360x640 at ${textScale}x text', (tester) async {
      await start(tester, ads: FakeRewardedAds());
      final (save, last) = nearlyFullSave(snapshot, meadow, revives: kMaxRevivesPerLevel);
      await _pumpGame(tester, services: services, entry: meadow, phone: _small, textScale: textScale, resume: save);
      await tapBoardTile(tester, snapshot, meadow, save.history, last);
      await _settle(tester);
      expect(find.text('Tray full'), findsOneWidget);
      expect(find.text('Revive'), findsNothing);
      expect(find.text(kNoRevivesLeftNote), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
      _expectLayout(tester, _small);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_360x640_tray_full_no_revives$text', _small.dpr);
      await _leave(tester);
    });

    testWidgets('refill card, no ad: a free Hint, 360x640 at ${textScale}x text', (tester) async {
      await start(tester, ads: FakeRewardedAds(RewardedAdStatus.loading));
      await _pumpGame(
        tester,
        services: services,
        entry: meadow,
        phone: _small,
        textScale: textScale,
        resume: solvedSave(snapshot, meadow, pairs: 2),
      );
      final game = gameOf(tester);
      while (game.usesLeft(GameAction.hint) > 0 && game.useHint() != null) {}
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('action-hint')));
      await _settle(tester);
      expect(find.text(kRefillLoadingNote), findsOneWidget);
      await _capture(tester, 'gameplay_night_360x640_refill_loading$text', _small.dpr);
      await tester.pump(kAdFallbackDelay);
      await tester.pump();
      expect(find.text('One more Hint?'), findsOneWidget);
      expect(find.text('Get +1 Hint'), findsOneWidget);
      expect(find.text(refillFreeNote(GameAction.hint)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'gameplay_night_360x640_refill_free$text', _small.dpr);
      await _leave(tester);
    });
  }

  testWidgets('revive flies the tray tiles back to the board', (tester) async {
    await start(tester);
    final (save, last) = nearlyFullSave(snapshot, meadow);
    await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: save);
    final level = snapshot.levels[meadow.levelId]!;
    final engine = engineFor(level, snapshot.registry)..replay([...save.history, last]);
    final trayTiles = engine.state.tray;
    final onBoard = engine.state.remaining.length;
    await tapBoardTile(tester, snapshot, meadow, save.history, last);
    await _settle(tester);
    expect(find.text('Revive'), findsOneWidget);
    await tester.tap(find.text('Revive'));
    await tester.pump();
    expect(find.text('Tray full'), findsNothing, reason: 'the card goes at once');
    expect(gameOf(tester).introPlaying, isFalse, reason: 'a revive does not replay the intro');
    expect(introOf(tester).isRunning, isFalse);
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
    expect(gameOf(tester).state.moveCount, 4, reason: 'a revive is not a move');
    expect(tester.takeException(), isNull);
    await _capture(tester, 'gameplay_night_411x914_revived', _large.dpr);
    // Play goes on: a returned tile can be tapped again.
    final free = engine..revive();
    final again = trayTiles.firstWhere((id) => free.isFreeIndex(free.indexOf(id)!));
    await tapBoardTile(tester, snapshot, meadow, free.state.history, again);
    await _settle(tester);
    expect(_inTray(again), findsOneWidget);
    await _leave(tester);
  });

  // Board previews of a scratch content tree (PREVIEW_TREE), every level at
  // both phone sizes, after the intro.
  testWidgets('board previews', skip: _previewTree == null || _captureDir == null, (tester) async {
    await start(tester, full: true);
    final only = Platform.environment['PREVIEW_LEVELS']?.split(',').toSet();
    final phones = Platform.environment['PREVIEW_PHONES']?.split(',').toSet();
    for (final entry in snapshot.playableEntries) {
      if (only != null && !only.contains(entry.levelId)) continue;
      for (final phone in [_iphone, _small, _ipad]) {
        if (phones == null ? phone == _ipad : !phones.contains(phone.name)) continue;
        await _pumpGame(tester, services: services, entry: entry, phone: phone);
        for (var i = 0; i < 3; i++) {
          await _settle(tester);
        }
        await _capture(tester, 'preview_${entry.levelId}_d${entry.difficulty}_${phone.name}', phone.dpr);
        await _leave(tester);
      }
    }
  });

  // One board per tier, the largest of each, at both phone sizes.
  for (final tier in ['1', '4', '7', '10']) {
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
        final capacity = level.rules.trayCapacity;
        expect(capacity, inInclusiveRange(2, 5));
        expect(find.bySemanticsLabel('Tray, 0 of $capacity tiles'), findsOneWidget);
        _expectLayout(tester, phone);
        // Tiles stay big enough to tap.
        final board = tester.getRect(find.byType(BoardView));
        final projection = boardProjectionFor(
          level,
          engineFor(level, snapshot.registry).geometry,
          TileStyle.forTileSet(level.tileSetId),
          board.size,
        );
        expect(projection.faceWidth, greaterThanOrEqualTo(30), reason: '${entry.levelId}: ${level.tiles.length} tiles');
        await _capture(tester, 'tier_${tier}_${phone.name}_${entry.levelId}', phone.dpr);
        await _leave(tester);
      });
    }
  }

  // The 5-slot tray of the easiest levels (the widest tray).
  for (final (phone, textScale) in [(_small, 1.3), (_large, 1.0)]) {
    testWidgets('5-slot tray ${phone.name}: empty, four held, full', (tester) async {
      await start(tester);
      final entry = snapshot.playableEntries.firstWhere((e) => e.trayCapacity == 5 && e.difficulty == '2');
      final level = snapshot.levels[entry.levelId]!;
      expect(level.rules.trayCapacity, 5);

      await _pumpGame(tester, services: services, entry: entry, phone: phone, textScale: textScale);
      expect(find.bySemanticsLabel('Tray, 0 of 5 tiles'), findsOneWidget);
      final tray = tester.getRect(find.byType(TrayView));
      expect(tray.left, greaterThanOrEqualTo(0));
      expect(tray.right, lessThanOrEqualTo(phone.width));
      _expectLayout(tester, phone);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'tray5_${phone.name}_empty', phone.dpr);
      await _leave(tester);

      final (save, last) = nearlyFullSave(snapshot, entry);
      await _pumpGame(tester, services: services, entry: entry, phone: phone, textScale: textScale, resume: save);
      expect(find.bySemanticsLabel('Tray, 4 of 5 tiles'), findsOneWidget);
      final engine = engineFor(level, snapshot.registry)..replay(save.history);
      final wells = <Rect>[for (final id in engine.state.tray) tester.getRect(_inTray(id))];
      expect(wells, hasLength(4));
      for (var i = 1; i < wells.length; i++) {
        expect(wells[i].left, greaterThan(wells[i - 1].right - 0.5), reason: 'slots do not overlap');
      }
      expect(wells.first.left, greaterThanOrEqualTo(0));
      _expectLayout(tester, phone);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'tray5_${phone.name}_four', phone.dpr);

      // The fifth unmatched tile fills the tray: game over.
      await tapBoardTile(tester, snapshot, entry, save.history, last);
      await _settle(tester);
      expect(find.text('Tray full'), findsOneWidget);
      expect(find.text('Revive'), findsOneWidget);
      expect(find.bySemanticsLabel('Tray full'), findsWidgets);
      _expectLayout(tester, phone);
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
      gameOf(tester).restart();
      await tester.pump();
      await tester.pump();
      expect(introOf(tester).isRunning, isTrue);
      final intro = introOf(tester).intro!;
      expect(intro.seconds, 0);
      final total = intro.choreography.total;
      for (final f in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        await _introTo(tester, total * f);
        expect(tester.takeException(), isNull);
        await _capture(tester, '${name}_t${(total * f).toStringAsFixed(1)}', _large.dpr, keep: frames);
      }
      await _introTo(tester, total);
      await tester.pump();
      expect(introOf(tester).isRunning, isFalse, reason: 'handed over to the board');
      expect(gameOf(tester).introPlaying, isFalse);
      await _capture(tester, '${name}_t${total.toStringAsFixed(1)}', _large.dpr, keep: frames);
      return frames;
    }

    testWidgets('a contact sheet per mix style, on difficulty 7-10 boards', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
      await start(tester, full: true);
      for (final style in IntroStyle.values) {
        final entry = snapshot.playableEntries.firstWhere(
          (e) => int.parse(e.difficulty!) >= 7 && IntroStyle.forLevel(e.levelId) == style,
        );
        await _pumpGame(tester, services: services, entry: entry, phone: _large);
        expect(introOf(tester).isRunning, isFalse);
        final frames = await sequence(tester, 'intro_${style.name}_${entry.levelId}_411x914');
        await _writeSheet(tester, 'intro_sheet_${style.name}', [frames]);
        await _leave(tester);
      }
    });

    testWidgets('the clock starts after the tier\'s intro: 2.333 s on a difficulty-4 board', (tester) async {
      await start(tester);
      final hard = firstOf('4');
      await _pumpGame(tester, services: services, entry: hard, phone: _large);
      final game = gameOf(tester);
      game.restart();
      await tester.pump();
      await tester.pump();
      expect(introOf(tester).intro!.choreography.total, closeTo(2.333, 1e-9));
      await _introTo(tester, 2.25);
      expect(game.introPlaying, isTrue, reason: 'longer than an easy intro');
      expect(game.elapsed, Duration.zero);
      await _introTo(tester, 2.333);
      await tester.pump();
      expect(game.introPlaying, isFalse);
      // The clock is a real stopwatch: give it real time.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      expect(game.elapsed, greaterThan(Duration.zero), reason: 'running now');
      await _leave(tester);
    });

    testWidgets('frame sequence at 411x914: a difficulty-10 level and a difficulty-1 one', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
      await start(tester, full: true);
      final hard = firstOf('10');
      await _pumpGame(tester, services: services, entry: hard, phone: _large);
      expect(snapshot.levels[hard.levelId]!.tiles.length, greaterThanOrEqualTo(80), reason: 'a big board on the 7x9 grid');
      final hardFrames = await sequence(tester, 'intro_${hard.levelId}_411x914');
      await _leave(tester);
      final easy = firstOf('1');
      await _pumpGame(tester, services: services, entry: easy, phone: _large);
      final easyFrames = await sequence(tester, 'intro_${easy.levelId}_411x914');
      await _writeSheet(tester, 'intro_sheet', [hardFrames, easyFrames]);
      await _leave(tester);
    });

    testWidgets('taps wait for the intro, the clock starts after it, a restart replays it', (tester) async {
      await start(tester);
      await _pumpGame(tester, services: services, entry: meadow, phone: _large);
      final game = gameOf(tester);
      game.restart();
      await tester.pump();
      await tester.pump();
      final level = snapshot.levels[meadow.levelId]!;
      final engine = engineFor(level, snapshot.registry);
      final id = (engine.state.free.toList()..sort()).first;
      await _introTo(tester, 1.0);
      expect(game.elapsed, Duration.zero, reason: 'the intro is not play time');
      await tapBoardTile(tester, snapshot, meadow, const [], id);
      await tester.pump();
      expect(game.state.moveCount, 0, reason: 'taps are ignored during the intro');
      expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
      // A restart mid-intro starts it again.
      final serial = game.introSerial;
      game.restart();
      await tester.pump();
      await tester.pump();
      expect(game.introSerial, isNot(serial));
      expect(introOf(tester).intro!.seconds, 0);
      await _introTo(tester, introOf(tester).intro!.choreography.total);
      await tester.pump();
      expect(game.introPlaying, isFalse);
      await tapBoardTile(tester, snapshot, meadow, const [], id);
      await _settle(tester);
      expect(_inTray(id), findsOneWidget, reason: 'play is on after the intro');
      expect(game.elapsed, greaterThan(Duration.zero));
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('a resumed game: only board tiles fly, the tray shows its tiles at once', (tester) async {
      await start(tester);
      final (save, _) = nearlyFullSave(snapshot, meadow);
      await _pumpGame(tester, services: services, entry: meadow, phone: _large, resume: save, intro: _IntroWait.start);
      final game = gameOf(tester);
      final intro = introOf(tester).intro!;
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
      await finishIntro(tester);
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('leaving during the intro frees it cleanly', skip: !_hasFullTree /* needs content/brain-train/ */, (tester) async {
      await start(tester, full: true);
      await _pumpGame(tester, services: services, entry: firstOf('10'), phone: _large, intro: _IntroWait.start);
      final intro = introOf(tester).intro!;
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
      final game = gameOf(tester);
      expect(game.introPlaying, isFalse);
      expect(introOf(tester).isRunning, isFalse);
      final level = snapshot.levels[meadow.levelId]!;
      final id = (engineFor(level, snapshot.registry).state.free.toList()..sort()).first;
      await tapBoardTile(tester, snapshot, meadow, const [], id);
      await _settle(tester);
      expect(_inTray(id), findsOneWidget);
      await _leave(tester);
    });
  });

  // The first-play tutorial on level 1: each step, with its card clear of
  // the highlight and inside the screen (1.3x text and iPad too).
  for (final (phone, textScale) in [(_large, 1.0), (_small, 1.0), (_small, 1.3), (_ipad, 1.0)]) {
    final suffix = '${phone.name}${textScale == 1 ? '' : '_text$textScale'}';
    testWidgets('first-play tutorial $suffix', (tester) async {
      await tester.runAsync(() async {
        services = await _services(tutorialDone: false);
        snapshot = services.content.snapshot;
      });
      final entry = snapshot.playableEntries.first;
      await _pumpGame(tester, services: services, entry: entry, phone: phone, textScale: textScale);
      await tester.pump();
      await tester.pump();
      final tutorial = tester.widget<FirstPlayTutorialOverlay>(find.byType(FirstPlayTutorialOverlay)).controller;
      final board = tester.state<BoardViewState>(find.byType(BoardView));
      final tray = tester.state<TrayViewState>(find.byType(TrayView));

      /// [finder]'s box on the (tablet) canvas, like the board's and tray's rects.
      Rect onCanvas(Finder finder) {
        final box = tester.renderObject<RenderBox>(finder);
        return MatrixUtils.transformRect(box.getTransformTo(TabletScale.canvasAbove(box)), Offset.zero & box.size);
      }

      Future<void> step(int number, String title, {List<Rect?> highlights = const []}) async {
        for (var i = 0; i < 60 && find.text(title).evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 60));
        }
        // The card has risen in; the pulse ring is out of the hole.
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
        final card = onCanvas(find.ancestor(of: find.text(title), matching: find.byType(PremiumPanel)).first);
        final screen = onCanvas(find.byType(FirstPlayTutorialOverlay));
        expect(screen.contains(card.topLeft) && screen.contains(card.bottomRight - const Offset(1, 1)), isTrue);
        for (final lit in highlights) {
          expect(card.overlaps(lit!), isFalse, reason: 'step $number: the card clears the highlights');
        }
        await _capture(tester, 'tutorial_${number}_$suffix', phone.dpr);
      }

      await step(1, 'Tap a free tile', highlights: [board.tileFaceRect(tutorial.pair.$1)]);
      await tapBoardTile(tester, snapshot, entry, gameOf(tester).state.history, tutorial.pair.$1);
      await step(2, 'It drops into your tray', highlights: [tray.panelRect()]);
      await tester.tap(find.text('Next'));
      await step(3, 'Find its twin', highlights: [board.tileFaceRect(tutorial.pair.$2), tray.panelRect()]);
      await tapBoardTile(tester, snapshot, entry, gameOf(tester).state.history, tutorial.pair.$2);
      await step(4, 'Keep your tray clear', highlights: [tray.panelRect()]);
      await tester.tap(find.text('Next'));
      await step(5, 'Clear every pair to win');
      await tester.tap(find.text("Let's play"));
      await tester.pump();
      await tester.pump();
      expect(find.byType(FirstPlayTutorialOverlay), findsNothing);
      expect(gameOf(tester).clockRunning, isTrue);
      await _leave(tester);
    });
  }
}

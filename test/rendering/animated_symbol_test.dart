import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/rendering/board_renderer.dart';
import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_animation.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// A 100x100, 1 s, 30 fps animation: a yellow disc (diameter 80) centred at
/// (50, 50), scaled 50% at t=0, 100% at t=0.5 s, back to 50% at t=1 s.
final Uint8List pulse = File('test/fixtures/pulse.lottie.json').readAsBytesSync();

const String pulsePath = 'animated-symbols/pulse.json';
const SymbolDefinition pulseSymbol = SymbolDefinition(code: 'PULSE', type: SymbolType.lottie, assetPath: pulsePath);

/// Serves [files] by content path; anything else is missing.
ContentSource sourceOf(Map<String, Uint8List> files) =>
    BundledContentSource((key) async => files[key.substring('content/brain-train/'.length)]);

Uint8List pulseWith(void Function(Map<String, Object?> json) edit) {
  final json = jsonDecode(utf8.decode(pulse)) as Map<String, Object?>;
  edit(json);
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

/// RGBA of the pixel at ([x], [y]) of [image].
Future<List<int>> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData())!;
  final offset = (y * image.width + x) * 4;
  return [for (var i = 0; i < 4; i++) data.getUint8(offset + i)];
}

Future<ui.Image> render(Size size, void Function(Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size.width.ceil(), size.height.ceil());
  picture.dispose();
  return Future.value(image);
}

bool isYellow(List<int> rgba) => rgba[3] > 200 && rgba[0] > 200 && rgba[1] > 150 && rgba[2] < 90;

void main() {
  const box = Size(100, 100);

  testWidgets('a Lottie symbol resolves to animated art with a still poster', (tester) async {
    await tester.runAsync(() async {
      final art = await SymbolArtCache().resolve(pulseSymbol, sourceOf({pulsePath: pulse}), box, 1);
      expect(art, isA<AnimatedSymbolArt>());
      expect(art.isAnimated, isTrue);
      expect(art.isFallback, isFalse);
      expect((art as AnimatedSymbolArt).composition.seconds, closeTo(1, 0.01));
      // Poster = first frame: the disc at half size (radius 20).
      expect(isYellow(await pixel(art.image, 50, 50)), isTrue);
      expect((await pixel(art.image, 50 + 30, 50))[3], 0);
    });
  });

  testWidgets('frames follow the shared clock and loop', (tester) async {
    await tester.runAsync(() async {
      final art =
          await SymbolArtCache().resolve(pulseSymbol, sourceOf({pulsePath: pulse}), box, 1) as AnimatedSymbolArt;
      expect(art.progressAt(0), 0);
      expect(art.progressAt(0.5), closeTo(0.5, 0.04));
      expect(art.progressAt(2.5), closeTo(art.progressAt(0.5), 1e-9));
      Future<List<int>> edgeAt(double seconds) async {
        final image = await render(box, (canvas) => art.paintFrame(canvas, Offset.zero & box, seconds));
        return pixel(image, 50 + 30, 50);
      }

      expect((await edgeAt(0))[3], 0, reason: 'disc is small at t=0');
      expect(isYellow(await edgeAt(0.5)), isTrue, reason: 'disc is full size at t=0.5 s');
      expect((await edgeAt(1.0))[3], 0, reason: 'and small again after one loop');
      expect(art.isBroken, isFalse);
    });
  });

  testWidgets('non-square animations are aspect-fitted and clipped to the symbol box', (tester) async {
    await tester.runAsync(() async {
      // 200x100 composition into a 60x80 box: scaled 0.3 to 60x30, centred
      // vertically (y 25-55). The disc (centre (50, 50), radius 40) lands at
      // (15, 40) with radius 12 at full size.
      final wide = pulseWith((json) => json['w'] = 200);
      const tall = Size(60, 80);
      final art =
          await SymbolArtCache().resolve(pulseSymbol, sourceOf({pulsePath: wide}), tall, 1) as AnimatedSymbolArt;
      final image = await render(tall, (canvas) => art.paintFrame(canvas, Offset.zero & tall, 0.5));
      expect(isYellow(await pixel(image, 15, 40)), isTrue);
      expect((await pixel(image, 15, 22))[3], 0, reason: 'nothing above the fitted area');
      expect((await pixel(image, 45, 40))[3], 0, reason: 'the disc is not stretched');
    });
  });

  testWidgets('missing or invalid animations fall back to a drawn face', (tester) async {
    await tester.runAsync(() async {
      final cache = SymbolArtCache();
      final missing = await cache.resolve(pulseSymbol, sourceOf({}), box, 1);
      expect(missing.isFallback, isTrue);
      expect(missing.isAnimated, isFalse);
      for (final bad in [
        bytesOf('<html>not json</html>'),
        bytesOf('[1, 2, 3]'),
        pulseWith((json) => json.remove('layers')),
        pulseWith((json) => json['fr'] = 0),
        // Plausible header, nonsense layer: the parser or drawing may fail.
        pulseWith(
          (json) => json['layers'] = [
            {'ty': 4, 'ks': 'oops', 'shapes': 7},
          ],
        ),
      ]) {
        final art = await SymbolArtCache().resolve(pulseSymbol, sourceOf({pulsePath: bad}), box, 1);
        if (art is AnimatedSymbolArt) {
          // Accepted by the parser: drawing must still never throw.
          await render(box, (canvas) => art.paintFrame(canvas, Offset.zero & box, 0.3));
        } else {
          expect(art.isFallback, isTrue);
        }
      }
    });
  });

  testWidgets('bundled animated symbols play offline', (tester) async {
    await tester.runAsync(() async {
      final manifest = LevelManifest.fromJson(
        decodeJsonBytes(await repoContent.read('manifest.json', ContentKind.json), 'manifest.json'),
      );
      final registry = SymbolRegistry.fromJson(
        decodeJsonBytes(await repoContent.read(manifest.symbolRegistry.url, ContentKind.json), 'registry'),
      );
      final animated = registry.symbols.values.where((s) => s.isAnimated).toList();
      expect(animated, isNotEmpty);
      final art = await SymbolArtCache().resolve(animated.first, repoContent, const Size(60, 80), 2);
      expect(art, isA<AnimatedSymbolArt>());
    });
  });

  testWidgets('the board draws animated symbols in draw order: covered tiles stay covered', (tester) async {
    await tester.runAsync(() async {
      const style = TileStyle.classicIvory;
      const renderer = MahjongTileRenderer(style);
      final open = level([('a1', 'PULSE', 0, 0, 0), ('a2', 'PULSE', 4, 0, 0)]);
      final covered = level([('a1', 'PULSE', 0, 0, 0), ('a2', 'PULSE', 4, 0, 0), ('c', 'COVER', 0, 0, 1)]);
      const size = Size(300, 200);
      Future<List<int>> centreOfFirstTile(LevelDefinition levelDef) async {
        final geometry = BoardGeometry.build(levelDef);
        final projection = boardProjectionFor(levelDef, geometry, style, size);
        final face = Size(projection.faceWidth, projection.faceHeight);
        final symbolBox = renderer.symbolRect(Offset.zero & face).size;
        final art = BoardArt(
          body: await renderer.renderBody(face, 1),
          // COVER has no art: its plain ivory face hides what is below.
          symbols: {
            'PULSE': await SymbolArtCache().resolve(pulseSymbol, sourceOf({pulsePath: pulse}), symbolBox, 1),
          },
        );
        final clock = SymbolAnimationClock();
        final painter = BoardPainter(
          level: levelDef,
          projection: projection,
          art: art,
          style: style,
          effects: BoardEffects(style: style),
          isRemaining: (_) => true,
          isFree: (_) => true,
          dimBlocked: false,
          stateVersion: 0,
          symbolClock: clock,
        );
        final image = await render(size, (canvas) => painter.paint(canvas, size));
        final face0 = projection.faceRect(0);
        return pixel(image, face0.centerX.round(), face0.centerY.round());
      }

      expect(isYellow(await centreOfFirstTile(open)), isTrue);
      expect(isYellow(await centreOfFirstTile(covered)), isFalse);
    });
  });

  testWidgets('a cached idle board (static image + moving symbols) matches drawing every tile live', (tester) async {
    await tester.runAsync(() async {
      const style = TileStyle.classicIvory;
      const renderer = MahjongTileRenderer(style);
      // Open animated tiles, one blocked between neighbours,
      // one under an upper-layer tile, and plain text tiles.
      final board = level([
        ('a1', 'PULSE', 0, 0, 0),
        ('t1', 'T', 2, 0, 0),
        ('a2', 'PULSE', 4, 0, 0),
        ('t2', 'T', 6, 0, 0),
        ('a3', 'PULSE', 0, 4, 0),
        ('a4', 'PULSE', 6, 4, 0),
        ('c', 'T', 5, 3, 1),
      ]);
      const size = Size(320, 240);
      final geometry = BoardGeometry.build(board);
      final projection = boardProjectionFor(board, geometry, style, size);
      final face = Size(projection.faceWidth, projection.faceHeight);
      final symbolBox = renderer.symbolRect(Offset.zero & face).size;
      final cache = SymbolArtCache();
      final source = sourceOf({pulsePath: pulse});
      final art = BoardArt(
        body: await renderer.renderBody(face, 1),
        raisedShadow: await renderer.renderRaisedShadow(face, 1),
        symbols: {
          'PULSE': await cache.resolve(pulseSymbol, source, symbolBox, 1),
          'T': await cache.resolve(
            const SymbolDefinition(code: 'T', type: SymbolType.text, value: 'T'),
            source,
            symbolBox,
            1,
          ),
        },
      );
      final effects = BoardEffects(style: style, reduceMotion: true);
      final clock = SymbolAnimationClock();
      final layers = BoardLayers();
      BoardPainter painter({BoardLayers? layers}) => BoardPainter(
        level: board,
        projection: projection,
        art: art,
        style: style,
        effects: effects,
        isRemaining: (_) => true,
        isFree: (i) => board.tiles[i].tileId != 't1',
        dimBlocked: true,
        stateVersion: 0,
        symbolClock: clock,
        layers: layers,
      );
      final live = await render(size, (canvas) => painter().paint(canvas, size));
      // The first paint draws tile by tile and starts rendering the static
      // image; once that is ready, paints use it.
      await render(size, (canvas) => painter(layers: layers).paint(canvas, size));
      await layers.ready;
      expect(layers.debugMovingTiles, isNotEmpty, reason: 'static image installed');
      final cached = await render(size, (canvas) => painter(layers: layers).paint(canvas, size));
      final a = (await live.toByteData())!, b = (await cached.toByteData())!;
      if (Platform.environment['DEBUG_BOARD_DIFF'] case final dir?) {
        for (final (name, image) in [('live', live), ('cached', cached)]) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/board_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      }
      // Moving symbols are frames rendered to pixels, so their edges may be
      // re-sampled a little differently; everywhere else (the faces around
      // them, shading, the covered tile) must match.
      Rect faceOf(String id) {
        final f = projection.faceRect(board.tiles.indexWhere((t) => t.tileId == id));
        return Rect.fromLTWH(f.left, f.top, f.width, f.height);
      }

      final moving = [
        for (final id in ['a1', 'a2', 'a3']) renderer.symbolRect(faceOf(id)).inflate(1),
      ];
      var outside = 0, inside = 0;
      for (var i = 0; i < a.lengthInBytes; i += 4) {
        var d = 0;
        for (var c = 0; c < 4; c++) {
          final v = (a.getUint8(i + c) - b.getUint8(i + c)).abs();
          if (v > d) d = v;
        }
        if (d <= 8) continue;
        final p = Offset(((i ~/ 4) % live.width) + 0.5, ((i ~/ 4) ~/ live.width) + 0.5);
        if (moving.any((r) => r.contains(p))) {
          inside++;
        } else {
          outside++;
        }
      }
      expect(outside, 0, reason: 'only the moving symbols may differ');
      expect(inside, lessThan(live.width * live.height ~/ 100), reason: 'and only along their edges');
      // Moving symbols are drawn over the static image; the covered one is not.
      final plan = layers.debugMovingTiles;
      expect(plan, containsAll(<String>['a1', 'a2', 'a3']));
      expect(plan, isNot(contains('a4')), reason: 'a4 is under tile c');
      layers.dispose();
      art.dispose();
    });
  });

  group('BoardView', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<GameController> controllerFor() async {
      final registry = SymbolRegistry(
        registryVersion: 'test',
        symbols: {
          'PULSE': pulseSymbol,
          'T': const SymbolDefinition(code: 'T', type: SymbolType.text, value: 'T'),
        },
      );
      return GameController(
        entry: const LevelManifestEntry(
          levelId: 'test-level',
          order: 1,
          title: 'Test',
          ref: ContentRef(url: 'levels/t.json'),
        ),
        level: level([('p1', 'PULSE', 0, 0, 0), ('p2', 'PULSE', 4, 0, 0), ('t1', 'T', 8, 0, 0), ('t2', 'T', 12, 0, 0)]),
        registry: registry,
        progress: await ProgressRepository.open(),
        settings: await SettingsRepository.open(),
      );
    }

    Future<void> pumpBoard(WidgetTester tester, GameController controller, {bool reduceMotion = false}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 300)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 400,
                height: 200,
                child: BoardView(
                  controller: controller,
                  artwork: sourceOf({pulsePath: pulse}),
                  symbolArt: SymbolArtCache(),
                  dimBlocked: true,
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// Lets the tile body and symbol art render (real async work).
    Future<void> loadArt(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    SymbolAnimationClock clockOf(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(of: find.byType(BoardView), matching: find.byType(CustomPaint)),
      );
      return (paint.painter! as BoardPainter).symbolClock!;
    }

    testWidgets('animates while animated tiles remain, then stops ticking', (tester) async {
      late GameController controller;
      await tester.runAsync(() async => controller = await controllerFor());
      await pumpBoard(tester, controller);
      await loadArt(tester);
      expect(tester.takeException(), isNull);
      final clock = clockOf(tester);
      expect(clock.isRunning, isTrue);
      expect(clock.motion, isTrue);
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'continuous repaint while animated tiles are on the board',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      // Backgrounded: paused. Back in the foreground: running again.
      void lifecycle(List<AppLifecycleState> states) => states.forEach(tester.binding.handleAppLifecycleStateChanged);
      lifecycle([AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect(clock.isRunning, isFalse);
      lifecycle([AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect(clock.isRunning, isTrue);

      // Clearing the only animated pair stops the symbol clock; once the
      // removal effect ends, no more frames are scheduled.
      controller
        ..tapTile('p1')
        ..tapTile('p2');
      await tester.pump();
      expect(clock.isRunning, isFalse);
      // Tile effects run on a real stopwatch.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('with animations disabled, animated symbols are still and nothing ticks', (tester) async {
      late GameController controller;
      await tester.runAsync(() async => controller = await controllerFor());
      await pumpBoard(tester, controller, reduceMotion: true);
      await loadArt(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final clock = clockOf(tester);
      expect(clock.isRunning, isFalse);
      expect(clock.motion, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Turning motion back on starts the animation.
      await pumpBoard(tester, controller);
      expect(clockOf(tester).isRunning, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/features/gameplay/widgets/board_intro.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/board_projection.dart';
import 'package:brain_train/game_engine/geometry/tile_availability.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/rendering/board_renderer.dart';
import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_animation.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const stage = IntroStage(screen: Size(411, 914), board: Rect.fromLTWH(20, 200, 371, 420), faceWidth: 30);

  group('IntroChoreography', () {
    test('a quarter of the tiles from each side, fixed per seed', () {
      final big = IntroChoreography(layers: List.filled(172, 0), seed: 7);
      for (final side in IntroSide.values) {
        expect(big.sides.where((s) => s == side), hasLength(43), reason: '$side');
      }
      final small = IntroChoreography(layers: List.filled(10, 0), seed: 7);
      for (final side in IntroSide.values) {
        expect(small.sides.where((s) => s == side).length, inInclusiveRange(2, 3));
      }
      expect(IntroChoreography(layers: List.filled(172, 0), seed: 7).sides, big.sides);
      expect(IntroChoreography(layers: List.filled(172, 0), seed: 8).sides, isNot(big.sides));
    });

    test('fly in from off-screen on the tile side, mix, then land exactly in place', () {
      final c = IntroChoreography(layers: [for (var i = 0; i < 40; i++) i % 3], seed: 3);
      const target = Offset(200, 400);
      final screen = Offset.zero & stage.screen;
      for (var i = 0; i < c.length; i++) {
        final start = c.poseAt(i, 0, target: target, stage: stage).center;
        expect(screen.contains(start), isFalse, reason: 'tile $i starts off-screen');
        switch (c.sides[i]) {
          case IntroSide.left:
            expect(start.dx, lessThan(0));
          case IntroSide.right:
            expect(start.dx, greaterThan(stage.screen.width));
          case IntroSide.top:
            expect(start.dy, lessThan(0));
          case IntroSide.bottom:
            expect(start.dy, greaterThan(stage.screen.height));
        }
        // In the cloud around the board centre when the mix begins.
        final cloud = c.poseAt(i, IntroChoreography.flyInEnd, target: target, stage: stage);
        expect((cloud.center - stage.board.center).distance, lessThan(stage.board.longestSide * 0.45));
        expect(cloud.scale, IntroChoreography.cloudScale);
        // The mix moves every tile.
        final mixed = c.poseAt(i, c.mixEnd - 0.01, target: target, stage: stage);
        expect((mixed.center - cloud.center).distance, greaterThan(5), reason: 'tile $i swirls');
        // Exactly in place, unrotated, full size, before the end.
        for (final t in [c.settleEnd(i), c.total - IntroChoreography.finalHold, 2.0]) {
          final pose = c.poseAt(i, t, target: target, stage: stage);
          expect(pose.center, target);
          expect(pose.rotation, 0);
          expect(pose.scale, 1);
        }
      }
    });

    test('tiles swirl both ways, so they cross', () {
      final c = IntroChoreography(layers: List.filled(40, 0), seed: 11);
      var clockwise = 0, counter = 0;
      for (var i = 0; i < c.length; i++) {
        final a = c.poseAt(i, IntroChoreography.flyInEnd, target: Offset.zero, stage: stage).center - stage.board.center;
        final b = c.poseAt(i, c.mixEnd - 0.01, target: Offset.zero, stage: stage).center -
            stage.board.center;
        final turn = math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);
        if (turn > 0) clockwise++;
        if (turn < 0) counter++;
      }
      expect(clockwise, greaterThan(5));
      expect(counter, greaterThan(5));
    });

    test('lower layers leave the cloud and land first; all within 2 s', () {
      final layers = [for (var i = 0; i < 120; i++) i % 5];
      final c = IntroChoreography(layers: layers, seed: 5);
      for (var layer = 0; layer < 4; layer++) {
        final lastStart = [
          for (var i = 0; i < c.length; i++)
            if (layers[i] == layer) c.settleStart(i),
        ].reduce(math.max);
        final nextFirstStart = [
          for (var i = 0; i < c.length; i++)
            if (layers[i] == layer + 1) c.settleStart(i),
        ].reduce(math.min);
        expect(lastStart, lessThan(nextFirstStart), reason: 'layer $layer before ${layer + 1}');
        expect(c.layerLanded(layer), lessThan(c.layerLanded(layer + 1)));
      }
      expect(c.settleStart(layers.indexOf(0)), greaterThanOrEqualTo(c.mixEnd));
      expect(c.layerLanded(4), lessThanOrEqualTo(c.total - IntroChoreography.finalHold + 1e-9));
    });
  });

  group('timing and styles', () {
    test('each tier has its length; boards without one go by tile count', () {
      expect(IntroTiming.forLevel(difficulty: 'easy', tileCount: 300), const Duration(milliseconds: 2000));
      expect(IntroTiming.forLevel(difficulty: 'medium', tileCount: 10), const Duration(milliseconds: 2300));
      expect(IntroTiming.forLevel(difficulty: 'hard', tileCount: 10), const Duration(milliseconds: 2600));
      expect(IntroTiming.forLevel(difficulty: 'veryHard', tileCount: 10), const Duration(milliseconds: 3000));
      expect(IntroTiming.forLevel(tileCount: 28), IntroTiming.easy);
      expect(IntroTiming.forLevel(tileCount: 64), IntroTiming.medium);
      expect(IntroTiming.forLevel(tileCount: 100), IntroTiming.hard);
      expect(IntroTiming.forLevel(difficulty: 'legendary', tileCount: 172), IntroTiming.veryHard);
    });

    test('longer intros keep the fly-in snappy and give the time to the mix and a calmer settle', () {
      final layers = [for (var i = 0; i < 170; i++) i % 4];
      final easy = IntroChoreography(layers: layers, seed: 1);
      final big = IntroChoreography(layers: layers, seed: 1, duration: IntroTiming.veryHard);
      expect(easy.total, 2.0);
      expect(big.total, 3.0);
      expect(easy.mixEnd, closeTo(1.3, 1e-9));
      final easyMix = easy.mixEnd - IntroChoreography.flyInEnd, bigMix = big.mixEnd - IntroChoreography.flyInEnd;
      final easySettle = easy.total - easy.mixEnd, bigSettle = big.total - big.mixEnd;
      expect(bigMix, greaterThan(easyMix * 2), reason: 'most of the extra second mixes');
      expect(bigSettle, greaterThan(easySettle));
      expect(bigMix - easyMix, greaterThan(bigSettle - easySettle));
      expect(big.settleTime, greaterThan(easy.settleTime));
      for (var i = 0; i < big.length; i++) {
        expect(big.settleEnd(i), lessThanOrEqualTo(big.total - IntroChoreography.finalHold + 1e-9));
      }
    });

    test('a style per level, always the same; levels next to each other differ', () {
      expect(IntroStyle.forLevel('level-0008'), IntroStyle.forLevel('level-0008'));
      final styles = [for (var n = 1; n <= 200; n++) IntroStyle.forLevel('level-${n.toString().padLeft(4, '0')}')];
      for (var n = 1; n < styles.length; n++) {
        expect(styles[n], isNot(styles[n - 1]), reason: 'levels $n and ${n + 1}');
      }
      expect(styles.toSet(), IntroStyle.values.toSet(), reason: 'every style is used');
      expect(IntroStyle.forLevel('meadow-path'), IntroStyle.forLevel('meadow-path'));
    });

    for (final style in IntroStyle.values) {
      for (final duration in [IntroTiming.easy, IntroTiming.veryHard]) {
        test('${style.name}, ${duration.inMilliseconds} ms: tiles mix, lower layers land first, exact at the end', () {
          final layers = [for (var i = 0; i < 60; i++) i % 3];
          final c = IntroChoreography(layers: layers, seed: 9, style: style, duration: duration);
          const target = Offset(150, 380);
          var moved = 0;
          for (var i = 0; i < c.length; i++) {
            final a = c.poseAt(i, IntroChoreography.flyInEnd, target: target, stage: stage).center;
            final b = c.poseAt(i, c.mixEnd - 0.01, target: target, stage: stage).center;
            if ((b - a).distance > stage.faceWidth * 0.5) moved++;
            // No jump where the fly-in hands over to the mix, or the mix to the settle.
            final before = c.poseAt(i, IntroChoreography.flyInEnd - 1e-6, target: target, stage: stage).center;
            expect((before - a).distance, lessThan(0.5));
            final s0 = c.settleStart(i);
            final leave = c.poseAt(i, s0 - 1e-6, target: target, stage: stage).center;
            expect((leave - c.poseAt(i, s0, target: target, stage: stage).center).distance, lessThan(0.5));
            final end = c.poseAt(i, c.total - IntroChoreography.finalHold, target: target, stage: stage);
            expect((end.center, end.rotation, end.scale), (target, 0.0, 1.0));
          }
          expect(moved, greaterThan(c.length * 0.8), reason: 'the mix moves almost every tile');
          expect(c.layerLanded(0), lessThan(c.layerLanded(1)));
          expect(c.layerLanded(1), lessThan(c.layerLanded(2)));
        });
      }
    }
  });

  group('BoardIntro', () {
    // Two layers: a 3x2 base, two tiles on top.
    final board = level([
      ('a1', 'A', 0, 0, 0),
      ('b1', 'B', 2, 0, 0),
      ('c1', 'C', 4, 0, 0),
      ('a2', 'A', 0, 2, 0),
      ('b2', 'B', 2, 2, 0),
      ('c2', 'C', 4, 2, 0),
      ('d1', 'D', 1, 1, 1),
      ('d2', 'D', 3, 1, 1),
    ]);
    const style = TileStyle.classicIvory;
    const renderer = MahjongTileRenderer(style);
    const size = Size(320, 240);

    Future<(BoardArt, BoardProjection, BoardGeometry)> artFor() async {
      final geometry = BoardGeometry.build(board);
      final projection = boardProjectionFor(board, geometry, style, size);
      final face = Size(projection.faceWidth, projection.faceHeight);
      final box = renderer.symbolRect(Offset.zero & face).size;
      final cache = SymbolArtCache();
      final art = BoardArt(
        body: await renderer.renderBody(face, 1),
        raisedShadow: await renderer.renderRaisedShadow(face, 1),
        symbols: {
          for (final code in ['A', 'B', 'C', 'D'])
            code: await cache.resolve(
              SymbolDefinition(code: code, type: SymbolType.text, value: code),
              BundledContentSource((_) async => null),
              box,
              1,
            ),
        },
      );
      return (art, projection, geometry);
    }

    BoardIntro introOf(
      BoardArt art,
      BoardProjection projection,
      BoardGeometry geometry, {
      VoidCallback? onDone,
      ValueChanged<int>? onLayer,
    }) {
      final free = TileAvailabilityCalculator(geometry);
      final all = TileMask.all(board.tiles.length);
      final tiles = geometry.drawOrder;
      final atlas = BoardSpriteAtlas.build(
        level: board,
        art: art,
        style: style,
        face: Size(projection.faceWidth, projection.faceHeight),
        tiles: tiles,
        shadeOf: (i) => boardTileShade(
          style,
          layer: board.tiles[i].layer,
          maxLayer: geometry.bounds.maxLayer,
          blocked: !free.isFree(i, all),
        ),
        pixelRatio: 1,
      );
      return BoardIntro(
        atlas: atlas,
        tiles: tiles,
        layers: [for (final i in tiles) board.tiles[i].layer],
        seed: 1,
        geometry: () => (projection: projection, transform: Matrix4.identity()),
        onDone: onDone,
        onLayerLanded: onLayer,
      );
    }

    Future<ui.Image> render(void Function(Canvas canvas) draw) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      draw(canvas);
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      picture.dispose();
      return image;
    }

    testWidgets('one sprite per distinct look; the last frame matches the board', (tester) async {
      await tester.runAsync(() async {
        final (art, projection, geometry) = await artFor();
        final controller = BoardIntroController();
        final intro = introOf(art, projection, geometry);
        // A1/A2 share a symbol but the shading differs only by blocking.
        expect(intro.atlas.spriteCount, lessThan(board.tiles.length));
        controller
          ..play(intro)
          ..tick(Duration.zero)
          ..tick(const Duration(milliseconds: 1960));
        expect(controller.isRunning, isTrue);
        final free = TileAvailabilityCalculator(geometry);
        final all = TileMask.all(board.tiles.length);
        final live = await render(
          (canvas) => BoardPainter(
            level: board,
            projection: projection,
            art: art,
            style: style,
            effects: BoardEffects(style: style),
            isRemaining: (_) => true,
            isFree: (i) => free.isFree(i, all),
            dimBlocked: true,
            stateVersion: 0,
          ).paint(canvas, size),
        );
        final last = await render((canvas) => controller.intro!.paint(canvas, size, Offset.zero));
        final a = (await live.toByteData())!, b = (await last.toByteData())!;
        var differing = 0, worst = 0;
        for (var i = 0; i < a.lengthInBytes; i += 4) {
          var d = 0;
          for (var c = 0; c < 4; c++) {
            d = math.max(d, (a.getUint8(i + c) - b.getUint8(i + c)).abs());
          }
          worst = math.max(worst, d);
          if (d > 24) differing++;
        }
        // Sprites are the board's own drawing, resampled once.
        expect(differing, lessThan(live.width * live.height ~/ 200), reason: 'worst channel diff $worst');
        controller.dispose();
        art.dispose();
      });
    });

    testWidgets('layers land in order, done once at 2 s, the atlas is freed', (tester) async {
      await tester.runAsync(() async {
        final (art, projection, geometry) = await artFor();
        final controller = BoardIntroController();
        final log = <String>[];
        final intro = introOf(art, projection, geometry, onDone: () => log.add('done'), onLayer: (l) => log.add('layer $l'));
        controller.play(intro);
        for (var ms = 0; ms <= 2100; ms += 16) {
          controller.tick(Duration(milliseconds: 1000 + ms));
        }
        expect(log, ['layer 0', 'layer 1', 'done']);
        expect(controller.isRunning, isFalse);
        expect(intro.isDisposed, isTrue);
        expect(intro.atlas.image.debugDisposed, isTrue);

        // Cancel and replace free the atlas without callbacks.
        final first = introOf(art, projection, geometry, onDone: () => log.add('first'));
        final second = introOf(art, projection, geometry, onDone: () => log.add('second'));
        controller
          ..play(first)
          ..play(second);
        expect(first.atlas.image.debugDisposed, isTrue);
        controller.cancel();
        expect(second.atlas.image.debugDisposed, isTrue);
        expect(log, ['layer 0', 'layer 1', 'done']);
        controller.dispose();
        art.dispose();
      });
    });
  });
}

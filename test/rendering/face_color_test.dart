import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/features/gameplay/widgets/tile_art.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/board_projection.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/rendering/board_renderer.dart';
import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_animation.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// RGBA pixels of an image, read once.
class _Pixels {
  _Pixels(this.width, this.bytes);

  static Future<_Pixels> of(ui.Image image) async =>
      _Pixels(image.width, (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!);

  final int width;
  final ByteData bytes;

  (int, int, int, int) at(Offset p) {
    final i = (p.dy.floor() * width + p.dx.floor()) * 4;
    return (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2), bytes.getUint8(i + 3));
  }
}

bool _bluish((int, int, int, int) p) => p.$3 > p.$1 + 20 && p.$4 == 255;
bool _warm((int, int, int, int) p) => p.$1 > p.$3 + 10 && p.$4 == 255;

LevelDefinition _withColors(LevelDefinition base, Map<String, String> faceColors) => LevelDefinition(
  levelId: base.levelId,
  title: base.title,
  board: base.board,
  tiles: base.tiles,
  faceColors: faceColors,
);

void main() {
  const style = TileStyle.classicIvory;
  const renderer = MahjongTileRenderer(style);

  group('face colours', () {
    test('a colour for every level colour name, all light and none green', () {
      expect(TileStyle.namedFaceColors.keys.toSet(), kFaceColorNames.toSet());
      for (final MapEntry(key: name, value: colour) in TileStyle.namedFaceColors.entries) {
        final hsl = HSLColor.fromColor(colour);
        expect(colour.a, 1, reason: '$name is opaque');
        expect(hsl.lightness, greaterThan(0.7), reason: '$name is light enough for symbols');
        expect(hsl.hue < 70 || hsl.hue > 170, isTrue, reason: '$name is not green (hue ${hsl.hue})');
        expect(colour, isNot(style.faceColor));
      }
      expect(TileStyle.faceColorNamed(null), isNull);
      expect(TileStyle.faceColorNamed('green'), isNull);
      expect(TileStyle.faceColorNamed('sky'), TileStyle.namedFaceColors['sky']);
    });

    test('each colour gives the style a coherent face (TileStyle.withFace)', () {
      expect(style.withFace(style.faceColor).faceColor, style.faceColor);
      for (final colour in TileStyle.namedFaceColors.values) {
        final s = style.withFace(colour);
        double l(Color c) => HSLColor.fromColor(c).lightness;
        expect(s.faceColor, colour);
        expect(l(s.faceHighlightColor), greaterThan(l(s.faceColor)));
        expect(l(s.faceShadeColor), lessThan(l(s.faceColor)));
        expect(l(s.sideColor), lessThan(l(s.faceColor)));
        expect(l(s.sideShadeColor), lessThan(l(s.sideColor)));
        expect(l(s.edgeColor), lessThan(l(s.faceShadeColor)));
      }
    });

    testWidgets('renderBody: ivory by default, the colour baked into the face', (tester) async {
      await tester.runAsync(() async {
        const face = Size(40, 52);
        final plain = await renderer.renderBody(face, 2);
        final ivory = await MahjongTileRenderer(style.withFace(style.faceColor)).renderBody(face, 2);
        final sky = await MahjongTileRenderer(style.withFace(TileStyle.namedFaceColors['sky']!)).renderBody(face, 2);
        final a = await plain.image.toByteData(), b = await ivory.image.toByteData();
        expect(b!.buffer.asUint8List(), a!.buffer.asUint8List(), reason: 'ivory is drawn exactly as before');
        final centre = (plain.faceOffset + face.center(Offset.zero)) * 2;
        expect(_warm((await _Pixels.of(plain.image)).at(centre)), isTrue);
        expect(_bluish((await _Pixels.of(sky.image)).at(centre)), isTrue);
        expect(sky.size, plain.size);
        expect(sky.faceOffset, plain.faceOffset);
        for (final body in [plain, ivory, sky]) {
          body.dispose();
        }
      });
    });

    testWidgets('renderFaceBodies: one body per known colour used', (tester) async {
      await tester.runAsync(() async {
        final bodies = await renderer.renderFaceBodies(const Size(30, 40), 1, {
          'A': 'sky',
          'B': 'sky',
          'C': 'gold',
          'D': 'mauve',
        });
        expect(bodies.keys.toSet(), {'sky', 'gold'});
        for (final body in bodies.values) {
          body.dispose();
        }
      });
    });
  });

  group('coloured pairs on the board', () {
    final plain = level([
      ('a1', 'A', 0, 0, 0),
      ('a2', 'A', 2, 0, 0),
      ('b1', 'B', 4, 0, 0),
      ('b2', 'B', 6, 0, 0),
      ('c1', 'C', 0, 2, 0),
      ('c2', 'C', 2, 2, 0),
    ]);
    const size = Size(240, 160);

    // No symbol art, so the face centre shows the body.
    Future<BoardArt> artFor(LevelDefinition lvl, Size face) async => BoardArt(
      body: await renderer.renderBody(face, 1),
      symbols: const {},
      faceBodies: await renderer.renderFaceBodies(face, 1, lvl.faceColors),
      faceColors: lvl.faceColors,
    );

    Future<(_Pixels, BoardProjection)> paintBoard(LevelDefinition lvl, {bool cached = false}) async {
      final geometry = BoardGeometry.build(lvl);
      final projection = boardProjectionFor(lvl, geometry, style, size);
      final art = await artFor(lvl, Size(projection.faceWidth, projection.faceHeight));
      final effects = BoardEffects(style: style);
      final layers = cached ? BoardLayers() : null;
      ui.Image draw() {
        final recorder = ui.PictureRecorder();
        BoardPainter(
          level: lvl,
          projection: projection,
          art: art,
          style: style,
          effects: effects,
          isRemaining: (_) => true,
          isFree: (_) => true,
          dimBlocked: false,
          stateVersion: 0,
          layers: layers,
        ).paint(Canvas(recorder), size);
        return recorder.endRecording().toImageSync(size.width.toInt(), size.height.toInt());
      }

      var image = draw();
      if (layers != null) {
        // The first paint starts the static image; the next one draws it.
        await layers.ready;
        image.dispose();
        image = draw();
      }
      final pixels = await _Pixels.of(image);
      image.dispose();
      layers?.dispose();
      effects.dispose();
      art.dispose();
      return (pixels, projection);
    }

    for (final cached in [false, true]) {
      testWidgets('coloured tiles take their colour, the rest stay ivory${cached ? ' (static cache)' : ''}', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final (ivory, projection) = await paintBoard(plain, cached: cached);
          final (coloured, _) = await paintBoard(_withColors(plain, {'A': 'sky'}), cached: cached);
          Offset centre(int i) => Offset(projection.faceRect(i).centerX, projection.faceRect(i).centerY);
          for (final i in [0, 1]) {
            expect(_warm(ivory.at(centre(i))), isTrue);
            expect(_bluish(coloured.at(centre(i))), isTrue, reason: 'tile $i is sky');
          }
          for (final i in [2, 3, 4, 5]) {
            expect(coloured.at(centre(i)), ivory.at(centre(i)), reason: 'tile $i stays ivory');
          }
        });
      });
    }

    testWidgets('unknown colour names draw ivory, exactly as a level without colours', (tester) async {
      await tester.runAsync(() async {
        final (ivory, _) = await paintBoard(plain);
        final (unknown, _) = await paintBoard(_withColors(plain, {'A': 'mauve', 'B': 'green'}));
        expect(unknown.bytes.buffer.asUint8List(), ivory.bytes.buffer.asUint8List());
      });
    });

    testWidgets('the intro sprite atlas bakes the colours in', (tester) async {
      await tester.runAsync(() async {
        final lvl = _withColors(plain, {'B': 'lavender', 'C': 'nope'});
        final geometry = BoardGeometry.build(lvl);
        final projection = boardProjectionFor(lvl, geometry, style, size);
        final face = Size(projection.faceWidth, projection.faceHeight);
        final art = await artFor(lvl, face);
        final atlas = BoardSpriteAtlas.build(
          level: lvl,
          art: art,
          style: style,
          face: face,
          tiles: geometry.drawOrder,
          shadeOf: (_) => 0,
          pixelRatio: 1,
        );
        expect(atlas.spriteCount, 3, reason: 'one look per symbol');
        final pixels = await _Pixels.of(atlas.image);
        (int, int, int, int) centre(int i) => pixels.at(atlas.spriteOf(i)!.topLeft + atlas.anchor);
        final lavender = centre(2);
        expect(lavender.$3, greaterThan(lavender.$2 + 10), reason: 'lavender: blue over green');
        expect(_warm(centre(0)), isTrue);
        expect(centre(4), centre(0), reason: 'an unknown colour is ivory');
        atlas.dispose();
        art.dispose();
      });
    });
  });

  testWidgets('TileArt (tray, flights, shatter snapshots) paints the colour of the symbol', (tester) async {
    await tester.runAsync(() async {
      final lvl = _withColors(
        level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('b1', 'B', 4, 0, 0), ('b2', 'B', 6, 0, 0)]),
        {'A': 'sky', 'B': 'mauve'},
      );
      const face = Size(40, 52);
      final art = await TileArt.load(
        level: lvl,
        registry: registry(const []),
        artwork: BundledContentSource((_) async => null),
        symbolArt: SymbolArtCache(),
        style: style,
        face: face,
        pixelRatio: 1,
      );
      expect(art.faceBodies.keys, ['sky']);
      expect(art.bodyFor('A'), same(art.faceBodies['sky']));
      expect(art.bodyFor('B'), same(art.body));
      expect(art.bodyFor('Z'), same(art.body));
      Future<(int, int, int, int)> centreOf(String code) async {
        final recorder = ui.PictureRecorder();
        art.paint(Canvas(recorder), code, const Offset(10, 10) & face);
        final image = recorder.endRecording().toImageSync(70, 80);
        final pixel = (await _Pixels.of(image)).at(const Offset(10, 10) + face.center(Offset.zero));
        image.dispose();
        return pixel;
      }

      expect(_bluish(await centreOf('A')), isTrue);
      expect(_warm(await centreOf('B')), isTrue);
      expect(await centreOf('B'), await centreOf('Z'));
      art.dispose();
    });
  });
}

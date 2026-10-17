import 'dart:typed_data';
import 'dart:ui';

import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TileStyle.classicIvory;
  const renderer = MahjongTileRenderer(style);

  test('symbols fill most of the face', () {
    final face = const Offset(0, 0) & const Size(60, 79);
    final symbol = renderer.symbolRect(face);
    expect(symbol.width / face.width, greaterThan(0.85));
    expect(face.contains(symbol.topLeft) && face.contains(symbol.bottomRight - const Offset(0.01, 0.01)), isTrue);
  });

  test('the fit margin covers the side walls', () {
    expect(style.edgeFraction, greaterThan(style.depthXFraction));
    expect(style.edgeFraction, greaterThan(style.depthYFraction / style.faceAspect));
  });

  test('walls and the cast shadow stay inside the fit margin, which never moves', () {
    // Board sizes (and the campaign generator's kFitEdgeFraction) hang on it.
    expect(style.edgeFraction, 0.2999);
    expect(style.depthYFraction / style.faceAspect + style.shadowReachFraction, lessThanOrEqualTo(style.edgeFraction));
    expect(style.depthXFraction + style.shadowReachXFraction, lessThanOrEqualTo(style.edgeFraction));
  });

  test('withFace recolours the face and its wall, nothing else', () {
    const gold = Color(0xFFF2C96B);
    final golden = style.withFace(gold);
    expect(golden.faceColor, gold);
    expect(golden.id, isNot(style.id));
    expect(golden.sideColor, isNot(style.sideColor));
    expect(golden.faceShadeColor, isNot(style.faceShadeColor));
    for (final (a, b) in [
      (golden.backColor, style.backColor),
      (golden.outlineColor, style.outlineColor),
      (golden.shadowColor, style.shadowColor),
    ]) {
      expect(a, b);
    }
    expect(golden.depthXFraction, style.depthXFraction);
    expect(golden.depthYFraction, style.depthYFraction);
    expect(golden.edgeFraction, style.edgeFraction);
    expect(golden.cornerRadiusFraction, style.cornerRadiusFraction);
    expect(style.withFace(TileStyle.ivoryFace).id, style.id);
  });

  testWidgets('the body: face, light wall over a green base, shadow down-right', (tester) async {
    await tester.runAsync(() async {
      const face = Size(40, 52);
      Future<(TileBodyImage, ByteData)> render(TileStyle style) async {
        final body = await MahjongTileRenderer(style).renderBody(face, 2);
        return (body, (await body.image.toByteData())!);
      }

      List<int> at((TileBodyImage, ByteData) rendered, Offset logical) {
        final (body, data) = rendered;
        final p = (body.faceOffset + logical) * 2;
        final i = (p.dy.floor() * body.image.width + p.dx.floor()) * 4;
        return [for (var k = 0; k < 4; k++) data.getUint8(i + k)];
      }

      double distance(List<int> rgba, Color color) {
        final c = [color.r, color.g, color.b].map((v) => v * 255).toList();
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          sum += (rgba[k] - c[k]) * (rgba[k] - c[k]);
        }
        return sum;
      }

      void expectNear(List<int> rgba, Color color) {
        final c = [color.r, color.g, color.b].map((v) => (v * 255).round()).toList();
        for (var k = 0; k < 3; k++) {
          expect(rgba[k], closeTo(c[k], 6), reason: '$rgba vs $color');
        }
      }

      final depthY = face.height * style.depthYFraction;
      for (final faceColor in [TileStyle.ivoryFace, const Color(0xFF9ED3F0)]) {
        final tile = style.withFace(faceColor);
        final rendered = await render(tile);
        // The middle of the face is the face colour.
        expectNear(at(rendered, face.center(Offset.zero)), faceColor);
        // Just under the face: the light wall, in the face's (darker) colour.
        final wall = at(rendered, Offset(face.width / 2, face.height + depthY * 0.2));
        expect(wall[3], 255);
        expect(distance(wall, tile.sideColor), lessThan(distance(wall, tile.backColor)));
        expect(wall.take(3).reduce((a, b) => a + b), lessThan(at(rendered, face.center(Offset.zero)).take(3).reduce((a, b) => a + b)));
        // Lower down: the green base.
        final base = at(rendered, Offset(face.width / 2, face.height + depthY * 0.8));
        expect(base[1], greaterThan(base[0]));
        expect(base[1], greaterThan(base[2]));
        // Past the base, down-right: the cast shadow; above-left: nothing.
        final shadow = at(rendered, Offset(face.width * 0.7, face.height + depthY + face.width * 0.04));
        expect(shadow[3], greaterThan(60));
        expect(at(rendered, const Offset(-3, -3))[3], 0);
        rendered.$1.dispose();
      }
    });
  });

  testWidgets('raised-tile shadow is offset down-right of the face', (tester) async {
    await tester.runAsync(() async {
      final shadow = await renderer.renderRaisedShadow(const Size(40, 52), 2);
      final body = await renderer.renderBody(const Size(40, 52), 2);
      // The image reaches further right/below the face than above/left of it.
      final right = shadow.size.width - shadow.faceOffset.dx - 40;
      final bottom = shadow.size.height - shadow.faceOffset.dy - 52;
      expect(right, greaterThan(shadow.faceOffset.dx));
      expect(bottom, greaterThan(shadow.faceOffset.dy));
      expect(shadow.image.width, (shadow.size.width * 2).ceil());
      shadow.dispose();
      body.dispose();
    });
  });
}

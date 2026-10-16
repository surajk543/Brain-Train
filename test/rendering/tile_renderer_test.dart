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

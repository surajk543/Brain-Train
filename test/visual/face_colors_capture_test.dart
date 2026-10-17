// Renders tile bodies in every face colour (ivory first, then
// `TileStyle.namedFaceColors`) with real symbol art at 31 px and 64 px face
// width, on the night felt, to check that symbols stay readable on each
// colour. Writes `$CAPTURE_DIR/face-colors-check.png`; skipped without
// CAPTURE_DIR:
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/face_colors_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby_support.dart';

const _symbols = ['halloween-bat', 'xmas-tree', 'halloween-moon', 'trip-camera', 'love-heart'];
const _faceWidths = [31.0, 64.0];
const _pixelRatio = 3.0;

/// One tile's cell, wide enough for its colour's label.
Size _cell(TileStyle style, double faceWidth, double gap) => Size(
  (faceWidth * (1 + style.depthXFraction) + gap).clamp(64.0, double.infinity),
  faceWidth / style.faceAspect * 1.2 + gap,
);

String _hex(Color c) => c.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');

void main() {
  final dir = Platform.environment['CAPTURE_DIR'];

  testWidgets('face colours with symbols at 31 and 64 px', skip: dir == null, (tester) async {
    await tester.runAsync(() async {
      await loadCaptureFonts();
      const style = TileStyle.classicIvory;
      const renderer = MahjongTileRenderer(style);
      final content = BundledContentSource((key) async {
        final file = File(key);
        return file.existsSync() ? file.readAsBytesSync() : null;
      });
      final available = [
        for (final name in _symbols)
          if (File('content/brain-train/symbols/v1/$name.webp').existsSync()) name,
      ];
      final colours = <(String, Color?)>[
        ('ivory', null),
        for (final MapEntry(:key, :value) in TileStyle.namedFaceColors.entries) (key, value),
      ];
      for (final (name, colour) in colours) {
        final s = style.faceShades(colour);
        // ignore: avoid_print
        print(
          '$name: face ${_hex(s.face)} highlight ${_hex(s.highlight)} shade ${_hex(s.shade)} '
          'catch ${_hex(s.catchLight)} bevel ${_hex(s.bevelShade)} edge ${_hex(s.edge)} '
          'side ${_hex(s.side)} sideShade ${_hex(s.sideShade)}',
        );
      }

      const pad = 18.0, gap = 10.0, labelHeight = 22.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(_pixelRatio);
      final panels = <(double, Offset)>[];
      var width = 0.0, top = pad;
      for (final faceWidth in _faceWidths) {
        final cell = _cell(style, faceWidth, gap);
        panels.add((faceWidth, Offset(pad + 64, top + labelHeight)));
        width = [width, pad * 2 + 64 + cell.width * colours.length].reduce((a, b) => a > b ? a : b);
        top += labelHeight + cell.height * available.length + pad;
      }
      final size = Size(width, top);
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF14513B));

      void label(String text, Offset at, {double fontSize = 11}) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontFamily: 'Roboto', fontSize: fontSize, color: const Color(0xFFF4E9C8)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, at);
        painter.dispose();
      }

      final cache = SymbolArtCache();
      for (final (faceWidth, origin) in panels) {
        final face = Size(faceWidth, faceWidth / style.faceAspect);
        final cell = _cell(style, faceWidth, gap);
        final bodies = [for (final (_, colour) in colours) await renderer.renderBody(face, _pixelRatio, faceColor: colour)];
        final box = renderer.symbolRect(Offset.zero & face).size;
        label('${faceWidth.round()} px', Offset(pad, origin.dy - labelHeight + 4), fontSize: 12);
        for (final (column, (name, _)) in colours.indexed) {
          label(name, Offset(origin.dx + column * cell.width, origin.dy - labelHeight + 4));
        }
        final symbolPaint = Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = style.symbolColorFilter;
        for (final (row, symbol) in available.indexed) {
          final art = await cache.resolve(
            SymbolDefinition(code: symbol, type: SymbolType.image, assetPath: 'symbols/v1/$symbol.webp'),
            content,
            box,
            _pixelRatio,
          );
          for (final (column, body) in bodies.indexed) {
            final faceRect = Offset(origin.dx + column * cell.width, origin.dy + row * cell.height) & face;
            body.paint(canvas, faceRect.topLeft, Paint()..filterQuality = FilterQuality.medium);
            art.paint(canvas, renderer.symbolRect(faceRect), symbolPaint);
          }
        }
        for (final body in bodies) {
          body.dispose();
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage((size.width * _pixelRatio).ceil(), (size.height * _pixelRatio).ceil());
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/face-colors-check.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
      picture.dispose();
      image.dispose();
      expect(available, isNotEmpty, reason: 'symbol art in content/brain-train/symbols/v1/');
    });
  });
}

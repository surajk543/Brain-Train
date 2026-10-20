// Close-ups of the tile look (body, side walls, cast shadows, face finish):
// a small three-layer board drawn exactly as the board's cached image draws it,
// on the felt, with 64-px and 31-px faces.
//
// Always checks that the tiles render. When CAPTURE_DIR is set, also writes
// `tiles-<look>-<face>px.png` there (3x pixels):
//
//   CAPTURE_DIR=/tmp/shots flutter test test/visual/tile_closeup_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/board_projection.dart';
import 'package:brain_train/rendering/board_renderer.dart';
import 'package:brain_train/rendering/mahjong_tile_renderer.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_animation.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/lobby_support.dart';
import '../helpers.dart';

const double _dpr = 3;

/// Felt centre and edge colours of the gameplay screen (`BrainTrainPalette`).
const _felts = {
  'night': (Color(0xFF1B6B45), Color(0xFF0E4A2F)),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tile close-ups: three layers on the felt at 64 px and 31 px', (tester) async {
    await tester.runAsync(() async {
      final AppServices services = await testServices();
      final snapshot = services.content.snapshot;
      final codes = <String>[];
      for (final entry in snapshot.playableEntries) {
        final level = snapshot.levels[entry.levelId];
        if (level == null) continue;
        for (final tile in level.tiles) {
          final symbol = snapshot.registry[tile.symbolCode];
          if (symbol != null && !symbol.isAnimated && !codes.contains(tile.symbolCode)) codes.add(tile.symbolCode);
        }
      }
      expect(codes.length, greaterThanOrEqualTo(9));
      // A 4x3 bottom layer, three tiles on half offsets above it, one on top.
      final board = level([
        for (var i = 0; i < 12; i++) ('b$i', codes[i % 9], (i % 4) * 2.0, (i ~/ 4) * 2.0, 0),
        ('m0', codes[0], 1, 1, 1),
        ('m1', codes[1], 3, 1, 1),
        ('m2', codes[4], 3, 3, 1),
        ('t0', codes[2], 2, 2, 2),
      ]);
      final geometry = BoardGeometry.build(board);
      const style = TileStyle.classicIvory;
      const renderer = MahjongTileRenderer(style);
      for (final faceWidth in [64.0, 31.0]) {
        final projection = BoardProjection.fit(
          geometry: geometry,
          tileWidth: 2,
          tileHeight: 2,
          width: 4000,
          height: 4000,
          faceAspect: style.faceAspect,
          edgeFraction: style.edgeFraction,
          layerOffsetX: board.board.layerOffsetX,
          layerOffsetY: board.board.layerOffsetY,
          padding: 0,
          maxFaceHeight: faceWidth / style.faceAspect,
        );
        final face = Size(projection.faceWidth, projection.faceHeight);
        final box = renderer.symbolRect(Offset.zero & face).size;
        final art = BoardArt(
          body: await renderer.renderBody(face, _dpr),
          raisedShadow: await renderer.renderRaisedShadow(face, _dpr),
          symbols: {
            for (final code in codes.take(9))
              code: await services.symbolArt.resolve(snapshot.registry[code]!, snapshot.artwork, box, _dpr),
          },
        );
        final rect = projection.boardRect;
        final margin = faceWidth * 0.6;
        final size = Size(rect.width + 2 * margin, rect.height + 2 * margin);
        final painter = BoardPainter(
          level: board,
          projection: projection,
          art: art,
          style: style,
          effects: BoardEffects(style: style, reduceMotion: true),
          isRemaining: (_) => true,
          isFree: (_) => true,
          dimBlocked: false,
          stateVersion: 0,
          symbolClock: SymbolAnimationClock(),
          pixelRatio: _dpr,
        );
        for (final MapEntry(key: look, value: (centre, edge)) in _felts.entries) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(_dpr);
          canvas.drawRect(
            Offset.zero & size,
            Paint()
              ..shader = RadialGradient(colors: [centre, edge], radius: 0.9).createShader(Offset.zero & size),
          );
          canvas.translate(margin - rect.left, margin - rect.top);
          painter.paint(canvas, Size(rect.right, rect.bottom));
          final picture = recorder.endRecording();
          final image = picture.toImageSync((size.width * _dpr).ceil(), (size.height * _dpr).ceil());
          picture.dispose();
          final dir = Platform.environment['CAPTURE_DIR'];
          if (dir != null) {
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$dir/tiles-$look-${faceWidth.round()}px.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          }
          image.dispose();
        }
        art.dispose();
      }
    });
  });
}

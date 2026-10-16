import 'dart:ui' as ui;

import 'package:brain_train/features/gameplay/widgets/tile_shatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TileSnapshot _tile(Rect face) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & face.size, Paint()..color = const Color(0xFFF4ECD8));
  final picture = recorder.endRecording();
  final image = picture.toImageSync((face.width * 2).ceil(), (face.height * 2).ceil());
  picture.dispose();
  return TileSnapshot(image: image, size: face.size, face: face, pixelRatio: 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const left = Rect.fromLTWH(20, 10, 40, 52);
  const right = Rect.fromLTWH(140, 10, 40, 52);

  group('TileShatterController', () {
    test('strike, impact once at the end of the strike, shatter, done once; images freed', () {
      final shatters = TileShatterController();
      final log = <String>[];
      final a = _tile(right), b = _tile(left);
      final shatter = shatters.start(a, b, onImpact: () => log.add('impact'), onDone: () => log.add('done'));
      expect(shatter.left, b, reason: 'ordered left to right');
      expect(shatter.contact, const Offset(100, 36), reason: 'they meet halfway');
      expect(shatter.shardCount, 36, reason: '18 shards per tile');
      shatters.tick(const Duration(seconds: 5)); // its clock starts here
      shatters.tick(const Duration(seconds: 5) + kStrikeDuration - const Duration(milliseconds: 1));
      expect(log, isEmpty);
      shatters.tick(const Duration(seconds: 5) + kStrikeDuration);
      expect(log, ['impact']);
      expect(shatter.impacted, isTrue);
      shatters.tick(const Duration(seconds: 5) + kStrikeDuration + kImpactDuration + kShatterDuration ~/ 2);
      expect(log, ['impact']);
      expect(shatters.isRunning, isTrue);
      shatters.tick(const Duration(seconds: 5) + PairShatter.total);
      expect(log, ['impact', 'done']);
      expect(shatters.isRunning, isFalse);
      expect(a.image.debugDisposed, isTrue);
      expect(b.image.debugDisposed, isTrue);
      shatters.tick(const Duration(seconds: 9));
      expect(log, ['impact', 'done']);
      shatters.dispose();
    });

    test('the whole effect lasts strike + impact + about 600 ms of shards', () {
      expect(kStrikeDuration, const Duration(milliseconds: 180));
      expect(kImpactDuration, const Duration(milliseconds: 80));
      expect(kShatterDuration, const Duration(milliseconds: 600));
      expect(PairShatter.total, const Duration(milliseconds: 860));
    });

    test('several shatters run side by side; cancel drops them without callbacks', () {
      final shatters = TileShatterController();
      final log = <String>[];
      final tiles = [_tile(left), _tile(right), _tile(left.shift(const Offset(0, 80))), _tile(right.shift(const Offset(0, 80)))];
      shatters
        ..start(tiles[0], tiles[1], onDone: () => log.add('one'))
        ..tick(Duration.zero)
        ..tick(const Duration(milliseconds: 300))
        ..start(tiles[2], tiles[3], onDone: () => log.add('two'))
        ..tick(const Duration(milliseconds: 400));
      expect(shatters.shatters, hasLength(2));
      expect(shatters.shatters.last.elapsed, Duration.zero, reason: 'the second clock starts at its first tick');
      shatters.tick(PairShatter.total);
      expect(log, ['one']);
      shatters.cancelAll();
      expect(log, ['one']);
      expect(shatters.isRunning, isFalse);
      expect(tiles.every((t) => t.image.debugDisposed), isTrue);
      shatters.dispose();
    });
  });

  testWidgets('the overlay ticks only while a shatter runs and draws every phase', (tester) async {
    final shatters = TileShatterController();
    await tester.pumpWidget(TileShatterOverlay(controller: shatters));
    expect(tester.binding.hasScheduledFrame, isFalse);
    var done = false;
    shatters.start(_tile(left), _tile(right), onDone: () => done = true);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    for (final step in [90, 100, 40, 300, 300]) {
      await tester.pump(Duration(milliseconds: step));
      expect(tester.takeException(), isNull);
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    shatters.dispose();
  });
}

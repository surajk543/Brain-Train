import 'dart:io';
import 'dart:typed_data';

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/features/gameplay/widgets/tile_shatter.dart';
import 'package:brain_train/features/gameplay/widgets/tray_view.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

final Uint8List _pulse = File('test/fixtures/pulse.lottie.json').readAsBytesSync();
const String _pulsePath = 'animated-symbols/pulse.json';

final SymbolRegistry _registry = SymbolRegistry(
  registryVersion: 'test',
  symbols: {
    for (final code in ['A', 'B', 'C', 'D'])
      code: SymbolDefinition(code: code, type: SymbolType.text, value: code),
    'PULSE': const SymbolDefinition(code: 'PULSE', type: SymbolType.lottie, assetPath: _pulsePath),
  },
);

final ContentSource _artwork = BundledContentSource(
  (key) async => key.endsWith(_pulsePath) ? _pulse : null,
);

final _level = level([
  for (final (i, code) in ['A', 'B', 'C', 'D', 'A', 'B', 'C', 'D'].indexed)
    ('${code.toLowerCase()}${i < 4 ? 1 : 2}', code, i * 4.0, 0.0, 0),
  ('p1', 'PULSE', 40, 0, 0),
  ('p2', 'PULSE', 44, 0, 0),
]);

void main() {
  group('TrayController', () {
    test('reserves slots left to right for incoming tiles and shows them once landed', () {
      final tray = TrayController();
      expect(tray.capacity, 4);
      expect(tray.expect('a1'), 0);
      expect(tray.expect('b1'), 1);
      expect(tray.expect('a1'), 0, reason: 'already expected');
      expect(tray.items.map((i) => i.phase), [TrayItemPhase.incoming, TrayItemPhase.incoming]);
      expect(tray.isBusy, isTrue);
      tray.land('b1');
      expect(tray.itemOf('b1')!.phase, TrayItemPhase.settled);
      expect(tray.itemOf('b1')!.flew, isTrue);
      tray
        ..land('b1')
        ..land('zz');
      expect(tray.items, hasLength(2));
    });

    test('a matched pair strikes only once both tiles have landed, then the tray re-packs', () {
      final ready = <(String, String, bool)>[];
      final tray = TrayController()
        ..onPairReady = ((a, b, {required animate}) => ready.add((a, b, animate)))
        ..restore(['a1', 'b1']);
      expect(tray.expect('a2'), 2);
      tray.clearPair('a1', 'a2');
      expect(tray.itemOf('a1')!.phase, TrayItemPhase.settled, reason: 'a2 is still flying');
      expect(tray.itemOf('a1')!.partnerId, 'a2');
      expect(ready, isEmpty);
      tray.land('a2');
      expect(ready, [('a2', 'a1', true)]);
      expect(tray.itemOf('a1')!.phase, TrayItemPhase.clearing);
      expect(tray.itemOf('a2')!.phase, TrayItemPhase.clearing);
      expect(tray.indexOf('b1'), 1, reason: 'positions hold while the pair strikes');
      tray.impact();
      expect(tray.impacts, 1);
      tray.completeClear('a2');
      expect(tray.items.map((i) => i.tileId), ['b1']);
      expect(tray.isBusy, isFalse);
    });

    test('without an owner for the strike, or with instant clears, a landed pair leaves at once', () {
      final plain = TrayController()..restore(['a1']);
      plain
        ..expect('a2')
        ..clearPair('a1', 'a2')
        ..land('a2');
      expect(plain.items, isEmpty);

      final ready = <bool>[];
      final instant = TrayController()
        ..instantClears = true
        ..onPairReady = ((a, b, {required animate}) => ready.add(animate))
        ..restore(['a1']);
      instant
        ..expect('a2')
        ..clearPair('a1', 'a2')
        ..land('a2');
      expect(instant.items, isEmpty);
      expect(ready, [false], reason: 'the feedback still plays');
    });

    test('a pair pushed out by rapid taps before it struck still reports, without a strike', () {
      final ready = <bool>[];
      final tray = TrayController()
        ..onPairReady = ((a, b, {required animate}) => ready.add(animate))
        ..restore(['a1', 'b1', 'c1']);
      tray
        ..expect('a2')
        ..clearPair('a1', 'a2')
        ..expect('d1');
      expect(ready, [false]);
      expect(tray.items.map((i) => i.tileId), ['b1', 'c1', 'd1']);
      tray.land('a2');
      expect(ready, [false], reason: 'its flight lands on nothing');
    });

    test('tiles tapped while a pair bursts queue after it', () {
      final tray = TrayController()..restore(['a1']);
      tray
        ..expect('a2')
        ..clearPair('a1', 'a2');
      expect(tray.expect('c1'), 2);
      tray
        ..land('a2')
        ..completeClear('a1');
      expect(tray.indexOf('c1'), 0);
    });

    test('out of room while matched pairs are on show, the oldest pair leaves at once', () {
      final tray = TrayController()..restore(['a1', 'b1', 'c1']);
      tray
        ..expect('a2')
        ..clearPair('a1', 'a2');
      expect(tray.items, hasLength(4));
      expect(tray.expect('d1'), 2);
      expect(tray.items.map((i) => i.tileId), ['b1', 'c1', 'd1']);
      // The flushed tile's flight still lands; nothing happens.
      tray.land('a2');
      expect(tray.items, hasLength(3));
    });

    test('with instant clears, a landed pair leaves without bursting', () {
      final tray = TrayController()
        ..instantClears = true
        ..restore(['a1', 'b1']);
      tray
        ..expect('a2')
        ..clearPair('a1', 'a2')
        ..land('a2');
      expect(tray.items.map((i) => i.tileId), ['b1']);
    });

    test('a full tray shows as full only once its last tile has landed', () {
      final tray = TrayController()..restore(['a1', 'b1', 'c1']);
      tray
        ..expect('d1')
        ..markFull();
      expect(tray.isFull, isTrue);
      expect(tray.showsFull, isFalse);
      tray.land('d1');
      expect(tray.showsFull, isTrue);
      tray.reset();
      expect(tray.items, isEmpty);
      expect(tray.isFull, isFalse);
    });

    test('on revive, slots empty in place as tiles depart; then the tray is empty', () {
      final tray = TrayController()..restore(['a1', 'b1', 'c1']);
      tray
        ..expect('d1')
        ..markFull()
        ..land('d1')
        ..returnAll();
      expect(tray.isFull, isFalse);
      tray.depart('b1');
      expect(tray.itemOf('b1')!.phase, TrayItemPhase.departed);
      expect(tray.indexOf('c1'), 2, reason: 'no slide while the others wait to leave');
      for (final id in ['a1', 'c1', 'd1']) {
        tray.depart(id);
      }
      expect(tray.items, isEmpty);
    });

    test('restored tiles are settled and do not pop', () {
      final tray = TrayController()..restore(['a1', 'b1']);
      expect(tray.items.every((i) => i.phase == TrayItemPhase.settled && !i.flew), isTrue);
      var notified = 0;
      tray
        ..addListener(() => notified++)
        ..clearPair('zz', 'yy');
      expect(notified, 0, reason: 'unknown tiles are ignored');
    });
  });

  group('TrayLayout', () {
    // Screen width and the tray's largest face width (as GameScreen picks it:
    // 6.2% of the screen height, 34-46 px) on the two reference phones.
    for (final (width, maxFace) in [(360.0, 39.68), (411.0, 46.0)]) {
      for (final capacity in [2, 3, 4, 5]) {
        test('$capacity wells fit ${width.toInt()} px, centred, apart, in the frame', () {
          final layout = TrayLayout.fit(
            width: width,
            capacity: capacity,
            style: TileStyle.classicIvory,
            maxFaceWidth: maxFace,
          );
          expect(layout.wells, hasLength(capacity));
          expect(layout.faces, hasLength(capacity));
          expect(layout.panel.left, greaterThanOrEqualTo(0));
          expect(layout.panel.right, lessThanOrEqualTo(width));
          expect((layout.panel.left - (width - layout.panel.right)).abs(), lessThan(0.01), reason: 'centred');
          for (var i = 0; i < capacity; i++) {
            final well = layout.wells[i].outerRect;
            expect(layout.panel.contains(well.topLeft) && layout.panel.contains(well.bottomRight - const Offset(0.01, 0.01)), isTrue);
            expect(well.contains(layout.faces[i].center), isTrue);
            if (i > 0) expect(well.left, greaterThan(layout.wells[i - 1].outerRect.right));
          }
          expect(layout.faceSize.width, greaterThanOrEqualTo(34), reason: 'tray tiles stay readable');
        });
      }
    }

    test('a 5-slot tray at 360 px still has full-size faces', () {
      final four = TrayLayout.fit(width: 360, capacity: 4, style: TileStyle.classicIvory, maxFaceWidth: 39.68);
      final five = TrayLayout.fit(width: 360, capacity: 5, style: TileStyle.classicIvory, maxFaceWidth: 39.68);
      expect(five.faceSize, four.faceSize);
      expect(five.size.height, four.size.height);
      expect(five.panel.width, greaterThan(four.panel.width));
    });
  });

  group('TrayView', () {
    late TrayController tray;
    final key = GlobalKey<TrayViewState>();

    Future<void> pumpTray(WidgetTester tester, {bool reduceMotion = false, double width = 360}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 640)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: TrayView(
                  key: key,
                  controller: tray,
                  level: _level,
                  registry: _registry,
                  artwork: _artwork,
                  symbolArt: SymbolArtCache(),
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

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      tray.dispose();
    }

    setUp(() => tray = TrayController());

    for (var count = 0; count <= 4; count++) {
      testWidgets('renders $count tiles without exceptions at phone widths', (tester) async {
        final ids = ['a1', 'b1', 'c1', 'd1'].take(count).toList();
        tray.restore(ids);
        for (final width in [360.0, 411.0, 280.0]) {
          await pumpTray(tester, width: width);
          await loadArt(tester);
          expect(tester.takeException(), isNull);
          for (final id in ids) {
            expect(find.byKey(ValueKey(id)), findsOneWidget, reason: '$id at $width');
          }
          expect(find.bySemanticsLabel(count == 4 ? 'Tray, 4 of 4 tiles' : 'Tray, $count of 4 tiles'), findsOneWidget);
          final size = tester.getSize(find.byType(TrayView));
          expect(size.width, width);
          expect(size.height, inInclusiveRange(48, 110));
        }
        await leave(tester);
      });
    }

    testWidgets('slot rects run left to right inside the tray; targets follow the tile', (tester) async {
      await pumpTray(tester, width: 411);
      await loadArt(tester);
      final state = key.currentState!;
      final bounds = tester.getRect(find.byType(TrayView));
      final slots = [for (var i = 0; i < 4; i++) state.slotRect(i)!];
      for (var i = 0; i < 4; i++) {
        expect(bounds.inflate(1).contains(slots[i].topLeft) && bounds.inflate(1).contains(slots[i].bottomRight), isTrue);
        expect(slots[i].size, state.faceSize);
        if (i > 0) expect(slots[i].left, greaterThan(slots[i - 1].right));
      }
      expect(state.targetRectFor('a1'), isNull);
      tray.expect('a1');
      tray.expect('b1');
      expect(state.targetRectFor('b1'), slots[1]);
      expect(state.art, isNotNull);
      await leave(tester);
    });

    testWidgets('a landed pair hands over to the strike; afterwards the rest slide left', (tester) async {
      final snapshots = <TileSnapshot?>[];
      tray
        ..onPairReady = (a, b, {required animate}) {
          // What the director does: picture both tiles for the shatter.
          snapshots
            ..add(key.currentState!.snapshot(a))
            ..add(key.currentState!.snapshot(b));
        }
        ..restore(['a1', 'b1']);
      await pumpTray(tester);
      await loadArt(tester);
      tray.expect('a2');
      await tester.pump();
      expect(find.byKey(const ValueKey('a2')), findsNothing, reason: 'drawn by the flight while incoming');
      final before = tester.getRect(find.byKey(const ValueKey('b1')));
      final slot0 = key.currentState!.slotRect(0)!;
      tray
        ..clearPair('a1', 'a2')
        ..land('a2');
      await tester.pump();
      expect(snapshots, hasLength(2));
      // (a2, a1): the tile that just landed, then its partner in slot 0.
      final first = snapshots.last!;
      expect(first.face, slot0, reason: 'pictured where it sat');
      expect(first.image.width, greaterThan(first.face.width), reason: 'at device pixels, depth included');
      expect(find.byKey(const ValueKey('a1')), findsNothing, reason: 'the shatter overlay draws the pair now');
      expect(find.byKey(const ValueKey('a2')), findsNothing);
      expect(find.byKey(const ValueKey('b1')), findsOneWidget, reason: 'the rest hold their slots');
      expect(tester.getRect(find.byKey(const ValueKey('b1'))), before);
      tray
        ..impact()
        ..completeClear('a1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final s in snapshots) {
        s!.dispose();
      }
      expect(find.byKey(const ValueKey('a1')), findsNothing);
      final after = tester.getRect(find.byKey(const ValueKey('b1')));
      expect(after.left, lessThan(before.left));
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'idle once effects end');
      await leave(tester);
    });

    testWidgets('a full tray shakes and pulses red, then settles', (tester) async {
      tray.restore(['a1', 'b1', 'c1']);
      await pumpTray(tester);
      await loadArt(tester);
      tray
        ..expect('d1')
        ..markFull();
      await tester.pump();
      tray.land('d1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.bySemanticsLabel('Tray full'), findsOneWidget);
      final mid = tester.getRect(find.byKey(const ValueKey('a1')));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 16));
      final rest = tester.getRect(find.byKey(const ValueKey('a1')));
      expect(mid.left, isNot(rest.left), reason: 'shaking mid-effect');
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      tray.reset();
      await tester.pump();
      expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('departing tiles leave their wells; the full glow goes on revive', (tester) async {
      tray.restore(['a1', 'b1', 'c1']);
      await pumpTray(tester);
      await loadArt(tester);
      tray
        ..expect('d1')
        ..markFull()
        ..land('d1');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.bySemanticsLabel('Tray full'), findsOneWidget);
      tray
        ..returnAll()
        ..depart('a1');
      await tester.pump();
      expect(find.byKey(const ValueKey('a1')), findsNothing);
      expect(find.byKey(const ValueKey('b1')), findsOneWidget);
      expect(find.bySemanticsLabel('Tray, 3 of 4 tiles'), findsOneWidget);
      for (final id in ['b1', 'c1', 'd1']) {
        tray.depart(id);
      }
      await tester.pump();
      expect(find.bySemanticsLabel('Tray, 0 of 4 tiles'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
      await leave(tester);
    });

    testWidgets('animated symbols play in the tray and stop when they leave', (tester) async {
      tray.restore(['p1']);
      await pumpTray(tester);
      await loadArt(tester);
      final state = key.currentState!;
      expect(state.art!.isAnimated('PULSE'), isTrue);
      expect(state.symbolClock.isRunning, isTrue);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      tray.reset();
      await tester.pump();
      expect(state.symbolClock.isRunning, isFalse);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await leave(tester);
    });

    testWidgets('with reduced motion, pairs clear at once and symbols stay still', (tester) async {
      tray.restore(['p1', 'a1']);
      await pumpTray(tester, reduceMotion: true);
      await loadArt(tester);
      expect(tray.instantClears, isTrue);
      expect(key.currentState!.symbolClock.isRunning, isFalse);
      tray
        ..expect('a2')
        ..clearPair('a1', 'a2')
        ..land('a2');
      await tester.pump();
      expect(tray.items.map((i) => i.tileId), ['p1']);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await leave(tester);
    });
  });
}

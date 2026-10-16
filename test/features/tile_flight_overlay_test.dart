import 'dart:ui' as ui;

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/widgets/tile_art.dart';
import 'package:brain_train/features/gameplay/widgets/tile_flight_overlay.dart';
import 'package:brain_train/features/gameplay/widgets/tile_shatter.dart';
import 'package:brain_train/features/gameplay/widgets/tray_view.dart';
import 'package:brain_train/rendering/symbol_art.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// A plain tile-sized image standing in for a tray snapshot.
TileSnapshot _snapshot(Rect face) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & face.size, Paint()..color = const Color(0xFFF4ECD8));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(face.width.ceil(), face.height.ceil());
  picture.dispose();
  return TileSnapshot(image: image, size: face.size, face: face, pixelRatio: 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const from = Rect.fromLTWH(100, 500, 40, 52);
  const to = Rect.fromLTWH(20, 30, 30, 39);
  const d = kTileFlightDuration;

  group('TileFlightController', () {
    test('flies from the board face to the slot and lands once', () {
      final flights = TileFlightController();
      var landed = 0;
      final flight = flights.launch(tileId: 'a1', symbolCode: 'A', from: from, to: () => to, onLanded: () => landed++)!;
      expect(flights.isFlying, isTrue);
      expect(flight.rect, from, reason: 'starts on the board');
      flights.tick(const Duration(seconds: 3)); // the flight's clock starts at its first tick
      expect(flight.progress, 0);
      flights.tick(const Duration(seconds: 3) + d ~/ 2);
      expect(flight.progress, closeTo(0.5, 0.01));
      expect(from.inflate(60).expandToInclude(to).contains(flight.rect.center), isTrue);
      expect(landed, 0);
      flights.tick(const Duration(seconds: 3) + d);
      expect(landed, 1);
      expect(flights.isFlying, isFalse);
      flights.tick(const Duration(seconds: 4));
      expect(landed, 1);
    });

    test('the path starts and ends exactly on the faces and lifts mid-air', () {
      expect(TileFlight.rectAt(from, to, 0), from);
      expect(TileFlight.rectAt(from, to, 1), to);
      final mid = TileFlight.rectAt(from, to, 0.5);
      final plain = Size.lerp(from.size, to.size, 0.5)!;
      expect(mid.width, greaterThan(plain.width));
      // Rises first, then glides across: early on it is higher, and still
      // nearer its start column, than a straight line at the same pace.
      final quarter = TileFlight.rectAt(from, to, 0.25).center;
      final straight = Offset.lerp(from.center, to.center, Curves.easeInOutCubic.transform(0.25))!;
      expect(quarter.dy, lessThan(straight.dy));
      expect(quarter.dx, greaterThan(straight.dx));
    });

    test('follows its target when the tray re-packs mid-flight', () {
      final flights = TileFlightController();
      var target = to;
      final flight = flights.launch(tileId: 'a1', symbolCode: 'A', from: from, to: () => target)!;
      flights.tick(Duration.zero);
      target = to.shift(const Offset(-60, 0));
      flights.tick(d ~/ 2);
      expect(flight.to, target);
      // A target that goes away keeps the last known one.
      flights.launch(tileId: 'b1', symbolCode: 'B', from: from, to: () => null);
      expect(flights.flights.last.to, from);
    });

    test('a delayed flight waits, takes off (onStart), then lands after its own duration', () {
      final flights = TileFlightController();
      final log = <String>[];
      final flight = flights.launch(
        tileId: 'a1',
        symbolCode: 'A',
        from: to,
        to: () => from,
        kind: FlightKind.toBoard,
        duration: kTileReturnDuration,
        delay: kTileReturnStagger * 2,
        onStart: () => log.add('start'),
        onLanded: () => log.add('landed'),
      )!;
      flights.tick(Duration.zero);
      expect(flight.started, isFalse);
      flights.tick(kTileReturnStagger);
      expect(log, isEmpty, reason: 'still waiting');
      flights.tick(kTileReturnStagger * 2);
      expect(log, ['start']);
      expect(flight.rect, to, reason: 'takes off from the tray slot');
      flights.tick(kTileReturnStagger * 2 + kTileReturnDuration ~/ 2);
      expect(log, ['start']);
      flights.tick(kTileReturnStagger * 2 + kTileReturnDuration);
      expect(log, ['start', 'landed']);
    });

    test('a return flight ends exactly on the board face after a small settle', () {
      expect(TileFlight.returnRectAt(to, from, 0), to);
      expect(TileFlight.returnRectAt(to, from, TileFlight.returnTravel), from);
      final settling = TileFlight.returnRectAt(to, from, (1 + TileFlight.returnTravel) / 2);
      expect(settling.center, from.center);
      expect(settling.width, lessThan(from.width), reason: 'a small squash on landing');
      expect(TileFlight.returnRectAt(to, from, 1), from);
    });

    test('zero duration lands at once; cancel drops flights; landAll lands them', () {
      final instant = TileFlightController(duration: Duration.zero);
      var landed = <String>[];
      expect(instant.launch(tileId: 'a1', symbolCode: 'A', from: from, to: () => to, onLanded: () => landed.add('a1')), isNull);
      expect(landed, ['a1']);
      expect(instant.isFlying, isFalse);

      final flights = TileFlightController();
      landed = [];
      flights
        ..launch(tileId: 'a1', symbolCode: 'A', from: from, to: () => to, onLanded: () => landed.add('a1'))
        ..launch(tileId: 'b1', symbolCode: 'B', from: from, to: () => to, onLanded: () => landed.add('b1'))
        ..cancelAll();
      expect(flights.isFlying, isFalse);
      expect(landed, isEmpty);
      flights
        ..launch(tileId: 'c1', symbolCode: 'C', from: from, to: () => to, onLanded: () => landed.add('c1'))
        ..landAll();
      expect(landed, ['c1']);
    });
  });

  group('TileFlightOverlay', () {
    testWidgets('ticks only while a tile is in the air and draws it with tile art', (tester) async {
      final reg = registry(['A']);
      final lvl = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0)]);
      late TileArt art;
      await tester.runAsync(() async {
        art = await TileArt.load(
          level: lvl,
          registry: reg,
          artwork: BundledContentSource((_) async => null),
          symbolArt: SymbolArtCache(),
          style: TileStyle.classicIvory,
          face: const Size(40, 52),
          pixelRatio: 2,
        );
      });
      final flights = TileFlightController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TileFlightOverlay(controller: flights, art: () => art),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      var landed = false;
      flights.launch(tileId: 'a1', symbolCode: 'A', from: from, to: () => to, onLanded: () => landed = true);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      await tester.pump(d ~/ 2);
      expect(flights.flights.single.progress, closeTo(0.5, 0.05));
      await tester.pump(d ~/ 2);
      expect(landed, isTrue);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      art.dispose();
    });
  });

  group('TrayFlightDirector', () {
    // A B C D A B C D, all free.
    final board = level([
      for (final (i, code) in ['A', 'B', 'C', 'D', 'A', 'B', 'C', 'D'].indexed)
        ('${code.toLowerCase()}${i < 4 ? 1 : 2}', code, i * 4.0, 0.0, 0),
    ]);
    final reg = registry(['A', 'B', 'C', 'D']);
    const entry = LevelManifestEntry(levelId: 'test-level', order: 1, title: 'Test', ref: ContentRef(url: 'levels/t.json'));

    late GameController game;
    late TrayController tray;
    late TileFlightController flights;
    late TrayFlightDirector director;

    Future<void> start({SavedGame? resume, bool instant = false}) async {
      SharedPreferences.setMockInitialValues({});
      game = GameController(
        entry: entry,
        level: board,
        registry: reg,
        progress: await ProgressRepository.open(),
        settings: await SettingsRepository.open(),
        resume: resume,
      );
      tray = TrayController();
      flights = TileFlightController();
      director = TrayFlightDirector(
        game: game,
        tray: tray,
        flights: flights,
        boardRect: (id) => from.shift(Offset(game.engine.indexOf(id)! * 50.0, 0)),
        trayRect: (id) {
          final index = tray.indexOf(id);
          return index < 0 ? null : to.shift(Offset(index * 40.0, 0));
        },
        instant: instant,
      );
    }

    Future<void> tap(List<String> ids) async {
      ids.forEach(game.tapTile);
      await Future<void>.delayed(Duration.zero);
    }

    void landFlights() {
      flights
        ..tick(Duration.zero)
        ..tick(d);
    }

    tearDown(() async {
      await director.dispose();
      game.dispose();
    });

    test('a tapped tile flies from its board face to its slot, then lands', () async {
      await start();
      await tap(['b1']);
      expect(tray.items.single.phase, TrayItemPhase.incoming);
      final flight = flights.flights.single;
      expect(flight.tileId, 'b1');
      expect(flight.symbolCode, 'B');
      expect(flight.from, from.shift(const Offset(50, 0)));
      expect(flight.to, to);
      landFlights();
      expect(tray.items.single.phase, TrayItemPhase.settled);
    });

    test('without a shatter, a match clears once the arriving tile lands; the tray catches up', () async {
      await start();
      await tap(['a1', 'b1', 'a2']);
      expect(tray.items.map((i) => i.tileId), ['a1', 'b1', 'a2']);
      expect(flights.flights, hasLength(3));
      landFlights();
      expect(tray.items.map((i) => i.tileId), ['b1']);
      expect(tray.items.map((i) => i.tileId), game.state.tray, reason: 'caught up with the engine');
    });

    test('with a shatter: strike after landing, impact feedback and tray shake, then the slots free up', () async {
      await start();
      await director.dispose();
      final shatters = TileShatterController();
      final impacts = <int>[];
      director = TrayFlightDirector(
        game: game,
        tray: tray,
        flights: flights,
        boardRect: (id) => from.shift(Offset(game.engine.indexOf(id)! * 50.0, 0)),
        trayRect: (id) {
          final index = tray.indexOf(id);
          return index < 0 ? null : to.shift(Offset(index * 40.0, 0));
        },
        shatters: shatters,
        snapshotTile: (id) {
          final index = tray.indexOf(id);
          return index < 0 ? null : _snapshot(to.shift(Offset(index * 40.0, 0)));
        },
      );
      tray.addListener(() => impacts.add(tray.impacts));
      await tap(['a1', 'b1', 'a2']);
      landFlights();
      expect(shatters.isRunning, isTrue);
      expect(tray.itemOf('a1')!.phase, TrayItemPhase.clearing);
      shatters.tick(Duration.zero);
      expect(tray.impacts, 0);
      shatters.tick(kStrikeDuration);
      expect(tray.impacts, 1, reason: 'the tray shakes on impact');
      expect(tray.items, hasLength(3), reason: 'slots held while the shards fly');
      shatters.tick(PairShatter.total);
      expect(shatters.isRunning, isFalse);
      expect(tray.items.map((i) => i.tileId), ['b1']);
      shatters.dispose();
    });

    test('tray full marks the tray; restart cancels flights and empties it', () async {
      await start();
      await tap(['a1', 'b1', 'c1', 'd1']);
      expect(tray.isFull, isTrue);
      expect(tray.showsFull, isFalse);
      landFlights();
      expect(tray.showsFull, isTrue);
      await tap(['a2']);
      expect(flights.isFlying, isFalse, reason: 'taps after losing do nothing');
      game.restart();
      await Future<void>.delayed(Duration.zero);
      expect(tray.items, isEmpty);
      expect(tray.isFull, isFalse);
    });

    test('revive flies the tray tiles back, staggered, hidden on the board until each lands', () async {
      await start();
      await director.dispose(); // replaced by one that hides and reveals
      final hidden = <String>{};
      director = TrayFlightDirector(
        game: game,
        tray: tray,
        flights: flights,
        boardRect: (id) => from.shift(Offset(game.engine.indexOf(id)! * 50.0, 0)),
        trayRect: (id) {
          final index = tray.indexOf(id);
          return index < 0 ? null : to.shift(Offset(index * 40.0, 0));
        },
        hideOnBoard: hidden.addAll,
        revealOnBoard: hidden.remove,
      );
      await tap(['a1', 'b1', 'c1', 'd1']);
      landFlights();
      expect(tray.showsFull, isTrue);
      expect(game.revive(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(hidden, {'a1', 'b1', 'c1', 'd1'});
      expect(tray.isFull, isFalse);
      final back = flights.flights.where((f) => f.kind == FlightKind.toBoard).toList();
      expect(back.map((f) => f.tileId), ['a1', 'b1', 'c1', 'd1']);
      expect(back[1].from, to.shift(const Offset(40, 0)), reason: 'from its tray slot');
      expect(back[1].to, from.shift(const Offset(50, 0)), reason: 'to its board face');
      expect(back.map((f) => f.delay), [for (var i = 0; i < 4; i++) kTileReturnStagger * i]);
      flights.tick(Duration.zero);
      expect(tray.itemOf('a1')!.phase, TrayItemPhase.departed);
      expect(tray.itemOf('b1')!.phase, TrayItemPhase.settled, reason: 'waits for its turn');
      flights.tick(kTileReturnDuration);
      expect(hidden, {'b1', 'c1', 'd1'}, reason: 'a1 landed');
      flights.tick(kTileReturnDuration + kTileReturnStagger * 3);
      expect(hidden, isEmpty);
      expect(tray.items, isEmpty);
    });

    test('a resumed game shows its tray at once; instant mode lands without flights', () async {
      await start(
        resume: SavedGame(levelId: 'test-level', levelUrl: 'levels/t.json', history: ['a1', 'b1'], elapsedMs: 0),
        instant: true,
      );
      expect(tray.items.map((i) => i.tileId), ['a1', 'b1']);
      expect(tray.items.every((i) => i.phase == TrayItemPhase.settled), isTrue);
      await tap(['c1']);
      expect(flights.isFlying, isFalse);
      expect(tray.itemOf('c1')!.phase, TrayItemPhase.settled);
    });
  });
}

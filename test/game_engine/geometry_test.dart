import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/board_grid.dart';
import 'package:brain_train/game_engine/geometry/board_projection.dart';
import 'package:brain_train/game_engine/geometry/tile_availability.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  int idx(BoardGeometry g, String id) => g.indexById[id]!;

  group('free-tile rules', () {
    test('a row: ends are free, the middle is side-blocked', () {
      final g = BoardGeometry.build(level([('a', 'X', 0, 0, 0), ('b', 'X', 2, 0, 0), ('c', 'X', 4, 0, 0)]));
      final free = TileAvailabilityCalculator(g).freeTiles(TileMask.all(3)).map((i) => g.tiles[i]).toList();
      expect(free.map((t) => t.index), [idx(g, 'a'), idx(g, 'c')]);
      expect(g.leftNeighbors[idx(g, 'b')], [idx(g, 'a')]);
      expect(g.rightNeighbors[idx(g, 'b')], [idx(g, 'c')]);
    });

    test('removing a neighbour frees the middle tile', () {
      final g = BoardGeometry.build(level([('a', 'X', 0, 0, 0), ('b', 'X', 2, 0, 0), ('c', 'X', 4, 0, 0)]));
      final remaining = TileMask.all(3)..remove(idx(g, 'a'));
      expect(TileAvailabilityCalculator(g).isFree(idx(g, 'b'), remaining), isTrue);
    });

    test('an upper tile straddling two lower tiles covers both', () {
      final g = BoardGeometry.build(level([('l', 'X', 0, 0, 0), ('r', 'X', 2, 0, 0), ('top', 'X', 1, 0, 1)]));
      expect(g.coveredBy[idx(g, 'l')], [idx(g, 'top')]);
      expect(g.coveredBy[idx(g, 'r')], [idx(g, 'top')]);
      expect(g.covers[idx(g, 'top')], unorderedEquals([idx(g, 'l'), idx(g, 'r')]));
      final calc = TileAvailabilityCalculator(g);
      final all = TileMask.all(3);
      expect(calc.isFree(idx(g, 'top'), all), isTrue);
      expect(calc.isFree(idx(g, 'l'), all), isFalse);
      expect(calc.isFree(idx(g, 'l'), all..remove(idx(g, 'top'))), isTrue);
    });

    test('a covered tile is not free even with open sides', () {
      final g = BoardGeometry.build(level([('base', 'X', 0, 0, 0), ('cap', 'X', 0, 0, 1)]));
      expect(TileAvailabilityCalculator(g).isFree(idx(g, 'base'), TileMask.all(2)), isFalse);
    });

    test('staggered rows only block when vertical spans overlap', () {
      final g = BoardGeometry.build(level([
        ('a', 'X', 0, 0, 0),
        ('b', 'X', 2, 1, 0), // half a row lower: still touches a's right edge
        ('c', 'X', 2, 2, 0), // a full row lower than a: touches only at a corner
      ]));
      expect(g.rightNeighbors[idx(g, 'a')], [idx(g, 'b')]);
      expect(g.leftNeighbors[idx(g, 'c')], isEmpty);
    });

    test('tiles on different layers never block sideways', () {
      final g = BoardGeometry.build(level([('a', 'X', 0, 0, 0), ('b', 'X', 2, 0, 1), ('base', 'X', 2, 0, 0)]));
      expect(g.rightNeighbors[idx(g, 'a')], [idx(g, 'base')]);
      expect(g.rightNeighbors[idx(g, 'a')], isNot(contains(idx(g, 'b'))));
    });
  });

  group('layout checks', () {
    test('detects same-layer overlaps and floating tiles', () {
      final g = BoardGeometry.build(level([('a', 'X', 0, 0, 0), ('b', 'X', 1, 0, 0), ('float', 'X', 10, 0, 1)]));
      expect(g.sameLayerOverlaps, [(idx(g, 'a'), idx(g, 'b'))]);
      expect(g.unsupportedTiles, [idx(g, 'float')]);
    });

    test('bounds use real footprints, including negative coordinates', () {
      final g = BoardGeometry.build(level([('a', 'X', -4, -2, 0), ('b', 'X', 3, 5, 2), ('c', 'X', 3, 5, 1), ('d', 'X', 3, 5, 0)]));
      expect(g.bounds.minX, -4);
      expect(g.bounds.minY, -2);
      expect(g.bounds.maxX, 5);
      expect(g.bounds.maxY, 7);
      expect(g.bounds.maxLayer, 2);
    });

    test('draw order is bottom layer first', () {
      final g = BoardGeometry.build(level([('top', 'X', 0, 0, 1), ('base', 'X', 0, 0, 0)]));
      expect(g.drawOrder, [idx(g, 'base'), idx(g, 'top')]);
    });
  });

  group('projection and hit testing', () {
    BoardProjection fit(BoardGeometry g, {double w = 400, double h = 600, BoardGridSpan? grid}) => BoardProjection.fit(
      geometry: g,
      tileWidth: 2,
      tileHeight: 2,
      width: w,
      height: h,
      faceAspect: 0.75,
      edgeFraction: 0.2,
      layerOffsetX: -0.1,
      layerOffsetY: -0.1,
      padding: 10,
      grid: grid,
    );

    test('with the fixed grid, every board inside it gets the same tile size, centred', () {
      final grid = BoardGridSpan.campaign();
      final small = BoardGeometry.build(level([('a', 'X', 0, 0, 0), ('b', 'X', 2, 0, 0)]));
      final big = BoardGeometry.build(
        level([('a', 'X', 0, 0, 0), ('b', 'X', 12, 16, 0), ('c', 'X', 1, 1, 1), ('d', 'X', 2, 2, 2), ('e', 'X', 3, 3, 3)]),
      );
      final ps = fit(small, grid: grid), pb = fit(big, grid: grid);
      expect(ps.faceWidth, closeTo(pb.faceWidth, 1e-9));
      // The small board sits in the middle, not enlarged.
      expect(ps.boardRect.centerX, closeTo(200, 1e-6));
      expect(ps.boardRect.centerY, closeTo(300, 1e-6));
      expect(ps.faceRect(1).left - ps.faceRect(0).left, closeTo(ps.faceWidth, 1e-9));
      expect(ps.faceWidth, lessThan(fit(small).faceWidth));
      // A board larger than the grid (older content) is scaled down to fit.
      final huge = BoardGeometry.build(level([('a', 'X', 0, 0, 0), ('b', 'X', 30, 30, 0)]));
      final ph = fit(huge, grid: grid);
      expect(ph.faceWidth, lessThan(pb.faceWidth));
      expect(ph.faceRect(1).bottom, lessThanOrEqualTo(590 + 1e-9));
    });

    test('the board fits inside the viewport, negative coordinates included', () {
      final g = BoardGeometry.build(level([('a', 'X', -6, -2, 0), ('b', 'X', 6, 8, 0), ('c', 'X', 0, 0, 0), ('d', 'X', 0, 0, 1)]));
      final p = fit(g);
      for (var i = 0; i < g.length; i++) {
        final r = p.faceRect(i);
        expect(r.left, greaterThanOrEqualTo(10 - 1e-9));
        expect(r.top, greaterThanOrEqualTo(10 - 1e-9));
        expect(r.right, lessThanOrEqualTo(390 + 1e-9));
        expect(r.bottom, lessThanOrEqualTo(590 + 1e-9));
      }
      expect(p.faceWidth / p.faceHeight, closeTo(0.75, 1e-9));
    });

    test('a tap on an overlap hits the upper tile; elsewhere the lower one', () {
      final g = BoardGeometry.build(level([('l', 'X', 0, 0, 0), ('r', 'X', 2, 0, 0), ('top', 'X', 1, 0, 1)]));
      final p = fit(g);
      final tester = TileHitTester(p);
      final top = p.faceRect(idx(g, 'top'));
      final left = p.faceRect(idx(g, 'l'));
      expect(tester.hitTest(top.centerX, top.centerY, (_) => true), idx(g, 'top'));
      expect(tester.hitTest(left.left + 2, left.bottom - 2, (_) => true), idx(g, 'l'));
      // With the upper tile gone, the same point reaches a lower tile.
      expect(tester.hitTest(top.centerX, top.centerY, (i) => i != idx(g, 'top')), isNot(idx(g, 'top')));
      expect(tester.hitTest(-50, -50, (_) => true), isNull);
    });
  });
}

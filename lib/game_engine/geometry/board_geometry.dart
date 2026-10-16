import '../models/level_definition.dart';
import 'tile_geometry.dart';

/// Logical extent of a board, computed from real tile footprints.
class BoardBounds {
  const BoardBounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.maxLayer,
  });

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final int maxLayer;

  double get width => maxX - minX;
  double get height => maxY - minY;
}

/// Computes [BoardBounds]. Coordinates may be negative or irregular.
class BoardBoundsCalculator {
  const BoardBoundsCalculator._();

  static BoardBounds compute(List<TileGeometry> tiles) {
    if (tiles.isEmpty) {
      return const BoardBounds(minX: 0, minY: 0, maxX: 0, maxY: 0, maxLayer: 0);
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    var maxLayer = 0;
    for (final tile in tiles) {
      final f = tile.footprint;
      if (f.left < minX) minX = f.left;
      if (f.top < minY) minY = f.top;
      if (f.right > maxX) maxX = f.right;
      if (f.bottom > maxY) maxY = f.bottom;
      if (tile.layer > maxLayer) maxLayer = tile.layer;
    }
    return BoardBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY, maxLayer: maxLayer);
  }
}

/// Immutable spatial relationships between the tiles of one level.
///
/// Built once per level and shared by the rules engine, the solver, the
/// renderer and the hit tester, so all of them agree on what covers what.
/// Tiles are addressed by their index in [LevelDefinition.tiles].
class BoardGeometry {
  BoardGeometry._({
    required this.tiles,
    required this.coveredBy,
    required this.covers,
    required this.leftNeighbors,
    required this.rightNeighbors,
    required this.sameLayerOverlaps,
    required this.unsupportedTiles,
    required this.drawOrder,
    required this.bounds,
    required this.indexById,
  });

  /// Builds the overlap and neighbour graph (O(n²); n is a few hundred).
  factory BoardGeometry.build(LevelDefinition level) {
    final width = level.board.tileWidth;
    final height = level.board.tileHeight;
    final defs = level.tiles;
    final count = defs.length;
    final tiles = [
      for (var i = 0; i < count; i++)
        TileGeometry(
          index: i,
          footprint: LogicalRect(defs[i].x, defs[i].y, defs[i].x + width, defs[i].y + height),
          layer: defs[i].layer,
        ),
    ];
    final coveredBy = List.generate(count, (_) => <int>[]);
    final covers = List.generate(count, (_) => <int>[]);
    final left = List.generate(count, (_) => <int>[]);
    final right = List.generate(count, (_) => <int>[]);
    final overlaps = <(int, int)>[];

    for (var i = 0; i < count; i++) {
      final a = tiles[i];
      for (var j = i + 1; j < count; j++) {
        final b = tiles[j];
        if (a.layer == b.layer) {
          if (a.footprint.overlaps(b.footprint)) {
            overlaps.add((i, j));
          } else if (a.footprint.sharesRowsWith(b.footprint)) {
            if ((a.footprint.right - b.footprint.left).abs() < kGeometryEpsilon) {
              right[i].add(j);
              left[j].add(i);
            } else if ((b.footprint.right - a.footprint.left).abs() < kGeometryEpsilon) {
              right[j].add(i);
              left[i].add(j);
            }
          }
        } else if (a.footprint.overlaps(b.footprint)) {
          final (upper, lower) = a.layer > b.layer ? (i, j) : (j, i);
          coveredBy[lower].add(upper);
          covers[upper].add(lower);
        }
      }
    }

    final unsupported = <int>[
      for (final tile in tiles)
        if (tile.layer > 0 && !covers[tile.index].any((lower) => tiles[lower].layer == tile.layer - 1))
          tile.index,
    ];

    // Bottom layers first; inside a layer, back-to-front along the diagonal
    // so each tile's right/bottom side wall is painted under its neighbours.
    final order = List<int>.generate(count, (i) => i)
      ..sort((p, q) {
        final a = tiles[p], b = tiles[q];
        if (a.layer != b.layer) return a.layer.compareTo(b.layer);
        final da = a.footprint.left / width + a.footprint.top / height;
        final db = b.footprint.left / width + b.footprint.top / height;
        if ((da - db).abs() > kGeometryEpsilon) return da.compareTo(db);
        if (a.footprint.top != b.footprint.top) return a.footprint.top.compareTo(b.footprint.top);
        if (a.footprint.left != b.footprint.left) return a.footprint.left.compareTo(b.footprint.left);
        return p.compareTo(q);
      });

    return BoardGeometry._(
      tiles: List.unmodifiable(tiles),
      coveredBy: _freeze(coveredBy),
      covers: _freeze(covers),
      leftNeighbors: _freeze(left),
      rightNeighbors: _freeze(right),
      sameLayerOverlaps: List.unmodifiable(overlaps),
      unsupportedTiles: List.unmodifiable(unsupported),
      drawOrder: List.unmodifiable(order),
      bounds: BoardBoundsCalculator.compute(tiles),
      indexById: {for (var i = 0; i < count; i++) defs[i].tileId: i},
    );
  }

  static List<List<int>> _freeze(List<List<int>> lists) =>
      List.unmodifiable(lists.map<List<int>>(List.unmodifiable));

  final List<TileGeometry> tiles;

  /// Higher-layer tiles overlapping each tile's footprint.
  final List<List<int>> coveredBy;

  /// Lower-layer tiles each tile overlaps.
  final List<List<int>> covers;

  /// Same-layer tiles touching each tile's left edge.
  final List<List<int>> leftNeighbors;

  /// Same-layer tiles touching each tile's right edge.
  final List<List<int>> rightNeighbors;

  /// Same-layer pairs whose footprints intersect (invalid layouts).
  final List<(int, int)> sameLayerOverlaps;

  /// Tiles above layer 0 with nothing on the layer directly below them.
  final List<int> unsupportedTiles;

  /// Paint order, bottom to top. Hit testing walks it in reverse.
  final List<int> drawOrder;

  final BoardBounds bounds;

  final Map<String, int> indexById;

  int get length => tiles.length;

  /// Tiles whose availability can change when [index] is removed or restored.
  Iterable<int> affectedBy(int index) sync* {
    yield* covers[index];
    yield* leftNeighbors[index];
    yield* rightNeighbors[index];
  }
}

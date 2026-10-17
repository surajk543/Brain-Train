import '../geometry/board_geometry.dart';
import '../geometry/tile_geometry.dart';

/// The depth rules of campaign boards (owner, 2026-10-17): upper layers sit
/// half a tile off the layer below, so the player always sees that there are
/// more tiles underneath.
///
/// - No tile sits exactly on top of another: no two tiles on different
///   layers share the same position ([stackedTiles]).
/// - Every tile shows part of its face from above: of the four quarters of
///   its footprint, at least [kMinVisibleQuarters] are not covered by any
///   higher tile ([visibleQuarters]).
///
/// The app plays boards that break them (older content); the content tool
/// and the generator enforce them.
const int kMinVisibleQuarters = 1;

/// Pairs of tile indices on different layers with the same position.
List<(int, int)> stackedTiles(BoardGeometry geometry) {
  final byPosition = <(double, double), List<int>>{};
  for (final tile in geometry.tiles) {
    (byPosition[(tile.footprint.left, tile.footprint.top)] ??= []).add(tile.index);
  }
  return [
    for (final group in byPosition.values)
      for (var a = 0; a < group.length; a++)
        for (var b = a + 1; b < group.length; b++)
          if (geometry.tiles[group[a]].layer != geometry.tiles[group[b]].layer) (group[a], group[b]),
  ];
}

/// For each tile, how many quarters of its footprint no higher tile covers.
List<int> visibleQuarters(BoardGeometry geometry) => [
  for (final tile in geometry.tiles)
    [
      for (final quarter in _quarters(tile.footprint))
        if (!geometry.coveredBy[tile.index].any((upper) => geometry.tiles[upper].footprint.overlaps(quarter))) quarter,
    ].length,
];

List<LogicalRect> _quarters(LogicalRect f) {
  final midX = (f.left + f.right) / 2, midY = (f.top + f.bottom) / 2;
  return [
    LogicalRect(f.left, f.top, midX, midY),
    LogicalRect(midX, f.top, f.right, midY),
    LogicalRect(f.left, midY, midX, f.bottom),
    LogicalRect(midX, midY, f.right, f.bottom),
  ];
}

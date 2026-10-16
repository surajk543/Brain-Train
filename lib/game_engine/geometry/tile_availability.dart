import 'board_geometry.dart';
import 'tile_mask.dart';

/// Mahjong Solitaire freedom rules over a [BoardGeometry].
///
/// A remaining tile is free when no remaining higher-layer tile overlaps its
/// footprint and at least one of its horizontal sides (left or right) has no
/// remaining same-layer tile touching it.
class TileAvailabilityCalculator {
  const TileAvailabilityCalculator(this.geometry);

  final BoardGeometry geometry;

  bool isCovered(int index, TileMask remaining) =>
      geometry.coveredBy[index].any(remaining.contains);

  bool isFree(int index, TileMask remaining) {
    if (!remaining.contains(index) || isCovered(index, remaining)) return false;
    final leftBlocked = geometry.leftNeighbors[index].any(remaining.contains);
    if (!leftBlocked) return true;
    return !geometry.rightNeighbors[index].any(remaining.contains);
  }

  List<int> freeTiles(TileMask remaining) => [
    for (final index in remaining.indices)
      if (isFree(index, remaining)) index,
  ];
}

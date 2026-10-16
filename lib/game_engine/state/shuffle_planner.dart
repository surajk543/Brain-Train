import '../campaign/seeded_random.dart';
import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../rules/match_rules.dart';

/// One new arrangement of the board's symbols, with its proof.
class ShufflePlan {
  const ShufflePlan({required this.seed, required this.source, required this.taps});

  final int seed;

  /// For every tile of the level: the level tile whose symbol it shows after
  /// the shuffle (tiles off the board keep theirs).
  final List<int> source;

  /// A winning tap order from the shuffled position (the tray's tiles first
  /// find their twins, then pairs): the arrangement was built along it.
  final List<int> taps;
}

/// Builds a shuffle that can always be won: it walks a random removal order
/// over the board's tile places (weighted towards high, stacked tiles, like
/// the level generator) and hands out the board's symbols along it. First a
/// twin for each tray tile, on a tile that is free then, then a pair at a
/// time on two tiles free together (or, when only one tile is free, the tile
/// that frees after it). The walk itself is the winning order
/// ([ShufflePlan.taps]), so the plan never dead-ends: a non-empty board always
/// has a free tile, and a tray always has room for the first of a pair.
///
/// A uniformly random rearrangement would mostly be unwinnable on the hard,
/// stacked boards with 2-slot trays, so this is built, not drawn and tested.
///
/// Pure and deterministic: the same position, sources and [ShufflePlan.seed]
/// give the same plan on every platform ([SeededRandom]). Saves replay a
/// shuffle from its seed, so this algorithm is pinned: change it only under a
/// new [version] (and keep this one for old saves).
class ShufflePlanner {
  ShufflePlanner({required this.geometry, required this.levelRules})
    : _availability = TileAvailabilityCalculator(geometry);

  /// The algorithm's version, written in save markers.
  static const int version = 1;

  final BoardGeometry geometry;

  /// The level's match keys (by level tile, before any shuffle).
  final MatchRules levelRules;
  final TileAvailabilityCalculator _availability;

  /// A plan for the board [remaining] with [tray] (tile indices, slot order)
  /// waiting, where tile `i` shows level tile `source[i]`'s symbol. Null when
  /// the symbols cannot pair up (an invalid level).
  ShufflePlan? plan({
    required TileMask remaining,
    required List<int> tray,
    required List<int> source,
    required int seed,
  }) {
    final random = SeededRandom(seed);
    // The board's symbols by match key, in a seeded order.
    final pool = <String, List<int>>{};
    for (final index in remaining.indices) {
      (pool[levelRules.keyOf(source[index])] ??= []).add(source[index]);
    }
    for (final symbols in pool.values) {
      random.shuffle(symbols);
    }
    final board = remaining.copy();
    final next = List.of(source);
    final taps = <int>[];
    int take(int index, String key) {
      next[index] = pool[key]!.removeLast();
      board.remove(index);
      taps.add(index);
      return index;
    }

    for (final waiting in tray) {
      final key = levelRules.keyOf(source[waiting]);
      final free = _availability.freeTiles(board);
      if (free.isEmpty || (pool[key]?.isEmpty ?? true)) return null;
      take(_weighted(free, random), key);
    }
    final pairs = <String>[];
    for (final MapEntry(:key, value: symbols) in pool.entries) {
      if (symbols.length.isOdd) return null;
      for (var i = 0; i < symbols.length ~/ 2; i++) {
        pairs.add(key);
      }
    }
    random.shuffle(pairs);
    for (final key in pairs) {
      final free = _availability.freeTiles(board);
      if (free.isEmpty) return null;
      final first = take(_weighted(free, random), key);
      var rest = [for (final index in free) if (index != first) index];
      // Only one tile was free: its twin goes where it frees next.
      if (rest.isEmpty) rest = _availability.freeTiles(board);
      if (rest.isEmpty) return null;
      take(_weighted(rest, random), key);
    }
    return ShufflePlan(seed: seed, source: next, taps: taps);
  }

  int _weighted(List<int> free, SeededRandom random) {
    var total = 0;
    final weights = [for (final i in free) 1 + geometry.tiles[i].layer * 3 + geometry.covers[i].length];
    for (final w in weights) {
      total += w;
    }
    var roll = random.nextInt(total);
    for (var i = 0; i < free.length; i++) {
      roll -= weights[i];
      if (roll < 0) return free[i];
    }
    return free.last;
  }
}

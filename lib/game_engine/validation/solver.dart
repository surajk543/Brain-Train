import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../rules/match_rules.dart';

enum SolveOutcome {
  /// A complete solution was found and is returned.
  solvable,

  /// The search space was exhausted: no sequence clears the board.
  unsolvable,

  /// The node budget ran out before either answer was proven.
  unknown,
}

class SolveResult {
  const SolveResult(this.outcome, this.solution, this.nodesVisited);

  final SolveOutcome outcome;

  /// Tile index pairs in play order. Empty unless [outcome] is solvable.
  final List<(int, int)> solution;
  final int nodesVisited;
}

class _BudgetExceeded implements Exception {}

/// Depth-first Mahjong Solitaire solver with dead-state memoisation.
///
/// Searches pair removals: two free tiles with the same match key leave the
/// board together. Every solution is also a winning game with the tray: tap
/// each pair's tiles one after the other, and the second clears the first
/// at once, so the tray never holds more than one tile. The tray allows more
/// (up to its capacity minus one tile can wait for a partner), so
/// [SolveOutcome.unsolvable] means "not clearable by pairs", a conservative
/// verdict for the game.
///
/// Pure Dart and synchronous: run it in an isolate (or an offline tool) for
/// large boards, never on the UI thread.
///
/// Pruning rule: when every remaining tile of a match key is free, removing a
/// pair of them can never hurt (freedom only grows as tiles leave the board),
/// so that move is taken without branching.
class MahjongSolver {
  MahjongSolver({required this.geometry, required this.rules, this.maxNodes = 500000})
    : _availability = TileAvailabilityCalculator(geometry);

  final BoardGeometry geometry;
  final MatchRules rules;
  final int maxNodes;
  final TileAvailabilityCalculator _availability;

  final Set<String> _dead = {};
  int _nodes = 0;

  SolveResult solve(TileMask remaining) {
    _dead.clear();
    _nodes = 0;
    final path = <(int, int)>[];
    try {
      final solved = _search(remaining.copy(), path);
      return SolveResult(solved ? SolveOutcome.solvable : SolveOutcome.unsolvable, solved ? path : const [], _nodes);
    } on _BudgetExceeded {
      return SolveResult(SolveOutcome.unknown, const [], _nodes);
    }
  }

  bool _search(TileMask remaining, List<(int, int)> path) {
    if (remaining.isEmpty) return true;
    final stateKey = remaining.key;
    if (_dead.contains(stateKey)) return false;
    if (++_nodes > maxNodes) throw _BudgetExceeded();

    final remainingByKey = <String, int>{};
    for (final index in remaining.indices) {
      final key = rules.keyOf(index);
      remainingByKey[key] = (remainingByKey[key] ?? 0) + 1;
    }
    final freeByKey = <String, List<int>>{};
    for (final index in _availability.freeTiles(remaining)) {
      (freeByKey[rules.keyOf(index)] ??= []).add(index);
    }

    for (final entry in freeByKey.entries) {
      final group = entry.value;
      if (group.length >= 2 && group.length == remainingByKey[entry.key]) {
        if (_tryMove(remaining, group[0], group[1], path)) return true;
        _dead.add(stateKey);
        return false;
      }
    }

    final moves = <(int, int, int)>[];
    for (final group in freeByKey.values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          moves.add((group[i], group[j], _score(group[i], remaining) + _score(group[j], remaining)));
        }
      }
    }
    moves.sort((a, b) => b.$3.compareTo(a.$3));
    for (final (a, b, _) in moves) {
      if (_tryMove(remaining, a, b, path)) return true;
    }
    _dead.add(stateKey);
    return false;
  }

  bool _tryMove(TileMask remaining, int a, int b, List<(int, int)> path) {
    final next = remaining.copy()
      ..remove(a)
      ..remove(b);
    path.add((a, b));
    if (_search(next, path)) return true;
    path.removeLast();
    return false;
  }

  /// Prefers tiles high in a stack that hold many other tiles back.
  int _score(int index, TileMask remaining) {
    var blocking = 0;
    for (final other in geometry.affectedBy(index)) {
      if (remaining.contains(other)) blocking++;
    }
    return geometry.tiles[index].layer * 4 + blocking;
  }
}

import '../validation/solver.dart';
import '../validation/tray_solver.dart';
import 'game_actions.dart';
import 'game_engine.dart';
import 'game_state.dart';

/// Picks a recommended next tap for the game in [engine]. A pure function of
/// the game's state: it reads the engine, never changes it, never scores.
///
/// In order:
/// 1. a free tile whose twin waits in the tray and that is the last board
///    tile of its symbol: it clears a pair now and can never hurt;
/// 2. with room in the tray: the first tile of a safe pair, a symbol whose
///    board tiles are all free (taking two of them never makes the board
///    harder; the solver's pruning rule), two-tile symbols first;
/// 3. the first tap of a winning order the tray solver ([TraySolver]) finds
///    from here, within [maxNodes] (it respects the tray's size);
/// 4. failing that, any free tile whose twin waits in the tray, the
///    longest-waiting twin first;
/// 5. with room in the tray: any free tile, one with a free twin first, then
///    high tiles that hold many others back.
///
/// A tray twin whose symbol has more tiles on the board is left to the
/// solver (step 3) rather than taken at once: which of them clears the tray
/// can decide the game, and on boards with a 2-slot tray taking the first
/// one found loses often.
///
/// Null when the game is not in play, or when the tray has one slot left and
/// no free tile matches it (every tap would fill the tray).
class HintFinder {
  const HintFinder(this.engine, {this.maxNodes = defaultMaxNodes});

  /// Solver budget for step 3. On the largest boards (176 tiles, 2-slot
  /// trays) 20k nodes take about 50 ms on a desktop VM; most positions solve
  /// in under 100 nodes.
  static const int defaultMaxNodes = 20000;

  final GameEngine engine;
  final int maxNodes;

  Hint? find() {
    final state = engine.state;
    if (state.status != GameStatus.playing) return null;
    final level = engine.level;
    final rules = engine.rules;
    String id(int index) => level.tiles[index].tileId;
    final tray = [for (final tileId in state.tray) engine.indexOf(tileId)!];
    final free = [
      for (var index = 0; index < level.tiles.length; index++)
        if (engine.isFreeIndex(index)) index,
    ];
    final onBoard = <String, int>{};
    for (var index = 0; index < level.tiles.length; index++) {
      if (engine.isRemaining(index)) onBoard.update(rules.keyOf(index), (n) => n + 1, ifAbsent: () => 1);
    }
    int twinSlot(int index) => tray.indexWhere((waiting) => rules.matches(waiting, index));

    // A free tile that clears the tray tile waiting longest, among [tiles].
    Hint? clearing(Iterable<int> tiles) {
      (int, int)? best;
      for (final index in tiles) {
        final slot = twinSlot(index);
        if (slot >= 0 && (best == null || slot < best.$2)) best = (index, slot);
      }
      return best == null
          ? null
          : Hint(tileId: id(best.$1), reason: HintReason.completesPair, partnerTileId: id(tray[best.$2]));
    }

    // 1. Completes a pair with the last board tile of its symbol.
    final safeClear = clearing(free.where((index) => onBoard[rules.keyOf(index)] == 1));
    if (safeClear != null) return safeClear;

    // 2. A safe pair. None of its symbol waits in the tray (all its tiles
    // are on the board).
    final room = tray.length + 1 < engine.trayCapacity;
    if (room) {
      final pairs = safePairs(engine).where((pair) => twinSlot(pair.$1) < 0).toList();
      if (pairs.isNotEmpty) {
        final (a, b) = pairs.firstWhere((pair) => onBoard[rules.keyOf(pair.$1)] == 2, orElse: () => pairs.first);
        return Hint(tileId: id(a), reason: HintReason.safePair, partnerTileId: id(b));
      }
    }

    // 3. The solver's first tap. After a shuffle, the order it was built
    // along still wins if play kept to it; that is checked when the search
    // runs out of budget.
    final solver = TraySolver.forRules(engine.geometry, rules, capacity: engine.trayCapacity, maxNodes: maxNodes);
    var solved = solver.solve(engine.remainingMask, tray: tray);
    if (solved.outcome == SolveOutcome.unknown && engine.shuffleProof.isNotEmpty) {
      final proof = engine.shuffleProof.where(engine.isRemaining).toList();
      if (solver.check(engine.remainingMask, proof, tray: tray)) {
        solved = TraySolveResult(SolveOutcome.solvable, proof, 0);
      }
    }
    if (solved.outcome == SolveOutcome.solvable && solved.taps.isNotEmpty) {
      final first = solved.taps.first;
      final slot = twinSlot(first);
      final second = solved.taps.length > 1 ? solved.taps[1] : null;
      return Hint(
        tileId: id(first),
        reason: HintReason.solver,
        partnerTileId: slot >= 0
            ? id(tray[slot])
            : second != null && rules.matches(first, second)
            ? id(second)
            : null,
      );
    }

    // 4. Any tile that clears a pair now.
    final anyClear = clearing(free);
    if (anyClear != null) return anyClear;

    // 5. Any free tile, if the tray has room for it.
    if (!room || free.isEmpty) return null;
    int? twinOf(int index) {
      for (final other in free) {
        if (rules.matches(index, other)) return other;
      }
      return null;
    }

    int score(int index) {
      var blocking = 0;
      for (final other in engine.geometry.affectedBy(index)) {
        if (engine.isRemaining(other)) blocking++;
      }
      return engine.geometry.tiles[index].layer * 4 + blocking;
    }

    final ranked = [...free]
      ..sort((a, b) {
        final twinA = twinOf(a) != null ? 1 : 0, twinB = twinOf(b) != null ? 1 : 0;
        if (twinA != twinB) return twinB.compareTo(twinA);
        final byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    final pick = ranked.first;
    final twin = twinOf(pick);
    return Hint(tileId: id(pick), reason: HintReason.fallback, partnerTileId: twin == null ? null : id(twin));
  }

  /// Free pairs of a symbol whose board tiles are all free (at least two),
  /// in board order: removing two of them never makes the board harder,
  /// since freedom only grows as tiles leave. The first two free tiles of
  /// each such symbol, symbols in the order their first free tile appears.
  static List<(int, int)> safePairs(GameEngine engine) {
    final level = engine.level;
    final rules = engine.rules;
    final remainingByKey = <String, int>{};
    final freeByKey = <String, List<int>>{};
    for (var index = 0; index < level.tiles.length; index++) {
      if (!engine.isRemaining(index)) continue;
      final key = rules.keyOf(index);
      remainingByKey[key] = (remainingByKey[key] ?? 0) + 1;
      if (engine.isFreeIndex(index)) (freeByKey[key] ??= []).add(index);
    }
    return [
      for (final MapEntry(:key, value: free) in freeByKey.entries)
        if (free.length >= 2 && free.length == remainingByKey[key]) (free[0], free[1]),
    ];
  }
}

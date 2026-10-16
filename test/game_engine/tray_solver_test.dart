import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/game_engine/validation/tray_solver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'hard_levels.dart';

void main() {
  final reg = registry(['A', 'B', 'C', 'D']);

  TraySolver solverFor(LevelDefinition level, {required int capacity, int maxNodes = 100000}) => TraySolver.forRules(
    BoardGeometry.build(level),
    MatchRules(level: level, registry: reg),
    capacity: capacity,
    maxNodes: maxNodes,
  );

  /// Plays [taps] through the real engine.
  GameStatus play(LevelDefinition level, List<int> taps, {required int capacity}) {
    final engine = GameEngine(level: level, rules: MatchRules(level: level, registry: reg), trayCapacity: capacity);
    for (final index in taps) {
      expect(engine.tap(level.tiles[index].tileId).accepted, isTrue);
    }
    return engine.state.status;
  }

  // b1 sits on a1 and a2 on b2: no two free tiles match, but a tile can
  // wait in the tray while its twin is uncovered.
  final crossed = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 0, 0, 1), ('b2', 'B', 6, 0, 0), ('a2', 'A', 6, 0, 1)]);

  test('wins that need the tray: tap a tile, its twin frees, then they match', () {
    // Pair removal cannot clear it.
    expect(
      MahjongSolver(geometry: BoardGeometry.build(crossed), rules: MatchRules(level: crossed, registry: reg))
          .solve(TileMask.all(4))
          .outcome,
      SolveOutcome.unsolvable,
    );
    // Three slots: b1 and a2 both wait, then a1 and b2 clear them.
    final three = solverFor(crossed, capacity: 3).solve(TileMask.all(4));
    expect(three.outcome, SolveOutcome.solvable);
    expect(play(crossed, three.taps, capacity: 3), GameStatus.won);
    // Two slots: the second tile fills the tray.
    expect(solverFor(crossed, capacity: 2).solve(TileMask.all(4)).outcome, SolveOutcome.unsolvable);
  });

  test('a single tile stacked on its twin plays with any tray', () {
    final stacked = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 0, 0, 1)]);
    final result = solverFor(stacked, capacity: 2).solve(TileMask.all(2));
    expect(result.outcome, SolveOutcome.solvable);
    expect(play(stacked, result.taps, capacity: 2), GameStatus.won);
  });

  test('starts from tiles already in the tray', () {
    final wide = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 4, 0, 0), ('a2', 'A', 8, 0, 0), ('b2', 'B', 12, 0, 0)]);
    final remaining = TileMask.all(4)
      ..remove(0)
      ..remove(1);
    final result = solverFor(wide, capacity: 3).solve(remaining, tray: [0, 1]);
    expect(result.outcome, SolveOutcome.solvable);
    expect(result.taps.toSet(), {2, 3});
    // A full tray is lost, and two of one key never wait together.
    expect(solverFor(wide, capacity: 2).solve(remaining, tray: [0, 1]).outcome, SolveOutcome.unsolvable);
    expect(solverFor(wide, capacity: 4).solve(TileMask.all(4)..remove(0)..remove(2), tray: [0, 2]).outcome,
        SolveOutcome.unsolvable);
  });

  test('check accepts a winning order and rejects a wrong one', () {
    final solver = solverFor(crossed, capacity: 3);
    final all = TileMask.all(4);
    expect(solver.check(all, [1, 3, 0, 2]), isTrue, reason: 'b1, a2, then a1 and b2 clear them');
    expect(solver.check(all, [0, 1, 2, 3]), isFalse, reason: 'a1 is covered');
    expect(solver.check(all, [1, 3]), isFalse, reason: 'the board is not empty');
    expect(solverFor(crossed, capacity: 2).check(all, [1, 3, 0, 2]), isFalse, reason: 'the tray fills');
  });

  test('reports unknown when the node budget runs out', () {
    final big = level([for (var i = 0; i < 40; i++) ('t$i', i.isEven ? 'A' : 'B', (i % 10) * 2.0, (i ~/ 10) * 2.0, 0)]);
    expect(solverFor(big, capacity: 4, maxNodes: 1).solve(TileMask.all(40)).outcome, SolveOutcome.unknown);
  });

  test('solves the hardest boards quickly, and its answers win in the engine', () {
    for (final hard in hardLevels()) {
      final geometry = BoardGeometry.build(hard);
      final rules = MatchRules(level: hard, registry: hardRegistry);
      final watch = Stopwatch()..start();
      final result = TraySolver.forRules(geometry, rules, capacity: 2).solve(TileMask.all(hard.tiles.length));
      expect(result.outcome, SolveOutcome.solvable, reason: hard.levelId);
      expect(watch.elapsedMilliseconds, lessThan(2000), reason: '${hard.levelId}: ${result.nodesVisited} nodes');
      final engine = GameEngine(level: hard, rules: rules, geometry: geometry);
      for (final index in result.taps) {
        engine.tap(hard.tiles[index].tileId);
      }
      expect(engine.state.status, GameStatus.won, reason: hard.levelId);
    }
  });
}

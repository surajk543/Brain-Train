import 'package:brain_train/game_engine/generator/level_generator.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/models/board_config.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/level_rules.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/level_validator.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final reg = registry(['A', 'B', 'C', 'ZINNIA', 'ANEMONE']);

  SolveResult solve(LevelDefinition level, {int maxNodes = 100000}) =>
      MahjongSolver(geometry: BoardGeometry.build(level), rules: MatchRules(level: level, registry: reg), maxNodes: maxNodes)
          .solve(TileMask.all(level.tiles.length));

  /// Plays the solver's answer through the real engine.
  void expectSolutionWins(LevelDefinition level, SolveResult result) {
    final engine = engineFor(level, reg);
    for (final (a, b) in result.solution) {
      engine
        ..tap(level.tiles[a].tileId)
        ..tap(level.tiles[b].tileId);
    }
    expect(engine.state.status, GameStatus.won);
  }

  test('finds a solution that the engine accepts', () {
    // Stacks must be cleared top-first: B frees a1, then A frees c1.
    final level0 = level([
      ('a1', 'A', 0, 0, 0),
      ('b1', 'B', 0, 0, 1),
      ('b2', 'B', 12, 0, 0),
      ('c1', 'C', 4, 0, 0),
      ('a2', 'A', 4, 0, 1),
      ('c2', 'C', 6, 0, 0),
    ]);
    final result = solve(level0);
    expect(result.outcome, SolveOutcome.solvable);
    expectSolutionWins(level0, result);
  });

  test('proves a crossed stack unsolvable', () {
    final crossed = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 0, 0, 1), ('b2', 'B', 6, 0, 0), ('a2', 'A', 6, 0, 1)]);
    expect(solve(crossed).outcome, SolveOutcome.unsolvable);
  });

  test('proves a pair stacked on itself unsolvable', () {
    expect(solve(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 0, 0, 1)])).outcome, SolveOutcome.unsolvable);
  });

  test('a trap: pairing the two open As first loses; the solver avoids it', () {
    // a3 lies under b1 and b2 lies under a4. Matching a1+a2 leaves the two
    // crossed stacks, which no pair order clears (the tray still can, so
    // the game itself plays on; the solver's verdicts are conservative).
    final trap = level([
      ('a1', 'A', 0, 0, 0),
      ('a2', 'A', 10, 0, 0),
      ('a3', 'A', 20, 0, 0),
      ('b1', 'B', 20, 0, 1),
      ('b2', 'B', 30, 0, 0),
      ('a4', 'A', 30, 0, 1),
    ]);
    final greedy = engineFor(trap, reg)
      ..tap('a1')
      ..tap('a2');
    expect(
      MahjongSolver(geometry: greedy.geometry, rules: greedy.rules).solve(greedy.remainingMask).outcome,
      SolveOutcome.unsolvable,
    );
    expect(greedy.state.status, GameStatus.playing);
    final result = solve(trap);
    expect(result.outcome, SolveOutcome.solvable);
    expectSolutionWins(trap, result);
  });

  test('reports unknown when the node budget runs out', () {
    final big = level([for (var i = 0; i < 40; i++) ('t$i', i.isEven ? 'A' : 'B', (i % 10) * 2.0, (i ~/ 10) * 2.0, 0)]);
    expect(solve(big, maxNodes: 1).outcome, SolveOutcome.unknown);
  });

  test('special groups are honoured by the solver', () {
    final flowers = level(
      [('z', 'ZINNIA', 0, 0, 0), ('n', 'ANEMONE', 4, 0, 0)],
      rules: const LevelRules(matchGroups: {'FLOWERS': ['ZINNIA', 'ANEMONE']}),
    );
    expect(solve(flowers).outcome, SolveOutcome.solvable);
    expect(solve(level([('z', 'ZINNIA', 0, 0, 0), ('n', 'ANEMONE', 4, 0, 0)])).outcome, SolveOutcome.unsolvable);
  });

  group('validator', () {
    test('rejects unpaired symbols', () {
      final report = LevelValidator(registry: reg).validate(level([('a', 'A', 0, 0, 0), ('b', 'A', 2, 0, 0), ('c', 'B', 4, 0, 0), ('d', 'C', 6, 0, 0)]));
      expect(report.hasError('unpaired_symbol'), isTrue);
    });

    test('rejects unsolvable levels when solvability is checked', () {
      final crossed = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 0, 0, 1), ('b2', 'B', 6, 0, 0), ('a2', 'A', 6, 0, 1)]);
      final report = LevelValidator(registry: reg).validate(crossed, checkSolvable: true);
      expect(report.isValid, isFalse);
      expect(report.hasError('no_initial_moves') || report.hasError('unsolvable'), isTrue);
    });

    test('rejects malformed backdrop palettes', () {
      final base = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0)]);
      LevelDefinition withColors(List<String> colors) => LevelDefinition(
        levelId: base.levelId,
        title: base.title,
        board: base.board,
        tiles: base.tiles,
        backdrop: LevelBackdrop(colors: colors),
      );
      final validator = LevelValidator(registry: reg);
      expect(validator.validate(withColors(['#112233', '#AABBCC'])).isValid, isTrue);
      expect(validator.validate(withColors(['#112233'])).hasError('invalid_backdrop'), isTrue);
      expect(validator.validate(withColors(['red', '#AABBCC'])).hasError('invalid_backdrop'), isTrue);
    });

    group('campaign rules (checkCampaignRules)', () {
      LevelDefinition withFaces(LevelDefinition base, Map<String, String> faces) => LevelDefinition(
        levelId: base.levelId,
        title: base.title,
        board: base.board,
        tiles: base.tiles,
        faceColors: faces,
      );
      LevelValidationReport check(LevelDefinition l) =>
          LevelValidator(registry: reg).validate(l, checkCampaignRules: true);

      test('accept a half-offset board with a coloured single pair, and the client never applies them', () {
        // B sits half a tile right of the two A tiles: both keep half their face.
        final ok = withFaces(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('b1', 'B', 1, 0, 1), ('b2', 'B', 6, 0, 0)]), {'B': 'gold'});
        expect(check(ok).errors, isEmpty);
        final stacked = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('b1', 'B', 0, 0, 1), ('b2', 'B', 6, 0, 0)]);
        expect(LevelValidator(registry: reg).validate(stacked).isValid, isTrue);
      });

      test('reject a tile exactly on top of another, and a tile with no quarter showing', () {
        final stacked = withFaces(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('b1', 'B', 0, 0, 1), ('b2', 'B', 6, 0, 0)]), {'B': 'sky'});
        expect(check(stacked).hasError('stacked_tile'), isTrue);
        expect(check(stacked).hasError('hidden_tile'), isTrue);
        // A at (2, 2) is covered by four offset tiles above, one quarter each.
        final hidden = withFaces(
          level([
            for (final (i, (x, y)) in [(0, 0), (2, 0), (4, 0), (0, 2), (2, 2), (4, 2), (0, 4), (2, 4), (4, 4)].indexed)
              ('t$i', i == 4 ? 'C' : (i.isEven ? 'A' : 'B'), x.toDouble(), y.toDouble(), 0),
            ('u1', 'A', 1, 1, 1), ('u2', 'B', 3, 1, 1), ('u3', 'A', 1, 3, 1), ('u4', 'B', 3, 3, 1), ('c2', 'C', 8, 0, 0),
          ]),
          {'C': 'peach'},
        );
        final report = check(hidden);
        expect(report.hasError('hidden_tile'), isTrue);
        expect(report.errors.where((e) => e.code == 'hidden_tile').single.message, contains('t4'));
        expect(report.hasError('stacked_tile'), isFalse);
      });

      test('reject boards outside the 7x9 grid', () {
        final wide = withFaces(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 14, 0, 0)]), {'A': 'gold'});
        expect(check(wide).hasError('outside_grid'), isTrue);
        final fits = withFaces(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 12, 16, 0)]), {'A': 'gold'});
        expect(check(fits).hasError('outside_grid'), isFalse);
      });

      test('need 1-2 coloured single pairs with palette names', () {
        final base = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('a3', 'A', 4, 0, 0), ('a4', 'A', 6, 0, 0), ('b1', 'B', 0, 2, 0), ('b2', 'B', 2, 2, 0), ('c1', 'C', 4, 2, 0), ('c2', 'C', 6, 2, 0)]);
        expect(check(withFaces(base, {})).hasError('face_colors'), isTrue, reason: 'none');
        expect(check(withFaces(base, {'B': 'gold'})).errors, isEmpty);
        expect(check(withFaces(base, {'B': 'gold', 'C': 'lavender'})).errors, isEmpty);
        expect(check(withFaces(base, {'A': 'gold'})).hasError('face_colors'), isTrue, reason: 'A has two pairs');
        expect(check(withFaces(base, {'B': 'green'})).hasError('face_colors'), isTrue, reason: 'not in the palette');
        expect(check(withFaces(base, {'B': 'gold', 'C': 'sky', 'A': 'peach'})).hasError('face_colors'), isTrue, reason: 'three');
      });
    });

    test('accepts a solvable level and attaches the proof', () {
      final ok = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0)]);
      final report = LevelValidator(registry: reg).validate(ok, checkSolvable: true);
      expect(report.isValid, isTrue);
      expect(report.solve!.outcome, SolveOutcome.solvable);
    });
  });

  group('generator', () {
    LayoutTemplate template(int seed, {int layers = 3}) => LayoutTemplate(
      levelId: 'gen-$seed',
      title: 'Generated',
      difficulty: 'test',
      board: const BoardConfig(),
      seed: seed,
      symbols: ['A', 'B', 'C'],
      slots: [
        for (var y = 0; y < 4; y++)
          for (var x = 0; x < 6; x++) LayoutSlot(x * 2.0, y * 2.0, 0),
        for (var y = 0; y < 2; y++)
          for (var x = 0; x < 4; x++) LayoutSlot(2 + x * 2.0, 1 + y * 2.0, 1),
        if (layers > 2) ...[const LayoutSlot(4, 2, 2), const LayoutSlot(6, 2, 2)],
      ],
    );

    test('every generated level is proven solvable', () {
      for (final seed in [1, 2, 3, 42, 99]) {
        final generated = const LevelGenerator().generate(template(seed));
        final report = LevelValidator(registry: reg).validate(generated, checkSolvable: true);
        expect(report.isValid, isTrue, reason: 'seed $seed: ${report.errors}');
      }
    });

    test('generation is deterministic per seed', () {
      final a = const LevelGenerator().generate(template(7)).toJson();
      final b = const LevelGenerator().generate(template(7)).toJson();
      expect(a, b);
    });

    test('rejects layouts that cannot be paired', () {
      final odd = LayoutTemplate(
        levelId: 'odd',
        title: 'Odd',
        difficulty: 'test',
        board: const BoardConfig(),
        seed: 1,
        symbols: ['A'],
        slots: const [LayoutSlot(0, 0, 0), LayoutSlot(2, 0, 0), LayoutSlot(4, 0, 0)],
      );
      expect(() => const LevelGenerator().generate(odd), throwsA(isA<LevelGenerationException>()));
    });
  });
}

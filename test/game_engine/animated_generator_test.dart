import 'package:brain_train/game_engine/generator/level_generator.dart';
import 'package:brain_train/game_engine/models/board_config.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/validation/level_validator.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  const statics = ['A', 'B', 'C', 'D'];
  const animated = ['X', 'Y', 'Z'];
  final reg = registry([...statics, ...animated]);

  /// 60 slots = 30 pairs over three layers.
  LayoutTemplate template({int seed = 7, List<String> animatedSymbols = animated, double share = 0.2}) =>
      LayoutTemplate(
        levelId: 'anim-$seed',
        title: 'Animated',
        difficulty: 'test',
        board: const BoardConfig(),
        seed: seed,
        symbols: statics,
        animatedSymbols: animatedSymbols,
        animatedShare: share,
        slots: [
          for (var y = 0; y < 5; y++)
            for (var x = 0; x < 8; x++) LayoutSlot(x * 2.0, y * 2.0, 0),
          for (var y = 0; y < 3; y++)
            for (var x = 0; x < 6; x++) LayoutSlot(2 + x * 2.0, 1 + y * 2.0, 1),
          const LayoutSlot(4, 3, 2),
          const LayoutSlot(6, 3, 2),
        ],
      );

  /// Pairs per symbol code.
  Map<String, int> pairsBySymbol(LevelDefinition level) {
    final counts = <String, int>{};
    for (final tile in level.tiles) {
      counts[tile.symbolCode] = (counts[tile.symbolCode] ?? 0) + 1;
    }
    return counts.map((code, tiles) => MapEntry(code, tiles ~/ 2));
  }

  test('animated pair count: round(pairs * share), at least one, at most all', () {
    int count(int pairs, {List<String> symbols = animated, double share = 0.2}) =>
        LevelGenerator.animatedPairCount(pairs, template(animatedSymbols: symbols, share: share));
    expect(count(30), 6);
    expect(count(8), 2);
    expect(count(15), 3);
    expect(count(24), 5);
    expect(count(51), 10);
    expect(count(1), 1, reason: 'at least one when animated symbols exist');
    expect(count(30, share: 1), 30);
    expect(count(30, symbols: []), 0);
    expect(count(30, share: 0), 0, reason: 'a layout can opt out');
  });

  test('30 pairs give 6 animated pairs, each group spread evenly, and stay solvable', () {
    final level = const LevelGenerator().generate(template());
    expect(level.tiles, hasLength(60));
    final pairs = pairsBySymbol(level);
    final animatedPairs = [for (final code in animated) pairs[code] ?? 0];
    final staticPairs = [for (final code in statics) pairs[code] ?? 0];
    expect(animatedPairs.fold(0, (a, b) => a + b), 6);
    expect(staticPairs.fold(0, (a, b) => a + b), 24);
    expect(
      animatedPairs.reduce((a, b) => a > b ? a : b) - animatedPairs.reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(1),
    );
    expect(
      staticPairs.reduce((a, b) => a > b ? a : b) - staticPairs.reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(1),
    );
    final report = LevelValidator(registry: reg).validate(level, checkSolvable: true);
    expect(report.isValid, isTrue, reason: '${report.errors}');
    expect(report.solve!.outcome, SolveOutcome.solvable);
  });

  test('every seed is solvable and deterministic', () {
    for (final seed in [1, 2, 3, 42, 99]) {
      final a = const LevelGenerator().generate(template(seed: seed));
      expect(a.toJson(), const LevelGenerator().generate(template(seed: seed)).toJson(), reason: 'seed $seed');
      final report = LevelValidator(registry: reg).validate(a, checkSolvable: true);
      expect(report.isValid, isTrue, reason: 'seed $seed: ${report.errors}');
    }
  });

  test('fewer animated pairs than animated symbols: each one used once', () {
    final level = const LevelGenerator().generate(template(share: 0.05)); // 2 pairs, 3 symbols
    final used = [for (final code in animated) pairsBySymbol(level)[code] ?? 0];
    expect(used.where((n) => n == 1), hasLength(2));
    expect(used.where((n) => n == 0), hasLength(1));
  });

  test('without animated symbols the level is all static and unchanged', () {
    final none = const LevelGenerator().generate(template(animatedSymbols: []));
    final optedOut = const LevelGenerator().generate(template(share: 0));
    expect(pairsBySymbol(none).keys.toSet(), statics.toSet());
    expect(optedOut.toJson(), none.toJson());
  });

  test('layout JSON may override the catalog defaults', () {
    Map<String, Object?> layout([Map<String, Object?> extra = const {}]) => {
      'levelId': 'lvl',
      'title': 'T',
      'difficulty': 'easy',
      'seed': 1,
      'symbols': statics,
      'board': {'tileWidth': 2, 'tileHeight': 2},
      'slots': [
        {'x': 0, 'y': 0, 'layer': 0},
        {'x': 2, 'y': 0, 'layer': 0},
      ],
      ...extra,
    };
    final defaults = LayoutTemplate.fromJson(layout(), defaultAnimatedSymbols: ['X'], defaultAnimatedShare: 0.3);
    expect(defaults.animatedSymbols, ['X']);
    expect(defaults.animatedShare, 0.3);
    final overridden = LayoutTemplate.fromJson(
      layout({
        'animatedSymbols': ['Y', 'Z'],
        'animatedShare': 0.5,
      }),
      defaultAnimatedSymbols: ['X'],
    );
    expect(overridden.animatedSymbols, ['Y', 'Z']);
    expect(overridden.animatedShare, 0.5);
    final plain = LayoutTemplate.fromJson(layout());
    expect(plain.animatedSymbols, isEmpty);
    expect(plain.animatedShare, kDefaultAnimatedShare);
  });

  test('rejects bad shares and symbols listed as both static and animated', () {
    expect(() => const LevelGenerator().generate(template(share: 1.5)), throwsA(isA<LevelGenerationException>()));
    expect(
      () => const LevelGenerator().generate(template(animatedSymbols: ['A', 'X'])),
      throwsA(isA<LevelGenerationException>()),
    );
  });
}

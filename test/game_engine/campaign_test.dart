import 'dart:convert';
import 'dart:io';

import 'package:brain_train/game_engine/campaign/board_shapes.dart';
import 'package:brain_train/game_engine/campaign/campaign_config.dart';
import 'package:brain_train/game_engine/campaign/campaign_generator.dart';
import 'package:brain_train/game_engine/campaign/seeded_random.dart';
import 'package:brain_train/game_engine/campaign/tier_schedule.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/tile_definition.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/level_validator.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/game_engine/validation/tray_simulator.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The campaign settings of the real catalog.
CampaignConfig catalogCampaign() =>
    CampaignConfig.fromJson((jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map)['campaign']);

/// A small campaign that generates in a moment: three tiers, four levels each.
CampaignConfig miniCampaign({int seed = 7}) => CampaignConfig.fromJson({
  'seed': seed,
  'simulationRuns': 40,
  'tiers': [
    {'id': 'easy', 'count': 4, 'tiles': [24, 40], 'layers': [1, 2], 'pairsPerStaticSymbol': 2.5, 'winRate': [0.6, 1]},
    {'id': 'medium', 'count': 4, 'tiles': [48, 72], 'layers': [2, 3], 'pairsPerStaticSymbol': 2},
    {
      'id': 'veryHard',
      'count': 4,
      'tiles': [144, 176],
      'layers': [5, 7],
      'trayCapacity': 5,
      'pairsPerStaticSymbol': 1.25,
      'pairsPerAnimatedSymbol': 2.2,
      'stalePairing': 0.2,
    },
  ],
});

List<String> codes(String prefix, int count) => [for (var i = 0; i < count; i++) '$prefix$i'];

void main() {
  group('randomness is pinned', () {
    test('mulberry32 and the string hash give the same numbers on every SDK', () {
      final random = SeededRandom(42);
      expect([for (var i = 0; i < 4; i++) random.nextUint32()], [2581720956, 1925393290, 3661312704, 2876485805]);
      expect(stableHash(['brain', 'train', 1]), 2438985116);
      expect(stableHash(['']), 2872998923);
    });
  });

  group('tier schedule', () {
    test('the catalog: 50 levels per tier, level 1 easy, never three of a tier in a row', () {
      final config = catalogCampaign();
      final order = scheduleTiers(config);
      expect(config.tiers.map((t) => t.id), ['easy', 'medium', 'hard', 'veryHard']);
      expect(order, hasLength(200));
      for (final tier in config.tiers) {
        expect(order.where((t) => t == tier.id), hasLength(tier.count), reason: tier.id);
        expect(tier.count, 50);
      }
      expect(order.first, 'easy');
      expect(longestRun(order), lessThanOrEqualTo(2));
      expect(scheduleTiers(config), order, reason: 'deterministic');
    });

    test('tiers are data: any set, counts and run limit', () {
      final config = CampaignConfig.fromJson({
        'seed': 3,
        'firstTier': 'calm',
        'maxTierRun': 1,
        'tiers': [
          {'id': 'calm', 'count': 7, 'tiles': [24, 30], 'layers': [1, 1]},
          {'id': 'brisk', 'count': 7, 'tiles': [24, 30], 'layers': [1, 1]},
          {'id': 'wild', 'count': 6, 'tiles': [24, 30], 'layers': [1, 1]},
        ],
      });
      final order = scheduleTiers(config);
      expect(order.first, 'calm');
      expect(longestRun(order), 1);
      expect({for (final id in ['calm', 'brisk', 'wild']) id: order.where((t) => t == id).length}, {
        'calm': 7,
        'brisk': 7,
        'wild': 6,
      });
      expect(scheduleTiers(CampaignConfig.fromJson({...jsonDecode(jsonEncode({'seed': 4})), 'tiers': [
        {'id': 'easy', 'count': 3, 'tiles': [24, 30], 'layers': [1, 1]},
        {'id': 'hard', 'count': 3, 'tiles': [24, 30], 'layers': [1, 1]},
      ]})), hasLength(6));
    });

    test('labels: known and new tier ids read well', () {
      expect(difficultyLabel('easy'), 'Easy');
      expect(difficultyLabel('veryHard'), 'Very Hard');
      expect(difficultyLabel('veryVeryHard'), 'Very Very Hard');
      expect(difficultyLabel('expert'), 'Expert');
    });

    test('bad configs are rejected', () {
      Map<String, Object?> tier(String id, {Object? capacity}) => {
        'id': id,
        'count': 2,
        'tiles': [24, 30],
        'layers': [1, 1],
        'trayCapacity': ?capacity,
      };
      expect(() => CampaignConfig.fromJson({'seed': 1, 'tiers': <Object?>[]}), throwsA(anything));
      expect(() => CampaignConfig.fromJson({'seed': 1, 'animatedShare': 0.4, 'tiers': [tier('easy')]}), throwsA(anything));
      expect(() => CampaignConfig.fromJson({'seed': 1, 'tiers': [tier('easy'), tier('easy')]}), throwsA(anything));
      expect(() => CampaignConfig.fromJson({'seed': 1, 'firstTier': 'hard', 'tiers': [tier('easy')]}), throwsA(anything));
    });
  });

  group('board shapes', () {
    test('the fit constants match the tile style', () {
      const style = TileStyle.classicIvory;
      expect(kFitFaceAspect, style.faceAspect);
      expect(kFitEdgeFraction, closeTo(style.edgeFraction, 1e-3));
      expect(kFitLayerOffset, 0.07);
    });

    test('every family builds valid, mirror-symmetric, even boards', () {
      for (final family in shapeFamilies) {
        var checked = 0;
        for (final shape in familyShapes(family, maxLayers: 5)) {
          // A sample of each family keeps the test fast.
          if (checked++ % 7 != 0) continue;
          expect(shape.tileCount.isEven, isTrue, reason: shape.describe);
          final slots = shape.slots;
          final level = LevelDefinition(
            levelId: 'shape',
            title: 'shape',
            tiles: [
              for (var i = 0; i < slots.length; i++)
                TileDefinition(tileId: 't$i', symbolCode: 'X', x: slots[i].x, y: slots[i].y, layer: slots[i].layer),
            ],
          );
          final geometry = BoardGeometry.build(level);
          expect(geometry.sameLayerOverlaps, isEmpty, reason: shape.describe);
          expect(geometry.unsupportedTiles, isEmpty, reason: shape.describe);
          final (minX, _, maxX, _) = shape.bounds;
          for (final layer in shape.layers) {
            for (final (x, y) in layer) {
              expect(layer.contains((minX + maxX - x - 2, y)), isTrue, reason: '${shape.describe}: mirror of ($x, $y)');
            }
          }
        }
        expect(checked, greaterThan(0), reason: family);
      }
    });
  });

  group('simulated tray player', () {
    test('plays exactly the game rules: replaying its taps through GameEngine gives the same result', () {
      final config = miniCampaign();
      final levels = CampaignGenerator(
        config: config,
        staticPool: codes('S', 30),
        animatedPool: codes('A', 12),
      ).generate();
      final reg = registry({...codes('S', 30), ...codes('A', 12)});
      for (final generated in [levels.first, levels[5], levels.last]) {
        final level = generated.level;
        final geometry = BoardGeometry.build(level);
        final rules = MatchRules(level: level, registry: reg);
        final simulator = TraySimulator.forRules(geometry, rules, capacity: level.rules.trayCapacity);
        final random = SeededRandom(11);
        for (var game = 0; game < 30; game++) {
          final taps = <int>[];
          final cleared = simulator.play(random, player: game.isEven ? TrayPlayer.random : TrayPlayer.pairSeeking, onTake: taps.add);
          final engine = GameEngine(level: level, rules: rules, geometry: geometry);
          for (final index in taps) {
            expect(engine.tap(level.tiles[index].tileId).accepted, isTrue);
          }
          expect(engine.state.matchedPairs * 2, cleared);
          expect(engine.state.status, cleared == level.tiles.length ? GameStatus.won : GameStatus.trayFull);
        }
      }
    });
  });

  group('campaign generator', () {
    final config = miniCampaign();
    // Pools larger than any level needs, as in the real campaign (a pool that
    // is too small caps the distinct symbols and so changes the structure).
    final statics = codes('S', 60), animated = codes('A', 14);
    late List<CampaignLevel> levels;
    setUpAll(() => levels = CampaignGenerator(config: config, staticPool: statics, animatedPool: animated).generate());

    test('is deterministic: same seed and symbols, same bytes', () {
      final again = CampaignGenerator(config: config, staticPool: statics, animatedPool: animated).generate();
      expect([for (final l in again) jsonEncode(l.level.toJson())], [for (final l in levels) jsonEncode(l.level.toJson())]);
      // The order of the pools does not matter either.
      final shuffled = CampaignGenerator(
        config: config,
        staticPool: statics.reversed.toList(),
        animatedPool: animated.reversed.toList(),
      ).generate();
      expect([for (final l in shuffled) jsonEncode(l.level.toJson())], [for (final l in levels) jsonEncode(l.level.toJson())]);
    });

    test('levels are valid, solvable, in their tier ranges and use the tier tray', () {
      final reg = registry({...statics, ...animated});
      final tiers = scheduleTiers(config);
      for (final l in levels) {
        final level = l.level;
        expect(level.difficulty, tiers[l.order - 1]);
        expect(level.levelId, CampaignGenerator.levelIdFor(l.order));
        final tier = config.tier(level.difficulty!);
        expect(level.tiles.length, inInclusiveRange(tier.minTiles, tier.maxTiles), reason: level.levelId);
        expect(l.layers, inInclusiveRange(tier.minLayers, tier.maxLayers), reason: level.levelId);
        expect(level.rules.trayCapacity, tier.trayCapacity);
        expect(l.shape.smallPhoneFaceWidth, greaterThanOrEqualTo(config.minFaceWidth));
        final report = LevelValidator(registry: reg).validate(level, checkSolvable: true, solverNodeBudget: 2000000);
        expect(report.isValid, isTrue, reason: '${level.levelId}: ${report.errors}');
        expect(report.solve!.outcome, SolveOutcome.solvable);
      }
      expect(levels.map((l) => l.level.title).toSet(), hasLength(levels.length), reason: 'unique titles');
    });

    test('the generator removal order is a valid pair-by-pair solution', () {
      final reg = registry({...statics, ...animated});
      for (final l in levels) {
        final engine = GameEngine(level: l.level, rules: MatchRules(level: l.level, registry: reg));
        for (final (a, b) in l.solution) {
          expect(engine.tap(l.level.tiles[a].tileId).accepted, isTrue);
          expect(engine.tap(l.level.tiles[b].tileId).outcome, isIn([TapOutcome.matched]));
        }
        expect(engine.state.status, GameStatus.won);
      }
    });

    test('70/30: floor(30%) of the pairs animated (at least one), distinct animated capped', () {
      for (final l in levels) {
        final tiles = l.level.tiles;
        final animatedTiles = tiles.where((t) => t.symbolCode.startsWith('A')).length;
        final pairs = tiles.length ~/ 2;
        expect(animatedTiles ~/ 2, (pairs * 0.3).floor().clamp(1, pairs), reason: l.level.levelId);
        expect(animatedTiles / tiles.length, lessThanOrEqualTo(0.3));
        final distinctAnimated = tiles.map((t) => t.symbolCode).where((c) => c.startsWith('A')).toSet();
        expect(distinctAnimated.length, lessThanOrEqualTo(config.maxDistinctAnimated));
        expect(distinctAnimated, l.animatedSymbols.toSet());
      }
      // The biggest boards reuse animated symbols for two or more pairs.
      final biggest = levels.reduce((a, b) => a.level.tiles.length > b.level.tiles.length ? a : b);
      expect(biggest.animatedPairs, greaterThanOrEqualTo(2 * biggest.animatedSymbols.length - 1));
      expect(biggest.animatedSymbols.length, lessThanOrEqualTo(config.maxDistinctAnimated));
    });

    test('new symbols change only symbol codes, never boards, tiers, titles or difficulty', () {
      final more = CampaignGenerator(
        config: config,
        staticPool: [...statics, ...codes('NEW', 6)],
        animatedPool: [...animated, ...codes('ANEW', 3)],
      ).generate();
      var changed = 0;
      for (var i = 0; i < levels.length; i++) {
        final a = levels[i], b = more[i];
        expect(b.level.title, a.level.title);
        expect(b.level.difficulty, a.level.difficulty);
        expect(b.level.backdrop!.colors, a.level.backdrop!.colors);
        expect(b.level.rules.trayCapacity, a.level.rules.trayCapacity);
        expect([for (final t in b.level.tiles) (t.x, t.y, t.layer)], [for (final t in a.level.tiles) (t.x, t.y, t.layer)]);
        expect(b.simulation.winRate, a.simulation.winRate, reason: 'difficulty does not depend on which codes');
        // Tiles that shared a symbol still do.
        final pairsA = _sameSymbolPairs(a.level), pairsB = _sameSymbolPairs(b.level);
        expect(pairsB, pairsA);
        if (jsonEncode(a.level.toJson()) != jsonEncode(b.level.toJson())) {
          changed++;
          expect(
            {...b.staticSymbols, ...b.animatedSymbols}.any((c) => c.startsWith('NEW') || c.startsWith('ANEW')),
            isTrue,
            reason: '${a.level.levelId} changed although no new symbol ranks in it',
          );
        }
      }
      expect(changed, greaterThan(0));
    });

    test('symbol subsets differ from level to level', () {
      for (var i = 1; i < levels.length; i++) {
        final a = {...levels[i - 1].staticSymbols, ...levels[i - 1].animatedSymbols};
        final b = {...levels[i].staticSymbols, ...levels[i].animatedSymbols};
        expect(a, isNot(equals(b)));
      }
    });
  });
}

/// For each tile, the tiles carrying the same symbol (by index).
List<Set<int>> _sameSymbolPairs(LevelDefinition level) {
  final byCode = <String, Set<int>>{};
  for (var i = 0; i < level.tiles.length; i++) {
    (byCode[level.tiles[i].symbolCode] ??= {}).add(i);
  }
  return [for (var i = 0; i < level.tiles.length; i++) byCode[level.tiles[i].symbolCode]!];
}

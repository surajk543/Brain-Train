import 'dart:convert';
import 'dart:io';

import 'package:brain_train/game_engine/campaign/board_shapes.dart';
import 'package:brain_train/game_engine/campaign/campaign_config.dart';
import 'package:brain_train/game_engine/campaign/campaign_generator.dart';
import 'package:brain_train/game_engine/campaign/seeded_random.dart';
import 'package:brain_train/game_engine/campaign/tier_schedule.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/board_grid.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/tile_definition.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/depth_rules.dart';
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
      'tiles': [84, 126],
      'layers': [4, 4],
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
    // Batch 2 needs over a million restarts (about 2 s): schedule the catalog once.
    late final catalogOrder = scheduleTiers(catalogCampaign());

    test('the catalog: difficulty 1-10, 10 levels each, level 1 is 1, never three of a tier in a row', () {
      final config = catalogCampaign();
      final order = catalogOrder;
      expect(config.tiers.map((t) => t.id), [for (var d = 1; d <= 10; d++) '$d']);
      expect(order, hasLength(config.levelCount));
      for (final tier in config.tiers) {
        expect(order.where((t) => t == tier.id), hasLength(config.batches.fold<int>(0, (n, b) => n + (b[tier.id] ?? 0))), reason: tier.id);
        expect(config.countIn(0, tier.id), 10);
      }
      expect(order.first, '1');
      expect(longestRun(order), lessThanOrEqualTo(2));
      expect(scheduleTiers(config), order, reason: 'deterministic');
    });

    test('the catalog: the published tier order is pinned, batch by batch', () {
      // Published levels depend on this order: a change to the schedule (its
      // draw, restart limit or the catalog) must never move a published level.
      const batch1 =
          '1 2 1 4 4 5 2 6 1 1 3 8 6 7 8 7 4 3 4 10 3 10 9 5 8 4 5 6 8 8 1 7 5 10 6 2 3 9 10 1 '
          '2 8 10 4 9 6 3 7 7 2 7 7 3 1 9 5 8 7 8 1 1 6 3 9 6 6 9 10 7 10 3 10 6 5 5 3 2 9 10 2 '
          '7 8 1 10 2 4 8 4 5 3 9 9 4 6 2 2 5 4 9 5';
      // 25 of difficulty 9 and 50 of 10 only fit as "10 10 9" repeats; the
      // draw finds one at restart 1,263,282 (maxScheduleAttempts).
      const batch2 =
          '10 10 9 10 10 9 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 '
          '10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 10 9 10 9 '
          '10 10 9 10 10';
      // 500 levels of difficulty 5-10 (84 / 84 / 83 / 83 / 83 / 83).
      const batch3 =
          '5 10 10 7 5 9 9 6 6 5 5 10 6 9 10 9 8 10 9 5 7 8 10 6 7 7 6 7 9 7 7 6 8 10 6 8 9 7 5 6 '
          '10 8 10 8 8 9 7 10 5 8 7 9 10 9 7 7 5 8 10 9 9 5 7 5 7 7 5 9 7 5 8 10 10 7 7 8 10 9 10 7 '
          '5 9 8 7 5 9 5 5 8 8 10 9 10 8 5 8 6 10 6 7 10 8 6 9 5 8 5 8 6 8 6 6 10 8 8 5 8 9 5 5 '
          '6 7 6 10 10 5 6 5 7 8 7 10 7 5 7 6 5 10 6 8 10 8 6 9 9 7 6 6 10 7 6 10 5 10 6 8 9 6 7 5 '
          '6 9 9 6 9 9 6 10 6 8 10 9 10 6 7 5 5 9 7 6 7 5 5 8 7 7 6 7 8 6 7 8 5 9 10 10 7 10 8 6 '
          '6 10 7 5 5 9 9 8 9 7 8 7 5 6 7 6 9 7 9 8 10 8 9 8 9 5 8 7 10 8 7 8 9 6 7 8 9 6 6 7 '
          '8 5 6 6 10 9 8 5 6 7 6 6 5 6 8 8 6 7 5 9 6 8 8 5 5 10 7 7 8 10 9 9 10 10 7 9 9 8 6 8 '
          '8 6 5 9 10 5 10 10 6 7 5 10 10 9 6 7 5 10 10 5 10 6 5 9 10 5 5 9 8 8 6 6 8 7 6 5 8 7 6 5 '
          '7 8 9 9 7 6 9 6 6 5 5 6 9 7 5 7 7 9 8 7 7 5 5 7 5 10 9 10 10 5 10 9 10 10 5 6 6 10 5 6 '
          '5 9 9 7 10 7 7 8 10 9 9 10 6 5 10 6 8 7 8 9 9 8 8 10 9 10 9 10 9 9 6 5 8 9 7 5 5 10 6 7 '
          '5 9 9 6 8 8 6 7 6 10 9 10 5 6 9 5 6 6 10 10 8 10 9 5 10 7 10 8 7 8 9 9 8 8 6 9 8 10 8 7 '
          '5 6 9 5 6 7 8 7 9 10 8 8 9 7 10 7 5 9 10 5 8 9 8 8 6 5 5 7 6 7 5 6 10 10 9 5 10 6 6 7 '
          '10 8 5 10 9 6 5 7 8 5 5 9 8 8 6 5 7 7 8 9';
      expect(catalogOrder.sublist(0, 100).join(' '), batch1);
      expect(catalogOrder.sublist(100, 175).join(' '), batch2);
      expect(catalogOrder.sublist(175, 675).join(' '), batch3);
      expect(catalogOrder, hasLength(675));
      // The batch-1 order is the same with the old restart limit: raising it
      // changed no published level.
      final firstBatch = CampaignConfig.fromJson({
        ...(jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map)['campaign'] as Map<String, Object?>,
        'batches': [catalogCampaign().batches.first],
      });
      expect(scheduleTiers(firstBatch, maxAttempts: 10000).join(' '), batch1);
    });

    test('the catalog: trays shrink as difficulty rises, within 2-5', () {
      final config = catalogCampaign();
      for (var i = 0; i < config.tiers.length; i++) {
        final tier = config.tiers[i];
        expect(tier.trayCapacity, inInclusiveRange(2, 5), reason: tier.id);
        expect(tier.maxTrayCapacity, inInclusiveRange(tier.trayCapacity, 5), reason: tier.id);
        if (i > 0) expect(tier.maxTrayCapacity, lessThanOrEqualTo(config.tiers[i - 1].maxTrayCapacity), reason: tier.id);
      }
      expect(config.animatedShare, 0.15);
    });

    test('a tray range is picked per level, seeded and inside the range', () {
      final config = CampaignConfig.fromJson({
        'seed': 5,
        'tiers': [
          {'id': 'easy', 'count': 4, 'tiles': [24, 30], 'layers': [1, 1], 'trayCapacity': [2, 5]},
        ],
      });
      final tier = config.tiers.single;
      final picks = [for (var order = 1; order <= 60; order++) config.trayCapacityFor(order, tier)];
      expect(picks.toSet(), {2, 3, 4, 5});
      expect([for (var order = 1; order <= 60; order++) config.trayCapacityFor(order, tier)], picks, reason: 'deterministic');
    });

    test('appending a batch never changes the levels before it', () {
      Map<String, Object?> campaign(List<Map<String, int>> batches) => {
        'seed': 9,
        'firstTier': '1',
        'batches': batches,
        'tiers': [
          for (final id in ['1', '2', '3']) {'id': id, 'tiles': [24, 30], 'layers': [1, 1]},
        ],
      };
      final first = scheduleTiers(CampaignConfig.fromJson(campaign([{'1': 4, '2': 4, '3': 4}])));
      final longer = scheduleTiers(CampaignConfig.fromJson(campaign([{'1': 4, '2': 4, '3': 4}, {'2': 3, '3': 5}])));
      expect(longer, hasLength(20));
      expect(longer.sublist(0, 12), first);
      expect(longer.sublist(12).where((t) => t == '3'), hasLength(5));
      expect(longestRun(longer), lessThanOrEqualTo(2));
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
      expect(difficultyLabel('1'), '1/10');
      expect(difficultyLabel('10'), '10/10');
      expect(difficultyLabel('11'), '11', reason: 'off the scale');
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
      expect(() => CampaignConfig.fromJson({'seed': 1, 'tiers': [tier('easy', capacity: 6)]}), throwsA(anything));
      expect(() => CampaignConfig.fromJson({'seed': 1, 'tiers': [tier('easy', capacity: [5, 3])]}), throwsA(anything));
      expect(() => CampaignConfig.fromJson({'seed': 1, 'firstTier': '0', 'tiers': [tier('0')]}), throwsA(anything));
    });
  });

  group('board shapes', () {
    test('the fit constants match the tile style', () {
      const style = TileStyle.classicIvory;
      expect(kFitFaceAspect, style.faceAspect);
      expect(kFitEdgeFraction, closeTo(style.edgeFraction, 1e-3));
      expect(kFitLayerOffset, 0.07);
    });

    test('the fixed grid gives faces of at least minFaceWidth on a 360x640 phone', () {
      expect(gridFaceWidthIn(kSmallBoardWidth, kSmallBoardHeight), greaterThanOrEqualTo(catalogCampaign().minFaceWidth));
    });

    test('every family builds valid, mirror-symmetric, even boards inside the grid, with depth showing', () {
      for (final family in shapeFamilies) {
        var checked = 0;
        for (final shape in familyShapes(family)) {
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
          expect(shape.fitsGrid, isTrue, reason: shape.describe);
          expect(geometry.bounds.width, lessThanOrEqualTo(2 * kBoardGridColumns), reason: shape.describe);
          expect(geometry.bounds.height, lessThanOrEqualTo(2 * kBoardGridRows), reason: shape.describe);
          expect(shape.layerCount, lessThanOrEqualTo(kBoardGridLayers), reason: shape.describe);
          // Depth shows: nothing exactly on top of anything, a quarter of
          // every tile uncovered.
          expect(stackedTiles(geometry), isEmpty, reason: shape.describe);
          expect(visibleQuarters(geometry).every((v) => v >= kMinVisibleQuarters), isTrue, reason: shape.describe);
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
        expect(l.shape.fitsGrid, isTrue, reason: level.levelId);
        // 1 or 2 single pairs have a face colour (validated below too).
        expect(level.faceColors.length, inInclusiveRange(1, 2), reason: level.levelId);
        final report = LevelValidator(
          registry: reg,
        ).validate(level, checkSolvable: true, solverNodeBudget: 2000000, checkCampaignRules: true);
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
      // Levels before the first one that ranks a new symbol keep their bytes;
      // from there on, codes may move along (least used first).
      final firstNew = more.indexWhere(
        (l) => {...l.staticSymbols, ...l.animatedSymbols}.any((c) => c.startsWith('NEW') || c.startsWith('ANEW')),
      );
      expect(firstNew, greaterThanOrEqualTo(0));
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
          expect(i, greaterThanOrEqualTo(firstNew), reason: '${a.level.levelId} changed before any new symbol ranks');
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

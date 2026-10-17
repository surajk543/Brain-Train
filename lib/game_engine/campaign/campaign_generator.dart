import 'dart:math' as math;

import '../generator/level_generator.dart';
import '../geometry/board_geometry.dart';
import '../geometry/board_grid.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../models/board_config.dart';
import '../models/level_definition.dart';
import '../models/level_rules.dart';
import '../models/symbol_registry.dart';
import '../models/tile_definition.dart';
import '../rules/match_rules.dart';
import '../validation/solver.dart';
import '../validation/tray_simulator.dart';
import 'board_shapes.dart';
import 'campaign_config.dart';
import 'level_names.dart';
import 'seeded_random.dart';
import 'tier_schedule.dart';

/// One generated campaign level with the facts the build reports on.
class CampaignLevel {
  CampaignLevel({
    required this.order,
    required this.tier,
    required this.shape,
    required this.level,
    required this.solution,
    required this.simulation,
    required this.pairSeekingSimulation,
    required this.staticPairs,
    required this.animatedPairs,
    required this.staticSymbols,
    required this.animatedSymbols,
    required this.attempts,
  });

  final int order;
  final TierSpec tier;
  final BoardShape shape;
  final LevelDefinition level;

  /// The removal order the symbols were placed for: tile index pairs that
  /// clear the board (a pair-order proof, checked again by the solver).
  final List<(int, int)> solution;
  /// The calibration player ([TrayPlayer.random]).
  final TraySimulation simulation;

  /// A player that also takes pairs it sees on the board, for reference.
  final TraySimulation pairSeekingSimulation;
  final int staticPairs;
  final int animatedPairs;

  /// Distinct symbol codes, in the order their abstract slots were filled.
  final List<String> staticSymbols;
  final List<String> animatedSymbols;

  /// Boards tried before this one was accepted.
  final int attempts;

  int get pairs => level.pairCount;
  int get layers => shape.layerCount;
  int get freeAtStart => shape.freeAtStart;
}

/// Generates the whole campaign from a [CampaignConfig] and the integrated
/// symbol pools.
///
/// Reproducible: the same config and pools give the same levels, byte for
/// byte. The board, title, backdrop, removal order, how many symbols a level
/// has and which pairs share one depend only on the config and the level
/// number; the symbol pools only decide which codes fill those slots. Level
/// by level, the codes used least so far come first (ties broken by a hash
/// of the level and the code), so every symbol is on some level before any
/// symbol is on many. A new symbol therefore changes codes (from the first
/// level that picks it on), never a board's shape, its difficulty or its
/// simulated win rate.
class CampaignGenerator {
  CampaignGenerator({
    required this.config,
    required List<String> staticPool,
    required List<String> animatedPool,
  }) : staticPool = List.unmodifiable({...staticPool}),
       animatedPool = List.unmodifiable({...animatedPool});

  final CampaignConfig config;
  final List<String> staticPool;
  final List<String> animatedPool;

  /// Boards tried per level before the closest one to the tier's win-rate
  /// band is taken.
  static const int maxAttempts = 36;

  final Map<String, List<BoardShape>> _shapesByTier = {};

  static String levelIdFor(int order) => 'level-${order.toString().padLeft(4, '0')}';

  List<CampaignLevel> generate({void Function(CampaignLevel level)? onLevel}) {
    if (staticPool.isEmpty) throw StateError('no static symbols');
    // Every board shows at the fixed grid's scale (boardProjectionFor).
    final face = gridFaceWidthIn(kSmallBoardWidth, kSmallBoardHeight);
    if (face < config.minFaceWidth) {
      throw StateError('the ${kBoardGridColumns}x$kBoardGridRows grid gives ${face.toStringAsFixed(1)}-px faces on a '
          '360x640 phone, below minFaceWidth ${config.minFaceWidth}');
    }
    final tiers = scheduleTiers(config);
    final decor = LevelDecor(config.seed, pinned: config.titles);
    final recentFamilies = <String>[];
    final familyUses = <String, int>{};
    final levels = <CampaignLevel>[];
    final uses = <String, int>{for (final code in [...staticPool, ...animatedPool]) code: 0};
    // Board size grows through a tier's levels within each batch.
    var batch = 0, batchStart = 0;
    var perTierIndex = <String, int>{};
    for (var i = 0; i < tiers.length; i++) {
      final order = i + 1;
      while (i - batchStart >= config.batches[batch].values.fold(0, (sum, n) => sum + n)) {
        batchStart += config.batches[batch].values.fold(0, (sum, n) => sum + n);
        batch++;
        perTierIndex = {};
      }
      final spec = config.tier(tiers[i]);
      final indexInTier = perTierIndex[spec.id] = (perTierIndex[spec.id] ?? -1) + 1;
      final count = config.countIn(batch, spec.id);
      final progress = count <= 1 ? 0.5 : indexInTier / (count - 1);
      final level = _generateLevel(order, spec, progress, recentFamilies, familyUses, decor, uses);
      for (final code in [...level.staticSymbols, ...level.animatedSymbols]) {
        uses[code] = uses[code]! + 1;
      }
      recentFamilies.add(level.shape.family);
      familyUses[level.shape.family] = (familyUses[level.shape.family] ?? 0) + 1;
      levels.add(level);
      onLevel?.call(level);
    }
    return levels;
  }

  List<BoardShape> _shapesFor(TierSpec spec) => _shapesByTier.putIfAbsent(spec.id, () {
    final allowed = spec.families.isEmpty ? shapeFamilies : spec.families;
    return [
      for (final family in allowed)
        for (final shape in familyShapes(family, maxLayers: spec.maxLayers))
          if (shape.tileCount >= spec.minTiles &&
              shape.tileCount <= spec.maxTiles &&
              shape.layerCount >= spec.minLayers &&
              shape.fitsGrid &&
              shape.freeRatio >= spec.minFreeRatio &&
              shape.freeRatio <= spec.maxFreeRatio)
            shape,
    ];
  });

  CampaignLevel _generateLevel(
    int order,
    TierSpec spec,
    double progress,
    List<String> recentFamilies,
    Map<String, int> familyUses,
    LevelDecor decor,
    Map<String, int> uses,
  ) {
    final levelId = levelIdFor(order);
    final trayCapacity = config.trayCapacityFor(order, spec);
    final shapes = _shapesFor(spec);
    if (shapes.isEmpty) throw StateError('tier ${spec.id}: no board fits its tile, layer, fit and free ranges');
    final random = SeededRandom.of(['board', config.seed, order]);
    final byFamily = <String, List<BoardShape>>{};
    for (final shape in shapes) {
      (byFamily[shape.family] ??= []).add(shape);
    }
    // Larger boards later in the campaign, with some noise.
    final target =
        spec.minTiles +
        (spec.maxTiles - spec.minTiles) * (0.1 + 0.8 * progress + (random.nextDouble() - 0.5) * 0.5).clamp(0.0, 1.0);

    final tried = <BoardShape>{};
    final usedFamilies = <String>[];
    _Built? best;
    var bestDistance = double.infinity;
    var attempts = 0;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      // A new family every few attempts, never one of the last three levels'.
      if (attempt % 3 == 0) {
        final recent = recentFamilies.length <= 3 ? recentFamilies : recentFamilies.sublist(recentFamilies.length - 3);
        var options = [
          for (final f in byFamily.keys)
            if (!recent.contains(f) && !usedFamilies.contains(f)) f,
        ];
        if (options.isEmpty) options = [for (final f in byFamily.keys) if (!usedFamilies.contains(f)) f];
        if (options.isEmpty) break;
        usedFamilies.add(_weightedFamily(options, familyUses, random));
      }
      final family = usedFamilies.last;
      final candidates = [
        for (final s in byFamily[family]!)
          if (!tried.contains(s)) s,
      ];
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) {
        final d = (a.tileCount - target).abs().compareTo((b.tileCount - target).abs());
        return d != 0 ? d : a.describe.compareTo(b.describe);
      });
      final shape = candidates[random.nextInt(math.min(4, candidates.length))];
      tried.add(shape);
      attempts++;
      final built = _build(levelId, spec, trayCapacity, shape, attempt);
      if (built == null) continue;
      final rate = built.simulation.winRate;
      final distance = rate < spec.minWinRate
          ? spec.minWinRate - rate
          : rate > spec.maxWinRate
          ? rate - spec.maxWinRate
          : 0.0;
      if (distance < bestDistance) {
        best = built;
        bestDistance = distance;
      }
      if (distance == 0) break;
    }
    if (best == null) throw StateError('$levelId (${spec.id}): no board could be filled');

    final title = decor.title(order, best.shape.family);
    final backdrop = decor.backdrop(order);
    final staticCodes = _rank('static', levelId, staticPool, best.distinctStatic, uses);
    final animatedCodes = _rank('animated', levelId, animatedPool, best.distinctAnimated, uses);
    final codes = [
      for (final id in best.tileSymbols) id < best.distinctStatic ? staticCodes[id] : animatedCodes[id - best.distinctStatic],
    ];
    final slots = best.slots;
    final faceColors = _faceColors(levelId, best, staticCodes);
    final level = LevelDefinition(
      levelId: levelId,
      title: title,
      difficulty: spec.id,
      board: const BoardConfig(),
      rules: LevelRules(trayCapacity: trayCapacity),
      backdrop: LevelBackdrop(colors: backdrop),
      faceColors: faceColors,
      tiles: [
        for (var i = 0; i < slots.length; i++)
          TileDefinition(
            tileId: 't${(i + 1).toString().padLeft(3, '0')}',
            symbolCode: codes[i],
            x: slots[i].x,
            y: slots[i].y,
            layer: slots[i].layer,
          ),
      ],
    );
    return CampaignLevel(
      order: order,
      tier: spec,
      shape: best.shape,
      level: level,
      solution: best.order,
      simulation: best.simulation,
      pairSeekingSimulation: TraySimulator(
        geometry: best.geometry,
        keys: best.tileSymbols,
        capacity: trayCapacity,
      ).run(runs: config.simulationRuns, seed: stableHash([config.seed, levelId, 'pairs']), player: TrayPlayer.pairSeeking),
      staticPairs: best.staticPairs,
      animatedPairs: best.animatedPairs,
      staticSymbols: staticCodes,
      animatedSymbols: animatedCodes,
      attempts: attempts,
    );
  }

  /// 1 or 2 single pairs (static symbols with exactly two tiles) get a face
  /// colour, seeded by the level (owner, 2026-10-17). Picked among abstract
  /// symbols, so new symbols change which codes are coloured, never which
  /// pairs.
  Map<String, String> _faceColors(String levelId, _Built built, List<String> staticCodes) {
    final tilesOf = <int, int>{};
    for (final id in built.tileSymbols) {
      tilesOf[id] = (tilesOf[id] ?? 0) + 1;
    }
    final single = [
      for (var id = 0; id < built.distinctStatic; id++)
        if (tilesOf[id] == 2) id,
    ];
    if (single.isEmpty) return const {};
    final random = SeededRandom.of(['faces', config.seed, levelId]);
    final count = math.min(single.length, 1 + random.nextInt(2));
    random.shuffle(single);
    final colours = [...kFaceColorNames];
    random.shuffle(colours);
    return {for (var i = 0; i < count; i++) staticCodes[single[i]]: colours[i]};
  }

  String _weightedFamily(List<String> options, Map<String, int> uses, SeededRandom random) {
    // Rarely used families first, so every shape keeps coming back.
    final weights = [for (final f in options) 1 / (1 + (uses[f] ?? 0))];
    var roll = random.nextDouble() * weights.fold(0.0, (a, b) => a + b);
    for (var i = 0; i < options.length; i++) {
      roll -= weights[i];
      if (roll < 0) return options[i];
    }
    return options.last;
  }

  /// The [count] codes of [pool] for [levelId]: the least used so far
  /// ([uses]), ties by a hash of the level and the code.
  List<String> _rank(String kind, String levelId, List<String> pool, int count, Map<String, int> uses) {
    if (count == 0) return const [];
    final scored = [for (final code in pool) (uses[code] ?? 0, stableHash([kind, config.seed, levelId, code]), code)]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3)));
    return [for (final (_, _, code) in scored.take(count)) code];
  }

  /// Animated pairs for [pairs] pairs: floor(pairs * share), at least one
  /// (when any animated symbol exists); the share is at most 30%.
  int animatedPairsFor(int pairs) {
    if (animatedPool.isEmpty || config.animatedShare <= 0 || pairs < 2) return 0;
    return math.max(1, (pairs * config.animatedShare).floor());
  }

  _Built? _build(String levelId, TierSpec spec, int trayCapacity, BoardShape shape, int attempt) {
    final slots = shape.slots;
    final blank = LevelDefinition(
      levelId: levelId,
      title: levelId,
      tiles: [
        for (var i = 0; i < slots.length; i++)
          TileDefinition(tileId: 't$i', symbolCode: '_', x: slots[i].x, y: slots[i].y, layer: slots[i].layer),
      ],
    );
    final geometry = BoardGeometry.build(blank);
    if (geometry.sameLayerOverlaps.isNotEmpty || geometry.unsupportedTiles.isNotEmpty) {
      throw StateError('${shape.describe}: overlapping or floating tiles');
    }
    final availability = TileAvailabilityCalculator(geometry);
    final orderRandom = SeededRandom.of(['order', config.seed, levelId, attempt]);
    List<(int, int)>? order;
    for (var tries = 0; tries < 400 && order == null; tries++) {
      order = _removalOrder(geometry, availability, orderRandom, spec.stalePairing);
    }
    if (order == null) return null;

    final pairs = order.length;
    final animatedPairs = animatedPairsFor(pairs);
    final staticPairs = pairs - animatedPairs;
    // At least ceil(pairs / maxPairsPerSymbol) symbols, so none repeats more.
    final cap = config.maxPairsPerSymbol;
    int atLeast(int pairs) => cap == null ? 1 : (pairs / cap).ceil();
    // At least one static symbol has a single pair (fewer than two pairs per
    // symbol on average), so the level can colour one.
    final distinctStatic = staticPairs == 0
        ? 0
        : math
              .max(math.max((staticPairs / spec.pairsPerStaticSymbol).round(), atLeast(staticPairs)), staticPairs ~/ 2 + 1)
              .clamp(1, math.min(staticPairs, staticPool.length))
              .toInt();
    final distinctAnimated = animatedPairs == 0
        ? 0
        : math
              .max((animatedPairs / spec.pairsPerAnimatedSymbol).ceil(), atLeast(animatedPairs))
              .clamp(1, math.min(animatedPairs, math.min(config.maxDistinctAnimated, animatedPool.length)))
              .toInt();
    // Abstract symbols 0..distinctStatic-1 are static, the rest animated;
    // each spread as evenly as possible over its pairs.
    final bag = [
      for (var p = 0; p < staticPairs; p++) p % distinctStatic,
      for (var p = 0; p < animatedPairs; p++) distinctStatic + p % distinctAnimated,
    ];
    SeededRandom.of(['symbols', config.seed, levelId, attempt]).shuffle(bag);
    final tileSymbols = List<int>.filled(slots.length, -1);
    for (var p = 0; p < pairs; p++) {
      tileSymbols[order[p].$1] = bag[p];
      tileSymbols[order[p].$2] = bag[p];
    }
    // The solver must prove it too (as the build and the tests do): a board
    // whose proof would exhaust the budget is replaced. Abstract codes give
    // the solver exactly the search it does on the real ones.
    final keyed = LevelDefinition(
      levelId: levelId,
      title: levelId,
      tiles: [
        for (var i = 0; i < slots.length; i++)
          TileDefinition(tileId: 't$i', symbolCode: 'K${tileSymbols[i]}', x: slots[i].x, y: slots[i].y, layer: slots[i].layer),
      ],
    );
    final solve = MahjongSolver(
      geometry: geometry,
      rules: MatchRules(level: keyed, registry: SymbolRegistry(registryVersion: 'abstract', symbols: const {})),
      maxNodes: config.solverBudget,
    ).solve(TileMask.all(slots.length));
    if (solve.outcome != SolveOutcome.solvable) return null;
    final simulation = TraySimulator(
      geometry: geometry,
      keys: tileSymbols,
      capacity: trayCapacity,
    ).run(runs: config.simulationRuns, seed: stableHash([config.seed, levelId, attempt]));
    return _Built(
      shape: shape,
      geometry: geometry,
      slots: slots,
      order: order,
      tileSymbols: tileSymbols,
      staticPairs: staticPairs,
      animatedPairs: animatedPairs,
      distinctStatic: distinctStatic,
      distinctAnimated: distinctAnimated,
      simulation: simulation,
      solverNodes: solve.nodesVisited,
    );
  }

  /// Clears the empty board pair by pair, the pairs being tiles free at the
  /// same moment, so giving each pair one symbol makes the level solvable by
  /// construction. With probability [stale] a pair joins the tile that
  /// became free last with the one that has waited longest; otherwise both
  /// are weighted picks that favour high, stacked tiles (two tiles stacked
  /// on each other can never both be free, so stacks must not be left for
  /// last). Null on a dead end.
  static List<(int, int)>? _removalOrder(
    BoardGeometry geometry,
    TileAvailabilityCalculator availability,
    SeededRandom random,
    double stale,
  ) {
    final n = geometry.length;
    final remaining = TileMask.all(n);
    final freeSince = List<int>.filled(n, -1);
    final order = <(int, int)>[];
    for (var step = 0; !remaining.isEmpty; step++) {
      final free = availability.freeTiles(remaining);
      for (final index in free) {
        if (freeSince[index] < 0) freeSince[index] = step;
      }
      if (free.length < 2) return null;
      int a, b;
      if (stale > 0 && random.chance(stale)) {
        final newest = free.map((i) => freeSince[i]).reduce(math.max);
        final fresh = [for (final i in free) if (freeSince[i] == newest) i];
        a = _weighted(fresh, geometry, random);
        final rest = [for (final i in free) if (i != a) i];
        final oldest = rest.map((i) => freeSince[i]).reduce(math.min);
        b = random.pick([for (final i in rest) if (freeSince[i] == oldest) i]);
      } else {
        a = _weighted(free, geometry, random);
        b = _weighted([for (final i in free) if (i != a) i], geometry, random);
      }
      remaining
        ..remove(a)
        ..remove(b);
      order.add((a, b));
    }
    return order;
  }

  static int _weighted(List<int> free, BoardGeometry geometry, SeededRandom random) {
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

class _Built {
  _Built({
    required this.shape,
    required this.geometry,
    required this.slots,
    required this.order,
    required this.tileSymbols,
    required this.staticPairs,
    required this.animatedPairs,
    required this.distinctStatic,
    required this.distinctAnimated,
    required this.simulation,
    required this.solverNodes,
  });

  final BoardShape shape;
  final BoardGeometry geometry;
  final List<LayoutSlot> slots;
  final List<(int, int)> order;
  final List<int> tileSymbols;
  final int staticPairs;
  final int animatedPairs;
  final int distinctStatic;
  final int distinctAnimated;
  final TraySimulation simulation;
  final int solverNodes;
}

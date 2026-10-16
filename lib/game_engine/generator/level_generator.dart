import 'dart:math';

import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../models/board_config.dart';
import '../models/json_reader.dart';
import '../models/level_definition.dart';
import '../models/level_rules.dart';
import '../models/tile_definition.dart';

/// One empty tile position of an authored layout.
class LayoutSlot {
  const LayoutSlot(this.x, this.y, this.layer);

  final double x;
  final double y;
  final int layer;
}

/// Default share of a level's pairs that get animated symbols.
const double kDefaultAnimatedShare = 0.2;

/// An authored board shape without symbols, plus how to fill it.
///
/// Authoring JSON accepts explicit `slots` and/or rectangular `blocks`:
/// `{"layer": 0, "x": 0, "y": 0, "columns": 4, "rows": 3}` expands to a
/// grid stepped by one footprint (`stepX`/`stepY` override the step).
///
/// Optional `animatedSymbols` (codes) and `animatedShare` (0-1) override the
/// defaults passed to [LayoutTemplate.fromJson] (normally from the catalog).
class LayoutTemplate {
  LayoutTemplate({
    required this.levelId,
    required this.title,
    required this.difficulty,
    required this.board,
    required this.slots,
    required this.symbols,
    required this.seed,
    this.rules = const LevelRules(),
    this.backdrop,
    this.animatedSymbols = const [],
    this.animatedShare = kDefaultAnimatedShare,
  });

  factory LayoutTemplate.fromJson(
    Object? decoded, {
    List<String> defaultAnimatedSymbols = const [],
    double defaultAnimatedShare = kDefaultAnimatedShare,
  }) {
    final json = JsonReader(decoded);
    final board = BoardConfig.fromJson(json.object('board'));
    final slots = <LayoutSlot>[];
    if (json.has('blocks')) {
      for (final block in json.objectList('blocks')) {
        final stepX = block.numberOr('stepX', board.tileWidth);
        final stepY = block.numberOr('stepY', board.tileHeight);
        final x0 = block.number('x'), y0 = block.number('y');
        for (var row = 0; row < block.integer('rows'); row++) {
          for (var col = 0; col < block.integer('columns'); col++) {
            slots.add(LayoutSlot(x0 + col * stepX, y0 + row * stepY, block.integer('layer')));
          }
        }
      }
    }
    if (json.has('slots')) {
      for (final slot in json.objectList('slots')) {
        slots.add(LayoutSlot(slot.number('x'), slot.number('y'), slot.integer('layer')));
      }
    }
    return LayoutTemplate(
      levelId: json.string('levelId'),
      title: json.string('title'),
      difficulty: json.string('difficulty'),
      board: board,
      slots: slots,
      symbols: json.stringList('symbols'),
      seed: json.integer('seed'),
      rules: json.has('rules') ? LevelRules.fromJson(json.object('rules')) : const LevelRules(),
      backdrop: json.has('backdrop') ? LevelBackdrop.fromJson(json.object('backdrop')) : null,
      animatedSymbols: json.has('animatedSymbols') ? json.stringList('animatedSymbols') : defaultAnimatedSymbols,
      animatedShare: json.numberOr('animatedShare', defaultAnimatedShare),
    );
  }

  /// A copy with other animated symbols or share.
  LayoutTemplate copyWith({List<String>? animatedSymbols, double? animatedShare}) => LayoutTemplate(
    levelId: levelId,
    title: title,
    difficulty: difficulty,
    board: board,
    slots: slots,
    symbols: symbols,
    seed: seed,
    rules: rules,
    backdrop: backdrop,
    animatedSymbols: animatedSymbols ?? this.animatedSymbols,
    animatedShare: animatedShare ?? this.animatedShare,
  );

  final String levelId;
  final String title;
  final String difficulty;
  final BoardConfig board;
  final List<LayoutSlot> slots;

  /// Static symbol codes to distribute over the static pairs, as evenly as
  /// possible.
  final List<String> symbols;
  final int seed;
  final LevelRules rules;
  final LevelBackdrop? backdrop;

  /// Animated symbol codes to distribute over the animated pairs, as evenly
  /// as possible. Empty: every pair is static.
  final List<String> animatedSymbols;

  /// Share of pairs that get an animated symbol; see
  /// [LevelGenerator.animatedPairCount].
  final double animatedShare;
}

class LevelGenerationException implements Exception {
  LevelGenerationException(this.message);

  final String message;

  @override
  String toString() => 'LevelGenerationException: $message';
}

/// Fills a [LayoutTemplate] with symbols so the level is solvable by
/// construction.
///
/// It simulates clearing the empty layout: each step picks two tiles that are
/// free at the same moment and gives them the same symbol. That removal order
/// is a valid solution, and also a winning tray game (tap each pair's tiles
/// in turn; see `MahjongSolver`). Dead ends (fewer than two free tiles) restart with
/// the next random stream. The result must still pass `LevelValidator` with
/// the solver before publishing: construction is not trusted on its own.
class LevelGenerator {
  const LevelGenerator({this.maxAttempts = 500});

  final int maxAttempts;

  /// How many of [pairs] pairs get an animated symbol:
  /// `round(pairs * animatedShare)`, at least 1 when the template has
  /// animated symbols and a positive share, at most every pair. The rest are
  /// static. E.g. 30 pairs at 0.2 give 6 animated and 24 static pairs.
  static int animatedPairCount(int pairs, LayoutTemplate template) {
    if (pairs <= 0 || template.animatedSymbols.isEmpty || template.animatedShare <= 0) return 0;
    return (pairs * template.animatedShare).round().clamp(1, pairs);
  }

  LevelDefinition generate(LayoutTemplate template) {
    if (template.slots.length.isOdd) {
      throw LevelGenerationException('${template.levelId}: ${template.slots.length} slots cannot be paired');
    }
    if (!(template.animatedShare >= 0 && template.animatedShare <= 1)) {
      throw LevelGenerationException('${template.levelId}: animatedShare must be between 0 and 1');
    }
    final both = template.symbols.toSet().intersection(template.animatedSymbols.toSet());
    if (both.isNotEmpty) {
      throw LevelGenerationException('${template.levelId}: ${both.join(', ')} listed as static and animated');
    }
    final pairs = template.slots.length ~/ 2;
    if (template.symbols.isEmpty && pairs - animatedPairCount(pairs, template) > 0) {
      throw LevelGenerationException('${template.levelId}: no symbols');
    }

    final blank = _level(template, [for (var i = 0; i < template.slots.length; i++) '_']);
    final geometry = BoardGeometry.build(blank);
    if (geometry.sameLayerOverlaps.isNotEmpty || geometry.unsupportedTiles.isNotEmpty) {
      throw LevelGenerationException('${template.levelId}: layout has overlapping or floating slots');
    }
    final availability = TileAvailabilityCalculator(geometry);
    final random = Random(template.seed);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final order = _removalOrder(geometry, availability, random);
      if (order == null) continue;
      final symbols = _symbolBag(template, order.length, random);
      final codes = List<String>.filled(template.slots.length, '');
      for (var p = 0; p < order.length; p++) {
        codes[order[p].$1] = symbols[p];
        codes[order[p].$2] = symbols[p];
      }
      return _level(template, codes);
    }
    throw LevelGenerationException('${template.levelId}: no removal order found in $maxAttempts attempts');
  }

  List<(int, int)>? _removalOrder(BoardGeometry geometry, TileAvailabilityCalculator availability, Random random) {
    final remaining = TileMask.all(geometry.length);
    final order = <(int, int)>[];
    while (!remaining.isEmpty) {
      final free = availability.freeTiles(remaining);
      if (free.length < 2) return null;
      final a = _pick(free, geometry, random);
      free.remove(a);
      final b = _pick(free, geometry, random);
      remaining
        ..remove(a)
        ..remove(b);
      order.add((a, b));
    }
    return order;
  }

  /// Weighted towards high, stacked tiles so stacks do not end up last
  /// (two stacked tiles can never both be free).
  int _pick(List<int> free, BoardGeometry geometry, Random random) {
    var total = 0;
    final weights = [for (final index in free) 1 + geometry.tiles[index].layer * 3 + geometry.covers[index].length];
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

  /// One symbol per pair. Without animated pairs this is exactly the original
  /// static bag, so existing levels regenerate byte-identically.
  List<String> _symbolBag(LayoutTemplate template, int pairs, Random random) {
    final symbols = template.symbols;
    final animated = animatedPairCount(pairs, template);
    if (animated == 0) return [for (var i = 0; i < pairs; i++) symbols[i % symbols.length]]..shuffle(random);
    // Shuffled first so small levels do not always get the same few animations.
    final pool = [...template.animatedSymbols]..shuffle(random);
    return [
      for (var i = 0; i < pairs - animated; i++) symbols[i % symbols.length],
      for (var i = 0; i < animated; i++) pool[i % pool.length],
    ]..shuffle(random);
  }

  LevelDefinition _level(LayoutTemplate template, List<String> codes) => LevelDefinition(
    levelId: template.levelId,
    title: template.title,
    difficulty: template.difficulty,
    board: template.board,
    rules: template.rules,
    backdrop: template.backdrop,
    tiles: [
      for (var i = 0; i < template.slots.length; i++)
        TileDefinition(
          tileId: 't${(i + 1).toString().padLeft(3, '0')}',
          symbolCode: codes[i],
          x: template.slots[i].x,
          y: template.slots[i].y,
          layer: template.slots[i].layer,
        ),
    ],
  );
}

import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../models/level_definition.dart';
import '../models/level_rules.dart';
import '../models/symbol_registry.dart';
import '../rules/match_rules.dart';
import 'solver.dart';

final RegExp _levelIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
final RegExp _tileIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _groupNamePattern = RegExp(r'^[A-Z0-9_]{1,40}$');
final RegExp _colorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

class ValidationIssue {
  const ValidationIssue(this.code, this.message);

  /// Stable machine-readable identifier, e.g. `duplicate_tile_id`.
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class LevelValidationReport {
  LevelValidationReport(this.levelId, this.errors, this.solve);

  final String levelId;
  final List<ValidationIssue> errors;

  /// Present when solvability was checked.
  final SolveResult? solve;

  bool get isValid => errors.isEmpty;

  bool hasError(String code) => errors.any((e) => e.code == code);
}

/// Semantic validation of a parsed level against a symbol registry.
///
/// The client runs it with `checkSolvable: false` on every level it loads;
/// the content tool and tests run it with the solver before publishing.
///
/// Play and solvability checks use the pair model (two free tiles with the
/// same match key leave together). The game itself plays through a tray
/// (see `GameEngine`), which accepts every pair-removal order as taps
/// `a1, b1, a2, b2, ...` with at most one tile ever waiting in the tray. So
/// a level that passes here is playable and solvable in the game; the tray
/// can also rescue some lines the pair model calls dead, which only makes
/// these checks conservative.
class LevelValidator {
  const LevelValidator({
    required this.registry,
    this.maxTiles = 400,
    this.maxLayer = 20,
    this.coordinateLimit = 1000,
  });

  final SymbolRegistry registry;
  final int maxTiles;
  final int maxLayer;
  final double coordinateLimit;

  LevelValidationReport validate(
    LevelDefinition level, {
    String? expectedLevelId,
    bool checkSolvable = false,
    int solverNodeBudget = 500000,
  }) {
    final errors = <ValidationIssue>[];
    void error(String code, String message) => errors.add(ValidationIssue(code, message));

    if (!kSupportedLevelSchemas.contains(level.schemaVersion)) {
      error('unsupported_schema', 'level schema ${level.schemaVersion} is not supported');
    }
    if (!_levelIdPattern.hasMatch(level.levelId)) {
      error('invalid_level_id', 'levelId "${level.levelId}" must be lowercase letters, digits and dashes');
    }
    if (expectedLevelId != null && expectedLevelId != level.levelId) {
      error('level_id_mismatch', 'manifest expects "$expectedLevelId" but file declares "${level.levelId}"');
    }

    final board = level.board;
    if (board.tileWidth <= 0 || board.tileWidth > 100 || board.tileHeight <= 0 || board.tileHeight > 100) {
      error('invalid_board', 'tileWidth and tileHeight must be in (0, 100]');
    }
    if (board.layerOffsetX.abs() > 0.5 || board.layerOffsetY.abs() > 0.5) {
      error('invalid_board', 'layer offsets must be within [-0.5, 0.5]');
    }

    final backdrop = level.backdrop;
    if (backdrop != null && (backdrop.colors.length < 2 || backdrop.colors.length > 4 || !backdrop.colors.every(_colorPattern.hasMatch))) {
      error('invalid_backdrop', 'backdrop needs 2-4 colours in #RRGGBB form');
    }

    final tiles = level.tiles;
    if (tiles.isEmpty) error('no_tiles', 'level has no tiles');
    if (tiles.length > maxTiles) error('too_many_tiles', '${tiles.length} tiles exceeds the limit of $maxTiles');
    if (tiles.length.isOdd) error('odd_tile_count', '${tiles.length} tiles cannot all be paired');

    final seenIds = <String>{};
    for (final tile in tiles) {
      if (!_tileIdPattern.hasMatch(tile.tileId)) {
        error('invalid_tile_id', 'tileId "${tile.tileId}" has unsupported characters');
      }
      if (!seenIds.add(tile.tileId)) error('duplicate_tile_id', 'tileId "${tile.tileId}" is used more than once');
      if (tile.x.abs() > coordinateLimit || tile.y.abs() > coordinateLimit) {
        error('coordinate_out_of_range', '${tile.tileId} is outside ±$coordinateLimit');
      }
      if (tile.layer < 0 || tile.layer > maxLayer) {
        error('invalid_layer', '${tile.tileId} layer ${tile.layer} is outside 0..$maxLayer');
      }
      if (!registry.contains(tile.symbolCode)) {
        final why = registry.rejected[tile.symbolCode];
        error('unknown_symbol', '${tile.tileId} uses ${why == null ? 'unknown' : 'rejected ($why)'} symbol ${tile.symbolCode}');
      }
    }

    if (!kAllowedTrayCapacities.contains(level.rules.trayCapacity)) {
      error(
        'invalid_tray_capacity',
        'rules.trayCapacity ${level.rules.trayCapacity} must be one of ${kAllowedTrayCapacities.join(', ')}',
      );
    }

    final grouped = <String>{};
    for (final entry in level.rules.matchGroups.entries) {
      if (!_groupNamePattern.hasMatch(entry.key)) error('invalid_match_group', 'group name "${entry.key}" is invalid');
      if (entry.value.length < 2) error('invalid_match_group', 'group ${entry.key} needs at least two symbols');
      for (final code in entry.value) {
        if (!registry.contains(code)) error('invalid_match_group', 'group ${entry.key} references unknown symbol $code');
        if (!grouped.add(code)) error('invalid_match_group', 'symbol $code appears in more than one group');
      }
    }

    // Structural errors make geometry and play checks meaningless.
    if (errors.isNotEmpty) return LevelValidationReport(level.levelId, errors, null);

    final geometry = BoardGeometry.build(level);
    for (final (a, b) in geometry.sameLayerOverlaps) {
      error('same_layer_overlap', '${tiles[a].tileId} and ${tiles[b].tileId} overlap on layer ${tiles[a].layer}');
    }
    for (final index in geometry.unsupportedTiles) {
      error('floating_tile', '${tiles[index].tileId} on layer ${tiles[index].layer} rests on nothing');
    }

    final rules = MatchRules(level: level, registry: registry);
    rules.keyCounts().forEach((key, count) {
      if (count.isOdd) error('unpaired_symbol', '$key appears $count times; counts must be even');
    });
    if (errors.isNotEmpty) return LevelValidationReport(level.levelId, errors, null);

    if (!_hasFreePair(geometry, rules)) error('no_initial_moves', 'no legal pair is available at the start');

    SolveResult? solve;
    if (checkSolvable && level.rules.requireSolvable && errors.isEmpty) {
      solve = MahjongSolver(geometry: geometry, rules: rules, maxNodes: solverNodeBudget)
          .solve(TileMask.all(tiles.length));
      switch (solve.outcome) {
        case SolveOutcome.solvable:
          break;
        case SolveOutcome.unsolvable:
          error('unsolvable', 'no sequence of moves clears the board');
        case SolveOutcome.unknown:
          error('solvability_unproven', 'solver budget of $solverNodeBudget nodes ran out');
      }
    }
    return LevelValidationReport(level.levelId, errors, solve);
  }

  /// Whether two tiles that are free at the start share a match key.
  static bool _hasFreePair(BoardGeometry geometry, MatchRules rules) {
    final seen = <String>{};
    final start = TileMask.all(geometry.length);
    return TileAvailabilityCalculator(geometry).freeTiles(start).any((index) => !seen.add(rules.keyOf(index)));
  }
}

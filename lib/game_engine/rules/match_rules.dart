import '../models/level_definition.dart';
import '../models/level_rules.dart';
import '../models/symbol_registry.dart';

/// Resolves the identity two tiles must share to match.
///
/// Matching never looks at artwork: it uses symbol codes, registry match
/// groups (only in `match_group` levels) and the level's explicit special
/// groups (only when the level declares them).
class MatchRules {
  MatchRules({required LevelDefinition level, required SymbolRegistry registry})
    : _keys = _buildKeys(level, registry);

  /// [base]'s keys after a shuffle: tile `i` shows the symbol tile
  /// `source[i]` had in the level.
  MatchRules.permuted(MatchRules base, List<int> source)
    : assert(source.length == base._keys.length, 'one source per tile'),
      _keys = List.unmodifiable([for (final from in source) base._keys[from]]);

  final List<String> _keys;

  static List<String> _buildKeys(LevelDefinition level, SymbolRegistry registry) {
    final explicitGroup = <String, String>{
      for (final entry in level.rules.matchGroups.entries)
        for (final code in entry.value) code: 'group:${entry.key}',
    };
    return [
      for (final tile in level.tiles)
        explicitGroup[tile.symbolCode] ??
            (level.rules.matchingMode == MatchingMode.matchGroup
                ? 'match:${registry[tile.symbolCode]?.matchGroup ?? tile.symbolCode}'
                : 'symbol:${tile.symbolCode}'),
    ];
  }

  /// The match key of the tile at [index].
  String keyOf(int index) => _keys[index];

  bool matches(int a, int b) => a != b && _keys[a] == _keys[b];

  /// Tile count per match key; every count must be even for a valid level.
  Map<String, int> keyCounts() {
    final counts = <String, int>{};
    for (final key in _keys) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }
}

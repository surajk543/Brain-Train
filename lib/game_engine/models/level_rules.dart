import 'json_reader.dart';

/// How two symbols are compared when the player tries to match them.
enum MatchingMode {
  /// Tiles match when their `symbolCode`s are equal.
  sameSymbol('same_symbol'),

  /// Tiles match when their registry `matchGroup`s are equal.
  matchGroup('match_group');

  const MatchingMode(this.wire);

  final String wire;

  static MatchingMode? fromWire(String value) {
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return null;
  }
}

/// Tray slots a level may ask for (`rules.trayCapacity`). Absent means
/// [kDefaultTrayCapacity]. Builds that predate the field ignore it and play
/// with 4, which is safe: every published level is pair-solvable. Sizes 2
/// and 3 need content schema 3 (see `kClientContentSchema`).
const int kDefaultTrayCapacity = 4;
const Set<int> kAllowedTrayCapacities = {2, 3, 4, 5};

class LevelRules {
  const LevelRules({
    this.matchingMode = MatchingMode.sameSymbol,
    this.requireSolvable = true,
    this.matchGroups = const {},
    this.trayCapacity = kDefaultTrayCapacity,
  });

  factory LevelRules.fromJson(JsonReader json) {
    final modeWire = json.optString('matchingMode') ?? MatchingMode.sameSymbol.wire;
    final mode = MatchingMode.fromWire(modeWire);
    if (mode == null) {
      throw JsonFormatException(
        '${json.path}.matchingMode',
        'unsupported matching mode "$modeWire"',
      );
    }
    return LevelRules(
      matchingMode: mode,
      requireSolvable: json.boolOr('requireSolvable', true),
      matchGroups: json.has('matchGroups') ? json.stringListMap('matchGroups') : const {},
      trayCapacity: json.optInt('trayCapacity') ?? kDefaultTrayCapacity,
    );
  }

  final MatchingMode matchingMode;

  /// Publishing requires a solver-verified solution when true.
  final bool requireSolvable;

  /// Explicit special groups, e.g. `{"PEARS": ["PEAR_AURORA", "PEAR_BUTTERFLY"]}`.
  /// Every symbol listed in a group matches every other symbol in that group.
  /// Only levels that declare a group get group matching.
  final Map<String, List<String>> matchGroups;

  /// Tray slots for this level; `LevelValidator` accepts
  /// [kAllowedTrayCapacities]. Written only when it differs from the default.
  final int trayCapacity;

  Map<String, Object?> toJson() => {
    'matchingMode': matchingMode.wire,
    'requireSolvable': requireSolvable,
    if (matchGroups.isNotEmpty) 'matchGroups': matchGroups,
    if (trayCapacity != kDefaultTrayCapacity) 'trayCapacity': trayCapacity,
  };
}

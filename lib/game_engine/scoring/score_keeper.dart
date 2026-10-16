import 'dart:math' as math;

import 'scoring_rules.dart';

/// What one match earned, for the on-screen feedback.
class MatchScore {
  const MatchScore({required this.points, required this.multiplier, required this.combo, required this.speedBonus});

  final int points;
  final int multiplier;

  /// The streak length after this match (may exceed the multiplier cap).
  final int combo;
  final int speedBonus;
}

/// A game's score and combo. Times are the game clock (it stops while the
/// game is paused), passed in by the caller, so this is deterministic.
class ScoreKeeper {
  ScoreKeeper({this.rules = const ScoringRules()});

  /// Restores [toJson] output. Throws [FormatException] on bad data.
  factory ScoreKeeper.fromJson(Map<String, Object?> json, {ScoringRules rules = const ScoringRules()}) {
    int count(String key) {
      final value = json[key];
      if (value is! int || value < 0) throw FormatException('scoring.$key: $value');
      return value;
    }

    final lastMs = json['lastMatchAtMs'];
    if (lastMs != null && (lastMs is! int || lastMs < 0)) throw FormatException('scoring.lastMatchAtMs: $lastMs');
    return ScoreKeeper(rules: rules)
      .._score = count('score')
      .._combo = count('combo')
      .._bestCombo = count('bestCombo')
      .._pairs = count('pairs')
      .._lastMatchAt = lastMs == null ? null : Duration(milliseconds: lastMs as int);
  }

  final ScoringRules rules;

  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _pairs = 0;
  int _speedBonus = 0;
  Duration? _lastMatchAt;

  int get score => _score;

  /// The current streak (0 when none; it stays until the next match or
  /// [endCombo] even after the window passed — see [isComboActive]).
  int get currentCombo => _combo;
  int get bestCombo => _bestCombo;
  int get currentMultiplier => math.max(1, math.min(_combo, rules.maxMultiplier));
  int get totalPairsMatched => _pairs;

  /// Speed bonus of the last match.
  int get speedBonus => _speedBonus;
  Duration? get lastSuccessfulMatchTime => _lastMatchAt;
  Duration? get comboExpiresAt => _lastMatchAt == null ? null : _lastMatchAt! + rules.comboWindow;

  /// Whether a match at [t] would continue the streak.
  bool isComboActive(Duration t) => _combo > 0 && comboExpiresAt != null && t <= comboExpiresAt!;

  /// A confirmed match at game time [t].
  MatchScore onMatch(Duration t) {
    final last = _lastMatchAt;
    final gap = last == null ? null : t - last;
    final continues = gap != null && !gap.isNegative && gap <= rules.comboWindow && _combo > 0;
    _combo = continues ? _combo + 1 : 1;
    _speedBonus = continues ? rules.speedBonusFor(gap) : 0;
    final multiplier = currentMultiplier;
    final points = rules.basePoints * multiplier + _speedBonus;
    _score += points;
    _bestCombo = math.max(_bestCombo, _combo);
    _pairs++;
    _lastMatchAt = t;
    return MatchScore(points: points, multiplier: multiplier, combo: _combo, speedBonus: _speedBonus);
  }

  /// A blocked tile was tapped: the penalty (never below 0) and the combo
  /// ends. Returns the points actually taken.
  int onBlockedTap() {
    final taken = math.min(_score, rules.blockedTapPenalty);
    _score -= taken;
    endCombo();
    return taken;
  }

  /// The streak ends (Revive, a blocked tap); score and best stay.
  void endCombo() {
    _combo = 0;
    _speedBonus = 0;
    _lastMatchAt = null;
  }

  /// A new game (Restart).
  void reset() {
    _score = 0;
    _bestCombo = 0;
    _pairs = 0;
    endCombo();
  }

  /// A save from before scoring: base points per matched pair, no combo.
  void restoreLegacy(int matchedPairs) {
    reset();
    _pairs = matchedPairs;
    _score = matchedPairs * rules.basePoints;
    _bestCombo = matchedPairs > 0 ? 1 : 0;
  }

  Map<String, Object?> toJson() => {
    'score': _score,
    'combo': _combo,
    'bestCombo': _bestCombo,
    'pairs': _pairs,
    'lastMatchAtMs': _lastMatchAt?.inMilliseconds,
  };
}

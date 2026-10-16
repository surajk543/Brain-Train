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
    final blocked = json['blockedTaps'] ?? 0;
    if (blocked is! int || blocked < 0) throw FormatException('scoring.blockedTaps: $blocked');
    final undo = json['undo'] ?? const <Object?>[];
    if (undo is! List) throw FormatException('scoring.undo: $undo');
    return ScoreKeeper(rules: rules)
      .._score = count('score')
      .._combo = count('combo')
      .._bestCombo = count('bestCombo')
      .._pairs = count('pairs')
      .._lastMatchAt = lastMs == null ? null : Duration(milliseconds: lastMs as int)
      .._blockedTaps = blocked
      .._undo.addAll(undo.map(_Checkpoint.fromJson));
  }

  final ScoringRules rules;

  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _pairs = 0;
  int _speedBonus = 0;
  Duration? _lastMatchAt;

  /// Blocked-tile taps so far (each may have cost points).
  int _blockedTaps = 0;

  /// The state just before each match an undo can still take back, oldest
  /// first ([undoMatch]); cleared by [sealUndo] and [reset].
  final List<_Checkpoint> _undo = [];

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
    _undo.add(_checkpoint());
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
    _blockedTaps++;
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

  /// Matches [undoMatch] can take back (since the start or [sealUndo]).
  int get undoableMatches => _undo.length;

  /// Pairs matched before the match [undoMatch] would take back; null when
  /// there is none.
  int? get pairsBeforeUndo => _undo.isEmpty ? null : _undo.last.pairs;

  /// An undo took back the last match: score, combo, best combo, pairs and
  /// the combo clock are as they were just before it, and blocked-tap
  /// penalties taken since then are taken again (an undo only takes back
  /// moves). False when no match can be taken back.
  bool undoMatch() {
    if (_undo.isEmpty) return false;
    final before = _undo.removeLast();
    final since = _blockedTaps - before.blockedTaps;
    _score = before.score;
    _combo = before.combo;
    _bestCombo = before.bestCombo;
    _pairs = before.pairs;
    _speedBonus = before.speedBonus;
    _lastMatchAt = before.lastMatchAt;
    _blockedTaps = before.blockedTaps;
    for (var i = 0; i < since; i++) {
      onBlockedTap();
    }
    return true;
  }

  /// Undo can no longer reach the matches so far (a revive, a shuffle).
  void sealUndo() => _undo.clear();

  _Checkpoint _checkpoint() => _Checkpoint(
    score: _score,
    combo: _combo,
    bestCombo: _bestCombo,
    pairs: _pairs,
    speedBonus: _speedBonus,
    lastMatchAt: _lastMatchAt,
    blockedTaps: _blockedTaps,
  );

  /// A new game (Restart).
  void reset() {
    _score = 0;
    _bestCombo = 0;
    _pairs = 0;
    _blockedTaps = 0;
    _undo.clear();
    endCombo();
  }

  /// Takes over [other]'s state (resume).
  void restoreFrom(ScoreKeeper other) {
    _score = other._score;
    _combo = other._combo;
    _bestCombo = other._bestCombo;
    _pairs = other._pairs;
    _speedBonus = other._speedBonus;
    _lastMatchAt = other._lastMatchAt;
    _blockedTaps = other._blockedTaps;
    _undo
      ..clear()
      ..addAll(other._undo);
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
    if (_blockedTaps > 0) 'blockedTaps': _blockedTaps,
    if (_undo.isNotEmpty) 'undo': [for (final checkpoint in _undo) checkpoint.toJson()],
  };
}

/// The keeper's state just before a match, for [ScoreKeeper.undoMatch].
/// Saved compactly: `[score, combo, bestCombo, pairs, lastMatchAtMs or -1,
/// blockedTaps]`.
class _Checkpoint {
  const _Checkpoint({
    required this.score,
    required this.combo,
    required this.bestCombo,
    required this.pairs,
    required this.speedBonus,
    required this.lastMatchAt,
    required this.blockedTaps,
  });

  factory _Checkpoint.fromJson(Object? json) {
    if (json is! List || json.length != 6 || json.any((v) => v is! int)) throw FormatException('scoring.undo: $json');
    final [score, combo, bestCombo, pairs, lastMs, blocked] = json.cast<int>();
    if ([score, combo, bestCombo, pairs, blocked].any((v) => v < 0) || lastMs < -1) {
      throw FormatException('scoring.undo: $json');
    }
    return _Checkpoint(
      score: score,
      combo: combo,
      bestCombo: bestCombo,
      pairs: pairs,
      speedBonus: 0,
      lastMatchAt: lastMs < 0 ? null : Duration(milliseconds: lastMs),
      blockedTaps: blocked,
    );
  }

  final int score;
  final int combo;
  final int bestCombo;
  final int pairs;

  /// Not saved (display only).
  final int speedBonus;
  final Duration? lastMatchAt;
  final int blockedTaps;

  List<int> toJson() => [score, combo, bestCombo, pairs, lastMatchAt?.inMilliseconds ?? -1, blockedTaps];
}

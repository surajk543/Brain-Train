# Scoring and Combo System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every matched pair scores (100 × combo multiplier + speed bonus), blocked taps cost 1 point (never below 0), and score/combo show live in the HUD, on the win card and in Completed Levels, with per-level best score and best combo stored.

**Architecture:** A pure-Dart `ScoreKeeper` (`lib/game_engine/scoring/`) is fed by `GameController` with the game clock (`elapsed`) on each `TapOutcome.matched` / `TapOutcome.blocked`. The controller saves the keeper's state inside `SavedGame`, records bests through `ProgressRepository.recordWin`, and publishes `ScoreEvent`s for popups. The game screen shows SCORE in the HUD, a combo badge floating on the tray's bottom edge (no layout change), a popup overlay, and the extended win card.

**Tech Stack:** Flutter 3.44.7 / Dart 3.12.2, `flutter_test`, existing `SharedPreferences` storage.

**Spec:** `docs/superpowers/specs/2026-10-16-scoring-combo-design.md`

## Global Constraints

- Defaults: `basePoints` 100; `comboWindow` 3 s (a gap of exactly 3.000 s continues); `maxMultiplier` 5; speed bonus +50 (gap < 1 s), +25 (1 s ≤ gap < 2 s), +10 (2 s ≤ gap ≤ 3 s); first match of a streak: no bonus; `blockedTapPenalty` 1.
- Points per match: `basePoints × min(combo, maxMultiplier) + speedBonus`. The visible combo may exceed 5; the multiplier never does.
- Only `TapOutcome.matched` adds points; `TapOutcome.blocked` costs 1 (score never below 0) and ends the combo; `toTray`, `ignored`, `trayFull`, taps refused during the intro, and animation callbacks change nothing.
- Revive ends the combo, keeps score and best combo. Restart resets everything.
- Time source: `GameController.elapsed` only (stops in background, during the intro, while the Restart confirm card is open). No wall clock.
- Records: `bestScore`/`bestCombo` only ever go up; fastest-time logic unchanged. Storage keys unchanged (`progress.completed.v1`, `progress.current.v2`); old data stays readable.
- Texts verbatim: HUD stat label `Score`; badge `COMBO ×N` (from ×2), `Best ×N`; popup `+N` and `×M · +B fast` (the `· +B fast` part only when B > 0); penalty `−1`; win card `Score`, `New best!`, `Best combo ×N`, `Pairs n/n`, `Best: <score> · <time>`; Completed Levels row best score, `—` when none. Numbers use thousands separators: `12,450`.
- Undo/Hint/Shuffle do not exist — show nothing for them.
- Rendering (CLAUDE.md): no `BackdropFilter`, no `Opacity`/`ColorFilter` layers, no per-frame blurs/blend passes; nothing ticks when no combo, popup or effect runs; overlays are `IgnorePointer`.
- Board layout must not change (the 31-px tile-face guarantee assumes the current 360×640 board area): the combo badge floats over the tray's bottom edge.
- Reduce motion: no popups, no ring animation, no effects; numbers update in place.
- `flutter analyze` clean; `flutter test` adds no new failures (6 pre-existing failures: RenderFlex overflow at `lib/features/levels/level_select_screen.dart:232` — level_select_test ×2, level_loader_test ×1, lobby_capture_test ×2, gameplay_capture_test "tray-full overlay 360x640 at 1.3x text").
- Flutter binary: `~/flutter/bin/flutter`. All work on branch `feat/play-games`. Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Stage files by path (never `.claude/`).

## Review Focus

- Resuming a save made mid-combo (app killed 1 s after a match): the combo continues with exactly the remaining window, not a fresh 3 s. → Task 3 test `resume keeps an active combo's remaining window`.
- A blocked tap while the score is 0 at the very start: no `−1` popup, score stays 0, nothing saved as negative. → Task 1 test `blocked tap at 0 stays 0` + Task 3 test `blocked tap at score 0 emits no penalty event`.
- Restart while a match's strike animation is still pending: the late `pairImpact` must not emit a popup or change the new game's score. → Task 3 test `pairImpact after restart emits nothing`.
- App sent to background with a combo running, back after 10 s: combo still alive with the same time left (clock paused). → Task 3 test `pauseClock freezes the combo window`.
- A corrupt `scoring` object in a save (hand-edited prefs / older build): the game resumes with the legacy rebuild, never crashes. → Task 3 test `corrupt scoring falls back to the legacy rebuild`.

---

### Task 1: `ScoringRules` and `ScoreKeeper` (pure Dart)

**Files:**
- Create: `lib/game_engine/scoring/scoring_rules.dart`
- Create: `lib/game_engine/scoring/score_keeper.dart`
- Test: `test/game_engine/score_keeper_test.dart`

**Interfaces:**
- Produces:
  - `class ScoringRules` (const) — `basePoints`, `comboWindow`, `maxMultiplier`, `speedTiers` (`List<({Duration under, int bonus})>`), `windowBonus`, `blockedTapPenalty`; `int speedBonusFor(Duration gap)`.
  - `class MatchScore` — `points`, `multiplier`, `combo`, `speedBonus` (ints).
  - `class ScoreKeeper` — `ScoreKeeper({ScoringRules rules = const ScoringRules()})`; `factory ScoreKeeper.fromJson(Map<String, Object?> json, {ScoringRules rules})` (throws `FormatException` on bad data); getters `score`, `currentCombo`, `bestCombo`, `currentMultiplier`, `totalPairsMatched`, `speedBonus`, `lastSuccessfulMatchTime` (`Duration?`), `comboExpiresAt` (`Duration?`); `bool isComboActive(Duration t)`; `MatchScore onMatch(Duration t)`; `int onBlockedTap()`; `void endCombo()`; `void reset()`; `void restoreLegacy(int matchedPairs)`; `Map<String, Object?> toJson()`.

- [ ] **Step 1: Write the failing tests**

Create `test/game_engine/score_keeper_test.dart`:

```dart
import 'package:brain_train/game_engine/scoring/score_keeper.dart';
import 'package:brain_train/game_engine/scoring/scoring_rules.dart';
import 'package:test/test.dart';

Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

void main() {
  late ScoreKeeper keeper;
  setUp(() => keeper = ScoreKeeper());

  test('starts empty', () {
    expect(keeper.score, 0);
    expect(keeper.currentCombo, 0);
    expect(keeper.bestCombo, 0);
    expect(keeper.totalPairsMatched, 0);
    expect(keeper.lastSuccessfulMatchTime, isNull);
    expect(keeper.comboExpiresAt, isNull);
    expect(keeper.isComboActive(Duration.zero), isFalse);
  });

  test('first match: +100, ×1, no speed bonus', () {
    final m = keeper.onMatch(s(5));
    expect((m.points, m.multiplier, m.combo, m.speedBonus), (100, 1, 1, 0));
    expect(keeper.score, 100);
    expect(keeper.comboExpiresAt, s(8));
    expect(keeper.isComboActive(s(8)), isTrue);
    expect(keeper.isComboActive(s(8.001)), isFalse);
  });

  test('consecutive matches inside the window build the combo with speed bonuses', () {
    keeper.onMatch(s(0));
    final second = keeper.onMatch(s(0.8));
    expect((second.points, second.multiplier, second.speedBonus), (250, 2, 50));
    final third = keeper.onMatch(s(2.3));
    expect((third.points, third.multiplier, third.speedBonus), (325, 3, 25));
    expect(keeper.score, 100 + 250 + 325);
    expect(keeper.bestCombo, 3);
  });

  test('exact boundaries', () {
    final rules = const ScoringRules();
    expect(rules.speedBonusFor(s(0.999)), 50);
    expect(rules.speedBonusFor(s(1)), 25);
    expect(rules.speedBonusFor(s(1.999)), 25);
    expect(rules.speedBonusFor(s(2)), 10);
    expect(rules.speedBonusFor(s(3)), 10);
    expect(rules.speedBonusFor(s(3.001)), 0);
    keeper.onMatch(s(0));
    final atWindow = keeper.onMatch(s(3));
    expect((atWindow.combo, atWindow.speedBonus, atWindow.points), (2, 10, 210));
    final past = keeper.onMatch(s(6.001));
    expect((past.combo, past.speedBonus, past.points), (1, 0, 100));
  });

  test('expiry: the next match starts over at ×1; score and best kept', () {
    keeper.onMatch(s(0));
    keeper.onMatch(s(1));
    final after = keeper.onMatch(s(10));
    expect((after.combo, after.multiplier, after.points), (1, 1, 100));
    expect(keeper.bestCombo, 2);
    expect(keeper.score, 100 + 225 + 100);
  });

  test('the multiplier caps at ×5 while the streak keeps counting', () {
    for (var i = 0; i < 7; i++) {
      keeper.onMatch(s(i * 0.5));
    }
    expect(keeper.currentCombo, 7);
    expect(keeper.currentMultiplier, 5);
    expect(keeper.bestCombo, 7);
    // Matches 6 and 7: ×5 + 50 each.
    expect(keeper.score, 100 + 250 + 350 + 450 + 550 + 550 + 550);
  });

  test('best combo across streaks', () {
    keeper.onMatch(s(0));
    keeper.onMatch(s(1));
    keeper.onMatch(s(2)); // ×3
    keeper.onMatch(s(9)); // new streak
    keeper.onMatch(s(10)); // ×2
    expect(keeper.bestCombo, 3);
    expect(keeper.currentCombo, 2);
  });

  test('endCombo (revive): combo over, score and best kept', () {
    keeper.onMatch(s(0));
    keeper.onMatch(s(1));
    keeper.endCombo();
    expect(keeper.currentCombo, 0);
    expect(keeper.isComboActive(s(1.5)), isFalse);
    expect(keeper.score, 325);
    expect(keeper.bestCombo, 2);
    final next = keeper.onMatch(s(1.5));
    expect((next.combo, next.speedBonus), (1, 0));
  });

  test('blocked tap: −1 and the combo ends; best combo kept', () {
    keeper.onMatch(s(0));
    keeper.onMatch(s(1));
    expect(keeper.onBlockedTap(), 1);
    expect(keeper.score, 324);
    expect(keeper.currentCombo, 0);
    expect(keeper.bestCombo, 2);
    expect(keeper.totalPairsMatched, 2);
  });

  test('blocked tap at 0 stays 0, and at 1 goes to 0, never negative', () {
    expect(keeper.onBlockedTap(), 0);
    expect(keeper.score, 0);
    final one = ScoreKeeper(rules: const ScoringRules(basePoints: 1));
    one.onMatch(s(0));
    expect(one.onBlockedTap(), 1);
    expect(one.onBlockedTap(), 0);
    expect(one.score, 0);
  });

  test('repeated blocked taps each cost 1', () {
    keeper.onMatch(s(0));
    keeper.onBlockedTap();
    keeper.onBlockedTap();
    expect(keeper.score, 98);
  });

  test('reset (restart): everything back to zero', () {
    keeper.onMatch(s(0));
    keeper.onMatch(s(1));
    keeper.reset();
    expect((keeper.score, keeper.currentCombo, keeper.bestCombo, keeper.totalPairsMatched), (0, 0, 0, 0));
    expect(keeper.lastSuccessfulMatchTime, isNull);
  });

  test('restoreLegacy: base points per pair, no combo, best 1', () {
    keeper.restoreLegacy(4);
    expect((keeper.score, keeper.totalPairsMatched, keeper.bestCombo, keeper.currentCombo), (400, 4, 1, 0));
    keeper.restoreLegacy(0);
    expect((keeper.score, keeper.bestCombo), (0, 0));
  });

  test('JSON round trip keeps an active combo', () {
    keeper.onMatch(s(10));
    keeper.onMatch(s(11));
    final copy = ScoreKeeper.fromJson(keeper.toJson());
    expect((copy.score, copy.currentCombo, copy.bestCombo, copy.totalPairsMatched), (325, 2, 2, 2));
    expect(copy.lastSuccessfulMatchTime, s(11));
    expect(copy.isComboActive(s(13.5)), isTrue);
    final next = copy.onMatch(s(12));
    expect((next.combo, next.speedBonus), (3, 50));
  });

  test('fromJson rejects bad data', () {
    expect(() => ScoreKeeper.fromJson({'score': 'x'}), throwsFormatException);
    expect(() => ScoreKeeper.fromJson({'score': -5, 'combo': 0, 'bestCombo': 0, 'pairs': 0}), throwsFormatException);
  });

  test('custom rules are honoured', () {
    final custom = ScoreKeeper(
      rules: const ScoringRules(basePoints: 10, comboWindow: Duration(seconds: 1), maxMultiplier: 2, windowBonus: 1),
    );
    custom.onMatch(s(0));
    final m = custom.onMatch(s(0.5)); // < 1 s tier → +50
    expect((m.multiplier, m.points), (2, 70));
    expect(custom.onMatch(s(2)).combo, 1); // gap 1.5 s > 1 s window
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `~/flutter/bin/flutter test test/game_engine/score_keeper_test.dart`
Expected: FAIL — `scoring/score_keeper.dart` not found.

- [ ] **Step 3: Implement `ScoringRules`**

Create `lib/game_engine/scoring/scoring_rules.dart`:

```dart
/// How pairs score: base points, the combo window, the multiplier cap, the
/// speed tiers and the blocked-tap penalty. Pure Dart (tools may import it).
class ScoringRules {
  const ScoringRules({
    this.basePoints = 100,
    this.comboWindow = const Duration(seconds: 3),
    this.maxMultiplier = 5,
    this.speedTiers = const [
      (under: Duration(seconds: 1), bonus: 50),
      (under: Duration(seconds: 2), bonus: 25),
    ],
    this.windowBonus = 10,
    this.blockedTapPenalty = 1,
  });

  final int basePoints;

  /// A match at most this long after the previous one continues the combo
  /// (the boundary itself included).
  final Duration comboWindow;

  final int maxMultiplier;

  /// Bonus for a gap shorter than `under`, checked in order.
  final List<({Duration under, int bonus})> speedTiers;

  /// Bonus for a gap past every tier but still inside [comboWindow].
  final int windowBonus;

  /// Points a blocked-tile tap costs (the score never goes below 0).
  final int blockedTapPenalty;

  /// Speed bonus for a match [gap] after the previous one (0 past the window).
  int speedBonusFor(Duration gap) {
    if (gap.isNegative || gap > comboWindow) return 0;
    for (final tier in speedTiers) {
      if (gap < tier.under) return tier.bonus;
    }
    return windowBonus;
  }
}
```

- [ ] **Step 4: Implement `ScoreKeeper`**

Create `lib/game_engine/scoring/score_keeper.dart`:

```dart
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
```

Note: `fromJson` restores `_combo` with `_lastMatchAt`; an `onMatch` right after a restore continues the streak (test "JSON round trip").

- [ ] **Step 5: Run the tests**

Run: `~/flutter/bin/flutter test test/game_engine/score_keeper_test.dart`
Expected: all PASS. If `package:test` is not a dev dependency, use `package:flutter_test/flutter_test.dart` (as `test/game_engine/rules_test.dart` does) — check that file's import first and match it.

- [ ] **Step 6: Analyze, commit**

Run: `~/flutter/bin/flutter analyze` → `No issues found!`

```bash
git add lib/game_engine/scoring/ test/game_engine/score_keeper_test.dart
git commit -m "$(printf 'Scoring: ScoreKeeper and ScoringRules (pure Dart)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 2: Records and saves carry scoring

**Files:**
- Modify: `lib/data/progress_repository.dart` (`LevelRecord`, `SavedGame`, `recordWin`)
- Test: `test/data/progress_repository_test.dart`

**Interfaces:**
- Produces: `LevelRecord.bestScore` (`int?`), `LevelRecord.bestCombo` (`int?`); `recordWin(levelId, {required int moves, required int timeMs, int? score, int? bestCombo})`; `SavedGame.scoring` (`Map<String, Object?>?`, constructor named parameter `scoring`).

Independent of Task 1 (stores the keeper's JSON as an opaque map).

- [ ] **Step 1: Write the failing tests** — add to `test/data/progress_repository_test.dart` (inside its `main`, reusing its `setUp`/helpers; read the file first):

```dart
  test('recordWin keeps the best score and best combo separately; old records have none', () async {
    final progress = await ProgressRepository.open();
    var record = await progress.recordWin('l1', moves: 20, timeMs: 60000);
    expect(record.bestScore, isNull);
    expect(record.bestCombo, isNull);
    record = await progress.recordWin('l1', moves: 22, timeMs: 70000, score: 1200, bestCombo: 3);
    expect((record.bestScore, record.bestCombo), (1200, 3));
    record = await progress.recordWin('l1', moves: 25, timeMs: 90000, score: 900, bestCombo: 5);
    expect((record.bestScore, record.bestCombo), (1200, 5), reason: 'a worse score never replaces a better one');
    expect(record.bestTimeMs, 60000);
    final reopened = (await ProgressRepository.open()).completed()['l1']!;
    expect((reopened.bestScore, reopened.bestCombo), (1200, 5));
  });

  test('old JSON without score fields still reads', () async {
    SharedPreferences.setMockInitialValues({
      'progress.completed.v1': jsonEncode({
        'l1': {'bestMoves': 10, 'bestTimeMs': 5000, 'completedAt': '2026-10-01T10:00:00.000'},
      }),
    });
    final record = (await ProgressRepository.open()).completed()['l1']!;
    expect(record.bestScore, isNull);
    expect(record.bestMoves, 10);
  });

  test('SavedGame keeps its scoring map; old saves have none', () async {
    final progress = await ProgressRepository.open();
    await progress.saveGame(
      SavedGame(levelId: 'l9', levelUrl: 'u', history: const ['a'], elapsedMs: 1000, scoring: const {'score': 100}),
    );
    expect((await ProgressRepository.open()).savedGame()!.scoring, {'score': 100});
    final old = SavedGame.fromJson({'levelId': 'l9', 'levelUrl': 'u', 'history': ['a'], 'moveCount': 1, 'elapsedMs': 1});
    expect(old.scoring, isNull);
    expect(old.toJson().containsKey('scoring'), isFalse);
  });
```

(Add `import 'dart:convert';` and `import 'package:shared_preferences/shared_preferences.dart';` if the file lacks them.)

- [ ] **Step 2: Run to see them fail**

Run: `~/flutter/bin/flutter test test/data/progress_repository_test.dart`
Expected: FAIL — no `bestScore` / `scoring` members.

- [ ] **Step 3: Implement** — in `lib/data/progress_repository.dart`:

`LevelRecord` becomes:

```dart
class LevelRecord {
  const LevelRecord({
    required this.bestMoves,
    required this.bestTimeMs,
    required this.completedAt,
    this.bestScore,
    this.bestCombo,
  });

  factory LevelRecord.fromJson(Map<String, Object?> json) => LevelRecord(
    bestMoves: json['bestMoves']! as int,
    bestTimeMs: json['bestTimeMs']! as int,
    completedAt: DateTime.parse(json['completedAt']! as String),
    bestScore: json['bestScore'] as int?,
    bestCombo: json['bestCombo'] as int?,
  );

  final int bestMoves;
  /// Fastest win, in milliseconds of play.
  final int bestTimeMs;

  /// When the fastest win ([bestTimeMs]) happened.
  final DateTime completedAt;

  /// Highest score and longest combo over all wins; null for wins from
  /// before scoring.
  final int? bestScore;
  final int? bestCombo;

  Map<String, Object?> toJson() => {
    'bestMoves': bestMoves,
    'bestTimeMs': bestTimeMs,
    'completedAt': completedAt.toIso8601String(),
    if (bestScore != null) 'bestScore': bestScore,
    if (bestCombo != null) 'bestCombo': bestCombo,
  };
}
```

`SavedGame`: add `this.scoring` to the constructor (named, optional), the field

```dart
  /// The game's [ScoreKeeper] state (`ScoreKeeper.toJson`); null for saves
  /// from before scoring.
  final Map<String, Object?>? scoring;
```

`fromJson`: `scoring: json['scoring'] as Map<String, Object?>?,`; `toJson`: `if (scoring != null) 'scoring': scoring,`.

`recordWin` becomes:

```dart
  /// Records a won game. A level played again keeps its fastest time
  /// (owner), and [LevelRecord.completedAt] is when that fastest win
  /// happened, so the time and the date shown always belong together. Best
  /// moves, best score and best combo are each kept on their own.
  Future<LevelRecord> recordWin(String levelId, {required int moves, required int timeMs, int? score, int? bestCombo}) async {
    final all = completed();
    final previous = all[levelId];
    final faster = previous == null || timeMs < previous.bestTimeMs;
    int? higher(int? a, int? b) => a == null ? b : (b == null ? a : (a > b ? a : b));
    final record = LevelRecord(
      bestMoves: previous == null || moves < previous.bestMoves ? moves : previous.bestMoves,
      bestTimeMs: faster ? timeMs : previous.bestTimeMs,
      completedAt: faster ? DateTime.now() : previous.completedAt,
      bestScore: higher(previous?.bestScore, score),
      bestCombo: higher(previous?.bestCombo, bestCombo),
    );
    all[levelId] = record;
    await _prefs.setString(_completedKey, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
    notifyListeners();
    return record;
  }
```

(Remove the duplicated first doc line "Records a win, keeping the best moves and best time separately." while you are there.)

- [ ] **Step 4: Run the tests** — `~/flutter/bin/flutter test test/data/progress_repository_test.dart` → PASS.

- [ ] **Step 5: Analyze, full suite, commit**

Run `~/flutter/bin/flutter analyze` (clean) and `~/flutter/bin/flutter test` (only the 6 known failures).

```bash
git add lib/data/progress_repository.dart test/data/progress_repository_test.dart
git commit -m "$(printf 'Progress: best score and best combo per level; saves carry scoring\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 3: `GameController` scores the game

**Files:**
- Modify: `lib/features/gameplay/game_controller.dart`
- Create: `test/helpers/fake_stopwatch.dart`
- Test: `test/features/game_controller_scoring_test.dart`

**Interfaces:**
- Consumes: Task 1 `ScoreKeeper`, `ScoringRules`, `MatchScore`; Task 2 `SavedGame.scoring`, `recordWin(..., score:, bestCombo:)`, `LevelRecord.bestScore`.
- Produces (on `GameController`):
  - constructor params `Stopwatch? stopwatch` (game clock; default `Stopwatch()`), `ScoringRules scoringRules = const ScoringRules()`.
  - `final ScoreKeeper scoring;` `int get score;` `int get activeCombo` (combo if active at `elapsed`, else 0); `Duration? get comboTimeLeft` (null when no active combo); `bool get clockRunning`.
  - `bool newBestScore` (set when a win beats an existing `bestScore`).
  - `Stream<ScoreEvent> get scoreEvents` with `sealed class ScoreEvent`; `ScoreAwarded(MatchScore score, int traySlot)`; `ScorePenalty(String tileId, int points)`.
  - Behaviour: `matched` → `scoring.onMatch(elapsed)`; `ScoreAwarded` is emitted at `pairImpact()` (FIFO) when `matchFeedbackOnImpact`, else at once; `blocked` → `onBlockedTap()`, `ScorePenalty` only if points > 0, save while playing, notify; `revive` → `endCombo()` + queued awards cleared; `restart` → `reset()`, queue cleared, serial bumped; combo-expiry timer (one, cancelled on pause, re-scheduled on resume); `_save` includes `scoring.toJson()`; resume restores `ScoreKeeper.fromJson` or `restoreLegacy(state.matchedPairs)` on missing/corrupt data; `_recordWin` passes `score`/`bestCombo` and sets `newBestScore`.

- [ ] **Step 1: Fake stopwatch**

Create `test/helpers/fake_stopwatch.dart`:

```dart
/// A [Stopwatch] whose time only moves when [advance] is called (and only
/// while it runs), for deterministic game-clock tests.
class FakeStopwatch implements Stopwatch {
  Duration _elapsed = Duration.zero;
  bool _running = false;

  void advance(Duration by) {
    if (_running) _elapsed += by;
  }

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  void reset() => _elapsed = Duration.zero;

  @override
  bool get isRunning => _running;

  @override
  Duration get elapsed => _elapsed;

  @override
  int get elapsedMilliseconds => _elapsed.inMilliseconds;

  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;

  @override
  int get elapsedTicks => _elapsed.inMicroseconds;

  @override
  int get frequency => 1000000;
}
```

- [ ] **Step 2: Write the failing tests**

Create `test/features/game_controller_scoring_test.dart` — it mirrors the setup of `test/features/game_controller_test.dart` (same `board`, `reg`, `entry`, `level(...)`/`registry(...)` helpers from `test/helpers.dart`):

```dart
import 'dart:async';

import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../helpers/fake_stopwatch.dart';

Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A B C D A B C D, all free; plus x1 under y1 (x1 starts blocked).
  final board = level([
    for (final (i, code) in ['A', 'B', 'C', 'D', 'A', 'B', 'C', 'D'].indexed)
      ('${code.toLowerCase()}${i < 4 ? 1 : 2}', code, i * 4.0, 0.0, 0),
    ('x1', 'X', 40, 0, 0),
    ('y1', 'X', 40, 0, 1),
  ]);
  final reg = registry(['A', 'B', 'C', 'D', 'X']);
  const entry = LevelManifestEntry(
    levelId: 'test-level',
    order: 1,
    title: 'Test',
    ref: ContentRef(url: 'levels/test-level-v1.json'),
  );

  late ProgressRepository progress;
  late SettingsRepository settings;
  late FakeStopwatch clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    progress = await ProgressRepository.open();
    settings = await SettingsRepository.open();
    clock = FakeStopwatch();
  });

  GameController controllerFor({SavedGame? resume, bool onImpact = false, LevelDefinition? on}) => GameController(
    entry: entry,
    level: on ?? board,
    registry: reg,
    progress: progress,
    settings: settings,
    resume: resume,
    stopwatch: clock,
    matchFeedbackOnImpact: onImpact,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('only a confirmed match adds points; toTray adds nothing', () async {
    final c = controllerFor();
    c.tapTile('a1');
    expect(c.score, 0);
    clock.advance(s(0.5));
    c.tapTile('a2');
    expect(c.score, 100);
    expect(c.activeCombo, 1);
    c.dispose();
  });

  test('a fast second match: ×2 with the speed bonus', () async {
    final c = controllerFor();
    c.tapTile('a1');
    c.tapTile('a2'); // t=0
    clock.advance(s(0.8));
    c.tapTile('b1');
    c.tapTile('b2'); // t=0.8
    expect(c.score, 100 + 250);
    expect(c.activeCombo, 2);
    expect(c.scoring.bestCombo, 2);
    c.dispose();
  });

  test('blocked tap costs 1, ends the combo, is saved; at score 0 emits no penalty event', () async {
    final c = controllerFor();
    final events = <ScoreEvent>[];
    final sub = c.scoreEvents.listen(events.add);
    c.tapTile('x1');
    await settle();
    expect(c.score, 0);
    expect(events, isEmpty);
    c.tapTile('a1');
    c.tapTile('a2');
    c.tapTile('x1');
    await settle();
    expect(c.score, 99);
    expect(c.activeCombo, 0);
    expect(events.whereType<ScorePenalty>().single.points, 1);
    expect(progress.savedGame()!.scoring!['score'], 99);
    await sub.cancel();
    c.dispose();
  });

  test('ScoreAwarded waits for the strike when matchFeedbackOnImpact; pairImpact after restart emits nothing', () async {
    final c = controllerFor(onImpact: true);
    final events = <ScoreEvent>[];
    final sub = c.scoreEvents.listen(events.add);
    c.tapTile('a1');
    c.tapTile('a2');
    await settle();
    expect(c.score, 100, reason: 'the score counts at the match');
    expect(events, isEmpty, reason: 'the popup waits for the strike');
    c.pairImpact();
    await settle();
    expect(events.single, isA<ScoreAwarded>().having((e) => e.score.points, 'points', 100).having((e) => e.traySlot, 'slot', 0));
    c.tapTile('b1');
    c.tapTile('b2');
    c.restart();
    c.pairImpact();
    await settle();
    expect(events, hasLength(1));
    expect(c.score, 0);
    await sub.cancel();
    c.dispose();
  });

  test('pauseClock freezes the combo window', () async {
    final c = controllerFor();
    c.tapTile('a1');
    c.tapTile('a2'); // t=0
    clock.advance(s(1));
    c.pauseClock();
    clock.advance(s(10)); // paused: no time passes
    c.resumeClock();
    expect(c.comboTimeLeft, s(2));
    clock.advance(s(1.5));
    c.tapTile('b1');
    c.tapTile('b2'); // t=2.5 → continues
    expect(c.activeCombo, 2);
    c.dispose();
  });

  test('revive ends the combo, keeps the score', () async {
    final c = controllerFor();
    c.tapTile('a1');
    c.tapTile('a2');
    for (final id in ['b1', 'c1', 'd1', 'y1']) {
      c.tapTile(id);
    }
    expect(c.state.status, GameStatus.trayFull);
    expect(c.revive(), isTrue);
    expect(c.activeCombo, 0);
    expect(c.score, 100);
    c.dispose();
  });

  test('restart resets the score', () async {
    final c = controllerFor();
    c.tapTile('a1');
    c.tapTile('a2');
    c.restart();
    expect((c.score, c.activeCombo, c.scoring.bestCombo), (0, 0, 0));
    c.dispose();
  });

  test('resume keeps an active combo\'s remaining window', () async {
    final first = controllerFor();
    first.tapTile('a1');
    clock.advance(s(2));
    first.tapTile('a2'); // match at t=2
    clock.advance(s(1));
    first.tapTile('b1'); // saved at t=3 with the combo active
    await settle();
    final saved = progress.savedGame()!;
    first.dispose();
    clock = FakeStopwatch();
    final resumed = controllerFor(resume: saved);
    expect(resumed.score, 100);
    expect(resumed.comboTimeLeft, s(2));
    clock.advance(s(1));
    resumed.tapTile('b2'); // t=4: gap 2 s → ×2 +10
    expect(resumed.score, 100 + 210);
    resumed.dispose();
  });

  test('a legacy save rebuilds at base points; corrupt scoring falls back to the legacy rebuild', () async {
    final legacy = SavedGame(levelId: 'test-level', levelUrl: entry.ref.url, history: const ['a1', 'a2', 'b1'], elapsedMs: 4000);
    final c1 = controllerFor(resume: legacy);
    expect((c1.score, c1.scoring.bestCombo, c1.activeCombo), (100, 1, 0));
    c1.dispose();
    final corrupt = SavedGame(
      levelId: 'test-level',
      levelUrl: entry.ref.url,
      history: const ['a1', 'a2', 'b1'],
      elapsedMs: 4000,
      scoring: const {'score': 'oops'},
    );
    final c2 = controllerFor(resume: corrupt);
    expect(c2.score, 100);
    c2.dispose();
  });

  test('a win records best score and combo; a worse replay never lowers them; a better one says new best', () async {
    Future<GameController> win({required Duration gap}) async {
      final c = controllerFor();
      for (final pair in [('a1', 'a2'), ('b1', 'b2'), ('c1', 'c2'), ('d1', 'd2'), ('y1', 'x1')]) {
        c.tapTile(pair.$1);
        c.tapTile(pair.$2);
        clock.advance(gap);
      }
      expect(c.state.status, GameStatus.won);
      await settle();
      await settle();
      return c;
    }

    final slow = await win(gap: s(5));
    expect(progress.completed()['test-level']!.bestScore, 500);
    expect(slow.newBestScore, isFalse, reason: 'first scored win: nothing to beat');
    slow.dispose();
    clock = FakeStopwatch();
    final fast = await win(gap: s(0.5));
    final record = progress.completed()['test-level']!;
    expect(record.bestScore, greaterThan(500));
    expect(record.bestCombo, 5);
    expect(fast.newBestScore, isTrue);
    fast.dispose();
    clock = FakeStopwatch();
    final worse = await win(gap: s(5));
    expect(progress.completed()['test-level']!.bestScore, record.bestScore);
    expect(worse.newBestScore, isFalse);
    worse.dispose();
  });
}
```

Check the board: `y1` sits on `x1` (layer 1 over layer 0), both symbol `X`; tapping `y1` then `x1` matches. If the tray-full sequence in the revive test does not fill the tray with this fixture (capacity 4 by default: after a match the tray holds nothing; `b1, c1, d1, y1` are four different symbols except y1 = X), adjust only the tile order so four unmatched tiles fill the tray, keeping the assertions.

- [ ] **Step 3: Run to see them fail**

Run: `~/flutter/bin/flutter test test/features/game_controller_scoring_test.dart`
Expected: FAIL — `stopwatch:` / `score` / `ScoreEvent` undefined.

- [ ] **Step 4: Implement in `game_controller.dart`**

Imports: add `import '../../game_engine/scoring/score_keeper.dart';` and `import '../../game_engine/scoring/scoring_rules.dart';`.

Score events (after `BoardReset`):

```dart
/// Score feedback for the screen (popups). The score itself is already
/// updated when these arrive.
sealed class ScoreEvent {
  const ScoreEvent();
}

/// A matched pair scored [score]; it struck in tray slot [traySlot].
class ScoreAwarded extends ScoreEvent {
  const ScoreAwarded(this.score, this.traySlot);

  final MatchScore score;
  final int traySlot;
}

/// A blocked-tile tap on [tileId] cost [points] (never 0).
class ScorePenalty extends ScoreEvent {
  const ScorePenalty(this.tileId, this.points);

  final String tileId;
  final int points;
}
```

Constructor: add parameters `Stopwatch? stopwatch, ScoringRules scoringRules = const ScoringRules(),` and initializers

```dart
  }) : trayCapacity = trayCapacity ?? level.rules.trayCapacity,
       _stopwatch = stopwatch ?? Stopwatch(),
       scoring = ScoreKeeper(rules: scoringRules) {
```

(the field `final Stopwatch _stopwatch = Stopwatch();` becomes `final Stopwatch _stopwatch;`). Inside the resume branch, after a successful `engine.replay(...)` and `_baseElapsed = ...`, add:

```dart
        _restoreScoring(resume.scoring);
```

and add the method:

```dart
  /// The saved score, or (no or unreadable data) base points per matched
  /// pair.
  void _restoreScoring(Map<String, Object?>? json) {
    if (json != null) {
      try {
        final saved = ScoreKeeper.fromJson(json, rules: scoring.rules);
        scoring
          ..reset()
          ..restoreFrom(saved);
        return;
      } on FormatException catch (error) {
        debugPrint('Saved score unreadable, rebuilt from the board ($error)');
      }
    }
    scoring.restoreLegacy(state.matchedPairs);
  }
```

and to `ScoreKeeper` (Task 1 file) a small copy method — add it there with this task:

```dart
  /// Takes over [other]'s state (resume).
  void restoreFrom(ScoreKeeper other) {
    _score = other._score;
    _combo = other._combo;
    _bestCombo = other._bestCombo;
    _pairs = other._pairs;
    _speedBonus = other._speedBonus;
    _lastMatchAt = other._lastMatchAt;
  }
```

Fields (after `_pendingImpacts`):

```dart
  /// The game's score and combo.
  final ScoreKeeper scoring;
  final StreamController<ScoreEvent> _scoreEvents = StreamController.broadcast();

  /// Awards waiting for their pair's strike ([pairImpact]), oldest first.
  final List<ScoreAwarded> _pendingAwards = [];
  Timer? _comboTimer;

  /// True when the last win beat this level's previous best score.
  bool newBestScore = false;
```

Getters:

```dart
  Stream<ScoreEvent> get scoreEvents => _scoreEvents.stream;
  int get score => scoring.score;

  /// The running combo (0 once its window has passed).
  int get activeCombo => scoring.isComboActive(elapsed) ? scoring.currentCombo : 0;

  /// Time left in the combo window, or null when no combo runs.
  Duration? get comboTimeLeft => activeCombo == 0 ? null : scoring.comboExpiresAt! - elapsed;

  bool get clockRunning => _stopwatch.isRunning;
```

In `tapTile`, case `TapOutcome.blocked` — before `return;` add:

```dart
        final taken = scoring.onBlockedTap();
        _scheduleComboEnd();
        if (taken > 0) {
          _emitScore(ScorePenalty(tileId, taken));
          if (state.status == GameStatus.playing) _save();
        }
        if (!_disposed) notifyListeners();
```

case `TapOutcome.matched` — after the `_emit(TrayPairCleared(...))` add:

```dart
        final award = ScoreAwarded(scoring.onMatch(elapsed), result.partnerSlot!);
        if (matchFeedbackOnImpact) {
          _pendingAwards.add(award);
        } else {
          _emitScore(award);
        }
        _scheduleComboEnd();
```

`pairImpact()` — add at the start:

```dart
    if (_pendingAwards.isNotEmpty) _emitScore(_pendingAwards.removeAt(0));
```

`revive()` — after `_cancelFeedback();` add `scoring.endCombo(); _pendingAwards.clear(); _scheduleComboEnd();`.

`restart()` — after `_pendingImpacts = 0;` add `scoring.reset(); _pendingAwards.clear(); newBestScore = false; _scheduleComboEnd();`.

`pauseClock` / `resumeClock`:

```dart
  void pauseClock() {
    _stopwatch.stop();
    _scheduleComboEnd();
  }

  void resumeClock() {
    if (state.status == GameStatus.playing && !_introPlaying) _stopwatch.start();
    _scheduleComboEnd();
  }
```

and in `endIntro()` after the stopwatch start, and in `_afterMove()` after each `_stopwatch.stop()`, call `_scheduleComboEnd();`.

The timer:

```dart
  /// One timer for the moment the running combo's window closes (so the
  /// badge goes away); none while the clock is stopped.
  void _scheduleComboEnd() {
    _comboTimer?.cancel();
    _comboTimer = null;
    final left = comboTimeLeft;
    if (left == null || !_stopwatch.isRunning || _disposed) return;
    _comboTimer = Timer(left + const Duration(milliseconds: 1), () {
      _comboTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _emitScore(ScoreEvent event) {
    if (!_scoreEvents.isClosed) _scoreEvents.add(event);
  }
```

(Restart cancels the old timer before any new one exists, so no stale timer can notify for an old game; the award queue is cleared, so a late `pairImpact` finds nothing.)

`_save()` — add `scoring: scoring.toJson(),` to the `SavedGame(...)`.

`_recordWin()`:

```dart
  Future<void> _recordWin() async {
    final previousBest = progress.completed()[level.levelId]?.bestScore;
    winRecord = await progress.recordWin(
      level.levelId,
      moves: state.moveCount,
      timeMs: elapsed.inMilliseconds,
      score: scoring.score,
      bestCombo: scoring.bestCombo,
    );
    newBestScore = previousBest != null && scoring.score > previousBest;
    await progress.clearSavedGame(levelId: level.levelId);
    if (!_disposed) notifyListeners();
  }
```

`dispose()` — add `_comboTimer?.cancel(); unawaited(_scoreEvents.close());`.

- [ ] **Step 5: Run the tests**

Run: `~/flutter/bin/flutter test test/features/game_controller_scoring_test.dart test/features/game_controller_test.dart test/game_engine/score_keeper_test.dart`
Expected: all PASS (existing controller tests unchanged).

- [ ] **Step 6: Analyze, full suite, commit**

`~/flutter/bin/flutter analyze` clean; `~/flutter/bin/flutter test` only the 6 known failures.

```bash
git add lib/features/gameplay/game_controller.dart lib/game_engine/scoring/score_keeper.dart test/helpers/fake_stopwatch.dart test/features/game_controller_scoring_test.dart
git commit -m "$(printf 'Game: score matches and blocked taps; save, restore and record scoring\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 4: HUD score, combo badge and score popups

**Files:**
- Create: `lib/features/gameplay/widgets/score_format.dart`
- Create: `lib/features/gameplay/widgets/combo_badge.dart`
- Create: `lib/features/gameplay/widgets/score_popups.dart`
- Modify: `lib/features/gameplay/game_screen.dart` (`_Hud` stats; tray wrapped in a `Stack` with the badge; popup overlay in the top-level `Stack`)
- Test: `test/features/score_hud_test.dart`

**Interfaces:**
- Consumes: Task 3 `GameController.score`, `activeCombo`, `comboTimeLeft`, `clockRunning`, `scoring.bestCombo`, `scoreEvents` (`ScoreAwarded(score, traySlot)`, `ScorePenalty(tileId, points)`); `TrayViewState.slotRect(int)` (global rect); `BoardViewState.tileFaceRect(String)` (global rect).
- Produces: `String formatScore(int)` (`12450` → `12,450`); `ComboBadge({required GameController controller, required bool reduceMotion})`; `ScorePopupOverlay({required GameController controller, required Rect? Function(int slot) traySlotRect, required Rect? Function(String tileId) tileRect, required bool reduceMotion})`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/score_hud_test.dart`. Build the game screen the way `test/features/restart_button_test.dart` / `test/features/game_flow_test.dart` do (read them and reuse their pump helper and fixture), with `MediaQuery(disableAnimations: false)` unless stated. Tests:

```dart
  // (helpers from game_flow_test: pump the GameScreen for a fixture level, tap tiles by id)

  testWidgets('the HUD shows SCORE instead of Moves', (tester) async {
    // pump game
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('MOVES'), findsNothing);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('the score counts up to its new value after a match', (tester) async {
    // tap a matching pair (ids from the fixture)
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('the combo badge appears at ×2 and goes when the window closes', (tester) async {
    // two quick matches
    expect(find.text('COMBO ×2'), findsOneWidget);
    expect(find.textContaining('Best ×2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // window passes (real clock in the screen)
    expect(find.text('COMBO ×2'), findsNothing);
    expect(find.textContaining('Best ×2'), findsOneWidget);
  });

  testWidgets('popups never block taps', (tester) async {
    // after a match, a popup is on screen; tapping a free board tile under it still works
    expect(find.byType(ScorePopupOverlay), findsOneWidget);
    final ignore = find.ancestor(of: find.byType(ScorePopupOverlay), matching: find.byType(IgnorePointer));
    expect(tester.widgetList<IgnorePointer>(ignore).any((w) => w.ignoring), isTrue);
  });

  testWidgets('reduce motion: no popups, numbers update in place', (tester) async {
    // pump with MediaQuery(disableAnimations: true), match a pair
    await tester.pump();
    expect(find.textContaining('+100'), findsNothing);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('360x640 at 1.3x text: no overflow with SCORE and Restart', (tester) async {
    // set view 360x640 @ dpr 2, textScale 1.3, pump game
    expect(tester.takeException(), isNull);
  });
```

Write them out fully against the real helpers (no comments left as code); the expected texts are verbatim from the Global Constraints.

Time in widget tests: the screen's `GameController` uses a real `Stopwatch`, which `tester.pump(duration)` does NOT advance. For the combo-window tests either drive real time with `tester.runAsync(() => Future<void>.delayed(...))` (as `test/features/restart_button_test.dart` does for its clock tests), or add a `@visibleForTesting Stopwatch? stopwatch` parameter to `GameScreen` that is passed through to `GameController(stopwatch:)` and use `FakeStopwatch` (`test/helpers/fake_stopwatch.dart`). Prefer the parameter (deterministic); keep it `@visibleForTesting`.

- [ ] **Step 2: Run to see them fail** — `~/flutter/bin/flutter test test/features/score_hud_test.dart` → FAIL.

- [ ] **Step 3: `formatScore`**

Create `lib/features/gameplay/widgets/score_format.dart`:

```dart
/// 12450 → "12,450".
String formatScore(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
```

(Add two asserts to `score_hud_test.dart`: `formatScore(0) == '0'`, `formatScore(1250) == '1,250'`, `formatScore(1234567) == '1,234,567'`.)

- [ ] **Step 4: HUD** — in `_Hud`, replace `PremiumStat(label: 'Moves', value: '${state.moveCount}'),` with an animated score stat:

```dart
                            TweenAnimationBuilder<int>(
                              tween: IntTween(end: controller.score),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 300),
                              builder: (context, value, _) => PremiumStat(label: 'Score', value: formatScore(value)),
                            ),
```

(`IntTween(end:)` animates from the previous value to the new one; first build starts at the current value.)

- [ ] **Step 5: Combo badge**

Create `lib/features/gameplay/widgets/combo_badge.dart` — a `StatefulWidget` with `TickerProviderStateMixin`:

- Listens to `controller` (`ChangeNotifier`). Shows a column: when `controller.activeCombo >= 2`, a pill (height 28, horizontal padding 14, `StadiumBorder`, gradient `[Color(0xE6F8DA8C), Color(0xD9D8B25E)]`, 1.2 px rim `BrandGold.light`) with text `COMBO ×N` (`displayText(13, color: Color(0xFF183D2D), weight: FontWeight.w800, spacing: 1.2)`) and, to its right inside the pill, an 18 px ring (`CustomPaint` arc, stroke 2.2, `Color(0xFF183D2D)` at alpha 0.8) whose sweep = `comboTimeLeft / scoring.rules.comboWindow`; under the pill (or alone when no badge) `Best ×N` (`displayText(11, color: BrandGold.light.withValues(alpha: 0.85), weight: FontWeight.w600)`) when `scoring.bestCombo >= 2`, else nothing.
- Ring ticking: a `Ticker` that runs only while `activeCombo >= 2 && controller.clockRunning && !reduceMotion`; each tick `setState` on the ring only (wrap the ring in its own `RepaintBoundary`; the pill's static parts in a `StaticLayer` per CLAUDE.md, ring outside it). Stop the ticker otherwise.
- Intensity, each once when the combo first reaches the level (track the last combo seen; reset when combo drops below 2): ×3 → rim `BrandGold.warm` and an outer glow painted by a `CustomPainter` (radial gradient, no blur filter); ×4 → a one-shot 600 ms burst of 7 small gold sparks (`CustomPainter`, colour alpha fades) around the pill; ×5+ → a one-shot 700 ms shimmer: a light band (linear gradient with alpha) swept across the pill by a `CustomPainter`. One `AnimationController` per effect, `forward(from: 0)` then stopped; nothing ticks between effects. No effects with `reduceMotion`.
- Wrapped in `IgnorePointer` and `ExcludeSemantics` is NOT used for the text: give the pill `Semantics(label: 'Combo times N', liveRegion: true)`.

In `game_screen.dart`, wrap the `TrayView`'s `Padding` child in:

```dart
Stack(
  clipBehavior: Clip.none,
  children: [
    TrayView(...existing...),
    // Floats on the tray's bottom edge: no layout change, so the board keeps
    // its size (the 31-px face guarantee).
    Positioned(
      left: 0,
      right: 0,
      bottom: -16,
      child: IgnorePointer(child: Center(child: ComboBadge(controller: controller, reduceMotion: reduceMotion))),
    ),
  ],
),
```

- [ ] **Step 6: Score popups**

Create `lib/features/gameplay/widgets/score_popups.dart` — `ScorePopupOverlay` (`StatefulWidget`, `SingleTickerProviderStateMixin`):

- Subscribes to `controller.scoreEvents`. For `ScoreAwarded(score, traySlot)`: origin = centre-bottom of `traySlotRect(traySlot)` converted from global to the overlay's local coordinates (`(context.findRenderObject() as RenderBox).globalToLocal`); popup lines `+${formatScore(score.points)}` (`displayText(20, color: BrandGold.light, weight: FontWeight.w800)` with a dark text shadow) and `×${score.multiplier}` + (`score.speedBonus > 0` ? ` · +${score.speedBonus} fast` : '') (`displayText(12, color: BrandGold.light, weight: FontWeight.w600)`). For `ScorePenalty(tileId, points)`: origin = centre of `tileRect(tileId)`; one line `−$points` in muted rose `Color(0xFFE59A9A)`, size 16.
- Animation per popup: scale 0.6 → 1.0 over the first 120 ms (`Curves.easeOutBack`), then rise 28 px and fade to alpha 0 over 700 ms (award) / 500 ms (penalty). Drawn by one `CustomPainter` with `TextPainter`s whose colours carry the alpha (no `Opacity`). Awards rise downward from the tray into the tray–board gap (positive dy) so they never cover board tiles' upper rows for long; penalties rise upward from the tile.
- One `Ticker` runs only while popups exist; dispose `TextPainter`s when a popup ends.
- `reduceMotion` → ignore events (no popups).
- The whole overlay: `IgnorePointer(child: ...)`.

In `game_screen.dart`, add to the top-level `Stack` children, after `TileShatterOverlay`:

```dart
            // Score feedback; ticks only while a popup is alive.
            Positioned.fill(
              child: IgnorePointer(
                child: ScorePopupOverlay(
                  controller: controller,
                  traySlotRect: (slot) => _trayKey.currentState?.slotRect(slot),
                  tileRect: (id) => _boardKey.currentState?.tileFaceRect(id),
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
```

- [ ] **Step 7: Run tests, captures**

Run: `~/flutter/bin/flutter test test/features/score_hud_test.dart test/features/restart_button_test.dart test/features/game_flow_test.dart`
Expected: PASS. Update existing expectations that relied on the `Moves` stat in the HUD only if they assert the HUD (e.g. a test finding 'MOVES'); say so in the report.

Run: `CAPTURE_DIR=/private/tmp/claude-501/-Users-suraj-kum-Code-Brain-Train/7565078f-55a3-459a-a0c7-58622b3c038b/scratchpad/shots-S4 ~/flutter/bin/flutter test test/visual/gameplay_capture_test.dart` and add to that file one capture of a game with an active ×3 combo (in its existing style), `gameplay_night_411x914_combo.png`. Read it: badge on the tray's bottom edge, not covering board tiles' faces more than its lower half over the 6 px gap and board margin.

- [ ] **Step 8: Analyze, full suite, commit**

`~/flutter/bin/flutter analyze` clean; full suite only the 6 known failures.

```bash
git add lib/features/gameplay/widgets/score_format.dart lib/features/gameplay/widgets/combo_badge.dart lib/features/gameplay/widgets/score_popups.dart lib/features/gameplay/game_screen.dart test/features/score_hud_test.dart test/visual/gameplay_capture_test.dart
git commit -m "$(printf 'Game: SCORE in the HUD, combo badge and score popups\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 5: Win card and Completed Levels show the score

**Files:**
- Modify: `lib/features/gameplay/game_screen.dart` (`_CompletionCard` only)
- Modify: `lib/features/levels/level_select_screen.dart` (completed row)
- Test: `test/features/score_results_test.dart`

**Interfaces:**
- Consumes: Task 3 `GameController.score`, `scoring.bestCombo`, `scoring.totalPairsMatched`, `newBestScore`, `winRecord` (`LevelRecord` with `bestScore`); Task 2 `LevelRecord.bestScore`; Task 4 `formatScore` (from `widgets/score_format.dart`).
- Produces: nothing new.

Runs after Task 4 if both touch `game_screen.dart` in one checkout; it only edits `_CompletionCard` (Task 4 never touches it), so it may run in parallel in its own worktree and be merged.

- [ ] **Step 1: Write the failing tests** — `test/features/score_results_test.dart`, reusing the game-flow helper to win a fixture level (read `test/features/game_flow_test.dart` / `test/visual/gameplay_capture_test.dart` win-card test):

1. After a win, the card shows `Score`, the score with separators, `Best combo ×N`, `Pairs n/n`, the time and the moves, and `Best: <bestScore> · <fastest time>`.
2. Win the same level a second time with a higher score → `New best!` is shown; with a lower score → not shown.
3. Completed Levels: a level with `bestScore` 12450 shows `12,450` in its row; a level recorded without a score (`recordWin` without `score:`) shows `—`.
4. 360×640 at 1.3× text: the win card and Completed Levels lay out without new overflow (Completed Levels already has the known 4.4 px overflow on this machine — assert only that no NEW exception appears compared with a level without score; or assert on the win card only).

- [ ] **Step 2: Run to see them fail.**

- [ ] **Step 3: Win card** — in `_CompletionCard.build`, replace the `'${controller.state.moveCount} moves  ·  …'` text and the `if (record != null)` Best line with:

```dart
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Score ', style: displayText(16, color: BrandGold.light, weight: FontWeight.w600)),
            Text(formatScore(controller.score), style: displayText(30, color: BrandGold.warm, weight: FontWeight.w800)),
          ],
        ),
        if (controller.newBestScore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('New best!', style: displayText(14, color: BrandGold.light, weight: FontWeight.w700, spacing: 0.6)),
          ),
        const SizedBox(height: 8),
        Text(
          '${formatDuration(controller.elapsed)}  ·  ${controller.state.moveCount} moves',
          textAlign: TextAlign.center,
          style: displayText(16, color: BrainTrainColors.ivory.withValues(alpha: 0.85), weight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          'Best combo ×${controller.scoring.bestCombo}  ·  Pairs ${controller.scoring.totalPairsMatched}/${controller.state.totalPairs}',
          textAlign: TextAlign.center,
          style: displayText(15, color: BrainTrainColors.ivory.withValues(alpha: 0.85), weight: FontWeight.w500),
        ),
        if (record != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Best: ${record.bestScore == null ? '—' : formatScore(record.bestScore!)} · ${formatDuration(Duration(milliseconds: record.bestTimeMs))}',
              textAlign: TextAlign.center,
              style: displayText(14, color: BrandGold.base, weight: FontWeight.w500),
            ),
          ),
```

(import `widgets/score_format.dart`). Note: `totalPairsMatched` after a resumed legacy save equals the board's matched pairs, so `Pairs n/n` is right on a win.

- [ ] **Step 4: Completed Levels row** — in the completed row's right-hand `Column` (`level_select_screen.dart`, the one with the timer icon and `time`), after the time `Row` add:

```dart
                        const SizedBox(height: 2),
                        Text(
                          record.bestScore == null ? '—' : formatScore(record.bestScore!),
                          style: displayText(13, color: lobby.panelAccent, weight: FontWeight.w600),
                        ),
```

before the existing `SizedBox(height: 4)` + `when` text, and extend the row's semantics label with `, best score ${record.bestScore ?? 'none'}`. Import `../gameplay/widgets/score_format.dart`.

- [ ] **Step 5: Run tests** — `~/flutter/bin/flutter test test/features/score_results_test.dart test/features/level_select_test.dart` (level_select_test has 2 known pre-existing failures — they must be the same two, unchanged).

- [ ] **Step 6: Captures** — `CAPTURE_DIR=<scratch>/shots-S5 ~/flutter/bin/flutter test test/visual/gameplay_capture_test.dart test/visual/lobby_capture_test.dart`; Read the win card and Levels captures (`<scratch>` = /private/tmp/claude-501/-Users-suraj-kum-Code-Brain-Train/7565078f-55a3-459a-a0c7-58622b3c038b/scratchpad).

- [ ] **Step 7: Analyze, full suite, commit**

```bash
git add lib/features/gameplay/game_screen.dart lib/features/levels/level_select_screen.dart test/features/score_results_test.dart
git commit -m "$(printf 'Win card and Completed Levels show score, best score and best combo\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 6: Docs and the emulator check

**Files:**
- Modify: `CLAUDE.md`
- Modify: `pubspec.yaml` (comment only: the trophy line says "plays once, holds" — it loops)

- [ ] **Step 1: CLAUDE.md** — Layout: add `lib/game_engine/scoring/` (`ScoringRules`, `ScoreKeeper`: pure Dart) to the `lib/game_engine/` bullet and the new gameplay widgets (`combo_badge.dart`, `score_popups.dart`, `score_format.dart`). Rules that are easy to break: add a Scoring bullet — "Scoring (owner): 100 × min(combo, 5) + speed bonus (+50 < 1 s, +25 < 2 s, +10 ≤ 3 s); combo window 3 s on the game clock (pauses with it); only `TapOutcome.matched` scores; a blocked-tile tap costs 1 (never below 0) and ends the combo; Revive ends the combo; Restart resets; score state is saved in `SavedGame.scoring`; `LevelRecord.bestScore/bestCombo` only go up. The combo badge floats on the tray's bottom edge — never add layout space between tray and board (31-px faces)." Product decisions: HUD shows SCORE (not Moves); win card fields. Open work: remove "scoring + combo system is in design"; keep Play Games pieces 2–3 (piece 2 builds on `bestScore`/`bestCombo`).
- [ ] **Step 2: pubspec comment** — change the trophy asset comment to say it loops while the Level complete card is open.
- [ ] **Step 3: Emulator** — `~/flutter/bin/flutter build apk --debug`, `adb install -r …`, `adb shell am force-stop com.sungamestudio.braintrain`, launch with `adb shell monkey -p com.sungamestudio.braintrain -c android.intent.category.LAUNCHER 1`, wait ~16 s, open a level (tap Play), make two quick matches if feasible by tapping (`adb shell input tap X Y` from a screenshot), screenshot to `<scratch>/S6-combo.png`; `adb logcat -d | grep -E "FATAL|AndroidRuntime"` → no crash. If driving matches by taps is unreliable, screenshot the HUD with SCORE and say so.
- [ ] **Step 4: Verify and commit** — `~/flutter/bin/flutter analyze` clean, `~/flutter/bin/flutter test` only the 6 known failures.

```bash
git add CLAUDE.md pubspec.yaml
git commit -m "$(printf 'Docs: scoring and combo rules\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

## Parallelism (for the executor)

Tasks 1 and 2 are independent (run in parallel, separate worktrees). Task 3 needs both. Tasks 4 and 5 both need Task 3; they edit different parts of `game_screen.dart` (`_Hud`/layout vs `_CompletionCard`) and can run in parallel in separate worktrees, merged after review. Task 6 last. Only one task at a time may use the emulator.

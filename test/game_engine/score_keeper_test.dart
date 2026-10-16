import 'package:brain_train/game_engine/scoring/score_format.dart';
import 'package:brain_train/game_engine/scoring/score_keeper.dart';
import 'package:brain_train/game_engine/scoring/scoring_rules.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(keeper.comboExpiresAt, s(9));
    expect(keeper.isComboActive(s(9)), isTrue);
    expect(keeper.isComboActive(s(9.001)), isFalse);
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
    expect(rules.speedBonusFor(s(3.5)), 10);
    expect(rules.speedBonusFor(s(4)), 10);
    expect(rules.speedBonusFor(s(4.001)), 0);
    keeper.onMatch(s(0));
    final atWindow = keeper.onMatch(s(4));
    expect((atWindow.combo, atWindow.speedBonus, atWindow.points), (2, 10, 210));
    final past = keeper.onMatch(s(8.001));
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

  test('every match restarts the window: a long chain of 2.5 s gaps keeps going', () {
    for (final t in [0, 2.5, 5, 7.5, 10]) {
      keeper.onMatch(s(t));
    }
    expect(keeper.currentCombo, 5);
    expect(keeper.currentMultiplier, 5);
    expect(keeper.comboExpiresAt, s(14));
    expect(keeper.isComboActive(s(13.9)), isTrue);
    expect(keeper.isComboActive(s(15)), isFalse);
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
    final next = copy.onMatch(s(11.5)); // gap 0.5 s
    expect((next.combo, next.speedBonus), (3, 50));
  });

  test('fromJson rejects bad data', () {
    expect(() => ScoreKeeper.fromJson({'score': 'x'}), throwsFormatException);
    expect(() => ScoreKeeper.fromJson({'score': -5, 'combo': 0, 'bestCombo': 0, 'pairs': 0}), throwsFormatException);
  });

  group('undo', () {
    (int, int, int, int, Duration?) stateOf(ScoreKeeper k) =>
        (k.score, k.currentCombo, k.bestCombo, k.totalPairsMatched, k.lastSuccessfulMatchTime);

    test('takes back the last match: score, combo, best and the combo clock as before it', () {
      keeper.onMatch(s(0));
      keeper.onMatch(s(1));
      final before = stateOf(keeper);
      expect(keeper.undoableMatches, 2);
      expect(keeper.pairsBeforeUndo, 1);
      keeper.onMatch(s(1.5)); // x3, +50
      expect(keeper.bestCombo, 3);
      expect(keeper.undoMatch(), isTrue);
      expect(stateOf(keeper), before);
      expect(keeper.isComboActive(s(4)), isTrue, reason: 'the window runs from the match before');
      expect(keeper.undoMatch(), isTrue);
      expect(keeper.undoMatch(), isTrue);
      expect(stateOf(keeper), (0, 0, 0, 0, null));
      expect(keeper.undoMatch(), isFalse);
      expect(keeper.pairsBeforeUndo, isNull);
    });

    test('blocked-tap penalties taken after the match stay taken', () {
      keeper.onMatch(s(0)); // 100
      keeper.onMatch(s(1)); // 225
      keeper.onBlockedTap(); // 324, combo ends
      expect(keeper.undoMatch(), isTrue);
      expect((keeper.score, keeper.currentCombo, keeper.totalPairsMatched), (99, 0, 1));
      // A penalty before the match is part of the state it goes back to.
      final k = ScoreKeeper()
        ..onMatch(s(0))
        ..onBlockedTap()
        ..onMatch(s(10));
      expect(k.score, 199);
      expect(k.undoMatch(), isTrue);
      expect(k.score, 99);
    });

    test('sealUndo: a revive or a shuffle keeps earlier matches; reset forgets them', () {
      keeper
        ..onMatch(s(0))
        ..sealUndo();
      expect(keeper.undoMatch(), isFalse);
      expect(keeper.score, 100);
      keeper.onMatch(s(10));
      expect(keeper.undoableMatches, 1);
      keeper.reset();
      expect(keeper.undoableMatches, 0);
    });

    test('checkpoints and blocked taps survive a JSON round trip and restoreFrom', () {
      keeper
        ..onMatch(s(0))
        ..onBlockedTap()
        ..onMatch(s(1.2));
      final json = keeper.toJson();
      expect(json['undo'], [
        [0, 0, 0, 0, -1, 0],
        [99, 0, 1, 1, -1, 1],
      ], reason: 'the blocked tap had ended the combo');
      expect(json['blockedTaps'], 1);
      final copy = ScoreKeeper.fromJson(json);
      final restored = ScoreKeeper()..restoreFrom(copy);
      for (final k in [copy, restored]) {
        expect(k.undoableMatches, 2);
        expect(k.undoMatch(), isTrue);
        expect((k.score, k.totalPairsMatched, k.lastSuccessfulMatchTime), (99, 1, null));
        expect(k.undoMatch(), isTrue);
        expect(k.score, 0, reason: 'the penalty after the first match is taken again, from 0');
      }
      // Saves from before undo have neither field.
      final old = ScoreKeeper.fromJson({'score': 100, 'combo': 1, 'bestCombo': 1, 'pairs': 1, 'lastMatchAtMs': 0});
      expect(old.undoableMatches, 0);
      expect(old.toJson().containsKey('undo'), isFalse);
      expect(old.toJson().containsKey('blockedTaps'), isFalse);
    });

    test('fromJson rejects bad checkpoints', () {
      Map<String, Object?> withUndo(Object? undo) => {'score': 0, 'combo': 0, 'bestCombo': 0, 'pairs': 0, 'undo': undo};
      expect(() => ScoreKeeper.fromJson(withUndo('x')), throwsFormatException);
      expect(() => ScoreKeeper.fromJson(withUndo([
        [1, 2, 3],
      ])), throwsFormatException);
      expect(() => ScoreKeeper.fromJson(withUndo([
        [0, 0, 0, 0, -2, 0],
      ])), throwsFormatException);
      expect(() => ScoreKeeper.fromJson({...withUndo(const []), 'blockedTaps': -1}), throwsFormatException);
    });
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

  group('formatScore', () {
    test('groups thousands with commas', () {
      expect(formatScore(0), '0');
      expect(formatScore(999), '999');
      expect(formatScore(1250), '1,250');
      expect(formatScore(12450), '12,450');
      expect(formatScore(1234567), '1,234,567');
    });
  });
}

import 'dart:convert';

import 'package:brain_train/game_engine/models/json_reader.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/level_rules.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/level_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  // a1 a2 b1 b2 in a row: only the ends (a1, b2) start free.
  final row = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('b1', 'B', 4, 0, 0), ('b2', 'B', 6, 0, 0)]);
  // Two separate pairs, all free.
  final open = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0), ('b1', 'B', 8, 0, 0), ('b2', 'B', 12, 0, 0)]);
  // Four separate pairs (A B C D A B C D), all free.
  final wide = level([
    for (final (i, code) in ['A', 'B', 'C', 'D', 'A', 'B', 'C', 'D'].indexed)
      ('${code.toLowerCase()}${i < 4 ? 1 : 2}', code, i * 4.0, 0.0, 0),
  ]);
  final reg = registry(['A', 'B', 'C', 'D', 'ZINNIA', 'ANEMONE']);

  test('the tray holds four tiles by default', () {
    expect(GameEngine.defaultTrayCapacity, 4);
    expect(engineFor(open, reg).state.trayCapacity, 4);
  });

  test('a free tile leaves the board for the next tray slot', () {
    final e = engineFor(wide, reg);
    final first = e.tap('a1');
    expect(first.outcome, TapOutcome.toTray);
    expect(first.slot, 0);
    expect(first.accepted, isTrue);
    final second = e.tap('b1');
    expect(second.outcome, TapOutcome.toTray);
    expect(second.slot, 1);
    expect(e.state.tray, ['a1', 'b1']);
    expect(e.state.remaining, isNot(contains('a1')));
    expect(e.state.free, isNot(contains('a1')));
    expect(e.isInTray(e.indexOf('a1')!), isTrue);
    expect(e.isRemaining(e.indexOf('a1')!), isFalse);
    expect(e.state.moveCount, 2);
    expect(e.state.history, ['a1', 'b1']);
    expect(e.state.matchedPairs, 0);
    expect(e.state.status, GameStatus.playing);
  });

  test('an arriving tile that matches a tray tile destroys both and the tray re-packs', () {
    final e = engineFor(wide, reg)
      ..tap('a1')
      ..tap('b1');
    final result = e.tap('a2');
    expect(result.outcome, TapOutcome.matched);
    expect(result.slot, 2, reason: 'lands next to the tray tiles before clearing');
    expect(result.partnerTileId, 'a1');
    expect(result.partnerSlot, 0);
    expect(e.state.tray, ['b1']);
    expect(e.state.remaining, isNot(contains('a2')));
    expect(e.state.matchedPairs, 1);
    expect(e.state.moveCount, 3);
    expect(e.state.status, GameStatus.playing);
  });

  test('four tiles that do not match fill the tray and lose', () {
    final e = engineFor(wide, reg);
    for (final id in ['a1', 'b1', 'c1']) {
      expect(e.tap(id).outcome, TapOutcome.toTray);
    }
    final last = e.tap('d1');
    expect(last.outcome, TapOutcome.trayFull);
    expect(last.slot, 3);
    expect(e.state.status, GameStatus.trayFull);
    expect(e.state.isTrayFull, isTrue);
    expect(e.state.tray, ['a1', 'b1', 'c1', 'd1']);
    // The game is over: even a matching free tile is ignored.
    expect(e.tap('a2').outcome, TapOutcome.ignored);
    expect(e.state.moveCount, 4);
  });

  test('a match on the fourth tap clears instead of filling the tray', () {
    final e = engineFor(wide, reg)
      ..tap('a1')
      ..tap('b1')
      ..tap('c1');
    final result = e.tap('c2');
    expect(result.outcome, TapOutcome.matched);
    expect(result.slot, 3);
    expect(result.partnerSlot, 2);
    expect(e.state.tray, ['a1', 'b1']);
    expect(e.state.status, GameStatus.playing);
  });

  test('the tray capacity is configurable', () {
    final e = GameEngine(level: wide, rules: MatchRules(level: wide, registry: reg), trayCapacity: 2);
    expect(e.tap('a1').outcome, TapOutcome.toTray);
    expect(e.tap('b1').outcome, TapOutcome.trayFull);
    expect(e.state.trayCapacity, 2);
  });

  test('blocked tiles are rejected and change nothing', () {
    final e = engineFor(row, reg);
    final result = e.tap('a2');
    expect(result.outcome, TapOutcome.blocked);
    expect(result.accepted, isFalse);
    expect(e.state.tray, isEmpty);
    expect(e.state.moveCount, 0);
    expect(e.state.free, {'a1', 'b2'});
  });

  test('a covered tile is blocked until the tile on top leaves', () {
    final stack = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 0, 0, 1), ('a2', 'A', 6, 0, 0), ('b2', 'B', 10, 0, 0)]);
    final e = engineFor(stack, reg);
    expect(e.tap('a1').outcome, TapOutcome.blocked);
    expect(e.tap('b1').outcome, TapOutcome.toTray);
    expect(e.state.free, contains('a1'));
    expect(e.tap('a1').outcome, TapOutcome.toTray);
  });

  test('taking a tile off the board frees its neighbours at once', () {
    final e = engineFor(row, reg);
    expect(e.state.free, {'a1', 'b2'});
    e.tap('a1');
    expect(e.state.free, {'a2', 'b2'});
    expect(e.isFreeIndex(e.indexOf('a2')!), isTrue);
    e.tap('b2');
    expect(e.state.free, {'a2', 'b1'});
  });

  test('tiles already in the tray or cleared are ignored, so a tile never moves twice', () {
    final e = engineFor(open, reg)..tap('a1');
    expect(e.tap('a1').outcome, TapOutcome.ignored);
    e.tap('a2');
    expect(e.tap('a1').outcome, TapOutcome.ignored);
    expect(e.tap('a2').outcome, TapOutcome.ignored);
    expect(e.tap('unknown').outcome, TapOutcome.ignored);
    expect(e.state.matchedPairs, 1);
    expect(e.state.moveCount, 2);
  });

  test('emptying the board and the tray wins; further taps are ignored', () {
    final e = engineFor(open, reg);
    for (final id in ['a1', 'b1', 'a2']) {
      e.tap(id);
    }
    expect(e.state.status, GameStatus.playing, reason: 'b1 still waits in the tray');
    expect(e.tap('b2').outcome, TapOutcome.matched);
    expect(e.state.status, GameStatus.won);
    expect(e.state.remaining, isEmpty);
    expect(e.state.tray, isEmpty);
    expect(e.state.matchedPairs, 2);
    expect(e.state.progress, 1);
    expect(e.tap('b2').outcome, TapOutcome.ignored);
  });

  test('crossed stacks that no pair order clears are won through the tray', () {
    // B on A and A on B: the pair solver calls this unsolvable.
    final crossed = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 0, 0, 1), ('b2', 'B', 6, 0, 0), ('a2', 'A', 6, 0, 1)]);
    final e = engineFor(crossed, reg);
    expect(e.state.status, GameStatus.playing);
    expect(e.tap('b1').outcome, TapOutcome.toTray);
    expect(e.tap('a2').outcome, TapOutcome.toTray);
    expect(e.tap('a1').outcome, TapOutcome.matched);
    expect(e.tap('b2').outcome, TapOutcome.matched);
    expect(e.state.status, GameStatus.won);
  });

  test('restart resets the board, the tray and the counters', () {
    final e = engineFor(wide, reg);
    for (final id in ['a1', 'b1', 'c1', 'd1']) {
      e.tap(id);
    }
    expect(e.state.status, GameStatus.trayFull);
    e.restart();
    expect(e.state.remaining.length, 8);
    expect(e.state.tray, isEmpty);
    expect(e.state.moveCount, 0);
    expect(e.state.matchedPairs, 0);
    expect(e.state.history, isEmpty);
    expect(e.state.status, GameStatus.playing);
    expect(e.tap('a1').outcome, TapOutcome.toTray);
  });

  test('replay re-applies saved taps, board and tray included', () {
    final e = engineFor(wide, reg);
    expect(e.replay(['a1', 'b1', 'a2']), isTrue);
    expect(e.state.tray, ['b1']);
    expect(e.state.matchedPairs, 1);
    expect(e.state.moveCount, 3);
    expect(e.state.history, ['a1', 'b1', 'a2']);
    expect(e.state.remaining.length, 5);
  });

  test('replay stops at the first illegal tap, keeping the valid prefix', () {
    final f = engineFor(row, reg);
    expect(f.replay(['a2']), isFalse); // a2 is blocked at the start
    expect(f.state.remaining.length, 4);
    expect(f.state.moveCount, 0);
    final g = engineFor(row, reg);
    expect(g.replay(['a1', 'a2', 'a1']), isFalse); // a1 was already cleared
    expect(g.state.matchedPairs, 1);
    expect(g.state.history, ['a1', 'a2']);
  });

  test('a pair-removal order replays as taps and wins', () {
    final e = engineFor(open, reg);
    expect(e.replay(['a1', 'a2', 'b1', 'b2']), isTrue);
    expect(e.state.status, GameStatus.won);
  });

  group('revive', () {
    test('puts the tray tiles back on the board, empties the tray, and is not a move', () {
      final e = engineFor(wide, reg);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      expect(e.state.status, GameStatus.trayFull);
      expect(e.revive(), ['a1', 'b1', 'c1', 'd1']);
      expect(e.state.status, GameStatus.playing);
      expect(e.state.tray, isEmpty);
      expect(e.state.remaining.length, 8);
      expect(e.state.free.length, 8);
      expect(e.state.moveCount, 4);
      expect(e.state.history, ['a1', 'b1', 'c1', 'd1', GameEngine.reviveMarker]);
      expect(e.tap('a1').outcome, TapOutcome.toTray, reason: 'the returned tiles play again');
    });

    test('only revives a game lost with a full tray', () {
      final e = engineFor(wide, reg);
      expect(e.revive(), isNull);
      e.tap('a1');
      expect(e.revive(), isNull);
      expect(e.state.tray, ['a1']);
    });

    test('pairs cleared before stay cleared', () {
      final e = GameEngine(level: wide, rules: MatchRules(level: wide, registry: reg), trayCapacity: 3);
      for (final id in ['a1', 'a2', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      expect(e.state.status, GameStatus.trayFull);
      expect(e.revive(), ['b1', 'c1', 'd1']);
      expect(e.state.matchedPairs, 1);
      expect(e.state.remaining, {'b1', 'b2', 'c1', 'c2', 'd1', 'd2'});
    });

    test('returned tiles block their neighbours again', () {
      final e = GameEngine(level: row, rules: MatchRules(level: row, registry: reg), trayCapacity: 2);
      e.tap('a1');
      expect(e.state.free, {'a2', 'b2'});
      expect(e.tap('b2').outcome, TapOutcome.trayFull);
      e.revive();
      expect(e.state.free, {'a1', 'b2'});
      expect(e.tap('a2').outcome, TapOutcome.blocked);
    });

    test('a returned tile covers the returned tile under it', () {
      final stacked = level([
        ('x1', 'A', 0, 0, 0),
        ('y1', 'B', 0, 0, 1),
        ('c1', 'C', 6, 0, 0),
        ('d1', 'D', 10, 0, 0),
        ('x2', 'A', 14, 0, 0),
        ('y2', 'B', 18, 0, 0),
        ('c2', 'C', 22, 0, 0),
        ('d2', 'D', 26, 0, 0),
      ]);
      final e = engineFor(stacked, reg);
      for (final id in ['y1', 'x1', 'c1', 'd1']) {
        e.tap(id);
      }
      expect(e.state.status, GameStatus.trayFull);
      e.revive();
      expect(e.state.free, isNot(contains('x1')));
      expect(e.state.free, contains('y1'));
      expect(e.tap('x1').outcome, TapOutcome.blocked);
    });

    test('replay re-applies revives, and the game can still be won', () {
      final e = engineFor(wide, reg);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      e.revive();
      e.tap('a1');
      final resumed = engineFor(wide, reg);
      expect(resumed.replay(e.state.history), isTrue);
      expect(resumed.state.tray, ['a1']);
      expect(resumed.state.remaining.length, 7);
      expect(resumed.state.moveCount, 5);
      for (final id in ['a2', 'b1', 'b2', 'c1', 'c2', 'd1', 'd2']) {
        resumed.tap(id);
      }
      expect(resumed.state.status, GameStatus.won);
      // A revive marker where nothing can be revived is illegal.
      expect(engineFor(wide, reg).replay([GameEngine.reviveMarker]), isFalse);
    });

    test('restart forgets revives', () {
      final e = engineFor(wide, reg);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      e
        ..revive()
        ..restart();
      expect(e.state.history, isEmpty);
      expect(e.state.moveCount, 0);
    });

    group('at most kMaxRevivesPerLevel per attempt', () {
      /// Fills the 4-slot tray of [wide] with four unmatched tiles.
      void fill(GameEngine e) {
        for (final id in ['a1', 'b1', 'c1', 'd1']) {
          e.tap(id);
        }
        expect(e.state.status, GameStatus.trayFull);
      }

      test('the limit is 2', () => expect(kMaxRevivesPerLevel, 2));

      test('a third revive is refused and changes nothing', () {
        final e = engineFor(wide, reg);
        expect(e.revivesLeft, 2);
        fill(e);
        expect(e.canRevive, isTrue);
        expect(e.revive(), isNotNull);
        expect(e.revivesUsed, 1);
        expect(e.revivesLeft, 1);
        fill(e);
        expect(e.revive(), isNotNull);
        expect(e.revivesLeft, 0);
        fill(e);
        expect(e.canRevive, isFalse);
        final before = e.state.history;
        expect(e.revive(), isNull);
        expect(e.state.status, GameStatus.trayFull);
        expect(e.state.tray, ['a1', 'b1', 'c1', 'd1']);
        expect(e.state.history, before);
        expect(e.state.history.where((h) => h == GameEngine.reviveMarker), hasLength(2));
      });

      test('a resumed save keeps its count (from its revive markers)', () {
        final e = engineFor(wide, reg);
        fill(e);
        e.revive();
        fill(e);
        e.revive();
        fill(e);
        final resumed = engineFor(wide, reg);
        expect(resumed.replay(e.state.history), isTrue);
        expect(resumed.state.status, GameStatus.trayFull);
        expect(resumed.revivesUsed, 2);
        expect(resumed.revivesLeft, 0);
        expect(resumed.canRevive, isFalse);
        expect(resumed.revive(), isNull);
      });

      test('a 1.0 save with more revives (unlimited then) still resumes, with none left', () {
        final history = [
          for (var i = 0; i < 3; i++) ...['a1', 'b1', 'c1', 'd1', GameEngine.reviveMarker],
          'a1',
        ];
        final e = engineFor(wide, reg);
        expect(e.replay(history), isTrue);
        expect(e.state.tray, ['a1']);
        expect(e.revivesUsed, 3);
        expect(e.revivesLeft, 0);
      });

      test('restart starts the count over', () {
        final e = engineFor(wide, reg);
        fill(e);
        e.revive();
        fill(e);
        e.revive();
        e.restart();
        expect(e.revivesUsed, 0);
        expect(e.revivesLeft, 2);
        fill(e);
        expect(e.revive(), isNotNull);
      });

      test('undo never gives a revive back', () {
        final e = engineFor(wide, reg);
        fill(e);
        e
          ..revive()
          ..tap('a1');
        expect(e.undo(), isNotNull);
        expect(e.revivesUsed, 1);
        expect(e.revivesLeft, 1);
        expect(e.undoAvailable, isFalse, reason: 'undo never crosses a revive');
      });
    });
  });

  group('special matching groups', () {
    // Plus a separate pair, so the board is not empty after z and n.
    final flowers = [('z', 'ZINNIA', 0.0, 0.0, 0), ('n', 'ANEMONE', 4.0, 0.0, 0), ('x1', 'A', 8.0, 0.0, 0), ('x2', 'A', 12.0, 0.0, 0)];

    test('different symbols do not match by default', () {
      final e = engineFor(level(flowers), reg);
      e.tap('z');
      expect(e.tap('n').outcome, TapOutcome.toTray);
      expect(e.state.tray, ['z', 'n']);
    });

    test('an explicit level group makes them match', () {
      final rules = LevelRules(matchGroups: const {'FLOWERS': ['ZINNIA', 'ANEMONE']});
      final e = engineFor(level(flowers, rules: rules), reg);
      e.tap('z');
      expect(e.tap('n').outcome, TapOutcome.matched);
      expect(e.state.tray, isEmpty);
    });

    test('registry match groups apply only in match_group mode', () {
      final grouped = registry(['ZINNIA', 'ANEMONE'], matchGroups: {'ZINNIA': 'FLOWER', 'ANEMONE': 'FLOWER'});
      final same = engineFor(level(flowers), grouped);
      same.tap('z');
      expect(same.tap('n').outcome, TapOutcome.toTray);
      final byGroup = engineFor(level(flowers, rules: const LevelRules(matchingMode: MatchingMode.matchGroup)), grouped);
      byGroup.tap('z');
      expect(byGroup.tap('n').outcome, TapOutcome.matched);
    });
  });

  group('per-level tray capacity', () {
    // Six separate pairs, all free: A B C D E F A B C D E F.
    final six = level(
      [
        for (final (i, code) in ['A', 'B', 'C', 'D', 'E', 'F', 'A', 'B', 'C', 'D', 'E', 'F'].indexed)
          ('${code.toLowerCase()}${i < 6 ? 1 : 2}', code, i * 4.0, 0.0, 0),
      ],
      rules: const LevelRules(trayCapacity: 5),
    );
    final reg6 = registry(['A', 'B', 'C', 'D', 'E', 'F']);

    test('rules.trayCapacity: parsed, 4 when absent, written only when not 4', () {
      final rules = LevelRules.fromJson(JsonReader({'matchingMode': 'same_symbol', 'trayCapacity': 5}));
      expect(rules.trayCapacity, 5);
      expect(rules.toJson()['trayCapacity'], 5);
      final plain = LevelRules.fromJson(JsonReader({'matchingMode': 'same_symbol'}));
      expect(plain.trayCapacity, kDefaultTrayCapacity);
      expect(plain.trayCapacity, 4);
      expect(plain.toJson().containsKey('trayCapacity'), isFalse, reason: 'older files stay byte-identical');
      expect(() => LevelRules.fromJson(JsonReader({'trayCapacity': 'five'})), throwsA(isA<JsonFormatException>()));
    });

    test('a level with a 5-slot tray round-trips through JSON', () {
      final parsed = LevelDefinition.fromJson(jsonDecode(jsonEncode(six.toJson())));
      expect(parsed.rules.trayCapacity, 5);
      expect(engineFor(parsed, reg6).state.trayCapacity, 5);
    });

    test('the validator accepts 2 to 5 slots only', () {
      for (final capacity in [2, 3, 4, 5]) {
        final ok = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0)], rules: LevelRules(trayCapacity: capacity));
        expect(LevelValidator(registry: reg6).validate(ok).isValid, isTrue, reason: '$capacity');
      }
      for (final capacity in [1, 6, 7]) {
        final bad = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0)], rules: LevelRules(trayCapacity: capacity));
        expect(LevelValidator(registry: reg6).validate(bad).hasError('invalid_tray_capacity'), isTrue, reason: '$capacity');
      }
    });

    test('the engine takes the capacity from the level', () {
      expect(engineFor(six, reg6).trayCapacity, 5);
      expect(GameEngine(level: six, rules: MatchRules(level: six, registry: reg6), trayCapacity: 4).trayCapacity, 4);
    });

    test('five unmatched tiles fill a 5-slot tray and lose; four do not', () {
      final e = engineFor(six, reg6);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        expect(e.tap(id).outcome, TapOutcome.toTray);
      }
      expect(e.state.status, GameStatus.playing, reason: 'four tiles fit a 5-slot tray');
      final fifth = e.tap('e1');
      expect(fifth.outcome, TapOutcome.trayFull);
      expect(fifth.slot, 4);
      expect(e.state.isTrayFull, isTrue);
      expect(e.state.status, GameStatus.trayFull);
      expect(e.tap('f1').outcome, TapOutcome.ignored);
    });

    test('a match on the fifth tap clears instead of losing', () {
      final e = engineFor(six, reg6);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      final match = e.tap('c2');
      expect(match.outcome, TapOutcome.matched);
      expect(match.slot, 4, reason: 'lands in the fifth slot before the pair clears');
      expect(match.partnerSlot, 2);
      expect(e.state.tray, ['a1', 'b1', 'd1']);
      expect(e.state.status, GameStatus.playing);
    });

    test('revive returns all five tray tiles to the board', () {
      final e = engineFor(six, reg6);
      for (final id in ['a1', 'b1', 'c1', 'd1', 'e1']) {
        e.tap(id);
      }
      expect(e.revive(), ['a1', 'b1', 'c1', 'd1', 'e1']);
      expect(e.state.tray, isEmpty);
      expect(e.state.status, GameStatus.playing);
      expect(e.state.remaining, hasLength(12));
      expect(e.state.history.last, GameEngine.reviveMarker);
    });

    test('saves replay with five slots, including a revive', () {
      final e = engineFor(six, reg6);
      for (final id in ['a1', 'b1', 'c1', 'd1', 'e1']) {
        e.tap(id);
      }
      e
        ..revive()
        ..tap('a1')
        ..tap('a2');
      final replayed = engineFor(six, reg6);
      expect(replayed.replay(e.state.history), isTrue);
      expect(replayed.state.matchedPairs, 1);
      expect(replayed.state.tray, isEmpty);
      // The same taps on a 4-slot tray lose on the fourth tile: the replay stops there.
      final four = GameEngine(level: six, rules: MatchRules(level: six, registry: reg6), trayCapacity: 4);
      expect(four.replay(e.state.history), isFalse);
    });
  });
}

import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/state/hint_finder.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/game_engine/validation/tray_solver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'hard_levels.dart';

void main() {
  final reg = registry(['A', 'B', 'C', 'D', 'E', 'X', 'Y']);
  // A B C D A B C D, far apart: all free.
  final wide = level([
    for (final (i, code) in ['A', 'B', 'C', 'D', 'A', 'B', 'C', 'D'].indexed)
      ('${code.toLowerCase()}${i < 4 ? 1 : 2}', code, i * 4.0, 0.0, 0),
  ]);
  // a1 a2 b1 b2 side by side: only the ends start free.
  final row = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 2, 0, 0), ('b1', 'B', 4, 0, 0), ('b2', 'B', 6, 0, 0)]);

  GameEngine engine(LevelDefinition on, {int? tray, SymbolRegistry? symbols}) =>
      GameEngine(level: on, rules: MatchRules(level: on, registry: symbols ?? reg), trayCapacity: tray);

  /// Everything a save must bring back.
  List<Object> snapshot(GameEngine e) => [
    e.state.remaining.toList()..sort(),
    e.state.free.toList()..sort(),
    e.state.tray,
    e.state.moveCount,
    e.state.matchedPairs,
    e.state.status,
    e.state.actions,
    e.state.undoAvailable,
    e.state.history,
    [for (var i = 0; i < e.level.tiles.length; i++) e.symbolCodeOf(i)],
  ];

  /// The game can still be won from here (the tray solver, exact).
  SolveOutcome solvability(GameEngine e, {int maxNodes = 200000}) => TraySolver.forRules(
    e.geometry,
    e.rules,
    capacity: e.trayCapacity,
    maxNodes: maxNodes,
  ).solve(e.remainingMask, tray: [for (final id in e.state.tray) e.indexOf(id)!]).outcome;

  Map<String, int> boardSymbolCounts(GameEngine e) {
    final counts = <String, int>{};
    for (var i = 0; i < e.level.tiles.length; i++) {
      if (e.isRemaining(i)) counts.update(e.symbolCodeOf(i), (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  group('uses', () {
    test('a level starts with 3 undos, 3 hints and 1 shuffle, none used', () {
      expect(kStartingCharges, {GameAction.undo: 3, GameAction.hint: 3, GameAction.shuffle: 1});
      final e = engine(wide);
      expect(e.state.actions, ActionCounts.initial);
      expect((e.usesLeft(GameAction.undo), e.usesLeft(GameAction.hint), e.usesLeft(GameAction.shuffle)), (3, 3, 1));
      expect(e.state.actions.used(GameAction.undo), 0);
    });

    test('grant adds one use and is saved as a marker; refused once won', () {
      final e = engine(wide);
      expect(e.grant(GameAction.shuffle), isTrue);
      expect(e.grant(GameAction.undo), isTrue);
      expect(e.state.actions.shufflesLeft, 2);
      expect(e.state.actions.undosLeft, 4);
      expect(e.state.history, ['!grant:shuffle', '!grant:undo']);
      final won = engine(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0)]))
        ..tap('a1')
        ..tap('a2');
      expect(won.state.status, GameStatus.won);
      expect(won.grant(GameAction.hint), isFalse);
      expect(won.state.actions.hintsLeft, 3);
    });

    test('restart gives the uses back; revive does not change them', () {
      final e = engine(wide)
        ..tap('a1')
        ..undo()
        ..useHint()
        ..grant(GameAction.hint);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      expect(e.state.status, GameStatus.trayFull);
      final before = e.state.actions;
      e.revive();
      expect(e.state.actions, before);
      e.restart();
      expect(e.state.actions, ActionCounts.initial);
    });
  });

  group('undo', () {
    test('a plain tap: the tile is back in its board place and the tray as it was', () {
      final e = engine(wide)
        ..tap('a1')
        ..tap('b1');
      final result = e.undo()!;
      expect((result.tileId, result.fromSlot, result.partnerTileId, result.undidMatch), ('b1', 1, null, false));
      expect(e.state.tray, ['a1']);
      expect(e.state.remaining, contains('b1'));
      expect(e.state.free, contains('b1'));
      expect(e.state.moveCount, 1);
      expect(e.state.history, ['a1', 'b1', GameEngine.undoMarker]);
      expect(e.state.actions.undosLeft, 2);
      expect(e.state.actions.undosUsed, 1);
      expect(e.tap('b1').slot, 1, reason: 'it plays again');
    });

    test('a returned tile blocks its neighbours again', () {
      final e = engine(row)..tap('a1');
      expect(e.state.free, {'a2', 'b2'});
      e.undo();
      expect(e.state.free, {'a1', 'b2'});
      expect(e.tap('a2').outcome, TapOutcome.blocked);
    });

    test('a match: both tiles come back, the twin in its tray slot, the tray in its order', () {
      final e = engine(wide)
        ..tap('a1')
        ..tap('b1')
        ..tap('c1');
      expect(e.tap('a2').outcome, TapOutcome.matched);
      expect(e.state.tray, ['b1', 'c1']);
      final result = e.undo()!;
      expect(result.undidMatch, isTrue);
      expect((result.tileId, result.fromSlot, result.partnerTileId, result.partnerSlot), ('a2', 3, 'a1', 0));
      expect(e.state.tray, ['a1', 'b1', 'c1']);
      expect(e.state.remaining, contains('a2'));
      expect(e.state.matchedPairs, 0);
      expect(e.state.moveCount, 3);
      expect(e.tap('a2').outcome, TapOutcome.matched, reason: 'the pair can be made again');
    });

    test('undos chain back to the start, then there is nothing to undo', () {
      final e = engine(wide);
      expect(e.undoAvailable, isFalse, reason: 'before any tap');
      expect(e.undo(), isNull);
      e
        ..tap('a1')
        ..tap('a2')
        ..tap('b1');
      expect(e.undo()!.tileId, 'b1');
      expect(e.undo()!.tileId, 'a2');
      expect(e.undo()!.tileId, 'a1');
      expect(e.state.remaining, hasLength(8));
      expect(e.state.tray, isEmpty);
      expect(e.undoAvailable, isFalse);
    });

    test('needs a use: none left, none taken; a granted one works', () {
      final e = engine(wide);
      for (var i = 0; i < 3; i++) {
        e
          ..tap('a1')
          ..undo();
      }
      e.tap('a1');
      expect(e.undoAvailable, isTrue);
      expect(e.state.actions.undosLeft, 0);
      expect(e.undo(), isNull);
      expect(e.state.tray, ['a1']);
      e.grant(GameAction.undo);
      expect(e.undo()!.tileId, 'a1');
      expect(e.state.actions.undosUsed, 4);
    });

    test('not after a win or with a full tray', () {
      final won = engine(level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0)]))
        ..tap('a1')
        ..tap('a2');
      expect(won.state.status, GameStatus.won);
      expect(won.undoAvailable, isFalse);
      expect(won.undo(), isNull);
      final full = engine(wide);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        full.tap(id);
      }
      expect(full.state.status, GameStatus.trayFull);
      expect(full.undoAvailable, isFalse);
      expect(full.undo(), isNull);
      expect(full.state.actions.undosLeft, 3);
    });

    test('never crosses a revive', () {
      final e = engine(wide);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        e.tap(id);
      }
      e.revive();
      expect(e.undoAvailable, isFalse);
      expect(e.undo(), isNull);
      e.tap('a1');
      expect(e.undo()!.tileId, 'a1');
      expect(e.undoAvailable, isFalse, reason: 'the taps before the revive stay');
      expect(e.state.status, GameStatus.playing);
    });

    test('never crosses a shuffle', () {
      final e = engine(wide)..tap('a1');
      expect(e.shuffle().shuffled, isTrue);
      expect(e.undoAvailable, isFalse);
      expect(e.undo(), isNull);
      final next = e.state.free.first;
      e.tap(next);
      expect(e.undo()!.tileId, next);
      expect(e.undoAvailable, isFalse);
    });

    test('tells whether it would take back a match', () {
      final e = engine(wide);
      expect(e.undoWouldUnmatch, isNull);
      e.tap('a1');
      expect(e.undoWouldUnmatch, isFalse);
      e.tap('a2');
      expect(e.undoWouldUnmatch, isTrue);
    });
  });

  group('hint', () {
    test('first a free tile whose twin waits in the tray', () {
      final e = engine(wide)
        ..tap('a1')
        ..tap('b1');
      expect(e.findHint(), const Hint(tileId: 'a2', reason: HintReason.completesPair, partnerTileId: 'a1'));
    });

    test('a tray twin with more of its symbol on the board is left to the solver', () {
      // x1 waits in a 2-slot tray. x3 matches it, but then the y1 under x2
      // and the x4 under y2 lock each other; x2 frees y1 and wins.
      final choice = level([
        ('x1', 'X', 0, 0, 0),
        ('x3', 'X', 4, 0, 0),
        ('y1', 'Y', 8, 0, 0),
        ('x2', 'X', 8, 0, 1),
        ('x4', 'X', 12, 0, 0),
        ('y2', 'Y', 12, 0, 1),
      ]);
      final e = engine(choice, tray: 2)..tap('x1');
      final hint = e.findHint()!;
      expect(hint, const Hint(tileId: 'x2', reason: HintReason.solver, partnerTileId: 'x1'));
      final wrong = engine(choice, tray: 2)
        ..tap('x1')
        ..tap('x3');
      expect(solvability(wrong), SolveOutcome.unsolvable);
      e.tap(hint.tileId);
      expect(solvability(e), SolveOutcome.solvable);
    });

    test('the last tile of its symbol first, then the oldest tray tile', () {
      // Four As: a1 waits in the tray with three As left; b1 waits with one B left.
      final many = level([
        ('a1', 'A', 0, 0, 0),
        ('a2', 'A', 4, 0, 0),
        ('a3', 'A', 8, 0, 0),
        ('a4', 'A', 12, 0, 0),
        ('b1', 'B', 16, 0, 0),
        ('b2', 'B', 20, 0, 0),
      ]);
      final e = engine(many)
        ..tap('a1')
        ..tap('b1');
      expect(e.findHint()!.tileId, 'b2');
      final f = engine(wide)
        ..tap('b1')
        ..tap('a1');
      expect(f.findHint()!.partnerTileId, 'b1', reason: 'b1 has waited longest');
    });

    test('then a safe pair: a symbol whose board tiles are all free, two-tile symbols first', () {
      final e = engine(wide);
      expect(e.findHint(), const Hint(tileId: 'a1', reason: HintReason.safePair, partnerTileId: 'a2'));
      final fours = level([
        ('a1', 'A', 0, 0, 0),
        ('a2', 'A', 4, 0, 0),
        ('a3', 'A', 8, 0, 0),
        ('a4', 'A', 12, 0, 0),
        ('b1', 'B', 16, 0, 0),
        ('b2', 'B', 20, 0, 0),
      ]);
      expect(engine(fours).findHint()!.tileId, 'b1');
    });

    test('a safe pair only with room for its first tile', () {
      // x1 waits in a 2-slot tray; its twin is buried: no tap is safe.
      final stuck = level([
        ('x1', 'X', 0, 0, 0),
        ('a1', 'A', 4, 0, 0),
        ('a2', 'A', 8, 0, 0),
        ('x2', 'X', 12, 0, 0),
        ('y1', 'Y', 12, 0, 1),
        ('y2', 'Y', 16, 0, 0),
      ]);
      final e = engine(stuck, tray: 2)..tap('x1');
      expect(e.state.status, GameStatus.playing);
      expect(e.findHint(), isNull, reason: 'every tap fills the tray');
      expect(e.useHint(), isNull);
      expect(e.state.actions.hintsLeft, 3, reason: 'no hint, no use spent');
    });

    test('on a board with no tray match and no safe pair, the solver picks a winning tap', () {
      // a3 lies under b1 and b2 under a4; with a 2-slot tray, pairing a1 and
      // a2 first loses. No symbol has all its tiles free.
      final trap = level([
        ('a1', 'A', 0, 0, 0),
        ('a2', 'A', 10, 0, 0),
        ('a3', 'A', 20, 0, 0),
        ('b1', 'B', 20, 0, 1),
        ('b2', 'B', 30, 0, 0),
        ('a4', 'A', 30, 0, 1),
      ]);
      final e = engine(trap, tray: 2);
      expect(HintFinder.safePairs(e), isEmpty);
      final hint = e.findHint()!;
      expect(hint.reason, HintReason.solver);
      // Following hints wins.
      var steps = 0;
      while (e.state.status == GameStatus.playing && steps++ < 20) {
        e.tap(e.findHint()!.tileId);
      }
      expect(e.state.status, GameStatus.won);
      // The greedy pair loses.
      final greedy = engine(trap, tray: 2)
        ..tap('a1')
        ..tap('a2');
      expect(solvability(greedy), SolveOutcome.unsolvable);
    });

    test('after a shuffle, a search out of budget falls back on the order the shuffle was built along', () {
      final trap = level([
        ('a1', 'A', 0, 0, 0),
        ('a2', 'A', 10, 0, 0),
        ('a3', 'A', 20, 0, 0),
        ('b1', 'B', 20, 0, 1),
        ('b2', 'B', 30, 0, 0),
        ('a4', 'A', 30, 0, 1),
      ]);
      var checked = 0;
      for (var seed = 0; seed < 40; seed++) {
        final e = engine(trap, tray: 2)..shuffle(seed: seed);
        final proof = e.shuffleProof;
        expect(TraySolver.forRules(e.geometry, e.rules, capacity: 2).check(e.remainingMask, proof), isTrue);
        if (HintFinder.safePairs(e).isNotEmpty) continue;
        checked++;
        expect(e.findHint(maxNodes: 1), Hint(tileId: e.level.tiles[proof.first].tileId, reason: HintReason.solver,
            partnerTileId: e.level.tiles[proof[1]].tileId));
      }
      expect(checked, greaterThan(0));
    });

    test('is pure: finding one changes nothing; using one spends a use and is counted', () {
      final e = engine(wide)..tap('a1');
      final before = snapshot(e);
      expect(e.findHint(), isNotNull);
      expect(e.findHint(), e.findHint());
      expect(snapshot(e), before);
      final hint = e.useHint()!;
      expect(hint.tileId, 'a2');
      expect(e.state.tray, ['a1'], reason: 'nothing is applied');
      expect(e.state.actions.hintsLeft, 2);
      expect(e.state.actions.hintsUsed, 1);
      expect(e.state.history.last, GameEngine.hintMarker);
      expect(e.state.undoAvailable, isTrue, reason: 'a hint is not a barrier for undo');
    });

    test('needs a use and a game in play', () {
      final e = engine(wide);
      for (var i = 0; i < 3; i++) {
        expect(e.useHint(), isNotNull);
      }
      expect(e.useHint(), isNull);
      e.grant(GameAction.hint);
      expect(e.useHint(), isNotNull);
      final full = engine(wide);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        full.tap(id);
      }
      expect(full.findHint(), isNull);
    });

    test('respects the tray: with one slot left, only a matching tile', () {
      final e = engine(wide, tray: 3)
        ..tap('a1')
        ..tap('b1');
      expect(e.findHint()!.reason, HintReason.completesPair);
    });

    test('following hints wins the hardest boards (2-slot trays, 144+ tiles)', () {
      for (final hard in hardLevels()) {
        expect(hard.rules.trayCapacity, 2);
        expect(hard.tiles.length, greaterThanOrEqualTo(144));
        final e = engine(hard, symbols: hardRegistry);
        final reasons = <HintReason>{};
        var steps = 0;
        while (e.state.status == GameStatus.playing && steps++ < hard.tiles.length) {
          final hint = e.findHint()!;
          reasons.add(hint.reason);
          e.tap(hint.tileId);
        }
        expect(e.state.status, GameStatus.won, reason: hard.levelId);
        expect(reasons, isNot(contains(HintReason.fallback)), reason: hard.levelId);
      }
    });
  });

  group('shuffle', () {
    test('moves symbols between board tiles only: places, ids, counts and the tray stay', () {
      final e = engine(wide)
        ..tap('a1')
        ..tap('b1')
        ..tap('a2');
      final counts = boardSymbolCounts(e);
      final traySymbols = [for (final id in e.state.tray) e.symbolCodeOf(e.indexOf(id)!)];
      final result = e.shuffle(seed: 7);
      expect(result.outcome, ShuffleOutcome.shuffled);
      expect(result.changes, isNotEmpty);
      for (final MapEntry(key: id, value: (from, to)) in result.changes.entries) {
        expect(e.state.remaining, contains(id));
        expect(e.symbolCodeOf(e.indexOf(id)!), to);
        expect(from, isNot(to));
      }
      expect(boardSymbolCounts(e), counts);
      expect(e.state.tray, ['b1']);
      expect([for (final id in e.state.tray) e.symbolCodeOf(e.indexOf(id)!)], traySymbols);
      expect(e.symbolCodeOf(e.indexOf('a1')!), 'A', reason: 'cleared tiles keep theirs');
      final board = e.boardLevel;
      for (final (i, tile) in board.tiles.indexed) {
        final dealt = e.level.tiles[i];
        expect((tile.tileId, tile.x, tile.y, tile.layer), (dealt.tileId, dealt.x, dealt.y, dealt.layer));
        expect(tile.symbolCode, e.symbolCodeOf(i));
      }
      expect(e.state.actions.shufflesLeft, 0);
      expect(e.state.actions.shufflesUsed, 1);
      expect(e.state.history.last, GameEngine.shuffleMarker(result.seed!));
      expect(e.state.moveCount, 3, reason: 'not a move');
      expect(e.state.matchedPairs, 1);
    });

    test('matching follows the new symbols', () {
      final e = engine(wide)..shuffle(seed: 3);
      final b = e.state.remaining.firstWhere((id) => e.symbolCodeOf(e.indexOf(id)!) == 'B');
      final twin = e.state.remaining.firstWhere((id) => id != b && e.symbolCodeOf(e.indexOf(id)!) == 'B');
      e.tap(b);
      expect(e.tap(twin).outcome, TapOutcome.matched);
    });

    test('is deterministic per seed', () {
      List<String> symbolsAfter(int seed) {
        final e = engine(wide)
          ..tap('a1')
          ..shuffle(seed: seed);
        return [for (var i = 0; i < 8; i++) e.symbolCodeOf(i)];
      }

      expect(symbolsAfter(1), symbolsAfter(1));
      expect(symbolsAfter(2), symbolsAfter(2));
      expect({for (var seed = 0; seed < 8; seed++) symbolsAfter(seed).join()}.length, greaterThan(1));
    });

    test('a stuck tray: the twin of the waiting tile is free afterwards and the game can be won', () {
      // x1 waits in a 2-slot tray; its twin x2 is under y1: every tap loses.
      final stuck = level([
        ('x1', 'X', 0, 0, 0),
        ('a1', 'A', 4, 0, 0),
        ('a2', 'A', 8, 0, 0),
        ('x2', 'X', 12, 0, 0),
        ('y1', 'Y', 12, 0, 1),
        ('y2', 'Y', 16, 0, 0),
      ]);
      final e = engine(stuck, tray: 2)..tap('x1');
      expect(solvability(e), SolveOutcome.unsolvable);
      expect(e.shuffle().shuffled, isTrue);
      expect(solvability(e), SolveOutcome.solvable);
      expect(e.findHint()!.reason, HintReason.completesPair);
    });

    test('leaves the hardest boards solvable, from the start and mid-game, tray included', () {
      for (final hard in hardLevels()) {
        final start = engine(hard, symbols: hardRegistry);
        expect(start.shuffle().shuffled, isTrue);
        expect(solvability(start), SolveOutcome.solvable, reason: '${hard.levelId} start');
        // Mid-game, one tile waiting in the tray.
        final mid = engine(hard, symbols: hardRegistry);
        final plan = TraySolver.forRules(mid.geometry, mid.rules, capacity: 2).solve(TileMask.all(hard.tiles.length));
        for (final index in plan.taps.take(plan.taps.length ~/ 2 + 1)) {
          mid.tap(hard.tiles[index].tileId);
        }
        expect(mid.state.tray, hasLength(1));
        final tray = List.of(mid.state.tray);
        final result = mid.shuffle();
        expect(result.shuffled, isTrue);
        expect(mid.state.tray, tray);
        expect(solvability(mid), SolveOutcome.solvable, reason: '${hard.levelId} mid-game');
      }
    });

    test('nothing to shuffle with one symbol on the board; no use spent', () {
      final e = engine(wide);
      for (final id in ['a1', 'a2', 'b1', 'b2', 'c1', 'c2']) {
        e.tap(id);
      }
      expect(e.canShuffleBoard, isFalse);
      expect(e.shuffle().outcome, ShuffleOutcome.nothingToShuffle);
      expect(e.state.actions.shufflesLeft, 1);
    });

    test('when no arrangement passes, the board stays and the use is kept', () {
      final e = engine(wide)..tap('a1');
      final before = snapshot(e);
      final result = e.shuffle(attempts: 0);
      expect(result.outcome, ShuffleOutcome.failed);
      expect(snapshot(e), before);
      expect(e.state.actions.shufflesLeft, 1);
    });

    test('needs a use and a game in play', () {
      final e = engine(wide)..shuffle();
      expect(e.shuffle().outcome, ShuffleOutcome.noCharges);
      e.grant(GameAction.shuffle);
      expect(e.shuffle().shuffled, isTrue);
      final full = engine(wide);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        full.tap(id);
      }
      expect(full.shuffle().outcome, ShuffleOutcome.unavailable);
    });

    test('restart deals the level again', () {
      final e = engine(wide)..shuffle(seed: 5);
      expect(e.boardLevel, isNot(same(e.level)));
      e.restart();
      expect(e.boardLevel, same(e.level));
      expect([for (var i = 0; i < 8; i++) e.symbolCodeOf(i)], [for (final t in wide.tiles) t.symbolCode]);
      expect(e.rules, same(e.levelRules));
    });
  });

  group('saves', () {
    test('replaying the history restores board, tray, symbols, uses and counters', () {
      final e = engine(wide, tray: 3);
      e
        ..tap('a1')
        ..tap('b1')
        ..useHint()
        ..undo()
        ..grant(GameAction.undo)
        ..tap('a2');
      expect(e.shuffle(seed: 11).shuffled, isTrue);
      final free = e.state.free.toList()..sort();
      e
        ..tap(free.first)
        ..undo()
        ..tap(free.last);
      // Fill the tray, revive, and play on.
      while (e.state.status == GameStatus.playing) {
        final tray = e.state.tray;
        final next = (e.state.free.toList()..sort()).firstWhere(
          (id) => !tray.any((t) => e.rules.matches(e.indexOf(t)!, e.indexOf(id)!)),
          orElse: () => e.state.free.first,
        );
        e.tap(next);
      }
      if (e.state.status == GameStatus.trayFull) e.revive();
      e.useHint();
      final replayed = engine(wide, tray: 3);
      expect(replayed.replay(e.state.history), isTrue);
      expect(snapshot(replayed), snapshot(e));
      expect(e.state.history, containsAll([GameEngine.undoMarker, GameEngine.hintMarker, '!grant:undo']));
      expect(e.state.history.where((h) => h.startsWith(GameEngine.shuffleMarkerPrefix)), hasLength(1));
    });

    test('a 1.0 save (taps and revives only) replays with fresh uses', () {
      final e = engine(wide);
      expect(e.replay(['a1', 'b1', 'c1', 'd1', GameEngine.reviveMarker, 'a1']), isTrue);
      expect(e.state.tray, ['a1']);
      expect(e.state.actions, ActionCounts.initial);
      expect(e.undoAvailable, isTrue);
    });

    test('a shuffle replays from its seed without a search, on the hardest boards too', () {
      final hard = hardLevels().first;
      final e = engine(hard, symbols: hardRegistry)..tap(hard.tiles[e0FreeTile(hard)].tileId);
      e.shuffle();
      final replayed = engine(hard, symbols: hardRegistry);
      final watch = Stopwatch()..start();
      expect(replayed.replay(e.state.history), isTrue);
      expect(watch.elapsedMilliseconds, lessThan(500));
      expect(snapshot(replayed), snapshot(e));
    });

    test('illegal or unknown markers stop the replay', () {
      expect(engine(wide).replay([GameEngine.undoMarker]), isFalse, reason: 'nothing to undo');
      expect(engine(wide).replay(['!shuffle:9:1']), isFalse, reason: 'unknown planner version');
      expect(engine(wide).replay(['!shuffle:1:x']), isFalse);
      expect(engine(wide).replay(['!grant:teleport']), isFalse);
      expect(engine(wide).replay(['!future']), isFalse);
      expect(engine(wide).replay(['!shuffle:1:5', '!shuffle:1:6']), isFalse, reason: 'one shuffle per level');
      expect(engine(wide).replay(['!hint', '!hint', '!hint', '!hint']), isFalse, reason: 'three hints');
      expect(engine(wide).replay(['!grant:hint', '!hint', '!hint', '!hint', '!hint']), isTrue);
    });
  });
}

/// A tile free at the start of [level].
int e0FreeTile(LevelDefinition level) {
  final e = GameEngine(level: level, rules: MatchRules(level: level, registry: hardRegistry));
  return e.indexOf(e.state.free.first)!;
}

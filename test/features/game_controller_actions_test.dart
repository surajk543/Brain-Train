import 'package:brain_train/app/sound_effects.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../helpers/fake_stopwatch.dart';

Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

class _RecordingSounds extends SoundEffects {
  _RecordingSounds(super.settings);

  final List<Sfx> played = [];

  @override
  void play(Sfx sfx) => played.add(sfx);
}

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
  late _RecordingSounds sounds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    progress = await ProgressRepository.open();
    settings = await SettingsRepository.open();
    clock = FakeStopwatch();
    sounds = _RecordingSounds(settings);
  });

  GameController controllerFor({
    SavedGame? resume,
    bool onImpact = false,
    bool playIntro = false,
    Duration delay = Duration.zero,
    LevelDefinition? on,
  }) => GameController(
    entry: entry,
    level: on ?? board,
    registry: reg,
    progress: progress,
    settings: settings,
    sounds: sounds,
    resume: resume,
    stopwatch: clock,
    matchFeedbackOnImpact: onImpact,
    arrivalFeedbackDelay: delay,
    playIntro: playIntro,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// [c] with [extra] (at most [kMaxGrantsPerAction]) more uses of [action]
  /// than the one a level starts with, granted the way a rewarded ad does
  /// ([GameController.grant]).
  GameController withGranted(GameController c, GameAction action, int extra) {
    for (var i = 0; i < extra; i++) {
      expect(c.grant(action), isTrue);
    }
    return c;
  }

  /// Collects board and score events until [stop].
  (List<BoardEvent>, List<ScoreEvent>, Future<void> Function()) listen(GameController c) {
    final board = <BoardEvent>[], score = <ScoreEvent>[];
    final a = c.events.listen(board.add), b = c.scoreEvents.listen(score.add);
    return (board, score, () async {
      await a.cancel();
      await b.cancel();
    });
  }

  group('undo', () {
    test('a plain tap: the tile is back, the event says where from, the clock runs on, the game is saved', () async {
      final c = controllerFor();
      final (events, _, stop) = listen(c);
      c
        ..tapTile('a1')
        ..tapTile('b1');
      clock.advance(s(3));
      final elapsed = c.elapsed;
      final result = c.undo()!;
      await settle();
      expect(result.tileId, 'b1');
      final undone = events.whereType<MoveUndone>().single;
      expect((undone.tileId, undone.fromSlot, undone.partnerId, undone.undidMatch), ('b1', 1, null, false));
      expect(undone.tray, ['a1']);
      expect(undone.pointsTakenBack, 0);
      expect(c.elapsed, elapsed, reason: 'undo never rewinds the clock');
      expect(c.clockRunning, isTrue);
      expect(c.actions.undosLeft, 0);
      expect(c.actions.undosUsed, 1);
      expect(progress.savedGame()!.history, ['a1', 'b1', GameEngine.undoMarker]);
      expect(sounds.played.last, Sfx.undo);
      await stop();
      c.dispose();
    });

    test('a match: score, combo and best combo go back to before the tap; later penalties stay', () async {
      final c = withGranted(controllerFor(), GameAction.undo, 1);
      final (events, _, stop) = listen(c);
      c
        ..tapTile('a1')
        ..tapTile('a2'); // t=0: 100
      clock.advance(s(0.5));
      c
        ..tapTile('b1')
        ..tapTile('b2'); // t=0.5: x2 +50 = 250
      expect((c.score, c.activeCombo, c.scoring.bestCombo), (350, 2, 2));
      c.undo();
      await settle();
      expect((c.score, c.activeCombo, c.scoring.bestCombo, c.scoring.totalPairsMatched), (100, 1, 1, 1));
      expect(c.state.tray, ['b1']);
      expect(c.state.matchedPairs, 1);
      final undone = events.whereType<MoveUndone>().single;
      expect((undone.tileId, undone.partnerId, undone.partnerSlot, undone.pointsTakenBack), ('b2', 'b1', 0, 250));
      // The pair again, 1 s later: the combo continues from the first match.
      clock.advance(s(1));
      c.tapTile('b2');
      expect(c.score, 100 + 225);
      // A blocked tap after a match is not taken back with it.
      c.tapTile('x1');
      expect(c.score, 324);
      c.undo();
      expect((c.score, c.activeCombo), (99, 0));
      await stop();
      c.dispose();
    });

    test('availability: not before a tap, in the intro, in the tutorial, with a full tray, after a revive or a shuffle',
        () async {
      final intro = controllerFor(playIntro: true);
      expect(intro.isAvailable(GameAction.undo), isFalse);
      intro.endIntro();
      expect(intro.isAvailable(GameAction.undo), isFalse, reason: 'no tap yet');
      intro.tapTile('a1');
      expect(intro.isAvailable(GameAction.undo), isTrue);
      intro.beginTutorial();
      expect(intro.isAvailable(GameAction.undo), isFalse);
      expect(intro.undo(), isNull);
      intro
        ..endTutorial()
        ..tapTile('b1')
        ..tapTile('c1')
        ..tapTile('d1');
      expect(intro.state.status, GameStatus.trayFull);
      expect(intro.isAvailable(GameAction.undo), isFalse);
      intro.revive();
      expect(intro.isAvailable(GameAction.undo), isFalse, reason: 'never across a revive');
      intro.tapTile('a1');
      expect(intro.canUse(GameAction.undo), isTrue);
      expect(intro.shuffle().shuffled, isTrue);
      expect(intro.isAvailable(GameAction.undo), isFalse, reason: 'never across a shuffle');
      intro.dispose();
    });

    test('no use left: available but not usable; a granted use (after an ad) works and is saved', () async {
      final c = controllerFor();
      expect(c.usesLeft(GameAction.undo), 1);
      c
        ..tapTile('a1')
        ..undo();
      expect(c.actions.undosUsed, 1, reason: 'the free use');
      c.tapTile('a1');
      expect(c.isAvailable(GameAction.undo), isTrue);
      expect(c.usesLeft(GameAction.undo), 0);
      expect(c.canUse(GameAction.undo), isFalse);
      expect(c.undo(), isNull);
      expect(c.grant(GameAction.undo), isTrue);
      await settle();
      expect(progress.savedGame()!.history.last, '!grant:undo');
      expect(c.undo(), isNotNull);
      expect(c.actions.undosUsed, 2);
      expect(c.usesLeft(GameAction.undo), 0);
      c.tapTile('a1');
      expect(c.canUse(GameAction.undo), isFalse, reason: 'one ad, one use');
      expect(c.isSpent(GameAction.undo), isTrue, reason: 'one ad per level attempt');
      expect(c.grant(GameAction.undo), isFalse);
      await settle();
      expect(progress.savedGame()!.history.last, 'a1', reason: 'a refused grant is not saved');
      c.dispose();
    });

    test('a strike of an undone pair is ignored: no popup, no sound, no double score', () async {
      final c = controllerFor(onImpact: true);
      final (_, scores, stop) = listen(c);
      c
        ..tapTile('a1')
        ..tapTile('a2');
      sounds.played.clear();
      c.undo();
      c.pairImpact('a1', 'a2'); // the strike the screen was still playing
      await settle();
      expect(scores, isEmpty);
      expect(sounds.played, [Sfx.undo], reason: 'only the undo, no match sound');
      expect(c.score, 0);
      // Made again: one strike, one award.
      c.tapTile('a2');
      c.pairImpact('a2', 'a1');
      c.pairImpact('a1', 'a2'); // a second, stale report of the same strike
      await settle();
      expect(scores.whereType<ScoreAwarded>(), hasLength(1));
      expect(sounds.played.where((sfx) => sfx == Sfx.match), hasLength(1));
      expect(c.score, 100);
      await stop();
      c.dispose();
    });

    test('a strike from before a restart is ignored', () async {
      final c = controllerFor(onImpact: true);
      final (_, scores, stop) = listen(c);
      c
        ..tapTile('a1')
        ..tapTile('a2')
        ..restart();
      sounds.played.clear();
      c.pairImpact('a1', 'a2');
      await settle();
      expect(scores, isEmpty);
      expect(sounds.played, isEmpty);
      await stop();
      c.dispose();
    });

    test('feedback still on its way for an undone match is dropped', () async {
      final c = controllerFor(delay: const Duration(milliseconds: 20));
      c
        ..tapTile('a1')
        ..tapTile('a2');
      sounds.played.clear();
      c.undo();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        sounds.played,
        [Sfx.undo, Sfx.tray],
        reason: 'the undo swishes, a1 still lands in the tray; the match sound never plays',
      );
      c.dispose();
    });

    test('a game resumed from a 1.0 save: its plain taps can be undone, its earlier matches cannot', () async {
      final saved = SavedGame(
        levelId: 'test-level',
        levelUrl: entry.ref.url,
        history: const ['a1', 'a2', 'b1'],
        elapsedMs: 4000,
        scoring: const {'score': 100, 'combo': 0, 'bestCombo': 1, 'pairs': 1, 'lastMatchAtMs': null},
      );
      final c = controllerFor(resume: saved);
      expect(c.actions, ActionCounts.initial);
      withGranted(c, GameAction.undo, 1);
      expect(c.undo()!.tileId, 'b1');
      expect(c.isAvailable(GameAction.undo), isFalse, reason: 'no score checkpoint for the a1-a2 match');
      expect(c.score, 100);
      c.tapTile('b1');
      c.tapTile('b2');
      expect(c.undo()!.tileId, 'b2', reason: 'matches made since the resume can be taken back');
      expect(c.score, 100);
      c.dispose();
    });
  });

  group('hint', () {
    test('returns the tap, tells the board, spends a use and changes nothing else', () async {
      final c = controllerFor();
      final (events, scores, stop) = listen(c);
      c.tapTile('a1');
      final tray = c.state.tray, score = c.score;
      final hint = c.useHint()!;
      await settle();
      expect(hint, const Hint(tileId: 'a2', reason: HintReason.completesPair, partnerTileId: 'a1'));
      expect(events.whereType<TileHinted>().single.hint, hint);
      expect(c.state.tray, tray);
      expect(c.score, score);
      expect(scores, isEmpty);
      expect(c.actions.hintsLeft, 0);
      expect(c.actions.hintsUsed, 1);
      expect(progress.savedGame()!.history, ['a1', GameEngine.hintMarker]);
      await stop();
      c.dispose();
    });

    test('not during the intro or the tutorial, nor once the game is over; none left until granted', () async {
      final c = controllerFor(playIntro: true);
      expect(c.useHint(), isNull);
      c
        ..endIntro()
        ..beginTutorial();
      expect(c.isAvailable(GameAction.hint), isFalse);
      c.endTutorial();
      expect(c.useHint(), isNotNull, reason: 'the free use');
      expect(c.isAvailable(GameAction.hint), isTrue);
      expect(c.canUse(GameAction.hint), isFalse);
      expect(c.useHint(), isNull);
      withGranted(c, GameAction.hint, 1);
      expect(c.useHint(), isNotNull);
      expect(c.useHint(), isNull);
      expect(c.actions.hintsUsed, 2);
      expect(c.grant(GameAction.hint), isFalse, reason: 'two hints per level attempt');
      expect(c.useHint(), isNull);
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        c.tapTile(id);
      }
      expect(c.isAvailable(GameAction.hint), isFalse, reason: 'the tray is full');
      c.dispose();
    });

    test('with one slot left, a hint exists only when a free tile matches the tray', () async {
      final c = controllerFor();
      c
        ..tapTile('a1')
        ..tapTile('b1')
        ..tapTile('c1');
      expect(c.isAvailable(GameAction.hint), isTrue);
      expect(c.useHint()!.reason, HintReason.completesPair);
      c.dispose();
    });
  });

  group('sounds (premium pass)', () {
    test('a match sounds plain at x1 and brighter while a combo runs (x2 and up)', () async {
      final c = controllerFor();
      c
        ..tapTile('a1')
        ..tapTile('a2');
      expect(sounds.played.last, Sfx.match, reason: 'x1');
      clock.advance(s(1));
      c
        ..tapTile('b1')
        ..tapTile('b2');
      expect(sounds.played.last, Sfx.combo, reason: 'x2 within the window');
      clock.advance(s(10));
      c
        ..tapTile('c1')
        ..tapTile('c2');
      expect(sounds.played.last, Sfx.match, reason: 'the window closed: x1 again');
      c.dispose();
    });

    test('a tile that lands without a match pops; Hint rings, Undo swishes, Shuffle sweeps', () async {
      final c = controllerFor();
      sounds.played.clear();
      c.tapTile('a1');
      expect(sounds.played, [Sfx.tap, Sfx.tray]);
      expect(c.useHint(), isNotNull);
      expect(sounds.played.last, Sfx.hint);
      expect(c.undo(), isNotNull);
      expect(sounds.played.last, Sfx.undo);
      c
        ..tapTile('a1')
        ..tapTile('a2')
        ..tapTile('b1');
      expect(c.shuffle(seed: 4).shuffled, isTrue);
      expect(sounds.played.last, Sfx.shuffle);
      c.dispose();
    });
  });

  group('shuffle', () {
    test('rearranges the board, ends the combo, keeps the score, seals undo and tells the board', () async {
      final c = controllerFor();
      final (events, _, stop) = listen(c);
      c
        ..tapTile('a1')
        ..tapTile('a2')
        ..tapTile('b1');
      expect(c.activeCombo, 1);
      final serial = c.symbolsSerial;
      final result = c.shuffle(seed: 4);
      await settle();
      expect(result.shuffled, isTrue);
      expect(c.score, 100);
      expect(c.activeCombo, 0);
      expect(c.scoring.undoableMatches, 0);
      expect(c.isAvailable(GameAction.undo), isFalse);
      expect(c.symbolsSerial, isNot(serial));
      final shuffled = events.whereType<BoardShuffled>().single;
      expect(shuffled.changes, result.changes);
      expect(shuffled.seed, result.seed);
      for (final MapEntry(key: id, value: (_, to)) in shuffled.changes.entries) {
        expect(c.symbolCodeOf(id), to);
        expect(c.boardLevel.tiles.firstWhere((t) => t.tileId == id).symbolCode, to);
      }
      expect(c.state.tray, ['b1']);
      expect(c.symbolCodeOf('b1'), 'B');
      expect(progress.savedGame()!.history.last, GameEngine.shuffleMarker(result.seed!));
      expect(c.shuffle().outcome, ShuffleOutcome.noCharges);
      await stop();
      c.dispose();
    });

    test('not during the intro or the tutorial; restart deals the level again with all uses back', () async {
      final c = controllerFor(playIntro: true);
      expect(c.shuffle().outcome, ShuffleOutcome.unavailable);
      c
        ..endIntro()
        ..beginTutorial();
      expect(c.shuffle().outcome, ShuffleOutcome.unavailable);
      c.endTutorial();
      expect(c.shuffle().shuffled, isTrue);
      c.tapTile(c.state.free.first);
      c
        ..useHint()
        ..undo()
        ..grant(GameAction.hint);
      expect((c.usesLeft(GameAction.undo), c.usesLeft(GameAction.hint), c.usesLeft(GameAction.shuffle)), (0, 1, 0));
      final serial = c.symbolsSerial;
      c.restart();
      expect(c.symbolsSerial, isNot(serial));
      expect(c.boardLevel, same(c.level));
      expect(c.actions, ActionCounts.initial);
      expect((c.usesLeft(GameAction.undo), c.usesLeft(GameAction.hint), c.usesLeft(GameAction.shuffle)), (1, 1, 1));
      c.dispose();
    });
  });

  test('a save resumes with its uses, its shuffled board, its score and its undo checkpoints', () async {
    final c = controllerFor();
    c.tapTile('a1');
    clock.advance(s(1));
    c
      ..tapTile('a2')
      ..useHint()
      ..grant(GameAction.undo)
      ..tapTile('b1')
      ..undo();
    expect(c.shuffle(seed: 9).shuffled, isTrue);
    // Two free tiles that show the same symbol now.
    final bySymbol = <String, List<String>>{};
    for (final id in c.state.free.toList()..sort()) {
      (bySymbol[c.symbolCodeOf(id)] ??= []).add(id);
    }
    final [b, twin, ...] = bySymbol.values.firstWhere((ids) => ids.length >= 2);
    clock.advance(s(1));
    c
      ..tapTile(b)
      ..tapTile(twin);
    await settle();
    final resumed = controllerFor(resume: progress.savedGame());
    expect(resumed.state.history, c.state.history);
    expect(resumed.state.tray, c.state.tray);
    expect(resumed.state.remaining, c.state.remaining);
    expect(resumed.actions, c.actions);
    expect(resumed.actions, const ActionCounts(
      undosLeft: 1,
      hintsLeft: 0,
      shufflesLeft: 0,
      undosUsed: 1,
      hintsUsed: 1,
      shufflesUsed: 1,
      undosGranted: 1,
    ));
    expect([for (final action in GameAction.values) resumed.grantsLeft(action)], [0, 1, 1],
        reason: 'undo, hint, shuffle');
    List<String> symbols(GameController game) => [for (final t in game.boardLevel.tiles) t.symbolCode];
    expect(symbols(resumed), symbols(c));
    expect((resumed.score, resumed.scoring.bestCombo), (c.score, c.scoring.bestCombo));
    // The match made after the shuffle can still be taken back after resuming.
    expect(resumed.undo()!.tileId, twin);
    expect(resumed.score, 100);
    expect(resumed.state.tray, [b]);
    resumed.dispose();
    c.dispose();
  });

  test('the win summary counts the actions used', () async {
    final small = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0), ('b1', 'B', 8, 0, 0), ('b2', 'B', 12, 0, 0)]);
    final c = controllerFor(on: small);
    c
      ..tapTile('a1')
      ..undo()
      ..useHint()
      ..grant(GameAction.hint)
      ..useHint();
    expect(c.shuffle().shuffled, isTrue);
    while (c.state.status == GameStatus.playing) {
      c.tapTile(c.engine.findHint()!.tileId);
    }
    expect(c.state.status, GameStatus.won);
    await settle();
    await settle();
    final summary = c.winSummary!;
    expect((summary.undosUsed, summary.hintsUsed, summary.shufflesUsed), (1, 2, 1));
    expect((summary.score, summary.matchedPairs, summary.totalPairs, summary.moves), (c.score, 2, 2, 4));
    expect(summary.record, isNotNull);
    expect(summary.record!.bestScore, c.score);
    c.restart();
    expect(c.winSummary, isNull);
    c.dispose();
  });

  group('grant cap', () {
    test('1 free use + 1 granted, then spent; grantsLeft and isSpent follow', () async {
      final c = controllerFor();
      for (final action in GameAction.values) {
        expect((c.usesLeft(action), c.grantsLeft(action), c.isSpent(action)), (1, 1, false), reason: action.name);
      }
      expect(c.useHint(), isNotNull);
      expect((c.usesLeft(GameAction.hint), c.grantsLeft(GameAction.hint), c.isSpent(GameAction.hint)), (0, 1, false));
      expect(c.grant(GameAction.hint), isTrue);
      expect((c.usesLeft(GameAction.hint), c.grantsLeft(GameAction.hint), c.isSpent(GameAction.hint)), (1, 0, false));
      expect(c.useHint(), isNotNull);
      expect((c.usesLeft(GameAction.hint), c.grantsLeft(GameAction.hint), c.isSpent(GameAction.hint)), (0, 0, true));
      expect(c.isAvailable(GameAction.hint), isTrue, reason: 'a hint exists; the action is spent');
      expect(c.grant(GameAction.hint), isFalse);
      expect(c.useHint(), isNull);
      expect(c.isSpent(GameAction.undo) || c.isSpent(GameAction.shuffle), isFalse);
      c.dispose();
    });

    test('revive keeps the cap; restart gives the grant back', () async {
      final c = controllerFor();
      c
        ..useHint()
        ..grant(GameAction.hint)
        ..useHint();
      for (final id in ['a1', 'b1', 'c1', 'd1']) {
        c.tapTile(id);
      }
      expect(c.revive(), isTrue);
      expect(c.isSpent(GameAction.hint), isTrue);
      expect(c.grant(GameAction.hint), isFalse);
      c.restart();
      expect(c.actions, ActionCounts.initial);
      expect((c.usesLeft(GameAction.hint), c.grantsLeft(GameAction.hint), c.isSpent(GameAction.hint)), (1, 1, false));
      c.dispose();
    });

    test('a resumed save keeps the cap', () async {
      final c = controllerFor();
      c
        ..tapTile('a1')
        ..undo()
        ..grant(GameAction.undo)
        ..tapTile('a1')
        ..undo();
      expect(c.isSpent(GameAction.undo), isTrue);
      await settle();
      final resumed = controllerFor(resume: progress.savedGame());
      expect(resumed.state.history, c.state.history, reason: 'resumed, not started over');
      expect(resumed.isSpent(GameAction.undo), isTrue);
      resumed.tapTile('a1');
      expect(resumed.grant(GameAction.undo), isFalse);
      expect(resumed.undo(), isNull);
      resumed.dispose();
      c.dispose();
    });

    test('a save from before the cap (two grants of an action) resumes; the action is then spent', () async {
      final saved = SavedGame(
        levelId: 'test-level',
        levelUrl: entry.ref.url,
        history: const ['a1', '!hint', '!grant:hint', '!hint', '!grant:hint', '!hint', 'b1'],
        elapsedMs: 5000,
      );
      final c = controllerFor(resume: saved);
      expect(c.state.history, saved.history, reason: 'resumed, not started over');
      expect(c.state.tray, ['a1', 'b1']);
      expect(c.elapsed, const Duration(seconds: 5));
      expect(c.actions.hintsUsed, 3);
      expect((c.usesLeft(GameAction.hint), c.grantsLeft(GameAction.hint), c.isSpent(GameAction.hint)), (0, 0, true));
      expect(c.grant(GameAction.hint), isFalse);
      expect(c.isSpent(GameAction.undo), isFalse);
      c.dispose();
    });
  });

  test('revive keeps the uses and seals undo; restart gives them back', () async {
    final c = controllerFor();
    c
      ..tapTile('a1')
      ..undo()
      ..useHint();
    for (final id in ['a1', 'b1', 'c1', 'd1']) {
      c.tapTile(id);
    }
    final uses = c.actions;
    c.revive();
    expect(c.actions, uses);
    expect(c.scoring.undoableMatches, 0);
    c.restart();
    expect(c.actions, ActionCounts.initial);
    c.dispose();
  });
}

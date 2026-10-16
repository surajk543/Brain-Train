import 'package:brain_train/app/sound_effects.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/level_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

class _RecordingSounds extends SoundEffects {
  _RecordingSounds(super.settings);

  final List<Sfx> played = [];

  @override
  void play(Sfx sfx) => played.add(sfx);
}

void main() {
  // Haptics go through a platform channel.
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
  late _RecordingSounds sounds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    progress = await ProgressRepository.open();
    settings = await SettingsRepository.open();
    sounds = _RecordingSounds(settings);
  });

  GameController controllerFor({
    LevelDefinition? on,
    SavedGame? resume,
    Duration delay = Duration.zero,
    bool intro = false,
  }) => GameController(
    entry: entry,
    level: on ?? board,
    registry: reg,
    progress: progress,
    settings: settings,
    sounds: sounds,
    resume: resume,
    arrivalFeedbackDelay: delay,
    playIntro: intro,
  );

  /// Taps [ids] and returns the events they emitted.
  Future<List<BoardEvent>> tap(GameController controller, List<String> ids) async {
    final events = <BoardEvent>[];
    final subscription = controller.events.listen(events.add);
    ids.forEach(controller.tapTile);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return events;
  }

  test('a free tile goes to the tray: TileToTray with its slot, a tap sound, an autosave', () async {
    final controller = controllerFor();
    final events = await tap(controller, ['a1', 'b1']);
    expect(events, [
      isA<TileToTray>().having((e) => e.tileId, 'tileId', 'a1').having((e) => e.slot, 'slot', 0),
      isA<TileToTray>().having((e) => e.tileId, 'tileId', 'b1').having((e) => e.slot, 'slot', 1),
    ]);
    expect(sounds.played, [Sfx.tap, Sfx.tap]);
    expect(controller.state.tray, ['a1', 'b1']);
    expect(controller.state.moveCount, 2);
    expect(progress.savedGame()!.history, ['a1', 'b1']);
    controller.dispose();
  });

  test('a match: TileToTray, then TrayPairCleared with both slots, and the match sound', () async {
    final controller = controllerFor();
    await tap(controller, ['a1', 'b1']);
    sounds.played.clear();
    final events = await tap(controller, ['a2']);
    expect(events, hasLength(2));
    expect(events[0], isA<TileToTray>().having((e) => e.slot, 'slot', 2));
    final cleared = events[1] as TrayPairCleared;
    expect(cleared.tileId, 'a2');
    expect(cleared.slot, 2);
    expect(cleared.partnerId, 'a1');
    expect(cleared.partnerSlot, 0);
    expect(cleared.pair, ('a1', 'a2'));
    expect(sounds.played, [Sfx.tap, Sfx.match]);
    expect(controller.state.tray, ['b1']);
    expect(controller.state.matchedPairs, 1);
    controller.dispose();
  });

  test('a blocked tile: TileRejected and only the invalid sound; nothing saved', () async {
    final controller = controllerFor();
    final events = await tap(controller, ['x1']);
    expect(events, [isA<TileRejected>().having((e) => e.tileId, 'tileId', 'x1')]);
    expect(sounds.played, [Sfx.invalid]);
    expect(controller.state.moveCount, 0);
    expect(progress.savedGame(), isNull);
    controller.dispose();
  });

  test('a full tray: TrayFull with the four tiles, the lose sound, saved for revive, clock stopped', () async {
    final controller = controllerFor();
    final events = await tap(controller, ['a1', 'b1', 'c1', 'd1']);
    expect(events.last, isA<TrayFull>().having((e) => e.tileIds, 'tileIds', ['a1', 'b1', 'c1', 'd1']));
    expect(events[events.length - 2], isA<TileToTray>().having((e) => e.slot, 'slot', 3));
    expect(sounds.played.last, Sfx.lose);
    expect(controller.state.status, GameStatus.trayFull);
    await Future<void>.delayed(Duration.zero);
    expect(progress.savedGame()!.history, ['a1', 'b1', 'c1', 'd1'], reason: 'it can still be revived after a restart');
    final elapsed = controller.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.elapsed, elapsed);
    // Taps after the game is over do nothing.
    expect(await tap(controller, ['a2']), isEmpty);
    controller.dispose();
  });

  test('a level with rules.trayCapacity 5: four tiles wait, the fifth fills the tray, revive returns five', () async {
    final five = LevelDefinition(
      levelId: board.levelId,
      title: board.title,
      board: board.board,
      rules: const LevelRules(trayCapacity: 5),
      tiles: board.tiles,
    );
    final controller = controllerFor(on: five);
    expect(controller.trayCapacity, 5);
    expect(controller.state.trayCapacity, 5);
    var events = await tap(controller, ['a1', 'b1', 'c1', 'd1']);
    expect(events.whereType<TrayFull>(), isEmpty);
    expect(controller.state.status, GameStatus.playing);
    events = await tap(controller, ['y1']);
    expect(events.last, isA<TrayFull>().having((e) => e.tileIds, 'tileIds', ['a1', 'b1', 'c1', 'd1', 'y1']));
    expect(controller.revive(), isTrue);
    expect(controller.state.tray, isEmpty);
    expect(controller.state.remaining, hasLength(10));
    // The save replays on the same level with five slots.
    await Future<void>.delayed(Duration.zero);
    final resumed = controllerFor(on: five, resume: progress.savedGame());
    expect(resumed.state.history, controller.state.history);
    expect(resumed.state.status, GameStatus.playing);
    controller.dispose();
    resumed.dispose();
  });

  test('revive: TrayReturned, tiles back on the board, clock running, saved, not a move', () async {
    final controller = controllerFor();
    expect(controller.revive(), isFalse, reason: 'nothing to revive while playing');
    await tap(controller, ['a1', 'b1', 'c1', 'd1']);
    sounds.played.clear();
    final events = <BoardEvent>[];
    final subscription = controller.events.listen(events.add);
    expect(controller.revive(), isTrue);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    final returned = events.single as TrayReturned;
    expect(returned.tileIds, ['a1', 'b1', 'c1', 'd1']);
    expect(returned.fromSlots, [0, 1, 2, 3]);
    expect(sounds.played, [Sfx.select]);
    expect(controller.state.status, GameStatus.playing);
    expect(controller.state.tray, isEmpty);
    expect(controller.state.remaining, containsAll(<String>['a1', 'b1', 'c1', 'd1']));
    expect(controller.state.moveCount, 4);
    expect(controller.revive(), isFalse);
    final elapsed = controller.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.elapsed, greaterThan(elapsed), reason: 'the clock runs again');
    expect(progress.savedGame()!.history, ['a1', 'b1', 'c1', 'd1', GameEngine.reviveMarker]);

    // The save resumes after the revive.
    final resumed = controllerFor(resume: progress.savedGame());
    expect(resumed.state.status, GameStatus.playing);
    expect(resumed.state.tray, isEmpty);
    expect(resumed.state.moveCount, 4);
    resumed.dispose();
    controller.dispose();
  });

  test('with matches played as strikes, match and win sound at impact, not on tap', () async {
    final small = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0), ('b1', 'B', 8, 0, 0), ('b2', 'B', 12, 0, 0)]);
    final controller = GameController(
      entry: entry,
      level: small,
      registry: reg,
      progress: progress,
      settings: settings,
      sounds: sounds,
      matchFeedbackOnImpact: true,
    );
    await tap(controller, ['a1', 'a2', 'b1', 'b2']);
    expect(controller.state.status, GameStatus.won);
    expect(sounds.played, [Sfx.tap, Sfx.tap, Sfx.tap, Sfx.tap], reason: 'only the taps so far');
    controller.pairImpact();
    expect(sounds.played.last, Sfx.match, reason: 'the last pair has not hit yet');
    controller.pairImpact();
    expect(sounds.played.sublist(sounds.played.length - 3), [Sfx.match, Sfx.match, Sfx.win],
        reason: 'the last pair strikes too, then the win sound follows');
    controller.dispose();
  });

  test('the win sound waits winSoundDelay after the last strike', () async {
    final small = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0)]);
    final controller = GameController(
      entry: entry,
      level: small,
      registry: reg,
      progress: progress,
      settings: settings,
      sounds: sounds,
      matchFeedbackOnImpact: true,
      winSoundDelay: const Duration(milliseconds: 30),
    );
    await tap(controller, ['a1', 'a2']);
    controller.pairImpact();
    expect(sounds.played.last, Sfx.match, reason: 'the strike first');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sounds.played.last, Sfx.win);
    controller.dispose();
  });

  test('clearing board and tray wins: win sound, record saved, save cleared', () async {
    final small = level([('a1', 'A', 0, 0, 0), ('a2', 'A', 4, 0, 0), ('b1', 'B', 8, 0, 0), ('b2', 'B', 12, 0, 0)]);
    final controller = controllerFor(on: small);
    await tap(controller, ['a1', 'b1', 'a2', 'b2']);
    expect(controller.state.status, GameStatus.won);
    expect(sounds.played.last, Sfx.win);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(progress.completed()['test-level']!.bestMoves, 4);
    expect(progress.savedGame(), isNull);
    expect(controller.winRecord, isNotNull);
    controller.dispose();
  });

  test('outcome feedback can wait for the flight; the tap sounds at once', () async {
    final controller = controllerFor(delay: const Duration(milliseconds: 30));
    await tap(controller, ['a1', 'a2']);
    expect(sounds.played, [Sfx.tap, Sfx.tap]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sounds.played, [Sfx.tap, Sfx.tap, Sfx.match]);
    // Restart drops feedback that has not played yet.
    await tap(controller, ['b1', 'b2']);
    controller.restart();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sounds.played.where((s) => s == Sfx.match), hasLength(1));
    controller.dispose();
  });

  test('restart: BoardReset, empty tray, zero counters, save cleared', () async {
    final controller = controllerFor();
    await tap(controller, ['a1', 'b1', 'a2']);
    final events = <BoardEvent>[];
    final subscription = controller.events.listen(events.add);
    controller.restart();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(events, [isA<BoardReset>()]);
    expect(controller.state.tray, isEmpty);
    expect(controller.state.moveCount, 0);
    expect(controller.state.matchedPairs, 0);
    expect(controller.state.remaining.length, board.tiles.length);
    expect(controller.elapsed, lessThan(const Duration(seconds: 1)));
    await Future<void>.delayed(Duration.zero);
    expect(progress.savedGame(), isNull);
    controller.dispose();
  });

  group('board intro', () {
    test('taps are ignored and the clock waits until the intro ends', () async {
      final controller = controllerFor(intro: true);
      expect(controller.introPlaying, isTrue);
      expect(await tap(controller, ['a1']), isEmpty);
      expect(controller.state.moveCount, 0);
      expect(sounds.played, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.elapsed, Duration.zero, reason: 'no time counted during the intro');
      controller.pauseClock();
      controller.resumeClock();
      expect(controller.elapsed, Duration.zero, reason: 'coming back to the app does not start it either');
      controller.endIntro();
      expect(controller.introPlaying, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.elapsed, greaterThan(Duration.zero));
      expect(await tap(controller, ['a1']), hasLength(1));
      controller
        ..introLayerLanded()
        ..dispose();
      expect(sounds.played.last, Sfx.select, reason: 'one soft tick per landed layer');
    });

    test('plays again on restart (a new serial), not on revive', () async {
      final controller = controllerFor(intro: true);
      final first = controller.introSerial;
      controller.endIntro();
      await tap(controller, ['a1', 'b1', 'c1', 'd1']);
      expect(controller.state.status, GameStatus.trayFull);
      expect(controller.revive(), isTrue);
      expect(controller.introPlaying, isFalse, reason: 'revive goes straight back to play');
      controller.restart();
      expect(controller.introPlaying, isTrue);
      expect(controller.introSerial, isNot(first));
      expect(controller.elapsed, Duration.zero);
      expect(await tap(controller, ['a1']), isEmpty);
      // A restart during the intro restarts it.
      final second = controller.introSerial;
      controller.restart();
      expect(controller.introSerial, isNot(second));
      controller.dispose();
    });

    test('a resumed game plays it, with its clock held at the saved time', () async {
      final resumed = controllerFor(
        intro: true,
        resume: SavedGame(levelId: 'test-level', levelUrl: entry.ref.url, history: ['a1', 'b1'], elapsedMs: 5000),
      );
      expect(resumed.introPlaying, isTrue);
      expect(resumed.state.tray, ['a1', 'b1']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resumed.elapsed, const Duration(seconds: 5));
      resumed.endIntro();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resumed.elapsed, greaterThan(const Duration(seconds: 5)));
      resumed.dispose();
    });

    test('without it (reduced motion, tests) play starts at once', () async {
      final controller = controllerFor();
      expect(controller.introPlaying, isFalse);
      expect(await tap(controller, ['a1']), hasLength(1));
      controller.dispose();
    });
  });

  test('a save resumes board, tray and clock; a save that no longer replays starts over', () async {
    final resumed = controllerFor(
      resume: SavedGame(levelId: 'test-level', levelUrl: entry.ref.url, history: ['a1', 'b1', 'a2'], elapsedMs: 5000),
    );
    expect(resumed.state.tray, ['b1']);
    expect(resumed.state.matchedPairs, 1);
    expect(resumed.state.moveCount, 3);
    expect(resumed.elapsed, greaterThanOrEqualTo(const Duration(seconds: 5)));
    resumed.dispose();

    final lost = controllerFor(
      resume: SavedGame(levelId: 'test-level', levelUrl: entry.ref.url, history: ['a1', 'b1', 'c1', 'd1'], elapsedMs: 5000),
    );
    expect(lost.state.status, GameStatus.trayFull, reason: 'a legal save resumes where it ended');
    expect(lost.elapsed, const Duration(seconds: 5), reason: 'the clock does not run once the game is over');
    lost.dispose();

    final illegal = controllerFor(
      resume: SavedGame(levelId: 'test-level', levelUrl: entry.ref.url, history: ['a1', 'x1'], elapsedMs: 5000),
    );
    expect(illegal.state.moveCount, 0, reason: 'x1 is blocked: the save no longer fits the level');
    illegal.dispose();
  });
}

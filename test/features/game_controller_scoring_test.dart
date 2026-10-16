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

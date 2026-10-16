import 'dart:convert';

import 'package:brain_train/data/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SavedGame game({List<String> history = const ['a1', 'b1', 'a2']}) =>
      SavedGame(levelId: 'level-0001', levelUrl: 'levels/level-0001-v1.json', history: history, elapsedMs: 4200);

  test('a saved game stores the tap sequence and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    await progress.saveGame(game());
    final reopened = await ProgressRepository.open();
    final saved = reopened.savedGame()!;
    expect(saved.history, ['a1', 'b1', 'a2']);
    expect(saved.moveCount, 3, reason: 'one move per tap by default');
    expect(saved.elapsedMs, 4200);
    expect(saved.levelUrl, 'levels/level-0001-v1.json');
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('progress.current.v3')!)['history'], ['a1', 'b1', 'a2']);
    expect(prefs.containsKey('progress.current.v2'), isFalse);
  });

  test('the history keeps action markers (v3)', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    const history = ['a1', '!undo', '!hint', '!grant:undo', '!shuffle:1:42', 'b1', '!revive'];
    await progress.saveGame(game(history: history));
    expect((await ProgressRepository.open()).savedGame()!.history, history);
  });

  Map<String, Object?> v2Save(String levelId) => {
    'levelId': levelId,
    'levelUrl': 'levels/$levelId-v1.json',
    'history': ['a1', 'b1', '!revive', 'c1'],
    'moveCount': 3,
    'elapsedMs': 9000,
    'scoring': {'score': 100, 'combo': 0, 'bestCombo': 1, 'pairs': 1, 'lastMatchAtMs': null},
  };

  test('a 1.0 save (v2) moves to v3 when the repository opens', () async {
    SharedPreferences.setMockInitialValues({'progress.current.v2': jsonEncode(v2Save('level-0003'))});
    final progress = await ProgressRepository.open();
    final saved = progress.savedGame()!;
    expect((saved.levelId, saved.moveCount, saved.elapsedMs), ('level-0003', 3, 9000));
    expect(saved.history, ['a1', 'b1', '!revive', 'c1']);
    expect(saved.scoring!['score'], 100);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('progress.current.v2'), isFalse);
    expect(jsonDecode(prefs.getString('progress.current.v3')!), v2Save('level-0003'));
  });

  test('a v3 save wins over a leftover v2 one; a v2 save is read until the next save', () async {
    SharedPreferences.setMockInitialValues({
      'progress.current.v2': jsonEncode(v2Save('level-0001')),
      'progress.current.v3': jsonEncode(v2Save('level-0002')),
    });
    expect((await ProgressRepository.open()).savedGame()!.levelId, 'level-0002');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('progress.current.v2'), isFalse);

    SharedPreferences.setMockInitialValues({'progress.current.v2': jsonEncode(v2Save('level-0004'))});
    // Constructed directly (as tests do), without the move in open().
    final direct = ProgressRepository(await SharedPreferences.getInstance());
    expect(direct.savedGame()!.levelId, 'level-0004');
    await direct.saveGame(
      SavedGame(levelId: 'level-0004', levelUrl: 'levels/level-0004-v1.json', history: const ['a1'], elapsedMs: 100),
    );
    final after = await SharedPreferences.getInstance();
    expect(after.containsKey('progress.current.v2'), isFalse);
    expect(direct.savedGame()!.history, ['a1']);
    await direct.clearSavedGame(levelId: 'level-0004');
    expect(direct.savedGame(), isNull);
  });

  test('pair-history saves from before the tray are ignored and removed', () async {
    SharedPreferences.setMockInitialValues({
      'progress.current.v1': jsonEncode({
        'levelId': 'level-0001',
        'levelUrl': 'levels/level-0001-v1.json',
        'history': [
          ['a1', 'a2'],
        ],
        'moveCount': 1,
        'elapsedMs': 1000,
      }),
      'progress.completed.v1': jsonEncode({
        'level-0001': {'bestMoves': 8, 'bestTimeMs': 41000, 'completedAt': '2026-10-01T10:00:00.000'},
      }),
    });
    final progress = await ProgressRepository.open();
    expect(progress.savedGame(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('progress.current.v1'), isFalse);
    // Completed levels are kept.
    expect(progress.completed()['level-0001']!.bestMoves, 8);
  });

  test('a malformed save reads as no save', () async {
    SharedPreferences.setMockInitialValues({
      'progress.current.v2': jsonEncode({
        'levelId': 'level-0001',
        'levelUrl': 'levels/level-0001-v1.json',
        'history': [
          ['a1', 'a2'],
        ],
        'moveCount': 1,
        'elapsedMs': 1000,
      }),
    });
    expect((await ProgressRepository.open()).savedGame(), isNull);
  });

  test('clearing the save removes it', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    await progress.saveGame(game());
    await progress.clearSavedGame(levelId: 'level-0001');
    expect(progress.savedGame(), isNull);
  });

  SavedGame gameOn(String id) =>
      SavedGame(levelId: id, levelUrl: 'levels/$id-v1.json', history: const ['a1'], elapsedMs: 100);

  test('clearing for a level removes only that level\'s save', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    await progress.saveGame(gameOn('level-0002'));
    await progress.clearSavedGame(levelId: 'level-0001');
    expect(progress.savedGame()!.levelId, 'level-0002', reason: 'another level\'s save is untouched');
    await progress.clearSavedGame(levelId: 'level-0002');
    expect(progress.savedGame(), isNull);
  });

  test('a completed level is never saved: no overwrite, no new save, no notification', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    await progress.recordWin('level-0001', moves: 8, timeMs: 1000);
    await progress.saveGame(gameOn('level-0002'));
    var notified = 0;
    progress.addListener(() => notified++);
    await progress.saveGame(gameOn('level-0001'));
    expect(progress.savedGame()!.levelId, 'level-0002');
    expect(notified, 0);
    await progress.clearSavedGame(levelId: 'level-0002');
    await progress.saveGame(gameOn('level-0001'));
    expect(progress.savedGame(), isNull, reason: 'a replay does not create a save');
  });

  test('replays keep the fastest time and the date of that fastest win', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    final first = await progress.recordWin('level-0001', moves: 20, timeMs: 90000);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final slower = await progress.recordWin('level-0001', moves: 18, timeMs: 120000);
    expect(slower.bestTimeMs, 90000, reason: 'a slower replay keeps the best time');
    expect(slower.completedAt, first.completedAt, reason: 'and the date of that best time');
    expect(slower.bestMoves, 18);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final faster = await progress.recordWin('level-0001', moves: 22, timeMs: 60000);
    expect(faster.bestTimeMs, 60000);
    expect(faster.completedAt.isAfter(first.completedAt), isTrue);
    final reopened = await ProgressRepository.open();
    expect(reopened.completed()['level-0001']!.bestTimeMs, 60000);
  });

  test('recordWin keeps the best score and best combo separately; old records have none', () async {
    SharedPreferences.setMockInitialValues({});
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
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.open();
    await progress.saveGame(
      SavedGame(levelId: 'l9', levelUrl: 'u', history: const ['a'], elapsedMs: 1000, scoring: const {'score': 100}),
    );
    expect((await ProgressRepository.open()).savedGame()!.scoring, {'score': 100});
    final old = SavedGame.fromJson({'levelId': 'l9', 'levelUrl': 'u', 'history': ['a'], 'moveCount': 1, 'elapsedMs': 1});
    expect(old.scoring, isNull);
    expect(old.toJson().containsKey('scoring'), isFalse);
  });
}

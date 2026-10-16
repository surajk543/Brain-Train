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
    expect(jsonDecode(prefs.getString('progress.current.v2')!)['history'], ['a1', 'b1', 'a2']);
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
    await progress.clearSavedGame();
    expect(progress.savedGame(), isNull);
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
}

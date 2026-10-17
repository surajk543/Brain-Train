// Shared setup for captures of the gameplay screen (test/visual/): saved
// games at a given point of play, the board intro and board taps.
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/widgets/board_intro.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/state/game_state.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// The first [pairs] pairs of a solver solution (all of them by default), as
/// a resumable game (each pair played as two taps through the tray).
SavedGame solvedSave(ContentSnapshot snapshot, LevelManifestEntry entry, {int? pairs, int elapsedMs = 17000}) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = engineFor(level, snapshot.registry);
  final solution = MahjongSolver(
    geometry: engine.geometry,
    rules: engine.rules,
  ).solve(TileMask.all(level.tiles.length)).solution;
  final history = [
    for (final (a, b) in solution.take(pairs ?? solution.length)) ...[level.tiles[a].tileId, level.tiles[b].tileId],
  ];
  return SavedGame(
    levelId: level.levelId,
    levelUrl: entry.ref.url,
    history: history,
    moveCount: history.length,
    elapsedMs: elapsedMs,
  );
}

/// A line of play that leaves the tray one tile short of full (three of
/// four, four of five), plus a free board tile that fills it without a match;
/// after [revives] full trays revived.
(SavedGame, String) nearlyFullSave(ContentSnapshot snapshot, LevelManifestEntry entry, {int revives = 0}) {
  final level = snapshot.levels[entry.levelId]!;
  final engine = engineFor(level, snapshot.registry);
  String unmatched() => (engine.state.free.toList()..sort()).firstWhere(
    (id) => !engine.state.tray.any((t) => engine.rules.matches(engine.indexOf(t)!, engine.indexOf(id)!)),
  );
  for (var i = 0; i < revives; i++) {
    while (engine.state.status == GameStatus.playing) {
      engine.tap(unmatched());
    }
    expect(engine.revive(), isNotNull);
  }
  while (engine.state.tray.length < engine.trayCapacity - 1) {
    engine.tap(unmatched());
  }
  final save = SavedGame(
    levelId: level.levelId,
    levelUrl: entry.ref.url,
    history: engine.state.history,
    elapsedMs: 94000,
  );
  return (save, unmatched());
}

/// The game screen's board intro.
BoardIntroController introOf(WidgetTester tester) =>
    tester.widget<BoardIntroOverlay>(find.byType(BoardIntroOverlay)).controller;

/// The game screen's controller (through its board).
GameController gameOf(WidgetTester tester) => tester.widget<BoardView>(find.byType(BoardView)).controller;

/// Pumps until the board intro has handed over to the board (big boards
/// may still be decoding their art, which needs real time).
Future<void> finishIntro(WidgetTester tester) async {
  for (var i = 0; i < 80 && (introOf(tester).isRunning || gameOf(tester).introPlaying); i++) {
    if (!introOf(tester).isRunning) await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(gameOf(tester).introPlaying, isFalse, reason: 'the intro handed over');
  await tester.pump();
}

/// Taps [tileId] on the board of a game resumed from [history].
Future<void> tapBoardTile(
  WidgetTester tester,
  ContentSnapshot snapshot,
  LevelManifestEntry entry,
  List<String> history,
  String tileId,
) async {
  final level = snapshot.levels[entry.levelId]!;
  final engine = engineFor(level, snapshot.registry)..replay(history);
  final board = tester.getRect(find.byType(BoardView));
  final projection = boardProjectionFor(level, engine.geometry, TileStyle.forTileSet(level.tileSetId), board.size);
  final face = projection.faceRect(engine.indexOf(tileId)!);
  await tester.tapAt(board.topLeft + Offset(face.centerX, face.centerY));
}

import '../campaign/seeded_random.dart';
import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../rules/match_rules.dart';

/// Outcome of many simulated games on one board.
class TraySimulation {
  const TraySimulation({required this.runs, required this.wins, required this.averageCleared});

  final int runs;
  final int wins;

  /// Mean share of tiles cleared per game (1 for a win).
  final double averageCleared;

  double get winRate => runs == 0 ? 0 : wins / runs;
}

/// How a simulated player picks its next tile.
enum TrayPlayer {
  /// Takes a free tile that matches a tray tile if there is one, otherwise
  /// a random free tile. The calibration player: no lookahead at all.
  random,

  /// Like [random], but before a random tile it takes one of two free tiles
  /// that match each other (a pair on the board), as most people would.
  pairSeeking,
}

/// A simple tray player for calibrating difficulty: it plays the game's
/// rules (`GameEngine`: free tiles go to a tray of [capacity] slots, a
/// matching pair clears, a full tray without a match loses) with no
/// lookahead; see [TrayPlayer] for how it picks.
///
/// Pure Dart, incremental and allocation-light: hundreds of games per level
/// run in milliseconds.
class TraySimulator {
  TraySimulator({required this.geometry, required List<int> keys, required this.capacity})
    : _keys = List.unmodifiable(keys),
      _keyCount = keys.isEmpty ? 0 : keys.reduce((a, b) => a > b ? a : b) + 1,
      _availability = TileAvailabilityCalculator(geometry);

  /// Simulates [rules]' match keys on [geometry].
  factory TraySimulator.forRules(BoardGeometry geometry, MatchRules rules, {required int capacity}) {
    final ids = <String, int>{};
    return TraySimulator(
      geometry: geometry,
      keys: [for (var i = 0; i < geometry.length; i++) ids.putIfAbsent(rules.keyOf(i), () => ids.length)],
      capacity: capacity,
    );
  }

  final BoardGeometry geometry;
  final int capacity;
  final List<int> _keys;
  final int _keyCount;
  final TileAvailabilityCalculator _availability;

  TraySimulation run({required int runs, required int seed, TrayPlayer player = TrayPlayer.random}) {
    var wins = 0;
    var cleared = 0.0;
    final random = SeededRandom.of(['tray-sim', seed]);
    for (var i = 0; i < runs; i++) {
      final removed = play(random, player: player);
      if (removed == geometry.length) wins++;
      cleared += geometry.length == 0 ? 1 : removed / geometry.length;
    }
    return TraySimulation(runs: runs, wins: wins, averageCleared: runs == 0 ? 0 : cleared / runs);
  }

  /// Plays one game; returns how many tiles were cleared (all of them is a
  /// win). [onTake] sees every tile index taken, in order (for tests that
  /// replay a game through `GameEngine`).
  int play(SeededRandom random, {TrayPlayer player = TrayPlayer.random, void Function(int index)? onTake}) {
    final n = geometry.length;
    final remaining = TileMask.all(n);
    final free = <int>[];
    final position = List<int>.filled(n, -1);
    void setFree(int index, bool isFree) {
      final at = position[index];
      if (isFree && at < 0) {
        position[index] = free.length;
        free.add(index);
      } else if (!isFree && at >= 0) {
        final last = free.removeLast();
        if (last != index) {
          free[at] = last;
          position[last] = at;
        }
        position[index] = -1;
      }
    }

    for (final index in _availability.freeTiles(remaining)) {
      setFree(index, true);
    }
    final inTray = List<int>.filled(_keyCount, 0);
    final seen = List<int>.filled(_keyCount, -1);
    var trayCount = 0, cleared = 0, onBoard = n;
    while (onBoard > 0) {
      if (free.isEmpty) return cleared;
      // A free tile that matches the tray, scanning from a random start.
      var choice = -1;
      if (trayCount > 0) {
        final start = random.nextInt(free.length);
        for (var k = 0; k < free.length; k++) {
          final index = free[(start + k) % free.length];
          if (inTray[_keys[index]] > 0) {
            choice = index;
            break;
          }
        }
      }
      final matched = choice >= 0;
      if (!matched && player == TrayPlayer.pairSeeking) {
        final start = random.nextInt(free.length);
        for (var k = 0; k < free.length && choice < 0; k++) {
          final index = free[(start + k) % free.length];
          final key = _keys[index];
          if (seen[key] == onBoard) {
            choice = index;
          } else {
            seen[key] = onBoard;
          }
        }
      }
      if (choice < 0) choice = free[random.nextInt(free.length)];
      onTake?.call(choice);
      remaining.remove(choice);
      onBoard--;
      setFree(choice, false);
      for (final other in geometry.affectedBy(choice)) {
        if (remaining.contains(other)) setFree(other, _availability.isFree(other, remaining));
      }
      final key = _keys[choice];
      if (matched) {
        inTray[key]--;
        trayCount--;
        cleared += 2;
      } else {
        inTray[key]++;
        trayCount++;
        if (trayCount >= capacity) return cleared;
      }
    }
    // An empty board leaves an empty tray: every key has an even count.
    return cleared;
  }
}

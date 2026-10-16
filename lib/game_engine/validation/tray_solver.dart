import 'dart:typed_data';

import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../rules/match_rules.dart';
import 'solver.dart';

/// What [TraySolver.solve] found.
class TraySolveResult {
  const TraySolveResult(this.outcome, this.taps, this.nodesVisited);

  final SolveOutcome outcome;

  /// Tile indices in tap order: every tap is a free board tile, a tile that
  /// matches the tray clears with it, the tray never fills, and the last tap
  /// empties board and tray. Empty unless [outcome] is solvable.
  final List<int> taps;
  final int nodesVisited;
}

class _BudgetExceeded implements Exception {}

/// Depth-first solver for the game as played: taps with a tray of [capacity]
/// slots, from any position (tiles already in the tray included).
///
/// Unlike [MahjongSolver] (pair removals from the board, which ignores the
/// tray) it searches single taps: a free tile goes to the tray, or clears the
/// tray tile it matches. So it also finds wins that need the tray, e.g. a
/// tile that frees its own twin. [SolveOutcome.unsolvable] is exact here:
/// no tap order wins.
///
/// The tray's contents follow from the board (a key is in the tray exactly
/// when an odd number of its tiles has left the board since the start), so
/// dead positions are remembered by the board alone.
///
/// Two moves are taken without branching, as they can never hurt (freedom
/// only grows as tiles leave the board, and they hold no tray slot longer
/// than any other order would): the last board tile of a key that waits in
/// the tray, when it is free; and two tiles of a key none of which waits in
/// the tray and all of whose board tiles are free, when the tray has room
/// for one. (Any winning order can be rearranged to start with them: the
/// key's other tiles take the places of its first taps in that order.)
///
/// Pure Dart and synchronous; the node budget ([maxNodes]) bounds the time.
class TraySolver {
  TraySolver({required this.geometry, required List<int> keys, required this.capacity, this.maxNodes = 20000})
    : assert(capacity >= 2, 'a tray must hold at least a pair'),
      _keys = Int32List.fromList(keys),
      _keyCount = keys.isEmpty ? 0 : keys.reduce((a, b) => a > b ? a : b) + 1,
      _availability = TileAvailabilityCalculator(geometry);

  /// Solves [rules]' match keys on [geometry].
  factory TraySolver.forRules(BoardGeometry geometry, MatchRules rules, {required int capacity, int maxNodes = 20000}) {
    final ids = <String, int>{};
    return TraySolver(
      geometry: geometry,
      keys: [for (var i = 0; i < geometry.length; i++) ids.putIfAbsent(rules.keyOf(i), () => ids.length)],
      capacity: capacity,
      maxNodes: maxNodes,
    );
  }

  final BoardGeometry geometry;
  final int capacity;
  final int maxNodes;
  final Int32List _keys;
  final int _keyCount;
  final TileAvailabilityCalculator _availability;

  // Search state, set up by [solve].
  late Uint8List _onBoard, _free, _inTray;
  late Int32List _keyLeft, _keyFree;
  late Uint32List _words;
  int _boardCount = 0, _trayCount = 0, _nodes = 0;

  /// Undo log: (tile, old free flag) pairs; a -1 tile marks a tap.
  final List<int> _log = [];
  final Set<String> _dead = {};

  /// Searches for a winning tap order from [remaining] (tiles on the board)
  /// with [tray] (tile indices, slot order) waiting in the tray.
  TraySolveResult solve(TileMask remaining, {List<int> tray = const []}) {
    if (!_setUp(remaining, tray)) return const TraySolveResult(SolveOutcome.unsolvable, [], 0);
    final path = <int>[];
    try {
      final solved = _search(path);
      return solved
          ? TraySolveResult(SolveOutcome.solvable, path, _nodes)
          : TraySolveResult(SolveOutcome.unsolvable, const [], _nodes);
    } on _BudgetExceeded {
      return TraySolveResult(SolveOutcome.unknown, const [], _nodes);
    } finally {
      _dead.clear();
      _log.clear();
    }
  }

  /// True when [taps] wins from [remaining] with [tray] waiting: each tap is
  /// a free board tile, the tray never fills, and board and tray end empty.
  /// A cheap check of a known answer, no search.
  bool check(TileMask remaining, List<int> taps, {List<int> tray = const []}) {
    if (!_setUp(remaining, tray)) return false;
    try {
      for (final index in taps) {
        if (index < 0 || index >= geometry.length || _onBoard[index] == 0 || _free[index] == 0) return false;
        if (_inTray[_keys[index]] == 0 && _trayCount + 1 >= capacity) return false;
        _tap(index);
      }
      return _boardCount == 0 && _trayCount == 0;
    } finally {
      _log.clear();
    }
  }

  bool _setUp(TileMask remaining, List<int> tray) {
    final n = geometry.length;
    _onBoard = Uint8List(n);
    _free = Uint8List(n);
    _inTray = Uint8List(_keyCount);
    _keyLeft = Int32List(_keyCount);
    _keyFree = Int32List(_keyCount);
    _words = Uint32List((n + 31) >> 5);
    _boardCount = 0;
    _trayCount = 0;
    _nodes = 0;
    _log.clear();
    for (final index in remaining.indices) {
      _onBoard[index] = 1;
      _words[index >> 5] |= 1 << (index & 31);
      _keyLeft[_keys[index]]++;
      _boardCount++;
    }
    for (final index in _availability.freeTiles(remaining)) {
      _free[index] = 1;
      _keyFree[_keys[index]]++;
    }
    for (final index in tray) {
      final key = _keys[index];
      // Two of a key never wait together (they would have matched).
      if (_inTray[key] == 1) return false;
      _inTray[key] = 1;
      _trayCount++;
    }
    return _trayCount < capacity;
  }

  bool _search(List<int> path) {
    if (_boardCount == 0) return _trayCount == 0;
    final stateKey = _words.join(',');
    if (_dead.contains(stateKey)) return false;
    if (++_nodes > maxNodes) throw _BudgetExceeded();

    final n = geometry.length;
    final room = _trayCount + 1 < capacity;
    // A move that can never hurt: take it without branching.
    for (var i = 0; i < n; i++) {
      if (_free[i] == 0) continue;
      final key = _keys[i];
      if (_inTray[key] == 1 && _keyLeft[key] == 1) {
        if (_try([i], path)) return true;
        _dead.add(stateKey);
        return false;
      }
      if (room && _inTray[key] == 0 && _keyLeft[key] >= 2 && _keyLeft[key] == _keyFree[key]) {
        var j = i + 1;
        while (_free[j] == 0 || _keys[j] != key) {
          j++;
        }
        if (_try([i, j], path)) return true;
        _dead.add(stateKey);
        return false;
      }
    }

    // (priority, score, tile): matches first, then the first tile of a free
    // pair, then tiles that only park in the tray.
    final moves = <(int, int, int)>[];
    for (var i = 0; i < n; i++) {
      if (_free[i] == 0) continue;
      final key = _keys[i];
      if (_inTray[key] == 1) {
        moves.add((2, _score(i), i));
      } else if (room) {
        moves.add((_keyFree[key] >= 2 ? 1 : 0, _score(i), i));
      }
    }
    moves.sort((a, b) {
      if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
      if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
      return a.$3.compareTo(b.$3);
    });
    for (final (_, _, tile) in moves) {
      if (_try([tile], path)) return true;
    }
    _dead.add(stateKey);
    return false;
  }

  bool _try(List<int> taps, List<int> path) {
    for (final tile in taps) {
      _tap(tile);
      path.add(tile);
    }
    if (_search(path)) return true;
    for (var k = taps.length - 1; k >= 0; k--) {
      _untap(taps[k]);
      path.removeLast();
    }
    return false;
  }

  /// Prefers tiles high in a stack that hold many other tiles back.
  int _score(int index) {
    var blocking = 0;
    for (final other in geometry.affectedBy(index)) {
      if (_onBoard[other] == 1) blocking++;
    }
    return geometry.tiles[index].layer * 4 + blocking;
  }

  void _setFree(int index, int value) {
    if (_free[index] == value) return;
    _log
      ..add(index)
      ..add(_free[index]);
    _free[index] = value;
    _keyFree[_keys[index]] += value == 1 ? 1 : -1;
  }

  bool _isFree(int index) {
    for (final upper in geometry.coveredBy[index]) {
      if (_onBoard[upper] == 1) return false;
    }
    var leftBlocked = false;
    for (final left in geometry.leftNeighbors[index]) {
      if (_onBoard[left] == 1) {
        leftBlocked = true;
        break;
      }
    }
    if (!leftBlocked) return true;
    for (final right in geometry.rightNeighbors[index]) {
      if (_onBoard[right] == 1) return false;
    }
    return true;
  }

  void _tap(int index) {
    _log
      ..add(-1)
      ..add(index);
    final key = _keys[index];
    _setFree(index, 0);
    _onBoard[index] = 0;
    _words[index >> 5] &= ~(1 << (index & 31));
    _keyLeft[key]--;
    _boardCount--;
    for (final other in geometry.affectedBy(index)) {
      if (_onBoard[other] == 1) _setFree(other, _isFree(other) ? 1 : 0);
    }
    if (_inTray[key] == 1) {
      _inTray[key] = 0;
      _trayCount--;
    } else {
      _inTray[key] = 1;
      _trayCount++;
    }
  }

  void _untap(int index) {
    final key = _keys[index];
    if (_inTray[key] == 1) {
      _inTray[key] = 0;
      _trayCount--;
    } else {
      _inTray[key] = 1;
      _trayCount++;
    }
    _onBoard[index] = 1;
    _words[index >> 5] |= 1 << (index & 31);
    _keyLeft[key]++;
    _boardCount++;
    // Restore free flags changed since this tap, newest first.
    while (true) {
      final flag = _log.removeLast(), tile = _log.removeLast();
      if (tile == -1) break;
      if (_free[tile] != flag) {
        _keyFree[_keys[tile]] += flag == 1 ? 1 : -1;
        _free[tile] = flag;
      }
    }
  }
}

import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../models/level_definition.dart';
import '../models/level_rules.dart';
import '../rules/match_rules.dart';
import 'game_state.dart';

/// What happened when the player tapped a tile.
enum TapOutcome {
  /// Not on the board (unknown, in the tray, cleared) or the game is over.
  ignored,

  /// The tile is covered or has both sides blocked.
  blocked,

  /// The tile left the board for tray slot [TapResult.slot].
  toTray,

  /// The tile left the board, matched [TapResult.partnerTileId] in the tray,
  /// and both were destroyed. Check [GameState.status] for a win.
  matched,

  /// The tile filled the last tray slot without a match: the game is lost.
  trayFull,
}

class TapResult {
  const TapResult(this.outcome, {this.tileId, this.slot, this.partnerTileId, this.partnerSlot});

  final TapOutcome outcome;

  /// The tapped tile.
  final String? tileId;

  /// The tray slot the tile goes to, for every accepted tap. For
  /// [TapOutcome.matched] it is the slot after the tray's last tile, where
  /// the tile lands before the pair clears.
  final int? slot;

  /// The tray tile it matched, for [TapOutcome.matched].
  final String? partnerTileId;

  /// Tray slot of [partnerTileId] before the pair cleared.
  final int? partnerSlot;

  /// True when the tile left the board.
  bool get accepted => slot != null;
}

/// UI-independent rules for one level: Mahjong Solitaire freedom rules with
/// a matching tray.
///
/// Tapping a free tile moves it off the board into the tray (slots fill
/// left to right, packed). If it matches a tile already in the tray, both
/// are destroyed and the tray re-packs. A tray holding [trayCapacity]
/// unmatched tiles loses the game; an empty board and tray wins it.
///
/// The tray never holds two tiles with the same match key (they would have
/// matched), so an arriving tile has at most one partner.
///
/// A lost game can be revived ([revive]): the tray's tiles go back to their
/// places on the board and play goes on.
///
/// All state changes are synchronous, so rapid taps can never move a tile
/// twice; animations only replay what has already happened here.
class GameEngine {
  GameEngine({
    required this.level,
    required this.rules,
    BoardGeometry? geometry,
    int? trayCapacity,
  }) : trayCapacity = trayCapacity ?? level.rules.trayCapacity,
       assert((trayCapacity ?? level.rules.trayCapacity) >= 2, 'a tray must hold at least a pair'),
       geometry = geometry ?? BoardGeometry.build(level),
       _remaining = TileMask.all(level.tiles.length) {
    _availability = TileAvailabilityCalculator(this.geometry);
    _recomputeAll();
    _changed();
  }

  /// Tray slots of a level that does not set `rules.trayCapacity`.
  static const int defaultTrayCapacity = kDefaultTrayCapacity;

  /// Marks a [revive] in [GameState.history]. Never a tile id: tile ids
  /// are letters, digits, `_` and `-` only.
  static const String reviveMarker = '!revive';

  final LevelDefinition level;
  final MatchRules rules;
  final BoardGeometry geometry;

  /// Tiles the tray holds before the game is lost: the level's
  /// `rules.trayCapacity` unless the constructor overrides it.
  final int trayCapacity;
  late final TileAvailabilityCalculator _availability;

  /// Tiles on the board.
  TileMask _remaining;
  final Set<int> _free = {};
  final List<int> _tray = [];

  /// Tapped tile ids and [reviveMarker]s, in order.
  final List<String> _history = [];
  int _moveCount = 0;
  int _matchedPairs = 0;
  GameStatus _status = GameStatus.playing;
  GameState? _cachedState;

  GameState get state => _cachedState ??= GameState(
    levelId: level.levelId,
    remaining: Set.unmodifiable(_remaining.indices.map(_id)),
    free: Set.unmodifiable(_free.map(_id)),
    tray: List.unmodifiable(_tray.map(_id)),
    trayCapacity: trayCapacity,
    moveCount: _moveCount,
    matchedPairs: _matchedPairs,
    totalPairs: level.pairCount,
    history: List.unmodifiable(_history),
    status: _status,
  );

  /// A copy of the board's remaining-tile set, for the solver.
  TileMask get remainingMask => _remaining.copy();

  String _id(int index) => level.tiles[index].tileId;

  /// True while the tile is on the board.
  bool isRemaining(int index) => _remaining.contains(index);

  bool isFreeIndex(int index) => _free.contains(index);

  bool isInTray(int index) => _tray.contains(index);

  int? indexOf(String tileId) => geometry.indexById[tileId];

  TapResult tap(String tileId) {
    final index = geometry.indexById[tileId];
    if (index == null || _status != GameStatus.playing || !_remaining.contains(index)) {
      return TapResult(TapOutcome.ignored, tileId: tileId);
    }
    if (!_free.contains(index)) {
      return TapResult(TapOutcome.blocked, tileId: tileId);
    }
    _remaining.remove(index);
    _free.remove(index);
    _refresh(geometry.affectedBy(index));
    _history.add(tileId);
    _moveCount++;

    final slot = _tray.length;
    final partnerSlot = _tray.indexWhere((other) => rules.matches(other, index));
    if (partnerSlot >= 0) {
      final partner = _tray.removeAt(partnerSlot);
      _matchedPairs++;
      _changed();
      return TapResult(
        TapOutcome.matched,
        tileId: tileId,
        slot: slot,
        partnerTileId: _id(partner),
        partnerSlot: partnerSlot,
      );
    }
    _tray.add(index);
    _changed();
    return TapResult(_status == GameStatus.trayFull ? TapOutcome.trayFull : TapOutcome.toTray, tileId: tileId, slot: slot);
  }

  /// After the tray filled up: puts every tray tile back where it was on the
  /// board and empties the tray, so play goes on. Pairs already cleared stay
  /// cleared, and a revive is not a move. Returns the returned tile ids in
  /// their former slot order, or null when the game is not lost with a full
  /// tray.
  List<String>? revive() {
    if (_status != GameStatus.trayFull || _tray.isEmpty) return null;
    final returned = List.of(_tray);
    _tray.clear();
    for (final index in returned) {
      _remaining.add(index);
    }
    // Returned tiles can block each other and their neighbours again.
    _refresh({for (final index in returned) ...[index, ...geometry.affectedBy(index)]});
    _history.add(reviveMarker);
    _changed();
    return [for (final index in returned) _id(index)];
  }

  void restart() {
    _remaining = TileMask.all(level.tiles.length);
    _tray.clear();
    _history.clear();
    _moveCount = 0;
    _matchedPairs = 0;
    _recomputeAll();
    _changed();
  }

  /// Re-applies saved taps (and [reviveMarker]s) in order. Stops at the
  /// first entry that is no longer legal and returns false, leaving the
  /// valid prefix applied.
  ///
  /// A pair-removal order (what the solver and generator produce) replays
  /// as taps `a1, b1, a2, b2, ...`: each first tile waits alone in the tray
  /// and its partner clears it at once.
  bool replay(List<String> taps) {
    for (final entry in taps) {
      final ok = entry == reviveMarker ? revive() != null : tap(entry).accepted;
      if (!ok) return false;
    }
    return true;
  }

  void _refresh(Iterable<int> indices) {
    for (final index in indices) {
      if (_availability.isFree(index, _remaining)) {
        _free.add(index);
      } else {
        _free.remove(index);
      }
    }
  }

  void _recomputeAll() {
    _free
      ..clear()
      ..addAll(_availability.freeTiles(_remaining));
  }

  void _changed() {
    if (_remaining.isEmpty && _tray.isEmpty) {
      _status = GameStatus.won;
    } else if (_tray.length >= trayCapacity || _free.isEmpty) {
      // A non-empty board always has a free tile; see GameStatus.trayFull.
      _status = GameStatus.trayFull;
    } else {
      _status = GameStatus.playing;
    }
    _cachedState = null;
  }
}

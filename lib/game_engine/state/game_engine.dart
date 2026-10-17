import '../campaign/seeded_random.dart';
import '../geometry/board_geometry.dart';
import '../geometry/tile_availability.dart';
import '../geometry/tile_mask.dart';
import '../models/level_definition.dart';
import '../models/level_rules.dart';
import '../models/tile_definition.dart';
import '../rules/match_rules.dart';
import '../validation/tray_solver.dart';
import 'game_actions.dart';
import 'game_state.dart';
import 'hint_finder.dart';
import 'shuffle_planner.dart';

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

/// Revives a level attempt allows (owner, 2026-10-17): after the second, a
/// full tray can only be restarted. Counted from the game's
/// [GameEngine.reviveMarker]s, so a resumed save keeps its count; Restart
/// starts over at 0 and Undo never gives one back.
const int kMaxRevivesPerLevel = 2;

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
/// places on the board and play goes on, at most [kMaxRevivesPerLevel] times
/// per level attempt (a restart starts over).
///
/// Helper actions (owner, 2026-10-17, 1.1.0), each with uses per game
/// ([kStartingCharges]: 1 undo, 1 hint, 1 shuffle; +1 with [grant], at most
/// [kMaxGrantsPerAction] per action, then the action is spent ([isSpent])):
/// [undo] takes the last tap back, [useHint] recommends a tap ([findHint]),
/// [shuffle] rearranges the board's symbols into a position that can be won.
/// Every action that changes the game or its uses is a marker in
/// [GameState.history], so [replay] restores uses, shuffles and all.
///
/// All state changes are synchronous, so rapid taps can never move a tile
/// twice; animations only replay what has already happened here.
class GameEngine {
  GameEngine({
    required this.level,
    required MatchRules rules,
    BoardGeometry? geometry,
    int? trayCapacity,
  }) : levelRules = rules,
       _rules = rules,
       trayCapacity = trayCapacity ?? level.rules.trayCapacity,
       assert((trayCapacity ?? level.rules.trayCapacity) >= 2, 'a tray must hold at least a pair'),
       geometry = geometry ?? BoardGeometry.build(level),
       _remaining = TileMask.all(level.tiles.length),
       _source = List.generate(level.tiles.length, (i) => i) {
    _availability = TileAvailabilityCalculator(this.geometry);
    _resetActions();
    _recomputeAll();
    _changed();
  }

  /// Tray slots of a level that does not set `rules.trayCapacity`.
  static const int defaultTrayCapacity = kDefaultTrayCapacity;

  /// Marks a [revive] in [GameState.history]. Never a tile id: tile ids
  /// are letters, digits, `_` and `-` only, and every marker starts with `!`.
  static const String reviveMarker = '!revive';

  /// Marks an [undo] (it takes back the last tap before it).
  static const String undoMarker = '!undo';

  /// Marks a used hint ([useHint]); the board does not change.
  static const String hintMarker = '!hint';

  /// Starts a [shuffle] marker: `!shuffle:<planner version>:<seed>`.
  static const String shuffleMarkerPrefix = '!shuffle:';

  /// Starts a [grant] marker: `!grant:<action>` (`GameAction.wire`).
  static const String grantMarkerPrefix = '!grant:';

  static String shuffleMarker(int seed) => '$shuffleMarkerPrefix${ShufflePlanner.version}:$seed';

  static String grantMarker(GameAction action) => '$grantMarkerPrefix${action.wire}';

  /// Arrangements a [shuffle] tries before it gives up.
  static const int shuffleAttempts = 8;

  final LevelDefinition level;

  /// The level's match keys, as dealt.
  final MatchRules levelRules;
  final BoardGeometry geometry;

  /// The match keys now: [levelRules] until a [shuffle] moves symbols.
  MatchRules get rules => _rules;
  MatchRules _rules;

  /// Tiles the tray holds before the game is lost: the level's
  /// `rules.trayCapacity` unless the constructor overrides it.
  final int trayCapacity;
  late final TileAvailabilityCalculator _availability;

  /// Tiles on the board.
  TileMask _remaining;
  final Set<int> _free = {};
  final List<int> _tray = [];

  /// Tapped tile ids and markers, in order.
  final List<String> _history = [];
  int _moveCount = 0;
  int _matchedPairs = 0;
  GameStatus _status = GameStatus.playing;
  GameState? _cachedState;

  /// For each tile, the level tile whose symbol it shows (a shuffle
  /// permutes the board's entries).
  final List<int> _source;
  LevelDefinition? _boardLevel;

  /// The winning tap order the last shuffle was built along (empty: none).
  List<int> _shuffleProof = const [];

  /// Taps that [undo] can take back, oldest first; a revive or a shuffle
  /// clears it (undo never crosses them).
  final List<_Move> _undoable = [];

  /// The [reviveMarker]s in [_history].
  int _revives = 0;
  final Map<GameAction, int> _left = {};
  final Map<GameAction, int> _used = {};

  /// The [grantMarkerPrefix] markers of each action in [_history].
  final Map<GameAction, int> _granted = {};

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
    actions: ActionCounts(
      undosLeft: _left[GameAction.undo]!,
      hintsLeft: _left[GameAction.hint]!,
      shufflesLeft: _left[GameAction.shuffle]!,
      undosUsed: _used[GameAction.undo]!,
      hintsUsed: _used[GameAction.hint]!,
      shufflesUsed: _used[GameAction.shuffle]!,
      undosGranted: _granted[GameAction.undo]!,
      hintsGranted: _granted[GameAction.hint]!,
      shufflesGranted: _granted[GameAction.shuffle]!,
    ),
    undoAvailable: undoAvailable,
  );

  /// A copy of the board's remaining-tile set, for the solver.
  TileMask get remainingMask => _remaining.copy();

  String _id(int index) => level.tiles[index].tileId;

  /// True while the tile is on the board.
  bool isRemaining(int index) => _remaining.contains(index);

  bool isFreeIndex(int index) => _free.contains(index);

  bool isInTray(int index) => _tray.contains(index);

  int? indexOf(String tileId) => geometry.indexById[tileId];

  /// The symbol tile [index] shows now (a shuffle may have changed it).
  String symbolCodeOf(int index) => level.tiles[_source[index]].symbolCode;

  /// The level tile whose symbol tile [index] shows now ([index] itself
  /// until a shuffle).
  int symbolSourceOf(int index) => _source[index];

  /// [level] with every tile showing its symbol now: [level] itself until a
  /// shuffle, so widgets that draw from a level can draw the shuffled board.
  LevelDefinition get boardLevel => _boardLevel ??= identical(_rules, levelRules)
      ? level
      : LevelDefinition(
          schemaVersion: level.schemaVersion,
          levelId: level.levelId,
          title: level.title,
          difficulty: level.difficulty,
          tileSetId: level.tileSetId,
          board: level.board,
          tiles: [
            for (final (i, tile) in level.tiles.indexed)
              TileDefinition(tileId: tile.tileId, symbolCode: symbolCodeOf(i), x: tile.x, y: tile.y, layer: tile.layer),
          ],
          rules: level.rules,
          backdrop: level.backdrop,
          faceColors: level.faceColors,
        );

  /// The winning tap order (tile indices) the last shuffle was built along;
  /// empty before one. Tiles taken since then are still listed.
  List<int> get shuffleProof => _shuffleProof;

  /// Uses of [action] left in this game.
  int usesLeft(GameAction action) => _left[action]!;

  /// Extra uses of [action] [grant] can still give in this game
  /// ([kMaxGrantsPerAction] in all; a restart starts over).
  int grantsLeft(GameAction action) {
    final granted = _granted[action]!;
    return granted >= kMaxGrantsPerAction ? 0 : kMaxGrantsPerAction - granted;
  }

  /// No use of [action] left and no [grant] to be had: it is over for this
  /// level attempt (until a restart).
  bool isSpent(GameAction action) => _left[action]! <= 0 && grantsLeft(action) <= 0;

  /// Revives used in this game (its [reviveMarker]s since the start or the
  /// last restart).
  int get revivesUsed => _revives;

  /// Revives this game still allows ([kMaxRevivesPerLevel] in all).
  int get revivesLeft => _revives >= kMaxRevivesPerLevel ? 0 : kMaxRevivesPerLevel - _revives;

  /// The game is lost with a full tray and a revive is left: [revive] works.
  bool get canRevive => _status == GameStatus.trayFull && _tray.isNotEmpty && revivesLeft > 0;

  /// The last tap can be taken back now, uses left aside: the game is in
  /// play and a tap was made since the start or the last revive or shuffle.
  bool get undoAvailable => _status == GameStatus.playing && _undoable.isNotEmpty;

  /// Whether the tap [undo] would take back cleared a pair (null: none).
  bool? get undoWouldUnmatch => _undoable.isEmpty ? null : _undoable.last.partner != null;

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
    final partnerSlot = _tray.indexWhere((other) => _rules.matches(other, index));
    if (partnerSlot >= 0) {
      final partner = _tray.removeAt(partnerSlot);
      _matchedPairs++;
      _undoable.add(_Move(index, slot, partner: partner, partnerSlot: partnerSlot));
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
    _undoable.add(_Move(index, slot));
    _changed();
    return TapResult(_status == GameStatus.trayFull ? TapOutcome.trayFull : TapOutcome.toTray, tileId: tileId, slot: slot);
  }

  /// Takes the last tap back, using one undo: the tile returns to its board
  /// place; if it had cleared a pair, its twin is back in its tray slot (and
  /// the pair is no longer cleared). Null when [undoAvailable] is false or
  /// no undo is left. The score is the caller's (`ScoreKeeper.undoMatch`).
  UndoResult? undo() {
    if (!undoAvailable || _left[GameAction.undo]! <= 0) return null;
    final move = _undoable.removeLast();
    final index = move.tile;
    final partner = move.partner;
    if (partner == null) {
      // Later taps were taken back first, so the tile is the tray's last.
      _tray.removeLast();
    } else {
      _tray.insert(move.partnerSlot!, partner);
      _matchedPairs--;
    }
    _remaining.add(index);
    // The returned tile can block its neighbours again.
    _refresh([index, ...geometry.affectedBy(index)]);
    _moveCount--;
    _spend(GameAction.undo);
    _history.add(undoMarker);
    _changed();
    return UndoResult(
      tileId: _id(index),
      fromSlot: move.slot,
      partnerTileId: partner == null ? null : _id(partner),
      partnerSlot: move.partnerSlot,
    );
  }

  /// The tap a hint would recommend now, without using one (pure; see
  /// [HintFinder]). Null when the game is not in play or no tap is safe.
  Hint? findHint({int maxNodes = HintFinder.defaultMaxNodes}) => HintFinder(this, maxNodes: maxNodes).find();

  /// Uses one hint: returns [findHint]'s tap, counted. Nothing is applied.
  /// Null (and no use spent) when there is no hint or no use left.
  Hint? useHint({int maxNodes = HintFinder.defaultMaxNodes}) {
    if (_status != GameStatus.playing || _left[GameAction.hint]! <= 0) return null;
    final hint = findHint(maxNodes: maxNodes);
    if (hint == null) return null;
    _spendHint();
    return hint;
  }

  void _spendHint() {
    _spend(GameAction.hint);
    _history.add(hintMarker);
    _changed();
  }

  /// The seed [shuffle] starts from by default: fixed for a position, so
  /// the same game shuffles the same way.
  int get defaultShuffleSeed => stableHash(['shuffle', level.levelId, _history.length]);

  /// The board holds at least two different symbols (match keys), so a
  /// shuffle can change something.
  bool get canShuffleBoard {
    String? first;
    for (final index in _remaining.indices) {
      final key = _rules.keyOf(index);
      if (first == null) {
        first = key;
      } else if (key != first) {
        return true;
      }
    }
    return false;
  }

  /// Rearranges which symbol sits on which board tile, using one shuffle:
  /// places, layers and tile ids stay, the tray is untouched, every symbol
  /// keeps its count. The new arrangement can be won from here, tray
  /// included: [ShufflePlanner] builds it along a winning tap order, which
  /// the solver's check ([TraySolver.check]) confirms. Tries up to
  /// [attempts] seeds derived from [seed] (default [defaultShuffleSeed])
  /// until one moves a symbol and passes; if none does, nothing changes and
  /// no use is spent. Undo never crosses a shuffle.
  ShuffleResult shuffle({int? seed, int attempts = shuffleAttempts}) {
    if (_status != GameStatus.playing) return const ShuffleResult(ShuffleOutcome.unavailable);
    if (_left[GameAction.shuffle]! <= 0) return const ShuffleResult(ShuffleOutcome.noCharges);
    if (!canShuffleBoard) return const ShuffleResult(ShuffleOutcome.nothingToShuffle);
    final base = seed ?? defaultShuffleSeed;
    final planner = ShufflePlanner(geometry: geometry, levelRules: levelRules);
    final tray = List.of(_tray);
    for (var attempt = 0; attempt < attempts; attempt++) {
      final seed = stableHash(['shuffle', base, attempt]);
      final plan = planner.plan(remaining: _remaining, tray: tray, source: _source, seed: seed);
      if (plan == null) continue;
      final keys = MatchRules.permuted(levelRules, plan.source);
      if (!_remaining.indices.any((i) => keys.keyOf(i) != _rules.keyOf(i))) continue;
      final solver = TraySolver.forRules(geometry, keys, capacity: trayCapacity);
      if (!solver.check(_remaining, plan.taps, tray: tray)) continue;
      final before = [for (final i in _remaining.indices) (i, symbolCodeOf(i))];
      _applyShuffle(plan);
      return ShuffleResult(
        ShuffleOutcome.shuffled,
        seed: plan.seed,
        attempts: attempt + 1,
        changes: {
          for (final (i, code) in before)
            if (code != symbolCodeOf(i)) _id(i): (code, symbolCodeOf(i)),
        },
      );
    }
    return ShuffleResult(ShuffleOutcome.failed, attempts: attempts);
  }

  void _applyShuffle(ShufflePlan plan) {
    for (final index in _remaining.indices) {
      _source[index] = plan.source[index];
    }
    _rules = MatchRules.permuted(levelRules, _source);
    _boardLevel = null;
    _shuffleProof = List.unmodifiable(plan.taps);
    _undoable.clear();
    _spend(GameAction.shuffle);
    _history.add(shuffleMarker(plan.seed));
    _changed();
  }

  /// Replays a saved shuffle: the arrangement [seed] gave (no search).
  bool _replayShuffle(int seed) {
    if (_status != GameStatus.playing || _left[GameAction.shuffle]! <= 0) return false;
    final plan = ShufflePlanner(
      geometry: geometry,
      levelRules: levelRules,
    ).plan(remaining: _remaining, tray: List.of(_tray), source: _source, seed: seed);
    if (plan == null) return false;
    _applyShuffle(plan);
    return true;
  }

  /// One more use of [action] (after a rewarded ad). False once the game is
  /// won or when [action] has no grant left ([grantsLeft]: at most
  /// [kMaxGrantsPerAction] per level attempt).
  bool grant(GameAction action) => grantsLeft(action) > 0 && _grant(action);

  /// [grant] without the limit: a save from a build without it (1.1.0+10 and
  /// earlier, when refills were unlimited) may hold more grants; it resumes
  /// with that action's grant used up instead of starting over.
  bool _grant(GameAction action) {
    if (_status == GameStatus.won) return false;
    _left[action] = _left[action]! + 1;
    _granted[action] = _granted[action]! + 1;
    _history.add(grantMarker(action));
    _changed();
    return true;
  }

  void _spend(GameAction action) {
    _left[action] = _left[action]! - 1;
    _used[action] = _used[action]! + 1;
  }

  void _resetActions() {
    _left.addAll(kStartingCharges);
    for (final action in GameAction.values) {
      _used[action] = 0;
      _granted[action] = 0;
    }
  }

  /// After the tray filled up: puts every tray tile back where it was on the
  /// board and empties the tray, so play goes on. Pairs already cleared stay
  /// cleared, and a revive is not a move. Returns the returned tile ids in
  /// their former slot order, or null when the game is not lost with a full
  /// tray or has no revive left ([canRevive]).
  List<String>? revive() => canRevive ? _revive() : null;

  /// [revive] without the limit: a save from a build without it (1.0, when
  /// Revive was unlimited) may hold more revives; it resumes with none left
  /// instead of starting over.
  List<String>? _revive() {
    if (_status != GameStatus.trayFull || _tray.isEmpty) return null;
    final returned = List.of(_tray);
    _tray.clear();
    for (final index in returned) {
      _remaining.add(index);
    }
    // Returned tiles can block each other and their neighbours again.
    _refresh({for (final index in returned) ...[index, ...geometry.affectedBy(index)]});
    _undoable.clear();
    _history.add(reviveMarker);
    _revives++;
    _changed();
    return [for (final index in returned) _id(index)];
  }

  /// A new game: the level as dealt, every action's uses (and its grant) back
  /// to the start.
  void restart() {
    _remaining = TileMask.all(level.tiles.length);
    _tray.clear();
    _history.clear();
    _moveCount = 0;
    _matchedPairs = 0;
    for (var i = 0; i < _source.length; i++) {
      _source[i] = i;
    }
    _rules = levelRules;
    _boardLevel = null;
    _shuffleProof = const [];
    _undoable.clear();
    _revives = 0;
    _resetActions();
    _recomputeAll();
    _changed();
  }

  /// Re-applies saved taps and markers in order (revives, undos, hints,
  /// shuffles from their seeds, granted uses). Stops at the first entry
  /// that is no longer legal (or not known) and returns false, leaving the
  /// valid prefix applied. Revives past [kMaxRevivesPerLevel] replay (a 1.0
  /// save, from before the limit): the game then has none left. So do grants
  /// past [kMaxGrantsPerAction] (a save from 1.1.0+10 or earlier): the
  /// action keeps the uses they gave and has no grant left.
  ///
  /// A pair-removal order (what the solver and generator produce) replays
  /// as taps `a1, b1, a2, b2, ...`: each first tile waits alone in the tray
  /// and its partner clears it at once.
  bool replay(List<String> taps) {
    for (final entry in taps) {
      if (!_replayEntry(entry)) return false;
    }
    return true;
  }

  bool _replayEntry(String entry) {
    if (!entry.startsWith('!')) return tap(entry).accepted;
    if (entry == reviveMarker) return _revive() != null;
    if (entry == undoMarker) return undo() != null;
    if (entry == hintMarker) {
      // Only the use counts: the hint itself is not needed again.
      if (_status != GameStatus.playing || _left[GameAction.hint]! <= 0) return false;
      _spendHint();
      return true;
    }
    if (entry.startsWith(grantMarkerPrefix)) {
      final action = GameAction.fromWire(entry.substring(grantMarkerPrefix.length));
      return action != null && _grant(action);
    }
    if (entry.startsWith(shuffleMarkerPrefix)) {
      final parts = entry.substring(shuffleMarkerPrefix.length).split(':');
      final seed = parts.length == 2 && parts[0] == '${ShufflePlanner.version}' ? int.tryParse(parts[1]) : null;
      return seed != null && _replayShuffle(seed);
    }
    return false;
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

/// A tap [GameEngine.undo] can take back.
class _Move {
  const _Move(this.tile, this.slot, {this.partner, this.partnerSlot});

  final int tile;

  /// The tray slot it went to (for a match: where it landed before clearing).
  final int slot;

  /// The tray tile it cleared, and that tile's slot then.
  final int? partner;
  final int? partnerSlot;
}

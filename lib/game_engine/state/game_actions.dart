/// The player's helper actions (owner, 2026-10-17, 1.1.0): Undo, Hint and
/// Shuffle, each with one use per level attempt and at most one more for a
/// rewarded ad ([kMaxGrantsPerAction]).
library;

enum GameAction {
  undo,
  hint,
  shuffle;

  /// Name in save markers (`!grant:undo`); never change it.
  String get wire => name;

  static GameAction? fromWire(String value) {
    for (final action in values) {
      if (action.wire == value) return action;
    }
    return null;
  }
}

/// Uses a level starts with (and starts over with on Restart).
const Map<GameAction, int> kStartingCharges = {GameAction.undo: 1, GameAction.hint: 1, GameAction.shuffle: 1};

/// Extra uses of one action a level attempt can get, each for a rewarded ad
/// (or free when no ad can be had while online) (owner, 2026-10-17). With
/// [kStartingCharges], each action is used at most twice per attempt: 1 free,
/// 1 after an ad; then it is spent and its button leaves the action bar.
/// Restart starts over; Revive changes nothing. Counted from the game's
/// `!grant:<action>` markers, so a resumed save keeps its count.
const int kMaxGrantsPerAction = 1;

/// Uses left, used and granted of each [GameAction] in one game.
class ActionCounts {
  const ActionCounts({
    required this.undosLeft,
    required this.hintsLeft,
    required this.shufflesLeft,
    this.undosUsed = 0,
    this.hintsUsed = 0,
    this.shufflesUsed = 0,
    this.undosGranted = 0,
    this.hintsGranted = 0,
    this.shufflesGranted = 0,
  });

  /// A new game: [kStartingCharges] left, none used (a test keeps the two
  /// equal; a const map lookup cannot build a const value).
  static const ActionCounts initial = ActionCounts(undosLeft: 1, hintsLeft: 1, shufflesLeft: 1);

  final int undosLeft;
  final int hintsLeft;
  final int shufflesLeft;
  final int undosUsed;
  final int hintsUsed;
  final int shufflesUsed;

  /// Extra uses given for rewarded ads (more than [kMaxGrantsPerAction] only
  /// in a save from a build without the limit).
  final int undosGranted;
  final int hintsGranted;
  final int shufflesGranted;

  int left(GameAction action) => switch (action) {
    GameAction.undo => undosLeft,
    GameAction.hint => hintsLeft,
    GameAction.shuffle => shufflesLeft,
  };

  int used(GameAction action) => switch (action) {
    GameAction.undo => undosUsed,
    GameAction.hint => hintsUsed,
    GameAction.shuffle => shufflesUsed,
  };

  int granted(GameAction action) => switch (action) {
    GameAction.undo => undosGranted,
    GameAction.hint => hintsGranted,
    GameAction.shuffle => shufflesGranted,
  };

  /// Extra uses of [action] a rewarded ad can still give in this game.
  int grantsLeft(GameAction action) =>
      granted(action) >= kMaxGrantsPerAction ? 0 : kMaxGrantsPerAction - granted(action);

  /// No use of [action] left and none to be had: its button is gone until a
  /// restart.
  bool isSpent(GameAction action) => left(action) <= 0 && grantsLeft(action) <= 0;

  @override
  bool operator ==(Object other) =>
      other is ActionCounts &&
      other.undosLeft == undosLeft &&
      other.hintsLeft == hintsLeft &&
      other.shufflesLeft == shufflesLeft &&
      other.undosUsed == undosUsed &&
      other.hintsUsed == hintsUsed &&
      other.shufflesUsed == shufflesUsed &&
      other.undosGranted == undosGranted &&
      other.hintsGranted == hintsGranted &&
      other.shufflesGranted == shufflesGranted;

  @override
  int get hashCode => Object.hash(
    undosLeft,
    hintsLeft,
    shufflesLeft,
    undosUsed,
    hintsUsed,
    shufflesUsed,
    undosGranted,
    hintsGranted,
    shufflesGranted,
  );

  @override
  String toString() =>
      'ActionCounts(left: $undosLeft/$hintsLeft/$shufflesLeft, used: $undosUsed/$hintsUsed/$shufflesUsed, '
      'granted: $undosGranted/$hintsGranted/$shufflesGranted)';
}

/// Why a [Hint] picked its tile, best first.
enum HintReason {
  /// Its twin waits in the tray: tapping it clears a pair now.
  completesPair,

  /// Every board tile of its symbol is free: taking two of them never hurts.
  safePair,

  /// The first tap of a winning order the solver found.
  solver,

  /// Any free tile that does not fill the tray (no better move was found).
  fallback,
}

/// A recommended next tap; nothing is applied.
class Hint {
  const Hint({required this.tileId, required this.reason, this.partnerTileId});

  /// The board tile to tap.
  final String tileId;
  final HintReason reason;

  /// The tile it pairs with when known: the tray tile it clears
  /// ([HintReason.completesPair]) or the board tile to tap next.
  final String? partnerTileId;

  @override
  bool operator ==(Object other) =>
      other is Hint && other.tileId == tileId && other.reason == reason && other.partnerTileId == partnerTileId;

  @override
  int get hashCode => Object.hash(tileId, reason, partnerTileId);

  @override
  String toString() => 'Hint($tileId, ${reason.name}${partnerTileId == null ? '' : ', twin $partnerTileId'})';
}

/// What an undo put back.
class UndoResult {
  const UndoResult({required this.tileId, required this.fromSlot, this.partnerTileId, this.partnerSlot});

  /// The tile that is back in its board place.
  final String tileId;

  /// The tray slot it had: its slot for a plain tap; for a tap that matched,
  /// the slot it landed in before the pair cleared (the tray's length before
  /// that tap, i.e. just after the tray's last tile now).
  final int fromSlot;

  /// For a tap that matched: the tray tile it had cleared, back in the tray.
  final String? partnerTileId;

  /// For a tap that matched: the tray slot [partnerTileId] is back in.
  final int? partnerSlot;

  bool get undidMatch => partnerTileId != null;
}

enum ShuffleOutcome {
  /// The board's symbols were rearranged.
  shuffled,

  /// Not now: the game is not in play (or, in the controller, the intro or
  /// the tutorial runs).
  unavailable,

  /// No shuffles left (a rewarded ad can grant one, unless it is spent).
  noCharges,

  /// The board has fewer than two different symbols: nothing would change.
  nothingToShuffle,

  /// No tried arrangement passed the solver; the board is unchanged.
  failed,
}

/// What a shuffle did.
class ShuffleResult {
  const ShuffleResult(this.outcome, {this.seed, this.attempts = 0, this.changes = const {}});

  final ShuffleOutcome outcome;

  /// The seed of the arrangement applied (saved in the game's history).
  final int? seed;

  /// Arrangements tried.
  final int attempts;

  /// Board tiles whose symbol changed: tile id → (old code, new code).
  final Map<String, (String from, String to)> changes;

  bool get shuffled => outcome == ShuffleOutcome.shuffled;
}

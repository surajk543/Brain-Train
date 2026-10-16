/// Lifecycle of a level being played.
enum GameStatus {
  playing,

  /// The board and the tray are empty.
  won,

  /// Lost: the tray filled up and its tiles do not match.
  ///
  /// With a tray, a non-empty board always has a free tile (the leftmost
  /// tile of the highest remaining layer), so a full tray is the only way to
  /// get stuck. An invalid level whose match keys have odd counts could also
  /// end with an empty board and unmatched tiles in the tray; that is
  /// reported as this status too.
  trayFull,
}

/// Two tile ids, e.g. a cleared pair (tray tile first, arriving tile second).
typedef TilePair = (String first, String second);

/// Immutable snapshot of a game for the UI layer.
class GameState {
  const GameState({
    required this.levelId,
    required this.remaining,
    required this.free,
    required this.tray,
    required this.trayCapacity,
    required this.moveCount,
    required this.matchedPairs,
    required this.totalPairs,
    required this.history,
    required this.status,
  });

  final String levelId;

  /// Tiles still on the board (not in the tray, not cleared).
  final Set<String> remaining;

  /// Board tiles that can be tapped now.
  final Set<String> free;

  /// Tiles waiting in the tray, slot 0 first. Packed: no gaps.
  final List<String> tray;
  final int trayCapacity;

  /// Accepted taps (every tile sent to the tray). Revives do not count.
  final int moveCount;

  /// Pairs cleared in the tray.
  final int matchedPairs;
  final int totalPairs;

  /// Accepted taps (tile ids) and revives (`GameEngine.reviveMarker`) in
  /// order, oldest first. Replaying them restores the game.
  final List<String> history;
  final GameStatus status;

  bool get isTrayFull => tray.length >= trayCapacity;
  double get progress => totalPairs == 0 ? 1 : matchedPairs / totalPairs;
}

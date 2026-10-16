/// Google Play Games Services as the app sees it (Android only). Optional:
/// the game plays the same signed out, offline or without it, and nothing
/// here is on the startup path.
library;

/// Whether the player is signed in to Play Games.
sealed class PlayGamesStatus {
  const PlayGamesStatus();
}

/// No Play Games here (iOS, a build without an app ID): the lobby shows no
/// Play Games buttons.
final class PlayGamesUnavailable extends PlayGamesStatus {
  const PlayGamesUnavailable();
}

final class PlayGamesSignedOut extends PlayGamesStatus {
  const PlayGamesSignedOut();
}

final class PlayGamesSignedIn extends PlayGamesStatus {
  const PlayGamesSignedIn(this.displayName);

  final String displayName;

  @override
  bool operator ==(Object other) => other is PlayGamesSignedIn && other.displayName == displayName;

  @override
  int get hashCode => displayName.hashCode;
}

/// How an interactive sign-in ended.
enum PlayGamesSignIn { signedIn, cancelled, failed }

abstract class PlayGames {
  /// Status changes; [current] is the latest.
  Stream<PlayGamesStatus> get status;
  PlayGamesStatus get current;

  /// Starts (or restarts) the silent sign-in check.
  void refresh();

  /// Google's sign-in dialog, when the player asks for Play Games.
  Future<PlayGamesSignIn> signIn();

  /// Opens Google's screen; false when it could not be opened.
  Future<bool> showAchievements();
  Future<bool> showLeaderboards();

  void dispose();
}

/// Play Games where there is none: always [PlayGamesUnavailable].
class UnavailablePlayGames implements PlayGames {
  const UnavailablePlayGames();

  @override
  Stream<PlayGamesStatus> get status => const Stream.empty();

  @override
  PlayGamesStatus get current => const PlayGamesUnavailable();

  @override
  void refresh() {}

  @override
  Future<PlayGamesSignIn> signIn() async => PlayGamesSignIn.failed;

  @override
  Future<bool> showAchievements() async => false;

  @override
  Future<bool> showLeaderboards() async => false;

  @override
  void dispose() {}
}

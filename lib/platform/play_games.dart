/// The platform's game service as the app sees it: Google Play Games
/// Services on Android, Apple Game Center on iOS. Optional: the game plays
/// the same signed out, offline or without it, and nothing here is on the
/// startup path.
library;

import 'game_services_ids.dart';

/// Which game service a [PlayGames] talks to.
enum GamesService { googlePlayGames, gameCenter }

/// Whether the player is signed in to Play Games.
sealed class PlayGamesStatus {
  const PlayGamesStatus();
}

/// No game service here (an Android build without a Play Games app ID,
/// another platform): the lobby shows no Play Games buttons.
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
  /// Google Play Games or Game Center (they take times in other units).
  GamesService get service;

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

  /// Unlocks [achievement] for the signed-in player; false when it could not
  /// (signed out, offline, an error, a timeout), never a throw. Game Center
  /// shows its completion banner only with [showBanner].
  Future<bool> unlock(GameAchievement achievement, {bool showBanner = true});

  /// Submits [value] to [leaderboard] for the signed-in player (the service
  /// keeps the player's best); false when it could not, never a throw.
  Future<bool> submitScore(GameLeaderboard leaderboard, int value);

  void dispose();
}

/// Play Games where there is none: always [PlayGamesUnavailable].
class UnavailablePlayGames implements PlayGames {
  const UnavailablePlayGames();

  @override
  GamesService get service => GamesService.googlePlayGames;

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
  Future<bool> unlock(GameAchievement achievement, {bool showBanner = true}) async => false;

  @override
  Future<bool> submitScore(GameLeaderboard leaderboard, int value) async => false;

  @override
  void dispose() {}
}

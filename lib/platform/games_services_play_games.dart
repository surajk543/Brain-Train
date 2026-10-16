import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';

import 'play_games.dart';

/// The plugin calls [GamesServicesPlayGames] makes, so tests can stand in.
class PlayGamesBackend {
  const PlayGamesBackend();

  /// The signed-in player's name, or null. Each subscription runs one silent
  /// sign-in check; an error means signed out.
  Stream<String?> get players => GameAuth.player.map((player) => player?.displayName);

  Future<void> signIn() => GameAuth.signIn();

  Future<void> showAchievements() => Achievements.showAchievements();

  Future<void> showLeaderboards() => Leaderboards.showLeaderboards();
}

/// [PlayGames] on the `games_services` plugin. The only file that imports
/// it; no call can throw, hang or block the app.
class GamesServicesPlayGames implements PlayGames {
  GamesServicesPlayGames({
    this.backend = const PlayGamesBackend(),
    this.callTimeout = const Duration(seconds: 10),
    this.signInTimeout = const Duration(minutes: 2),
  });

  final PlayGamesBackend backend;

  /// For opening a screen (the plugin answers once it is started).
  final Duration callTimeout;

  /// For sign-in, which waits for the player in Google's dialog.
  final Duration signInTimeout;

  final _status = StreamController<PlayGamesStatus>.broadcast();
  PlayGamesStatus _current = const PlayGamesSignedOut();
  StreamSubscription<String?>? _players;
  bool _disposed = false;

  @override
  Stream<PlayGamesStatus> get status => _status.stream;

  @override
  PlayGamesStatus get current => _current;

  @override
  void refresh() {
    if (_disposed) return;
    // The plugin checks once per subscription: listen again to check again.
    unawaited(_players?.cancel());
    try {
      _players = backend.players.listen(
        (name) => _set(name == null ? const PlayGamesSignedOut() : PlayGamesSignedIn(name)),
        onError: (Object error) {
          debugPrint('Play Games: not signed in ($error)');
          _set(const PlayGamesSignedOut());
        },
      );
    } on Object catch (error) {
      debugPrint('Play Games: sign-in check failed ($error)');
      _set(const PlayGamesSignedOut());
    }
  }

  void _set(PlayGamesStatus status) {
    if (_disposed || status == _current) return;
    _current = status;
    _status.add(status);
  }

  @override
  Future<PlayGamesSignIn> signIn() async {
    try {
      await backend.signIn().timeout(signInTimeout);
      refresh();
      return PlayGamesSignIn.signedIn;
    } on PlatformException catch (error) {
      // The plugin reports a dismissed dialog with an empty message, and real
      // failures (network, configuration) with one.
      debugPrint('Play Games: sign-in ended (${error.code}: ${error.message})');
      return (error.message ?? '').isEmpty ? PlayGamesSignIn.cancelled : PlayGamesSignIn.failed;
    } on Object catch (error) {
      debugPrint('Play Games: sign-in failed ($error)');
      return PlayGamesSignIn.failed;
    }
  }

  @override
  Future<bool> showAchievements() => _show('achievements', backend.showAchievements);

  @override
  Future<bool> showLeaderboards() => _show('leaderboards', backend.showLeaderboards);

  Future<bool> _show(String screen, Future<void> Function() open) async {
    try {
      await open().timeout(callTimeout);
      return true;
    } on Object catch (error) {
      debugPrint('Play Games: could not open $screen ($error)');
      return false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_players?.cancel());
    unawaited(_status.close());
  }
}

/// Play Games when this build and device have it (Android with an app ID,
/// see docs/PLAY_GAMES.md), else [UnavailablePlayGames]. Only a local
/// channel call: never waits for the network.
Future<PlayGames> createPlayGames() async {
  if (!Platform.isAndroid) return const UnavailablePlayGames();
  try {
    final configured = await const MethodChannel('brain_train/platform').invokeMethod<bool>('playGamesConfigured');
    return configured == true ? GamesServicesPlayGames() : const UnavailablePlayGames();
  } on Object catch (error) {
    debugPrint('Play Games: configuration check failed ($error)');
    return const UnavailablePlayGames();
  }
}

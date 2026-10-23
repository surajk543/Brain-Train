import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';

import 'game_services_ids.dart';
import 'play_games.dart';

/// The plugin calls [GamesServicesPlayGames] makes, so tests can stand in.
class PlayGamesBackend {
  const PlayGamesBackend();

  /// The signed-in player's name, or null. Each subscription runs one silent
  /// sign-in check; an error means signed out.
  Stream<String?> get players => GameAuth.player.map((player) => player?.displayName);

  /// Google's sign-in dialog; on iOS, Game Center's authentication.
  Future<void> signIn() => GameAuth.signIn();

  /// Starts the Play Games SDK (MainActivity; it no longer starts by itself at
  /// launch, so it never signs in a player who was not allowed). Android only.
  Future<void> initialize() => const MethodChannel('brain_train/platform').invokeMethod<bool>('initPlayGames');

  Future<void> showAchievements() => Achievements.showAchievements();

  Future<void> showLeaderboards() => Leaderboards.showLeaderboards();

  /// The plugin sends the ID of the platform it runs on.
  Future<void> unlock(GameAchievement achievement, {required bool showBanner}) => Achievements.unlock(
    achievement: Achievement(
      androidID: achievement.androidId ?? '',
      iOSID: achievement.iosId,
      showsCompletionBanner: showBanner,
    ),
  );

  Future<void> submitScore(GameLeaderboard leaderboard, int value) => Leaderboards.submitScore(
    score: Score(androidLeaderboardID: leaderboard.androidId, iOSLeaderboardID: leaderboard.iosId, value: value),
  );
}

/// [PlayGames] on the `games_services` plugin: Google Play Games on Android,
/// Game Center on iOS ([service]). The only file that imports it; no call can
/// throw, hang or block the app.
class GamesServicesPlayGames implements PlayGames {
  GamesServicesPlayGames({
    this.backend = const PlayGamesBackend(),
    this.service = GamesService.googlePlayGames,
    this.callTimeout = const Duration(seconds: 10),
    this.signInTimeout = const Duration(minutes: 2),
  });

  final PlayGamesBackend backend;

  @override
  final GamesService service;

  /// For opening a screen or reporting (the plugin answers once it is
  /// started).
  final Duration callTimeout;

  /// For sign-in, which waits for the player in Google's dialog (or Game
  /// Center's sheet).
  final Duration signInTimeout;

  final _status = StreamController<PlayGamesStatus>.broadcast();
  PlayGamesStatus _current = const PlayGamesSignedOut();
  StreamSubscription<String?>? _players;
  Future<void>? _initialized;
  bool _disposed = false;

  @override
  Stream<PlayGamesStatus> get status => _status.stream;

  @override
  PlayGamesStatus get current => _current;

  @override
  void refresh() => unawaited(_refresh());

  Future<void> _refresh() async {
    if (_disposed) return;
    try {
      await _start();
    } on Object catch (error) {
      debugPrint('Play Games: could not start ($error)');
      _set(const PlayGamesSignedOut());
      return;
    }
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
    if (service == GamesService.gameCenter) unawaited(_authenticate());
  }

  /// Game Center has no silent check of its own: the player stream only says
  /// whether GameKit has authenticated the player, which it does once the app
  /// asks (Apple's "Welcome back" banner when the device is signed in to Game
  /// Center, else Apple's sign-in sheet; GameKit offers that at most once per
  /// launch). Asking again later shows nothing; the stream reports the player.
  Future<void> _authenticate() async {
    try {
      await backend.signIn().timeout(signInTimeout);
    } on Object catch (error) {
      debugPrint('Game Center: not signed in ($error)');
    }
  }

  /// Starts the SDK once; a failed start is tried again next time. Game
  /// Center needs no start.
  Future<void> _start() async {
    if (service == GamesService.gameCenter) return;
    try {
      await (_initialized ??= backend.initialize().timeout(callTimeout));
    } on Object {
      _initialized = null;
      rethrow;
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
      await _start();
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
  Future<bool> showAchievements() => _call('open achievements', backend.showAchievements);

  @override
  Future<bool> showLeaderboards() => _call('open leaderboards', backend.showLeaderboards);

  @override
  Future<bool> unlock(GameAchievement achievement, {bool showBanner = true}) => _signedIn
      ? _call('unlock ${achievement.name}', () => backend.unlock(achievement, showBanner: showBanner))
      : Future.value(false);

  @override
  Future<bool> submitScore(GameLeaderboard leaderboard, int value) => _signedIn
      ? _call('submit ${leaderboard.name}', () => backend.submitScore(leaderboard, value))
      : Future.value(false);

  bool get _signedIn => !_disposed && _current is PlayGamesSignedIn;

  Future<bool> _call(String what, Future<void> Function() call) async {
    try {
      await call().timeout(callTimeout);
      return true;
    } on Object catch (error) {
      debugPrint('Play Games: could not $what ($error)');
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

/// The game service when this build and device have one: Game Center on iOS
/// (the Runner has the Game Center entitlement), Google Play Games on Android
/// with an app ID (see docs/PLAY_GAMES.md), else [UnavailablePlayGames]. Only
/// a local channel call: never waits for the network, never signs in.
Future<PlayGames> createPlayGames() async {
  if (Platform.isIOS) return GamesServicesPlayGames(service: GamesService.gameCenter);
  if (!Platform.isAndroid) return const UnavailablePlayGames();
  try {
    final configured = await const MethodChannel('brain_train/platform').invokeMethod<bool>('playGamesConfigured');
    return configured == true ? GamesServicesPlayGames() : const UnavailablePlayGames();
  } on Object catch (error) {
    debugPrint('Play Games: configuration check failed ($error)');
    return const UnavailablePlayGames();
  }
}

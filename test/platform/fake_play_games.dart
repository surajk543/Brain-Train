import 'dart:async';

import 'package:brain_train/platform/play_games.dart';

/// Scriptable [PlayGames]: records calls, can hold them open with [gate].
class FakePlayGames implements PlayGames {
  FakePlayGames([this._current = const PlayGamesSignedOut()]);

  final _status = StreamController<PlayGamesStatus>.broadcast();
  PlayGamesStatus _current;

  final List<String> calls = [];
  int refreshes = 0;
  bool disposed = false;

  PlayGamesSignIn signInResult = PlayGamesSignIn.signedIn;

  /// Whether a successful [signIn] also reports the player (as the plugin does).
  bool emitOnSignIn = true;
  bool showResult = true;

  /// When set, every call waits for it.
  Completer<void>? gate;

  void emit(PlayGamesStatus status) {
    _current = status;
    _status.add(status);
  }

  @override
  Stream<PlayGamesStatus> get status => _status.stream;

  @override
  PlayGamesStatus get current => _current;

  @override
  void refresh() => refreshes++;

  @override
  Future<PlayGamesSignIn> signIn() async {
    calls.add('signIn');
    await gate?.future;
    if (signInResult == PlayGamesSignIn.signedIn && emitOnSignIn) emit(const PlayGamesSignedIn('Tester'));
    return signInResult;
  }

  @override
  Future<bool> showAchievements() async {
    calls.add('achievements');
    await gate?.future;
    return showResult;
  }

  @override
  Future<bool> showLeaderboards() async {
    calls.add('leaderboards');
    await gate?.future;
    return showResult;
  }

  @override
  void dispose() => disposed = true;
}

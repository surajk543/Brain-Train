import 'dart:async';

import 'package:brain_train/platform/game_services_ids.dart';
import 'package:brain_train/platform/play_games.dart';

/// Scriptable [PlayGames]: records calls, can hold them open with [gate].
class FakePlayGames implements PlayGames {
  FakePlayGames([this._current = const PlayGamesSignedOut()]);

  final _status = StreamController<PlayGamesStatus>.broadcast();
  PlayGamesStatus _current;

  @override
  GamesService service = GamesService.googlePlayGames;

  final List<String> calls = [];
  int refreshes = 0;
  bool disposed = false;

  /// Reports, in order: unlocked achievements (with the banner flag) and
  /// submitted scores. Recorded even when they fail.
  final List<(GameAchievement, bool)> unlocks = [];
  final List<(GameLeaderboard, int)> scores = [];

  /// What [unlock] and [submitScore] answer; [reportError] makes them throw.
  bool reportResult = true;
  Object? reportError;

  /// The achievements unlocked, in order.
  List<GameAchievement> get unlocked => [for (final (achievement, _) in unlocks) achievement];

  /// The submitted scores by leaderboard (the last value of each).
  Map<GameLeaderboard, int> get submitted => {for (final (board, value) in scores) board: value};

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
  Future<bool> unlock(GameAchievement achievement, {bool showBanner = true}) async {
    unlocks.add((achievement, showBanner));
    if (reportError case final error?) throw error;
    return reportResult;
  }

  @override
  Future<bool> submitScore(GameLeaderboard leaderboard, int value) async {
    scores.add((leaderboard, value));
    if (reportError case final error?) throw error;
    return reportResult;
  }

  @override
  void dispose() => disposed = true;
}

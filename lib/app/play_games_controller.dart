import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/age_group.dart';
import '../data/progress_repository.dart';
import '../platform/game_services_ids.dart';
import '../platform/play_games.dart';
import 'play_games_reports.dart';

/// Play Games for the lobby (Google Play Games on Android, Game Center on
/// iOS): the sign-in status, the Achievements and Leaderboards actions, a
/// short notice when one fails, and the reports to the leaderboards and
/// achievements (every win, and once per app run after sign-in a catch-up of
/// the stored progress). Started by the lobby after its first frame (never on
/// the startup path); checks the sign-in again when the app comes back to
/// the foreground.
class PlayGamesController extends ChangeNotifier with WidgetsBindingObserver {
  PlayGamesController(this.playGames, {this.noticeDuration = const Duration(seconds: 4)});

  final PlayGames playGames;
  final Duration noticeDuration;

  static const failedNotice = "Couldn't connect to Google Play Games";
  static const gameCenterFailedNotice = "Couldn't connect to Game Center";

  StreamSubscription<PlayGamesStatus>? _statuses;
  Timer? _noticeTimer;
  String? _notice;
  bool _started = false;
  bool _blocked = false;
  bool _observing = false;
  bool _busy = false;
  bool _disposed = false;

  ProgressRepository? _progress;
  Map<String, String?> Function()? _difficulties;
  bool _caughtUp = false;

  /// Achievements unlocked (or being unlocked) in this app run: each is sent
  /// once (Game Center would show its banner again).
  final Set<GameAchievement> _unlocked = {};

  PlayGamesStatus get status => playGames.current;

  /// False without Play Games (no app ID on Android, another platform) or
  /// for a player under 13: the lobby shows no buttons.
  bool get available => !_blocked && status is! PlayGamesUnavailable;

  /// True while a sign-in or a screen is opening; taps are ignored meanwhile.
  bool get busy => _busy;

  /// A short failure message for the lobby footer, or null.
  String? get notice => _notice;

  /// Reports go out only for a signed-in player, and only after [start] let
  /// Play Games run (13+).
  bool get _reporting => _started && !_disposed && status is PlayGamesSignedIn;

  /// Where the reports read the wins ([ProgressRepository.completed]) and
  /// each level's tier by level id (the manifest's [difficulties]).
  /// AppServices attaches them.
  void attachProgress(ProgressRepository progress, {required Map<String, String?> Function() difficulties}) {
    _progress = progress;
    _difficulties = difficulties;
    _catchUp();
  }

  /// Runs the silent sign-in check, for 13+ players only: under 13 (or not
  /// answered yet) Play Games is never started, so it never signs in, and the
  /// buttons stay hidden (Play Families policy). Safe to call more than once.
  void start(AgeGroup? ageGroup) {
    if (_started || _disposed || !available) return;
    if (ageGroup != AgeGroup.thirteenPlus) {
      _blocked = true;
      notifyListeners();
      return;
    }
    _started = true;
    _statuses = playGames.status.listen((_) {
      _catchUp();
      notifyListeners();
    });
    playGames.refresh();
    _catchUp();
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object {
      // No binding (a pure Dart test): nothing to observe.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started && !_disposed) playGames.refresh();
  }

  Future<void> openAchievements() => _open(playGames.showAchievements);

  Future<void> openLeaderboards() => _open(playGames.showLeaderboards);

  /// Signs in first when needed (Google's dialog), then opens the screen.
  Future<void> _open(Future<bool> Function() show) async {
    if (_busy || _disposed || !available) return;
    _busy = true;
    notifyListeners();
    try {
      if (status is! PlayGamesSignedIn) {
        switch (await playGames.signIn()) {
          case PlayGamesSignIn.cancelled:
            return;
          case PlayGamesSignIn.failed:
            _showNotice(_failedNotice);
            return;
          case PlayGamesSignIn.signedIn:
            break;
        }
      }
      if (!await show()) _showNotice(_failedNotice);
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  String get _failedNotice => playGames.service == GamesService.gameCenter ? gameCenterFailedNotice : failedNotice;

  /// Reports a won game (replays too) once its record is saved: its tier's
  /// Best Score and Fastest Time, the totals of all wins and the achievements
  /// earned ([reportForWin]). Fire and forget: nothing unless a 13+ player is
  /// signed in, and a failure is only logged.
  void reportWin(WonGame game) {
    final progress = _progress;
    if (!_reporting || progress == null) return;
    try {
      unawaited(_send(reportForWin(game, progress.completed(), playGames.service), showBanners: true));
    } on Object catch (error) {
      debugPrint('Play Games: win report failed ($error)');
    }
  }

  /// Once per app run, at the first sign-in: what the stored progress has
  /// already earned ([reportForProgress]), unlocked without Game Center
  /// banners (most were unlocked before).
  void _catchUp() {
    final (progress, difficulties) = (_progress, _difficulties);
    if (_caughtUp || !_reporting || progress == null || difficulties == null) return;
    _caughtUp = true;
    try {
      unawaited(_send(reportForProgress(progress.completed(), difficulties(), playGames.service), showBanners: false));
    } on Object catch (error) {
      debugPrint('Play Games: catch-up failed ($error)');
    }
  }

  /// Sends [report] one call at a time; a failed unlock is tried again by a
  /// later report.
  Future<void> _send(PlayGamesReport report, {required bool showBanners}) async {
    // Claimed at once, so a report running meanwhile does not send them too.
    final unlocks = [
      for (final achievement in report.achievements)
        if (_unlocked.add(achievement)) achievement,
    ];
    for (final achievement in unlocks) {
      if (_disposed) return;
      if (!await _attempt(() => playGames.unlock(achievement, showBanner: showBanners))) _unlocked.remove(achievement);
    }
    for (final (leaderboard, value) in report.scores) {
      if (_disposed) return;
      await _attempt(() => playGames.submitScore(leaderboard, value));
    }
  }

  static Future<bool> _attempt(Future<bool> Function() call) async {
    try {
      return await call();
    } on Object catch (error) {
      debugPrint('Play Games: report failed ($error)');
      return false;
    }
  }

  void _showNotice(String text) {
    if (_disposed) return;
    _notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(noticeDuration, () {
      if (_disposed) return;
      _notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    unawaited(_statuses?.cancel());
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    playGames.dispose();
    super.dispose();
  }
}

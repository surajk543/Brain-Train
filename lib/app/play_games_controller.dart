import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/play_games.dart';

/// Play Games for the lobby: the sign-in status, the Achievements and
/// Leaderboards actions, and a short notice when one fails. Started by the
/// lobby after its first frame (never on the startup path); checks the
/// sign-in again when the app comes back to the foreground.
class PlayGamesController extends ChangeNotifier with WidgetsBindingObserver {
  PlayGamesController(this.playGames, {this.noticeDuration = const Duration(seconds: 4)});

  final PlayGames playGames;
  final Duration noticeDuration;

  static const failedNotice = "Couldn't connect to Google Play Games";

  StreamSubscription<PlayGamesStatus>? _statuses;
  Timer? _noticeTimer;
  String? _notice;
  bool _started = false;
  bool _observing = false;
  bool _busy = false;
  bool _disposed = false;

  PlayGamesStatus get status => playGames.current;

  /// False without Play Games (iOS, no app ID): the lobby shows no buttons.
  bool get available => status is! PlayGamesUnavailable;

  /// True while a sign-in or a screen is opening; taps are ignored meanwhile.
  bool get busy => _busy;

  /// A short failure message for the lobby footer, or null.
  String? get notice => _notice;

  /// Runs the silent sign-in check. Safe to call more than once.
  void start() {
    if (_started || _disposed || !available) return;
    _started = true;
    _statuses = playGames.status.listen((_) => notifyListeners());
    playGames.refresh();
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object {
      // No binding (a pure Dart test): nothing to observe.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) playGames.refresh();
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
            _showNotice(failedNotice);
            return;
          case PlayGamesSignIn.signedIn:
            break;
        }
      }
      if (!await show()) _showNotice(failedNotice);
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
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

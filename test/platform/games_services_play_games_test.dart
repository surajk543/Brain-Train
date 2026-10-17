import 'dart:async';

import 'package:brain_train/platform/game_services_ids.dart';
import 'package:brain_train/platform/games_services_play_games.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the plugin: every listen to [players] is a new check.
class _FakeBackend implements PlayGamesBackend {
  int listens = 0;
  int cancels = 0;
  StreamController<String?>? check;

  Future<void> Function() onSignIn = () async {};
  Future<void> Function() onShow = () async {};

  @override
  Stream<String?> get players {
    listens++;
    final controller = StreamController<String?>(onCancel: () => cancels++);
    check = controller;
    return controller.stream;
  }

  int initializes = 0;
  Future<void> Function() onInitialize = () async {};

  @override
  Future<void> initialize() {
    initializes++;
    return onInitialize();
  }

  int signIns = 0;

  @override
  Future<void> signIn() {
    signIns++;
    return onSignIn();
  }

  @override
  Future<void> showAchievements() => onShow();

  @override
  Future<void> showLeaderboards() => onShow();

  final List<String> reports = [];
  Future<void> Function() onReport = () async {};

  @override
  Future<void> unlock(GameAchievement achievement, {required bool showBanner}) {
    reports.add('unlock ${achievement.name} banner=$showBanner');
    return onReport();
  }

  @override
  Future<void> submitScore(GameLeaderboard leaderboard, int value) {
    reports.add('submit ${leaderboard.name} $value');
    return onReport();
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeBackend backend;
  late GamesServicesPlayGames playGames;

  setUp(() {
    backend = _FakeBackend();
    playGames = GamesServicesPlayGames(
      backend: backend,
      callTimeout: const Duration(milliseconds: 20),
      signInTimeout: const Duration(milliseconds: 20),
    );
  });

  tearDown(() => playGames.dispose());

  test('starts signed out', () {
    expect(playGames.current, const PlayGamesSignedOut());
  });

  group('silent sign-in', () {
    test('a player means signed in, and the change is announced', () async {
      final seen = <PlayGamesStatus>[];
      playGames.status.listen(seen.add);
      playGames.refresh();
      await _settle();
      backend.check!.add('Ann');
      await _settle();
      expect(playGames.current, const PlayGamesSignedIn('Ann'));
      expect(seen, [const PlayGamesSignedIn('Ann')]);
    });

    test('no player or an error means signed out', () async {
      playGames.refresh();
      await _settle();
      backend.check!.add('Ann');
      await _settle();
      backend.check!.add(null);
      await _settle();
      expect(playGames.current, const PlayGamesSignedOut());
      backend.check!.add('Ann');
      await _settle();
      backend.check!.addError(PlatformException(code: 'failed_to_authenticate'));
      await _settle();
      expect(playGames.current, const PlayGamesSignedOut());
    });

    test('refresh checks again on a new subscription', () async {
      playGames.refresh();
      playGames.refresh();
      await _settle();
      expect(backend.listens, 2);
      expect(backend.cancels, 1);
    });

    test('stays signed out while the check never answers', () async {
      playGames.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(playGames.current, const PlayGamesSignedOut());
      expect(await playGames.signIn(), PlayGamesSignIn.signedIn);
    });
  });

  group('SDK start', () {
    test('the SDK starts once, before the first check or sign-in', () async {
      expect(backend.initializes, 0);
      playGames.refresh();
      await _settle();
      playGames.refresh();
      await _settle();
      await playGames.signIn();
      expect(backend.initializes, 1);
    });

    test('a failed start reports signed out and is tried again next time', () async {
      backend.onInitialize = () async => throw PlatformException(code: 'no_play_services');
      playGames.refresh();
      await _settle();
      expect(playGames.current, const PlayGamesSignedOut());
      expect(backend.listens, 0);
      backend.onInitialize = () async {};
      playGames.refresh();
      await _settle();
      expect(backend.initializes, 2);
      expect(backend.listens, 1);
    });
  });

  group('signIn', () {
    test('success signs in and checks the player again', () async {
      expect(await playGames.signIn(), PlayGamesSignIn.signedIn);
      await _settle();
      expect(backend.listens, 1);
    });

    test('a dismissed dialog (empty message) is a cancel', () async {
      backend.onSignIn = () async => throw PlatformException(code: 'failed_to_authenticate', message: '');
      expect(await playGames.signIn(), PlayGamesSignIn.cancelled);
      backend.onSignIn = () async => throw PlatformException(code: 'failed_to_authenticate');
      expect(await playGames.signIn(), PlayGamesSignIn.cancelled);
    });

    test('an error with a message, a timeout or anything else is a failure', () async {
      backend.onSignIn = () async => throw PlatformException(code: 'failed_to_authenticate', message: 'Network error');
      expect(await playGames.signIn(), PlayGamesSignIn.failed);
      backend.onSignIn = () => Completer<void>().future;
      expect(await playGames.signIn(), PlayGamesSignIn.failed);
      backend.onSignIn = () async => throw StateError('boom');
      expect(await playGames.signIn(), PlayGamesSignIn.failed);
    });
  });

  group('screens', () {
    test('open: true', () async {
      expect(await playGames.showAchievements(), isTrue);
      expect(await playGames.showLeaderboards(), isTrue);
    });

    test('an error or a timeout: false, never a throw', () async {
      backend.onShow = () async => throw PlatformException(code: 'failed_to_show_achievements', message: 'x');
      expect(await playGames.showAchievements(), isFalse);
      backend.onShow = () => Completer<void>().future;
      expect(await playGames.showLeaderboards(), isFalse);
    });
  });

  test('after dispose, refresh and late events are ignored', () async {
    playGames.refresh();
    await _settle();
    final check = backend.check!;
    playGames.dispose();
    playGames.refresh();
    await _settle();
    expect(backend.listens, 1);
    check.add('Ann');
    await _settle();
    expect(playGames.current, const PlayGamesSignedOut());
  });

  group('reports', () {
    Future<void> signInAs(String name) async {
      playGames.refresh();
      await _settle();
      backend.check!.add(name);
      await _settle();
    }

    test('signed out: nothing reaches the plugin', () async {
      expect(await playGames.unlock(GameAchievement.firstWin), isFalse);
      expect(await playGames.submitScore(GameLeaderboard.totalScore, 100), isFalse);
      expect(backend.reports, isEmpty);
    });

    test('signed in: unlocks (with or without the banner) and scores go through', () async {
      await signInAs('Ann');
      expect(await playGames.unlock(GameAchievement.summit), isTrue);
      expect(await playGames.unlock(GameAchievement.firstWin, showBanner: false), isTrue);
      expect(await playGames.submitScore(GameLeaderboard.timeD3, 61234), isTrue);
      expect(backend.reports, [
        'unlock summit banner=true',
        'unlock firstWin banner=false',
        'submit timeD3 61234',
      ]);
    });

    test('an error or a timeout: false, never a throw', () async {
      await signInAs('Ann');
      backend.onReport = () async => throw PlatformException(code: 'failed_to_send_score', message: 'offline');
      expect(await playGames.submitScore(GameLeaderboard.levelsCompleted, 3), isFalse);
      backend.onReport = () => Completer<void>().future;
      expect(await playGames.unlock(GameAchievement.combo5), isFalse);
      backend.onReport = () async => throw StateError('boom');
      expect(await playGames.unlock(GameAchievement.combo5), isFalse);
    });

    test('after dispose: nothing', () async {
      await signInAs('Ann');
      playGames.dispose();
      expect(await playGames.unlock(GameAchievement.firstWin), isFalse);
      expect(backend.reports, isEmpty);
    });
  });

  group('Game Center', () {
    late GamesServicesPlayGames gameCenter;

    setUp(() {
      gameCenter = GamesServicesPlayGames(
        backend: backend,
        service: GamesService.gameCenter,
        callTimeout: const Duration(milliseconds: 20),
        signInTimeout: const Duration(milliseconds: 20),
      );
    });

    tearDown(() => gameCenter.dispose());

    test('the check asks GameKit to authenticate; no Play Games SDK start', () async {
      gameCenter.refresh();
      await _settle();
      expect(backend.initializes, 0);
      expect(backend.listens, 1);
      expect(backend.signIns, 1);
      backend.check!.add('Ann');
      await _settle();
      expect(gameCenter.current, const PlayGamesSignedIn('Ann'));
      expect(gameCenter.service, GamesService.gameCenter);
    });

    test('a failed or unanswered authentication is swallowed: signed out', () async {
      backend.onSignIn = () async => throw PlatformException(code: 'sign_in_unavailable', message: 'Settings');
      gameCenter.refresh();
      await _settle();
      backend.check!.add(null);
      await _settle();
      expect(gameCenter.current, const PlayGamesSignedOut());
      backend.onSignIn = () => Completer<void>().future;
      gameCenter.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(gameCenter.current, const PlayGamesSignedOut());
      expect(backend.signIns, 2);
    });
  });

  test('createPlayGames: unavailable off Android and iOS', () async {
    expect(await createPlayGames(), isA<UnavailablePlayGames>());
  });
}

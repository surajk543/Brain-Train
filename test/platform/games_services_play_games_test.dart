import 'dart:async';

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

  @override
  Future<void> signIn() => onSignIn();

  @override
  Future<void> showAchievements() => onShow();

  @override
  Future<void> showLeaderboards() => onShow();
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
      backend.check!.add('Ann');
      await _settle();
      expect(playGames.current, const PlayGamesSignedIn('Ann'));
      expect(seen, [const PlayGamesSignedIn('Ann')]);
    });

    test('no player or an error means signed out', () async {
      playGames.refresh();
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

  group('signIn', () {
    test('success signs in and checks the player again', () async {
      expect(await playGames.signIn(), PlayGamesSignIn.signedIn);
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
    final check = backend.check!;
    playGames.dispose();
    playGames.refresh();
    expect(backend.listens, 1);
    check.add('Ann');
    await _settle();
    expect(playGames.current, const PlayGamesSignedOut());
  });

  test('createPlayGames: unavailable off Android', () async {
    expect(await createPlayGames(), isA<UnavailablePlayGames>());
  });
}

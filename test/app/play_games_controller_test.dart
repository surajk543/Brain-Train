import 'dart:async';

import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../platform/fake_play_games.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlayGames fake;
  late PlayGamesController controller;

  setUp(() {
    fake = FakePlayGames();
    controller = PlayGamesController(fake, noticeDuration: const Duration(milliseconds: 30));
  });

  tearDown(() => controller.dispose());

  test('unavailable: not available, start does nothing', () {
    final none = PlayGamesController(const UnavailablePlayGames());
    expect(none.available, isFalse);
    none.start();
    none.dispose();
  });

  test('start runs the silent check once and follows the status', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    controller
      ..start()
      ..start();
    expect(fake.refreshes, 1);
    fake.emit(const PlayGamesSignedIn('Ann'));
    await _settle();
    expect(controller.status, const PlayGamesSignedIn('Ann'));
    expect(notified, 1);
  });

  test('resume checks again', () {
    controller.start();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(fake.refreshes, 2);
  });

  test('signed in: opens the screen', () async {
    fake.emit(const PlayGamesSignedIn('Ann'));
    await controller.openAchievements();
    await controller.openLeaderboards();
    expect(fake.calls, ['achievements', 'leaderboards']);
    expect(controller.notice, isNull);
  });

  test('signed out: signs in, then opens the screen', () async {
    await controller.openAchievements();
    expect(fake.calls, ['signIn', 'achievements']);
  });

  test('opens the screen after sign-in even before a status event', () async {
    fake.emitOnSignIn = false;
    await controller.openLeaderboards();
    expect(fake.calls, ['signIn', 'leaderboards']);
  });

  test('cancelled sign-in: nothing else, no notice', () async {
    fake.signInResult = PlayGamesSignIn.cancelled;
    await controller.openAchievements();
    expect(fake.calls, ['signIn']);
    expect(controller.notice, isNull);
  });

  test('failed sign-in or screen: notice, then it clears', () async {
    fake.signInResult = PlayGamesSignIn.failed;
    await controller.openAchievements();
    expect(fake.calls, ['signIn']);
    expect(controller.notice, PlayGamesController.failedNotice);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.notice, isNull);

    fake
      ..signInResult = PlayGamesSignIn.signedIn
      ..showResult = false;
    await controller.openLeaderboards();
    expect(controller.notice, PlayGamesController.failedNotice);
  });

  test('taps during a call are ignored', () async {
    fake.gate = Completer<void>();
    final first = controller.openAchievements();
    expect(controller.busy, isTrue);
    unawaited(controller.openAchievements());
    unawaited(controller.openLeaderboards());
    fake.gate!.complete();
    await first;
    expect(fake.calls, ['signIn', 'achievements']);
    expect(controller.busy, isFalse);
  });

  test('a resume during sign-in still opens one screen', () async {
    controller.start();
    fake.gate = Completer<void>();
    final open = controller.openAchievements();
    await _settle();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    fake.gate!.complete();
    await open;
    expect(fake.calls, ['signIn', 'achievements']);
    expect(fake.refreshes, 2);
  });

  test('notice timer after dispose is harmless', () async {
    final local = PlayGamesController(FakePlayGames()..signInResult = PlayGamesSignIn.failed,
        noticeDuration: const Duration(milliseconds: 10));
    await local.openAchievements();
    expect(local.notice, isNotNull);
    local.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test('dispose disposes the PlayGames', () {
    final local = FakePlayGames();
    PlayGamesController(local).dispose();
    expect(local.disposed, isTrue);
  });
}

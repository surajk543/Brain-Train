import 'dart:async';
import 'dart:convert';

import 'package:brain_train/app/app_update_controller.dart';
import 'package:brain_train/content/app_update_config.dart';
import 'package:brain_train/data/app_update_cache.dart';
import 'package:brain_train/platform/app_updates.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_app_updater.dart';

AppUpdateFetch _found(Map<String, Object?> json) =>
    AppUpdateFetch.found(AppUpdateConfig.tryParse(json)!, jsonEncode(json));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAppUpdater updater;
  late AppUpdateCache cache;
  late AppUpdateFetch Function() remote;
  late int fetches;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = await AppUpdateCache.open();
    updater = FakeAppUpdater(build: 4);
    remote = () => const AppUpdateFetch.failed();
    fetches = 0;
  });

  AppUpdateController controller({Duration timeout = const Duration(seconds: 5)}) {
    final controller = AppUpdateController(
      updater: updater,
      fetch: () async {
        fetches++;
        return remote();
      },
      cache: cache,
      checkTimeout: timeout,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('up to date: no card', () async {
    remote = () => _found(androidNotice(latest: 4, min: 1));
    final updates = controller();
    await updates.check();
    expect(updates.prompt, AppUpdatePrompt.none);
  });

  test('a newer build: optional, with the store page and message', () async {
    remote = () => _found(androidNotice(latest: 5, min: 1, message: 'Fresh levels'));
    final updates = controller();
    await updates.check();
    expect(updates.prompt, const AppUpdatePrompt(AppUpdateNeed.optional, storeUrl: kTestStoreUrl, message: 'Fresh levels'));
  });

  test('below the minimum: required', () async {
    remote = () => _found(androidNotice(latest: 6, min: 5));
    final updates = controller();
    await updates.check();
    expect(updates.prompt.need, AppUpdateNeed.required);
  });

  test('the fetched notice is kept; offline later it still applies', () async {
    remote = () => _found(androidNotice(latest: 6, min: 5));
    await controller().check();
    expect(AppUpdateConfig.tryDecode(cache.read()), AppUpdateConfig.tryParse(androidNotice(latest: 6, min: 5)));

    // Next launch, offline.
    remote = () => const AppUpdateFetch.failed();
    final offline = controller();
    await offline.check();
    expect(offline.prompt.need, AppUpdateNeed.required);
  });

  test('offline with nothing kept: no card', () async {
    final updates = controller();
    await updates.check();
    expect(updates.prompt, AppUpdatePrompt.none);
  });

  test('the kept notice applies before the fetch answers; a slow fetch times out', () async {
    await cache.write(jsonEncode(androidNotice(latest: 6, min: 5)));
    final never = Completer<AppUpdateFetch>();
    final updates = AppUpdateController(
      updater: updater,
      fetch: () => never.future,
      cache: cache,
      checkTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(updates.dispose);
    final seen = <AppUpdateNeed>[];
    updates.addListener(() => seen.add(updates.prompt.need));
    final checking = updates.check();
    await Future<void>.delayed(Duration.zero);
    expect(updates.prompt.need, AppUpdateNeed.required);
    await checking;
    expect(updates.prompt.need, AppUpdateNeed.required);
    expect(seen.first, AppUpdateNeed.required);
  });

  test('a notice removed from the host is forgotten; a malformed one keeps the last good', () async {
    await cache.write(jsonEncode(androidNotice(latest: 6, min: 5)));
    remote = () => const AppUpdateFetch.invalid();
    final malformed = controller();
    await malformed.check();
    expect(malformed.prompt.need, AppUpdateNeed.required);
    expect(cache.read(), isNotNull);

    remote = () => const AppUpdateFetch.missing();
    await malformed.check();
    expect(malformed.prompt, AppUpdatePrompt.none);
    expect(cache.read(), isNull);
  });

  test('a garbled kept notice is ignored', () async {
    await cache.write('{"schemaVersion": 1, "android": {');
    final updates = controller();
    await updates.check();
    expect(updates.prompt, AppUpdatePrompt.none);
  });

  test('no build number or no platform: nothing is fetched or shown', () async {
    remote = () => _found(androidNotice(latest: 9, min: 9));
    updater.build = null;
    final noBuild = controller();
    await noBuild.check();
    expect(noBuild.prompt, AppUpdatePrompt.none);
    expect(fetches, 0);

    final unavailable = AppUpdateController(updater: const UnavailableAppUpdater(), fetch: () async => remote());
    addTearDown(unavailable.dispose);
    unavailable.start();
    await Future<void>.delayed(Duration.zero);
    expect(unavailable.prompt, AppUpdatePrompt.none);
    expect(fetches, 0);
  });

  test('start checks once; coming back to the foreground checks again', () async {
    remote = () => _found(androidNotice(latest: 4, min: 1));
    final updates = controller()
      ..start()
      ..start();
    await Future<void>.delayed(Duration.zero);
    await updates.check();
    final before = fetches;
    updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await updates.check();
    expect(fetches, greaterThan(before));
  });

  group('optional card', () {
    setUp(() => remote = () => _found(androidNotice(latest: 5, min: 1)));

    test('Later hides it for this launch, even after another check', () async {
      final updates = controller();
      await updates.check();
      updates.later();
      expect(updates.prompt, AppUpdatePrompt.none);
      updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await updates.check();
      expect(updates.prompt, AppUpdatePrompt.none);

      // The next launch asks again.
      final next = controller();
      await next.check();
      expect(next.prompt.need, AppUpdateNeed.optional);
    });

    test('Update opens the store page and the card goes', () async {
      final updates = controller();
      await updates.check();
      await updates.update();
      expect(updater.launches, [kTestStoreUrl]);
      expect(updates.prompt, AppUpdatePrompt.none);
    });

    test('nothing opened: the card stays with a note', () async {
      updater.result = AppUpdateLaunch.failed;
      final updates = controller();
      await updates.check();
      await updates.update();
      expect(updates.prompt.need, AppUpdateNeed.optional);
      expect(updates.launchFailed, isTrue);
    });

    test('Later does not hide a required update that comes after it', () async {
      final updates = controller();
      await updates.check();
      updates.later();
      remote = () => _found(androidNotice(latest: 6, min: 5));
      await updates.check();
      expect(updates.prompt.need, AppUpdateNeed.required);
    });
  });

  group('required card', () {
    setUp(() => remote = () => _found(androidNotice(latest: 6, min: 5)));

    test('Later and Update leave it up', () async {
      final updates = controller();
      await updates.check();
      updates.later();
      expect(updates.prompt.need, AppUpdateNeed.required);
      await updates.update();
      expect(updater.launches, [kTestStoreUrl]);
      expect(updates.prompt.need, AppUpdateNeed.required);
      updater.result = AppUpdateLaunch.declined;
      await updates.update();
      expect(updates.prompt.need, AppUpdateNeed.required);
    });

    test('one launch at a time; back in the foreground Update works again', () async {
      final updates = controller();
      await updates.check();
      updater.gate = Completer<void>();
      unawaited(updates.update());
      await Future<void>.delayed(Duration.zero);
      expect(updates.launching, isTrue);
      unawaited(updates.update());
      await Future<void>.delayed(Duration.zero);
      expect(updater.launches, hasLength(1));
      updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(updates.launching, isFalse);
      updater.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(updates.launching, isFalse);
    });
  });
}

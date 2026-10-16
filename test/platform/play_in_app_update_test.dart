import 'dart:async';

import 'package:brain_train/content/app_update_config.dart';
import 'package:brain_train/platform/app_updates.dart';
import 'package:brain_train/platform/play_in_app_update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_app_updater.dart';

/// Stands in for the plugin and the platform channel.
class _FakeBackend implements AppUpdateBackend {
  Future<int?> Function() build = () async => 4;
  Future<PlayUpdateAvailability> Function() check = () async => PlayUpdateAvailability.none;
  PlayUpdateResult result = PlayUpdateResult.accepted;

  /// Links that open; any other one fails.
  Set<String> opens = {};
  final List<String> calls = [];

  @override
  Future<int?> installedBuild() => build();

  @override
  Future<PlayUpdateAvailability> checkPlay() {
    calls.add('check');
    return check();
  }

  @override
  Future<PlayUpdateResult> performImmediate() async {
    calls.add('immediate');
    return result;
  }

  @override
  Future<bool> openUri(Uri uri) async {
    calls.add('open $uri');
    return opens.contains(uri.scheme);
  }
}

const _market = 'market://details?id=com.sungamestudio.braintrain';

void main() {
  late _FakeBackend backend;

  setUp(() => backend = _FakeBackend());

  PlayInAppUpdater updater([UpdatePlatform platform = UpdatePlatform.android]) =>
      PlayInAppUpdater(platform: platform, backend: backend, callTimeout: const Duration(milliseconds: 30));

  group('Android', () {
    test("Play's immediate update when Play has one", () async {
      backend.check = () async => PlayUpdateAvailability.immediate;
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.started);
      expect(backend.calls, ['check', 'immediate']);
    });

    test('an update already running resumes', () async {
      backend.check = () async => PlayUpdateAvailability.inProgress;
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.started);
    });

    test('declined in Play: no store page', () async {
      backend
        ..check = (() async => PlayUpdateAvailability.immediate)
        ..result = PlayUpdateResult.declined;
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.declined);
      expect(backend.calls, ['check', 'immediate']);
    });

    test('no Play update: the Play Store app, else the web page', () async {
      backend.opens = {'market', 'https'};
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.openedStore);
      expect(backend.calls, ['check', 'open $_market']);

      backend
        ..calls.clear()
        ..opens = {'https'};
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.openedStore);
      expect(backend.calls, ['check', 'open $_market', 'open $kTestStoreUrl']);
    });

    test('Play errors, hangs or fails: the store page instead', () async {
      backend.opens = {'market'};
      for (final check in <Future<PlayUpdateAvailability> Function()>[
        () async => throw PlatformException(code: 'TASK_FAILURE'),
        () async => throw MissingPluginException(),
        () => Completer<PlayUpdateAvailability>().future,
      ]) {
        backend.check = check;
        expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.openedStore);
      }
      backend
        ..check = (() async => PlayUpdateAvailability.immediate)
        ..result = PlayUpdateResult.failed
        ..calls.clear();
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.openedStore);
      expect(backend.calls, ['check', 'immediate', 'open $_market']);
    });

    test('nothing opens: failed', () async {
      expect(await updater().launch(storeUrl: kTestStoreUrl), AppUpdateLaunch.failed);
      expect(await updater().launch(storeUrl: ''), AppUpdateLaunch.failed);
    });
  });

  test('iOS opens the store page only', () async {
    backend.opens = {'https'};
    const appStore = 'https://apps.apple.com/app/id123';
    expect(await updater(UpdatePlatform.ios).launch(storeUrl: appStore), AppUpdateLaunch.openedStore);
    expect(backend.calls, ['open $appStore']);
    expect(await updater(UpdatePlatform.ios).launch(storeUrl: ''), AppUpdateLaunch.failed);
  });

  test('build number: unknown on error or timeout', () async {
    expect(await updater().installedBuild(), 4);
    backend.build = () async => throw MissingPluginException();
    expect(await updater().installedBuild(), isNull);
    backend.build = () => Completer<int?>().future;
    expect(await updater().installedBuild(), isNull);
  });

  test('store links', () {
    expect(storeLaunchUris(kTestStoreUrl, UpdatePlatform.android).map((u) => '$u'), [_market, kTestStoreUrl]);
    expect(storeLaunchUris(kTestStoreUrl, UpdatePlatform.ios).map((u) => '$u'), [kTestStoreUrl]);
    expect(storeLaunchUris('https://example.com/app', UpdatePlatform.android).map((u) => '$u'), ['https://example.com/app']);
    expect(storeLaunchUris('https://play.google.com/store/apps/details', UpdatePlatform.android).map((u) => '$u'), [
      'https://play.google.com/store/apps/details',
    ]);
    expect(storeLaunchUris('', UpdatePlatform.android), isEmpty);
    expect(storeLaunchUris('http://play.google.com/x', UpdatePlatform.android), isEmpty);
  });
}

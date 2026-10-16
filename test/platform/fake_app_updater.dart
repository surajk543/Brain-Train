import 'dart:async';

import 'package:brain_train/content/app_update_config.dart';
import 'package:brain_train/platform/app_updates.dart';

/// Scriptable [AppUpdater]: a fixed build number; records [launch]es, which
/// end with [result] (or wait for [gate]).
class FakeAppUpdater implements AppUpdater {
  FakeAppUpdater({this.build = 4, this.platform = UpdatePlatform.android});

  int? build;

  @override
  UpdatePlatform? platform;

  AppUpdateLaunch result = AppUpdateLaunch.openedStore;

  /// When set, [launch] waits for it (the store or Play is open meanwhile).
  Completer<void>? gate;

  final List<String> launches = [];

  @override
  Future<int?> installedBuild() async => build;

  @override
  Future<AppUpdateLaunch> launch({required String storeUrl}) async {
    launches.add(storeUrl);
    await gate?.future;
    return result;
  }
}

const String kTestStoreUrl = 'https://play.google.com/store/apps/details?id=com.sungamestudio.braintrain';

/// A notice JSON for Android with [latest] and [min].
Map<String, Object?> androidNotice({required int latest, required int min, String storeUrl = kTestStoreUrl, String? message}) => {
  'schemaVersion': 1,
  'android': {
    'latestVersionCode': latest,
    'minVersionCode': min,
    'storeUrl': storeUrl,
    'message': ?message,
  },
};

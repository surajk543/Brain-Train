import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../content/app_update_config.dart';
import 'app_updates.dart';

/// What Google Play says about an update for this install.
enum PlayUpdateAvailability {
  /// Play has a newer build and allows the immediate (full-screen) flow.
  immediate,

  /// An immediate update was started earlier and is still running.
  inProgress,

  /// Nothing Play can install now (none yet, flow not allowed).
  none,
}

/// How Google Play's immediate update flow ended.
enum PlayUpdateResult { accepted, declined, failed }

/// The plugin and channel calls [PlayInAppUpdater] makes, so tests can
/// stand in.
class AppUpdateBackend {
  const AppUpdateBackend();

  Future<int?> installedBuild() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber.trim());

  Future<PlayUpdateAvailability> checkPlay() async {
    final info = await InAppUpdate.checkForUpdate();
    return switch (info.updateAvailability) {
      UpdateAvailability.developerTriggeredUpdateInProgress => PlayUpdateAvailability.inProgress,
      UpdateAvailability.updateAvailable when info.immediateUpdateAllowed => PlayUpdateAvailability.immediate,
      _ => PlayUpdateAvailability.none,
    };
  }

  Future<PlayUpdateResult> performImmediate() async => switch (await InAppUpdate.performImmediateUpdate()) {
    AppUpdateResult.success => PlayUpdateResult.accepted,
    AppUpdateResult.userDeniedUpdate => PlayUpdateResult.declined,
    AppUpdateResult.inAppUpdateFailed => PlayUpdateResult.failed,
  };

  /// Opens [uri] in the app that handles it (MainActivity / AppDelegate,
  /// `brain_train/platform`); false when nothing could.
  Future<bool> openUri(Uri uri) async =>
      await const MethodChannel('brain_train/platform').invokeMethod<bool>('openUrl', {'url': uri.toString()}) ??
      false;
}

/// [AppUpdater] on Google Play In-App Updates (`in_app_update`, Android)
/// and the store page. The only file that imports the plugin; no call can
/// throw or block the app.
class PlayInAppUpdater implements AppUpdater {
  PlayInAppUpdater({
    required this.platform,
    this.backend = const AppUpdateBackend(),
    this.callTimeout = const Duration(seconds: 5),
  });

  @override
  final UpdatePlatform platform;

  final AppUpdateBackend backend;

  /// For the build number, Play's check and opening a link. Play's update
  /// screen waits for the player, so it has none.
  final Duration callTimeout;

  @override
  Future<int?> installedBuild() async {
    try {
      return await backend.installedBuild().timeout(callTimeout);
    } on Object catch (error) {
      debugPrint('App update: build number unknown ($error)');
      return null;
    }
  }

  @override
  Future<AppUpdateLaunch> launch({required String storeUrl}) async {
    if (platform == UpdatePlatform.android) {
      final play = await _play();
      if (play != null) return play;
    }
    for (final uri in storeLaunchUris(storeUrl, platform)) {
      try {
        if (await backend.openUri(uri).timeout(callTimeout)) return AppUpdateLaunch.openedStore;
      } on Object catch (error) {
        debugPrint('App update: could not open $uri ($error)');
      }
    }
    return AppUpdateLaunch.failed;
  }

  /// Google Play's immediate update, or null when Play cannot run one here
  /// (not installed from Play, no update yet, emulator without Play, an
  /// error): the store page opens instead.
  Future<AppUpdateLaunch?> _play() async {
    try {
      final availability = await backend.checkPlay().timeout(callTimeout);
      if (availability == PlayUpdateAvailability.none) return null;
      return switch (await backend.performImmediate()) {
        PlayUpdateResult.accepted => AppUpdateLaunch.started,
        PlayUpdateResult.declined => AppUpdateLaunch.declined,
        PlayUpdateResult.failed => null,
      };
    } on Object catch (error) {
      debugPrint('App update: Google Play update unavailable ($error)');
      return null;
    }
  }
}

/// Updates on Android and iOS, else [UnavailableAppUpdater]. Creating it
/// calls nothing: the lobby checks after its first frame.
AppUpdater createAppUpdater() {
  if (Platform.isAndroid) return PlayInAppUpdater(platform: UpdatePlatform.android);
  if (Platform.isIOS) return PlayInAppUpdater(platform: UpdatePlatform.ios);
  return const UnavailableAppUpdater();
}

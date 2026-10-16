/// Updating the app from the lobby's update card (docs/APP_UPDATES.md): the
/// installed build number and the "Update" action. Pure Dart; the plugin
/// lives in `play_in_app_update.dart`. Nothing here is on the startup path.
library;

import '../content/app_update_config.dart';

/// How an "Update" tap ended.
enum AppUpdateLaunch {
  /// Google Play's in-app update ran (the app restarts once it is installed).
  started,

  /// The store page opened.
  openedStore,

  /// The player said no in Google Play's update screen.
  declined,

  /// Nothing could be opened (no Play, no store page, an error).
  failed,
}

abstract class AppUpdater {
  /// Whose rule in the notice applies here; null where updates are not
  /// offered (tests, desktop): the lobby then never asks.
  UpdatePlatform? get platform;

  /// The installed build number (Android `versionCode`, iOS
  /// `CFBundleVersion`), or null when it is unknown or not a number.
  Future<int?> installedBuild();

  /// Starts the update. Android: Google Play's in-app update when Play has
  /// one for this install, else [storeUrl]. iOS: [storeUrl]. Never throws.
  Future<AppUpdateLaunch> launch({required String storeUrl});
}

/// Where there are no updates: never asks, opens nothing.
class UnavailableAppUpdater implements AppUpdater {
  const UnavailableAppUpdater();

  @override
  UpdatePlatform? get platform => null;

  @override
  Future<int?> installedBuild() async => null;

  @override
  Future<AppUpdateLaunch> launch({required String storeUrl}) async => AppUpdateLaunch.failed;
}

/// The links to try, in order, to open [storeUrl] on [platform]. A Google
/// Play page opens in the Play Store app (`market://`) first, then as the
/// https page; anything else only as given. Only https store pages (the
/// notice drops others); empty for none.
List<Uri> storeLaunchUris(String storeUrl, UpdatePlatform platform) {
  final page = Uri.tryParse(storeUrl);
  if (page == null || page.scheme != 'https' || page.host.isEmpty) return const [];
  final id = page.queryParameters['id'];
  if (platform == UpdatePlatform.android &&
      page.host == 'play.google.com' &&
      page.path == '/store/apps/details' &&
      id != null &&
      id.isNotEmpty) {
    return [Uri(scheme: 'market', host: 'details', queryParameters: {'id': id}), page];
  }
  return [page];
}

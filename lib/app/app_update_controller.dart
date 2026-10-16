import 'dart:async';

import 'package:flutter/widgets.dart';

import '../content/app_update_config.dart';
import '../data/app_update_cache.dart';
import '../platform/app_updates.dart';

/// The lobby's update card (docs/APP_UPDATES.md): which card to show, if
/// any, and its Update and Later actions.
///
/// Started by the lobby after its first frame (never on the startup path):
/// it applies the notice kept on the device at once (so a required update
/// holds offline), then fetches the current one with a [checkTimeout], and
/// checks again whenever the app comes back to the foreground. Nothing it
/// does can throw.
class AppUpdateController extends ChangeNotifier with WidgetsBindingObserver {
  AppUpdateController({
    required this.updater,
    this.fetch,
    this.cache,
    this.checkTimeout = const Duration(seconds: 5),
  });

  final AppUpdater updater;

  /// Fetches the current notice; null never fetches (tests, no network).
  final Future<AppUpdateFetch> Function()? fetch;

  /// The last good notice on the device; null keeps nothing.
  final AppUpdateCache? cache;

  final Duration checkTimeout;

  AppUpdateConfig? _config;
  int? _installed;
  bool _prepared = false;
  bool _optionalDismissed = false;
  bool _launching = false;
  bool _launchFailed = false;
  bool _started = false;
  bool _observing = false;
  bool _disposed = false;
  Future<void>? _checking;

  /// The card to show now. An optional update the player put off ([later],
  /// or Update) stays hidden until the next launch.
  AppUpdatePrompt get prompt {
    final decided = decideAppUpdate(config: _config, platform: updater.platform, installedBuild: _installed);
    if (decided.need == AppUpdateNeed.optional && _optionalDismissed) return AppUpdatePrompt.none;
    return decided;
  }

  /// True while Update is opening Google Play or the store (taps ignored).
  bool get launching => _launching;

  /// The last Update could open nothing: the card says so.
  bool get launchFailed => _launchFailed;

  /// Applies the stored notice and fetches the current one, in the
  /// background. Safe to call more than once; nothing where updates are not
  /// offered.
  void start() {
    if (_started || _disposed || updater.platform == null) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object {
      // No binding (a pure Dart test): nothing to observe.
    }
    unawaited(check());
  }

  /// Fetches the notice again (one check at a time).
  Future<void> check() => _checking ??= () async {
    try {
      await _check();
    } on Object catch (error) {
      debugPrint('App update: check failed ($error)');
    } finally {
      _checking = null;
    }
  }();

  Future<void> _check() async {
    if (_disposed) return;
    if (!_prepared) {
      _prepared = true;
      _installed = await updater.installedBuild();
      // The last good notice first: a required update applies offline too.
      _config = AppUpdateConfig.tryDecode(cache?.read());
      _changed();
    }
    // Without a build number there is nothing to compare.
    if (_installed == null) return;
    final fetched = await _fetch();
    if (_disposed) return;
    switch (fetched.status) {
      case AppUpdateFetchStatus.found:
        _config = fetched.config;
        await cache?.write(fetched.json);
      case AppUpdateFetchStatus.missing:
        // No notice on the host: nothing to ask.
        _config = null;
        await cache?.write(null);
      case AppUpdateFetchStatus.invalid:
      case AppUpdateFetchStatus.failed:
        // Keep the last good notice.
        break;
    }
    _changed();
  }

  Future<AppUpdateFetch> _fetch() async {
    final fetch = this.fetch;
    if (fetch == null) return const AppUpdateFetch.failed();
    try {
      return await fetch().timeout(checkTimeout);
    } on Object catch (error) {
      debugPrint('App update: notice not fetched ($error)');
      return const AppUpdateFetch.failed();
    }
  }

  /// "Later" on the optional card: hidden until the next launch.
  void later() {
    if (_disposed || prompt.need != AppUpdateNeed.optional) return;
    _optionalDismissed = true;
    _changed();
  }

  /// "Update": Google Play's update or the store page. The optional card
  /// goes once something opened (or the player said no to Play); the
  /// required one stays until this build is replaced.
  Future<void> update() async {
    final prompt = this.prompt;
    if (_disposed || _launching || prompt.need == AppUpdateNeed.none) return;
    _launching = true;
    _launchFailed = false;
    _changed();
    try {
      final result = await updater.launch(storeUrl: prompt.storeUrl);
      _launchFailed = result == AppUpdateLaunch.failed;
      if (prompt.need == AppUpdateNeed.optional && !_launchFailed) _optionalDismissed = true;
    } on Object catch (error) {
      debugPrint('App update: launch failed ($error)');
      _launchFailed = true;
    } finally {
      _launching = false;
      _changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _disposed) return;
    // Back from the store or Play's update screen: Update works again.
    if (_launching) {
      _launching = false;
      _changed();
    }
    unawaited(check());
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

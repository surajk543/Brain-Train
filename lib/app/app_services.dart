import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../content/app_update_config.dart';
import '../content/asset_download_manager.dart';
import '../content/content_cache.dart';
import '../content/content_config.dart';
import '../content/content_coordinator.dart';
import '../content/content_exception.dart';
import '../content/content_fetcher.dart';
import '../content/content_repositories.dart';
import '../content/content_snapshot.dart';
import '../content/content_sources.dart';
import '../content/file_content_store.dart';
import '../content/level_manifest.dart';
import '../content/remote_asset_resolver.dart';
import '../data/app_update_cache.dart';
import '../data/progress_repository.dart';
import '../data/settings_repository.dart';
import '../platform/app_updates.dart';
import '../platform/games_services_play_games.dart';
import '../platform/google_mobile_ads_rewarded.dart';
import '../platform/play_games.dart';
import '../platform/play_in_app_update.dart';
import '../platform/rewarded_ads.dart';
import '../rendering/symbol_art.dart';
import 'app_update_controller.dart';
import 'background_music.dart';
import 'play_games_controller.dart';
import 'rewarded_ads_controller.dart';
import 'sound_effects.dart';

/// Observable wrapper around [ContentCoordinator] for the widget tree, and
/// the scheduler of background downloads.
///
/// After the initial (offline) load it checks for a new manifest and keeps
/// the level window ready, in the background: at start, after every win (the
/// window moves on), when the app comes back to the foreground, and, while
/// any window level is still missing (offline, a server error, a rate limit),
/// every few seconds ([retryDelays]) until all of them are on the device.
/// Retries pause while the app is in the background.
class ContentController extends ChangeNotifier with WidgetsBindingObserver {
  ContentController(
    this.coordinator, {
    ProgressRepository? progress,
    this.autoRetry = true,
    this.retryDelays = defaultRetryDelays,
  }) {
    _subscriptions = [
      coordinator.snapshots.listen((_) => notifyListeners()),
      coordinator.statuses.listen((_) => notifyListeners()),
      coordinator.levelsReady.listen((_) => notifyListeners()),
    ];
    if (progress != null) attachProgress(progress);
  }

  final ContentCoordinator coordinator;

  /// Retry on a timer while the window is incomplete (off in tests).
  final bool autoRetry;

  /// Waits between window retries; the last one repeats until every window
  /// level is ready.
  final List<Duration> retryDelays;

  static const List<Duration> defaultRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  late final List<StreamSubscription<Object?>> _subscriptions;
  ProgressRepository? _progress;
  Set<String> _won = const {};
  Future<void>? _toppingUp;
  Timer? _retry;
  int _retries = 0;
  bool _observing = false;
  bool _disposed = false;

  ContentSnapshot get snapshot => coordinator.current!;
  ContentSyncStatus get status => coordinator.status;
  ContentException? get lastError => coordinator.lastError;

  /// The window follows the player's wins.
  void attachProgress(ProgressRepository progress) {
    if (identical(progress, _progress)) return;
    _progress?.removeListener(_progressChanged);
    _progress = progress;
    _won = progress.completed().keys.toSet();
    coordinator.completedLevels = () => progress.completed().keys.toSet();
    progress.addListener(_progressChanged);
  }

  void _progressChanged() {
    final won = _progress!.completed().keys.toSet();
    if (setEquals(won, _won)) return;
    _won = won;
    unawaited(_window());
  }

  Future<void> start() async {
    await coordinator.loadInitial();
    // Window levels already on the device open at once (no network).
    await coordinator.warmUp();
    _observeLifecycle();
    unawaited(topUp());
  }

  /// A new manifest if there is one, then the level window.
  Future<void> topUp() => _toppingUp ??= () async {
    try {
      final status = await coordinator.refresh();
      await _window(offlineAlready: status == ContentSyncStatus.offline);
    } finally {
      _toppingUp = null;
    }
  }();

  Future<void> _window({bool offlineAlready = false}) async {
    final result = await coordinator.maintainWindow();
    if (offlineAlready || result.offline || result.ready < result.window.length) {
      _scheduleRetry();
    } else {
      _retry?.cancel();
      _retries = 0;
    }
  }

  void _scheduleRetry() {
    if (!autoRetry || _disposed || (_retry?.isActive ?? false)) return;
    final delay = retryDelays[math.min(_retries, retryDelays.length - 1)];
    _retries++;
    _retry = Timer(delay, () => unawaited(topUp()));
  }

  void _observeLifecycle() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object {
      // No binding (a pure Dart test): nothing to observe.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retry?.cancel();
      unawaited(topUp());
    } else if (state == AppLifecycleState.paused) {
      // No downloads in the background; resuming tops up at once.
      _retry?.cancel();
    }
  }

  Future<ContentSyncStatus> refresh() => coordinator.refresh();

  /// Whether [entry] opens at once (its file and art are on the device).
  bool isReady(LevelManifestEntry entry) => snapshot.isReady(entry.levelId);

  /// The level window right now (the first level not won and the ones after
  /// it, [ContentCoordinator.windowSize] in all): how many of its levels are
  /// on the device, ready to play offline, and how many it has (0 once every
  /// level is won). The lobby's "5 levels ready" line.
  ({int ready, int window}) get windowReadiness {
    final window = coordinator.windowOf(snapshot);
    return (ready: window.where((e) => snapshot.isReady(e.levelId)).length, window: window.length);
  }

  /// Gets [entry] ready to play (see [ContentCoordinator.ensureLevel]).
  Future<ReadyLevel> ensureLevel(LevelManifestEntry entry) => coordinator.ensureLevel(entry);

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _progress?.removeListener(_progressChanged);
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// App-wide services, created once at startup.
class AppServices {
  AppServices({
    required this.content,
    required this.progress,
    required this.settings,
    required this.symbolArt,
    this.sounds,
    this.music,
    PlayGamesController? playGames,
    RewardedAdsController? ads,
    AppUpdateController? updates,
  }) : playGames = playGames ?? PlayGamesController(const UnavailablePlayGames()),
       ads = ads ?? RewardedAdsController(const UnavailableRewardedAds()),
       updates = updates ?? AppUpdateController(updater: const UnavailableAppUpdater()) {
    // The level window follows this player's progress.
    content.attachProgress(progress);
  }

  final ContentController content;
  final ProgressRepository progress;
  final SettingsRepository settings;
  final SymbolArtCache symbolArt;

  /// Null when audio is unavailable (tests).
  final SoundEffects? sounds;

  /// Looping ambient music, started after the studio intro. Null in tests.
  final BackgroundMusic? music;

  /// Google Play Games (Android builds with an app ID); unavailable elsewhere.
  final PlayGamesController playGames;

  /// Rewarded ads for Revive (Android and iOS); off elsewhere (no ad needed).
  final RewardedAdsController ads;

  /// The lobby's update card (Android and iOS); never asks elsewhere.
  final AppUpdateController updates;

  static Future<AppServices> create({ContentConfig? config}) async {
    final contentConfig = config ?? ContentConfig.production;
    final supportDir = await getApplicationSupportDirectory();
    final cache = ContentCache(FileContentStore(Directory('${supportDir.path}/content_cache')));
    final fetcher = ContentFetcher(client: http.Client(), config: contentConfig);
    final resolver = RemoteAssetResolver(contentConfig);
    // The starter pack (levels 1-5, their art, the manifest and registry),
    // then the lobby hero's three symbols.
    final bundled = bundledContent(_loadAsset);
    final coordinator = ContentCoordinator(
      cache: cache,
      bundled: bundled,
      // Objects the app already bundles are copied, not downloaded.
      downloads: AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver, seed: bundled),
      manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
    );
    final (progress, settings) = (await ProgressRepository.open(), await SettingsRepository.open());
    final content = ContentController(coordinator, progress: progress);
    await content.start();
    final sounds = SoundEffects(settings);
    await sounds.preload();
    final music = BackgroundMusic(settings);
    return AppServices(
      content: content,
      progress: progress,
      settings: settings,
      symbolArt: SymbolArtCache(),
      sounds: sounds,
      music: music,
      // A local check only; sign-in starts from the lobby.
      playGames: PlayGamesController(await createPlayGames()),
      // Nothing runs yet: the lobby starts ads after its first frame.
      ads: RewardedAdsController(createRewardedAds(), music: music, sounds: sounds),
      // Nothing runs yet: the lobby checks for an update after its first frame.
      updates: AppUpdateController(
        updater: createAppUpdater(),
        fetch: AppUpdateConfigService(fetcher: fetcher, resolver: resolver).fetch,
        cache: await AppUpdateCache.open(),
      ),
    );
  }

  static Future<Uint8List?> _loadAsset(String key) async {
    try {
      final data = await rootBundle.load(key);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on FlutterError {
      return null;
    }
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

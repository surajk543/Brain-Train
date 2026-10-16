import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
import '../content/remote_asset_resolver.dart';
import '../data/progress_repository.dart';
import '../data/settings_repository.dart';
import '../rendering/symbol_art.dart';
import 'background_music.dart';
import 'sound_effects.dart';

/// Observable wrapper around [ContentCoordinator] for the widget tree.
class ContentController extends ChangeNotifier {
  ContentController(this.coordinator) {
    _subscriptions = [
      coordinator.snapshots.listen((_) => notifyListeners()),
      coordinator.statuses.listen((_) => notifyListeners()),
    ];
  }

  final ContentCoordinator coordinator;
  late final List<StreamSubscription<Object?>> _subscriptions;

  ContentSnapshot get snapshot => coordinator.current!;
  ContentSyncStatus get status => coordinator.status;
  ContentException? get lastError => coordinator.lastError;

  Future<void> start() async {
    await coordinator.loadInitial();
    unawaited(refresh());
  }

  Future<ContentSyncStatus> refresh() => coordinator.refresh();

  @override
  void dispose() {
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
  });

  final ContentController content;
  final ProgressRepository progress;
  final SettingsRepository settings;
  final SymbolArtCache symbolArt;

  /// Null when audio is unavailable (tests).
  final SoundEffects? sounds;

  /// Looping ambient music, started after the studio intro. Null in tests.
  final BackgroundMusic? music;

  static Future<AppServices> create({ContentConfig? config}) async {
    final contentConfig = config ?? ContentConfig.production;
    final supportDir = await getApplicationSupportDirectory();
    final cache = ContentCache(FileContentStore(Directory('${supportDir.path}/content_cache')));
    final fetcher = ContentFetcher(client: http.Client(), config: contentConfig);
    final resolver = RemoteAssetResolver(contentConfig);
    final bundled = BundledContentSource(_loadAsset);
    final coordinator = ContentCoordinator(
      cache: cache,
      bundled: bundled,
      // Objects the app already bundles are copied, not downloaded.
      downloads: AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver, seed: bundled),
      manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
    );
    final content = ContentController(coordinator);
    final (progress, settings) = (await ProgressRepository.open(), await SettingsRepository.open());
    await content.start();
    final sounds = SoundEffects(settings);
    await sounds.preload();
    return AppServices(
      content: content,
      progress: progress,
      settings: settings,
      symbolArt: SymbolArtCache(),
      sounds: sounds,
      music: BackgroundMusic(settings),
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

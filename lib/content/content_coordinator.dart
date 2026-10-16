import 'dart:async';
import 'dart:math' as math;

import '../game_engine/models/level_definition.dart';
import '../game_engine/models/symbol_registry.dart';
import 'asset_download_manager.dart';
import 'content_cache.dart';
import 'content_exception.dart';
import 'content_repositories.dart';
import 'content_snapshot.dart';
import 'content_sources.dart';
import 'content_validator.dart';
import 'level_manifest.dart';
import 'remote_asset_resolver.dart';

enum ContentSyncStatus {
  idle,
  checking,

  /// The remote manifest matches what is in use.
  upToDate,

  /// New content was validated, cached and published.
  updated,

  /// Network trouble; the current content stays in use.
  offline,

  /// Remote content was invalid or needs a newer app; it was not used.
  rejected,
}

/// A level ready to play: the snapshot and manifest entry to start the game
/// with (an older cached file of the level when its current one cannot be
/// downloaded), and the level.
typedef ReadyLevel = ({ContentSnapshot snapshot, LevelManifestEntry entry, LevelDefinition level});

/// How a top-up of the level window went.
typedef WindowResult = ({List<String> window, int ready, bool offline});

/// Runs the content loading flow. R2 is the source of truth; the device
/// keeps what it has downloaded, forever.
///
/// 1. [loadInitial]: the newer of the cached known-good manifest and the
///    bundled starter pack (levels 1-5 and their art), with every level file
///    already on the device. No network, so play starts at once.
/// 2. [refresh]: fetch the manifest. A newer one becomes active only once
///    its registry and its level window (see [maintainWindow]) are cached,
///    with their art; otherwise the current one stays.
/// 3. [maintainWindow]: keep the next [windowSize] levels (the first level
///    not won and the ones after it) fully on the device: level file plus
///    only the symbol art it uses.
/// 4. [ensureLevel]: get any one level ready on demand, e.g. to replay a
///    level outside the window.
///
/// Objects come from the cache first, then from the app bundle when their
/// SHA-256 matches (copied into the cache), and only then from the network
/// (see [AssetDownloadManager]), so nothing is downloaded twice. A level
/// whose current file cannot be fetched (offline) still opens from an older
/// cached file of it ([CachedLevel]), so a level that was once ready never
/// becomes unplayable offline.
class ContentCoordinator {
  ContentCoordinator({
    required this.cache,
    required this.bundled,
    required this.downloads,
    required this.manifests,
    this.registries = const SymbolRegistryRepository(),
    this.levelRepository = const LevelRepository(),
    this.validator = const ContentValidator(),
    this.windowSize = 5,
    Set<String> Function()? completedLevels,
  }) : completedLevels = completedLevels ?? _none;

  static Set<String> _none() => const {};

  final ContentCache cache;
  final ContentSource bundled;
  final AssetDownloadManager downloads;
  final ContentManifestService manifests;
  final SymbolRegistryRepository registries;
  final LevelRepository levelRepository;
  final ContentValidator validator;

  /// Levels kept ready ahead of the player.
  final int windowSize;

  /// Ids of the levels the player has won (the window starts at the first
  /// level not in it).
  Set<String> Function() completedLevels;

  final StreamController<ContentSnapshot> _snapshots = StreamController.broadcast();
  final StreamController<ContentSyncStatus> _statuses = StreamController.broadcast();
  final StreamController<String> _levelsReady = StreamController.broadcast();

  ContentSnapshot? _current;
  ContentSyncStatus _status = ContentSyncStatus.idle;
  ContentException? lastError;
  Future<ContentSyncStatus>? _refreshing;
  Future<WindowResult>? _windowRun;
  bool _windowAgain = false;
  final Map<String, Future<ReadyLevel>> _ensuring = {};
  Map<String, CachedLevel> _index = {};
  Future<void> _indexWrites = Future.value();

  ContentSnapshot? get current => _current;
  ContentSyncStatus get status => _status;
  Stream<ContentSnapshot> get snapshots => _snapshots.stream;
  Stream<ContentSyncStatus> get statuses => _statuses.stream;

  /// Ids of levels that just became ready to play.
  Stream<String> get levelsReady => _levelsReady.stream;

  /// What is already on the device: the cache, then the app bundle.
  ContentSource get _local => FallbackContentSource(CachedContentSource(cache), bundled);

  Future<ContentSnapshot> loadInitial() async {
    const path = 'manifest.json';
    final bundledJson = decodeJsonBytes(await bundled.read(path, ContentKind.json), path);
    final bundledManifest = ContentManifestService.parseAndValidate(bundledJson, validator, path);
    _index = await cache.readLevelIndex();
    final record = await cache.readKnownGood();
    if (record != null) {
      final cachedVersion = ContentVersion.tryParse(record.contentVersion);
      final bundledVersion = ContentVersion.tryParse(bundledManifest.contentVersion);
      // An app update may ship newer content than an old cached download.
      if (cachedVersion != null && bundledVersion != null && cachedVersion.compareTo(bundledVersion) >= 0) {
        try {
          final manifest = ContentManifestService.parseAndValidate(record.manifestJson, validator, 'known-good');
          final snapshot = await _localSnapshot(manifest, record.manifestJson, ContentOrigin.cached);
          _publish(snapshot);
          return snapshot;
        } on ContentException {
          // Unusable (e.g. its registry is gone): the bundle is used.
        }
      }
    }
    final snapshot = await _localSnapshot(bundledManifest, bundledJson, ContentOrigin.bundled);
    _publish(snapshot);
    return snapshot;
  }

  /// [manifest] with its registry and every level file already on the
  /// device (never the network).
  Future<ContentSnapshot> _localSnapshot(
    LevelManifest manifest,
    Object? json,
    ContentOrigin origin, {
    SymbolRegistry? registry,
  }) async {
    final snapshot = ContentSnapshot(
      manifest: manifest,
      manifestJson: json,
      registry: registry ?? await registries.load(manifest.symbolRegistry, _local),
      origin: origin,
      artwork: _local,
    );
    Future<void> loadLocal(LevelManifestEntry entry) async {
      try {
        snapshot.addLevel(await levelRepository.load(entry, snapshot.registry, _local));
      } on ContentException catch (error) {
        if (error.kind == ContentErrorKind.missingFromCache || error.kind == ContentErrorKind.notFound) return;
        snapshot.addError(entry.levelId, error.toString());
      }
    }

    await Future.wait([for (final entry in manifest.levels) loadLocal(entry)]);
    return snapshot;
  }

  /// Safe to call repeatedly; concurrent calls share one refresh.
  Future<ContentSyncStatus> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<ContentSyncStatus> _refresh() async {
    _setStatus(ContentSyncStatus.checking);
    try {
      final (manifest, json) = await manifests.fetchLatest();
      // Only move forward: an app update may bundle newer content than R2
      // has. Roll back by publishing old content under a higher version.
      final remote = ContentVersion.tryParse(manifest.contentVersion)!;
      final current = _current == null ? null : ContentVersion.tryParse(_current!.contentVersion);
      if (current != null && remote.compareTo(current) <= 0) {
        return _setStatus(ContentSyncStatus.upToDate);
      }
      // Metadata first: the registry is small. Then the window, all or nothing.
      final registry = await registries.load(manifest.symbolRegistry, downloads);
      final candidate = await _localSnapshot(manifest, json, ContentOrigin.remote, registry: registry);
      final window = windowOf(candidate);
      final failures = <(LevelManifestEntry, Object)>[];
      await Future.wait([
        for (final entry in window)
          _ensure(candidate, entry).then<void>((_) {}, onError: (Object error) => failures.add((entry, error))),
      ]);
      for (final (entry, error) in failures) {
        // A broken level file is left out (recorded in levelErrors); missing
        // art or a lost connection blocks the whole update.
        if (candidate.levelErrors.containsKey(entry.levelId)) continue;
        if (error is ContentException) throw error;
        throw ContentException(ContentErrorKind.validation, '$error', path: entry.ref.url);
      }
      await cache.writeKnownGood(manifest.contentVersion, json);
      _publish(candidate);
      lastError = null;
      return _setStatus(ContentSyncStatus.updated);
    } on ContentException catch (error) {
      lastError = error;
      return _setStatus(error.isTransient ? ContentSyncStatus.offline : ContentSyncStatus.rejected);
    }
  }

  /// The levels to keep ready in [snapshot]: the first level not won and the
  /// ones after it, [windowSize] in all.
  List<LevelManifestEntry> windowOf(ContentSnapshot snapshot) => levelWindow(
    snapshot.manifest,
    completedLevels(),
    excluded: snapshot.levelErrors.keys.toSet(),
    size: windowSize,
  );

  static List<LevelManifestEntry> levelWindow(
    LevelManifest manifest,
    Set<String> completed, {
    Set<String> excluded = const {},
    int size = 5,
  }) {
    final entries = [
      for (final entry in manifest.levels)
        if (!excluded.contains(entry.levelId)) entry,
    ];
    final start = entries.indexWhere((e) => !completed.contains(e.levelId));
    if (start < 0) return const [];
    return entries.sublist(start, math.min(start + size, entries.length));
  }

  /// Makes every level of the current window ready (cache, bundle, then
  /// network). Safe to call often, e.g. after every win: concurrent calls
  /// share one run, and a call during a run makes it check once more.
  Future<WindowResult> maintainWindow() {
    final running = _windowRun;
    if (running != null) {
      _windowAgain = true;
      return running;
    }
    return _windowRun = _runWindow().whenComplete(() => _windowRun = null);
  }

  Future<WindowResult> _runWindow() async {
    WindowResult result;
    do {
      _windowAgain = false;
      final snapshot = _current!;
      final window = windowOf(snapshot);
      var offline = false;
      await Future.wait([
        for (final entry in window)
          _ensure(snapshot, entry).then<void>(
            (_) {},
            onError: (Object error) => offline |= error is ContentException && error.isTransient,
          ),
      ]);
      result = (
        window: [for (final e in window) e.levelId],
        ready: window.where((e) => snapshot.isReady(e.levelId)).length,
        offline: offline,
      );
    } while (_windowAgain);
    return result;
  }

  /// Gets [entry] of [snapshot] (default: the current one) ready to play,
  /// downloading its file and art if needed. Offline, a level whose current
  /// file is not cached opens from an older cached file of it if there is
  /// one; otherwise the transient [ContentException] is rethrown.
  Future<ReadyLevel> ensureLevel(LevelManifestEntry entry, {ContentSnapshot? snapshot}) async {
    final target = snapshot ?? _current!;
    try {
      return await _ensure(target, entry);
    } on ContentException catch (error) {
      if (!error.isTransient) rethrow;
      final older = await _olderCachedFile(target, entry);
      if (older == null) rethrow;
      return older;
    }
  }

  Future<ReadyLevel> _ensure(ContentSnapshot snapshot, LevelManifestEntry entry) {
    final key = '${identityHashCode(snapshot)}/${entry.levelId}';
    // (A block body: whenComplete would wait for a returned future, here
    // the removed entry, i.e. itself.)
    return _ensuring[key] ??= _ensureOnce(snapshot, entry).whenComplete(() {
      _ensuring.remove(key);
    });
  }

  Future<ReadyLevel> _ensureOnce(ContentSnapshot snapshot, LevelManifestEntry entry) async {
    // The registry and the level file are copied into the cache too (from
    // the bundle when it has them), so the cache alone can replay the level.
    await downloads.read(snapshot.manifest.symbolRegistry.url, ContentKind.json, sha256: snapshot.manifest.symbolRegistry.sha256);
    LevelDefinition level;
    try {
      await downloads.read(entry.ref.url, ContentKind.json, sha256: entry.ref.sha256);
      level = snapshot.levels[entry.levelId] ?? await levelRepository.load(entry, snapshot.registry, downloads);
    } on ContentException catch (error) {
      if (!error.isTransient) snapshot.addError(entry.levelId, error.toString());
      rethrow;
    }
    // Only this level's art; a symbol shared with other levels is fetched
    // once (concurrent reads of one path share a request, then it is cached).
    await Future.wait([
      for (final symbol in snapshot.assetSymbolsOf(level))
        downloads.read(symbol.assetPath!, ContentKind.forSymbol(symbol)!, sha256: symbol.sha256),
    ]);
    snapshot.addLevel(level, ready: true);
    _remember(entry, snapshot.manifest.symbolRegistry);
    if (!_levelsReady.isClosed) _levelsReady.add(entry.levelId);
    return (snapshot: snapshot, entry: entry, level: level);
  }

  void _remember(LevelManifestEntry entry, ContentRef registry) {
    _index[entry.levelId] = CachedLevel(
      level: (url: entry.ref.url, sha256: entry.ref.sha256),
      registry: (url: registry.url, sha256: registry.sha256),
    );
    final copy = Map.of(_index);
    _indexWrites = _indexWrites.then((_) => cache.writeLevelIndex(copy)).catchError((Object _) {});
  }

  /// The level from the cached file recorded for it when that is not
  /// [entry]'s current file (content changed since), with the registry it
  /// was cached with. Cache only; null when anything is missing.
  Future<ReadyLevel?> _olderCachedFile(ContentSnapshot snapshot, LevelManifestEntry entry) async {
    final cached = _index[entry.levelId];
    if (cached == null || cached.level.url == entry.ref.url) return null;
    final source = CachedContentSource(cache);
    try {
      final registryRef = ContentRef(url: cached.registry.url, sha256: cached.registry.sha256);
      final registry = registryRef.url == snapshot.manifest.symbolRegistry.url
          ? snapshot.registry
          : await registries.load(registryRef, source);
      final older = entry.withRef(ContentRef(url: cached.level.url, sha256: cached.level.sha256));
      final level = await levelRepository.load(older, registry, source);
      final legacy = ContentSnapshot(
        manifest: snapshot.manifest,
        manifestJson: snapshot.manifestJson,
        registry: registry,
        origin: ContentOrigin.cached,
        artwork: _local,
      );
      for (final symbol in legacy.assetSymbolsOf(level)) {
        await source.read(symbol.assetPath!, ContentKind.forSymbol(symbol)!, sha256: symbol.sha256);
      }
      legacy.addLevel(level, ready: true);
      return (snapshot: legacy, entry: older, level: level);
    } on ContentException {
      return null;
    }
  }

  void _publish(ContentSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  ContentSyncStatus _setStatus(ContentSyncStatus status) {
    _status = status;
    _statuses.add(status);
    return status;
  }

  Future<void> dispose() async {
    await _indexWrites;
    await _snapshots.close();
    await _statuses.close();
    await _levelsReady.close();
  }
}

import 'dart:async';

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

/// Runs the content loading flow:
///
/// 1. [loadInitial]: newest of the cached known-good snapshot and the bundled
///    snapshot, so play can start without the network.
/// 2. [refresh]: fetch the manifest, then registry, levels and artwork
///    (images and Lottie animations); only when every referenced object is
///    fetched and valid does it become the new known-good snapshot. Partial
///    or invalid updates are discarded. Objects come from the cache first,
///    then from the app bundle when their SHA-256 matches (copied into the
///    cache), and only then from the network, a few requests at a time
///    (see [AssetDownloadManager]); the screen in use never waits for it.
class ContentCoordinator {
  ContentCoordinator({
    required this.cache,
    required this.bundled,
    required this.downloads,
    required this.manifests,
    this.registries = const SymbolRegistryRepository(),
    this.levelRepository = const LevelRepository(),
    this.validator = const ContentValidator(),
  });

  final ContentCache cache;
  final ContentSource bundled;
  final AssetDownloadManager downloads;
  final ContentManifestService manifests;
  final SymbolRegistryRepository registries;
  final LevelRepository levelRepository;
  final ContentValidator validator;

  final StreamController<ContentSnapshot> _snapshots = StreamController.broadcast();
  final StreamController<ContentSyncStatus> _statuses = StreamController.broadcast();

  ContentSnapshot? _current;
  ContentSyncStatus _status = ContentSyncStatus.idle;
  ContentException? lastError;
  Future<ContentSyncStatus>? _refreshing;

  ContentSnapshot? get current => _current;
  ContentSyncStatus get status => _status;
  Stream<ContentSnapshot> get snapshots => _snapshots.stream;
  Stream<ContentSyncStatus> get statuses => _statuses.stream;

  /// Compares the manifests first and loads only the levels of the one in
  /// use (a campaign has hundreds), so startup parses each level once.
  Future<ContentSnapshot> loadInitial() async {
    const path = 'manifest.json';
    final bundledJson = decodeJsonBytes(await bundled.read(path, ContentKind.json), path);
    final bundledManifest = ContentManifestService.parseAndValidate(bundledJson, validator, path);
    final record = await cache.readKnownGood();
    if (record != null) {
      final cachedVersion = ContentVersion.tryParse(record.contentVersion);
      final bundledVersion = ContentVersion.tryParse(bundledManifest.contentVersion);
      // An app update may ship newer content than an old cached download.
      if (cachedVersion != null && bundledVersion != null && cachedVersion.compareTo(bundledVersion) >= 0) {
        final cachedSnapshot = await _loadKnownGood(record);
        if (cachedSnapshot != null) {
          _publish(cachedSnapshot);
          return cachedSnapshot;
        }
      }
    }
    final snapshot = await _build(bundledManifest, bundledJson, bundled, ContentOrigin.bundled, bundled, strict: false);
    _publish(snapshot);
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
      final artwork = FallbackContentSource(CachedContentSource(cache), bundled);
      final snapshot = await _build(manifest, json, downloads, ContentOrigin.remote, artwork, strict: true);
      // Download (and check) every image and animation a playable level
      // uses before committing.
      await Future.wait([
        for (final symbol in snapshot.usedAssetSymbols)
          downloads.read(symbol.assetPath!, ContentKind.forSymbol(symbol)!, sha256: symbol.sha256),
      ]);
      await cache.writeKnownGood(manifest.contentVersion, json);
      _publish(snapshot);
      await cache.prune(keepPaths: snapshot.referencedPaths);
      lastError = null;
      return _setStatus(ContentSyncStatus.updated);
    } on ContentException catch (error) {
      lastError = error;
      return _setStatus(error.isTransient ? ContentSyncStatus.offline : ContentSyncStatus.rejected);
    }
  }

  /// The cached known-good snapshot, or null when it is unusable.
  Future<ContentSnapshot?> _loadKnownGood(KnownGoodRecord record) async {
    try {
      final manifest = ContentManifestService.parseAndValidate(record.manifestJson, validator, 'known-good');
      final cached = CachedContentSource(cache);
      final artwork = FallbackContentSource(cached, bundled);
      final snapshot = await _build(
        manifest,
        record.manifestJson,
        cached,
        ContentOrigin.cached,
        artwork,
        strict: false,
      );
      return snapshot.levels.isEmpty ? null : snapshot;
    } on ContentException {
      return null;
    }
  }

  /// Loads the registry and every level. With [strict], a transient failure
  /// aborts (the update is retried later); otherwise failing levels are left
  /// out. Content errors always just exclude the affected level.
  Future<ContentSnapshot> _build(
    LevelManifest manifest,
    Object? json,
    ContentSource source,
    ContentOrigin origin,
    ContentSource artwork, {
    required bool strict,
  }) async {
    final SymbolRegistry registry = await registries.load(manifest.symbolRegistry, source);
    final levels = <String, LevelDefinition>{};
    final errors = <String, String>{};
    Future<void> loadLevel(LevelManifestEntry entry) async {
      try {
        levels[entry.levelId] = await levelRepository.load(entry, registry, source);
      } on ContentException catch (error) {
        if (strict && error.isTransient) rethrow;
        errors[entry.levelId] = error.toString();
      }
    }

    await Future.wait([for (final entry in manifest.levels) loadLevel(entry)]);
    if (levels.isEmpty) {
      throw ContentException(ContentErrorKind.validation, 'no playable levels: ${errors.values.join('; ')}');
    }
    return ContentSnapshot(
      manifest: manifest,
      manifestJson: json,
      registry: registry,
      levels: levels,
      levelErrors: errors,
      origin: origin,
      artwork: artwork,
    );
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
    await _snapshots.close();
    await _statuses.close();
  }
}

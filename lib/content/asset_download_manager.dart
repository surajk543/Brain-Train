import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'content_cache.dart';
import 'content_config.dart';
import 'content_exception.dart';
import 'content_fetcher.dart';
import 'content_sources.dart';
import 'content_validator.dart';
import 'remote_asset_resolver.dart';

/// Fetches immutable content objects (level JSON, registries, artwork,
/// Lottie animations): cache first, then [seed] (the app bundle) when the
/// expected SHA-256 is known and matches, then network, with at most
/// [ContentConfig.maxConcurrentDownloads] requests in flight, one request per
/// path at a time, checksum, image-signature and Lottie checks, and a cache
/// write only after the bytes pass. Seeded objects are copied into the cache,
/// so the cache alone always holds the known-good set, even after an app
/// update bundles different content.
class AssetDownloadManager implements ContentSource {
  AssetDownloadManager({required this.cache, required this.fetcher, required this.resolver, this.seed})
    : _limit = fetcher.config.maxConcurrentDownloads;

  final ContentCache cache;
  final ContentFetcher fetcher;
  final RemoteAssetResolver resolver;

  /// Content shipped with the app; objects found here are not downloaded.
  final ContentSource? seed;
  final int _limit;

  final Map<String, Future<Uint8List>> _inFlight = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;

  /// Network requests made so far (cache hits excluded). For tests and logs.
  int networkRequests = 0;

  /// Objects copied from [seed] instead of downloaded. For tests and logs.
  int seededObjects = 0;

  /// Bytes and paths fetched from the network so far. For tests and logs.
  int downloadedBytes = 0;
  final List<String> downloadedPaths = [];

  ContentConfig get config => fetcher.config;

  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) {
    final existing = _inFlight[path];
    if (existing != null) return existing;
    final future = _load(path, kind, sha256);
    _inFlight[path] = future;
    return future.whenComplete(() => _inFlight.remove(path));
  }

  Future<Uint8List> _load(String path, ContentKind kind, String? sha256) async {
    final uri = resolver.resolve(path, kind);
    final cached = await cache.readObject(path, sha256: sha256);
    if (cached != null) return cached;
    final seed = this.seed;
    if (seed != null && sha256 != null) {
      try {
        final bytes = await seed.read(path, kind, sha256: sha256);
        await cache.writeObject(path, bytes);
        seededObjects++;
        return bytes;
      } on ContentException {
        // Not bundled (or different bytes): download it.
      }
    }

    await _acquire();
    final Uint8List bytes;
    try {
      networkRequests++;
      bytes = await fetcher.get(
        uri,
        maxBytes: switch (kind) {
          ContentKind.json => config.maxJsonBytes,
          ContentKind.image => config.maxImageBytes,
          ContentKind.animation => config.maxAnimationBytes,
        },
        path: path,
      );
    } finally {
      _release();
    }
    ContentValidator.verifyChecksum(bytes, sha256, path);
    switch (kind) {
      case ContentKind.image:
        checkImageSignature(bytes, path);
      case ContentKind.animation:
        checkLottieJson(bytes, path, maxBytes: config.maxAnimationBytes);
      case ContentKind.json:
        break;
    }
    await cache.writeObject(path, bytes);
    downloadedBytes += bytes.length;
    downloadedPaths.add(path);
    return bytes;
  }

  Future<void> _acquire() async {
    if (_active < _limit) {
      _active++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }
}

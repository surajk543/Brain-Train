import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brain_train/content/asset_download_manager.dart';
import 'package:brain_train/content/content_cache.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_exception.dart';
import 'package:brain_train/content/content_fetcher.dart';
import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/content_validator.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers.dart';

final config = ContentConfig(
  baseUrl: Uri.parse('https://content.test/'),
  allowedHosts: const {'content.test'},
  retryBackoff: Duration.zero,
);

Map<String, Object?> manifestJson() =>
    jsonDecode(File('content/brain-train/manifest.json').readAsStringSync()) as Map<String, Object?>;

/// Bundled content for tests: the repository copy.
ContentSource get bundled => repoContent;

/// Levels in the published manifest.
int get levelCount => (manifestJson()['levels']! as List<Object?>).length;

ContentCoordinator coordinatorFor(http.Client client, ContentCache cache, {ContentSource? bundle, bool seed = false}) {
  final fetcher = ContentFetcher(client: client, config: config, delay: (_) async {});
  final resolver = RemoteAssetResolver(config);
  return ContentCoordinator(
    cache: cache,
    bundled: bundle ?? bundled,
    downloads: AssetDownloadManager(
      cache: cache,
      fetcher: fetcher,
      resolver: resolver,
      seed: seed ? bundle ?? bundled : null,
    ),
    manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
  );
}

/// [repoContent] that counts reads per path.
class CountingSource implements ContentSource {
  final Map<String, int> reads = {};

  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) {
    reads[path] = (reads[path] ?? 0) + 1;
    return repoContent.read(path, kind, sha256: sha256);
  }
}

/// The repository manifest with a newer content version, served remotely.
http.Response newerManifest({void Function(Map<String, Object?>)? edit}) {
  final json = manifestJson()..['contentVersion'] = '2999.1.1.1';
  edit?.call(json);
  return http.Response(jsonEncode(json), 200);
}

void main() {
  group('manifest', () {
    test('parses and validates the published manifest', () {
      final manifest = LevelManifest.fromJson(manifestJson());
      expect(const ContentValidator().validateManifest(manifest), isEmpty);
      expect(manifest.levels.first.order, 1);
    });

    test('rejects unsupported schemas and incompatible content', () {
      final future = LevelManifest.fromJson(manifestJson()..['schemaVersion'] = 99);
      expect(const ContentValidator().validateManifest(future).map((e) => e.code), contains('unsupported_schema'));
      final needsNewApp = LevelManifest.fromJson(manifestJson()..['compatibility'] = {'minClientContentSchema': kClientContentSchema + 1});
      expect(
        () => ContentManifestService.parseAndValidate(needsNewApp.toJson(), const ContentValidator(), 'm'),
        throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.incompatible)),
      );
    });

    test('rejects unsafe paths and malformed checksums', () {
      final json = manifestJson();
      (json['levels']! as List<Object?>)[0] = {'levelId': 'level-0001', 'order': 1, 'url': '../secret.json'};
      (json['symbolRegistry']! as Map<String, Object?>)['sha256'] = 'XYZ';
      final codes = const ContentValidator().validateManifest(LevelManifest.fromJson(json)).map((e) => e.code);
      expect(codes, containsAll(['unsafe_path', 'invalid_checksum']));
    });

    test('content versions compare numerically', () {
      expect(ContentVersion.tryParse('2026.10.16.2')!.compareTo(ContentVersion.tryParse('2026.10.16.10')!), lessThan(0));
      expect(ContentVersion.tryParse('latest'), isNull);
    });
  });

  group('asset paths', () {
    for (final bad in ['../x.json', '/abs.json', 'https://evil.test/x.json', r'a\b.json', 'a//b.json', 'a/./b.json', 'x.json?q=1', 'x.exe', '']) {
      test('rejects "$bad"', () {
        expect(RemoteAssetResolver.isSafe(bad, ContentKind.json), isFalse);
      });
    }

    test('resolves safe paths under the content root on an allowed host', () {
      final uri = RemoteAssetResolver(config).resolve('levels/level-0001-v1.json', ContentKind.json);
      expect(uri.toString(), 'https://content.test/brain-train/levels/level-0001-v1.json');
      expect(() => RemoteAssetResolver(config).resolve('symbols/a.json', ContentKind.image), throwsA(isA<ContentException>()));
    });
  });

  group('registry', () {
    test('rejects unsupported types and unsafe artwork paths without failing the rest', () {
      final parsed = SymbolRegistry.fromJson({
        'schemaVersion': 1,
        'registryVersion': 'r',
        'symbols': {
          'GOOD': {'type': 'image', 'assetPath': 'symbols/v1/good.webp'},
          'MODEL': {'type': 'glb', 'assetPath': 'symbols/v1/m.glb'},
          'ESCAPE': {'type': 'image', 'assetPath': '../../etc/passwd.png'},
          'NOPATH': {'type': 'image'},
        },
      });
      final (registry, errors) = const ContentValidator().validateRegistry(parsed);
      expect(errors, isEmpty);
      expect(registry.symbols.keys, ['GOOD']);
      expect(registry.rejected.keys, containsAll(['MODEL', 'ESCAPE', 'NOPATH']));
    });
  });

  group('levels', () {
    final reg = registry(['A']);

    Future<Object> loadError(Map<String, Object?> json) async {
      final source = BundledContentSource((_) async => bytesOf(jsonEncode(json)));
      const entry = LevelManifestEntry(levelId: 'lvl', order: 1, title: 't', ref: ContentRef(url: 'levels/lvl.json'));
      try {
        await const LevelRepository().load(entry, reg, source);
        return 'loaded';
      } on ContentException catch (error) {
        return error;
      }
    }

    Map<String, Object?> levelJson(List<Map<String, Object?>> tiles, {int schema = 1}) => {
      'schemaVersion': schema,
      'levelId': 'lvl',
      'board': {'tileWidth': 2, 'tileHeight': 2},
      'tiles': tiles,
    };

    Map<String, Object?> tile(String id, String symbol, num x) => {'tileId': id, 'symbolCode': symbol, 'x': x, 'y': 0, 'layer': 0};

    test('accepts a valid level', () async {
      expect(await loadError(levelJson([tile('a', 'A', 0), tile('b', 'A', 4)])), 'loaded');
    });

    test('rejects duplicate tile ids', () async {
      final error = await loadError(levelJson([tile('a', 'A', 0), tile('a', 'A', 4)]));
      expect(error.toString(), contains('duplicate_tile_id'));
    });

    test('rejects unknown symbols', () async {
      final error = await loadError(levelJson([tile('a', 'A', 0), tile('b', 'MISSING', 4)]));
      expect(error.toString(), contains('unknown_symbol'));
    });

    test('rejects a newer level schema as incompatible', () async {
      final error = await loadError(levelJson([tile('a', 'A', 0), tile('b', 'A', 4)], schema: 99));
      expect((error as ContentException).kind, ContentErrorKind.incompatible);
    });

    test('rejects wrong JSON types as a format error', () async {
      final error = await loadError({'schemaVersion': 1, 'levelId': 'lvl', 'board': 'big', 'tiles': []});
      expect((error as ContentException).kind, ContentErrorKind.format);
    });
  });

  group('downloads', () {
    test('retries server errors, then succeeds', () async {
      var calls = 0;
      final client = MockClient((_) async => ++calls < 3 ? http.Response('busy', 503) : http.Response('{}', 200));
      final bytes = await ContentFetcher(client: client, config: config, delay: (_) async {}).get(Uri.parse('https://content.test/x'), maxBytes: 10);
      expect(utf8.decode(bytes), '{}');
      expect(calls, 3);
    });

    test('does not retry 404s', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('no', 404);
      });
      final fetcher = ContentFetcher(client: client, config: config, delay: (_) async {});
      await expectLater(
        fetcher.get(Uri.parse('https://content.test/x'), maxBytes: 10),
        throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.notFound)),
      );
      expect(calls, 1);
    });

    test('network failures surface as transient errors after bounded retries', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        throw http.ClientException('offline', request.url);
      });
      final fetcher = ContentFetcher(client: client, config: config, delay: (_) async {});
      await expectLater(
        fetcher.get(Uri.parse('https://content.test/x'), maxBytes: 10),
        throwsA(isA<ContentException>().having((e) => e.isTransient, 'transient', isTrue)),
      );
      expect(calls, config.maxRetries + 1);
    });

    test('checksum mismatches are rejected and never cached', () async {
      final cache = ContentCache(MemoryContentStore());
      final downloads = AssetDownloadManager(
        cache: cache,
        fetcher: ContentFetcher(client: MockClient((_) async => http.Response('tampered', 200)), config: config),
        resolver: RemoteAssetResolver(config),
      );
      await expectLater(
        downloads.read('levels/a.json', ContentKind.json, sha256: '0' * 64),
        throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.checksum)),
      );
      expect(await cache.readObject('levels/a.json'), isNull);
    });

    test('non-image bytes are rejected as artwork', () async {
      final downloads = AssetDownloadManager(
        cache: ContentCache(MemoryContentStore()),
        fetcher: ContentFetcher(client: MockClient((_) async => http.Response('<html>', 200)), config: config),
        resolver: RemoteAssetResolver(config),
      );
      await expectLater(downloads.read('symbols/v1/x.webp', ContentKind.image), throwsA(isA<ContentException>()));
    });

    test('cached objects are not downloaded again, and parallel reads share one request', () async {
      final log = <String>[];
      final cache = ContentCache(MemoryContentStore());
      final downloads = AssetDownloadManager(
        cache: cache,
        fetcher: ContentFetcher(client: contentServer(log: log), config: config),
        resolver: RemoteAssetResolver(config),
      );
      await Future.wait([for (var i = 0; i < 3; i++) downloads.read('manifest.json', ContentKind.json)]);
      await downloads.read('manifest.json', ContentKind.json);
      expect(log, ['/brain-train/manifest.json']);
    });
  });

  group('coordinator', () {
    test('fresh install offline: bundled content, status offline', () async {
      final offline = MockClient((r) async => throw http.ClientException('offline', r.url));
      final coordinator = coordinatorFor(offline, ContentCache(MemoryContentStore()));
      final snapshot = await coordinator.loadInitial();
      expect(snapshot.origin, ContentOrigin.bundled);
      expect(snapshot.playableEntries.length, levelCount);
      expect(await coordinator.refresh(), ContentSyncStatus.offline);
      expect(coordinator.current, same(snapshot));
    });

    test('an update is cached as known-good and survives going offline', () async {
      final store = MemoryContentStore();
      final online = coordinatorFor(contentServer(overrides: {'/brain-train/manifest.json': newerManifest()}), ContentCache(store));
      await online.loadInitial();
      expect(await online.refresh(), ContentSyncStatus.updated);
      expect(online.current!.origin, ContentOrigin.remote);
      expect(online.current!.contentVersion, '2999.1.1.1');

      // Next launch, no network: the cached update is used.
      final offline = coordinatorFor(MockClient((r) async => throw http.ClientException('offline', r.url)), ContentCache(store));
      final snapshot = await offline.loadInitial();
      expect(snapshot.origin, ContentOrigin.cached);
      expect(snapshot.contentVersion, '2999.1.1.1');
      expect(snapshot.levels.length, levelCount);
      final art = snapshot.usedImageSymbols.first;
      expect(await snapshot.artwork.read(art.assetPath!, ContentKind.image), isNotEmpty);
    });

    test('an older remote version never replaces newer bundled content', () async {
      final log = <String>[];
      final coordinator = coordinatorFor(
        contentServer(log: log, overrides: {
          '/brain-train/manifest.json': http.Response(jsonEncode(manifestJson()..['contentVersion'] = '2000.1.1.1'), 200),
        }),
        ContentCache(MemoryContentStore()),
      );
      final bundledSnapshot = await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.upToDate);
      expect(coordinator.current, same(bundledSnapshot));
      expect(log, ['/brain-train/manifest.json']);
    });

    test('an invalid update is rejected and nothing is marked known-good', () async {
      final cache = ContentCache(MemoryContentStore());
      final coordinator = coordinatorFor(
        contentServer(overrides: {'/brain-train/manifest.json': http.Response('{"schemaVersion": 1, "levels": "nope"}', 200)}),
        cache,
      );
      final before = await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.rejected);
      expect(coordinator.current, same(before));
      expect(await cache.readKnownGood(), isNull);
    });

    test('an update needing a newer app is rejected', () async {
      final coordinator = coordinatorFor(
        contentServer(overrides: {
          '/brain-train/manifest.json': newerManifest(edit: (m) => m['compatibility'] = {'minClientContentSchema': 99}),
        }),
        ContentCache(MemoryContentStore()),
      );
      await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.rejected);
      expect(coordinator.lastError!.kind, ContentErrorKind.incompatible);
    });

    test('missing artwork blocks the update instead of half-applying it', () async {
      final manifest = manifestJson();
      final cache = ContentCache(MemoryContentStore());
      final registryPath = (manifest['symbolRegistry']! as Map<String, Object?>)['url']! as String;
      final registryJson = jsonDecode(File('content/brain-train/$registryPath').readAsStringSync()) as Map<String, Object?>;
      final firstArt = ((registryJson['symbols']! as Map<String, Object?>).values.first! as Map<String, Object?>)['assetPath']! as String;
      final coordinator = coordinatorFor(
        contentServer(overrides: {
          '/brain-train/manifest.json': newerManifest(),
          '/brain-train/$firstArt': http.Response('gone', 404),
        }),
        cache,
      );
      await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.rejected);
      expect(coordinator.current!.origin, ContentOrigin.bundled);
      expect(await cache.readKnownGood(), isNull);
    });

    test('a corrupt known-good pointer falls back to bundled content', () async {
      final store = MemoryContentStore();
      await store.write('state/known-good.json', utf8.encode('not json'));
      final coordinator = coordinatorFor(MockClient((r) async => throw http.ClientException('x', r.url)), ContentCache(store));
      expect((await coordinator.loadInitial()).origin, ContentOrigin.bundled);
    });

    test('a bad level is excluded while the other levels still update', () async {
      final manifest = manifestJson();
      final secondLevel = ((manifest['levels']! as List<Object?>)[1]! as Map<String, Object?>)['url']! as String;
      final broken = Map<String, Object?>.of(LevelDefinition.fromJson(
        jsonDecode(File('content/brain-train/$secondLevel').readAsStringSync()),
      ).toJson())..['tiles'] = <Object?>[];
      final coordinator = coordinatorFor(
        contentServer(overrides: {
          '/brain-train/manifest.json': newerManifest(edit: (m) {
            for (final level in (m['levels']! as List<Object?>).cast<Map<String, Object?>>()) {
              level.remove('sha256');
            }
          }),
          '/brain-train/$secondLevel': http.Response(jsonEncode(broken), 200),
        }),
        ContentCache(MemoryContentStore()),
      );
      await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.updated);
      expect(coordinator.current!.levels.length, levelCount - 1);
      expect(coordinator.current!.levelErrors.keys, ['level-0002']);
    });

    test('an update reuses bundled objects: only the manifest is downloaded', () async {
      final log = <String>[];
      final store = MemoryContentStore();
      final coordinator = coordinatorFor(
        contentServer(log: log, overrides: {'/brain-train/manifest.json': newerManifest()}),
        ContentCache(store),
        seed: true,
      );
      await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.updated);
      expect(log, ['/brain-train/manifest.json'], reason: 'every level, the registry and all art are bundled');
      // Copied into the cache, so the known-good set stands on its own.
      final offline = coordinatorFor(
        MockClient((r) async => throw http.ClientException('offline', r.url)),
        ContentCache(store),
        // A bundle with only its manifest: every object must come from the cache.
        bundle: BundledContentSource((key) async => key.endsWith('/manifest.json') ? File(key).readAsBytesSync() : null),
      );
      final cached = await offline.loadInitial();
      expect(cached.origin, ContentOrigin.cached);
      expect(cached.levels.length, levelCount);
    });

    test('a changed object is downloaded; unchanged bundled ones are not', () async {
      final log = <String>[];
      final manifest = manifestJson();
      final first = (manifest['levels']! as List<Object?>).first! as Map<String, Object?>;
      final level = LevelDefinition.fromJson(jsonDecode(File('content/brain-train/${first['url']}').readAsStringSync()));
      final renamed = jsonEncode(
        LevelDefinition(
          levelId: level.levelId,
          title: 'Renamed Glade',
          difficulty: level.difficulty,
          board: level.board,
          rules: level.rules,
          backdrop: level.backdrop,
          tiles: level.tiles,
        ).toJson(),
      );
      const newPath = 'levels/level-0001-renamed.json';
      final coordinator = coordinatorFor(
        contentServer(log: log, overrides: {
          '/brain-train/manifest.json': newerManifest(edit: (m) {
            final entry = (m['levels']! as List<Object?>).first! as Map<String, Object?>;
            entry
              ..['url'] = newPath
              ..remove('sha256');
          }),
          '/brain-train/$newPath': http.Response(renamed, 200),
        }),
        ContentCache(MemoryContentStore()),
        seed: true,
      );
      await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.updated);
      expect(log, ['/brain-train/manifest.json', '/brain-train/$newPath']);
      expect(coordinator.current!.levels['level-0001']!.title, 'Renamed Glade');
    });

    test('startup reads each level once: only the content in use is built', () async {
      final store = MemoryContentStore();
      final online = coordinatorFor(contentServer(overrides: {'/brain-train/manifest.json': newerManifest()}), ContentCache(store));
      await online.loadInitial();
      expect(await online.refresh(), ContentSyncStatus.updated);

      // Newer content is cached: the bundled levels are not parsed at all.
      final counting = CountingSource();
      final next = coordinatorFor(
        MockClient((r) async => throw http.ClientException('offline', r.url)),
        ContentCache(store),
        bundle: counting,
      );
      expect((await next.loadInitial()).origin, ContentOrigin.cached);
      expect(counting.reads.keys, ['manifest.json']);

      // Nothing cached: every bundled level is read exactly once.
      final fresh = CountingSource();
      final first = coordinatorFor(
        MockClient((r) async => throw http.ClientException('offline', r.url)),
        ContentCache(MemoryContentStore()),
        bundle: fresh,
      );
      expect((await first.loadInitial()).levels.length, levelCount);
      final levelReads = fresh.reads.entries.where((e) => e.key.startsWith('levels/'));
      expect(levelReads, hasLength(levelCount));
      expect(levelReads.every((e) => e.value == 1), isTrue);
    });
  });
}

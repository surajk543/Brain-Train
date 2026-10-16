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
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers.dart';
import 'fixture_content.dart';

final config = ContentConfig(
  baseUrl: Uri.parse('https://content.test/'),
  allowedHosts: const {'content.test'},
  retryBackoff: Duration.zero,
);

Map<String, Object?> manifestJson() =>
    jsonDecode(File('content/starter/manifest.json').readAsStringSync()) as Map<String, Object?>;

/// A source that counts reads per path.
class CountingSource implements ContentSource {
  CountingSource(this.inner);

  final ContentSource inner;
  final Map<String, int> reads = {};

  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) {
    reads[path] = (reads[path] ?? 0) + 1;
    return inner.read(path, kind, sha256: sha256);
  }
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
        fetcher: ContentFetcher(client: FixtureContent().server(log: log), config: config),
        resolver: RemoteAssetResolver(config),
      );
      await Future.wait([for (var i = 0; i < 3; i++) downloads.read('manifest.json', ContentKind.json)]);
      await downloads.read('manifest.json', ContentKind.json);
      expect(log, ['manifest.json']);
    });
  });

  group('coordinator', () {
    final content = FixtureContent();

    test('fresh install offline: the starter pack, status offline', () async {
      final f = fixtureCoordinator(server: content.server(online: () => false), bundle: content.starter());
      final snapshot = await f.coordinator.loadInitial();
      expect(snapshot.origin, ContentOrigin.bundled);
      expect(snapshot.playableEntries, hasLength(content.levels));
      expect(await f.coordinator.refresh(), ContentSyncStatus.offline);
      expect(f.coordinator.current, same(snapshot));
    });

    test('an update is cached as known-good and survives going offline', () async {
      final store = MemoryContentStore();
      final v2 = FixtureContent(version: '2999.1.1.1', titles: {1: 'Renamed Glade'});
      final online = fixtureCoordinator(server: v2.server(), bundle: content.starter(), store: store);
      await online.coordinator.loadInitial();
      expect(await online.coordinator.refresh(), ContentSyncStatus.updated);
      expect(online.coordinator.current!.origin, ContentOrigin.remote);
      expect(online.coordinator.current!.contentVersion, '2999.1.1.1');

      // Next launch, no network: the cached update is used.
      final offline = fixtureCoordinator(server: v2.server(online: () => false), bundle: content.starter(), store: store);
      final snapshot = await offline.coordinator.loadInitial();
      expect(snapshot.origin, ContentOrigin.cached);
      expect(snapshot.contentVersion, '2999.1.1.1');
      expect(snapshot.levels[content.levelId(1)]!.title, 'Renamed Glade');
      final art = content.levelArt[1]!.first;
      expect(await snapshot.artwork.read(art, ContentKind.image), isNotEmpty);
    });

    test('an invalid update is rejected and nothing is marked known-good', () async {
      final store = MemoryContentStore();
      final f = fixtureCoordinator(
        server: content.server(overrides: {'manifest.json': http.Response('{"schemaVersion": 1, "levels": "nope"}', 200)}),
        bundle: content.starter(),
        store: store,
      );
      final before = await f.coordinator.loadInitial();
      expect(await f.coordinator.refresh(), ContentSyncStatus.rejected);
      expect(f.coordinator.current, same(before));
      expect(await ContentCache(store).readKnownGood(), isNull);
    });

    test('an update needing a newer app is rejected', () async {
      final newer = Map<String, Object?>.of(FixtureContent(version: '2999.1.1.1').manifest)
        ..['compatibility'] = {'minClientContentSchema': 99};
      final f = fixtureCoordinator(
        server: content.server(overrides: {'manifest.json': http.Response(jsonEncode(newer), 200)}),
        bundle: content.starter(),
      );
      await f.coordinator.loadInitial();
      expect(await f.coordinator.refresh(), ContentSyncStatus.rejected);
      expect(f.coordinator.lastError!.kind, ContentErrorKind.incompatible);
    });

    test('a corrupt known-good pointer falls back to the starter pack', () async {
      final store = MemoryContentStore();
      await store.write('state/known-good.json', utf8.encode('not json'));
      final f = fixtureCoordinator(server: content.server(online: () => false), bundle: content.starter(), store: store);
      expect((await f.coordinator.loadInitial()).origin, ContentOrigin.bundled);
    });

    test('startup reads each local level file once and nothing else', () async {
      final counting = CountingSource(content.starter());
      final f = fixtureCoordinator(server: content.server(online: () => false), bundle: counting, seed: false);
      final snapshot = await f.coordinator.loadInitial();
      expect(snapshot.levels, hasLength(5));
      final levelReads = counting.reads.entries.where((e) => e.key.startsWith('levels/')).toList();
      expect(levelReads.every((e) => e.value == 1), isTrue);
      expect(counting.reads.keys.where((k) => k.startsWith('symbols/') || k.startsWith('animated-symbols/')), isEmpty,
          reason: 'art is read when a level is opened, not at startup');
    });
  });
}

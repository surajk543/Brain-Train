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
import 'package:brain_train/game_engine/models/symbol_definition.dart';
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

ContentCoordinator coordinatorFor(http.Client client, ContentCache cache) {
  final fetcher = ContentFetcher(client: client, config: config, delay: (_) async {});
  final resolver = RemoteAssetResolver(config);
  return ContentCoordinator(
    cache: cache,
    bundled: repoContent,
    downloads: AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver),
    manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
  );
}

/// The repository manifest with a newer content version, served remotely.
http.Response newerManifest() => http.Response(jsonEncode(manifestJson()..['contentVersion'] = '2999.1.1.1'), 200);

final Uint8List pulse = File('test/fixtures/pulse.lottie.json').readAsBytesSync();

Uint8List pulseWith(void Function(Map<String, Object?> json) edit) {
  final json = jsonDecode(utf8.decode(pulse)) as Map<String, Object?>;
  edit(json);
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

/// Animated symbols the repository content's levels use.
Future<List<SymbolDefinition>> usedAnimated() async {
  final coordinator = coordinatorFor(
    MockClient((r) async => throw http.ClientException('offline', r.url)),
    ContentCache(MemoryContentStore()),
  );
  return (await coordinator.loadInitial()).usedAnimatedSymbols.toList();
}

void main() {
  group('registry', () {
    test('accepts lottie symbols with safe .json paths and rejects the rest', () {
      final parsed = SymbolRegistry.fromJson({
        'schemaVersion': 1,
        'registryVersion': 'r',
        'symbols': {
          'GOOD': {'type': 'lottie', 'assetPath': 'animated-symbols/good.json', 'sha256': 'a' * 64},
          'ESCAPE': {'type': 'lottie', 'assetPath': '../../secret.json'},
          'ABSOLUTE': {'type': 'lottie', 'assetPath': 'https://evil.test/x.json'},
          'IMAGE_EXT': {'type': 'lottie', 'assetPath': 'animated-symbols/x.webp'},
          'NOPATH': {'type': 'lottie'},
          'BAD_SHA': {'type': 'lottie', 'assetPath': 'animated-symbols/b.json', 'sha256': 'XYZ'},
        },
      });
      final (registry, errors) = const ContentValidator().validateRegistry(parsed);
      expect(errors, isEmpty);
      expect(registry.symbols.keys, ['GOOD']);
      expect(registry['GOOD']!.isAnimated, isTrue);
      expect(registry.rejected.keys, containsAll(['ESCAPE', 'ABSOLUTE', 'IMAGE_EXT', 'NOPATH', 'BAD_SHA']));
      expect(SymbolRegistry.fromJson(registry.toJson()).symbols['GOOD']!.toJson(), registry['GOOD']!.toJson());
    });

    test('asset kinds per symbol type', () {
      SymbolDefinition of(SymbolType type) => SymbolDefinition(code: 'X', type: type, assetPath: 'a.json', value: 'x');
      expect(ContentKind.forSymbol(of(SymbolType.lottie)), ContentKind.animation);
      expect(ContentKind.forSymbol(of(SymbolType.image)), ContentKind.image);
      expect(ContentKind.forSymbol(of(SymbolType.emoji)), isNull);
      expect(ContentKind.forSymbol(of(SymbolType.text)), isNull);
      expect(RemoteAssetResolver.isSafe('animated-symbols/fire-emoji.json', ContentKind.animation), isTrue);
      expect(RemoteAssetResolver.isSafe('animated-symbols/fire.webp', ContentKind.animation), isFalse);
    });

    test('this build accepts content that needs animated symbols (client schema 2)', () {
      expect(kClientContentSchema, greaterThanOrEqualTo(2));
      final manifest = LevelManifest.fromJson(manifestJson()..['compatibility'] = {'minClientContentSchema': 2});
      expect(const ContentValidator().validateManifest(manifest), isEmpty);
    });
  });

  group('Lottie validation', () {
    test('accepts a valid animation and summarises it', () {
      final info = checkLottieJson(pulse, 'p.json');
      expect(info.frameRate, 30);
      expect(info.seconds, closeTo(1, 1e-9));
      expect((info.width, info.height, info.layers), (100.0, 100.0, 1));
    });

    final invalid = <String, Uint8List>{
      'not JSON': bytesOf('<html>'),
      'not an object': bytesOf('[]'),
      'no version': pulseWith((j) => j.remove('v')),
      'no frame rate': pulseWith((j) => j.remove('fr')),
      'zero frame rate': pulseWith((j) => j['fr'] = 0),
      'no duration': pulseWith((j) => j['op'] = j['ip']),
      'no size': pulseWith((j) => j.remove('w')),
      'empty layers': pulseWith((j) => j['layers'] = []),
      'layers not objects': pulseWith((j) => j['layers'] = [1]),
      'external image': pulseWith(
        (j) => j['assets'] = [
          {'id': 'img', 'w': 10, 'h': 10, 'u': 'images/', 'p': 'img_0.png'},
        ],
      ),
    };
    for (final MapEntry(key: what, value: bytes) in invalid.entries) {
      test('rejects $what', () {
        expect(
          () => checkLottieJson(bytes, 'p.json'),
          throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.format)),
        );
      });
    }

    test('accepts embedded images and precompositions', () {
      final embedded = pulseWith(
        (j) => j['assets'] = [
          {'id': 'img', 'w': 1, 'h': 1, 'e': 1, 'u': '', 'p': 'data:image/png;base64,AAAA'},
          {'id': 'comp', 'layers': <Object?>[]},
        ],
      );
      expect(() => checkLottieJson(embedded, 'p.json'), returnsNormally);
    });

    test('rejects oversized files', () {
      expect(
        () => checkLottieJson(pulse, 'p.json', maxBytes: 100),
        throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.tooLarge)),
      );
    });
  });

  group('downloads', () {
    AssetDownloadManager downloadsFor(http.Client client, ContentCache cache) => AssetDownloadManager(
      cache: cache,
      fetcher: ContentFetcher(client: client, config: config, delay: (_) async {}),
      resolver: RemoteAssetResolver(config),
    );

    test('animations are checked, cached and not downloaded twice', () async {
      var requests = 0;
      final cache = ContentCache(MemoryContentStore());
      final downloads = downloadsFor(
        MockClient((_) async {
          requests++;
          return http.Response.bytes(pulse, 200);
        }),
        cache,
      );
      const path = 'animated-symbols/pulse.json';
      expect(await downloads.read(path, ContentKind.animation), pulse);
      expect(await cache.readObject(path), pulse);
      await downloads.read(path, ContentKind.animation);
      expect(requests, 1);
    });

    test('invalid animations are rejected and never cached', () async {
      final cache = ContentCache(MemoryContentStore());
      final downloads = downloadsFor(MockClient((_) async => http.Response('{"v": "5"}', 200)), cache);
      await expectLater(
        downloads.read('animated-symbols/bad.json', ContentKind.animation),
        throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.format)),
      );
      expect(await cache.readObject('animated-symbols/bad.json'), isNull);
    });

    test('oversized animations are refused before parsing', () async {
      final small = ContentConfig(
        baseUrl: config.baseUrl,
        allowedHosts: config.allowedHosts,
        retryBackoff: Duration.zero,
        maxAnimationBytes: 64,
      );
      final downloads = AssetDownloadManager(
        cache: ContentCache(MemoryContentStore()),
        fetcher: ContentFetcher(client: MockClient((_) async => http.Response.bytes(pulse, 200)), config: small),
        resolver: RemoteAssetResolver(small),
      );
      await expectLater(
        downloads.read('animated-symbols/big.json', ContentKind.animation),
        throwsA(isA<ContentException>().having((e) => e.kind, 'kind', ContentErrorKind.tooLarge)),
      );
    });
  });

  group('coordinator', () {
    test('the bundled snapshot references its animations and loads them offline', () async {
      final animated = await usedAnimated();
      expect(animated, isNotEmpty, reason: 'published levels use animated symbols');
      final coordinator = coordinatorFor(
        MockClient((r) async => throw http.ClientException('offline', r.url)),
        ContentCache(MemoryContentStore()),
      );
      final snapshot = await coordinator.loadInitial();
      expect(snapshot.origin, ContentOrigin.bundled);
      for (final symbol in animated) {
        expect(snapshot.referencedPaths, contains(symbol.assetPath));
        final bytes = await snapshot.artwork.read(symbol.assetPath!, ContentKind.animation, sha256: symbol.sha256);
        checkLottieJson(bytes, symbol.assetPath!);
      }
    });

    test('an update downloads and caches every animation its levels use before committing', () async {
      final log = <String>[];
      final store = MemoryContentStore();
      final cache = ContentCache(store);
      final coordinator = coordinatorFor(
        contentServer(log: log, overrides: {'/brain-train/manifest.json': newerManifest()}),
        cache,
      );
      await coordinator.loadInitial();
      expect(await coordinator.refresh(), ContentSyncStatus.updated);
      final animated = coordinator.current!.usedAnimatedSymbols.toList();
      expect(animated, isNotEmpty);
      for (final symbol in animated) {
        expect(log, contains('/brain-train/${symbol.assetPath}'));
        expect(await cache.readObject(symbol.assetPath!, sha256: symbol.sha256), isNotNull);
      }
      // Pruning keeps them: they are referenced by the committed snapshot.
      await cache.prune(keepPaths: coordinator.current!.referencedPaths);
      expect(await cache.readObject(animated.first.assetPath!), isNotNull);

      // Next launch offline: the cached update plays with its animations.
      final offline = coordinatorFor(
        MockClient((r) async => throw http.ClientException('x', r.url)),
        ContentCache(store),
      );
      final snapshot = await offline.loadInitial();
      expect(snapshot.origin, ContentOrigin.cached);
      final bytes = await CachedContentSource(
        ContentCache(store),
      ).read(animated.first.assetPath!, ContentKind.animation);
      expect(bytes, isNotEmpty);
    });

    test('a missing or invalid animation blocks the update instead of half-applying it', () async {
      final symbol = (await usedAnimated()).first;
      for (final broken in [http.Response('gone', 404), http.Response('{"not": "lottie"}', 200)]) {
        final cache = ContentCache(MemoryContentStore());
        final coordinator = coordinatorFor(
          contentServer(
            overrides: {'/brain-train/manifest.json': newerManifest(), '/brain-train/${symbol.assetPath}': broken},
          ),
          cache,
        );
        await coordinator.loadInitial();
        expect(await coordinator.refresh(), ContentSyncStatus.rejected);
        expect(coordinator.current!.origin, ContentOrigin.bundled);
        expect(await cache.readKnownGood(), isNull);
      }
    });
  });

  group('authoring', () {
    final sources = jsonDecode(File('art/animated_sources.json').readAsStringSync()) as Map<String, Object?>;
    final entries = (sources['symbols']! as List<Object?>).cast<Map<String, Object?>>();
    final staticCodes = {
      for (final s in (jsonDecode(File('art/asset_sources.json').readAsStringSync())['symbols'] as List))
        (s as Map)['code'] as String,
    };

    test('art/animated_sources.json has unique, valid codes and safe output names', () {
      final codes = entries.map((e) => e['code']! as String).toList();
      expect(codes.toSet(), hasLength(codes.length));
      expect(codes.toSet().intersection(staticCodes), isEmpty);
      for (final entry in entries) {
        expect(entry['code'], matches(RegExp(r'^[A-Z0-9_]{1,40}$')));
        expect(entry['title'], isA<String>());
        expect(
          RemoteAssetResolver.isSafe('animated-symbols/${entry['outputFile']}', ContentKind.animation),
          isTrue,
          reason: '${entry['outputFile']}',
        );
      }
      expect(entries.map((e) => e['outputFile']).toSet(), hasLength(entries.length));
    });

    test('pubspec bundles the animated symbols for offline play', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('- content/brain-train/animated-symbols/'));
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brain_train/content/asset_download_manager.dart';
import 'package:brain_train/content/content_cache.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_exception.dart';
import 'package:brain_train/content/content_fetcher.dart';
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
import 'fixture_content.dart';

final config = ContentConfig(
  baseUrl: Uri.parse('https://content.test/'),
  allowedHosts: const {'content.test'},
  retryBackoff: Duration.zero,
);

Map<String, Object?> manifestJson() =>
    jsonDecode(File('content/starter/manifest.json').readAsStringSync()) as Map<String, Object?>;

final Uint8List pulse = File('test/fixtures/pulse.lottie.json').readAsBytesSync();

Uint8List pulseWith(void Function(Map<String, Object?> json) edit) {
  final json = jsonDecode(utf8.decode(pulse)) as Map<String, Object?>;
  edit(json);
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
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
    final content = FixtureContent();
    // Level 2 uses animated A2, level 4 animated A0 (see FixtureContent).
    final animatedPath = content.levelArt[2]!.firstWhere((p) => p.startsWith('animated-symbols/'));

    test('the starter pack plays its animations offline', () async {
      final f = fixtureCoordinator(server: content.server(online: () => false), bundle: content.starter());
      final snapshot = await f.coordinator.loadInitial();
      final ready = await f.coordinator.ensureLevel(snapshot.manifest.entry(content.levelId(2))!);
      final animated = ready.snapshot.assetSymbolsOf(ready.level).where((s) => s.isAnimated).toList();
      expect(animated.map((s) => s.assetPath), [animatedPath]);
      final bytes = await snapshot.artwork.read(animatedPath, ContentKind.animation, sha256: animated.single.sha256);
      checkLottieJson(bytes, animatedPath);
    });

    test('an update downloads and caches the animations its window uses before committing', () async {
      final log = <String>[];
      final store = MemoryContentStore();
      final cache = ContentCache(store);
      // An app bundle without levels: everything comes from R2.
      final empty = FixtureContent(version: '2026.1.1.0').starter(count: 0);
      final f = fixtureCoordinator(server: content.server(log: log), bundle: empty, store: store, seed: false);
      await f.coordinator.loadInitial();
      expect(await f.coordinator.refresh(), ContentSyncStatus.updated);
      final animated = content.artOf([1, 2, 3, 4, 5]).where((p) => p.startsWith('animated-symbols/')).toSet();
      expect(animated, isNotEmpty);
      for (final path in animated) {
        expect(log, contains(path));
        expect(await cache.readObject(path), isNotNull);
      }
      // Next launch offline: the cached update plays with its animations.
      final offline = fixtureCoordinator(server: content.server(online: () => false), bundle: empty, store: store);
      final snapshot = await offline.coordinator.loadInitial();
      expect(snapshot.origin, ContentOrigin.cached);
      expect(await CachedContentSource(ContentCache(store)).read(animated.first, ContentKind.animation), isNotEmpty);
    });

    test('a missing or invalid animation blocks the update instead of half-applying it', () async {
      for (final broken in [http.Response('gone', 404), http.Response('{"not": "lottie"}', 200)]) {
        final cache = ContentCache(MemoryContentStore());
        final empty = FixtureContent(version: '2026.1.1.0').starter(count: 0);
        final f = fixtureCoordinator(
          server: content.server(overrides: {animatedPath: broken}),
          bundle: empty,
          store: cache.store as MemoryContentStore,
          seed: false,
        );
        await f.coordinator.loadInitial();
        expect(await f.coordinator.refresh(), ContentSyncStatus.rejected);
        expect(f.coordinator.current!.origin, ContentOrigin.bundled);
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
      expect(File('pubspec.yaml').readAsStringSync(), contains('- content/starter/animated-symbols/'));
    });
  });
}

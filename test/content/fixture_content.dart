// A small, complete content tree for tests (no dependency on the generated
// content/brain-train/ tree, which is not in git): a registry of image and
// Lottie symbols, a few levels with content-addressed keys and a manifest,
// plus an HTTP server and a "starter pack" bundle over it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brain_train/content/asset_download_manager.dart';
import 'package:brain_train/content/content_cache.dart';
import 'package:brain_train/content/content_config.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_fetcher.dart';
import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/game_engine/models/board_config.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/level_rules.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/models/tile_definition.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final ContentConfig fixtureConfig = ContentConfig(
  baseUrl: Uri.parse('https://content.test/'),
  allowedHosts: const {'content.test'},
  retryBackoff: Duration.zero,
);

final Uint8List _pulse = File('test/fixtures/pulse.lottie.json').readAsBytesSync();

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// A PNG-signed blob, unique per [code] (content tests never decode it).
Uint8List _image(String code) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...utf8.encode('fixture $code')]);

/// A valid Lottie animation, unique per [code].
Uint8List _lottie(String code) {
  final json = jsonDecode(utf8.decode(_pulse)) as Map<String, Object?>..['nm'] = code;
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

class FixtureContent {
  /// [levels] levels of three pairs each. Level n uses static symbols
  /// S(n mod 10) and S((n + 3) mod 10) and, on even n, animated A(n mod 4),
  /// so each level has its own art set. [titles] overrides level titles
  /// (by order) to change those levels' bytes and keys.
  FixtureContent({
    this.levels = 12,
    this.version = '2026.1.1.1',
    Map<int, String> titles = const {},
    this.extraSymbols = 0,
  }) {
    final symbols = <String, SymbolDefinition>{};
    void addSymbol(String code, SymbolType type, String path, Uint8List bytes) {
      files[path] = bytes;
      symbols[code] = SymbolDefinition(code: code, type: type, assetPath: path, matchGroup: code, sha256: _sha(bytes));
    }

    for (var i = 0; i < 10 + extraSymbols; i++) {
      addSymbol('S$i', SymbolType.image, 'symbols/f/s$i.png', _image('S$i'));
    }
    for (var i = 0; i < 4; i++) {
      addSymbol('A$i', SymbolType.lottie, 'animated-symbols/a$i.json', _lottie('A$i'));
    }
    registry = SymbolRegistry(registryVersion: 'fixture-$extraSymbols', symbols: symbols);
    final registryBytes = utf8.encode(jsonEncode(registry.toJson()));
    registryPath = 'registries/symbols-${_sha(registryBytes).substring(0, 12)}.json';
    files[registryPath] = Uint8List.fromList(registryBytes);

    final entries = <Map<String, Object?>>[];
    for (var n = 1; n <= levels; n++) {
      final codes = ['S${n % 10}', 'S${(n + 3) % 10}', n.isEven ? 'A${n % 4}' : 'S${(n + 6) % 10}'];
      final id = 'level-${n.toString().padLeft(4, '0')}';
      final capacity = n % 4 == 0 ? 5 : 4;
      final level = LevelDefinition(
        levelId: id,
        title: titles[n] ?? 'Glade $n',
        difficulty: capacity == 5 ? 'hard' : 'easy',
        board: const BoardConfig(),
        rules: LevelRules(trayCapacity: capacity),
        tiles: [
          for (var k = 0; k < 6; k++)
            TileDefinition(tileId: 't$k', symbolCode: codes[k % 3], x: k * 4.0, y: 0, layer: 0),
        ],
      );
      final bytes = utf8.encode(jsonEncode(level.toJson()));
      final path = 'levels/$id-${_sha(bytes).substring(0, 12)}.json';
      files[path] = Uint8List.fromList(bytes);
      levelPaths[n] = path;
      levelArt[n] = {for (final code in codes.toSet()) symbols[code]!.assetPath!};
      entries.add({
        'levelId': id,
        'order': n,
        'title': level.title,
        'url': path,
        'sha256': _sha(bytes),
        'difficulty': level.difficulty,
        'tileCount': 6,
        'trayCapacity': capacity,
      });
    }
    manifest = {
      'schemaVersion': 1,
      'contentVersion': version,
      'compatibility': {'minClientContentSchema': 2},
      'symbolRegistry': {'url': registryPath, 'sha256': _sha(registryBytes)},
      'levels': entries,
    };
    files['manifest.json'] = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
  }

  final int levels;
  final String version;
  final int extraSymbols;
  final Map<String, Uint8List> files = {};
  late final SymbolRegistry registry;
  late final String registryPath;
  late final Map<String, Object?> manifest;

  /// Level file and art paths by level order.
  final Map<int, String> levelPaths = {};
  final Map<int, Set<String>> levelArt = {};

  String levelId(int order) => 'level-${order.toString().padLeft(4, '0')}';

  /// Every artwork path in the registry.
  Set<String> get allArt => {for (final s in registry.symbols.values) s.assetPath!};

  /// Art of levels [orders], each path once.
  Set<String> artOf(Iterable<int> orders) => {for (final n in orders) ...levelArt[n]!};

  /// Serves this tree under `/brain-train/`. [online] false makes every
  /// request fail like a dropped connection; [overrides] replace responses
  /// by content path. Every requested content path is added to [log].
  /// [before] runs first for every request (e.g. to hold responses).
  MockClient server({
    List<String>? log,
    Map<String, http.Response> overrides = const {},
    bool Function()? online,
    Future<void> Function()? before,
  }) =>
      MockClient((request) async {
        await before?.call();
        if (online != null && !online()) throw http.ClientException('offline', request.url);
        final path = Uri.decodeComponent(request.url.path).replaceFirst('/brain-train/', '');
        log?.add(path);
        final override = overrides[path];
        if (override != null) return override;
        final bytes = files[path];
        return bytes == null ? http.Response('missing', 404) : http.Response.bytes(bytes, 200);
      });

  /// The starter pack: manifest, registry, the first [count] levels and only
  /// their art.
  BundledContentSource starter({int count = 5}) {
    final keep = {'manifest.json', registryPath, for (var n = 1; n <= count; n++) levelPaths[n]!, ...artOf([for (var n = 1; n <= count; n++) n])};
    return BundledContentSource((key) async => keep.contains(key.substring('bundle/'.length)) ? files[key.substring('bundle/'.length)] : null, prefix: 'bundle/');
  }
}

/// A coordinator over [server] with an in-memory (or given) cache and the
/// [bundle] as starter pack (also used to seed downloads).
({ContentCoordinator coordinator, AssetDownloadManager downloads, ContentCache cache}) fixtureCoordinator({
  required http.Client server,
  required ContentSource bundle,
  MemoryContentStore? store,
  Set<String> Function()? completed,
  bool seed = true,
}) {
  final cache = ContentCache(store ?? MemoryContentStore());
  final fetcher = ContentFetcher(client: server, config: fixtureConfig, delay: (_) async {});
  final resolver = RemoteAssetResolver(fixtureConfig);
  final downloads = AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver, seed: seed ? bundle : null);
  final coordinator = ContentCoordinator(
    cache: cache,
    bundled: bundle,
    downloads: downloads,
    manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
    completedLevels: completed,
  );
  return (coordinator: coordinator, downloads: downloads, cache: cache);
}

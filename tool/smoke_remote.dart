// ignore_for_file: avoid_print

// Live check of published content with the app's own loading code.
//
//   dart run tool/smoke_remote.dart
//
// Starts from a pretend-old bundled copy so the live manifest counts as an
// update, then runs the full refresh: manifest, registry, every level and
// all artwork from production, with validation and caching. Unlike
// `flutter test`, this needs the network.

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
import 'package:brain_train/content/content_validator.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final config = ContentConfig.production;
  final fetcher = ContentFetcher(client: http.Client(), config: config);
  final resolver = RemoteAssetResolver(config);
  final cache = ContentCache(MemoryContentStore());
  final downloads = AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver);

  // Bundled copy from the repo, with its manifest version forced to "0".
  final bundled = BundledContentSource((key) async {
    final file = File(key);
    if (!file.existsSync()) return null;
    if (!key.endsWith('/manifest.json')) return file.readAsBytesSync();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>..['contentVersion'] = '0';
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  });

  final coordinator = ContentCoordinator(
    cache: cache,
    bundled: bundled,
    downloads: downloads,
    manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
  );
  await coordinator.loadInitial();
  final watch = Stopwatch()..start();
  final status = await coordinator.refresh();
  final snapshot = coordinator.current!;
  print('host        ${config.baseUrl.host}');
  print('status      ${status.name}${coordinator.lastError == null ? '' : ' (${coordinator.lastError})'}');
  print('version     ${snapshot.contentVersion} (${snapshot.origin.name})');
  print('levels      ${snapshot.playableEntries.length} playable (${snapshot.playableEntries.first.levelId} .. ${snapshot.playableEntries.last.levelId})');
  if (snapshot.levelErrors.isNotEmpty) print('level errors ${snapshot.levelErrors}');
  print('requests    ${downloads.networkRequests} objects in ${watch.elapsedMilliseconds} ms');
  print('cached      ${(await cache.store.sizes()).length} entries');

  // Sample levels across the campaign: downloaded, validated like the app,
  // solver-proven, and every symbol's art fetched from production and
  // checked (checksum, WebP signature or Lottie structure).
  var samplesOk = true;
  for (final order in [1, 57, 128, 200]) {
    final entry = snapshot.manifest.levels.where((e) => e.order == order).firstOrNull;
    final level = entry == null ? null : snapshot.levels[entry.levelId];
    if (entry == null || level == null) {
      print('sample      level $order MISSING');
      samplesOk = false;
      continue;
    }
    final report = const ContentValidator().validateLevel(level, snapshot.registry, checkSolvable: true, solverNodeBudget: 2000000);
    final codes = level.tiles.map((t) => t.symbolCode).toSet();
    var art = 0;
    for (final code in codes) {
      final symbol = snapshot.registry[code]!;
      final kind = ContentKind.forSymbol(symbol);
      if (kind == null) continue;
      final bytes = await cache.readObject(symbol.assetPath!, sha256: symbol.sha256);
      if (bytes == null) {
        print('sample      level $order: ${symbol.assetPath} not downloaded');
        samplesOk = false;
        continue;
      }
      if (kind == ContentKind.image) {
        checkImageSignature(bytes, symbol.assetPath!);
      } else {
        checkLottieJson(bytes, symbol.assetPath!);
      }
      art++;
    }
    final animated = level.tiles.where((t) => snapshot.registry[t.symbolCode]!.isAnimated).length;
    print(
      'sample      level $order ${entry.ref.url}: ${level.difficulty}, ${level.tiles.length} tiles, '
      'tray ${level.rules.trayCapacity}, ${codes.length} symbols (${animated ~/ 2}/${level.pairCount} pairs animated), '
      '$art art files ok, ${report.isValid ? 'valid, solvable in ${report.solve!.nodesVisited} nodes' : 'INVALID ${report.errors}'}  "${level.title}"',
    );
    samplesOk &= report.isValid && art == codes.length;
  }
  exitCode = status == ContentSyncStatus.updated && snapshot.levelErrors.isEmpty && samplesOk ? 0 : 1;
  exit(exitCode);
}

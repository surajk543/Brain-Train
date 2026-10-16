// ignore_for_file: avoid_print

// Live check of published content with the app's own loading code.
//
//   dart run tool/smoke_remote.dart
//
// 1. A fresh install as shipped (the committed starter pack, content/starter/):
//    what the first launch downloads.
// 2. The lazy path from R2 alone (a bundle with only metadata, pretend-old):
//    manifest and registry, then the 5-level window with only its art, then
//    the window after ten wins, then level 1, the middle level and the last
//    level on demand, each validated like the app does plus the solver.
// Unlike `flutter test`, this needs the network.

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

const String starter = 'content/starter/';

Future<void> main() async {
  final config = ContentConfig.production;
  var ok = true;
  print('host        ${config.baseUrl.host}');

  // 1. Fresh install with the shipped starter pack.
  {
    final (coordinator, downloads) = _coordinator(config, _starterBundle(), seed: true);
    await coordinator.loadInitial();
    await coordinator.warmUp();
    final status = await coordinator.refresh();
    final window = await coordinator.maintainWindow();
    print('\nfresh install (starter pack ${coordinator.current!.contentVersion})');
    print('  status    ${status.name}; window ${window.window.first}..${window.window.last}: ${window.ready}/${window.window.length} ready');
    print('  downloads ${_summary(downloads)} (manifest fetched separately)');
    ok &= window.ready == window.window.length;
  }

  // 2. The lazy path from R2 alone.
  var won = <String>{};
  final (coordinator, downloads) = _coordinator(config, _metadataOnlyBundle(), seed: false, completed: () => won);
  await coordinator.loadInitial();
  var mark = _Mark(downloads);
  final status = await coordinator.refresh();
  final snapshot = coordinator.current!;
  print('\nlazy path (no level files bundled)');
  print('  status    ${status.name}${coordinator.lastError == null ? '' : ' (${coordinator.lastError})'}');
  print('  version   ${snapshot.contentVersion} (${snapshot.origin.name}), ${snapshot.manifest.levels.length} levels in the manifest, '
      'registry ${snapshot.registry.symbols.length} symbols');
  print('  metadata + window 1-5: ${mark.delta()}');
  ok &= status == ContentSyncStatus.updated;
  for (var n = 1; n <= 5; n++) {
    ok &= snapshot.isReady(snapshot.manifest.levels[n - 1].levelId);
  }
  final registryArt = snapshot.registry.symbols.values.where((s) => ContentKind.forSymbol(s) != null).length;
  print('  art       ${downloads.downloadedPaths.where(_isArt).length} of $registryArt registry art files fetched so far');

  won = {for (final e in snapshot.manifest.levels.take(10)) e.levelId};
  mark = _Mark(downloads);
  final window = await coordinator.maintainWindow();
  print('  after 10 wins: window ${window.window.first}..${window.window.last} ${window.ready}/${window.window.length} ready; ${mark.delta()}');
  ok &= window.ready == window.window.length && !window.offline;

  mark = _Mark(downloads);
  final again = await coordinator.maintainWindow();
  print('  again:    ${mark.delta()} (nothing twice)');
  ok &= again.ready == again.window.length && mark.files == 0;

  final last = snapshot.manifest.levels.map((e) => e.order).reduce((a, b) => a > b ? a : b);
  for (final order in {1, (last + 1) ~/ 2, last}) {
    final entry = snapshot.manifest.levels.firstWhere((e) => e.order == order);
    mark = _Mark(downloads);
    try {
      final ready = await coordinator.ensureLevel(entry);
      final level = ready.level;
      final report = const ContentValidator().validateLevel(level, ready.snapshot.registry, checkSolvable: true, solverNodeBudget: 2000000);
      final codes = level.tiles.map((t) => t.symbolCode).toSet();
      final animated = level.tiles.where((t) => ready.snapshot.registry[t.symbolCode]!.isAnimated).length;
      var art = 0;
      for (final symbol in ready.snapshot.assetSymbolsOf(level)) {
        final bytes = await coordinator.cache.readObject(symbol.assetPath!, sha256: symbol.sha256);
        if (bytes == null) continue;
        if (symbol.isAnimated) {
          checkLottieJson(bytes, symbol.assetPath!);
        } else {
          checkImageSignature(bytes, symbol.assetPath!);
        }
        art++;
      }
      print(
        '  level $order ${entry.ref.url}: ${level.difficulty}, ${level.tiles.length} tiles, tray ${level.rules.trayCapacity} '
        '(manifest ${entry.trayCapacity}), ${codes.length} symbols (${animated ~/ 2}/${level.pairCount} pairs animated), '
        '$art art files ok, ${report.isValid ? 'valid, solvable in ${report.solve!.nodesVisited} nodes' : 'INVALID ${report.errors}'}; '
        '${mark.delta()}  "${level.title}"',
      );
      ok &= report.isValid && art == ready.snapshot.assetSymbolsOf(level).length && entry.trayCapacity == level.rules.trayCapacity;
    } on Exception catch (error) {
      print('  level $order FAILED: $error');
      ok = false;
    }
  }
  print('\ntotal       ${_summary(downloads)}');
  print(ok ? 'OK' : 'FAILED');
  exit(ok ? 0 : 1);
}

bool _isArt(String path) => path.startsWith('symbols/') || path.startsWith('animated-symbols/');

String _summary(AssetDownloadManager downloads) {
  final art = downloads.downloadedPaths.where(_isArt).length;
  final levels = downloads.downloadedPaths.where((p) => p.startsWith('levels/')).length;
  return '${downloads.downloadedPaths.length} objects downloaded ($levels level files, $art symbol files, '
      '${(downloads.downloadedBytes / 1024).toStringAsFixed(0)} KB), ${downloads.seededObjects} copied from the bundle';
}

class _Mark {
  _Mark(this.downloads) : _paths = downloads.downloadedPaths.length, _bytes = downloads.downloadedBytes;

  final AssetDownloadManager downloads;
  final int _paths;
  final int _bytes;

  int get files => downloads.downloadedPaths.length - _paths;

  String delta() {
    final added = downloads.downloadedPaths.sublist(_paths);
    return '${added.length} downloaded (${added.where((p) => p.startsWith('levels/')).length} levels, '
        '${added.where(_isArt).length} symbol files, ${((downloads.downloadedBytes - _bytes) / 1024).toStringAsFixed(0)} KB)';
  }
}

(ContentCoordinator, AssetDownloadManager) _coordinator(
  ContentConfig config,
  ContentSource bundle, {
  required bool seed,
  Set<String> Function()? completed,
}) {
  final fetcher = ContentFetcher(client: http.Client(), config: config);
  final resolver = RemoteAssetResolver(config);
  final cache = ContentCache(MemoryContentStore());
  final downloads = AssetDownloadManager(cache: cache, fetcher: fetcher, resolver: resolver, seed: seed ? bundle : null);
  final coordinator = ContentCoordinator(
    cache: cache,
    bundled: bundle,
    downloads: downloads,
    manifests: ContentManifestService(fetcher: fetcher, resolver: resolver),
    completedLevels: completed,
  );
  return (coordinator, downloads);
}

BundledContentSource _starterBundle() => BundledContentSource((key) async {
  final file = File(key);
  return file.existsSync() ? file.readAsBytesSync() : null;
}, prefix: starter);

/// The starter pack's manifest (version forced to "0", so the live one is an
/// update) and registry, nothing else.
BundledContentSource _metadataOnlyBundle() {
  final manifest = jsonDecode(File('${starter}manifest.json').readAsStringSync()) as Map<String, Object?>;
  final registry = (manifest['symbolRegistry']! as Map<String, Object?>)['url']! as String;
  manifest['contentVersion'] = '0';
  return BundledContentSource((key) async {
    if (key == '${starter}manifest.json') return Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    if (key == '$starter$registry') return File(key).readAsBytesSync();
    return null;
  }, prefix: starter);
}

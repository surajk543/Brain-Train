// ignore_for_file: avoid_print

// Brain Train content tool. Pure Dart; run from the repository root.
//
//   dart run tool/content.dart build     # content-src/ -> content/brain-train/
//   dart run tool/content.dart validate  # check content/brain-train/ like the app + solver
//   dart run tool/content.dart stats     # simulated tray win rates per tier
//
// `build` generates the campaign from catalog `campaign` (tiers, counts,
// seed: see CampaignGenerator), proves every level solvable, writes the
// registry and levels with SHA-256 hashes, then the manifest. Levels and the
// registry are content-addressed (`levels/level-0001-<sha>.json`): a changed
// level gets a new key by itself, an unchanged one keeps its key, so
// published objects are never overwritten and unchanged ones are never
// uploaded or downloaded again. Files no longer referenced are removed from
// content/brain-train/ (they stay on R2).
//
// Symbols: entries of art/asset_sources.json (static WebP) and
// art/animated_sources.json (Lottie) with "status": "integrated" whose
// processed file exists. Both files are read fresh on every build.
// Each level gets floor(30% of its pairs) animated pairs (at least one),
// the rest static, from a per-level subset of each pool.

import 'dart:convert';
import 'dart:io';

import 'package:brain_train/content/content_exception.dart';
import 'package:brain_train/content/content_files.dart';
import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/content_validator.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/game_engine/campaign/campaign_config.dart';
import 'package:brain_train/game_engine/campaign/campaign_generator.dart';
import 'package:brain_train/game_engine/generator/level_generator.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/geometry/tile_availability.dart';
import 'package:brain_train/game_engine/geometry/tile_mask.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/validation/tray_simulator.dart';
import 'package:crypto/crypto.dart';

/// The full publishable tree (local build output, gitignored; publish.dart
/// uploads it to R2).
final Directory contentRoot = Directory('content/brain-train');

/// The starter pack bundled in the app: the manifest and registry (metadata
/// of every level) plus the first levels and only the art they use, so a
/// first launch without internet can play. Committed to git.
final Directory starterRoot = Directory('content/starter');
const String staticSourcesPath = 'art/asset_sources.json';
const String animatedSourcesPath = 'art/animated_sources.json';
const JsonEncoder pretty = JsonEncoder.withIndent('  ');
const ContentValidator validator = ContentValidator();

/// Solver budget for the proof every published level gets.
const int solverBudget = 2000000;

Future<void> main(List<String> args) async {
  if (!File('pubspec.yaml').existsSync()) fail('run from the repository root');
  switch (args.firstOrNull) {
    case 'build':
      await build(force: args.contains('--force'));
    case 'validate':
      exitCode = await validate() ? 0 : 1;
    case 'stats':
      await stats();
    default:
      stderr.writeln('usage: dart run tool/content.dart <build [--force] | validate | stats>');
      exitCode = 64;
  }
}

Never fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}

String sha(List<int> bytes) => sha256.convert(bytes).toString();

Object? readJson(String path) => jsonDecode(File(path).readAsStringSync());

/// Writes [text] to an immutable content path unless identical bytes exist.
void writeImmutable(String relative, String text, {required bool force}) {
  final file = File('${contentRoot.path}/$relative');
  if (file.existsSync() && file.readAsStringSync() != text && !force) {
    fail('$relative already exists with different content; bump its revision (or pass --force before first publish)');
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

String encodeLevel(LevelDefinition level) => encodeLevelFile(level);

String contentAddressed(String directory, String stem, String text) => contentAddressedPath(directory, stem, text);

Future<void> build({required bool force}) async {
  final catalog = readJson('content-src/catalog.json')! as Map<String, Object?>;
  final registrySpec = catalog['registry']! as Map<String, Object?>;
  final placeholder = registrySpec['placeholder'] == true;

  // Registry: integrated static art + integrated animated art.
  final statics = staticSymbols(placeholder: placeholder, fallbackSet: registrySpec['imageSet'] as String?);
  final animated = animatedSymbols();
  for (final code in animated.keys) {
    if (statics.containsKey(code)) fail('$code is both a static and an animated symbol');
  }
  final symbols = {...statics, ...animated};
  // The version names the symbol table, so it changes exactly when a symbol does.
  final table = jsonEncode({for (final e in symbols.entries) e.key: e.value.toJson()});
  final registryVersion = '${registrySpec['registryVersion'] ?? 'brain-train-symbols'}-${sha(utf8.encode(table)).substring(0, 8)}';
  final registry = SymbolRegistry(registryVersion: registryVersion, symbols: symbols);
  final registryText = '${pretty.convert(registry.toJson())}\n';
  final registryPath = contentAddressed('registries', 'symbols', registryText);
  writeImmutable(registryPath, registryText, force: force);
  print('registry  $registryPath (${statics.length} static, ${animated.length} animated${placeholder ? ', PLACEHOLDER art' : ''})');

  final entries = <LevelManifestEntry>[];
  final written = <String>{registryPath};
  final campaignJson = catalog['campaign'];
  final levels = <CampaignLevel>[];
  if (campaignJson != null) {
    final config = CampaignConfig.fromJson(campaignJson);
    final watch = Stopwatch()..start();
    final generator = CampaignGenerator(config: config, staticPool: statics.keys.toList(), animatedPool: animated.keys.toList());
    for (final generated in generator.generate()) {
      final level = generated.level;
      final report = validator.validateLevel(level, registry, checkSolvable: true, solverNodeBudget: solverBudget);
      if (!report.isValid) fail('${level.levelId}: ${report.errors.join('; ')}');
      final text = encodeLevel(level);
      final path = contentAddressed('levels', level.levelId, text);
      writeImmutable(path, text, force: force);
      written.add(path);
      entries.add(
        LevelManifestEntry(
          levelId: level.levelId,
          order: generated.order,
          title: level.title,
          ref: ContentRef(url: path, sha256: sha(utf8.encode(text))),
          difficulty: level.difficulty,
          category: config.category,
          tileCount: level.tiles.length,
          trayCapacity: level.rules.trayCapacity,
        ),
      );
      levels.add(generated);
      print(
        'level     $path  ${generated.tier.id.padRight(8)} ${_describe(level, registry)}, '
        '${generated.shape.family}/${generated.shape.stacking}, free ${generated.freeAtStart}, '
        'tray ${level.rules.trayCapacity}, sim win ${_pct(generated.simulation.winRate)} '
        '(pair-seeking ${_pct(generated.pairSeekingSimulation.winRate)}), solved in ${report.solve!.nodesVisited} nodes  "${level.title}"',
      );
    }
    print('campaign  ${levels.length} levels in ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    _printCampaignSummary(config, levels, statics.keys.toSet(), animated.keys.toSet());
  }

  // Hand-authored layouts (optional) follow the campaign.
  for (final spec in ((catalog['levels'] as List<Object?>?) ?? const []).cast<Map<String, Object?>>()) {
    final layout = readJson('content-src/${spec['layout']}')! as Map<String, Object?>;
    final template = LayoutTemplate.fromJson(layout, defaultAnimatedSymbols: animated.keys.toList());
    final level = const LevelGenerator().generate(template);
    final report = validator.validateLevel(level, registry, checkSolvable: true, solverNodeBudget: solverBudget);
    if (!report.isValid) fail('${level.levelId}: ${report.errors.join('; ')}');
    final text = encodeLevel(level);
    final path = contentAddressed('levels', level.levelId, text);
    writeImmutable(path, text, force: force);
    written.add(path);
    entries.add(
      LevelManifestEntry(
        levelId: level.levelId,
        order: entries.length + 1,
        title: level.title,
        ref: ContentRef(url: path, sha256: sha(utf8.encode(text))),
        difficulty: level.difficulty,
        category: spec['category'] as String?,
        tileCount: level.tiles.length,
        trayCapacity: level.rules.trayCapacity,
      ),
    );
    print('level     $path  ${_describe(level, registry)}  solved in ${report.solve!.nodesVisited} nodes');
  }
  if (entries.isEmpty) fail('catalog has no campaign and no levels');

  // Animated symbols need client content schema 2. Older builds then reject
  // this manifest as a whole and keep their known-good content, instead of
  // installing it with every level that has an animated tile missing.
  // Trays other than 4/5 and numeric difficulty tiers need schema 3, for the
  // same reason.
  final usesAnimation = _usesAnimation(entries, registry);
  final usesSchema3 = entries.any(
    (e) =>
        (e.trayCapacity != null && e.trayCapacity != 4 && e.trayCapacity != 5) ||
        (e.difficulty != null && numericDifficulty(e.difficulty!) != null),
  );
  if (animated.isEmpty) print('animated  none processed: levels are 100% static (see $animatedSourcesPath)');
  final manifest = LevelManifest(
    schemaVersion: 1,
    contentVersion: catalog['contentVersion']! as String,
    minClientContentSchema: usesSchema3 ? 3 : (usesAnimation ? 2 : 1),
    publishedAt: DateTime.now().toUtc().toIso8601String().split('.').first.replaceFirst('T', ' '),
    symbolRegistry: ContentRef(url: registryPath, sha256: sha(utf8.encode(registryText))),
    levels: entries,
  );
  final manifestErrors = validator.validateManifest(manifest);
  if (manifestErrors.isNotEmpty) fail('manifest: ${manifestErrors.join('; ')}');
  // Same content as the current manifest: keep it (and its publishedAt), so
  // an unchanged rebuild changes no file.
  final manifestFile = File('${contentRoot.path}/manifest.json');
  Object? withoutDate(Object? json) => json is Map<String, Object?> ? ({...json}..remove('publishedAt')) : json;
  final previous = manifestFile.existsSync() ? withoutDate(jsonDecode(manifestFile.readAsStringSync())) : null;
  if (jsonEncode(previous) != jsonEncode(withoutDate(manifest.toJson()))) {
    manifestFile.writeAsStringSync('${pretty.convert(manifest.toJson())}\n');
  }
  print(
    'manifest  manifest.json  contentVersion ${manifest.contentVersion}'
    ', minClientContentSchema ${manifest.minClientContentSchema}',
  );

  // Generated files the manifest no longer references (published copies on
  // R2 are immutable and stay; the bundle should not carry them).
  var pruned = 0;
  for (final directory in ['levels', 'registries']) {
    final dir = Directory('${contentRoot.path}/$directory');
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync().whereType<File>()) {
      if (!written.contains('$directory/${file.uri.pathSegments.last}')) {
        file.deleteSync();
        pruned++;
      }
    }
  }
  if (pruned > 0) print('pruned    $pruned unreferenced level/registry files from ${contentRoot.path}');

  writeStarterPack(manifest, registry, count: (catalog['starterLevels'] as int?) ?? 5);
}

/// Copies the manifest, the registry, the first [count] levels and exactly
/// the art they use into [starterRoot], removing anything else there.
void writeStarterPack(LevelManifest manifest, SymbolRegistry registry, {required int count}) {
  final paths = starterPaths(manifest, registry, count: count);
  final keep = <String>{};
  var bytes = 0;
  for (final path in paths) {
    final source = File('${contentRoot.path}/$path');
    final target = File('${starterRoot.path}/$path');
    final data = source.readAsBytesSync();
    bytes += data.length;
    keep.add(target.path);
    if (target.existsSync() && sha(target.readAsBytesSync()) == sha(data)) continue;
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(data);
  }
  var removed = 0;
  if (starterRoot.existsSync()) {
    for (final file in starterRoot.listSync(recursive: true).whereType<File>()) {
      if (!keep.contains(file.path)) {
        file.deleteSync();
        removed++;
      }
    }
  }
  final art = paths.where((p) => p.startsWith('symbols/') || p.startsWith('animated-symbols/')).length;
  print(
    'starter   ${starterRoot.path}: manifest, registry, levels 1-$count, $art art files '
    '(${(bytes / 1024).toStringAsFixed(0)} KB)${removed == 0 ? '' : ', removed $removed old files'}',
  );
}

/// The content paths of the starter pack: manifest, registry, the first
/// [count] levels and the art files they use.
List<String> starterPaths(LevelManifest manifest, SymbolRegistry registry, {required int count}) {
  final levels = manifest.levels.take(count).toList();
  final art = <String>{};
  for (final entry in levels) {
    final level = LevelDefinition.fromJson(readJson('${contentRoot.path}/${entry.ref.url}'));
    for (final tile in level.tiles) {
      final symbol = registry[tile.symbolCode];
      if (symbol != null && ContentKind.forSymbol(symbol) != null) art.add(symbol.assetPath!);
    }
  }
  return ['manifest.json', manifest.symbolRegistry.url, for (final e in levels) e.ref.url, ...(art.toList()..sort())];
}

String _pct(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

void _printCampaignSummary(CampaignConfig config, List<CampaignLevel> levels, Set<String> statics, Set<String> animated) {
  print('\ntier       levels  tiles     layers  tray  free%      sim win avg (min-max)    pair-seeking  distinct sym  anim share max  anim distinct max');
  for (final tier in config.tiers) {
    final ls = levels.where((l) => l.tier.id == tier.id).toList();
    if (ls.isEmpty) continue;
    int minOf(int Function(CampaignLevel) f) => ls.map(f).reduce((a, b) => a < b ? a : b);
    int maxOf(int Function(CampaignLevel) f) => ls.map(f).reduce((a, b) => a > b ? a : b);
    double avg(double Function(CampaignLevel) f) => ls.map(f).reduce((a, b) => a + b) / ls.length;
    final rates = ls.map((l) => l.simulation.winRate).toList()..sort();
    print(
      '${tier.id.padRight(10)} ${ls.length.toString().padLeft(6)}  '
      '${'${minOf((l) => l.level.tiles.length)}-${maxOf((l) => l.level.tiles.length)}'.padRight(8)}  '
      '${'${minOf((l) => l.layers)}-${maxOf((l) => l.layers)}'.padRight(6)}  ${'${minOf((l) => l.level.rules.trayCapacity)}-${maxOf((l) => l.level.rules.trayCapacity)}'.padRight(4)}  '
      '${(avg((l) => l.freeAtStart / l.level.tiles.length) * 100).toStringAsFixed(0).padRight(9)}  '
      '${'${_pct(avg((l) => l.simulation.winRate))} (${_pct(rates.first)}-${_pct(rates.last)})'.padRight(23)}  '
      '${_pct(avg((l) => l.pairSeekingSimulation.winRate)).padRight(12)}  '
      '${'${minOf((l) => l.staticSymbols.length + l.animatedSymbols.length)}-${maxOf((l) => l.staticSymbols.length + l.animatedSymbols.length)}'.padRight(12)}  '
      '${_pct(ls.map((l) => l.animatedPairs / l.pairs).reduce((a, b) => a > b ? a : b)).padRight(14)}  '
      '${maxOf((l) => l.animatedSymbols.length)}',
    );
  }
  final staticUses = <String, int>{for (final c in statics) c: 0};
  final animatedUses = <String, int>{for (final c in animated) c: 0};
  for (final l in levels) {
    for (final c in l.staticSymbols) {
      staticUses[c] = staticUses[c]! + 1;
    }
    for (final c in l.animatedSymbols) {
      animatedUses[c] = animatedUses[c]! + 1;
    }
  }
  String spread(Map<String, int> uses) {
    if (uses.isEmpty) return 'none';
    final counts = uses.values.toList()..sort();
    final unused = [for (final e in uses.entries) if (e.value == 0) e.key];
    return '${uses.length - unused.length}/${uses.length} used, levels per symbol ${counts.first}-${counts.last}'
        '${unused.isEmpty ? '' : ', UNUSED: ${unused.join(', ')}'}';
  }

  var maxOverlap = 0.0;
  for (var i = 1; i < levels.length; i++) {
    final a = {...levels[i - 1].staticSymbols, ...levels[i - 1].animatedSymbols};
    final b = {...levels[i].staticSymbols, ...levels[i].animatedSymbols};
    final jaccard = a.intersection(b).length / a.union(b).length;
    if (jaccard > maxOverlap) maxOverlap = jaccard;
  }
  print('\nsymbols   static ${spread(staticUses)}');
  print('          animated ${spread(animatedUses)}');
  print('          neighbouring levels share at most ${_pct(maxOverlap)} of their symbol set');
  final animatedShare = [for (final l in levels) l.animatedPairs / l.pairs];
  print('          animated pairs per level ${_pct(animatedShare.reduce((a, b) => a < b ? a : b))}-${_pct(animatedShare.reduce((a, b) => a > b ? a : b))}');
  final unused = [...staticUses.entries, ...animatedUses.entries].where((e) => e.value == 0).toList();
  if (unused.isNotEmpty) fail('symbols used by no level: ${unused.map((e) => e.key).join(', ')}');
}

/// `image` registry entries for every integrated static source whose
/// processed WebP exists, in the order of [staticSourcesPath].
Map<String, SymbolDefinition> staticSymbols({required bool placeholder, String? fallbackSet}) {
  final json = readJson(staticSourcesPath)! as Map<String, Object?>;
  final imageSet = json['imageSet'] as String? ?? fallbackSet ?? fail('$staticSourcesPath has no imageSet');
  final symbols = <String, SymbolDefinition>{};
  final waiting = <String>[];
  for (final raw in (json['symbols']! as List<Object?>).cast<Map<String, Object?>>()) {
    final code = raw['code']! as String;
    if (raw['status'] != 'integrated') {
      waiting.add(code);
      continue;
    }
    final assetPath = 'symbols/$imageSet/${raw['outputFile']}';
    final image = File('${contentRoot.path}/$assetPath');
    if (!image.existsSync()) {
      print('note      $code is "integrated" but $assetPath is missing; left out (run tool/assets/prepare_symbols.py)');
      continue;
    }
    symbols[code] = SymbolDefinition(
      code: code,
      type: SymbolType.image,
      assetPath: assetPath,
      matchGroup: code,
      label: raw['title']! as String,
      sha256: sha(image.readAsBytesSync()),
      isPlaceholder: placeholder,
      sourceUrl: raw['sourceUrl'] as String?,
    );
  }
  if (waiting.isNotEmpty) print('static    ${waiting.length} not yet integrated: ${waiting.join(', ')}');
  return symbols;
}

/// `lottie` registry entries for every integrated animated source whose
/// processed file exists, in the order of [animatedSourcesPath]. Prints what
/// is missing.
Map<String, SymbolDefinition> animatedSymbols() {
  final file = File(animatedSourcesPath);
  if (!file.existsSync()) return const {};
  final json = readJson(file.path)! as Map<String, Object?>;
  final packUrl = json['packUrl'] as String?;
  final symbols = <String, SymbolDefinition>{};
  final missing = <String>[];
  final waiting = <String>[];
  for (final raw in (json['symbols']! as List<Object?>).cast<Map<String, Object?>>()) {
    final code = raw['code']! as String;
    if (raw['status'] != 'integrated') {
      waiting.add(code);
      continue;
    }
    final assetPath = 'animated-symbols/${raw['outputFile']}';
    final processed = File('${contentRoot.path}/$assetPath');
    if (!processed.existsSync()) {
      missing.add(code);
      continue;
    }
    final bytes = processed.readAsBytesSync();
    try {
      checkLottieJson(bytes, assetPath);
    } on ContentException catch (error) {
      fail('$assetPath: $error; re-run tool/assets/prepare_animated.py');
    }
    symbols[code] = SymbolDefinition(
      code: code,
      type: SymbolType.lottie,
      assetPath: assetPath,
      matchGroup: code,
      label: raw['title']! as String,
      sha256: sha(bytes),
      sourceUrl: raw['sourceUrl'] as String? ?? packUrl,
    );
  }
  if (waiting.isNotEmpty) print('animated  ${waiting.length} not yet integrated: ${waiting.join(', ')}');
  if (missing.isNotEmpty) {
    print(
      'animated  ${symbols.length} processed, ${missing.length} integrated but awaiting files: ${missing.join(', ')}'
      ' (put Lottie JSON in art/source/animated-symbols/, run tool/assets/prepare_animated.py)',
    );
  }
  return symbols;
}

bool _usesAnimation(Iterable<LevelManifestEntry> entries, SymbolRegistry registry) {
  for (final entry in entries) {
    final level = LevelDefinition.fromJson(readJson('${contentRoot.path}/${entry.ref.url}'));
    if (level.tiles.any((t) => registry[t.symbolCode]?.isAnimated ?? false)) return true;
  }
  return false;
}

String _describe(LevelDefinition level, SymbolRegistry registry) {
  final layers = level.tiles.map((t) => t.layer).reduce((a, b) => a > b ? a : b) + 1;
  final symbols = level.tiles.map((t) => t.symbolCode).toSet().length;
  final animated = level.tiles.where((t) => registry[t.symbolCode]?.isAnimated ?? false).length;
  final pairs = level.tiles.length ~/ 2;
  return '${level.tiles.length} tiles, $layers layers, $symbols symbols'
      '${animated == 0 ? '' : ', ${animated ~/ 2}/$pairs pairs animated'}';
}

/// Validates the publishable tree exactly as the app would load it from R2,
/// plus solvability and image checks the app does not repeat.
Future<bool> validate() async {
  final source = BundledContentSource((key) async {
    final file = File(key);
    return file.existsSync() ? file.readAsBytesSync() : null;
  });
  var ok = true;
  void problem(String message) {
    ok = false;
    stderr.writeln('FAIL  $message');
  }

  try {
    final json = decodeJsonBytes(await source.read('manifest.json', ContentKind.json), 'manifest.json');
    final manifest = ContentManifestService.parseAndValidate(json, validator, 'manifest.json');
    final registry = await const SymbolRegistryRepository().load(manifest.symbolRegistry, source);
    print(
      'manifest  ${manifest.contentVersion}: ${manifest.levels.length} levels, registry ${registry.registryVersion}',
    );
    if (registry.rejected.isNotEmpty) problem('rejected symbols: ${registry.rejected}');
    for (final symbol in registry.symbols.values) {
      final kind = ContentKind.forSymbol(symbol);
      if (kind == null) continue;
      try {
        final bytes = await source.read(symbol.assetPath!, kind, sha256: symbol.sha256);
        var detail = '';
        if (kind == ContentKind.animation) {
          final info = checkLottieJson(bytes, symbol.assetPath!);
          detail =
              '  [animated ${info.seconds.toStringAsFixed(1)}s @ ${info.frameRate}fps, ${bytes.length ~/ 1024} KB]';
        } else {
          checkImageSignature(bytes, symbol.assetPath!);
        }
        print(
          'symbol    ${symbol.code.padRight(11)} ${symbol.assetPath}${symbol.isPlaceholder ? '  [placeholder]' : ''}$detail',
        );
      } on ContentException catch (error) {
        problem('symbol ${symbol.code}: $error');
      }
    }
    var usesAnimation = false;
    for (final entry in manifest.levels) {
      try {
        final level = await const LevelRepository().load(entry, registry, source);
        final report = validator.validateLevel(
          level,
          registry,
          expectedLevelId: entry.levelId,
          checkSolvable: true,
          solverNodeBudget: 2000000,
        );
        if (!report.isValid) {
          problem('${entry.levelId}: ${report.errors.join('; ')}');
        } else {
          print(
            'level     ${entry.levelId}  ${_describe(level, registry)}  solvable (${report.solve!.nodesVisited} nodes)',
          );
        }
        usesAnimation |= level.tiles.any((t) => registry[t.symbolCode]?.isAnimated ?? false);
      } on ContentException catch (error) {
        problem('${entry.levelId}: $error');
      }
    }
    // The starter pack: the same manifest and registry, the first levels and
    // exactly their art, byte for byte.
    final count = ((readJson('content-src/catalog.json')! as Map<String, Object?>)['starterLevels'] as int?) ?? 5;
    final expected = starterPaths(manifest, registry, count: count).toSet();
    final present = {
      if (starterRoot.existsSync())
        for (final file in starterRoot.listSync(recursive: true).whereType<File>())
          file.path.substring(starterRoot.path.length + 1),
    };
    if (present.difference(expected).isNotEmpty) problem('starter pack has extra files: ${present.difference(expected)}');
    if (expected.difference(present).isNotEmpty) problem('starter pack is missing: ${expected.difference(present)}');
    for (final path in expected.intersection(present)) {
      if (sha(File('${starterRoot.path}/$path').readAsBytesSync()) != sha(File('${contentRoot.path}/$path').readAsBytesSync())) {
        problem('starter pack $path differs from ${contentRoot.path}/$path; run build');
      }
    }
    print('starter   ${expected.length} files match (levels 1-$count, ${expected.where((p) => p.contains('symbols/')).length} art files)');
    if (usesAnimation && manifest.minClientContentSchema < 2) {
      problem(
        'levels use animated symbols but manifest minClientContentSchema is ${manifest.minClientContentSchema}; needs 2',
      );
    }
  } on ContentException catch (error) {
    problem(error.toString());
  }
  print(ok ? 'OK' : 'INVALID');
  return ok;
}

/// Loads content/brain-train/ like the app and plays every level with the
/// simulated tray players; prints win rates per tier.
Future<void> stats({int runs = 200}) async {
  final source = BundledContentSource((key) async {
    final file = File(key);
    return file.existsSync() ? file.readAsBytesSync() : null;
  });
  final json = decodeJsonBytes(await source.read('manifest.json', ContentKind.json), 'manifest.json');
  final manifest = ContentManifestService.parseAndValidate(json, validator, 'manifest.json');
  final registry = await const SymbolRegistryRepository().load(manifest.symbolRegistry, source);
  final byTier = <String, List<(LevelDefinition, TraySimulation, TraySimulation, int)>>{};
  for (final entry in manifest.levels) {
    final level = await const LevelRepository().load(entry, registry, source);
    final geometry = BoardGeometry.build(level);
    final simulator = TraySimulator.forRules(
      geometry,
      MatchRules(level: level, registry: registry),
      capacity: level.rules.trayCapacity,
    );
    final free = TileAvailabilityCalculator(geometry).freeTiles(TileMask.all(level.tiles.length)).length;
    (byTier[level.difficulty ?? '-'] ??= []).add((
      level,
      simulator.run(runs: runs, seed: 1),
      simulator.run(runs: runs, seed: 2, player: TrayPlayer.pairSeeking),
      free,
    ));
  }
  print('contentVersion ${manifest.contentVersion}: ${manifest.levels.length} levels, $runs simulated games each');
  print('tier          levels  tiles    layers  tray  free%  random player win (min-max)  pair-seeking win');
  for (final MapEntry(key: tier, value: rows) in byTier.entries) {
    double avg(double Function((LevelDefinition, TraySimulation, TraySimulation, int)) f) =>
        rows.map(f).reduce((a, b) => a + b) / rows.length;
    final tiles = rows.map((r) => r.$1.tiles.length).toList()..sort();
    final layers = rows.map((r) => r.$1.tiles.map((t) => t.layer).reduce((a, b) => a > b ? a : b) + 1).toList()..sort();
    final rates = rows.map((r) => r.$2.winRate).toList()..sort();
    final trays = rows.map((r) => r.$1.rules.trayCapacity).toSet().join('/');
    print(
      '${difficultyLabel(tier).padRight(14)}${rows.length.toString().padLeft(6)}  ${'${tiles.first}-${tiles.last}'.padRight(7)}  '
      '${'${layers.first}-${layers.last}'.padRight(6)}  ${trays.padRight(4)}  ${(avg((r) => r.$4 / r.$1.tiles.length) * 100).toStringAsFixed(0).padLeft(4)}   '
      '${'${_pct(avg((r) => r.$2.winRate))} (${_pct(rates.first)}-${_pct(rates.last)})'.padRight(27)}  ${_pct(avg((r) => r.$3.winRate))}',
    );
  }
}

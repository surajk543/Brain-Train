import 'dart:convert';
import 'dart:io';

import 'package:brain_train/content/content_files.dart';
import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/content_validator.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/features/gameplay/game_layout.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/game_engine/campaign/board_shapes.dart';
import 'package:brain_train/game_engine/campaign/campaign_config.dart';
import 'package:brain_train/game_engine/campaign/campaign_generator.dart';
import 'package:brain_train/game_engine/campaign/tier_schedule.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/game_engine/validation/tray_simulator.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Integrated symbol codes in an art source file.
Set<String> integrated(String path) => {
  for (final s in (jsonDecode(File(path).readAsStringSync())['symbols'] as List))
    if ((s as Map)['status'] == 'integrated') s['code'] as String,
};

/// Checks the published content without the generated tree (which is not in
/// git): the committed starter pack carries the manifest (every level)
/// and the registry, and the campaign is regenerated from the catalog with
/// the registry's symbols. Every regenerated level must hash to its manifest
/// entry, so the checks below cover the exact published files.
void main() {
  final catalog = jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map<String, Object?>;
  final campaign = CampaignConfig.fromJson(catalog['campaign']);
  final starterLevels = (catalog['starterLevels'] as int?) ?? 5;

  late LevelManifest manifest;
  late SymbolRegistry registry;
  late List<LevelDefinition> levels;

  setUpAll(() async {
    final json = decodeJsonBytes(await repoContent.read('manifest.json', ContentKind.json), 'manifest.json');
    manifest = ContentManifestService.parseAndValidate(json, const ContentValidator(), 'manifest.json');
    registry = await const SymbolRegistryRepository().load(manifest.symbolRegistry, repoContent);
    final generated = CampaignGenerator(
      config: campaign,
      staticPool: [for (final s in registry.symbols.values) if (s.type == SymbolType.image) s.code],
      animatedPool: [for (final s in registry.symbols.values) if (s.isAnimated) s.code],
    ).generate();
    levels = [for (final g in generated) g.level];
  });

  test('the catalog regenerates exactly the published levels', () {
    expect(manifest.contentVersion, catalog['contentVersion']);
    expect(levels, hasLength(manifest.levels.length));
    for (final (i, level) in levels.indexed) {
      final entry = manifest.levels[i];
      final text = encodeLevelFile(level);
      expect(entry.ref.sha256, sha256.convert(utf8.encode(text)).toString(), reason: '${entry.levelId} bytes');
      expect(entry.ref.url, contentAddressedPath('levels', level.levelId, text));
    }
  });

  test('the manifest lists every level in order with tier, size and tray', () {
    final count = campaign.levelCount;
    expect(manifest.levels.map((e) => e.order), [for (var i = 1; i <= count; i++) i]);
    expect(manifest.levels.map((e) => e.levelId), [for (var i = 1; i <= count; i++) 'level-${i.toString().padLeft(4, '0')}']);
    for (final (i, entry) in manifest.levels.indexed) {
      expect(entry.difficulty, levels[i].difficulty);
      expect(entry.tileCount, levels[i].tiles.length);
      expect(entry.trayCapacity, levels[i].rules.trayCapacity, reason: 'lists never need the level file');
      expect(entry.title, levels[i].title);
    }
    expect(manifest.minClientContentSchema, 3, reason: 'trays of 2-3 slots and numeric tiers need client content schema 3');
  });

  test('the starter pack: levels 1-5, exactly their art, and nothing else', () async {
    final files = {
      for (final f in Directory('content/starter').listSync(recursive: true).whereType<File>())
        f.path.substring('content/starter/'.length),
    };
    final art = {
      for (final level in levels.take(starterLevels))
        for (final t in level.tiles)
          if (ContentKind.forSymbol(registry[t.symbolCode]!) != null) registry[t.symbolCode]!.assetPath!,
    };
    expect(files, {
      'manifest.json',
      manifest.symbolRegistry.url,
      for (final e in manifest.levels.take(starterLevels)) e.ref.url,
      ...art,
    });
    for (final entry in manifest.levels.take(starterLevels)) {
      await const LevelRepository().load(entry, registry, repoContent);
    }
    for (final path in art) {
      final symbol = registry.symbols.values.firstWhere((s) => s.assetPath == path);
      final bytes = await repoContent.read(path, ContentKind.forSymbol(symbol)!, sha256: symbol.sha256);
      if (symbol.isAnimated) {
        checkLottieJson(bytes, path);
      } else {
        checkImageSignature(bytes, path);
      }
    }
  });

  test('the registry holds only integrated symbols, all valid, all used', () {
    expect(registry.rejected, isEmpty);
    final integratedCodes = {...integrated('art/asset_sources.json'), ...integrated('art/animated_sources.json')};
    expect(registry.symbols.keys.toSet().difference(integratedCodes), isEmpty);
    for (final symbol in registry.symbols.values) {
      expect(symbol.sha256, isNotNull);
      expect(symbol.isPlaceholder, isFalse);
      expect(
        symbol.assetPath,
        symbol.isAnimated ? allOf(startsWith('animated-symbols/'), endsWith('.json')) : endsWith('.webp'),
      );
    }
    final used = {for (final level in levels) ...level.tiles.map((t) => t.symbolCode)};
    expect(used, registry.symbols.keys.toSet(), reason: 'every integrated symbol appears in some level');
  });

  test('difficulty 1-10: batch counts, shuffled, level 1 is 1, never three in a row, stored with labels', () {
    final order = [for (final level in levels) level.difficulty!];
    expect(order, scheduleTiers(campaign), reason: 'the seeded schedule');
    expect(order.first, '1');
    expect(longestRun(order), lessThanOrEqualTo(2));
    expect({for (final id in order) id: order.where((t) => t == id).length}, {
      for (final t in campaign.tiers) t.id: campaign.batches.fold<int>(0, (n, b) => n + (b[t.id] ?? 0)),
    });
    expect(order.toSet().map(difficultyLabel), {for (var d = 1; d <= 10; d++) '$d/10'});
  });

  test('tiers differ in size, depth, symbols, free tiles and tray', () {
    final byTier = <String, List<LevelDefinition>>{};
    for (final level in levels) {
      (byTier[level.difficulty!] ??= []).add(level);
    }
    int layers(LevelDefinition l) => l.tiles.map((t) => t.layer).reduce((a, b) => a > b ? a : b) + 1;
    double freeShare(LevelDefinition l) {
      final geometry = BoardGeometry.build(l);
      final free = [
        for (var i = 0; i < l.tiles.length; i++)
          if (geometry.coveredBy[i].isEmpty && (geometry.leftNeighbors[i].isEmpty || geometry.rightNeighbors[i].isEmpty)) i,
      ];
      return free.length / l.tiles.length;
    }

    double mean(Iterable<num> values) => values.fold(0.0, (a, b) => a + b) / values.length;
    final ids = [for (final t in campaign.tiers) t.id];
    for (final id in ids) {
      final tier = campaign.tier(id);
      for (final level in byTier[id]!) {
        expect(level.tiles.length, inInclusiveRange(tier.minTiles, tier.maxTiles), reason: level.levelId);
        expect(layers(level), inInclusiveRange(tier.minLayers, tier.maxLayers), reason: level.levelId);
        expect(level.rules.trayCapacity, inInclusiveRange(tier.trayCapacity, tier.maxTrayCapacity), reason: level.levelId);
      }
    }
    for (var i = 1; i < ids.length; i++) {
      final easier = byTier[ids[i - 1]]!, harder = byTier[ids[i]]!;
      expect(mean(harder.map((l) => l.tiles.length)), greaterThan(mean(easier.map((l) => l.tiles.length))), reason: ids[i]);
      expect(mean(harder.map((l) => l.rules.trayCapacity)), lessThanOrEqualTo(mean(easier.map((l) => l.rules.trayCapacity))), reason: ids[i]);
    }
    expect(mean(byTier['10']!.map(layers)), greaterThan(mean(byTier['5']!.map(layers))));
    expect(mean(byTier['5']!.map(layers)), greaterThan(mean(byTier['1']!.map(layers))));
    expect(mean(byTier['10']!.map(freeShare)), lessThan(mean(byTier['1']!.map(freeShare))));
    expect(byTier['10']!.map((l) => l.tiles.length).reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(campaign.tier('10').minTiles));
  });

  test('the simulated tray player wins less from tier to tier', () {
    final rates = <String, List<double>>{};
    for (final level in levels) {
      final simulator = TraySimulator.forRules(
        BoardGeometry.build(level),
        MatchRules(level: level, registry: registry),
        capacity: level.rules.trayCapacity,
      );
      (rates[level.difficulty!] ??= []).add(simulator.run(runs: 60, seed: 5).winRate);
    }
    double mean(String id) => rates[id]!.reduce((a, b) => a + b) / rates[id]!.length;
    expect(mean('1'), greaterThanOrEqualTo(0.6));
    for (var d = 2; d <= 10; d++) {
      expect(mean('$d'), lessThanOrEqualTo(mean('${d - 1}') + 0.05), reason: 'difficulty $d');
    }
    expect(mean('10'), lessThan(mean('5')));
    expect(mean('5'), lessThan(mean('1')));
    expect(mean('10'), lessThanOrEqualTo(0.05));
  });

  test('85/15 symbols: floor(15%) of pairs animated (at least one), at most 12 distinct animated', () {
    expect(campaign.animatedShare, 0.15);
    for (final level in levels) {
      final pairs = level.pairCount;
      final animatedTiles = level.tiles.where((t) => registry[t.symbolCode]!.isAnimated).toList();
      expect(animatedTiles.length ~/ 2, (pairs * 0.15).floor().clamp(1, pairs), reason: level.levelId);
      expect(animatedTiles.map((t) => t.symbolCode).toSet().length, lessThanOrEqualTo(campaign.maxDistinctAnimated));
    }
  });

  test('no symbol has more than maxPairsPerSymbol pairs on a level', () {
    expect(campaign.maxPairsPerSymbol, 2);
    for (final level in levels) {
      final counts = <String, int>{};
      for (final tile in level.tiles) {
        counts[tile.symbolCode] = (counts[tile.symbolCode] ?? 0) + 1;
      }
      for (final MapEntry(:key, :value) in counts.entries) {
        expect(value, lessThanOrEqualTo(2 * campaign.maxPairsPerSymbol!), reason: '${level.levelId} $key');
      }
    }
  });

  test('every level validates and is solver-proven', () {
    for (final level in levels) {
      final report = const ContentValidator().validateLevel(level, registry, checkSolvable: true, solverNodeBudget: 2000000);
      expect(report.isValid, isTrue, reason: '${level.levelId}: ${report.errors}');
      expect(report.solve!.outcome, SolveOutcome.solvable);
    }
  });

  test('every board fits a 360x640 phone with playable tiles', () {
    const style = TileStyle.classicIvory;
    // The board's room on the real gameplay screen of a 360x640 phone (24-px
    // status bar): the full width, the height GameLayout leaves it. The
    // campaign generator assumes 360 x kSmallBoardHeight; the screen must
    // never give less.
    const screen = Size(360, 640), safe = EdgeInsets.only(top: 24);
    final board = Size(screen.width, GameLayout.of(screen, safe).boardHeight(screen, safe));
    expect(board.height, greaterThanOrEqualTo(kSmallBoardHeight));
    var smallest = double.infinity;
    for (final level in levels) {
      final projection = boardProjectionFor(level, BoardGeometry.build(level), style, board);
      expect(projection.faceWidth, greaterThanOrEqualTo(campaign.minFaceWidth - 0.01), reason: level.levelId);
      if (projection.faceWidth < smallest) smallest = projection.faceWidth;
    }
    printOnFailure('smallest face ${smallest.toStringAsFixed(2)} px on a ${board.width}x${board.height} board');
  });

  test('unique nature titles, a backdrop each, neighbours with different symbol sets', () {
    expect(levels.map((l) => l.title).toSet(), hasLength(levels.length));
    for (final level in levels) {
      expect(level.title, matches(RegExp(r'^[A-Z][a-z]+( [A-Z][a-z]+)+$')));
      expect(level.backdrop?.colors, hasLength(3));
    }
    for (var i = 1; i < levels.length; i++) {
      final a = levels[i - 1].tiles.map((t) => t.symbolCode).toSet();
      final b = levels[i].tiles.map((t) => t.symbolCode).toSet();
      expect(a, isNot(equals(b)), reason: levels[i].levelId);
    }
  });

  test('pubspec bundles only the starter pack', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dir in ['manifest.json', 'registries/', 'levels/', 'symbols/v1/', 'animated-symbols/']) {
      expect(pubspec, contains('- content/starter/$dir'));
    }
    expect(pubspec, isNot(contains('content/brain-train')), reason: 'the full tree lives on R2 only');
    expect(File('.gitignore').readAsStringSync(), contains('/content/brain-train/'));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:brain_train/content/content_repositories.dart';
import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/content/content_validator.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/content/remote_asset_resolver.dart';
import 'package:brain_train/game_engine/campaign/campaign_config.dart';
import 'package:brain_train/game_engine/campaign/tier_schedule.dart';
import 'package:brain_train/game_engine/geometry/board_geometry.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/validation/solver.dart';
import 'package:brain_train/game_engine/validation/tray_simulator.dart';
import 'package:brain_train/features/gameplay/widgets/board_view.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Integrated symbol codes in an art source file (others are still being
/// prepared and must not be published).
Set<String> integrated(String path) => {
  for (final s in (jsonDecode(File(path).readAsStringSync())['symbols'] as List))
    if ((s as Map)['status'] == 'integrated') s['code'] as String,
};

/// Checks the exact files that are bundled in the app and published to R2.
void main() {
  final staticCodes = integrated('art/asset_sources.json');
  final animatedCodes = integrated('art/animated_sources.json');
  final campaign = CampaignConfig.fromJson(
    (jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map)['campaign'],
  );

  late LevelManifest manifest;
  late SymbolRegistry registry;
  late List<LevelDefinition> levels;

  setUpAll(() async {
    final json = decodeJsonBytes(await repoContent.read('manifest.json', ContentKind.json), 'manifest.json');
    manifest = ContentManifestService.parseAndValidate(json, const ContentValidator(), 'manifest.json');
    registry = await const SymbolRegistryRepository().load(manifest.symbolRegistry, repoContent);
    levels = [for (final entry in manifest.levels) await const LevelRepository().load(entry, registry, repoContent)];
  });

  test('the manifest lists levels 1-200 in order, with tier, size and checksum', () {
    expect(manifest.levels, hasLength(200));
    expect(manifest.levels.map((e) => e.order), [for (var i = 1; i <= 200; i++) i]);
    expect(manifest.levels.map((e) => e.levelId), [for (var i = 1; i <= 200; i++) 'level-${i.toString().padLeft(4, '0')}']);
    expect(manifest.contentVersion, (jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map)['contentVersion']);
    for (final (i, entry) in manifest.levels.indexed) {
      expect(entry.ref.sha256, isNotNull);
      expect(entry.ref.url, startsWith('levels/${entry.levelId}-'), reason: 'content-addressed key');
      expect(entry.difficulty, levels[i].difficulty);
      expect(entry.tileCount, levels[i].tiles.length);
      expect(entry.title, levels[i].title);
    }
    expect(manifest.minClientContentSchema, 2, reason: 'animated symbols need client content schema 2');
  });

  test('the registry holds only integrated symbols, all valid, all used', () async {
    expect(registry.rejected, isEmpty);
    expect(registry.symbols.keys.toSet().difference({...staticCodes, ...animatedCodes}), isEmpty);
    for (final symbol in registry.symbols.values) {
      if (animatedCodes.contains(symbol.code)) {
        expect(symbol.type, SymbolType.lottie);
        expect(symbol.assetPath, allOf(startsWith('animated-symbols/'), endsWith('.json')));
        final bytes = await repoContent.read(symbol.assetPath!, ContentKind.animation, sha256: symbol.sha256);
        checkLottieJson(bytes, symbol.assetPath!);
        continue;
      }
      expect(symbol.type, SymbolType.image);
      expect(symbol.assetPath, endsWith('.webp'));
      expect(symbol.isPlaceholder, isFalse);
      final bytes = await repoContent.read(symbol.assetPath!, ContentKind.image, sha256: symbol.sha256);
      checkImageSignature(bytes, symbol.assetPath!);
    }
    final used = {for (final level in levels) ...level.tiles.map((t) => t.symbolCode)};
    expect(used, registry.symbols.keys.toSet(), reason: 'every integrated symbol appears in some level');
  });

  test('tiers: 50 each, shuffled, level 1 easy, never three in a row, stored with labels', () {
    final order = [for (final level in levels) level.difficulty!];
    expect(order, scheduleTiers(campaign), reason: 'the seeded schedule');
    expect(order.first, 'easy');
    expect(longestRun(order), lessThanOrEqualTo(2));
    expect({for (final id in order) id: order.where((t) => t == id).length}, {
      'easy': 50,
      'medium': 50,
      'hard': 50,
      'veryHard': 50,
    });
    expect(order.toSet().map(difficultyLabel), {'Easy', 'Medium', 'Hard', 'Very Hard'});
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
    final ids = ['easy', 'medium', 'hard', 'veryHard'];
    for (final id in ids) {
      final tier = campaign.tier(id);
      for (final level in byTier[id]!) {
        expect(level.tiles.length, inInclusiveRange(tier.minTiles, tier.maxTiles), reason: level.levelId);
        expect(layers(level), inInclusiveRange(tier.minLayers, tier.maxLayers), reason: level.levelId);
        expect(level.rules.trayCapacity, id == 'easy' || id == 'medium' ? 4 : 5, reason: level.levelId);
      }
    }
    for (var i = 1; i < ids.length; i++) {
      final easier = byTier[ids[i - 1]]!, harder = byTier[ids[i]]!;
      expect(mean(harder.map((l) => l.tiles.length)), greaterThan(mean(easier.map((l) => l.tiles.length))));
      expect(mean(harder.map(layers)), greaterThan(mean(easier.map(layers))));
      expect(
        mean(harder.map((l) => l.tiles.map((t) => t.symbolCode).toSet().length)),
        greaterThan(mean(easier.map((l) => l.tiles.map((t) => t.symbolCode).toSet().length))),
      );
    }
    expect(mean(byTier['veryHard']!.map(freeShare)), lessThan(mean(byTier['easy']!.map(freeShare))));
    expect(byTier['veryHard']!.map((l) => l.tiles.length).reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(144));
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
    expect(mean('easy'), greaterThanOrEqualTo(0.6));
    expect(mean('medium'), lessThan(mean('easy')));
    expect(mean('hard'), lessThan(mean('medium')));
    expect(mean('veryHard'), lessThan(mean('hard')));
    expect(mean('veryHard'), lessThanOrEqualTo(0.05));
  });

  test('70/30 symbols: floor(30%) of pairs animated (at least one), at most 12 distinct animated', () {
    for (final level in levels) {
      final pairs = level.pairCount;
      final animatedTiles = level.tiles.where((t) => registry[t.symbolCode]!.isAnimated).toList();
      expect(animatedTiles.length ~/ 2, (pairs * 0.3).floor().clamp(1, pairs), reason: level.levelId);
      expect(animatedTiles.length / level.tiles.length, lessThanOrEqualTo(0.3), reason: level.levelId);
      expect(animatedTiles.map((t) => t.symbolCode).toSet().length, lessThanOrEqualTo(campaign.maxDistinctAnimated));
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
    for (final level in levels) {
      final projection = boardProjectionFor(level, BoardGeometry.build(level), style, const Size(360, 433.5));
      expect(projection.faceWidth, greaterThanOrEqualTo(campaign.minFaceWidth - 0.01), reason: level.levelId);
    }
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

  test('pubspec bundles the fallback content', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('content/brain-train/manifest.json'));
    expect(pubspec, contains('content/brain-train/levels/'));
    expect(pubspec, contains('content/brain-train/registries/'));
    expect(pubspec, contains('content/brain-train/animated-symbols/'));
    for (final symbol in registry.symbols.values) {
      if (symbol.type == SymbolType.image) {
        expect(pubspec, contains('content/brain-train/${symbol.assetPath!.substring(0, symbol.assetPath!.lastIndexOf('/') + 1)}'));
      }
    }
    // Nothing unreferenced is bundled with the levels.
    final referenced = {for (final e in manifest.levels) e.ref.url};
    for (final file in Directory('content/brain-train/levels').listSync().whereType<File>()) {
      expect(referenced, contains('levels/${file.uri.pathSegments.last}'));
    }
  });
}

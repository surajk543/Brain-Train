import 'dart:convert';
import 'dart:io';

import 'package:brain_train/game_engine/campaign/campaign_config.dart';
import 'package:brain_train/game_engine/campaign/campaign_generator.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';

import '../helpers.dart';

List<String> _codes(String prefix, int count) => [for (var i = 0; i < count; i++) '$prefix$i'];

/// Symbols the hard levels draw from.
final SymbolRegistry hardRegistry = registry({..._codes('S', 60), ..._codes('A', 14)});

List<LevelDefinition>? _hard;

/// The catalog's difficulty-10 tier.
Map<String, Object?> _hardTier() => ((jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map)['campaign']
        as Map)['tiers']
    .cast<Map<String, Object?>>()
    .firstWhere((t) => t['id'] == '10');

/// The fewest tiles a difficulty-10 board has.
int hardMinTiles() => ((_hardTier()['tiles']! as List).first as num).toInt();

/// Boards like the campaign's hardest: the catalog's difficulty-10 tier (the
/// most tiles and layers, a 2-slot tray, 1.25 pairs per symbol), three
/// levels generated with a short simulation.
List<LevelDefinition> hardLevels() => _hard ??= () {
  final campaign = (jsonDecode(File('content-src/catalog.json').readAsStringSync()) as Map)['campaign'] as Map;
  final tier = (campaign['tiers'] as List).cast<Map<String, Object?>>().firstWhere((t) => t['id'] == '10');
  final config = CampaignConfig.fromJson({
    ...campaign.cast<String, Object?>(),
    'tiers': [tier],
    'batches': [
      {'10': 3},
    ],
    'firstTier': '10',
    'maxTierRun': 3,
    'simulationRuns': 20,
  });
  return [
    for (final generated in CampaignGenerator(
      config: config,
      staticPool: _codes('S', 60),
      animatedPool: _codes('A', 14),
    ).generate())
      generated.level,
  ];
}();

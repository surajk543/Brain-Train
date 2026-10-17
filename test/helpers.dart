import 'dart:io';
import 'dart:typed_data';

import 'package:brain_train/content/content_sources.dart';
import 'package:brain_train/game_engine/models/board_config.dart';
import 'package:brain_train/game_engine/models/level_definition.dart';
import 'package:brain_train/game_engine/models/level_rules.dart';
import 'package:brain_train/game_engine/models/symbol_definition.dart';
import 'package:brain_train/game_engine/models/symbol_registry.dart';
import 'package:brain_train/game_engine/models/tile_definition.dart';
import 'package:brain_train/game_engine/rules/match_rules.dart';
import 'package:brain_train/game_engine/state/game_engine.dart';

/// Tile spec: (id, symbol, x, y, layer). Footprints are 2x2 logical units.
typedef T = (String, String, double, double, int);

LevelDefinition level(List<T> tiles, {LevelRules rules = const LevelRules(), String id = 'test-level'}) =>
    LevelDefinition(
      levelId: id,
      title: 'Test',
      board: const BoardConfig(tileWidth: 2, tileHeight: 2),
      rules: rules,
      tiles: [for (final (tid, sym, x, y, l) in tiles) TileDefinition(tileId: tid, symbolCode: sym, x: x, y: y, layer: l)],
    );

SymbolRegistry registry(Iterable<String> codes, {Map<String, String> matchGroups = const {}}) => SymbolRegistry(
  registryVersion: 'test',
  symbols: {
    for (final code in codes)
      code: SymbolDefinition(code: code, type: SymbolType.text, value: code.substring(0, 1), matchGroup: matchGroups[code]),
  },
);

GameEngine engineFor(LevelDefinition level, SymbolRegistry registry) =>
    GameEngine(level: level, rules: MatchRules(level: level, registry: registry));

/// The starter pack the app bundles (manifest and registry of every level,
/// levels 1-5 and their art), read straight from the repository. Committed
/// to git, unlike the full generated tree.
final BundledContentSource repoContent = BundledContentSource((key) async {
  final file = File(key);
  return file.existsSync() ? file.readAsBytesSync() : null;
}, prefix: 'content/starter/');

/// Everything the app bundles (the starter pack, then the lobby hero's art,
/// `bundledContent`), read straight from the repository.
final ContentSource repoBundle = bundledContent((key) async {
  final file = File(key);
  return file.existsSync() ? file.readAsBytesSync() : null;
});

Uint8List bytesOf(String text) => Uint8List.fromList(text.codeUnits);

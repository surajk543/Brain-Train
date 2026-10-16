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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

/// Published content, read straight from the repository.
final BundledContentSource repoContent = BundledContentSource((key) async {
  final file = File(key);
  return file.existsSync() ? file.readAsBytesSync() : null;
});

/// An HTTP client serving `content/<path>` for `/brain-train/<path>`, with
/// optional per-path overrides (status code or bytes).
MockClient contentServer({
  Map<String, http.Response> overrides = const {},
  List<String>? log,
}) => MockClient((request) async {
  final path = request.url.path;
  log?.add(path);
  final override = overrides[path];
  if (override != null) return override;
  final file = File('content${Uri.decodeComponent(path)}');
  if (!file.existsSync()) return http.Response('missing', 404);
  return http.Response.bytes(file.readAsBytesSync(), 200);
});

Uint8List bytesOf(String text) => Uint8List.fromList(text.codeUnits);

import 'dart:collection';

import '../game_engine/models/level_definition.dart';
import '../game_engine/models/symbol_definition.dart';
import '../game_engine/models/symbol_registry.dart';
import 'content_sources.dart';
import 'level_manifest.dart';
import 'remote_asset_resolver.dart';

enum ContentOrigin {
  /// Shipped inside the app (the starter pack); always available.
  bundled,

  /// Last known-good remote content, loaded from the device cache.
  cached,

  /// Fetched from R2 during this session.
  remote,
}

/// One content version: its manifest and symbol registry, plus the levels
/// of it that are on the device so far.
///
/// The manifest lists every level (title, tier, tile count, tray size), so
/// lists and panels never need a level file. Level files are loaded on
/// demand: [levels] starts with what the device already holds (cache and
/// bundle) and grows as the coordinator downloads more; a loaded level never
/// changes. A game keeps the snapshot it started with, so a background
/// update can never change the meaning of the board being played.
class ContentSnapshot {
  ContentSnapshot({
    required this.manifest,
    required this.manifestJson,
    required this.registry,
    Map<String, LevelDefinition> levels = const {},
    Map<String, String> levelErrors = const {},
    Set<String> ready = const {},
    required this.origin,
    required this.artwork,
  }) : _levels = {...levels},
       _errors = {...levelErrors},
       _ready = {...ready};

  final LevelManifest manifest;
  final Object? manifestJson;
  final SymbolRegistry registry;
  final ContentOrigin origin;

  /// Where image and animated symbols are read from (cache, then bundle).
  final ContentSource artwork;

  final Map<String, LevelDefinition> _levels;
  final Map<String, String> _errors;
  final Set<String> _ready;

  /// Valid levels loaded so far, by id.
  Map<String, LevelDefinition> get levels => UnmodifiableMapView(_levels);

  /// Levels that failed to load for a content reason (not a missing
  /// connection), with the reason. They are not offered.
  Map<String, String> get levelErrors => UnmodifiableMapView(_errors);

  String get contentVersion => manifest.contentVersion;

  /// Manifest entries that can be played, in order: every level except the
  /// ones known to be broken, whether or not its file is on the device yet.
  List<LevelManifestEntry> get playableEntries => [
    for (final entry in manifest.levels)
      if (!_errors.containsKey(entry.levelId)) entry,
  ];

  /// True once the level and every artwork file it uses are on the device:
  /// it opens at once and plays offline.
  bool isReady(String levelId) => _ready.contains(levelId) && _levels.containsKey(levelId);

  /// Symbols of [level] that have an artwork file (image or animation).
  List<SymbolDefinition> assetSymbolsOf(LevelDefinition level) => [
    for (final code in {for (final tile in level.tiles) tile.symbolCode})
      if (registry[code] case final symbol? when ContentKind.forSymbol(symbol) != null) symbol,
  ];

  /// For the coordinator: a level file that was loaded (and, with [ready],
  /// whose artwork is cached too).
  void addLevel(LevelDefinition level, {bool ready = false}) {
    _levels.putIfAbsent(level.levelId, () => level);
    _errors.remove(level.levelId);
    if (ready) _ready.add(level.levelId);
  }

  /// For the coordinator: a level that cannot be used in this version.
  void addError(String levelId, String reason) {
    if (!_levels.containsKey(levelId)) _errors[levelId] = reason;
  }
}

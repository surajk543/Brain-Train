import '../game_engine/models/level_definition.dart';
import '../game_engine/models/symbol_definition.dart';
import '../game_engine/models/symbol_registry.dart';
import 'content_sources.dart';
import 'level_manifest.dart';
import 'remote_asset_resolver.dart';

enum ContentOrigin {
  /// Shipped inside the app; always available.
  bundled,

  /// Last known-good remote content, loaded from the device cache.
  cached,

  /// Fetched from R2 during this session.
  remote,
}

/// One immutable, fully validated content version.
///
/// A game keeps the snapshot it started with, so a background update can
/// never change the meaning of the board being played.
class ContentSnapshot {
  ContentSnapshot({
    required this.manifest,
    required this.manifestJson,
    required this.registry,
    required Map<String, LevelDefinition> levels,
    required Map<String, String> levelErrors,
    required this.origin,
    required this.artwork,
  }) : levels = Map.unmodifiable(levels),
       levelErrors = Map.unmodifiable(levelErrors);

  final LevelManifest manifest;
  final Object? manifestJson;
  final SymbolRegistry registry;

  /// Valid levels by id.
  final Map<String, LevelDefinition> levels;

  /// Levels listed in the manifest that failed to load, with the reason.
  final Map<String, String> levelErrors;
  final ContentOrigin origin;

  /// Where image and animated symbols are read from (cache, then bundle).
  final ContentSource artwork;

  String get contentVersion => manifest.contentVersion;

  /// Manifest entries that can be played, in order.
  List<LevelManifestEntry> get playableEntries => [
    for (final entry in manifest.levels)
      if (levels.containsKey(entry.levelId)) entry,
  ];

  /// Every content path this snapshot uses; the cache keeps exactly these.
  Set<String> get referencedPaths => {
    manifest.symbolRegistry.url,
    for (final entry in manifest.levels) entry.ref.url,
    for (final symbol in registry.symbols.values)
      if (ContentKind.forSymbol(symbol) != null) symbol.assetPath!,
  };

  /// Symbols with an artwork file (image or animation) used by at least one
  /// valid level: everything a refresh must download before committing.
  Iterable<SymbolDefinition> get usedAssetSymbols {
    final codes = {
      for (final level in levels.values)
        for (final tile in level.tiles) tile.symbolCode,
    };
    return [
      for (final code in codes)
        if (registry[code] case final symbol? when ContentKind.forSymbol(symbol) != null) symbol,
    ];
  }

  /// Image symbols used by at least one valid level.
  Iterable<SymbolDefinition> get usedImageSymbols => usedAssetSymbols.where((s) => s.type == SymbolType.image);

  /// Animated (Lottie) symbols used by at least one valid level.
  Iterable<SymbolDefinition> get usedAnimatedSymbols => usedAssetSymbols.where((s) => s.type == SymbolType.lottie);
}

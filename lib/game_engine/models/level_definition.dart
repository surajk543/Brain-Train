import 'board_config.dart';
import 'json_reader.dart';
import 'level_rules.dart';
import 'tile_definition.dart';

/// Level schema versions this build understands.
const Set<int> kSupportedLevelSchemas = {1};

/// Optional per-level background palette: 2-4 `#RRGGBB` colours the game
/// screen blends into soft light behind its frosted-glass panels.
class LevelBackdrop {
  const LevelBackdrop({required this.colors});

  factory LevelBackdrop.fromJson(JsonReader json) => LevelBackdrop(colors: json.stringList('colors'));

  final List<String> colors;

  Map<String, Object?> toJson() => {'colors': colors};
}

/// Tile face colours a level may give single pairs (`faceColors`), besides
/// the usual ivory. Never green, so the tiles stand out on the felt. Builds
/// that predate the field ignore it and draw those tiles ivory.
const List<String> kFaceColorNames = ['gold', 'sky', 'blush', 'lavender', 'peach'];

/// An immutable, screen-independent level: tiles, board geometry and rules.
class LevelDefinition {
  LevelDefinition({
    this.schemaVersion = 1,
    required this.levelId,
    required this.title,
    this.difficulty,
    this.tileSetId = 'classic-ivory',
    this.board = const BoardConfig(),
    required List<TileDefinition> tiles,
    this.rules = const LevelRules(),
    this.backdrop,
    Map<String, String> faceColors = const {},
  }) : tiles = List.unmodifiable(tiles),
       faceColors = Map.unmodifiable(faceColors);

  /// Parses the JSON shape. Semantic checks (unique IDs, symbols, overlaps,
  /// solvability) belong to `LevelValidator`.
  factory LevelDefinition.fromJson(Object? decoded) {
    final json = JsonReader(decoded);
    return LevelDefinition(
      schemaVersion: json.integer('schemaVersion'),
      levelId: json.string('levelId'),
      title: json.optString('title') ?? json.string('levelId'),
      difficulty: json.optString('difficulty'),
      tileSetId: json.optString('tileSetId') ?? 'classic-ivory',
      board: BoardConfig.fromJson(json.object('board')),
      tiles: json.objectList('tiles').map(TileDefinition.fromJson).toList(),
      rules: json.has('rules') ? LevelRules.fromJson(json.object('rules')) : const LevelRules(),
      backdrop: json.has('backdrop') ? LevelBackdrop.fromJson(json.object('backdrop')) : null,
      faceColors: json.has('faceColors') ? json.stringMap('faceColors') : const {},
    );
  }

  final int schemaVersion;
  final String levelId;
  final String title;
  final String? difficulty;
  final String tileSetId;
  final BoardConfig board;
  final List<TileDefinition> tiles;
  final LevelRules rules;

  /// Rendering only; null uses the app's default palette.
  final LevelBackdrop? backdrop;

  /// Rendering only: symbol code -> face colour name ([kFaceColorNames]) for
  /// the pairs whose tiles are not ivory. Matching never looks at it. Names
  /// this build does not know draw ivory.
  final Map<String, String> faceColors;

  /// The face colour of tile [index], or null for ivory.
  String? faceColorOf(int index) {
    final name = faceColors[tiles[index].symbolCode];
    return name != null && kFaceColorNames.contains(name) ? name : null;
  }

  int get pairCount => tiles.length ~/ 2;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'levelId': levelId,
    'title': title,
    if (difficulty != null) 'difficulty': difficulty,
    'tileSetId': tileSetId,
    'board': board.toJson(),
    'rules': rules.toJson(),
    if (backdrop != null) 'backdrop': backdrop!.toJson(),
    if (faceColors.isNotEmpty) 'faceColors': faceColors,
    'tiles': [for (final tile in tiles) tile.toJson()],
  };
}

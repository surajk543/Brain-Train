import 'json_reader.dart';

/// One tile slot of a level.
///
/// Coordinates are logical board units, not pixels. `(x, y)` is the top-left
/// corner of the tile's footprint; the footprint size comes from
/// [BoardConfig.tileWidth] and [BoardConfig.tileHeight]. `layer` 0 is the
/// table surface; higher layers sit on top.
class TileDefinition {
  const TileDefinition({
    required this.tileId,
    required this.symbolCode,
    required this.x,
    required this.y,
    required this.layer,
  });

  factory TileDefinition.fromJson(JsonReader json) => TileDefinition(
    tileId: json.string('tileId'),
    symbolCode: json.string('symbolCode'),
    x: json.number('x'),
    y: json.number('y'),
    layer: json.integer('layer'),
  );

  final String tileId;
  final String symbolCode;
  final double x;
  final double y;
  final int layer;

  Map<String, Object?> toJson() => {
    'tileId': tileId,
    'symbolCode': symbolCode,
    'x': compactNumber(x),
    'y': compactNumber(y),
    'layer': layer,
  };

  @override
  String toString() => 'Tile($tileId $symbolCode @$x,$y L$layer)';
}

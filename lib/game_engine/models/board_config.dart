import 'json_reader.dart';

/// Board-wide geometry parameters of a level.
class BoardConfig {
  const BoardConfig({
    this.tileWidth = 2,
    this.tileHeight = 2,
    this.layerOffsetX = -0.07,
    this.layerOffsetY = -0.07,
  });

  factory BoardConfig.fromJson(JsonReader json) => BoardConfig(
    tileWidth: json.number('tileWidth'),
    tileHeight: json.number('tileHeight'),
    layerOffsetX: json.numberOr('layerOffsetX', -0.07),
    layerOffsetY: json.numberOr('layerOffsetY', -0.07),
  );

  /// Footprint width of one tile, in logical board units.
  ///
  /// Brain Train levels use 2x2 footprints so half-tile offsets stay integers.
  final double tileWidth;

  /// Footprint height of one tile, in logical board units.
  final double tileHeight;

  /// Visual shift applied per layer, as a fraction of the rendered face width.
  /// Negative values move higher layers left. Rendering only; never geometry.
  final double layerOffsetX;

  /// Visual shift applied per layer, as a fraction of the rendered face height.
  /// Negative values move higher layers up. Rendering only; never geometry.
  final double layerOffsetY;

  Map<String, Object?> toJson() => {
    'tileWidth': compactNumber(tileWidth),
    'tileHeight': compactNumber(tileHeight),
    'layerOffsetX': layerOffsetX,
    'layerOffsetY': layerOffsetY,
  };
}

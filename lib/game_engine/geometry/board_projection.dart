import 'board_geometry.dart';

/// A rectangle in logical pixels.
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool contains(double x, double y) => x >= left && x < right && y >= top && y < bottom;
}

/// Maps logical board coordinates to screen pixels for one viewport size.
///
/// Rendering and hit testing both read [faceRect], so a tap always lands on
/// the tile that is drawn there.
class BoardProjection {
  BoardProjection._({
    required this.geometry,
    required this.faceWidth,
    required this.faceHeight,
    required this.originX,
    required this.originY,
    required this.unitX,
    required this.unitY,
    required this.layerShiftX,
    required this.layerShiftY,
    required this.boardRect,
  }) : _faces = List.generate(geometry.length, (i) {
         final tile = geometry.tiles[i];
         return PixelRect(
           originX + tile.footprint.left * unitX + tile.layer * layerShiftX,
           originY + tile.footprint.top * unitY + tile.layer * layerShiftY,
           faceWidth,
           faceHeight,
         );
       }, growable: false);

  /// Fits the whole board, including side walls and layer shifts, into
  /// [width] x [height], centred, keeping the tile face proportions.
  ///
  /// [faceAspect] is face width / face height. [edgeFraction] is how far the
  /// tile body and shadow extend past the face (right and bottom), as a
  /// fraction of face width. [layerOffsetX]/[layerOffsetY] are per-layer
  /// shifts as fractions of face width/height.
  factory BoardProjection.fit({
    required BoardGeometry geometry,
    required double tileWidth,
    required double tileHeight,
    required double width,
    required double height,
    required double faceAspect,
    required double edgeFraction,
    required double layerOffsetX,
    required double layerOffsetY,
    double padding = 8,
    double maxFaceHeight = 140,
  }) {
    final bounds = geometry.bounds;
    final layers = bounds.maxLayer;
    // Board size per pixel of face height.
    final perHeightX =
        faceAspect * (bounds.width / tileWidth) + faceAspect * edgeFraction + faceAspect * layerOffsetX.abs() * layers;
    final perHeightY = bounds.height / tileHeight + faceAspect * edgeFraction + layerOffsetY.abs() * layers;
    final availableX = (width - 2 * padding).clamp(1.0, double.infinity);
    final availableY = (height - 2 * padding).clamp(1.0, double.infinity);
    var faceHeight = maxFaceHeight;
    if (perHeightX > 0) faceHeight = faceHeight < availableX / perHeightX ? faceHeight : availableX / perHeightX;
    if (perHeightY > 0) faceHeight = faceHeight < availableY / perHeightY ? faceHeight : availableY / perHeightY;
    final faceWidth = faceHeight * faceAspect;
    final unitX = faceWidth / tileWidth;
    final unitY = faceHeight / tileHeight;
    final shiftX = layerOffsetX * faceWidth;
    final shiftY = layerOffsetY * faceHeight;
    final contentWidth = perHeightX * faceHeight;
    final contentHeight = perHeightY * faceHeight;
    final left = padding + (availableX - contentWidth) / 2;
    final top = padding + (availableY - contentHeight) / 2;
    final leftExtra = shiftX < 0 ? -shiftX * layers : 0.0;
    final topExtra = shiftY < 0 ? -shiftY * layers : 0.0;
    return BoardProjection._(
      geometry: geometry,
      faceWidth: faceWidth,
      faceHeight: faceHeight,
      originX: left + leftExtra - bounds.minX * unitX,
      originY: top + topExtra - bounds.minY * unitY,
      unitX: unitX,
      unitY: unitY,
      layerShiftX: shiftX,
      layerShiftY: shiftY,
      boardRect: PixelRect(left, top, contentWidth, contentHeight),
    );
  }

  final BoardGeometry geometry;
  final double faceWidth;
  final double faceHeight;
  final double originX;
  final double originY;
  final double unitX;
  final double unitY;
  final double layerShiftX;
  final double layerShiftY;

  /// The pixel area the whole board occupies.
  final PixelRect boardRect;

  final List<PixelRect> _faces;

  /// The on-screen face of tile [index] (side walls and shadow excluded).
  PixelRect faceRect(int index) => _faces[index];
}

/// Finds the tile under a pointer using the shared projection.
class TileHitTester {
  const TileHitTester(this.projection);

  final BoardProjection projection;

  /// The topmost tile, among those for which [isPresent] is true, whose face
  /// contains the point. Blocked tiles are returned too so the UI can explain
  /// why they cannot be picked.
  int? hitTest(double x, double y, bool Function(int index) isPresent) {
    final order = projection.geometry.drawOrder;
    for (var k = order.length - 1; k >= 0; k--) {
      final index = order[k];
      if (isPresent(index) && projection.faceRect(index).contains(x, y)) return index;
    }
    return null;
  }
}

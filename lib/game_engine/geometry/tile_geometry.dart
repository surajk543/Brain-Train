/// Tolerance for comparing logical coordinates (levels may use fractions).
const double kGeometryEpsilon = 1e-6;

/// An axis-aligned rectangle in logical board units.
class LogicalRect {
  const LogicalRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  /// True when the two rectangles share a region of positive area.
  /// Touching edges do not overlap.
  bool overlaps(LogicalRect other) =>
      _overlapLength(left, right, other.left, other.right) > kGeometryEpsilon &&
      _overlapLength(top, bottom, other.top, other.bottom) > kGeometryEpsilon;

  /// True when the vertical spans share a positive length.
  bool sharesRowsWith(LogicalRect other) =>
      _overlapLength(top, bottom, other.top, other.bottom) > kGeometryEpsilon;

  bool contains(double x, double y) => x >= left && x < right && y >= top && y < bottom;

  static double _overlapLength(double a0, double a1, double b0, double b1) =>
      (a1 < b1 ? a1 : b1) - (a0 > b0 ? a0 : b0);

  @override
  String toString() => 'LogicalRect($left, $top, $right, $bottom)';
}

/// The footprint and layer of one tile.
class TileGeometry {
  const TileGeometry({required this.index, required this.footprint, required this.layer});

  final int index;
  final LogicalRect footprint;
  final int layer;
}

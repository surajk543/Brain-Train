/// The fixed board grid (owner, 2026-10-17): every campaign board, with all
/// its layers and half offsets, fits [kBoardGridColumns] x [kBoardGridRows]
/// tiles, at most [kBoardGridLayers] layers deep. The app fits this grid, not
/// the level, into the board area, so every level shows its tiles at the same
/// size (smaller boards are centred, not enlarged). The content tool rejects
/// boards outside it. Shared by the app (`boardProjectionFor`) and the tools.
const int kBoardGridColumns = 7;
const int kBoardGridRows = 9;
const int kBoardGridLayers = 4;

/// A logical area a projection reserves room for: [width] x [height] units
/// with the layer shifts of [maxLayer] layers above the first.
class BoardGridSpan {
  const BoardGridSpan({required this.width, required this.height, required this.maxLayer});

  /// The fixed campaign grid for footprints of [tileWidth] x [tileHeight].
  factory BoardGridSpan.campaign({double tileWidth = 2, double tileHeight = 2}) => BoardGridSpan(
    width: kBoardGridColumns * tileWidth,
    height: kBoardGridRows * tileHeight,
    maxLayer: kBoardGridLayers - 1,
  );

  final double width;
  final double height;
  final int maxLayer;
}

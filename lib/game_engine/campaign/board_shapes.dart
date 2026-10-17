import 'dart:math' as math;

import '../generator/level_generator.dart';
import '../geometry/board_grid.dart';

/// A tile position on one layer: logical `x`, `y` of the footprint's
/// top-left corner (footprints are 2x2, so `+1` is a half-tile offset).
typedef Cell = (int, int);

/// Tile face aspect and edge reach of the classic-ivory tile set
/// (`TileStyle.classicIvory`; a Flutter test keeps them in sync). Used to
/// check that a board fits a small phone without importing Flutter.
const double kFitFaceAspect = 0.76;
const double kFitEdgeFraction = 0.2999;
const double kFitLayerOffset = 0.07;

/// The gameplay board area of a 360x640 phone (measured in the capture
/// tests), and the board's padding inside it.
const double kSmallBoardWidth = 360;
const double kSmallBoardHeight = 433.5;
const double kBoardPadding = 4;

/// One procedurally built board: a mirror-symmetric base shape and the
/// layers stacked on it.
class BoardShape {
  BoardShape({
    required this.family,
    required this.variant,
    required this.stacking,
    required this.columns,
    required this.rows,
    required List<Set<Cell>> layers,
  }) : layers = List.unmodifiable(layers.map(Set<Cell>.unmodifiable));

  /// Shape family id, e.g. `turtle`, `ring`.
  final String family;
  final String variant;

  /// Stacking program id, e.g. `pyramid`, `stagger`.
  final String stacking;

  /// Base grid size in tiles.
  final int columns;
  final int rows;

  /// Layer 0 first. Every tile above layer 0 sits half a tile off the tiles
  /// below it (never exactly on one), rests on at least half a tile of the
  /// layer directly below and lies wholly over lower tiles.
  final List<Set<Cell>> layers;

  int get tileCount => layers.fold(0, (sum, layer) => sum + layer.length);
  int get layerCount => layers.length;

  String get describe => '$family/$variant/$stacking ${columns}x$rows';

  /// Slots, layer by layer, each layer in reading order.
  List<LayoutSlot> get slots => [
    for (var l = 0; l < layers.length; l++)
      for (final (x, y) in (layers[l].toList()..sort(_readingOrder))) LayoutSlot(x.toDouble(), y.toDouble(), l),
  ];

  /// The first [count] layers.
  BoardShape prefix(int count) => BoardShape(
    family: family,
    variant: variant,
    stacking: stacking,
    columns: columns,
    rows: rows,
    layers: layers.sublist(0, count),
  );

  (int, int, int, int) get bounds {
    var minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
    for (final layer in layers) {
      for (final (x, y) in layer) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x + 2);
        maxY = math.max(maxY, y + 2);
      }
    }
    return (minX, minY, maxX, maxY);
  }

  /// Whether the board, all layers and half offsets included, fits the fixed
  /// board grid ([kBoardGridColumns] x [kBoardGridRows] tiles,
  /// [kBoardGridLayers] layers).
  bool get fitsGrid {
    final (minX, minY, maxX, maxY) = bounds;
    return maxX - minX <= 2 * kBoardGridColumns && maxY - minY <= 2 * kBoardGridRows && layers.length <= kBoardGridLayers;
  }

  /// Tile face width (logical px) when the board is fitted into
  /// [width] x [height] the way `boardProjectionFor` does it: at the fixed
  /// grid's scale, or smaller for a board larger than the grid.
  double faceWidthIn(double width, double height) {
    final (minX, minY, maxX, maxY) = bounds;
    return gridFaceWidthIn(
      width,
      height,
      columns: math.max(kBoardGridColumns, (maxX - minX) / 2),
      rows: math.max(kBoardGridRows, (maxY - minY) / 2),
      maxLayer: math.max(kBoardGridLayers, layers.length) - 1,
    );
  }

  double get smallPhoneFaceWidth => faceWidthIn(kSmallBoardWidth, kSmallBoardHeight);

  /// Tiles that can be picked at the start: nothing higher overlaps them
  /// and their left or right side is open (the game's freedom rule).
  int get freeAtStart {
    var free = 0;
    for (var l = 0; l < layers.length; l++) {
      for (final (x, y) in layers[l]) {
        if (_covered(l, x, y)) continue;
        final layer = layers[l];
        bool side(int dx) =>
            layer.contains((x + dx, y - 1)) || layer.contains((x + dx, y)) || layer.contains((x + dx, y + 1));
        if (!side(-2) || !side(2)) free++;
      }
    }
    return free;
  }

  bool _covered(int l, int x, int y) {
    for (var u = l + 1; u < layers.length; u++) {
      final layer = layers[u];
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (layer.contains((x + dx, y + dy))) return true;
        }
      }
    }
    return false;
  }

  double get freeRatio => tileCount == 0 ? 0 : freeAtStart / tileCount;

  /// Removes one uncovered tile on the mirror axis (highest first) so the
  /// tile count is even and the board stays symmetric. Null if impossible.
  BoardShape? evened() {
    if (tileCount.isEven) return this;
    final (minX, _, maxX, _) = bounds;
    final axis2 = minX + maxX; // 2 * axis; a tile is on the axis when 2x + 2 == axis2
    for (var l = layers.length - 1; l >= 0; l--) {
      final onAxis = [
        for (final cell in layers[l])
          if (2 * cell.$1 + 2 == axis2 && !_covered(l, cell.$1, cell.$2)) cell,
      ]..sort(_readingOrder);
      if (onAxis.isEmpty) continue;
      // The middle one keeps the shape balanced top to bottom.
      final drop = onAxis[onAxis.length ~/ 2];
      final next = [for (final layer in layers) {...layer}];
      next[l].remove(drop);
      while (next.isNotEmpty && next.last.isEmpty) {
        next.removeLast();
      }
      return BoardShape(family: family, variant: variant, stacking: stacking, columns: columns, rows: rows, layers: next);
    }
    return null;
  }
}

/// Tile face width (logical px) of the fixed board grid fitted into
/// [width] x [height] (the arithmetic of `BoardProjection.fit`).
double gridFaceWidthIn(
  double width,
  double height, {
  num columns = kBoardGridColumns,
  num rows = kBoardGridRows,
  int maxLayer = kBoardGridLayers - 1,
}) {
  const a = kFitFaceAspect, e = kFitEdgeFraction, o = kFitLayerOffset;
  final perX = a * columns + a * e + a * o * maxLayer;
  final perY = rows + a * e + o * maxLayer;
  final availableX = width - 2 * kBoardPadding, availableY = height - 2 * kBoardPadding;
  final faceHeight = math.min(140.0, math.min(availableX / perX, availableY / perY));
  return faceHeight * a;
}

int _readingOrder(Cell a, Cell b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1);

/// Named regions a family hands to its stacking program (corner towers,
/// bridge piers, a turtle's shell).
typedef _Regions = Map<String, Set<Cell>>;

/// The four 1x1 cells (quarters) of the 2x2 footprint at [c].
List<Cell> footprintQuarters(Cell c) => [(c.$1, c.$2), (c.$1 + 1, c.$2), (c.$1, c.$2 + 1), (c.$1 + 1, c.$2 + 1)];

/// Where a layer's tiles sit relative to the tiles of the layer below.
enum _Order { centre, outside, reading }

/// How one layer is placed on the layers below it (owner, 2026-10-17: depth
/// must show). Every tile sits half a tile off the tiles under it, never
/// exactly on top of one; candidates come from [offsets] (mirrored left and
/// right, so the board stays symmetric) applied to the layer below, are taken
/// in [order], and a tile is only placed when
/// - its whole footprint lies over lower tiles (nothing hangs over the felt),
/// - at least [support] of its quarters lie over the layer directly below,
/// - no lower tile has the same position, and
/// - every lower tile it covers keeps at least [minVisible] uncovered
///   quarters (of four).
class _Op {
  const _Op(this.offsets, this.order, {this.minVisible = 2, this.support = 2, this.region});

  final List<Cell> offsets;
  final _Order order;
  final int minVisible;
  final int support;
  final String? region;
}

// Half offsets a layer may take from the tiles below it (mirrored left and
// right). The first ones listed are preferred.
const List<Cell> _stagger = [(1, 1), (1, -1), (1, 0), (0, 1)];
const List<Cell> _brick = [(1, 0), (1, 1), (1, -1), (0, 1)];
const List<Cell> _drop = [(0, 1), (1, 1), (1, -1), (1, 0)];
const List<Cell> _any = [(1, 1), (1, 0), (0, 1), (1, -1)];

const Map<String, _Op> _ops = {
  // Half a tile right and down, from the middle out: a mound.
  'pyramid': _Op(_stagger, _Order.centre),
  // Half a tile right, from the middle out: long ridges.
  'ridge': _Op(_brick, _Order.centre),
  // Half a tile down, from the middle out: columns.
  'column': _Op(_drop, _Order.centre),
  // Half a tile right and down, evenly over the board.
  'stagger': _Op(_stagger, _Order.reading),
  // Half a tile right, evenly over the board: brickwork.
  'brick': _Op(_brick, _Order.reading),
  // Any half offset, outside first: walls along the outline.
  'rim': _Op(_any, _Order.outside),
  // Any half offset, as many as fit while one quarter of every tile shows.
  'solid': _Op(_any, _Order.reading, minVisible: 1),
  // Any half offset, from the middle out, one quarter showing: a dense heap.
  'heap': _Op(_any, _Order.centre, minVisible: 1, support: 1),
  // Half a tile right and down where it fits, one quarter showing.
  'dense': _Op(_stagger, _Order.reading, minVisible: 1, support: 1),
  // Inside a family's regions only.
  'towers': _Op(_any, _Order.reading, minVisible: 1, region: 'towers'),
  'core': _Op(_any, _Order.centre, region: 'core'),
};

/// Layers stacked so far, with the topmost tile over every quarter cell.
class _Stack {
  _Stack(Set<Cell> base, this.axis2, this.centre2) {
    layers.add(<Cell>{});
    for (final cell in base) {
      _place(0, cell);
    }
  }

  /// Twice the mirror axis (`minX + maxX` of the base): `x` mirrors to
  /// `axis2 - x - 2`.
  final int axis2;

  /// Twice the base centre.
  final (int, int) centre2;
  final List<Set<Cell>> layers = [];
  final Set<Cell> _used = {};
  final Map<Cell, (int, Cell)> _top = {};
  final Map<(int, Cell), int> _visible = {};

  void _place(int layer, Cell cell) {
    for (final q in footprintQuarters(cell)) {
      final below = _top[q];
      if (below != null) _visible[below] = _visible[below]! - 1;
      _top[q] = (layer, cell);
    }
    _visible[(layer, cell)] = 4;
    layers[layer].add(cell);
    _used.add(cell);
  }

  Cell mirror(Cell c) => (axis2 - c.$1 - 2, c.$2);

  /// Adds the next layer with [op]; false when not one tile fits.
  bool addLayer(_Op op, _Regions regions) {
    final layer = layers.length;
    final below = layers.last;
    final region = op.region == null ? null : {for (final c in regions[op.region] ?? const <Cell>{}) ...footprintQuarters(c)};
    // Each candidate with the rank of the first offset that reaches it.
    final rank = <Cell, int>{};
    for (var i = 0; i < op.offsets.length; i++) {
      final (dx, dy) = op.offsets[i];
      for (final (x, y) in below) {
        rank.putIfAbsent((x + dx, y + dy), () => i);
        rank.putIfAbsent((x - dx, y + dy), () => i);
      }
    }
    final candidates = [
      for (final c in rank.keys)
        if (region == null || footprintQuarters(c).every(region.contains)) c,
    ];
    int distance(Cell c) {
      final dx = 2 * c.$1 + 2 - centre2.$1, dy = 2 * c.$2 + 2 - centre2.$2;
      return dx * dx + dy * dy;
    }

    candidates.sort((a, b) {
      final byRank = rank[a]!.compareTo(rank[b]!);
      if (byRank != 0) return byRank;
      final byOrder = switch (op.order) {
        _Order.centre => distance(a).compareTo(distance(b)),
        _Order.outside => distance(b).compareTo(distance(a)),
        _Order.reading => 0,
      };
      return byOrder != 0 ? byOrder : _readingOrder(a, b);
    });
    layers.add(<Cell>{});
    final seen = <Cell>{};
    for (final c in candidates) {
      if (!seen.add(c)) continue;
      final m = mirror(c);
      seen.add(m);
      final group = m == c ? [c] : [c, m];
      if (group.length == 2 && _overlap(c, m)) continue;
      if (_fits(layer, group, op)) {
        for (final cell in group) {
          _place(layer, cell);
        }
      }
    }
    if (layers.last.isEmpty) {
      layers.removeLast();
      return false;
    }
    return true;
  }

  static bool _overlap(Cell a, Cell b) => (a.$1 - b.$1).abs() < 2 && (a.$2 - b.$2).abs() < 2;

  bool _fits(int layer, List<Cell> group, _Op op) {
    final loss = <(int, Cell), int>{};
    for (final cell in group) {
      if (_used.contains(cell)) return false;
      for (final other in layers[layer]) {
        if (_overlap(cell, other)) return false;
      }
      var support = 0;
      for (final q in footprintQuarters(cell)) {
        final below = _top[q];
        if (below == null) return false;
        if (below.$1 == layer - 1) support++;
        loss[below] = (loss[below] ?? 0) + 1;
      }
      if (support < op.support) return false;
    }
    for (final MapEntry(key: tile, value: lost) in loss.entries) {
      if (_visible[tile]! - lost < op.minVisible) return false;
    }
    return true;
  }
}

/// One family of mirror-symmetric shapes.
class _Family {
  const _Family(this.id, this.variants, this.stackings, this.base, {this.minColumns = 3, this.minRows = 3});

  final String id;
  final List<String> variants;

  /// Stacking programs: op names applied in turn, cycling.
  final Map<String, List<String>> stackings;

  /// Base cells and regions for a [c] x [r] grid, or null when the size does
  /// not suit the family.
  final (Set<Cell>, _Regions)? Function(int c, int r, String variant) base;
  final int minColumns;
  final int minRows;
}

/// Base grid cells (tile units) where [inside] holds, as logical cells.
/// [inside] gets the column and row distance from the grid centre
/// (`dc`, `dr`, in tiles) and both normalised to [-1, 1] (`u`, `v`), so
/// every mask is mirror-symmetric left to right by construction.
Set<Cell> _mask(int c, int r, bool Function(double dc, double dr, double u, double v, int col, int row) inside) {
  final cx = (c - 1) / 2, cy = (r - 1) / 2;
  return {
    for (var row = 0; row < r; row++)
      for (var col = 0; col < c; col++)
        if (inside(
          (col - cx).abs(),
          row - cy,
          cx == 0 ? 0 : (col - cx) / cx,
          cy == 0 ? 0 : (row - cy) / cy,
          col,
          row,
        ))
          (col * 2, row * 2),
  };
}

/// Dense programs every family also gets (one quarter of each tile showing),
/// for the deep boards of the hardest tiers.
const Map<String, List<String>> _denseStackings = {
  'heap': ['heap'],
  'dense': ['dense', 'heap'],
};

const Map<String, List<String>> _layered = {
  'pyramid': ['pyramid'],
  'stagger': ['stagger'],
  'mixed': ['stagger', 'pyramid'],
};

final List<_Family> _families = [
  _Family('pyramid', const ['full'], const {'pyramid': ['pyramid'], 'ridge': ['ridge'], 'mixed': ['pyramid', 'stagger']},
      (c, r, _) => (_mask(c, r, (_, _, _, _, _, _) => true), const {})),
  _Family('terrace', const ['full'], const {'stagger': ['stagger'], 'brick': ['brick'], 'column': ['column']},
      (c, r, _) => (_mask(c, r, (_, _, _, _, _, _) => true), const {}), minColumns: 4),
  _Family('diamond', const ['round', 'sharp'], _layered, (c, r, variant) {
    final limit = variant == 'round' ? 1.2 : 1.0;
    return (_mask(c, r, (_, _, u, v, _, _) => u.abs() + v.abs() <= limit + 1e-9), const {});
  }, minColumns: 5, minRows: 5),
  _Family('cross', const ['thin', 'thick'], const {'pyramid': ['pyramid'], 'ridge': ['ridge'], 'towers': ['towers', 'solid']},
      (c, r, variant) {
    final half = variant == 'thin' ? 0.6 : 1.1;
    final cells = _mask(c, r, (dc, dr, _, _, _, _) => dc <= half || dr.abs() <= half);
    final centre = _mask(c, r, (dc, dr, _, _, _, _) => dc <= 1.1 && dr.abs() <= 1.1);
    return (cells, {'towers': centre});
  }, minColumns: 5, minRows: 5),
  _Family('ring', const ['thin', 'thick', 'double'], const {'rim': ['rim', 'solid'], 'brick': ['brick'], 'pyramid': ['pyramid']},
      (c, r, variant) {
    final cells = switch (variant) {
      'thin' => _mask(c, r, (_, _, _, _, col, row) => col == 0 || row == 0 || col == c - 1 || row == r - 1),
      'thick' => _mask(c, r, (_, _, _, _, col, row) => col < 2 || row < 2 || col >= c - 2 || row >= r - 2),
      _ => _mask(c, r, (_, _, _, _, col, row) {
        final edge = col == 0 || row == 0 || col == c - 1 || row == r - 1;
        final inner = col >= 2 && row >= 2 && col <= c - 3 && row <= r - 3;
        return edge || inner;
      }),
    };
    return (cells, const {});
  }, minColumns: 5, minRows: 5),
  _Family('fortress', const ['walls', 'keep'], const {'towers': ['rim', 'towers', 'solid'], 'pyramid': ['towers', 'pyramid']},
      (c, r, variant) {
    final cells = variant == 'walls'
        ? _mask(c, r, (_, _, _, _, col, row) => col < 2 || row < 2 || col >= c - 2 || row >= r - 2)
        : _mask(c, r, (_, _, _, _, _, _) => true);
    final corners = _mask(c, r, (_, _, _, _, col, row) => (col < 2 || col >= c - 2) && (row < 2 || row >= r - 2));
    return (cells, {'towers': corners});
  }, minColumns: 6, minRows: 5),
  _Family('arch', const ['round', 'square'], const {'brick': ['brick'], 'rim': ['rim', 'solid'], 'pyramid': ['pyramid']},
      (c, r, variant) {
    final band = math.max(2, r ~/ 3), leg = math.max(2, c ~/ 4);
    final cells = _mask(c, r, (dc, _, _, _, col, row) {
      if (variant == 'round' && row == 0 && (col == 0 || col == c - 1)) return false;
      return row < band || col < leg || col >= c - leg;
    });
    return (cells, const {});
  }, minColumns: 6, minRows: 5),
  _Family('bridge', const ['low', 'high'], const {'piers': ['towers', 'solid'], 'brick': ['brick']}, (c, r, variant) {
    final pier = math.max(2, c ~/ 4);
    final span = variant == 'low' ? 0.6 : 1.1;
    final cells = _mask(c, r, (_, dr, _, _, col, _) => col < pier || col >= c - pier || dr.abs() <= span);
    final piers = _mask(c, r, (_, _, _, _, col, _) => col < pier || col >= c - pier);
    return (cells, {'towers': piers});
  }, minColumns: 7, minRows: 4),
  _Family('hourglass', const ['narrow', 'wide'], const {'pyramid': ['pyramid'], 'ridge': ['ridge'], 'stagger': ['stagger']},
      (c, r, variant) {
    final waist = variant == 'narrow' ? 0.6 : 1.1;
    final cx = (c - 1) / 2;
    return (_mask(c, r, (dc, _, _, v, _, _) => dc <= waist + (cx - waist) * v.abs() + 1e-9), const {});
  }, minColumns: 5, minRows: 5),
  _Family('heart', const ['plain'], _layered, (c, r, _) {
    final cells = _mask(c, r, (_, _, u, v, _, _) {
      final x = u * 1.25, y = -v * 1.25 + 0.25;
      final a = x * x + y * y - 1;
      return a * a * a - x * x * y * y * y <= 0;
    });
    return (cells, const {});
  }, minColumns: 6, minRows: 6),
  _Family('flower', const ['four', 'round'], _layered, (c, r, variant) {
    bool disc(double u, double v, double cu, double cv, double radius) =>
        (u - cu) * (u - cu) + (v - cv) * (v - cv) <= radius * radius + 1e-9;
    final cells = _mask(c, r, (_, _, u, v, _, _) {
      if (disc(u, v, 0, 0, 0.45)) return true;
      if (variant == 'four') {
        return disc(u, v, 0, 0.62, 0.42) ||
            disc(u, v, 0, -0.62, 0.42) ||
            disc(u, v, 0.62, 0, 0.42) ||
            disc(u, v, -0.62, 0, 0.42);
      }
      return disc(u, v, 0.55, 0.55, 0.38) ||
          disc(u, v, -0.55, 0.55, 0.38) ||
          disc(u, v, 0.55, -0.55, 0.38) ||
          disc(u, v, -0.55, -0.55, 0.38);
    });
    return (cells, const {});
  }, minColumns: 5, minRows: 5),
  _Family('grove', const ['trees'], const {'column': ['column'], 'solid': ['solid']}, (c, r, _) {
    final cells = _mask(c, r, (dc, _, _, _, _, _) => (dc * 2).round() % 4 == (c.isOdd ? 0 : 1));
    return (cells, const {});
  }, minColumns: 3),
  _Family('furrows', const ['rows'], const {'ridge': ['ridge'], 'brick': ['brick']}, (c, r, _) {
    final cells = _mask(c, r, (_, dr, _, _, _, _) => (dr * 2).round().abs() % 4 == (r.isOdd ? 0 : 1));
    return (cells, const {});
  }, minColumns: 4),
  _Family('chevron', const ['up', 'down'], const {'ridge': ['ridge'], 'pyramid': ['pyramid'], 'brick': ['brick']},
      (c, r, variant) {
    final cx = (c - 1) / 2;
    final cells = _mask(c, r, (dc, _, _, _, _, row) {
      final slope = (r - 2) / math.max(cx, 1);
      final edge = variant == 'up' ? (cx - dc) * slope : dc * slope;
      return row >= edge.round() - 1e-9 && row <= edge.round() + 1;
    });
    return (cells, const {});
  }, minColumns: 5, minRows: 4),
  _Family('isles', const ['grid'], const {'stagger': ['stagger'], 'towers': ['solid', 'stagger']}, (c, r, _) {
    if (c % 3 != 2) return null;
    return (_mask(c, r, (_, _, _, _, col, row) => col % 3 != 2 && row % 3 != 2), const {});
  }, minColumns: 5, minRows: 5),
  _Family('oval', const ['plain'], _layered, (c, r, _) {
    return (_mask(c, r, (_, _, u, v, _, _) => u * u + v * v <= 1.1), const {});
  }, minColumns: 5, minRows: 4),
  _Family('star', const ['plain'], const {'pyramid': ['pyramid'], 'ridge': ['ridge'], 'towers': ['towers', 'solid']},
      (c, r, _) {
    final cells = _mask(c, r, (_, _, u, v, _, _) => u.abs() <= 0.25 || v.abs() <= 0.25 || (u.abs() - v.abs()).abs() <= 0.3);
    final centre = _mask(c, r, (_, _, u, v, _, _) => u.abs() <= 0.35 && v.abs() <= 0.35);
    return (cells, {'towers': centre});
  }, minColumns: 5, minRows: 5),
  _Family('butterfly', const ['open'], _layered, (c, r, _) {
    final cells = _mask(c, r, (dc, _, u, v, _, _) => dc <= 0.6 || (u.abs() - 0.55).abs() / 0.5 + v.abs() <= 1.05);
    return (cells, const {});
  }, minColumns: 7, minRows: 5),
  _Family('turtle', const ['shell'], const {'shell': ['core', 'pyramid'], 'stagger': ['core', 'stagger']}, (c, r, _) {
    // Seen from above: a shell, four flippers, the head on top and the tail
    // below, all inside the grid.
    final shell = _mask(c, r, (_, _, _, _, col, row) => col >= 1 && col <= c - 2 && row >= 1 && row <= r - 2);
    final flippers = _mask(c, r, (_, _, _, _, col, row) => (col == 0 || col == c - 1) && (row == 1 || row == r - 2));
    final cells = {...shell, ...flippers, (c - 1, 0), (c - 1, 2 * (r - 1))};
    return (cells, {'core': shell});
  }, minColumns: 5, minRows: 5),
  _Family('lattice', const ['panes'], const {'pyramid': ['solid', 'rim'], 'stagger': ['stagger'], 'rim': ['rim']},
      (c, r, _) {
    if (c % 3 != 0) return null;
    return (_mask(c, r, (_, _, _, _, col, row) => !(col % 3 == 1 && row % 3 == 1)), const {});
  }, minColumns: 6, minRows: 4),
  _Family('crown', const ['spikes'], const {'pyramid': ['pyramid'], 'ridge': ['ridge']}, (c, r, _) {
    if (c.isEven) return null;
    final cells = _mask(c, r, (dc, _, _, _, _, row) => row >= 2 || (row >= 0 && dc.round().isEven));
    return (cells, const {});
  }, minColumns: 5, minRows: 5),
  _Family('pillars', const ['row', 'grid'], const {'towers': ['solid'], 'capped': ['solid', 'solid', 'stagger']},
      (c, r, variant) {
    if (c % 3 != 2 || (variant == 'grid' ? r % 3 != 2 : r != 2)) return null;
    return (_mask(c, r, (_, _, _, _, col, row) => col % 3 != 2 && row % 3 != 2), const {});
  }, minColumns: 5, minRows: 2),
];

/// Every family id, in a fixed order.
List<String> get shapeFamilies => [for (final f in _families) f.id];

/// Largest base grid the generator tries: the fixed board grid.
const int kMaxColumns = kBoardGridColumns;
const int kMaxRows = kBoardGridRows;

/// All boards of [familyId] up to [maxLayers] layers, for every grid size,
/// variant and stacking program; each layer prefix is its own board. Boards
/// whose base is empty, that leave the fixed grid or that cannot be made even
/// are left out.
Iterable<BoardShape> familyShapes(String familyId, {int maxLayers = kBoardGridLayers}) sync* {
  final family = _families.firstWhere((f) => f.id == familyId);
  for (var c = family.minColumns; c <= kMaxColumns; c++) {
    for (var r = family.minRows; r <= kMaxRows; r++) {
      for (final variant in family.variants) {
        final built = family.base(c, r, variant);
        if (built == null || built.$1.length < 4) continue;
        final (base, regions) = built;
        var minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
        for (final (x, y) in base) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x + 2);
          maxY = math.max(maxY, y + 2);
        }
        for (final MapEntry(key: name, value: program) in {...family.stackings, ..._denseStackings}.entries) {
          final stack = _Stack(base, minX + maxX, (minX + maxX, minY + maxY));
          var guard = 0;
          while (stack.layers.length < maxLayers && guard++ < 32) {
            if (!stack.addLayer(_ops[program[(stack.layers.length - 1) % program.length]]!, regions)) break;
          }
          final layers = stack.layers;
          for (var count = 1; count <= layers.length; count++) {
            final shape = BoardShape(
              family: family.id,
              variant: variant,
              stacking: name,
              columns: c,
              rows: r,
              layers: layers.sublist(0, count),
            ).evened();
            if (shape != null && shape.layerCount == count && shape.fitsGrid) yield shape;
          }
        }
      }
    }
  }
}

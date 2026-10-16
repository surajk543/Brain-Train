import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';

import 'tile_style.dart';

/// Per-tile animation values for one frame. Reused; read immediately.
class TileFx {
  /// Horizontal offset, as a fraction of the face width.
  double shakeX = 0;

  /// Strength of the red "blocked" tint, 0-1.
  double invalidTint = 0;

  /// Horizontal scale of the whole tile around its face centre (a shuffle
  /// turns tiles over: 1 to 0 showing the old symbol, 0 to 1 the new one).
  double flipScaleX = 1;

  /// The symbol to draw instead of the tile's own (the old one, during the
  /// first half of a shuffle's turn); null: the tile's symbol.
  String? symbolOverride;

  void _reset() {
    shakeX = 0;
    invalidTint = 0;
    flipScaleX = 1;
    symbolOverride = null;
  }
}

/// Short-lived visual effects layered over the game state: a blocked tile
/// shakes with a red tint; tiles flying back to the board (a revive) stay
/// hidden until they land; a shuffle turns its tiles over ([flip]).
///
/// The rules engine has already applied every change; effects only animate
/// it. Tiles leave the board at once (the tray flight draws them from then
/// on). Only tiles with an active effect animate; idle tiles cost nothing.
class BoardEffects extends ChangeNotifier {
  BoardEffects({required this.style, this.reduceMotion = false}) {
    _clock.start();
  }

  TileStyle style;

  /// Effects complete instantly.
  bool reduceMotion;
  final Stopwatch _clock = Stopwatch();
  final TileFx _fx = TileFx();

  final Map<String, Duration> _shaking = {};
  final Set<String> _hidden = {};

  /// Tiles turning over: when the turn starts and the symbol shown until
  /// half-way.
  final Map<String, (Duration start, String oldSymbol)> _flipping = {};

  /// How long one tile takes to turn over in a shuffle.
  static const Duration flipDuration = Duration(milliseconds: 360);

  /// The latest a tile starts turning (a wave across the board).
  static const Duration flipStagger = Duration(milliseconds: 220);

  int _generation = 0;

  Duration get _now => _clock.elapsed;

  /// Changes whenever the set of effects changes (a new or finished effect,
  /// a reset): while [isAnimating] is false, equal generations mean equal
  /// [fx] for every tile.
  int get generation => _generation;

  Duration _d(Duration d) => reduceMotion ? Duration.zero : d;

  bool get isAnimating => _shaking.isNotEmpty || _flipping.isNotEmpty;

  /// True while a shuffle's tiles are turning over (taps wait).
  bool get isFlipping => _flipping.isNotEmpty;

  /// True while [id] is on the board but not drawn (flying back to it).
  bool isHidden(String id) => _hidden.contains(id);

  bool get hasHidden => _hidden.isNotEmpty;

  /// Stops drawing [ids] until each is [reveal]ed.
  void hide(Iterable<String> ids) {
    _hidden.addAll(ids);
    _generation++;
    notifyListeners();
  }

  void reveal(String id) {
    if (!_hidden.remove(id)) return;
    _generation++;
    notifyListeners();
  }

  void shake(Iterable<String> ids) {
    for (final id in ids) {
      _shaking[id] = _now;
    }
    _generation++;
    notifyListeners();
  }

  /// A shuffle: each tile in [oldSymbols] (id → the symbol it showed) turns
  /// over, showing its old symbol until half-way and its new one after;
  /// [delays] starts some later (a wave). Instant with [reduceMotion].
  void flip(Map<String, String> oldSymbols, {Map<String, double> delays = const {}}) {
    if (reduceMotion || oldSymbols.isEmpty) return;
    final now = _now;
    for (final MapEntry(key: id, value: old) in oldSymbols.entries) {
      final delay = flipStagger * (delays[id] ?? 0).clamp(0.0, 1.0);
      _flipping[id] = (now + delay, old);
    }
    _generation++;
    notifyListeners();
  }

  void reset() {
    _shaking.clear();
    _hidden.clear();
    _flipping.clear();
    _generation++;
    notifyListeners();
  }

  /// Advances time: drops finished effects and repaints.
  void tick() {
    final now = _now;
    final before = _shaking.length;
    _shaking.removeWhere((_, start) => now - start >= _d(style.invalidDuration));
    final flips = _flipping.length;
    _flipping.removeWhere((_, flip) => now - flip.$1 >= _d(flipDuration));
    if (_shaking.length != before || _flipping.length != flips) _generation++;
    notifyListeners();
  }

  double _progress(Duration start, Duration length) {
    if (length == Duration.zero) return 1;
    return ((_now - start).inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);
  }

  TileFx fx(String id) {
    final fx = _fx.._reset();
    final shaking = _shaking[id];
    if (shaking != null) {
      final t = _progress(shaking, _d(style.invalidDuration));
      fx
        ..shakeX = math.sin(t * math.pi * 6) * (1 - t) * 0.06
        ..invalidTint = 1 - t;
    }
    final flipping = _flipping[id];
    if (flipping != null) {
      final (start, old) = flipping;
      final t = _now < start ? 0.0 : _progress(start, _d(flipDuration));
      // Narrows to an edge, then widens showing the new symbol.
      final turn = Curves.easeInOut.transform(t);
      fx.flipScaleX = (1 - 2 * turn).abs().clamp(0.0, 1.0);
      if (t < 0.5) fx.symbolOverride = old;
    }
    return fx;
  }

  @override
  void dispose() {
    _clock.stop();
    super.dispose();
  }
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'tile_style.dart';

/// Per-tile animation values for one frame. Reused; read immediately.
class TileFx {
  /// Horizontal offset, as a fraction of the face width.
  double shakeX = 0;

  /// Strength of the red "blocked" tint, 0-1.
  double invalidTint = 0;

  void _reset() {
    shakeX = 0;
    invalidTint = 0;
  }
}

/// Short-lived visual effects layered over the game state: a blocked tile
/// shakes with a red tint; tiles flying back to the board (a revive) stay
/// hidden until they land.
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

  int _generation = 0;

  Duration get _now => _clock.elapsed;

  /// Changes whenever the set of effects changes (a new or finished effect,
  /// a reset): while [isAnimating] is false, equal generations mean equal
  /// [fx] for every tile.
  int get generation => _generation;

  Duration _d(Duration d) => reduceMotion ? Duration.zero : d;

  bool get isAnimating => _shaking.isNotEmpty;

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

  void reset() {
    _shaking.clear();
    _hidden.clear();
    _generation++;
    notifyListeners();
  }

  /// Advances time: drops finished effects and repaints.
  void tick() {
    final now = _now;
    final before = _shaking.length;
    _shaking.removeWhere((_, start) => now - start >= _d(style.invalidDuration));
    if (_shaking.length != before) _generation++;
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
    return fx;
  }

  @override
  void dispose() {
    _clock.stop();
    super.dispose();
  }
}

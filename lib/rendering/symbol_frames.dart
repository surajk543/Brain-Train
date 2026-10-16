import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'symbol_art.dart';

/// The current frame of each animated symbol on a board, rendered together
/// into one image and then stamped on every tile that shows it.
///
/// Replaying a Lottie frame's vectors costs tessellation, gradients and
/// often offscreen layers on the raster thread; doing it once per symbol
/// per frame step (one small offscreen render for all symbols) instead of
/// once per tile per display frame keeps animated boards cheap. Frames
/// advance in steps of [frameRate] (30 per second, evenly paced on 60 and
/// 120 Hz displays); between steps the same image is reused.
class SymbolFrameAtlas {
  SymbolFrameAtlas({this.frameRate = 30});

  final double frameRate;

  ui.Image? _image;
  final Map<AnimatedSymbolArt, Rect> _cells = {};
  int _step = -1;

  /// The frame step [seconds] falls in.
  int stepAt(double seconds) => (seconds * frameRate).floor();

  /// Makes the image hold every art in [arts] at the frame for [seconds];
  /// does nothing if it already does.
  void prepare(Set<AnimatedSymbolArt> arts, double seconds) {
    final step = stepAt(seconds);
    if (step == _step && arts.length == _cells.length && arts.every(_cells.containsKey)) return;
    _step = step;
    _cells.clear();
    _image?.dispose();
    _image = null;
    if (arts.isEmpty) return;
    // Shelf packing in device pixels, one pixel apart so samples never bleed.
    const maxWidth = 2048.0;
    var x = 0.0, y = 0.0, shelf = 0.0, width = 0.0;
    for (final art in arts) {
      final w = (art.box.width * art.pixelRatio).ceilToDouble();
      final h = (art.box.height * art.pixelRatio).ceilToDouble();
      if (x > 0 && x + w > maxWidth) {
        x = 0;
        y += shelf + 1;
        shelf = 0;
      }
      _cells[art] = Rect.fromLTWH(x, y, w, h);
      x += w + 1;
      shelf = math.max(shelf, h);
      width = math.max(width, x);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final t = step / frameRate;
    for (final MapEntry(key: art, value: cell) in _cells.entries) {
      canvas
        ..save()
        ..translate(cell.left, cell.top)
        ..clipRect(Offset.zero & cell.size)
        ..scale(art.pixelRatio);
      art.drawFrameAt(canvas, t);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    _image = picture.toImageSync(width.ceil(), (y + shelf).ceil());
    picture.dispose();
  }

  /// Draws [art]'s current frame into [box] (the art's own box size, so it
  /// is copied 1:1). Returns false if [prepare] did not include [art].
  bool paint(Canvas canvas, AnimatedSymbolArt art, Rect box, Paint paint) {
    final image = _image, cell = _cells[art];
    if (image == null || cell == null) return false;
    canvas.drawImageRect(image, cell, box, paint);
    return true;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _cells.clear();
    _step = -1;
  }
}

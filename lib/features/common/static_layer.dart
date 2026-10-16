import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../../app/tablet_scale.dart';

/// Called with the image a [StaticLayer] just painted: [bounds] is the area
/// it covers in the layer's own (logical) coordinates.
typedef StaticLayerRasterCallback = void Function(RenderBox layer, ui.Image image, Rect bounds, double pixelRatio);

/// Paints [child] once into an image, then draws only that image every
/// frame, until something inside [child] repaints (an image finishing its
/// decode, a size change, a pressed button's ink); then it paints [child]
/// again and keeps the new image.
///
/// The renderer has no cache of its own, so a static subtree under (or next
/// to) an animation is otherwise drawn again in full on every frame: every
/// gradient, shadow blur, text shadow, opacity layer and blend. Behind
/// ambient animation that is the difference between one textured quad and
/// dozens of draws and offscreen passes per frame.
///
/// [overflow] is how far [child] paints outside its box (shadows, glows,
/// leaves); that area is kept in the image too. Hit testing, layout and
/// semantics are untouched.
///
/// The layer is its own repaint boundary. [child] must not contain other
/// repaint boundaries (their repaints would not reach this layer), nor
/// platform views. Avoid it around content that animates continuously: it
/// would re-render the image every frame.
class StaticLayer extends SingleChildRenderObjectWidget {
  const StaticLayer({super.key, this.overflow = EdgeInsets.zero, this.onRaster, required Widget super.child});

  final EdgeInsets overflow;

  /// Receives each new image, for example to derive a blurred copy.
  final StaticLayerRasterCallback? onRaster;

  @override
  RenderStaticLayer createRenderObject(BuildContext context) => RenderStaticLayer(
    pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio,
    overflow: overflow,
    onRaster: onRaster,
  );

  @override
  void updateRenderObject(BuildContext context, RenderStaticLayer renderObject) {
    renderObject
      ..pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio
      ..overflow = overflow
      ..onRaster = onRaster;
  }
}

class RenderStaticLayer extends RenderProxyBox {
  RenderStaticLayer({required this._pixelRatio, this._overflow = EdgeInsets.zero, this.onRaster});

  double get pixelRatio => _pixelRatio;
  double _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  EdgeInsets get overflow => _overflow;
  EdgeInsets _overflow;
  set overflow(EdgeInsets value) {
    if (value == _overflow) return;
    _overflow = value;
    markNeedsPaint();
  }

  StaticLayerRasterCallback? onRaster;

  ui.Image? _image;
  Rect _imageBounds = Rect.zero;
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  /// Whether the next paint renders [child] again (for tests).
  @visibleForTesting
  bool get hasImage => _image != null;

  @override
  bool get isRepaintBoundary => true;

  /// Children call this on their way up when they need painting: that is
  /// exactly when the image goes stale.
  @override
  void markNeedsPaint() {
    _drop();
    super.markNeedsPaint();
  }

  void _drop() {
    _image?.dispose();
    _image = null;
  }

  @override
  void detach() {
    _drop();
    super.detach();
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) return;
    var image = _image;
    if (image == null) {
      final bounds = _overflow.inflateRect(Offset.zero & size);
      final layer = OffsetLayer();
      final recording = PaintingContext(layer, bounds);
      super.paint(recording, Offset.zero);
      // ignore: invalid_use_of_protected_member
      recording.stopRecordingIfNeeded();
      if (!layer.supportsRasterization()) {
        layer.dispose();
        super.paint(context, offset);
        return;
      }
      image = _image = layer.toImageSync(bounds, pixelRatio: _pixelRatio);
      _imageBounds = bounds;
      layer.dispose();
      onRaster?.call(this, image, bounds, _pixelRatio);
    }
    // Land on whole device pixels so the image is copied 1:1 (crisp text).
    final origin = localToGlobal(Offset.zero, ancestor: TabletScale.canvasAbove(this)) * _pixelRatio;
    final snap = Offset(origin.dx.roundToDouble() - origin.dx, origin.dy.roundToDouble() - origin.dy) / _pixelRatio;
    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        offset.dx + _imageBounds.left + snap.dx,
        offset.dy + _imageBounds.top + snap.dy,
        image.width / _pixelRatio,
        image.height / _pixelRatio,
      ),
      _paint,
    );
  }
}

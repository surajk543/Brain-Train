import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A pre-blurred copy of a screen's static backdrop, for [FrostedGlass].
///
/// Real frosted glass ([BackdropFilter]) reads back and blurs whatever is
/// behind it on every frame, which with ambient animation on screen is every
/// frame. The backdrop art never changes, so it is blurred once, when its
/// [StaticLayer] renders, and glass panels show the matching part of that
/// copy. Moving decoration (leaves, fireflies) passes behind the glass
/// unseen, as behind thick frosting.
///
/// Pass [update] as the backdrop's `StaticLayer.onRaster` and provide the
/// source to panels with a [FrostScope].
class FrostSource extends ChangeNotifier {
  FrostSource({this.sigma = 14, this.downscale = 4});

  /// Blur radius (Gaussian sigma) in logical pixels.
  final double sigma;

  /// The copy is stored this many times smaller than the screen: blur hides
  /// the lost detail and the copy is tiny.
  final double downscale;

  ui.Image? _image;
  RenderBox? _box;
  Rect _bounds = Rect.zero;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// The blurred copy, or null until the backdrop has rendered.
  ui.Image? get image => _image;

  /// The backdrop's render box; [bounds] is in its coordinates.
  RenderBox? get box => _box;

  /// The area [image] covers, in [box]'s logical coordinates.
  Rect get bounds => _bounds;

  /// Builds the blurred copy of a fresh backdrop [image] (called during
  /// paint; listeners hear about it after the frame).
  void update(RenderBox box, ui.Image image, Rect bounds, double pixelRatio) {
    if (_disposed) return;
    final width = (image.width / downscale).ceil().clamp(1, 4096);
    final height = (image.height / downscale).ceil().clamp(1, 4096);
    final blur = sigma * pixelRatio * width / image.width;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
    );
    final picture = recorder.endRecording();
    _image?.dispose();
    _image = picture.toImageSync(width, height);
    picture.dispose();
    _box = box;
    _bounds = bounds;
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    // Listeners repaint; that is not allowed during this paint.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    _box = null;
    super.dispose();
  }
}

/// Makes a [FrostSource] available to the [FrostedGlass] panels below.
class FrostScope extends InheritedWidget {
  const FrostScope({super.key, required this.source, required super.child});

  final FrostSource source;

  static FrostSource? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<FrostScope>()?.source;

  @override
  bool updateShouldNotify(FrostScope old) => old.source != source;
}

/// Frosted glass from the nearest [FrostScope]: paints the blurred backdrop
/// behind [child] inside a rounded rectangle, then [child] (the panel's
/// tint, rim and content). Without a source it paints only [child].
///
/// Costs one textured draw per frame, wherever the panel moves (route
/// transitions, entrance animations), since it samples the copy at its
/// current position on every paint.
class FrostedGlass extends SingleChildRenderObjectWidget {
  const FrostedGlass({super.key, required this.borderRadius, this.tint, super.child});

  final BorderRadius borderRadius;

  /// Laid over the frost: whatever sits between the backdrop and the glass
  /// (a dimming scrim), which a real backdrop blur would have included.
  final Color? tint;

  @override
  RenderFrostedGlass createRenderObject(BuildContext context) =>
      RenderFrostedGlass(source: FrostScope.maybeOf(context), borderRadius: borderRadius, tint: tint);

  @override
  void updateRenderObject(BuildContext context, RenderFrostedGlass renderObject) {
    renderObject
      ..source = FrostScope.maybeOf(context)
      ..borderRadius = borderRadius
      ..tint = tint;
  }
}

class RenderFrostedGlass extends RenderProxyBox {
  RenderFrostedGlass({this._source, required this._borderRadius, this._tint});

  FrostSource? get source => _source;
  FrostSource? _source;
  set source(FrostSource? value) {
    if (value == _source) return;
    if (attached) _source?.removeListener(markNeedsPaint);
    _source = value;
    if (attached) _source?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  BorderRadius get borderRadius => _borderRadius;
  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (value == _borderRadius) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  Color? get tint => _tint;
  Color? _tint;
  set tint(Color? value) {
    if (value == _tint) return;
    _tint = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _source?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = _source;
    final image = source?.image;
    final box = source?.box;
    if (image != null && box != null && box.attached && !size.isEmpty) {
      // Image pixels -> backdrop coordinates -> this box -> canvas.
      final toBackdrop = getTransformTo(box);
      if (toBackdrop.invert() != 0) {
        final bounds = source!.bounds;
        final matrix = Matrix4.translationValues(offset.dx, offset.dy, 0)
          ..multiply(toBackdrop)
          ..translateByDouble(bounds.left, bounds.top, 0, 1)
          ..scaleByDouble(bounds.width / image.width, bounds.height / image.height, 1, 1);
        final rrect = _borderRadius.toRRect(offset & size);
        context.canvas.drawRRect(
          rrect,
          Paint()
            ..shader = ImageShader(
              image,
              TileMode.clamp,
              TileMode.clamp,
              matrix.storage,
              filterQuality: FilterQuality.low,
            ),
        );
        final tint = _tint;
        if (tint != null) context.canvas.drawRRect(rrect, Paint()..color = tint);
      }
    }
    super.paint(context, offset);
  }
}

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Tablets (shortest side [canvasShortestSide] logical px or more) lay the app
/// out on a canvas whose shortest side is [canvasShortestSide] and scale it up
/// to fill the screen (at most [maxScale]), so the tray, HUD, lobby buttons and
/// cards grow with the screen instead of staying phone-sized. Phones are not
/// touched: the child is returned as is.
///
/// The device pixel ratio seen by the app is raised by the same factor, so
/// images and cached layers still render at the screen's full resolution.
/// Code that maps between widgets through "global" coordinates must measure
/// from the canvas, not the screen: use [canvasAbove] as the ancestor (null on
/// phones, which keeps true global coordinates).
class TabletScale extends StatelessWidget {
  const TabletScale({super.key, required this.child});

  static const double canvasShortestSide = 600;
  static const double maxScale = 1.75;

  final Widget child;

  /// The scale for a screen of [size] (1 on phones).
  static double scaleFor(Size size) {
    final shortest = size.shortestSide;
    if (shortest < canvasShortestSide) return 1;
    return math.min(shortest / canvasShortestSide, maxScale);
  }

  /// The scaled canvas above [object], or null when the app is not scaled
  /// (phones, tests without the app shell): pass it as the `ancestor` of
  /// `localToGlobal`, `globalToLocal` and `getTransformTo`.
  static RenderBox? canvasAbove(RenderObject object) {
    for (RenderObject? node = object.parent; node != null; node = node.parent) {
      if (node is _RenderTabletCanvas) return node;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = scaleFor(media.size);
    if (scale == 1) return child;
    final canvas = media.size / scale;
    return MediaQuery(
      data: media.copyWith(
        size: canvas,
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
        systemGestureInsets: media.systemGestureInsets / scale,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: canvas, child: _TabletCanvas(child: child)),
      ),
    );
  }
}

class _TabletCanvas extends SingleChildRenderObjectWidget {
  const _TabletCanvas({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTabletCanvas();
}

class _RenderTabletCanvas extends RenderProxyBox {}

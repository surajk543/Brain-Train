import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'tile_style.dart';

/// A pre-rendered tile layer (body, or the extra shadow under raised tiles).
///
/// Rendered once per face size and device pixel ratio, then stamped for
/// every tile with a single `drawImageRect`, so no blur or gradient work
/// happens per tile per frame.
class TileBodyImage {
  TileBodyImage._(this.image, this.faceOffset, this.size);

  final ui.Image image;

  /// Where the face's top-left corner sits inside [size].
  final Offset faceOffset;

  /// Logical size of the whole body image.
  final Size size;

  void paint(Canvas canvas, Offset faceTopLeft, Paint paint) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      (faceTopLeft - faceOffset) & size,
      paint,
    );
  }

  /// Draws only the part of the layer under [area] (logical, for a face at
  /// [faceTopLeft]), sampled exactly as [paint] samples it.
  void paintPart(Canvas canvas, Offset faceTopLeft, Rect area, Paint paint) {
    final origin = faceTopLeft - faceOffset;
    final k = image.width / size.width;
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(
        (area.left - origin.dx) * k,
        (area.top - origin.dy) * k,
        (area.right - origin.dx) * k,
        (area.bottom - origin.dy) * k,
      ),
      area,
      paint,
    );
  }

  void dispose() => image.dispose();
}

class MahjongTileRenderer {
  const MahjongTileRenderer(this.style);

  final TileStyle style;

  RRect faceRRect(Rect face) => RRect.fromRectAndRadius(face, Radius.circular(face.width * style.cornerRadiusFraction));

  /// The area inside the bevel where symbols are drawn.
  Rect symbolRect(Rect face) => face.deflate(face.width * style.symbolInsetFraction);

  /// Renders the tile: cast shadow, two-tone extruded body (ivory wall over
  /// an olive-green base), and the bevelled ivory face lit from the top-left.
  Future<TileBodyImage> renderBody(Size face, double pixelRatio) async {
    final depthX = face.width * style.depthXFraction;
    final depthY = face.height * style.depthYFraction;
    final blur = face.width * style.shadowBlurFraction;
    final shadowOffset = face.width * style.shadowOffsetFraction;
    final margin = (blur * 2.2 + 2).ceilToDouble();
    final size = Size(
      face.width + depthX + shadowOffset + margin * 2,
      face.height + depthY + shadowOffset + margin * 2,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    final faceRect = Offset(margin, margin) & face;
    final radius = Radius.circular(face.width * style.cornerRadiusFraction);
    RRect rounded(Rect rect) => RRect.fromRectAndRadius(rect, radius);
    final hairline = 1 / pixelRatio;
    final base = faceRect.shift(Offset(depthX, depthY));

    // Two shadows: a wide soft one and a tight contact one under the base.
    canvas
      ..drawRRect(
        rounded(base.shift(Offset(shadowOffset * 0.55, shadowOffset)).inflate(face.width * 0.01)),
        Paint()
          ..color = style.shadowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      )
      ..drawRRect(
        rounded(base.shift(Offset(shadowOffset * 0.2, shadowOffset * 0.35))),
        Paint()
          ..color = style.contactShadowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.8, blur * 0.25)),
      );

    // Extruded thickness: stacked copies from the dark base to the ivory
    // wall just under the face, so the walls read as one solid block.
    final steps = math.max(3, (math.max(depthX, depthY) * pixelRatio * 1.5).ceil());
    for (var i = steps; i >= 1; i--) {
      final t = i / steps;
      final color = t > style.backSplit
          ? Color.lerp(style.backColor, style.backShadeColor, (t - style.backSplit) / (1 - style.backSplit))!
          : Color.lerp(style.sideColor, style.sideShadeColor, t / style.backSplit)!;
      canvas.drawRRect(rounded(faceRect.shift(Offset(depthX * t, depthY * t))), Paint()..color = color);
    }
    // Fine gold seam between the ivory wall and the green base.
    final seam = rounded(faceRect.shift(Offset(depthX * style.backSplit, depthY * style.backSplit)));
    canvas.drawRRect(
      seam,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(hairline, face.width * 0.008)
        ..color = style.edgeColor.withValues(alpha: 0.75),
    );
    // Crisp outline of the base and a soft sheen on the green rim.
    canvas.drawRRect(
      rounded(base),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hairline * 1.5
        ..color = const Color(0x66061A0C),
    );

    final face0 = rounded(faceRect);
    // Lift the face off the wall with a hairline of shade along its edge.
    canvas.drawRRect(
      face0.shift(Offset(hairline * 0.8, hairline * 1.2)),
      Paint()
        ..color = const Color(0x40382A10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.6, face.width * 0.012)),
    );

    // Ivory face with gentle top-left lighting.
    canvas.drawRRect(
      face0,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.faceHighlightColor, style.faceColor, style.faceShadeColor],
          stops: const [0, 0.48, 1],
        ).createShader(faceRect),
    );

    // Bevel: warm gold-white catch light top/left, honey shade bottom/right.
    final bevel = face.width * style.bevelFraction;
    final innerRect = faceRect.deflate(bevel);
    final inner = RRect.fromRectAndRadius(innerRect, Radius.circular(math.max(1, radius.x - bevel * 0.6)));
    canvas.drawDRRect(
      face0,
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.catchLightColor,
            style.catchLightColor.withValues(alpha: 0.25),
            style.bevelShadeColor.withValues(alpha: 0),
            style.bevelShadeColor,
          ],
          stops: const [0, 0.35, 0.55, 1],
        ).createShader(faceRect),
    );
    // Slightly domed centre.
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.55),
          radius: 1.2,
          colors: [const Color(0x40FFFFFF), const Color(0x00FFFFFF), const Color(0x147A5A20)],
          stops: const [0, 0.6, 1],
        ).createShader(innerRect),
    );
    // Soft step between bevel and centre.
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, face.width * 0.01)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.faceShadeColor.withValues(alpha: 0.45), const Color(0x99FFFFFF)],
        ).createShader(innerRect),
    );
    // Bright rim along the very top-left edge.
    canvas.drawRRect(
      face0.deflate(math.max(hairline, face.width * 0.012)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(hairline * 1.5, face.width * 0.014)
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF2FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.45],
        ).createShader(faceRect),
    );
    // Thin gold edge line.
    canvas.drawRRect(
      face0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(hairline * 1.2, face.width * 0.01)
        ..color = style.edgeColor,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    picture.dispose();
    return TileBodyImage._(image, Offset(margin, margin), size);
  }

  /// A gold glow ring around a tile's face (a tile landing in the tray), at
  /// full strength (stamp it with the paint's alpha as the strength).
  /// Pre-rendered because its soft outer ring is a blur, too costly to
  /// redraw on every frame.
  Future<TileBodyImage> renderGlow(Size face, double pixelRatio) async {
    final width = face.width * 0.06;
    final margin = (width * 4.6 + 2).ceilToDouble();
    final size = Size(face.width + margin * 2, face.height + margin * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _paintGlow(canvas, faceRRect(Offset(margin, margin) & face), face.width);
    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    picture.dispose();
    return TileBodyImage._(image, Offset(margin, margin), size);
  }

  /// The glow around [rrect]: a soft outer ring and a crisp inner line.
  void _paintGlow(Canvas canvas, RRect rrect, double faceWidth) {
    final width = faceWidth * 0.06;
    final color = style.glowColor;
    canvas
      ..drawRRect(
        rrect.inflate(width * 0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 1.6
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width),
      )
      ..drawRRect(
        rrect.deflate(width * 0.25),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.5
          ..color = color.withValues(alpha: 0.95),
      );
  }

  /// The extra shadow a raised (upper-layer) tile casts onto the tiles below.
  Future<TileBodyImage> renderRaisedShadow(Size face, double pixelRatio) async {
    final blur = face.width * style.raisedShadowBlurFraction;
    final margin = (blur * 2.2 + 2).ceilToDouble();
    final offset =
        Offset(face.width * style.depthXFraction, face.height * style.depthYFraction) +
        Offset(face.width * style.raisedShadowOffsetFraction * 0.7, face.width * style.raisedShadowOffsetFraction);
    final size = Size(face.width + offset.dx + margin * 2, face.height + offset.dy + margin * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    final faceRect = Offset(margin, margin) & face;
    canvas.drawRRect(
      RRect.fromRectAndRadius(faceRect.shift(offset), Radius.circular(face.width * style.cornerRadiusFraction)),
      Paint()
        ..color = style.raisedShadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    picture.dispose();
    return TileBodyImage._(image, Offset(margin, margin), size);
  }
}

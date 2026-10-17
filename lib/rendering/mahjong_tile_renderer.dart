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

  /// Renders the tile, everything baked into one image: a soft cast shadow
  /// and a tight contact shadow down-right, the solid body (a light wall in
  /// the face's colour over a green base, outlined), and the face with a
  /// softly rounded rim lit from the top-left.
  ///
  /// The face sits at [TileBodyImage.faceOffset]; the walls (right and below,
  /// [TileStyle.depthXFraction] / [TileStyle.depthYFraction]) and shadows
  /// paint outside the face, inside the board's fit margin
  /// ([TileStyle.edgeFraction]).
  Future<TileBodyImage> renderBody(Size face, double pixelRatio) async {
    final w = face.width;
    final depth = Offset(w * style.depthXFraction, face.height * style.depthYFraction);
    final sigma = w * style.shadowBlurFraction;
    final hairline = 1 / pixelRatio;
    final outline = math.max(hairline * 1.5, w * 0.014);
    final margin = (math.max(sigma * 3, outline) + 2).ceilToDouble();
    final shadowShift = Offset(w * style.shadowOffsetXFraction, w * style.shadowOffsetFraction);
    final size = Size(
      w + depth.dx + shadowShift.dx + margin * 2,
      face.height + depth.dy + shadowShift.dy + margin * 2,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    final faceRect = Offset(margin, margin) & face;
    final radius = Radius.circular(w * style.cornerRadiusFraction);
    RRect rounded(Rect rect) => RRect.fromRectAndRadius(rect, radius);
    final face0 = rounded(faceRect);
    final base = faceRect.shift(depth);
    // Wall copies: enough that the extruded walls are solid at this size.
    final steps = math.max(4, (math.max(depth.dx, depth.dy) * pixelRatio * 1.5).ceil());

    // Shadows: the body's silhouette, offset down-right and blurred (here,
    // once; the board stamps the image).
    canvas
      ..drawPath(
        _silhouette(faceRect, depth, radius, shift: shadowShift),
        Paint()
          ..color = style.shadowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      )
      ..drawPath(
        _silhouette(faceRect, depth, radius, shift: Offset(w * 0.008, w * 0.014)),
        Paint()
          ..color = style.contactShadowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(hairline, w * 0.012)),
      )
      // Fine dark outline around the whole tile, under the walls.
      ..drawPath(_silhouette(faceRect, depth, radius, inflate: outline), Paint()..color = style.outlineColor);

    // Extruded thickness: stacked copies from the base on the felt up to the
    // wall just under the face, so the walls read as one solid block. The
    // outer part is the green base, the inner part the face's colour,
    // darkening with depth.
    final split = style.backSplit;
    final faceSide = style.sideColor, faceSideShade = style.sideShadeColor;
    for (var i = steps; i >= 1; i--) {
      final t = i / steps;
      final color = t > split
          ? Color.lerp(style.backColor, style.backShadeColor, (t - split) / (1 - split))!
          : Color.lerp(faceSide, faceSideShade, t / split)!;
      canvas.drawRRect(rounded(faceRect.shift(depth * t)), Paint()..color = color);
    }
    // Light along the top of the green base, then the base's dark rim.
    canvas
      ..drawRRect(
        rounded(faceRect.shift(depth * split)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(hairline, w * 0.012)
          ..color = style.backLightColor.withValues(alpha: 0.9),
      )
      ..drawRRect(
        rounded(base),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(hairline, w * 0.008)
          ..color = style.outlineColor.withValues(alpha: 0.55),
      );
    // Walls turn away from the light: darker toward the bottom-right corner.
    canvas
      ..save()
      ..clipPath(_silhouette(faceRect, depth, radius))
      ..drawRect(
        faceRect.expandToInclude(base),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [Color(0x00000000), Color(0x00000000), Color(0x38000000)],
            stops: const [0, 0.55, 1],
          ).createShader(faceRect.expandToInclude(base)),
      )
      ..restore();

    // Crisp step from the face down to its wall.
    canvas.drawRRect(
      face0.shift(Offset(hairline * 0.5, hairline * 0.8)).inflate(w * 0.006),
      Paint()..color = style.edgeColor,
    );

    // The face, lit from the top-left.
    canvas.drawRRect(
      face0,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.faceHighlightColor, style.faceColor, style.faceShadeColor],
          stops: const [0, 0.5, 1],
        ).createShader(faceRect),
    );

    // Its rim rounds down into the wall: a soft shade inside the bottom and
    // right edges, a soft light inside the top and left ones.
    final bevel = w * style.bevelFraction;
    canvas
      ..save()
      ..clipRRect(face0)
      ..drawPath(
        _rim(face0, Offset(-bevel * 0.45, -bevel * 0.55), faceRect.inflate(bevel * 3)),
        Paint()
          ..color = style.bevelShadeColor.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, bevel * 0.45),
      )
      ..drawPath(
        _rim(face0, Offset(bevel * 0.35, bevel * 0.4), faceRect.inflate(bevel * 3)),
        Paint()
          ..color = const Color(0xE6FFFFFF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, bevel * 0.3),
      )
      ..restore();
    // Fine inner edge where the rim meets the flat of the face.
    final inner = face0.deflate(bevel);
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(hairline * 0.75, w * 0.006)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [style.bevelShadeColor.withValues(alpha: 0.2), style.faceHighlightColor.withValues(alpha: 0.8)],
        ).createShader(inner.outerRect),
    );
    // Crisp outer edge of the face.
    canvas.drawRRect(
      face0.deflate(hairline * 0.35),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(hairline, w * 0.008)
        ..color = style.edgeColor.withValues(alpha: 0.45),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    picture.dispose();
    return TileBodyImage._(image, Offset(margin, margin), size);
  }

  /// The tile's outline seen from the front: the face swept along [depth]
  /// to the base, moved by [shift] and grown by [inflate].
  Path _silhouette(Rect face, Offset depth, Radius radius, {Offset shift = Offset.zero, double inflate = 0}) {
    final path = Path();
    final steps = math.max(4, (depth.distance / math.max(1, radius.x * 0.5)).ceil());
    for (var i = 0; i <= steps; i++) {
      path.addRRect(RRect.fromRectAndRadius(face.shift(shift + depth * (i / steps)), radius).inflate(inflate));
    }
    return path;
  }

  /// Everything in [bounds] outside [rrect] moved by [shift]: blurred and
  /// clipped to the face, a soft rim along the edges [shift] points away from.
  Path _rim(RRect rrect, Offset shift, Rect bounds) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(bounds)
    ..addRRect(rrect.shift(shift));

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

  /// The extra shadow a raised (upper-layer) tile casts onto the tiles below:
  /// the body's silhouette, further down-right than its own shadow and
  /// softer, baked once.
  Future<TileBodyImage> renderRaisedShadow(Size face, double pixelRatio) async {
    final w = face.width;
    final blur = w * style.raisedShadowBlurFraction;
    final margin = (blur * 3 + 2).ceilToDouble();
    final depth = Offset(w * style.depthXFraction, face.height * style.depthYFraction);
    final shift = Offset(w * style.raisedShadowOffsetFraction, w * style.raisedShadowOffsetFraction);
    final size = Size(w + depth.dx + shift.dx + margin * 2, face.height + depth.dy + shift.dy + margin * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    final faceRect = Offset(margin, margin) & face;
    canvas.drawPath(
      _silhouette(faceRect, depth, Radius.circular(w * style.cornerRadiusFraction), shift: shift),
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

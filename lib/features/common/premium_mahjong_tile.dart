import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../rendering/mahjong_tile_renderer.dart';
import '../../rendering/symbol_art.dart';
import '../../rendering/tile_style.dart';

/// A single decorative Mahjong tile showing a registry symbol, drawn with the
/// same [MahjongTileRenderer], [TileStyle] and [SymbolArtCache] as the board,
/// so lobby tiles always match the game's tiles. Animated symbols show their
/// still poster frame.
///
/// The widget's layout size is the tile *face* ([faceSize]); the body's
/// thickness and cast shadow paint outside it, so callers can position
/// tiles by their faces.
class PremiumMahjongTile extends StatefulWidget {
  const PremiumMahjongTile({super.key, required this.symbolCode, this.height = 96});

  final String symbolCode;

  /// Face height in logical pixels.
  final double height;

  static const TileStyle style = TileStyle.classicIvory;

  static Size faceSize(double height) => Size(height * style.faceAspect, height);

  /// Visible thickness below the face, in logical pixels.
  static double depthBelow(double height) => height * style.depthYFraction;

  @override
  State<PremiumMahjongTile> createState() => _PremiumMahjongTileState();
}

class _PremiumMahjongTileState extends State<PremiumMahjongTile> {
  static const _renderer = MahjongTileRenderer(PremiumMahjongTile.style);
  TileBodyImage? _body;
  SymbolArt? _art;
  Object? _loadedFor;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(PremiumMahjongTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final services = AppScope.of(context);
    final snapshot = services.content.snapshot;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final key = (widget.symbolCode, widget.height, pixelRatio, snapshot);
    if (key == _loadedFor) return;
    _loadedFor = key;
    final generation = ++_generation;
    final symbol = snapshot.registry[widget.symbolCode];
    final face = PremiumMahjongTile.faceSize(widget.height);
    _renderer.renderBody(face, pixelRatio).then((body) async {
      final art = symbol == null
          ? null
          : await services.symbolArt.resolve(
              symbol,
              snapshot.artwork,
              _renderer.symbolRect(Offset.zero & face).size,
              pixelRatio,
            );
      if (!mounted || generation != _generation) {
        body.dispose();
        return;
      }
      final old = _body;
      setState(() {
        _body = body;
        _art = art;
      });
      // The previous body may still be in the current frame's layer tree.
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    });
  }

  @override
  void dispose() {
    _body?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = PremiumMahjongTile.faceSize(widget.height);
    final body = _body;
    return SizedBox.fromSize(
      size: face,
      child: body == null ? null : CustomPaint(painter: _TilePainter(body, _art, face)),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.body, this.art, this.face);

  final TileBodyImage body;
  final SymbolArt? art;
  final Size face;

  @override
  void paint(Canvas canvas, Size size) {
    const style = PremiumMahjongTile.style;
    body.paint(canvas, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    art?.paint(
      canvas,
      const MahjongTileRenderer(style).symbolRect(Offset.zero & face),
      Paint()
        ..filterQuality = FilterQuality.medium
        // Tuned for static art; animations are drawn as authored.
        ..colorFilter = (art?.isAnimated ?? false) ? null : style.symbolColorFilter,
    );
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.body != body || old.art != art;
}

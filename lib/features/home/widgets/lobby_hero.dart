import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../content/content_snapshot.dart';
import '../../../content/remote_asset_resolver.dart';
import '../../../game_engine/models/symbol_definition.dart';
import '../../common/premium_mahjong_tile.dart';
import '../../common/static_layer.dart';

/// The lobby's centrepiece (reference board): three Mahjong tiles standing
/// on a mossy ledge, a leaf on the left, a sunflower forward and larger in
/// the middle, a purple flower on the right, and beneath them a big gold
/// "Tile Park" over a wooden "PUZZLES" plaque (premium mockup, 2026-10-23).
///
/// The tiles are real registry symbols drawn by [PremiumMahjongTile] (the
/// board's renderer). Each slot takes the first symbol of its list whose
/// artwork is on the device (downloaded, or bundled: the starter pack and the
/// hero's own three symbols, `kHeroArtPrefix`), so the lobby never waits for
/// the network; see [slots].
///
/// Static once drawn: tiles, ledge and title are one [StaticLayer] image.
/// They fade and rise in once when the lobby first appears (not with reduced
/// motion). Screen readers hear one header, "Tile Park: Puzzles".
class LobbyHero extends StatefulWidget {
  const LobbyHero({
    super.key,
    required this.width,
    required this.sceneWidth,
    required this.tileHeight,
    required this.titleSize,
  });

  static const String title = 'Tile Park: Puzzles';

  /// The gold title's words and the plaque's word under them ([title] read
  /// as one header).
  static const String titleWords = 'Tile Park';
  static const String plaqueWord = 'PUZZLES';

  /// Width of the hero's own box (the title fits it).
  final double width;

  /// Width the ledge spans (about the screen width; it may reach past
  /// [width]).
  final double sceneWidth;

  /// Face height of the middle tile; the side tiles are a little smaller.
  final double tileHeight;

  /// Font size of the title before text scaling.
  final double titleSize;

  /// Symbol codes for the left, middle and right tiles, best first: the
  /// reference's leaf, sunflower and purple flower (their art is bundled,
  /// `assets/lobby/hero/`), then the closest symbols of the starter pack, for
  /// a registry whose art for the first ones changed and is not cached yet.
  /// If none of a list is available, any image symbol on the device is used.
  static const List<List<String>> slots = [
    ['PLANT_POT_B', 'PLANT_POT_A', 'XMAS_HOLLY', 'XMAS_TREE'],
    ['FLOWER_SUNFLOWER', 'FLOWER_ZINNIA', 'BIRD_PEACOCK'],
    ['FLOWER_PANSY', 'FLOWER_LAVENDER', 'GALAXY_POMEGRANATE'],
  ];

  static final Expando<Future<List<String>>> _chosen = Expando();

  /// The three codes to show for [snapshot] (computed once per snapshot):
  /// for each slot the first code whose artwork reads from the device
  /// (cache or bundle, never the network), without repeats.
  static Future<List<String>> symbolsFor(ContentSnapshot snapshot) => _chosen[snapshot] ??= _choose(snapshot);

  static Future<List<String>> _choose(ContentSnapshot snapshot) async {
    Future<bool> onDevice(String code) async {
      final symbol = snapshot.registry[code];
      if (symbol == null || symbol.type != SymbolType.image || symbol.assetPath == null) return false;
      try {
        await snapshot.artwork.read(symbol.assetPath!, ContentKind.image, sha256: symbol.sha256);
        return true;
      } on Object {
        return false;
      }
    }

    final chosen = <String>[];
    for (final slot in slots) {
      String? pick;
      for (final code in slot) {
        if (!chosen.contains(code) && await onDevice(code)) {
          pick = code;
          break;
        }
      }
      if (pick == null) {
        for (final code in snapshot.registry.symbols.keys) {
          if (!chosen.contains(code) && await onDevice(code)) {
            pick = code;
            break;
          }
        }
      }
      if (pick == null) return const [];
      chosen.add(pick);
    }
    return chosen;
  }

  @override
  State<LobbyHero> createState() => _LobbyHeroState();
}

class _LobbyHeroState extends State<LobbyHero> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
  ContentSnapshot? _snapshot;
  List<String>? _codes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  /// The lobby rebuilds this widget when the content changes: a new snapshot
  /// (an update, a newly cached level) may have more of the preferred art.
  @override
  void didUpdateWidget(LobbyHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  void _follow() {
    final snapshot = AppScope.of(context).content.snapshot;
    if (identical(snapshot, _snapshot)) return;
    _snapshot = snapshot;
    LobbyHero.symbolsFor(snapshot).then((codes) {
      if (!mounted || !identical(snapshot, _snapshot)) return;
      setState(() => _codes = codes);
      if (_entrance.isDismissed) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _entrance.value = 1;
        } else {
          _entrance.forward();
        }
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final h = widget.tileHeight;
    final face = PremiumMahjongTile.faceSize(h);
    final side = h * 0.86;
    final sideFace = PremiumMahjongTile.faceSize(side);
    // Side tiles tuck a little behind the middle one, tilted outward, their
    // tops a little lower (reference).
    final spread = face.width / 2 + sideFace.width / 2 - sideFace.width * 0.1;
    final depth = PremiumMahjongTile.depthBelow(h);
    final tilesHeight = h + depth;
    final ledgeWidth = widget.sceneWidth;
    final ledgeHeight = ledgeWidth * lobby.heroLedgeAspect;
    final ledgeTop = tilesHeight - ledgeHeight * 0.36;
    final gap = h * 0.08;
    final codes = _codes;

    Widget tile(String code, double height, double dx, double dy, double turn) {
      final size = PremiumMahjongTile.faceSize(height);
      return Positioned(
        left: widget.width / 2 + dx - size.width / 2,
        top: dy,
        child: Transform.rotate(angle: turn, child: PremiumMahjongTile(symbolCode: code, height: height)),
      );
    }

    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.width,
          height: tilesHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: (widget.width - ledgeWidth) / 2,
                top: ledgeTop,
                width: ledgeWidth,
                height: ledgeHeight,
                child: Image.asset(
                  lobby.heroLedgeAsset,
                  fit: BoxFit.fill,
                  cacheWidth: (ledgeWidth * MediaQuery.devicePixelRatioOf(context)).round(),
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
              ),
              if (codes != null && codes.length == 3) ...[
                tile(codes[0], side, -spread, h * 0.13, -0.12),
                tile(codes[2], side, spread, h * 0.13, 0.12),
                tile(codes[1], h, 0, 0, 0),
              ],
            ],
          ),
        ),
        SizedBox(height: gap),
        SizedBox(
          width: widget.width,
          child: _Title(size: widget.titleSize * 1.26),
        ),
        // The plaque tucks up under the title's baseline.
        Transform.translate(
          offset: Offset(0, -widget.titleSize * 0.1),
          child: _Plaque(size: widget.titleSize, maxWidth: widget.width),
        ),
      ],
    );

    return Semantics(
      header: true,
      label: LobbyHero.title,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value.clamp(0, 1).toDouble(),
          child: Transform.translate(offset: Offset(0, (1 - _curve.value) * h * 0.18), child: child),
        ),
        child: StaticLayer(
          // The ledge reaches past the sides and below the tiles; shadows
          // and the title's glow spill a little further.
          overflow: EdgeInsets.fromLTRB(
            math.max(24, (ledgeWidth - widget.width) / 2 + 8),
            24,
            math.max(24, (ledgeWidth - widget.width) / 2 + 8),
            math.max(24.0, ledgeTop + ledgeHeight - tilesHeight - gap),
          ),
          child: hero,
        ),
      ),
    );
  }
}

/// "Tile Park" in gold Playfair Display: the letters filled with the
/// look's gold gradient over a fine dark edge, a soft warm glow and a drop
/// shadow, for depth on the dark scene. Scales
/// down to fit its width (large text included).
class _Title extends StatelessWidget {
  const _Title({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final base = BrainTrainType.title(size: size).copyWith(fontWeight: FontWeight.w800, height: 1.12, letterSpacing: 0);
    final gold = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: lobby.titleGradient,
      stops: const [0, 0.38, 0.6, 1],
    );
    // A RichText with the style a Text would get, so the copies under the
    // gold letters line up with them exactly.
    final defaults = DefaultTextStyle.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final bold = MediaQuery.boldTextOf(context);
    Widget layer(TextStyle style) {
      var merged = defaults.style.merge(style);
      if (bold) merged = merged.merge(const TextStyle(fontWeight: FontWeight.bold));
      return RichText(
        text: TextSpan(text: LobbyHero.titleWords, style: merged),
        maxLines: 1,
        softWrap: false,
        textScaler: scaler,
        textHeightBehavior: defaults.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        children: [
          // Glow and drop shadow.
          layer(
            base.copyWith(
              color: const Color(0x00000000),
              shadows: [
                Shadow(color: lobby.titleGlow, blurRadius: size * 0.45),
                Shadow(color: lobby.titleShadow, blurRadius: size * 0.1, offset: Offset(0, size * 0.06)),
              ],
            ),
          ),
          // Fine dark edge.
          layer(
            base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size * 0.045
                ..strokeJoin = StrokeJoin.round
                ..color = lobby.titleShadow,
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => gold.createShader(
              Rect.fromLTWH(0, bounds.height * 0.16, bounds.width, bounds.height * 0.72),
            ),
            child: layer(base.copyWith(color: const Color(0xFFFFFFFF))),
          ),
        ],
      ),
    );
  }
}

/// "PUZZLES" on a small wooden sign under the title: pointed ends, a gold
/// rim with a fine inner line, ivory Playfair capitals, and a leaf tucked
/// behind each end. Static (drawn into the hero's [StaticLayer]).
class _Plaque extends StatelessWidget {
  const _Plaque({required this.size, required this.maxWidth});

  /// The title's font size: the plaque scales with it.
  final double size;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    final height = size * 0.62;
    final text = Text(
      LobbyHero.plaqueWord,
      maxLines: 1,
      softWrap: false,
      style: BrainTrainType.title(size: size * 0.34, color: lobby.plaqueText).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.11,
        height: 1,
        shadows: [Shadow(color: lobby.titleShadow, blurRadius: 2, offset: Offset(0, size * 0.025))],
      ),
    );
    final leaf = height * 1.15;
    final leafWidth = leaf / lobby.buttonLeafAspect;
    Widget endLeaf(bool flip) => Transform.flip(
      flipX: flip,
      child: Image.asset(
        lobby.buttonLeafAsset,
        width: leafWidth,
        height: leaf,
        cacheWidth: (leafWidth * MediaQuery.devicePixelRatioOf(context)).round(),
        excludeFromSemantics: true,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(left: -leafWidth * 0.55, child: endLeaf(false)),
            Positioned(right: -leafWidth * 0.55, child: endLeaf(true)),
            CustomPaint(
              painter: _PlaquePainter(fill: lobby.plaqueFill, rim: lobby.plaqueRim, shadow: lobby.titleShadow),
              child: SizedBox(
                height: height,
                child: Padding(
                  // Letter spacing trails the last letter: balance it on the left.
                  padding: EdgeInsets.only(left: height * 0.9 + size * 0.11, right: height * 0.9),
                  child: Center(widthFactor: 1, child: text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaquePainter extends CustomPainter {
  const _PlaquePainter({required this.fill, required this.rim, required this.shadow});

  final List<Color> fill;
  final List<Color> rim;
  final Color shadow;

  /// The sign's outline in [r]: a long panel whose ends come to soft points.
  static Path _outline(Rect r) {
    final h = r.height;
    final point = h * 0.42;
    return Path()
      ..moveTo(r.left + point, r.top)
      ..lineTo(r.right - point, r.top)
      ..quadraticBezierTo(r.right - point * 0.25, r.top + h * 0.1, r.right, r.center.dy)
      ..quadraticBezierTo(r.right - point * 0.25, r.bottom - h * 0.1, r.right - point, r.bottom)
      ..lineTo(r.left + point, r.bottom)
      ..quadraticBezierTo(r.left + point * 0.25, r.bottom - h * 0.1, r.left, r.center.dy)
      ..quadraticBezierTo(r.left + point * 0.25, r.top + h * 0.1, r.left + point, r.top)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = _outline(rect);
    // Drop shadow: the outline, offset and darkened (no blur).
    canvas.drawPath(outline.shift(Offset(0, size.height * 0.08)), Paint()..color = shadow.withValues(alpha: 0.55));
    canvas.drawPath(
      outline,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fill,
        ).createShader(rect),
    );
    // Wood grain: a few faint lines along the sign.
    final grain = Paint()
      ..color = shadow.withValues(alpha: 0.16)
      ..strokeWidth = size.height * 0.025;
    canvas.save();
    canvas.clipPath(outline);
    for (final y in const [0.3, 0.55, 0.78]) {
      canvas.drawLine(Offset(0, size.height * y), Offset(size.width, size.height * (y + 0.04)), grain);
    }
    canvas.restore();
    final rimShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: rim,
    ).createShader(rect);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.075
        ..strokeJoin = StrokeJoin.round
        ..shader = rimShader,
    );
    final inset = size.height * 0.14;
    canvas.drawPath(
      _outline(rect.deflate(inset)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.02
        ..color = rim[1].withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_PlaquePainter old) =>
      !listEquals(old.fill, fill) || !listEquals(old.rim, rim) || old.shadow != shadow;
}

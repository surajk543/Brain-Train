import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../app/tablet_scale.dart';
import '../../../game_engine/state/game_actions.dart';
import '../../../rendering/mahjong_tile_renderer.dart';
import '../../../rendering/tile_style.dart';
import '../game_controller.dart';

/// Lights the tile a Hint recommends (and its twin, on the board or in the
/// tray) with a restrained gold glow that breathes gently, over the board.
///
/// The glow is one image rendered once per face size
/// ([MahjongTileRenderer.renderGlow]; its blur is baked in), stamped at the
/// tiles' rects: nothing blurs per frame. The ticker runs only while a hint
/// shows. It goes on the next tap that takes a tile (or an undo, shuffle,
/// revive, restart or the end of the game), or after [duration]. With
/// reduced motion the glow is still (no ticker) and goes the same way.
///
/// A hint never taps for the player: this only draws.
class HintGlowOverlay extends StatefulWidget {
  const HintGlowOverlay({
    super.key,
    required this.controller,
    required this.tileRect,
    required this.trayRect,
    required this.style,
    required this.reduceMotion,
  });

  final GameController controller;

  /// A board tile's face on the canvas (`BoardViewState.tileFaceRect`).
  final Rect? Function(String tileId) tileRect;

  /// A tray tile's face on the canvas (`TrayViewState.targetRectFor`).
  final Rect? Function(String tileId) trayRect;
  final TileStyle style;
  final bool reduceMotion;

  /// How long a hint stays lit.
  static const Duration duration = Duration(milliseconds: 4500);

  /// One breath of the glow.
  static const Duration period = Duration(milliseconds: 1300);

  @override
  State<HintGlowOverlay> createState() => HintGlowOverlayState();
}

class HintGlowOverlayState extends State<HintGlowOverlay> with SingleTickerProviderStateMixin {
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker;
  StreamSubscription<BoardEvent>? _events;
  Timer? _timeout;
  Hint? _hint;
  Duration _elapsed = Duration.zero;

  TileBodyImage? _glow;
  Size? _glowFace;
  bool _rendering = false;

  /// The hint lit now, if any.
  @visibleForTesting
  Hint? get hint => _hint;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _events = widget.controller.events.listen(_onEvent);
  }

  @override
  void didUpdateWidget(HintGlowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_events?.cancel());
      _events = widget.controller.events.listen(_onEvent);
      _clear();
    }
    if (widget.reduceMotion != oldWidget.reduceMotion && _hint != null) _start();
  }

  void _onEvent(BoardEvent event) {
    if (!mounted) return;
    switch (event) {
      case TileHinted(:final hint):
        _hint = hint;
        _start();
      case TileToTray() || MoveUndone() || BoardShuffled() || BoardReset() || TrayReturned() || TrayFull():
        _clear();
      case TrayPairCleared() || TileRejected():
        // A blocked tap keeps the hint; a pair follows its tap's TileToTray.
        break;
    }
  }

  void _start() {
    _timeout?.cancel();
    _elapsed = Duration.zero;
    if (widget.reduceMotion) {
      _ticker.stop();
      _timeout = Timer(HintGlowOverlay.duration, _clear);
    } else {
      _ticker
        ..stop()
        ..start();
    }
    _frame.value++;
  }

  void _clear() {
    _timeout?.cancel();
    _timeout = null;
    if (_ticker.isActive) _ticker.stop();
    if (_hint == null) return;
    _hint = null;
    _frame.value++;
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    if (elapsed >= HintGlowOverlay.duration) {
      _clear();
      return;
    }
    _frame.value++;
  }

  /// Renders the glow for faces of [face] once (again only for a new size).
  void _ensureGlow(Size face) {
    if (_rendering || (_glowFace != null && (_glowFace!.width - face.width).abs() < 0.5)) return;
    _rendering = true;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    unawaited(
      MahjongTileRenderer(widget.style).renderGlow(face, pixelRatio).then((glow) {
        _rendering = false;
        if (!mounted) {
          glow.dispose();
          return;
        }
        _glow?.dispose();
        _glow = glow;
        _glowFace = face;
        _frame.value++;
      }, onError: (Object _) => _rendering = false),
    );
  }

  /// The glow's strength now: a slow breath between 0.6 and 1, fading in over
  /// the first 200 ms and out over the last 400 ms; 1 with reduced motion.
  double get strength {
    if (widget.reduceMotion) return 1;
    final t = _elapsed.inMicroseconds / 1e6;
    final breath = 0.8 + 0.2 * math.cos(2 * math.pi * t / (HintGlowOverlay.period.inMicroseconds / 1e6));
    final fadeIn = (t / 0.2).clamp(0.0, 1.0);
    final end = HintGlowOverlay.duration.inMicroseconds / 1e6;
    final fadeOut = ((end - t) / 0.4).clamp(0.0, 1.0);
    return breath * fadeIn * fadeOut;
  }

  /// The lit faces in this overlay's coordinates: the tile to tap first.
  List<Rect> _faces() {
    final hint = _hint;
    final box = context.findRenderObject();
    if (hint == null || box is! RenderBox || !box.hasSize || !box.attached) return const [];
    final canvas = TabletScale.canvasAbove(box);
    Rect? local(Rect? global) => global == null
        ? null
        : Rect.fromPoints(
            box.globalToLocal(global.topLeft, ancestor: canvas),
            box.globalToLocal(global.bottomRight, ancestor: canvas),
          );
    final partner = hint.partnerTileId;
    return [
      ?local(widget.tileRect(hint.tileId)),
      if (partner != null) ?local(widget.trayRect(partner) ?? widget.tileRect(partner)),
    ];
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _timeout?.cancel();
    _ticker.dispose();
    _frame.dispose();
    _glow?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _HintGlowPainter(this, _frame), size: Size.infinite),
    ),
  );
}

class _HintGlowPainter extends CustomPainter {
  _HintGlowPainter(this.state, ValueListenable<int> repaint) : super(repaint: repaint);

  final HintGlowOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    if (state._hint == null) return;
    final faces = state._faces();
    if (faces.isEmpty) return;
    state._ensureGlow(faces.first.size);
    final glow = state._glow, glowFace = state._glowFace;
    final strength = state.strength;
    if (strength <= 0) return;
    for (final face in faces) {
      if (glow != null && glowFace != null) {
        final scale = face.width / glowFace.width;
        canvas
          ..save()
          ..translate(face.left, face.top)
          ..scale(scale);
        glow.paint(canvas, Offset.zero, Paint()..color = Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 1.0)));
        canvas.restore();
      }
      // A warm wash over the face, like light on the ivory, and a fine gold
      // line around it.
      final rrect = RRect.fromRectAndRadius(face, Radius.circular(face.width * 0.12));
      final gold = state.widget.style.glowColor;
      canvas
        ..drawRRect(rrect, Paint()..color = gold.withValues(alpha: 0.2 * strength))
        ..drawRRect(
          rrect.deflate(0.8),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.6, face.width * 0.05)
            ..color = gold.withValues(alpha: 0.9 * strength),
        );
    }
  }

  @override
  bool shouldRepaint(_HintGlowPainter old) => old.state != state;
}

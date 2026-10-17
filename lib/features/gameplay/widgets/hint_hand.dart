import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

/// The hint's pointing hand: the owner's Lottie (`assets/lottie/hint_hand.json`,
/// recoloured gold with a dark-green outline so it reads on the felt and on
/// ivory tiles). 512 x 512, 21 frames at 30 fps (0.7 s): one tap, the hand
/// pushing along its finger and back. One shape layer turned 140°, so the
/// finger points down and to the right.
///
/// The geometry below comes from the file's path data (the layer's anchor,
/// rotation and position keyframes applied to its paths); it changes only if
/// the file does.
abstract final class HintHand {
  static const String asset = 'assets/lottie/hint_hand.json';

  /// The composition's frame.
  static const double frameSize = 512;

  /// Length of one tap.
  static const Duration tap = Duration(milliseconds: 700);

  /// Where the finger points, as a unit vector in the frame.
  static const Offset pointing = Offset(0.6428, 0.7660);

  /// The progress of the pressed pose (frame 10.435 of 21): the fingertip is
  /// furthest along [pointing]. Frames 0 and 20 are the resting pose, 98
  /// units back.
  static const double pressedProgress = 10.435 / 21;

  /// The pad of the index finger at the pressed pose, in the frame: the
  /// outline's far end is at (375.6, 376.0); the pad sits about 15 units back
  /// along [pointing], inside the finger's rounded end (38 units wide). This
  /// point goes on the tile face.
  static const Offset fingertip = Offset(366, 364);

  /// The hand's box over a whole tap (pressed and resting poses), relative to
  /// [fingertip], in frame units: it reaches up and left of the fingertip.
  static const Rect reach = Rect.fromLTRB(75 - 366, 55 - 364, 383 - 366, 381 - 364);

  /// Width of the hand's box at the pressed pose, in frame units.
  static const double handWidth = 244;

  /// The hand's width as a share of the tile face's width.
  static const double sizeToFace = 1.3;

  /// How far the fingertip sits from the face's centre, back towards the
  /// hand, as a share of the face width: the finger touches the symbol and
  /// leaves most of it in view.
  static const double tipInset = 0.1;

  static LottieComposition? _loaded;

  /// Loads the hand from [bundle]; null when it cannot be read or parsed (the
  /// hint then keeps its glow alone). A loaded hand is kept for later games.
  static Future<LottieComposition?> load(AssetBundle bundle, {String name = asset}) async {
    if (name == asset && _loaded != null) return _loaded;
    try {
      final data = await bundle.load(name);
      final composition = await LottieComposition.fromByteData(data);
      if (name == asset) _loaded = composition;
      return composition;
    } catch (_) {
      return null;
    }
  }

  /// The hand loaded earlier, if any (no wait for later games).
  static LottieComposition? get loaded => _loaded;

  /// Frame units to logical pixels for a face [faceWidth] wide.
  static double scaleFor(double faceWidth) => sizeToFace * faceWidth / handWidth;

  /// Where the fingertip goes on [face] with the hand turned [flip] (each
  /// axis +1 or -1; (1, 1) is the hand above and left of the tile).
  static Offset tipOn(Rect face, Offset flip) =>
      face.center - Offset(pointing.dx * flip.dx, pointing.dy * flip.dy) * (tipInset * face.width);

  /// The hand's box over a tap with its fingertip at [tip].
  static Rect reachAt(Offset tip, double scale, Offset flip) {
    final a = Offset(reach.left * flip.dx, reach.top * flip.dy) * scale;
    final b = Offset(reach.right * flip.dx, reach.bottom * flip.dy) * scale;
    return Rect.fromPoints(tip + a, tip + b);
  }

  static const List<Offset> _flips = [Offset(1, 1), Offset(-1, 1), Offset(1, -1), Offset(-1, -1)];

  /// The turn of the hand for [faces] inside [bounds]: above and left of the
  /// tiles when it fits, else mirrored (to the right near the left edge,
  /// below near the top), so the hand stays on screen. The same turn for
  /// every face when one fits them all.
  static List<Offset> flipsFor(List<Rect> faces, Rect bounds) {
    final room = bounds.deflate(2);
    bool fits(Rect face, Offset flip) {
      final box = reachAt(tipOn(face, flip), scaleFor(face.width), flip);
      return room.contains(box.topLeft) && room.contains(box.bottomRight);
    }

    Offset best(Rect face) {
      for (final flip in _flips) {
        if (fits(face, flip)) return flip;
      }
      // Nothing fits (a tiny screen): the turn that keeps most of it in view.
      double inView(Offset flip) {
        final box = reachAt(tipOn(face, flip), scaleFor(face.width), flip);
        final seen = box.intersect(room);
        return seen.isEmpty ? 0 : seen.width * seen.height;
      }

      return _flips.reduce((a, b) => inView(b) > inView(a) ? b : a);
    }

    for (final flip in _flips) {
      if (faces.every((face) => fits(face, flip))) return [for (final _ in faces) flip];
    }
    return [for (final face in faces) best(face)];
  }

  /// Paints [drawable] at [pose].
  static void paint(Canvas canvas, LottieDrawable drawable, HintHandPose pose) {
    if (pose.scale <= 0) return;
    drawable.setProgress(pose.progress);
    canvas
      ..save()
      ..translate(pose.tip.dx, pose.tip.dy)
      ..scale(pose.flip.dx * pose.scale, pose.flip.dy * pose.scale);
    drawable.draw(
      canvas,
      Rect.fromLTWH(-fingertip.dx, -fingertip.dy, frameSize, frameSize),
      fit: BoxFit.fill,
    );
    canvas.restore();
  }
}

/// Where the hand is and what it does at one moment.
class HintHandPose {
  const HintHandPose({required this.tip, required this.flip, required this.progress, required this.scale});

  /// The fingertip ([HintHand.fingertip]) in the overlay.
  final Offset tip;

  /// The turn of the hand: each axis +1 or -1 (between two during a glide).
  final Offset flip;

  /// The Lottie's progress (0..1).
  final double progress;

  /// Frame units to logical pixels (0 while hidden).
  final double scale;

  @override
  String toString() => 'HintHandPose($tip, flip $flip, progress ${progress.toStringAsFixed(2)}, scale $scale)';
}

/// The hand's moves for one hint: it taps the tile to play twice, glides to
/// its twin on the board, taps it once and glides back, over and over until
/// the hint ends; with no twin on the board (it waits in the tray, or there
/// is none) it keeps tapping the tile. It pops in at the start and shrinks
/// away at the end. With reduced motion it rests pressed on the tile.
class HintHandMotion {
  const HintHandMotion({
    required this.first,
    required this.firstFlip,
    required this.faceWidth,
    required this.total,
    this.second,
    this.secondFlip,
  });

  /// Builds the motion for [tile] (and [twin], on the board) in [bounds].
  factory HintHandMotion.forFaces({required Rect tile, Rect? twin, required Rect bounds, required Duration total}) {
    final flips = HintHand.flipsFor([tile, ?twin], bounds);
    return HintHandMotion(
      first: HintHand.tipOn(tile, flips.first),
      firstFlip: flips.first,
      second: twin == null ? null : HintHand.tipOn(twin, flips.last),
      secondFlip: twin == null ? null : flips.last,
      faceWidth: tile.width,
      total: total,
    );
  }

  final Offset first;
  final Offset firstFlip;
  final Offset? second;
  final Offset? secondFlip;
  final double faceWidth;
  final Duration total;

  /// Taps on the tile, then on its twin, per round.
  static const int tapsOnTile = 2, tapsOnTwin = 1;

  /// One glide between the tiles.
  static const Duration glide = Duration(milliseconds: 350);

  static const Duration popIn = Duration(milliseconds: 180), popOut = Duration(milliseconds: 250);

  /// One round: taps on the tile, a glide, taps on the twin, a glide back.
  static Duration get round => HintHand.tap * (tapsOnTile + tapsOnTwin) + glide * 2;

  /// The hand at rest, pressed on the tile (reduced motion).
  HintHandPose get still =>
      HintHandPose(tip: first, flip: firstFlip, progress: HintHand.pressedProgress, scale: HintHand.scaleFor(faceWidth));

  HintHandPose at(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final size = HintHand.scaleFor(faceWidth) * _appear(t);
    final tapTime = HintHand.tap.inMicroseconds / 1e6;
    double tapProgress(double into) => (into % tapTime) / tapTime;
    final twin = second;
    if (twin == null) {
      return HintHandPose(tip: first, flip: firstFlip, progress: tapProgress(t), scale: size);
    }
    final onTile = tapTime * tapsOnTile, onTwin = tapTime * tapsOnTwin;
    final glideTime = glide.inMicroseconds / 1e6;
    final into = t % (round.inMicroseconds / 1e6);
    if (into < onTile) {
      return HintHandPose(tip: first, flip: firstFlip, progress: tapProgress(into), scale: size);
    }
    if (into < onTile + glideTime) {
      return _glide(first, firstFlip, twin, secondFlip!, (into - onTile) / glideTime, size);
    }
    if (into < onTile + glideTime + onTwin) {
      return HintHandPose(
        tip: twin,
        flip: secondFlip!,
        progress: tapProgress(into - onTile - glideTime),
        scale: size,
      );
    }
    return _glide(twin, secondFlip!, first, firstFlip, (into - onTile - glideTime - onTwin) / glideTime, size);
  }

  static HintHandPose _glide(Offset from, Offset fromFlip, Offset to, Offset toFlip, double u, double size) {
    final eased = Curves.easeInOutCubic.transform(u.clamp(0.0, 1.0));
    return HintHandPose(
      tip: Offset.lerp(from, to, eased)!,
      flip: Offset.lerp(fromFlip, toFlip, eased)!,
      progress: 0,
      scale: size,
    );
  }

  double _appear(double t) {
    final start = popIn.inMicroseconds / 1e6, end = popOut.inMicroseconds / 1e6;
    final left = total.inMicroseconds / 1e6 - t;
    if (left <= 0) return 0;
    final grow = t >= start ? 1.0 : Curves.easeOutBack.transform((t / start).clamp(0.0, 1.0));
    final shrink = left >= end ? 1.0 : Curves.easeIn.transform((left / end).clamp(0.0, 1.0));
    return math.max(0, grow * shrink);
  }
}

/// A [LottieDrawable] for the hand, drawn at any progress (not rounded to the
/// composition's 30 fps).
LottieDrawable hintHandDrawable(LottieComposition composition) =>
    LottieDrawable(composition, frameRate: FrameRate.max);

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:lottie/lottie.dart';

import '../content/content_exception.dart';
import '../content/content_sources.dart';
import '../content/remote_asset_resolver.dart';
import '../game_engine/models/symbol_definition.dart';
import 'symbol_frames.dart';

/// A symbol ready to paint on a tile face.
class SymbolArt {
  const SymbolArt(this.image, {this.isFallback = false});

  /// The still artwork. For [AnimatedSymbolArt] this is the poster frame.
  final ui.Image image;

  /// True when the real artwork was unavailable and a stand-in is shown.
  final bool isFallback;

  /// True for [AnimatedSymbolArt]. Animated art is drawn as authored: the
  /// tile style's symbol colour filter is for static art only.
  bool get isAnimated => false;

  /// Draws the art centred in [box], preserving its aspect ratio.
  void paint(Canvas canvas, Rect box, Paint paint) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final scale = (box.width / w) < (box.height / h) ? box.width / w : box.height / h;
    final dst = Rect.fromCenter(center: box.center, width: w * scale, height: h * scale);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w, h), dst, paint);
  }
}

/// An animated (Lottie) symbol.
///
/// [image] is a still poster (the first frame), used when animations are
/// disabled and by callers that only draw still art. [paintFrame] draws the
/// frame for a time on a shared clock. One frame is recorded per animation
/// frame and box size and then stamped on every tile that shows it, so the
/// Lottie layer tree is walked once per frame, not once per tile. Boards
/// draw frames through a [SymbolFrameAtlas] instead, which renders each
/// frame to pixels once ([drawFrameAt]) rather than replaying its vectors on
/// every tile.
class AnimatedSymbolArt extends SymbolArt {
  AnimatedSymbolArt._(this.composition, this._drawable, super.poster, this.box, this.pixelRatio);

  /// Parses nothing itself: [composition] must come from checked bytes.
  /// Throws when the animation cannot be drawn.
  static Future<AnimatedSymbolArt> create(LottieComposition composition, Size box, double pixelRatio) async {
    final drawable = LottieDrawable(composition, frameRate: FrameRate.max)
      // Some emoji use merge paths; lottie-flutter skips them unless enabled.
      ..enableMergePaths = true
      ..setProgress(0);
    final recorder = ui.PictureRecorder();
    try {
      _drawInto(Canvas(recorder)..scale(pixelRatio), drawable, box);
    } on Object {
      recorder.endRecording().dispose();
      rethrow;
    }
    final picture = recorder.endRecording();
    try {
      final poster = await picture.toImage((box.width * pixelRatio).ceil(), (box.height * pixelRatio).ceil());
      return AnimatedSymbolArt._(composition, drawable, poster, box, pixelRatio);
    } finally {
      picture.dispose();
    }
  }

  final LottieComposition composition;
  final LottieDrawable _drawable;

  /// Logical size the art was made for (the poster is this times
  /// [pixelRatio], rounded up).
  final Size box;
  final double pixelRatio;

  ui.Picture? _frame;
  double _frameProgress = -1;
  Size _frameSize = Size.zero;
  bool _broken = false;

  @override
  bool get isAnimated => true;

  /// True after drawing a frame failed; [paintFrame] then shows the poster.
  bool get isBroken => _broken;

  /// Where in the loop the animation is at [seconds] on a shared clock,
  /// rounded down to one of the animation's own frames.
  double progressAt(double seconds) {
    final length = composition.seconds;
    if (!seconds.isFinite || !length.isFinite || length <= 0) return 0;
    final t = (seconds % length) / length;
    return composition.roundProgress(t, frameRate: FrameRate.composition).clamp(0.0, 1.0);
  }

  /// Draws the frame at [seconds] aspect-fitted into [box], faded by
  /// [opacity]. Falls back to the poster (with [posterPaint]) if the
  /// animation fails to draw.
  void paintFrame(Canvas canvas, Rect box, double seconds, {double opacity = 1, Paint? posterPaint}) {
    final frame = _broken ? null : _frameAt(progressAt(seconds), box.size);
    if (frame == null) {
      paint(canvas, box, posterPaint ?? Paint());
      return;
    }
    canvas
      ..save()
      ..translate(box.left, box.top);
    if (opacity < 1) {
      canvas.saveLayer(Offset.zero & box.size, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
    }
    canvas.drawPicture(frame);
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  /// Draws the frame at [seconds] into a [box]-sized area at the canvas
  /// origin, in logical units (scale the canvas for pixels). Draws the poster
  /// instead once the animation has failed to draw.
  void drawFrameAt(Canvas canvas, double seconds) {
    if (!_broken) {
      final saves = canvas.getSaveCount();
      try {
        _drawable.setProgress(progressAt(seconds));
        _drawInto(canvas, _drawable, box);
        return;
      } on Object catch (error) {
        canvas.restoreToCount(saves);
        _broken = true;
        debugPrint('animated symbol failed to draw, showing its still frame: $error');
      }
    }
    // Replaces anything a failed draw left behind.
    paint(
      canvas,
      Offset.zero & box,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = BlendMode.src,
    );
  }

  ui.Picture? _frameAt(double progress, Size size) {
    if (_frame != null && progress == _frameProgress && size == _frameSize) return _frame;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    try {
      _drawable.setProgress(progress);
      _drawInto(canvas, _drawable, size);
    } on Object catch (error) {
      recorder.endRecording().dispose();
      _broken = true;
      _frame?.dispose();
      _frame = null;
      debugPrint('animated symbol failed to draw, showing its still frame: $error');
      return null;
    }
    // A board that drew the previous frame keeps its own reference to it.
    _frame?.dispose();
    _frameProgress = progress;
    _frameSize = size;
    return _frame = recorder.endRecording();
  }

  static void _drawInto(Canvas canvas, LottieDrawable drawable, Size box) {
    final bounds = Offset.zero & box;
    canvas
      ..save()
      ..clipRect(bounds);
    drawable.draw(canvas, bounds, fit: BoxFit.contain);
    canvas.restore();
  }
}

/// Shared time for the animated symbols of one board, so every tile showing
/// the same animation moves in step. Listeners are notified on [tick]; the
/// owner decides how often (the board throttles to about 30 fps).
class SymbolAnimationClock extends ChangeNotifier {
  final Stopwatch _watch = Stopwatch();

  /// False while the platform asks for no animations: symbols then show
  /// their still poster frame.
  bool motion = true;

  /// Seconds the clock has run, excluding pauses.
  double get seconds => _watch.elapsedMicroseconds / Duration.microsecondsPerSecond;

  bool get isRunning => _watch.isRunning;

  void start() => _watch.start();

  void pause() => _watch.stop();

  void tick() => notifyListeners();
}

/// Decodes and caches symbol artwork at the size it is drawn.
///
/// Images are decoded (and Lottie animations parsed) once per (path, target
/// width) and kept in a small LRU, so replaying a level or resizing back does
/// not decode again.
class SymbolArtCache {
  SymbolArtCache({this.capacity = 48});

  final int capacity;
  final LinkedHashMap<String, Future<SymbolArt>> _entries = LinkedHashMap();

  /// Art for [symbol] fitting a box of [box] logical pixels.
  Future<SymbolArt> resolve(SymbolDefinition symbol, ContentSource source, Size box, double pixelRatio) {
    final targetWidth = (box.width * pixelRatio).round().clamp(16, 1024);
    final key = '${symbol.code}|${symbol.type.name}|${symbol.assetPath ?? symbol.value}|$targetWidth';
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }
    final created = _create(symbol, source, box, pixelRatio, targetWidth);
    _entries[key] = created;
    // Evicted images are not disposed: a board may still be painting them.
    // They are released by the garbage collector once unreferenced.
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return created;
  }

  Future<SymbolArt> _create(
    SymbolDefinition symbol,
    ContentSource source,
    Size box,
    double pixelRatio,
    int targetWidth,
  ) async {
    switch (symbol.type) {
      case SymbolType.image:
        try {
          final Uint8List bytes = await source.read(symbol.assetPath!, ContentKind.image, sha256: symbol.sha256);
          final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
          final frame = await codec.getNextFrame();
          codec.dispose();
          return SymbolArt(frame.image);
        } on ContentException {
          return _fallback(symbol, box, pixelRatio);
        } on Exception {
          // Undecodable bytes: show the fallback face rather than crash.
          return _fallback(symbol, box, pixelRatio);
        }
      case SymbolType.lottie:
        try {
          final bytes = await source.read(symbol.assetPath!, ContentKind.animation, sha256: symbol.sha256);
          checkLottieJson(bytes, symbol.assetPath!);
          final composition = LottieComposition.parseJsonBytes(bytes);
          await _loadEmbeddedImages(composition);
          return await AnimatedSymbolArt.create(composition, box, pixelRatio);
        } on Object catch (error) {
          // Missing, invalid or undrawable animation: never crash the board.
          if (error is! ContentException) debugPrint('animated symbol ${symbol.code} unusable: $error');
          return _fallback(symbol, box, pixelRatio);
        }
      case SymbolType.emoji:
        return SymbolArt(await _renderText(symbol.value!, box, pixelRatio, null));
      case SymbolType.text:
        return SymbolArt(
          await _renderText(symbol.value!, box, pixelRatio, _parseColor(symbol.textColor) ?? const Color(0xFF7A1F1F)),
        );
    }
  }

  static Future<SymbolArt> _fallback(SymbolDefinition symbol, Size box, double pixelRatio) async =>
      SymbolArt(await _renderText(_initials(symbol), box, pixelRatio, const Color(0xFF8A7A5C)), isFallback: true);

  /// Decodes image assets embedded as `data:` URIs. Other references were
  /// rejected by `checkLottieJson`; nothing is fetched from elsewhere.
  static Future<void> _loadEmbeddedImages(LottieComposition composition) async {
    for (final asset in composition.images.values) {
      if (asset.loadedImage != null || !asset.fileName.startsWith('data:')) continue;
      final data = UriData.parse(asset.fileName).contentAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      asset.loadedImage = (await codec.getNextFrame()).image;
      codec.dispose();
    }
  }

  static String _initials(SymbolDefinition symbol) {
    final words = symbol.displayName.split(RegExp(r'[\s_]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  static Color? _parseColor(String? hex) =>
      hex == null ? null : Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

  static Future<ui.Image> _renderText(String text, Size box, double pixelRatio, Color? color) async {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: box.height * 0.55, height: 1.05, color: color, fontWeight: FontWeight.w700),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final scale = [1.0, box.width / painter.width, box.height / painter.height].reduce((a, b) => a < b ? a : b);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(box.width / 2, box.height / 2)
      ..scale(scale)
      ..translate(-painter.width / 2, -painter.height / 2);
    painter.paint(canvas, Offset.zero);
    painter.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage((box.width * pixelRatio).ceil(), (box.height * pixelRatio).ceil());
    picture.dispose();
    return image;
  }

  void clear() => _entries.clear();
}

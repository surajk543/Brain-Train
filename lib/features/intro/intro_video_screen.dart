import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Edge colour of the Sun Game Studio intro, so the square video blends into
/// any screen shape. The native launch screens use the same colour.
const Color kStudioIntroBackground = Color(0xFF0A1A2E);

/// Plays the Sun Game Studio logo video once, then calls [onFinished].
///
/// Never blocks the game: if the video cannot load within [loadTimeout] or
/// fails while playing, it finishes immediately; [maxDuration] caps a stalled
/// playback.
class IntroVideoScreen extends StatefulWidget {
  const IntroVideoScreen({
    super.key,
    required this.onFinished,
    this.asset = 'assets/video/sun_game_studio_intro.mp4',
    this.loadTimeout = const Duration(seconds: 3),
    this.maxDuration = const Duration(seconds: 10),
  });

  final VoidCallback onFinished;
  final String asset;
  final Duration loadTimeout;
  final Duration maxDuration;

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen> {
  late final VideoPlayerController _video = VideoPlayerController.asset(widget.asset);
  Timer? _safety;
  bool _ready = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _safety = Timer(widget.loadTimeout + widget.maxDuration, _finish);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _video.initialize().timeout(widget.loadTimeout);
    } on Object {
      _finish();
      return;
    }
    if (!mounted || _done) return;
    _video.addListener(_onTick);
    setState(() => _ready = true);
    await _video.play();
  }

  void _onTick() {
    final value = _video.value;
    if (value.hasError) {
      _finish();
    } else if (value.isInitialized &&
        !value.isPlaying &&
        value.position >= value.duration - const Duration(milliseconds: 80)) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _safety?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _safety?.cancel();
    _video
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: kStudioIntroBackground,
    child: Center(
      child: AnimatedOpacity(
        opacity: _ready ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: _ready
            ? AspectRatio(
                aspectRatio: _video.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(_video),
                    const CustomPaint(painter: _EdgeFade()),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    ),
  );
}

/// Fades the video's square edges into the background colour.
class _EdgeFade extends CustomPainter {
  const _EdgeFade();

  @override
  void paint(Canvas canvas, Size size) {
    const solid = kStudioIntroBackground;
    final clear = kStudioIntroBackground.withValues(alpha: 0);
    final band = size.shortestSide * 0.08;
    void strip(Rect rect, Alignment from, Alignment to) => canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: from, end: to, colors: [solid, clear]).createShader(rect),
    );
    strip(Rect.fromLTWH(0, 0, size.width, band), Alignment.topCenter, Alignment.bottomCenter);
    strip(Rect.fromLTWH(0, size.height - band, size.width, band), Alignment.bottomCenter, Alignment.topCenter);
    strip(Rect.fromLTWH(0, 0, band, size.height), Alignment.centerLeft, Alignment.centerRight);
    strip(Rect.fromLTWH(size.width - band, 0, band, size.height), Alignment.centerRight, Alignment.centerLeft);
  }

  @override
  bool shouldRepaint(_EdgeFade old) => false;
}

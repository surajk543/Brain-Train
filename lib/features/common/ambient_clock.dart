import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Seconds of ambient (decorative) animation time, advanced by one [Ticker]
/// on every frame (display rate), so motion is smooth and evenly paced.
/// Listen to it to repaint. [frameInterval] can throttle it, but a running
/// ticker produces a frame every vsync anyway, so throttling saves only the
/// listeners' paint work and makes motion step unevenly.
///
/// It only runs while all of these hold:
/// * the owner's [TickerMode] is enabled (so it stops while its route is
///   covered by another screen, via the ticker provider);
/// * the app is in the foreground;
/// * reduced motion is off ([reduceMotion], from
///   `MediaQuery.disableAnimationsOf`); the value then stays put and
///   painters show a still frame.
class AmbientClock extends ValueNotifier<double> {
  AmbientClock(TickerProvider vsync, {this.frameInterval = Duration.zero}) : super(0) {
    _ticker = vsync.createTicker(_tick);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _sync();
      },
    );
  }

  final Duration frameInterval;
  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;
  bool _reduceMotion = false;
  Duration _last = Duration.zero;

  bool get reduceMotion => _reduceMotion;
  set reduceMotion(bool value) {
    _reduceMotion = value;
    _sync();
  }

  /// Whether the clock is running (it may still be muted by [TickerMode]).
  bool get isRunning => _ticker.isActive;

  void _sync() {
    final run = _foreground && !_reduceMotion;
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    if (elapsed == _last || elapsed - _last < frameInterval) return;
    value += (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ticker.dispose();
    super.dispose();
  }
}

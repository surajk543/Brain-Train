import 'dart:async';

import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/intro/brand_logo_screen.dart';
import '../features/intro/intro_video_screen.dart';
import 'app_services.dart';
import 'theme.dart';

/// Launch sequence: Sun Game Studio video, then the Brain Train logo (at
/// least [logoDuration], and until services are ready), then the game.
/// Services (bundled or cached content, no network needed) load from the
/// first frame, in parallel with both.
class BrainTrainApp extends StatefulWidget {
  const BrainTrainApp({
    super.key,
    this.servicesFactory = AppServices.create,
    this.showIntro = true,
    this.logoDuration = const Duration(milliseconds: 2200),
  });

  /// Overridable for tests.
  final Future<AppServices> Function() servicesFactory;

  /// Tests skip the video and the logo screen.
  final bool showIntro;
  final Duration logoDuration;

  @override
  State<BrainTrainApp> createState() => _BrainTrainAppState();
}

enum _Phase { video, logo, game }

class _BrainTrainAppState extends State<BrainTrainApp> {
  late Future<AppServices> _services;
  late _Phase _phase;
  bool _logoTimeUp = false;
  Timer? _logoTimer;

  // Brain Train has a single (night) look; there is no day mode.
  static final ThemeData _theme = buildBrainTrainTheme(Brightness.dark);

  @override
  void initState() {
    super.initState();
    _services = widget.servicesFactory();
    _phase = widget.showIntro ? _Phase.video : _Phase.game;
    _logoTimeUp = !widget.showIntro;
  }

  void _videoFinished() {
    setState(() => _phase = _Phase.logo);
    // Background music starts once the studio intro (which has its own audio)
    // is over.
    unawaited(_services.then((services) => services.music?.start(), onError: (_) {}));
    _logoTimer = Timer(widget.logoDuration, () {
      if (mounted) setState(() => _logoTimeUp = true);
    });
  }

  @override
  void dispose() {
    _logoTimer?.cancel();
    super.dispose();
  }

  MaterialApp _app(Widget home) => MaterialApp(
    title: 'Brain Train',
    debugShowCheckedModeBanner: false,
    theme: _theme,
    darkTheme: _theme,
    themeMode: ThemeMode.dark,
    home: home,
  );

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 450),
    child: switch (_phase) {
      _Phase.video => KeyedSubtree(
        key: const ValueKey('video'),
        child: _app(Scaffold(
          backgroundColor: kStudioIntroBackground,
          body: IntroVideoScreen(onFinished: _videoFinished),
        )),
      ),
      _ => _gameOrLogo(),
    },
  );

  Widget _gameOrLogo() => FutureBuilder<AppServices>(
    key: const ValueKey('game'),
    future: _services,
    builder: (context, snapshot) {
      final services = snapshot.data;
      final showGame = services != null && _logoTimeUp;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: showGame
            ? AppScope(
                key: const ValueKey('home'),
                services: services,
                child: _app(const HomeScreen()),
              )
            : KeyedSubtree(
                key: const ValueKey('logo'),
                child: _app(BrandLogoScreen(
                  loading: _logoTimeUp && !snapshot.hasError,
                  failed: snapshot.hasError,
                  onRetry: () => setState(() => _services = widget.servicesFactory()),
                )),
              ),
      );
    },
  );
}

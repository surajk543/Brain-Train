import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/appearance.dart';
import '../data/settings_repository.dart';
import '../features/home/home_screen.dart';
import '../features/intro/age_screen.dart';
import '../features/intro/brand_logo_screen.dart';
import '../features/intro/intro_video_screen.dart';
import 'app_services.dart';
import 'tablet_scale.dart';
import 'theme.dart';

/// Launch sequence: Sun Game Studio video, then the Brain Train logo (at
/// least [logoDuration], and until services are ready), then the game. At
/// first launch the neutral age screen comes between the logo and the lobby
/// (once: its answer is stored). Services (bundled or cached content, no
/// network needed) load from the first frame, in parallel with both.
///
/// Day / Night (redesign 1.1.0): the lobby and everything after it follow the
/// Appearance setting (`SettingsRepository.appearance`: the phone's setting by
/// default, or Day, or Night). That `MaterialApp` is built only once the
/// services, and with them the stored setting, are loaded, and it reads the
/// platform brightness on its first frame, so the first lobby frame is
/// already in the right look (no flash). The studio video and the white logo
/// screen look the same in both.
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

  static final ThemeData _night = buildBrainTrainTheme(Brightness.dark);
  static final ThemeData _day = buildBrainTrainTheme(Brightness.light);

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

  /// The video and logo screens draw their own fixed colours ([themeMode]
  /// dark); the game follows the Appearance setting.
  MaterialApp _app(Widget home, {ThemeMode themeMode = ThemeMode.dark}) => MaterialApp(
    title: 'Brain Train',
    debugShowCheckedModeBanner: false,
    theme: _day,
    darkTheme: _night,
    themeMode: themeMode,
    home: home,
    // Tablets: the whole UI on a 600-px canvas scaled to the screen.
    builder: (context, child) => TabletScale(child: child ?? const SizedBox.shrink()),
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
                child: _AppearanceBuilder(
                  settings: services.settings,
                  builder: (appearance) => _app(_AgeGate(services: services), themeMode: appearance.themeMode),
                ),
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

/// Rebuilds [builder] when the Appearance setting changes (not on other
/// settings), so the app switches between Day and Night without a restart.
///
/// Debug builds can force a look for a run with
/// `--dart-define=BRAIN_TRAIN_APPEARANCE=day` (or `night`, `system`); it
/// wins over the setting and is ignored in release builds. Players choose in
/// Settings (Game Theme: Day, Night, System).
class _AppearanceBuilder extends StatefulWidget {
  const _AppearanceBuilder({required this.settings, required this.builder});

  final SettingsRepository settings;
  final Widget Function(AppAppearance appearance) builder;

  static final AppAppearance? debugOverride =
      kDebugMode ? AppAppearance.tryParse(const String.fromEnvironment('BRAIN_TRAIN_APPEARANCE')) : null;

  @override
  State<_AppearanceBuilder> createState() => _AppearanceBuilderState();
}

class _AppearanceBuilderState extends State<_AppearanceBuilder> {
  late AppAppearance _appearance = _current;

  AppAppearance get _current => _AppearanceBuilder.debugOverride ?? widget.settings.appearance;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_changed);
  }

  @override
  void didUpdateWidget(_AppearanceBuilder old) {
    super.didUpdateWidget(old);
    if (identical(old.settings, widget.settings)) return;
    old.settings.removeListener(_changed);
    widget.settings.addListener(_changed);
    _appearance = _current;
  }

  void _changed() {
    if (_current != _appearance) setState(() => _appearance = _current);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_appearance);
}

/// The age screen until it has been answered once, then the lobby (which
/// starts ads, with the stored age group, after its first frame).
class _AgeGate extends StatelessWidget {
  const _AgeGate({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.settings,
    builder: (context, _) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: services.settings.ageGroup == null
          ? AgeScreen(
              key: const ValueKey('age'),
              onAnswered: (group) => unawaited(services.settings.setAgeGroup(group)),
            )
          : const HomeScreen(key: ValueKey('lobby')),
    ),
  );
}

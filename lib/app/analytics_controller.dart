import 'dart:async';

import '../content/level_manifest.dart';
import '../data/settings_repository.dart';
import '../game_engine/state/game_actions.dart';
import '../platform/analytics.dart';
import 'rewarded_ads_controller.dart';

/// The app's analytics (owner, 2026-10-24; docs/ANALYTICS.md): Firebase
/// counts the players (Realtime: who plays now) and the screens log a few
/// game events through the methods below, for every player and minimally
/// (never the age group, nothing for ads). Started by the lobby after its
/// first frame; what is logged earlier waits (at most [maxQueued]).
///
/// Analytics identifiers are stored except where privacy choices are
/// required (EEA/UK, as the consent SDK tells [ads]; remembered in
/// [SettingsRepository.privacyRegion] for the next launches). Before the
/// first answer (the first launch) collection waits for it, at most
/// [regionTimeout], then starts without identifiers until the answer comes.
class AnalyticsController {
  AnalyticsController(
    this.analytics, {
    required this.settings,
    required this.ads,
    this.regionTimeout = const Duration(seconds: 10),
  });

  final Analytics analytics;
  final SettingsRepository settings;
  final RewardedAdsController ads;
  final Duration regionTimeout;

  static const int maxQueued = 20;

  final _queued = <Future<void> Function()>[];
  Timer? _regionWait;
  bool _started = false;
  bool _collecting = false;
  bool _disposed = false;

  /// Where privacy choices are required, as last applied (null: unknown, no
  /// identifiers).
  bool? _region;

  /// Starts collection once the player's region is known (see the class).
  /// Safe to call more than once.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Nothing to collect (tests, other platforms): no answer to wait for.
    if (analytics is UnavailableAnalytics) return;
    ads.addListener(_adsChanged);
    final region = ads.privacyRegion ?? settings.privacyRegion;
    if (region != null) {
      _collect(region);
    } else {
      _regionWait = Timer(regionTimeout, () => _collect(null));
    }
  }

  void _adsChanged() {
    final region = ads.privacyRegion;
    if (region == null || _disposed) return;
    if (region != settings.privacyRegion) unawaited(settings.setPrivacyRegion(region));
    if (!_collecting) {
      _collect(region);
    } else if (region != _region) {
      _region = region;
      unawaited(analytics.setAnalyticsStorage(!region));
    }
  }

  void _collect(bool? region) {
    if (_collecting || _disposed) return;
    _collecting = true;
    _regionWait?.cancel();
    _region = region;
    unawaited(analytics.start(analyticsStorage: region == false));
    for (final log in _queued) {
      unawaited(log());
    }
    _queued.clear();
  }

  void _log(Future<void> Function() log) {
    if (_disposed) return;
    if (_collecting) {
      unawaited(log());
    } else if (_queued.length < maxQueued) {
      _queued.add(log);
    }
  }

  /// A screen came up: "lobby", "levels", "settings", "game".
  void screen(String name) => _log(() => analytics.screen(name));

  /// A game screen opened on [entry] (a saved game when [resumed]).
  void levelStart(LevelManifestEntry entry, {required bool resumed}) =>
      _event('level_start', entry, {'resumed': resumed ? 1 : 0});

  /// The game on [entry] ended: won, or lost with a full tray, at [score]
  /// after [time] with [pairs] pairs matched.
  void levelEnd(
    LevelManifestEntry entry, {
    required bool won,
    required int score,
    required Duration time,
    required int pairs,
  }) => _event('level_end', entry, {'success': won ? 1 : 0, 'score': score, 'seconds': time.inSeconds, 'pairs': pairs});

  /// Restart (from the action bar, Pause, the Tray full card or Replay).
  void levelRestart(LevelManifestEntry entry) => _event('level_restart', entry);

  /// A revive, after a rewarded ad ([ad]) or free (no ad to be had, or a
  /// build without ads).
  void revive(LevelManifestEntry entry, {required bool ad}) => _event('revive', entry, {'ad': ad ? 1 : 0});

  /// An Undo, Hint or Shuffle was used.
  void actionUsed(LevelManifestEntry entry, GameAction action) =>
      _event('action_used', entry, {'action': action.name});

  /// One more use of [action], after a rewarded ad ([ad]) or free.
  void actionRefill(LevelManifestEntry entry, GameAction action, {required bool ad}) =>
      _event('action_refill', entry, {'action': action.name, 'ad': ad ? 1 : 0});

  void _event(String name, LevelManifestEntry entry, [Map<String, Object> parameters = const {}]) => _log(
    () => analytics.event(name, {
      'level': entry.order,
      'difficulty': ?entry.difficulty,
      ...parameters,
    }),
  );

  void dispose() {
    _disposed = true;
    _regionWait?.cancel();
    _queued.clear();
    if (_started) ads.removeListener(_adsChanged);
  }
}

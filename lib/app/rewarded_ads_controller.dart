import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/age_group.dart';
import '../platform/rewarded_ads.dart';
import 'background_music.dart';
import 'sound_effects.dart';

/// Rewarded ads for the screens: the Revive button's state, showing an ad
/// (with the game's audio held meanwhile) and the privacy options entry.
/// Started by the lobby after its first frame (never on the startup path);
/// tries again to load an ad when the app comes back to the foreground.
class RewardedAdsController extends ChangeNotifier with WidgetsBindingObserver {
  RewardedAdsController(this.ads, {this.music, this.sounds}) {
    _states = ads.states.listen((_) {
      if (!_disposed) notifyListeners();
    });
  }

  final RewardedAds ads;

  /// Held while an ad is on screen. Null in tests.
  final BackgroundMusic? music;
  final SoundEffects? sounds;

  late final StreamSubscription<RewardedAdsState> _states;
  bool _started = false;
  bool _observing = false;
  bool _disposed = false;

  RewardedAdStatus get status => ads.current.ad;

  /// No ads in this build: Revive needs none.
  bool get off => status == RewardedAdStatus.off;

  /// Settings shows "Privacy choices" only then (EEA/UK).
  bool get privacyOptionsRequired => ads.current.privacyOptionsRequired;

  /// Configures ads for [group], gathers consent and loads the first ad, in
  /// the background. Safe to call more than once; nothing without a group.
  void start(AgeGroup? group) {
    if (_started || _disposed || group == null || off) return;
    _started = true;
    ads.start(AdAudience.forAgeGroup(group));
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object {
      // No binding (a pure Dart test): nothing to observe.
    }
  }

  /// A game opened: have an ad ready for Revive. Never waits.
  void preload() => ads.preload();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) ads.preload();
  }

  /// Shows the loaded ad; music and sound effects stop until it closes.
  Future<RewardedAdResult> show() async {
    if (_disposed) return RewardedAdResult.failed;
    music?.interrupted = true;
    sounds?.stopAll();
    try {
      return await ads.show();
    } finally {
      // The ad may have changed the audio session (iOS).
      unawaited(sounds?.restoreAudioContext());
      music?.interrupted = false;
    }
  }

  /// Google's privacy options form (Settings, EEA/UK).
  Future<bool> openPrivacyOptions() => ads.showPrivacyOptions();

  @override
  void dispose() {
    _disposed = true;
    unawaited(_states.cancel());
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    ads.dispose();
    super.dispose();
  }
}

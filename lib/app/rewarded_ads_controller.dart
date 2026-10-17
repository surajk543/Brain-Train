import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/age_group.dart';
import '../platform/rewarded_ads.dart';
import 'background_music.dart';
import 'rewarded_ad_offer.dart';
import 'sound_effects.dart';

export 'rewarded_ad_offer.dart' show AdOfferMode, RewardedAdOffer, kAdFallbackDelay;

/// Rewarded ads for the screens: the Revive button's state, showing an ad
/// (with the game's audio held meanwhile) and the privacy options entry.
/// Started by the lobby after its first frame (never on the startup path);
/// tries again to load an ad when the app comes back to the foreground.
/// A card that needs an ad asks for an [offer] (with its no-ad fallback).
class RewardedAdsController extends ChangeNotifier with WidgetsBindingObserver {
  RewardedAdsController(this.ads, {this.music, this.sounds, this.fallbackDelay = kAdFallbackDelay}) {
    _states = ads.states.listen((_) {
      if (!_disposed) notifyListeners();
    });
  }

  final RewardedAds ads;

  /// Held while an ad is on screen. Null in tests.
  final BackgroundMusic? music;
  final SoundEffects? sounds;

  /// How long an [offer] waits for an ad before its reward is free.
  final Duration fallbackDelay;

  late final StreamSubscription<RewardedAdsState> _states;
  bool _started = false;
  bool _observing = false;
  bool _disposed = false;

  RewardedAdStatus get status => ads.current.ad;

  /// No ads in this build: Revive needs none.
  bool get off => status == RewardedAdStatus.off;

  /// Loading after a failed attempt (no fill, an error), not the network.
  bool get loadFailed => status == RewardedAdStatus.loading && ads.current.loadFailed;

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

  /// A card that needs an ad opened (Tray full, a refill offer): its reward
  /// with an ad, or (online, no ad to show) without one after
  /// [fallbackDelay]. Dispose it when the card closes.
  RewardedAdOffer offer() => RewardedAdOffer(this, fallbackDelay: fallbackDelay);

  /// Whether the ad server can be reached now (false on any failure).
  Future<bool> checkOnline() async {
    if (_disposed) return false;
    try {
      return await ads.checkOnline();
    } on Object {
      return false;
    }
  }

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

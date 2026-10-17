import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/rewarded_ads.dart';
import 'rewarded_ads_controller.dart';

/// How long an open card that needs a rewarded ad (Revive, a refill) waits
/// for one before its reward is given without an ad (owner, 2026-10-17:
/// AdMob serves almost no ads until the apps are linked to their published
/// store listings). Counted from the card opening.
const Duration kAdFallbackDelay = Duration(seconds: 8);

/// How an open card's reward is paid for now ([RewardedAdOffer.mode]).
enum AdOfferMode {
  /// This build has no ads: the reward is given at once.
  off,

  /// An ad is loaded: the reward needs it watched to the end.
  ad,

  /// No ad to show yet: waiting for one (up to [kAdFallbackDelay]).
  waiting,

  /// Online, but no ad could be shown: the reward is free.
  free,

  /// No internet: no reward until it is back.
  offline,

  /// An ad is on screen, or the reward has been claimed.
  busy,
}

/// One card's rewarded ad: whether its reward needs an ad now, and the
/// claim that shows it (or gives the reward without one). Created when the
/// card opens and disposed when it closes; [claim] pays out at most once.
///
/// Fallback (owner, 2026-10-17): with no ad to show while the device is
/// online (still loading, no fill, load errors, the SDK not started) the
/// reward becomes free [fallbackDelay] after the card opened, or at once
/// when the ads report a failed load ([RewardedAdsState.loadFailed]) or a
/// loaded ad fails to show. "Online" is a fresh check
/// ([RewardedAdsController.checkOnline]); offline the card stays blocked. Once
/// free, the card stays free even if an ad loads meanwhile (no flip under
/// the player's finger); the next card needs an ad again. An ad closed
/// early pays nothing and starts the wait over.
class RewardedAdOffer extends ChangeNotifier {
  RewardedAdOffer(this.ads, {this.fallbackDelay = kAdFallbackDelay}) {
    _status = ads.status;
    if (!ads.off) {
      ads.addListener(_adsChanged);
      _startGrace();
      // Have an ad ready (after a failure: try again now).
      ads.preload();
    }
    _mode = _compute();
    _maybeProbe();
  }

  final RewardedAdsController ads;
  final Duration fallbackDelay;

  late AdOfferMode _mode;
  RewardedAdResult? _lastResult;
  RewardedAdStatus? _status;
  Timer? _grace;
  Timer? _recheck;
  bool _graceOver = false;
  bool _probing = false;

  /// The last online check failed: offline until the next one.
  bool _probedOffline = false;
  bool _free = false;
  bool _busy = false;
  bool _claimed = false;
  bool _disposed = false;

  AdOfferMode get mode => _mode;

  /// How the last ad shown for this card ended without paying (dismissed:
  /// the card says to watch to the end); null before one or after a reward.
  RewardedAdResult? get lastResult => _lastResult;

  /// The button is on: [claim] pays now (with an ad, or without one).
  bool get canClaim => _mode == AdOfferMode.off || _mode == AdOfferMode.ad || _mode == AdOfferMode.free;

  /// Pays the reward: true when it is due, once per offer. [AdOfferMode.ad]
  /// shows the ad (music and sounds held) and pays when its reward was earned,
  /// or when it could not be shown while online; [AdOfferMode.free] and
  /// [AdOfferMode.off] pay at once. False (nothing to give) otherwise: no ad
  /// and no fallback yet, offline, an ad closed early, already claimed, or a
  /// claim still running (rapid taps get one reward).
  Future<bool> claim() async {
    if (_disposed || _busy || _claimed || !canClaim) return false;
    if (_mode != AdOfferMode.ad) {
      _paid();
      return true;
    }
    _busy = true;
    _lastResult = null;
    _update();
    final result = await ads.show();
    var paid = result == RewardedAdResult.earned;
    // A loaded ad that could not be shown: free, unless offline.
    if (result == RewardedAdResult.failed && !_disposed) paid = await ads.checkOnline();
    _busy = false;
    if (_disposed) return false;
    if (paid) {
      _paid();
      return true;
    }
    _lastResult = result;
    if (result == RewardedAdResult.failed) {
      _offline();
    } else {
      // Closed early: the next ad gets its own wait.
      _startGrace();
    }
    _update();
    return false;
  }

  /// The reward is out: nothing more to wait for.
  void _paid() {
    _claimed = true;
    _grace?.cancel();
    _recheck?.cancel();
    _update();
  }

  void _startGrace() {
    _grace?.cancel();
    _graceOver = false;
    _grace = Timer(fallbackDelay, () {
      _graceOver = true;
      _update();
    });
  }

  void _adsChanged() {
    if (_disposed) return;
    final status = ads.status;
    final was = _status;
    _status = status;
    // The ads are past their offline spell: check again rather than wait.
    if (_probedOffline && was == RewardedAdStatus.offline && status != RewardedAdStatus.offline) {
      _recheck?.cancel();
      _probedOffline = false;
    }
    _update();
  }

  /// No network for this card: checked again after [fallbackDelay].
  void _offline() {
    _probedOffline = true;
    _recheck?.cancel();
    _recheck = Timer(fallbackDelay, () {
      _probedOffline = false;
      _update();
    });
  }

  void _update() {
    if (_disposed) return;
    _maybeProbe();
    final next = _compute();
    if (next != _mode) {
      _mode = next;
      notifyListeners();
    }
  }

  /// No ad to show (loading, or one on screen elsewhere).
  bool get _noAd => switch (ads.status) {
    RewardedAdStatus.loading || RewardedAdStatus.showing => true,
    _ => false,
  };

  AdOfferMode _compute() {
    if (ads.off) return AdOfferMode.off;
    if (_busy || _claimed) return AdOfferMode.busy;
    if (_free) return AdOfferMode.free;
    return switch (ads.status) {
      RewardedAdStatus.off => AdOfferMode.off,
      RewardedAdStatus.ready => AdOfferMode.ad,
      RewardedAdStatus.offline => AdOfferMode.offline,
      RewardedAdStatus.loading || RewardedAdStatus.showing => _probedOffline ? AdOfferMode.offline : AdOfferMode.waiting,
    };
  }

  /// Past the wait (or after a failed load) with no ad: is the device
  /// online? Then the reward is free.
  void _maybeProbe() {
    if (_disposed || ads.off || _busy || _claimed || _free || _probing || _probedOffline) return;
    if (!_noAd || !(_graceOver || ads.loadFailed)) return;
    _probing = true;
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final online = await ads.checkOnline();
    _probing = false;
    if (_disposed) return;
    if (!online) {
      _offline();
    } else if (_noAd && !_busy && !_claimed) {
      // Still no ad (one that loaded meanwhile is required).
      _free = true;
      _grace?.cancel();
    }
    _update();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _grace?.cancel();
    _recheck?.cancel();
    if (!ads.off) ads.removeListener(_adsChanged);
    super.dispose();
  }
}

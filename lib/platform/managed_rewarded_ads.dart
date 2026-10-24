import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'rewarded_ads.dart';

/// A failed ads SDK call; [offline] when the network was the cause.
class AdsFailure implements Exception {
  const AdsFailure(this.message, {this.offline = false});

  final String message;
  final bool offline;

  @override
  String toString() => 'AdsFailure($message${offline ? ', offline' : ''})';
}

/// One loaded rewarded ad. Shown at most once, then disposed.
abstract class LoadedRewardedAd {
  /// Shows the ad; completes once it has closed (or could not show).
  Future<RewardedAdResult> show();

  void dispose();
}

/// The SDK calls [ManagedRewardedAds] makes, so tests can stand in. Failures
/// are [AdsFailure]s.
abstract class AdsBackend {
  /// Ad request settings for [audience]; before [initialize] and any request.
  Future<void> configure(AdAudience audience);

  /// The consent flow: a consent information update, then Google's consent
  /// form when one is required (it waits for the player).
  Future<void> gatherConsent(AdAudience audience);

  /// Whether ads may be requested under the consent gathered so far.
  Future<bool> canRequestAds();

  /// Whether the privacy options entry point is required (EEA/UK).
  Future<bool> privacyOptionsRequired();

  Future<void> showPrivacyOptionsForm();

  /// iOS App Tracking Transparency: asks once, if not answered yet, so ads
  /// may use the advertising identifier. Called only for a 13+ audience,
  /// after consent and before [initialize]; a no-op on Android.
  Future<void> requestTracking();

  /// Starts the ads SDK (once, after consent).
  Future<void> initialize();

  Future<LoadedRewardedAd> loadRewardedAd(AdAudience audience);

  /// Whether the network (the ad server) is reachable: asked after a
  /// failure, and by a card with no ad before it gives its reward free.
  Future<bool> isOnline();
}

/// [RewardedAds] over an [AdsBackend]: configures, gathers consent,
/// initializes and keeps one ad loaded, retrying with backoff after a
/// failure. Every backend call is caught and timed out; nothing waits for
/// it on the startup path.
class ManagedRewardedAds implements RewardedAds {
  ManagedRewardedAds(
    this.backend, {
    this.callTimeout = const Duration(seconds: 15),
    this.consentTimeout = const Duration(minutes: 10),
    this.initTimeout = const Duration(seconds: 30),
    this.loadTimeout = const Duration(seconds: 75),
    this.showTimeout = const Duration(minutes: 15),
    this.onlineTimeout = const Duration(seconds: 6),
    this.retryDelays = defaultRetryDelays,
  });

  /// Short: a player may be looking at a disabled Revive button.
  static const List<Duration> defaultRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  final AdsBackend backend;

  /// For quick calls (configuration, status checks).
  final Duration callTimeout;

  /// For the consent and privacy forms, which wait for the player.
  final Duration consentTimeout;
  final Duration initTimeout;
  final Duration loadTimeout;

  /// A guard for an ad that never reports closing.
  final Duration showTimeout;

  /// For [checkOnline]: longer than this counts as offline.
  final Duration onlineTimeout;

  /// Waits before each retry after consecutive failures (the last repeats).
  final List<Duration> retryDelays;

  final _states = StreamController<RewardedAdsState>.broadcast();
  RewardedAdsState _state = const RewardedAdsState(RewardedAdStatus.loading);
  AdAudience? _audience;
  bool _configured = false;
  bool _consentGathered = false;
  bool _trackingAsked = false;
  bool _initialized = false;
  LoadedRewardedAd? _ad;
  Future<void>? _working;
  Timer? _retry;
  int _failures = 0;
  bool _showing = false;
  bool _disposed = false;

  @override
  Stream<RewardedAdsState> get states => _states.stream;

  @override
  RewardedAdsState get current => _state;

  @override
  void start(AdAudience audience) {
    if (_audience != null || _disposed) return;
    _audience = audience;
    _run();
  }

  @override
  void preload() {
    if (_audience == null || _disposed || _ad != null || _showing || _working != null) return;
    _retry?.cancel();
    _run();
  }

  void _run() {
    _working ??= _attempt().whenComplete(() => _working = null);
  }

  Future<void> _attempt() async {
    final audience = _audience!;
    // While offline the button keeps saying so during the retry.
    _set(
      _state.copyWith(
        ad: _state.ad == RewardedAdStatus.offline ? RewardedAdStatus.offline : RewardedAdStatus.loading,
        loadFailed: false,
      ),
    );
    try {
      if (!_configured) {
        await _guard(() => backend.configure(audience), callTimeout, 'configure');
        _configured = true;
      }
      AdsFailure? consentFailure;
      if (!_consentGathered) {
        try {
          await _guard(() => backend.gatherConsent(audience), consentTimeout, 'consent');
          _consentGathered = true;
        } on AdsFailure catch (failure) {
          // Consent from an earlier session may still allow ads.
          consentFailure = failure;
        }
      }
      await _refreshPrivacyOptions();
      if (!await _guard(backend.canRequestAds, callTimeout, 'canRequestAds')) {
        throw consentFailure ?? const AdsFailure('consent not gathered yet');
      }
      // Never asked for children (under 13): their ads are not personalized.
      if (!_trackingAsked && !audience.childDirected) {
        _trackingAsked = true;
        try {
          await _guard(backend.requestTracking, consentTimeout, 'tracking');
        } on AdsFailure catch (failure) {
          // Ads still work without the advertising identifier.
          debugPrint('Rewarded ads: $failure');
        }
      }
      if (!_initialized) {
        await _guard(backend.initialize, initTimeout, 'initialize');
        _initialized = true;
      }
      final ad = await _guard(() => backend.loadRewardedAd(audience), loadTimeout, 'load');
      if (_disposed) {
        _disposeAd(ad);
        return;
      }
      _ad = ad;
      _failures = 0;
      _setAd(RewardedAdStatus.ready);
    } on Object catch (error) {
      if (_disposed) return;
      debugPrint('Rewarded ads: $error');
      final offline = (error is AdsFailure && error.offline) || !await _online();
      if (_disposed) return;
      _set(_state.copyWith(ad: offline ? RewardedAdStatus.offline : RewardedAdStatus.loading, loadFailed: !offline));
      _scheduleRetry();
    }
  }

  Future<bool> _online() async {
    try {
      return await backend.isOnline().timeout(const Duration(seconds: 5));
    } on Object {
      return true; // Unknown: not reported as offline.
    }
  }

  Future<void> _refreshPrivacyOptions() async {
    try {
      final required = await _guard(backend.privacyOptionsRequired, callTimeout, 'privacy options status');
      if (!_disposed) _set(_state.copyWith(privacyOptionsRequired: required, privacyOptionsChecked: true));
    } on AdsFailure catch (failure) {
      debugPrint('Rewarded ads: $failure');
    }
  }

  void _scheduleRetry() {
    if (_disposed || retryDelays.isEmpty) return;
    _retry?.cancel();
    final delay = retryDelays[math.min(_failures, retryDelays.length - 1)];
    _failures++;
    _retry = Timer(delay, () {
      if (!_disposed && _ad == null && !_showing) _run();
    });
  }

  @override
  Future<RewardedAdResult> show() async {
    final ad = _ad;
    if (ad == null || _showing || _disposed) return RewardedAdResult.failed;
    _ad = null;
    _showing = true;
    _setAd(RewardedAdStatus.showing);
    var result = RewardedAdResult.failed;
    try {
      result = await ad.show().timeout(showTimeout);
    } on Object catch (error) {
      debugPrint('Rewarded ads: show failed ($error)');
    } finally {
      _disposeAd(ad);
      _showing = false;
    }
    if (!_disposed) {
      // The next ad, for the next Revive.
      _failures = 0;
      _retry?.cancel();
      _setAd(RewardedAdStatus.loading);
      _run();
    }
    return result;
  }

  @override
  Future<bool> showPrivacyOptions() async {
    if (_disposed || _audience == null) return false;
    var shown = false;
    try {
      await _guard(backend.showPrivacyOptionsForm, consentTimeout, 'privacy options form');
      shown = true;
    } on AdsFailure catch (failure) {
      debugPrint('Rewarded ads: $failure');
    }
    if (_disposed) return shown;
    await _refreshPrivacyOptions();
    // The choices may have changed: the next ad is requested under them.
    if (shown && !_showing && _working == null) {
      final ad = _ad;
      _ad = null;
      if (ad != null) _disposeAd(ad);
      _retry?.cancel();
      _run();
    }
    return shown;
  }

  @override
  Future<bool> checkOnline() async {
    if (_disposed) return false;
    try {
      return await backend.isOnline().timeout(onlineTimeout);
    } on Object catch (error) {
      debugPrint('Rewarded ads: online check failed ($error)');
      return false;
    }
  }

  /// Runs [call] (which may throw at once), timed out, as an [AdsFailure].
  Future<T> _guard<T>(Future<T> Function() call, Duration timeout, String what) async {
    try {
      return await call().timeout(timeout);
    } on AdsFailure {
      rethrow;
    } on TimeoutException {
      throw AdsFailure('$what timed out');
    } on Object catch (error) {
      throw AdsFailure('$what failed ($error)');
    }
  }

  void _disposeAd(LoadedRewardedAd ad) {
    try {
      ad.dispose();
    } on Object catch (error) {
      debugPrint('Rewarded ads: dispose failed ($error)');
    }
  }

  void _setAd(RewardedAdStatus status) => _set(_state.copyWith(ad: status));

  void _set(RewardedAdsState state) {
    if (_disposed || state == _state) return;
    _state = state;
    _states.add(state);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    final ad = _ad;
    _ad = null;
    if (ad != null) _disposeAd(ad);
    unawaited(_states.close());
  }
}

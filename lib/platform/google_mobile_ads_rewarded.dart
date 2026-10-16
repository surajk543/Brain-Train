import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'managed_rewarded_ads.dart';
import 'rewarded_ads.dart';

/// Google's sample rewarded ad units (test ads only). Real units come from
/// android/admob.properties and ios/Runner/Info.plist (docs/ADS.md).
const String kTestRewardedAdUnitAndroid = 'ca-app-pub-3940256099942544/5224354917';
const String kTestRewardedAdUnitIos = 'ca-app-pub-3940256099942544/1712485313';

/// A test device's hashed ID from the ads SDK's log line, for testing with
/// real ad units (docs/ADS.md). Debug and profile builds only:
/// `--dart-define=ADS_TEST_DEVICE_ID=<id>`.
const String _adsTestDevice = String.fromEnvironment('ADS_TEST_DEVICE_ID');

/// A test device's hashed ID from the consent SDK's log line, for its debug
/// settings: `--dart-define=UMP_TEST_DEVICE_ID=<id>`.
const String _consentTestDevice = String.fromEnvironment('UMP_TEST_DEVICE_ID');

/// With [_consentTestDevice]: the consent SDK treats that device as in the
/// EEA, to see the consent form and the "Privacy choices" row outside
/// Europe. `--dart-define=ADS_DEBUG_EEA=true`.
const bool _debugEea = bool.fromEnvironment('ADS_DEBUG_EEA');

List<String> _debugOnly(String id) => !kReleaseMode && id.isNotEmpty ? [id] : const [];

/// The SDK's request configuration for [audience]. Under 13: child-directed
/// and under-age-of-consent tags (owner's choice; the plugin now also offers
/// [AgeRestrictedTreatment.child], which is set too: Google applies the most
/// conservative of them) and content rated G. 13+: rated PG, no tags.
@visibleForTesting
RequestConfiguration requestConfigurationFor(AdAudience audience, {List<String> testDeviceIds = const []}) =>
    RequestConfiguration(
      maxAdContentRating: switch (audience.maxContentRating) {
        AdContentRating.g => MaxAdContentRating.g,
        AdContentRating.pg => MaxAdContentRating.pg,
      },
      // ignore: deprecated_member_use
      tagForChildDirectedTreatment: audience.childDirected ? TagForChildDirectedTreatment.yes : null,
      // ignore: deprecated_member_use
      tagForUnderAgeOfConsent: audience.childDirected ? TagForUnderAgeOfConsent.yes : null,
      ageRestrictedTreatment: audience.childDirected ? AgeRestrictedTreatment.child : null,
      testDeviceIds: testDeviceIds.isEmpty ? null : testDeviceIds,
    );

/// The consent request for [audience]: under 13 is under the age of consent.
@visibleForTesting
ConsentRequestParameters consentParametersFor(AdAudience audience, {List<String> testDeviceIds = const []}) =>
    ConsentRequestParameters(
      tagForUnderAgeOfConsent: audience.childDirected,
      consentDebugSettings: testDeviceIds.isEmpty
          ? null
          : ConsentDebugSettings(
              testIdentifiers: testDeviceIds,
              debugGeography: _debugEea ? DebugGeography.debugGeographyEea : null,
            ),
    );

/// The ad request: never personalized for a child-directed audience.
@visibleForTesting
AdRequest adRequestFor(AdAudience audience) => AdRequest(nonPersonalizedAds: audience.childDirected ? true : null);

/// [AdsBackend] on the `google_mobile_ads` plugin (AdMob + UMP). The only
/// file that imports it. Failures come back as [AdsFailure]s.
class GoogleMobileAdsBackend implements AdsBackend {
  GoogleMobileAdsBackend({
    required this.adUnitId,
    this.callTimeout = const Duration(seconds: 30),
    this.loadTimeout = const Duration(seconds: 60),
    this.showTimeout = const Duration(minutes: 10),
  });

  /// This build's rewarded ad unit (asked once, when the first ad loads).
  final Future<String> Function() adUnitId;
  final Duration callTimeout;
  final Duration loadTimeout;
  final Duration showTimeout;

  String? _unit;

  /// AdMob's network error code (Android and iOS).
  static const int _networkErrorCode = 2;

  @override
  Future<void> configure(AdAudience audience) =>
      MobileAds.instance.updateRequestConfiguration(
        requestConfigurationFor(audience, testDeviceIds: _debugOnly(_adsTestDevice)),
      );

  @override
  Future<void> gatherConsent(AdAudience audience) async {
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      consentParametersFor(audience, testDeviceIds: _debugOnly(_consentTestDevice)),
      () {
        if (!updated.isCompleted) updated.complete();
      },
      (error) {
        if (!updated.isCompleted) updated.completeError(AdsFailure('consent update: ${error.errorCode} ${error.message}'));
      },
    );
    await updated.future.timeout(callTimeout);
    FormError? formError;
    // Shows Google's consent form only when one is required (EEA/UK, not
    // yet answered); waits for the player.
    await ConsentForm.loadAndShowConsentFormIfRequired((error) => formError = error);
    if (formError case final error?) throw AdsFailure('consent form: ${error.errorCode} ${error.message}');
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptionsForm() async {
    FormError? formError;
    await ConsentForm.showPrivacyOptionsForm((error) => formError = error);
    if (formError case final error?) throw AdsFailure('privacy options: ${error.errorCode} ${error.message}');
  }

  @override
  Future<void> initialize() => MobileAds.instance.initialize();

  @override
  Future<LoadedRewardedAd> loadRewardedAd(AdAudience audience) async {
    final unit = _unit ??= await adUnitId();
    final loaded = Completer<LoadedRewardedAd>();
    var abandoned = false;
    await RewardedAd.load(
      adUnitId: unit,
      request: adRequestFor(audience),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // Too late: nobody waits for it any more.
          if (abandoned || loaded.isCompleted) {
            unawaited(ad.dispose());
            return;
          }
          loaded.complete(_GoogleRewardedAd(ad, showTimeout));
        },
        onAdFailedToLoad: (error) {
          if (loaded.isCompleted) return;
          loaded.completeError(
            AdsFailure('load: ${error.code} ${error.message}', offline: error.code == _networkErrorCode),
          );
        },
      ),
    );
    try {
      return await loaded.future.timeout(loadTimeout);
    } on TimeoutException {
      abandoned = true;
      throw const AdsFailure('load timed out');
    }
  }

  @override
  Future<bool> isOnline() async {
    try {
      final addresses = await InternetAddress.lookup('googleads.g.doubleclick.net');
      return addresses.isNotEmpty;
    } on SocketException {
      return false;
    }
  }
}

class _GoogleRewardedAd implements LoadedRewardedAd {
  _GoogleRewardedAd(this.ad, this.showTimeout);

  final RewardedAd ad;
  final Duration showTimeout;

  /// A reward reported just after the ad closed still counts.
  static const Duration _lateRewardGrace = Duration(milliseconds: 400);

  @override
  Future<RewardedAdResult> show() async {
    final closed = Completer<void>();
    var earned = false;
    var failed = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (_) {
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        debugPrint('Rewarded ads: could not show (${error.code} ${error.message})');
        failed = true;
        if (!closed.isCompleted) closed.complete();
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
      await closed.future.timeout(showTimeout);
    } on Object catch (error) {
      debugPrint('Rewarded ads: show ended without closing ($error)');
      return earned ? RewardedAdResult.earned : RewardedAdResult.failed;
    }
    if (!earned && !failed) await Future<void>.delayed(_lateRewardGrace);
    if (earned) return RewardedAdResult.earned;
    return failed ? RewardedAdResult.failed : RewardedAdResult.dismissed;
  }

  @override
  void dispose() => unawaited(ad.dispose().catchError((Object error) => debugPrint('Rewarded ads: $error')));
}

/// This build's rewarded ad unit: Android reads it from the Gradle resource
/// (android/admob.properties), iOS from Info.plist (BrainTrainRewardedAdUnitId);
/// Google's test unit when neither answers.
Future<String> platformRewardedAdUnitId() async {
  final test = Platform.isIOS ? kTestRewardedAdUnitIos : kTestRewardedAdUnitAndroid;
  try {
    final unit = await const MethodChannel(
      'brain_train/platform',
    ).invokeMethod<String>('rewardedAdUnitId').timeout(const Duration(seconds: 5));
    if (unit != null && unit.trim().isNotEmpty) return unit.trim();
    debugPrint('Rewarded ads: no ad unit configured, using the test unit');
  } on Object catch (error) {
    debugPrint('Rewarded ads: ad unit lookup failed ($error), using the test unit');
  }
  return test;
}

/// Rewarded ads on Android and iOS, else [UnavailableRewardedAds]. Creating
/// it does nothing yet: the SDK starts when the lobby calls
/// [RewardedAds.start] after its first frame.
RewardedAds createRewardedAds() {
  if (!Platform.isAndroid && !Platform.isIOS) return const UnavailableRewardedAds();
  return ManagedRewardedAds(GoogleMobileAdsBackend(adUnitId: platformRewardedAdUnitId));
}

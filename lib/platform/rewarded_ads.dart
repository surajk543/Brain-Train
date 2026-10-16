/// Rewarded ads as the app sees them: the Tray full card's Revive shows one
/// and revives only when its reward is earned (docs/ADS.md). Nothing here is
/// on the startup path, and no call can throw or hang the game.
library;

import '../data/age_group.dart';

/// Whether Revive can show an ad now.
enum RewardedAdStatus {
  /// This build has no ads (tests, platforms without the SDK): Revive needs
  /// no ad.
  off,

  /// Starting, gathering consent or loading an ad, including the wait before
  /// a retry after a failure that was not the network (no fill, an error).
  loading,

  /// An ad is loaded: Revive shows it.
  ready,

  /// The last attempt failed for want of a network; it retries with backoff
  /// (and at once when a game opens or the app comes back).
  offline,

  /// An ad is on screen.
  showing,
}

/// How a shown ad ended (reported once it has closed).
enum RewardedAdResult {
  /// Watched far enough to earn the reward.
  earned,

  /// Closed before the reward.
  dismissed,

  /// Could not be shown (none loaded, or the SDK refused).
  failed,
}

/// The highest ad content rating allowed.
enum AdContentRating { g, pg }

/// How ads are requested for an [AgeGroup] (Families policy, mixed
/// audience).
final class AdAudience {
  const AdAudience._({required this.childDirected, required this.maxContentRating});

  /// Under 13: child-directed and under-age-of-consent treatment, rated G,
  /// no personalized ads, and the consent SDK is told the user is under the
  /// age of consent. 13+: rated PG and the normal consent flow.
  factory AdAudience.forAgeGroup(AgeGroup group) => switch (group) {
    AgeGroup.under13 => const AdAudience._(childDirected: true, maxContentRating: AdContentRating.g),
    AgeGroup.thirteenPlus => const AdAudience._(childDirected: false, maxContentRating: AdContentRating.pg),
  };

  /// Child-directed treatment (also: under the age of consent, no
  /// personalized ads).
  final bool childDirected;
  final AdContentRating maxContentRating;

  @override
  bool operator ==(Object other) =>
      other is AdAudience && other.childDirected == childDirected && other.maxContentRating == maxContentRating;

  @override
  int get hashCode => Object.hash(childDirected, maxContentRating);

  @override
  String toString() => 'AdAudience(childDirected: $childDirected, max: ${maxContentRating.name})';
}

/// The ad state and whether the EEA/UK privacy options entry point is
/// required (then Settings shows "Privacy choices").
final class RewardedAdsState {
  const RewardedAdsState(this.ad, {this.privacyOptionsRequired = false});

  final RewardedAdStatus ad;
  final bool privacyOptionsRequired;

  RewardedAdsState copyWith({RewardedAdStatus? ad, bool? privacyOptionsRequired}) =>
      RewardedAdsState(ad ?? this.ad, privacyOptionsRequired: privacyOptionsRequired ?? this.privacyOptionsRequired);

  @override
  bool operator ==(Object other) =>
      other is RewardedAdsState && other.ad == ad && other.privacyOptionsRequired == privacyOptionsRequired;

  @override
  int get hashCode => Object.hash(ad, privacyOptionsRequired);

  @override
  String toString() => 'RewardedAdsState(${ad.name}, privacyOptionsRequired: $privacyOptionsRequired)';
}

abstract class RewardedAds {
  /// State changes; [current] is the latest.
  Stream<RewardedAdsState> get states;
  RewardedAdsState get current;

  /// Configures ad requests for [audience], gathers consent, then loads the
  /// first ad, in the background. Only the first call counts.
  void start(AdAudience audience);

  /// Loads an ad unless one is loaded, loading or showing; after a failure
  /// it retries now instead of waiting for the backoff. Nothing before
  /// [start].
  void preload();

  /// Shows the loaded ad; completes once it has closed. The next ad loads
  /// by itself afterwards.
  Future<RewardedAdResult> show();

  /// Google's privacy options form (EEA/UK); false when it could not be
  /// shown.
  Future<bool> showPrivacyOptions();

  void dispose();
}

/// Rewarded ads where there are none (tests, platforms without the SDK):
/// always [RewardedAdStatus.off], so Revive needs no ad.
class UnavailableRewardedAds implements RewardedAds {
  const UnavailableRewardedAds();

  @override
  Stream<RewardedAdsState> get states => const Stream.empty();

  @override
  RewardedAdsState get current => const RewardedAdsState(RewardedAdStatus.off);

  @override
  void start(AdAudience audience) {}

  @override
  void preload() {}

  @override
  Future<RewardedAdResult> show() async => RewardedAdResult.failed;

  @override
  Future<bool> showPrivacyOptions() async => false;

  @override
  void dispose() {}
}

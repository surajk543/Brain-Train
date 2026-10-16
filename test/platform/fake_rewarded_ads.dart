import 'dart:async';

import 'package:brain_train/platform/rewarded_ads.dart';

/// Scriptable [RewardedAds]: records calls; [show] can be held open with
/// [gate] (the ad on screen) and ends with [showResult].
class FakeRewardedAds implements RewardedAds {
  FakeRewardedAds([RewardedAdStatus status = RewardedAdStatus.ready]) : _current = RewardedAdsState(status);

  final _states = StreamController<RewardedAdsState>.broadcast();
  RewardedAdsState _current;

  final List<AdAudience> starts = [];
  int preloads = 0;
  int shows = 0;
  int privacyForms = 0;
  bool disposed = false;

  RewardedAdResult showResult = RewardedAdResult.earned;

  /// The status once an ad has closed (the next one loading).
  RewardedAdStatus afterShow = RewardedAdStatus.loading;

  /// When set, [show] waits for it (the ad is on screen meanwhile).
  Completer<void>? gate;

  void emit(RewardedAdsState state) {
    _current = state;
    _states.add(state);
  }

  void setStatus(RewardedAdStatus status) => emit(_current.copyWith(ad: status));

  void setPrivacyOptionsRequired(bool required) => emit(_current.copyWith(privacyOptionsRequired: required));

  @override
  Stream<RewardedAdsState> get states => _states.stream;

  @override
  RewardedAdsState get current => _current;

  @override
  void start(AdAudience audience) => starts.add(audience);

  @override
  void preload() => preloads++;

  @override
  Future<RewardedAdResult> show() async {
    shows++;
    setStatus(RewardedAdStatus.showing);
    await gate?.future;
    setStatus(afterShow);
    return showResult;
  }

  @override
  Future<bool> showPrivacyOptions() async {
    privacyForms++;
    return true;
  }

  @override
  void dispose() => disposed = true;
}

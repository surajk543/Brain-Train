import 'dart:async';

import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/platform/managed_rewarded_ads.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAd implements LoadedRewardedAd {
  _FakeAd(this.result);

  final RewardedAdResult result;
  bool disposed = false;
  int shows = 0;

  @override
  Future<RewardedAdResult> show() async {
    shows++;
    return result;
  }

  @override
  void dispose() => disposed = true;
}

/// Stands in for the SDK: records the calls in order, fails on demand.
class _FakeBackend implements AdsBackend {
  final List<String> calls = [];
  AdAudience? configured;
  AdAudience? consentAudience;
  bool canRequest = true;
  bool privacyRequired = false;
  bool online = true;
  RewardedAdResult adResult = RewardedAdResult.earned;
  final List<_FakeAd> ads = [];

  /// Failures for the next loads, in order (null: load fine).
  final List<AdsFailure?> loadFailures = [];
  AdsFailure? consentFailure;
  AdsFailure? trackingFailure;

  /// When set, loads wait for it.
  Completer<void>? loadGate;

  /// When true, consent never answers (a hung SDK).
  bool consentHangs = false;

  @override
  Future<void> configure(AdAudience audience) async {
    calls.add('configure');
    configured = audience;
  }

  @override
  Future<void> gatherConsent(AdAudience audience) async {
    calls.add('consent');
    consentAudience = audience;
    if (consentHangs) await Completer<void>().future;
    if (consentFailure case final failure?) throw failure;
  }

  @override
  Future<bool> canRequestAds() async => canRequest;

  @override
  Future<bool> privacyOptionsRequired() async => privacyRequired;

  @override
  Future<void> showPrivacyOptionsForm() async => calls.add('privacy');

  @override
  Future<void> requestTracking() async {
    calls.add('tracking');
    if (trackingFailure case final failure?) throw failure;
  }

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Future<LoadedRewardedAd> loadRewardedAd(AdAudience audience) async {
    calls.add('load');
    await loadGate?.future;
    if (loadFailures.isNotEmpty) {
      if (loadFailures.removeAt(0) case final failure?) throw failure;
    }
    final ad = _FakeAd(adResult);
    ads.add(ad);
    return ad;
  }

  @override
  Future<bool> isOnline() async => online;
}

/// A backend whose online check never answers.
class _HangingOnline extends _FakeBackend {
  @override
  Future<bool> isOnline() => Completer<bool>().future;
}

Future<void> _settle([int ms = 0]) => Future<void>.delayed(Duration(milliseconds: ms));

/// Waits (real time, briefly) until [ads] reports [status].
Future<void> _until(ManagedRewardedAds ads, RewardedAdStatus status) async {
  for (var i = 0; i < 100 && ads.current.ad != status; i++) {
    await _settle(5);
  }
  expect(ads.current.ad, status);
}

final AdAudience _child = AdAudience.forAgeGroup(AgeGroup.under13);
final AdAudience _teenOrAdult = AdAudience.forAgeGroup(AgeGroup.thirteenPlus);

void main() {
  late _FakeBackend backend;
  late ManagedRewardedAds ads;

  setUp(() {
    backend = _FakeBackend();
    ads = ManagedRewardedAds(
      backend,
      callTimeout: const Duration(milliseconds: 50),
      consentTimeout: const Duration(milliseconds: 50),
      initTimeout: const Duration(milliseconds: 50),
      loadTimeout: const Duration(milliseconds: 50),
      showTimeout: const Duration(milliseconds: 200),
      retryDelays: const [Duration(milliseconds: 20)],
    );
  });

  tearDown(() => ads.dispose());

  test('the audience for each age group', () {
    expect(_child.childDirected, isTrue);
    expect(_child.maxContentRating, AdContentRating.g);
    expect(_teenOrAdult.childDirected, isFalse);
    expect(_teenOrAdult.maxContentRating, AdContentRating.pg);
  });

  test('nothing happens before start, not even on preload', () async {
    expect(ads.current.ad, RewardedAdStatus.loading);
    ads.preload();
    await _settle(30);
    expect(backend.calls, isEmpty);
  });

  test('under 13: child-directed configuration first, consent as under age, then the SDK and an ad', () async {
    ads.start(_child);
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.calls, ['configure', 'consent', 'initialize', 'load']);
    expect(backend.configured, _child);
    expect(backend.consentAudience!.childDirected, isTrue);
  });

  test('13+: the normal flow, rated PG, the tracking prompt after consent and before the SDK', () async {
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.configured!.childDirected, isFalse);
    expect(backend.configured!.maxContentRating, AdContentRating.pg);
    expect(backend.calls, ['configure', 'consent', 'tracking', 'initialize', 'load']);
  });

  test('the tracking prompt is asked once, and a failure does not stop ads', () async {
    backend.trackingFailure = const AdsFailure('no answer');
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(await ads.show(), RewardedAdResult.earned);
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.calls.where((c) => c == 'tracking'), hasLength(1));
  });

  test('only the first start counts', () async {
    ads
      ..start(_child)
      ..start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.configured, _child);
    expect(backend.calls.where((c) => c == 'configure'), hasLength(1));
  });

  test('no ads may be requested yet: no SDK start and no request, retried later', () async {
    backend.canRequest = false;
    ads.start(_teenOrAdult);
    await _settle(10);
    expect(backend.calls, isNot(contains('initialize')));
    expect(backend.calls, isNot(contains('load')));
    expect(ads.current.ad, RewardedAdStatus.loading);
    backend.canRequest = true;
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.calls.where((c) => c == 'consent'), hasLength(1), reason: 'a gathered consent is not asked again');
  });

  test('consent that failed offline still allows ads consented to before', () async {
    backend.consentFailure = const AdsFailure('no network', offline: true);
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
  });

  test('offline: says so, retries with backoff, and is ready once back', () async {
    backend.loadFailures.addAll([const AdsFailure('network', offline: true), const AdsFailure('network', offline: true)]);
    final seen = <RewardedAdStatus>[];
    ads.states.listen((s) => seen.add(s.ad));
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.offline);
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.calls.where((c) => c == 'load'), hasLength(3));
    // (The first attempt's consent check may report while still loading.)
    expect(
      seen.skipWhile((s) => s == RewardedAdStatus.loading),
      [RewardedAdStatus.offline, RewardedAdStatus.ready],
      reason: 'no flicker back to loading while offline',
    );
  });

  test('a failure while the network is down counts as offline', () async {
    backend
      ..online = false
      ..loadFailures.add(const AdsFailure('no fill'));
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.offline);
    backend.online = true;
    await _until(ads, RewardedAdStatus.ready);
  });

  test('no fill: keeps loading and retries', () async {
    backend.loadFailures.addAll([const AdsFailure('no fill'), const AdsFailure('no fill')]);
    ads.start(_teenOrAdult);
    await _settle(5);
    expect(ads.current.ad, RewardedAdStatus.loading);
    await _until(ads, RewardedAdStatus.ready);
  });

  test('no fill marks the load failed until the next attempt (a card may then go free at once)', () async {
    final slow = ManagedRewardedAds(backend, loadTimeout: const Duration(milliseconds: 50), retryDelays: const [Duration(minutes: 5)]);
    addTearDown(slow.dispose);
    backend.loadFailures.addAll([const AdsFailure('no fill'), const AdsFailure('no fill')]);
    expect(slow.current.loadFailed, isFalse);
    slow.start(_teenOrAdult);
    for (var i = 0; i < 100 && !slow.current.loadFailed; i++) {
      await _settle(5);
    }
    expect(slow.current.ad, RewardedAdStatus.loading);
    expect(slow.current.loadFailed, isTrue);
    // A card opening retries at once: no longer failed while it runs.
    backend.loadGate = Completer<void>();
    slow.preload();
    expect(slow.current.loadFailed, isFalse);
    backend.loadGate!.complete();
    for (var i = 0; i < 100 && !slow.current.loadFailed; i++) {
      await _settle(5);
    }
    expect(slow.current.loadFailed, isTrue, reason: 'no fill again');
    slow.preload();
    await _until(slow, RewardedAdStatus.ready);
    expect(slow.current.loadFailed, isFalse);
  });

  test('a network failure is offline, never a failed load', () async {
    backend.loadFailures.add(const AdsFailure('network', offline: true));
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.offline);
    expect(ads.current.loadFailed, isFalse);
  });

  test('checkOnline asks the backend fresh; a failure or a slow answer is offline', () async {
    expect(await ads.checkOnline(), isTrue);
    backend.online = false;
    expect(await ads.checkOnline(), isFalse);
    final slow = ManagedRewardedAds(_HangingOnline(), onlineTimeout: const Duration(milliseconds: 20));
    addTearDown(slow.dispose);
    expect(await slow.checkOnline(), isFalse);
  });

  test('a hung SDK call times out and is retried', () async {
    backend.consentHangs = true;
    backend.canRequest = false;
    ads.start(_teenOrAdult);
    await _settle(80);
    expect(ads.current.ad, isNot(RewardedAdStatus.ready));
    backend
      ..consentHangs = false
      ..canRequest = true;
    await _until(ads, RewardedAdStatus.ready);
  });

  test('preload retries at once after a failure instead of waiting', () async {
    final slow = ManagedRewardedAds(backend, retryDelays: const [Duration(minutes: 5)]);
    addTearDown(slow.dispose);
    backend.loadFailures.add(const AdsFailure('network', offline: true));
    slow.start(_teenOrAdult);
    await _until(slow, RewardedAdStatus.offline);
    slow.preload();
    await _until(slow, RewardedAdStatus.ready);
  });

  test('show: earned, the ad disposed, and the next one loads', () async {
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(await ads.show(), RewardedAdResult.earned);
    expect(backend.ads.first.disposed, isTrue);
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.ads, hasLength(2));
  });

  test('show: dismissed is reported as such', () async {
    backend.adResult = RewardedAdResult.dismissed;
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(await ads.show(), RewardedAdResult.dismissed);
  });

  test('show with no ad loaded fails without calling the SDK', () async {
    backend.loadGate = Completer<void>();
    ads.start(_teenOrAdult);
    await _settle(5);
    expect(await ads.show(), RewardedAdResult.failed);
    backend.loadGate!.complete();
  });

  test('privacy options: required status is reported, the form opens and the ad is requested again', () async {
    backend.privacyRequired = true;
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(ads.current.privacyOptionsRequired, isTrue);
    expect(await ads.showPrivacyOptions(), isTrue);
    expect(backend.calls, contains('privacy'));
    await _until(ads, RewardedAdStatus.ready);
    expect(backend.ads.first.disposed, isTrue, reason: 'requested under the old choices');
    expect(backend.ads, hasLength(2));
  });

  test('privacy options are not required by default', () async {
    ads.start(_teenOrAdult);
    await _until(ads, RewardedAdStatus.ready);
    expect(ads.current.privacyOptionsRequired, isFalse);
  });

  test('the unavailable implementation is off: Revive needs no ad', () async {
    const off = UnavailableRewardedAds();
    expect(off.current.ad, RewardedAdStatus.off);
    expect(await off.show(), RewardedAdResult.failed);
  });

  group('age group', () {
    test('from the birth year: under 13 until 13 is certain', () {
      expect(AgeGroup.fromBirthYear(2026, currentYear: 2026), AgeGroup.under13);
      expect(AgeGroup.fromBirthYear(2014, currentYear: 2026), AgeGroup.under13);
      // Born 2013: 12 or 13 this year.
      expect(AgeGroup.fromBirthYear(2013, currentYear: 2026), AgeGroup.under13);
      expect(AgeGroup.fromBirthYear(2012, currentYear: 2026), AgeGroup.thirteenPlus);
      expect(AgeGroup.fromBirthYear(1950, currentYear: 2026), AgeGroup.thirteenPlus);
    });

    test('stored values', () {
      expect(AgeGroup.under13.storageValue, 'under13');
      expect(AgeGroup.thirteenPlus.storageValue, '13plus');
      expect(AgeGroup.parse('13plus'), AgeGroup.thirteenPlus);
      expect(AgeGroup.parse('under13'), AgeGroup.under13);
      expect(AgeGroup.parse(null), isNull);
      expect(AgeGroup.parse('adult'), isNull);
    });
  });
}

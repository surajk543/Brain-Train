// A card's rewarded ad with its no-ad fallback (owner, 2026-10-17): an ad
// when one is loaded; online with no ad to show, free after kAdFallbackDelay
// (at once after a failed load or a failed show); offline, never. Fake time
// (testWidgets' clock): no real waits.
import 'dart:async';

import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../platform/fake_rewarded_ads.dart';

void main() {
  late FakeRewardedAds ads;
  late RewardedAdsController controller;
  late RewardedAdOffer offer;

  /// Offers and controllers to dispose when a test body ends (before the
  /// test checks that no timer is left).
  final open = <ChangeNotifier>[];

  /// An offer over ads in [status] (a card just opened).
  void openOffer(RewardedAdStatus status, {bool online = true}) {
    ads = FakeRewardedAds(status)..online = online;
    controller = RewardedAdsController(ads);
    offer = controller.offer();
    open.addAll([offer, controller]);
  }

  /// One more card's offer on the same ads.
  RewardedAdOffer another() {
    final next = controller.offer();
    open.add(next);
    return next;
  }

  void testOffer(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          for (final notifier in open.reversed) {
            notifier.dispose();
          }
          open.clear();
        }
      });

  /// Lets stream events and checks land, after [time] on the fake clock.
  Future<void> wait(WidgetTester tester, [Duration time = Duration.zero]) async {
    await tester.pump(time);
    await tester.pump();
  }

  test('the wait is about 8 s', () => expect(kAdFallbackDelay, const Duration(seconds: 8)));

  testOffer('a loaded ad is required: the reward only when it was earned', (tester) async {
    openOffer(RewardedAdStatus.ready);
    expect(offer.mode, AdOfferMode.ad);
    expect(ads.preloads, 1, reason: 'opening the card loads one if none is');
    await wait(tester, kAdFallbackDelay * 2);
    expect(offer.mode, AdOfferMode.ad, reason: 'never free while an ad is loaded');
    expect(await offer.claim(), isTrue);
    expect(ads.shows, 1);
    expect(offer.mode, AdOfferMode.busy);
    expect(await offer.claim(), isFalse, reason: 'one reward per offer');
    expect(ads.shows, 1);
  });

  testOffer('loading: waits, then free after kAdFallbackDelay (online), with no ad shown', (tester) async {
    openOffer(RewardedAdStatus.loading);
    expect(offer.mode, AdOfferMode.waiting);
    expect(offer.canClaim, isFalse);
    expect(await offer.claim(), isFalse);
    await wait(tester, kAdFallbackDelay - const Duration(milliseconds: 100));
    expect(offer.mode, AdOfferMode.waiting);
    expect(ads.onlineChecks, 0);
    await wait(tester, const Duration(milliseconds: 100));
    expect(ads.onlineChecks, 1);
    expect(offer.mode, AdOfferMode.free);
    expect(await offer.claim(), isTrue);
    expect(ads.shows, 0);
    expect(await offer.claim(), isFalse);
  });

  testOffer('a failed load (no fill, an error) is free at once', (tester) async {
    openOffer(RewardedAdStatus.loading);
    ads.failLoad();
    await wait(tester);
    expect(offer.mode, AdOfferMode.free);
    expect(await offer.claim(), isTrue);
    expect(ads.shows, 0);
  });

  testOffer('offline: never free, however long the card is open', (tester) async {
    openOffer(RewardedAdStatus.offline);
    expect(offer.mode, AdOfferMode.offline);
    await wait(tester, kAdFallbackDelay * 4);
    expect(offer.mode, AdOfferMode.offline);
    expect(await offer.claim(), isFalse);
    expect(ads.shows, 0);
  });

  testOffer('loading but the online check fails: offline, and free once it passes again', (tester) async {
    openOffer(RewardedAdStatus.loading, online: false);
    await wait(tester, kAdFallbackDelay);
    expect(ads.onlineChecks, 1);
    expect(offer.mode, AdOfferMode.offline);
    expect(await offer.claim(), isFalse);
    ads.online = true;
    await wait(tester, kAdFallbackDelay);
    expect(ads.onlineChecks, 2, reason: 'checked again after a while');
    expect(offer.mode, AdOfferMode.free);
  });

  testOffer('an ad that loads during the wait is required', (tester) async {
    openOffer(RewardedAdStatus.loading);
    await wait(tester, const Duration(seconds: 3));
    ads.setStatus(RewardedAdStatus.ready);
    await wait(tester);
    expect(offer.mode, AdOfferMode.ad);
    await wait(tester, kAdFallbackDelay);
    expect(offer.mode, AdOfferMode.ad);
  });

  testOffer('an ad that loads during the online check is required', (tester) async {
    openOffer(RewardedAdStatus.loading);
    ads.onlineGate = Completer<void>();
    await wait(tester, kAdFallbackDelay);
    expect(offer.mode, AdOfferMode.waiting);
    ads.setStatus(RewardedAdStatus.ready);
    ads.onlineGate!.complete();
    await wait(tester);
    expect(offer.mode, AdOfferMode.ad);
  });

  testOffer('once free, the open card stays free when an ad loads', (tester) async {
    openOffer(RewardedAdStatus.loading);
    await wait(tester, kAdFallbackDelay);
    expect(offer.mode, AdOfferMode.free);
    ads.setStatus(RewardedAdStatus.ready);
    await wait(tester);
    expect(offer.mode, AdOfferMode.free);
    expect(await offer.claim(), isTrue);
    expect(ads.shows, 0);
    // The next card needs the ad.
    final next = another();
    expect(next.mode, AdOfferMode.ad);
  });

  testOffer('an ad that fails to show pays free (online)', (tester) async {
    openOffer(RewardedAdStatus.ready);
    ads.showResult = RewardedAdResult.failed;
    expect(await offer.claim(), isTrue);
    expect(ads.shows, 1);
    expect(ads.onlineChecks, 1);
    expect(offer.mode, AdOfferMode.busy);
  });

  testOffer('an ad that fails to show while offline pays nothing', (tester) async {
    openOffer(RewardedAdStatus.ready, online: false);
    ads.showResult = RewardedAdResult.failed;
    expect(await offer.claim(), isFalse);
    await wait(tester);
    expect(offer.mode, AdOfferMode.offline);
    expect(offer.lastResult, RewardedAdResult.failed);
  });

  testOffer('an ad closed early pays nothing, and the wait starts over', (tester) async {
    openOffer(RewardedAdStatus.ready);
    await wait(tester, const Duration(seconds: 6));
    ads.showResult = RewardedAdResult.dismissed;
    expect(await offer.claim(), isFalse);
    await wait(tester);
    expect(offer.lastResult, RewardedAdResult.dismissed);
    expect(offer.mode, AdOfferMode.waiting, reason: 'the next ad is loading');
    await wait(tester, const Duration(seconds: 3));
    expect(offer.mode, AdOfferMode.waiting, reason: 'not the rest of the first wait');
    // Another ad arrives within the new wait: it is required again.
    ads
      ..setStatus(RewardedAdStatus.ready)
      ..showResult = RewardedAdResult.earned;
    await wait(tester);
    expect(offer.mode, AdOfferMode.ad);
    expect(await offer.claim(), isTrue);
    expect(ads.shows, 2);
  });

  testOffer('rapid claims pay once (ad and free)', (tester) async {
    openOffer(RewardedAdStatus.ready);
    ads.gate = Completer<void>();
    final claims = [offer.claim(), offer.claim(), offer.claim()];
    await wait(tester);
    expect(offer.mode, AdOfferMode.busy);
    ads.gate!.complete();
    expect(await Future.wait(claims), [true, false, false]);
    expect(ads.shows, 1);

    final free = another();
    ads.failLoad();
    await wait(tester);
    expect(free.mode, AdOfferMode.free);
    expect(await Future.wait([free.claim(), free.claim()]), [true, false]);
  });

  testOffer('a build without ads pays at once and never waits or checks', (tester) async {
    controller = RewardedAdsController(const UnavailableRewardedAds());
    open.add(controller);
    final off = another();
    expect(off.mode, AdOfferMode.off);
    expect(await off.claim(), isTrue);
  });

  testOffer('a disposed offer pays nothing and stops its timers', (tester) async {
    openOffer(RewardedAdStatus.loading);
    offer.dispose();
    await wait(tester, kAdFallbackDelay * 2);
    expect(ads.onlineChecks, 0);
    expect(await offer.claim(), isFalse);
  });
}

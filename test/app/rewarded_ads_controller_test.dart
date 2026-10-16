import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../platform/fake_rewarded_ads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRewardedAds ads;
  late RewardedAdsController controller;

  setUp(() {
    ads = FakeRewardedAds(RewardedAdStatus.loading);
    controller = RewardedAdsController(ads);
  });

  tearDown(() => controller.dispose());

  test('starts once, with the audience of the age group', () {
    controller
      ..start(AgeGroup.under13)
      ..start(AgeGroup.thirteenPlus);
    expect(ads.starts, [AdAudience.forAgeGroup(AgeGroup.under13)]);
    expect(ads.starts.single.childDirected, isTrue);
  });

  test('no age group yet: nothing starts', () {
    controller.start(null);
    expect(ads.starts, isEmpty);
  });

  test('a build without ads never starts them', () {
    final off = RewardedAdsController(const UnavailableRewardedAds());
    addTearDown(off.dispose);
    off.start(AgeGroup.thirteenPlus);
    expect(off.off, isTrue);
    expect(off.privacyOptionsRequired, isFalse);
  });

  test('state changes reach the screens', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    ads.setStatus(RewardedAdStatus.ready);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    expect(controller.status, RewardedAdStatus.ready);
    ads.setPrivacyOptionsRequired(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.privacyOptionsRequired, isTrue);
  });

  test('coming back to the foreground loads an ad', () {
    controller.start(AgeGroup.thirteenPlus);
    final before = ads.preloads;
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(ads.preloads, before + 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(ads.preloads, before + 1);
  });

  test('show passes the result through', () async {
    ads
      ..setStatus(RewardedAdStatus.ready)
      ..showResult = RewardedAdResult.dismissed;
    expect(await controller.show(), RewardedAdResult.dismissed);
    expect(ads.shows, 1);
  });

  test('dispose disposes the ads', () {
    final other = FakeRewardedAds();
    RewardedAdsController(other).dispose();
    expect(other.disposed, isTrue);
  });
}

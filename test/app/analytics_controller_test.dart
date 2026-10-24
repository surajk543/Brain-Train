import 'package:brain_train/app/analytics_controller.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_analytics.dart';
import '../platform/fake_rewarded_ads.dart';

const _entry = LevelManifestEntry(
  levelId: 'level-0007',
  order: 7,
  title: 'Seven',
  ref: ContentRef(url: 'levels/level-0007.json'),
  difficulty: '4',
);

void main() {
  late SettingsRepository settings;
  late FakeRewardedAds ads;
  late RewardedAdsController adsController;
  late FakeAnalytics analytics;
  late AnalyticsController controller;

  Future<void> open({Map<String, Object> prefs = const {}, RewardedAds? withAds}) async {
    SharedPreferences.setMockInitialValues(prefs);
    settings = await SettingsRepository.open();
    ads = FakeRewardedAds(RewardedAdStatus.loading);
    adsController = RewardedAdsController(withAds ?? ads);
    analytics = FakeAnalytics();
    controller = AnalyticsController(
      analytics,
      settings: settings,
      ads: adsController,
      regionTimeout: const Duration(milliseconds: 30),
    );
  }

  /// Lets the ads controller pass a state change on.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  tearDown(() {
    controller.dispose();
    adsController.dispose();
  });

  test('a known region outside the EEA/UK starts at once, with identifiers; earlier logs follow', () async {
    await open(prefs: {SettingsRepository.privacyRegionKey: false});
    controller.screen('lobby');
    expect(analytics.calls, isEmpty, reason: 'nothing before start');
    controller.start();
    expect(analytics.calls, ['start storage=true', 'screen lobby']);
  });

  test('a known EEA/UK region starts without identifiers', () async {
    await open(prefs: {SettingsRepository.privacyRegionKey: true});
    controller.start();
    expect(analytics.calls, ['start storage=false']);
  });

  test('first launch: waits for the consent check, then follows it and remembers it', () async {
    await open();
    controller
      ..start()
      ..levelStart(_entry, resumed: false);
    expect(analytics.calls, isEmpty);
    ads.setPrivacyOptionsRequired(true);
    await settle();
    expect(analytics.calls, ['start storage=false', 'event level_start']);
    expect(settings.privacyRegion, isTrue);
  });

  test('first launch without an answer: starts without identifiers, grants them once it is known', () async {
    await open();
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(analytics.calls, ['start storage=false']);
    ads.setPrivacyOptionsRequired(false);
    await settle();
    expect(analytics.calls, ['start storage=false', 'storage=true']);
    expect(settings.privacyRegion, isFalse);
  });

  test('a player who left the EEA/UK gets identifiers again (and the other way round)', () async {
    await open(prefs: {SettingsRepository.privacyRegionKey: true});
    controller.start();
    ads.setPrivacyOptionsRequired(false);
    await settle();
    ads.setPrivacyOptionsRequired(true);
    await settle();
    expect(analytics.calls, ['start storage=false', 'storage=true', 'storage=false']);
  });

  test('a build without ads (no consent check) starts at once, with identifiers', () async {
    await open(withAds: const UnavailableRewardedAds());
    controller.start();
    expect(analytics.calls, ['start storage=true']);
  });

  test('game events carry the level and its difficulty, and never the age group', () async {
    await open(prefs: {SettingsRepository.privacyRegionKey: false, SettingsRepository.ageGroupKey: 'under13'});
    controller
      ..start()
      ..levelStart(_entry, resumed: true)
      ..levelEnd(_entry, won: true, score: 2450, time: const Duration(seconds: 95, milliseconds: 700), pairs: 36)
      ..levelEnd(_entry, won: false, score: 300, time: const Duration(seconds: 20), pairs: 4)
      ..levelRestart(_entry)
      ..revive(_entry, ad: true)
      ..actionUsed(_entry, GameAction.hint)
      ..actionRefill(_entry, GameAction.shuffle, ad: false);
    expect([for (final (name, parameters) in analytics.events) [name, parameters]], [
      ['level_start', {'level': 7, 'difficulty': '4', 'resumed': 1}],
      ['level_end', {'level': 7, 'difficulty': '4', 'success': 1, 'score': 2450, 'seconds': 95, 'pairs': 36}],
      ['level_end', {'level': 7, 'difficulty': '4', 'success': 0, 'score': 300, 'seconds': 20, 'pairs': 4}],
      ['level_restart', {'level': 7, 'difficulty': '4'}],
      ['revive', {'level': 7, 'difficulty': '4', 'ad': 1}],
      ['action_used', {'level': 7, 'difficulty': '4', 'action': 'hint'}],
      ['action_refill', {'level': 7, 'difficulty': '4', 'action': 'shuffle', 'ad': 0}],
    ]);
    for (final (_, parameters) in analytics.events) {
      expect(parameters.values, isNot(contains('under13')));
    }
  });

  test('before start at most maxQueued logs wait; after dispose nothing goes', () async {
    await open(prefs: {SettingsRepository.privacyRegionKey: false});
    for (var i = 0; i < AnalyticsController.maxQueued + 5; i++) {
      controller.screen('s$i');
    }
    controller.start();
    expect(analytics.calls.where((c) => c.startsWith('screen')), hasLength(AnalyticsController.maxQueued));
    controller.dispose();
    controller.screen('late');
    expect(analytics.calls, isNot(contains('screen late')));
  });
}

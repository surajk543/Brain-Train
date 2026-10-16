// Settings has only the Game Theme, Sound Effects, Music, Vibration and the
// version (owner), plus "Privacy choices" where the consent SDK requires that
// entry point (EEA/UK).
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_rewarded_ads.dart';
import 'lobby_support.dart';

void main() {
  late FakeRewardedAds ads;
  late AppServices services;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Brain Train',
      packageName: 'com.sungamestudio.braintrain',
      version: '1.0.0',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  Future<void> open(WidgetTester tester, {required bool required}) async {
    ads = FakeRewardedAds()..setPrivacyOptionsRequired(required);
    await tester.runAsync(() async => services = await testServices(ads: RewardedAdsController(ads)));
    await pumpLobby(tester, services: services, home: const SettingsScreen());
  }

  testWidgets('hidden where privacy options are not required', (tester) async {
    await open(tester, required: false);
    expect(find.text('Sound Effects'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.text('Privacy choices'), findsNothing);
    expect(find.byIcon(Icons.privacy_tip_outlined), findsNothing);
    expect(find.byType(SwitchListTile), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shown when required, and opens the privacy options form', (tester) async {
    await open(tester, required: true);
    expect(find.text('Privacy choices'), findsOneWidget);
    await tester.tap(find.text('Privacy choices'));
    await tester.pump();
    expect(ads.privacyForms, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('appears and goes as the requirement changes (consent is gathered after the lobby opens)', (tester) async {
    await open(tester, required: false);
    ads.setPrivacyOptionsRequired(true);
    await tester.pump();
    expect(find.text('Privacy choices'), findsOneWidget);
    ads.setPrivacyOptionsRequired(false);
    await tester.pump();
    expect(find.text('Privacy choices'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a build without ads has no privacy row', (tester) async {
    await tester.runAsync(() async => services = await testServices());
    await pumpLobby(tester, services: services, home: const SettingsScreen());
    expect(services.ads.status, RewardedAdStatus.off);
    expect(find.text('Privacy choices'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

// The plugin request settings each age group gets (Families policy).
// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/platform/google_mobile_ads_rewarded.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  final child = AdAudience.forAgeGroup(AgeGroup.under13);
  final teenOrAdult = AdAudience.forAgeGroup(AgeGroup.thirteenPlus);

  test('under 13: child-directed, under the age of consent, rated G', () {
    final config = requestConfigurationFor(child);
    expect(config.tagForChildDirectedTreatment, TagForChildDirectedTreatment.yes);
    expect(config.tagForUnderAgeOfConsent, TagForUnderAgeOfConsent.yes);
    expect(config.ageRestrictedTreatment, AgeRestrictedTreatment.child);
    expect(config.maxAdContentRating, MaxAdContentRating.g);
    expect(config.testDeviceIds, isNull);
    expect(consentParametersFor(child).tagForUnderAgeOfConsent, isTrue);
    expect(adRequestFor(child).nonPersonalizedAds, isTrue);
  });

  test('13+: rated PG, no child tags, the normal consent flow', () {
    final config = requestConfigurationFor(teenOrAdult);
    expect(config.tagForChildDirectedTreatment, isNull);
    expect(config.tagForUnderAgeOfConsent, isNull);
    expect(config.ageRestrictedTreatment, isNull);
    expect(config.maxAdContentRating, MaxAdContentRating.pg);
    expect(consentParametersFor(teenOrAdult).tagForUnderAgeOfConsent, isFalse);
    expect(adRequestFor(teenOrAdult).nonPersonalizedAds, isNull);
  });

  test('test devices go to both SDKs', () {
    expect(requestConfigurationFor(teenOrAdult, testDeviceIds: ['abc']).testDeviceIds, ['abc']);
    expect(consentParametersFor(teenOrAdult, testDeviceIds: ['abc']).consentDebugSettings!.testIdentifiers, ['abc']);
    expect(consentParametersFor(teenOrAdult).consentDebugSettings, isNull);
  });

  test("Google's test units", () {
    expect(kTestRewardedAdUnitAndroid, 'ca-app-pub-3940256099942544/5224354917');
    expect(kTestRewardedAdUnitIos, 'ca-app-pub-3940256099942544/1712485313');
  });

  test('outside Android and iOS there are no ads', () {
    expect(createRewardedAds(), isA<UnavailableRewardedAds>());
  });

  test('the online check dials only public addresses (a DNS ad block or a local answer is offline)', () {
    for (final public in ['142.250.74.66', '8.8.8.8', '2a00:1450:4001:82a::2002', '64:ff9b::8efa:4a42']) {
      expect(isPublicAddress(InternetAddress(public)), isTrue, reason: public);
    }
    for (final local in ['0.0.0.0', '127.0.0.1', '10.0.0.2', '172.16.5.4', '192.168.1.1', '100.64.0.1', '169.254.1.1', '::', '::1', 'fe80::1', 'fd00::1']) {
      expect(isPublicAddress(InternetAddress(local)), isFalse, reason: local);
    }
  });
}

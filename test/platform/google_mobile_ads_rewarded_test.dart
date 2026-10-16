// The plugin request settings each age group gets (Families policy).
// ignore_for_file: deprecated_member_use
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
}

// The neutral age screen: once at first launch, between the logo and the
// lobby; only the derived group is stored, and it decides how ads are
// requested.
import 'package:brain_train/app/app.dart';
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/rewarded_ads_controller.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/intro/age_screen.dart';
import 'package:brain_train/platform/rewarded_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_rewarded_ads.dart';
import 'lobby_support.dart';

const _question = 'What year were you born?';
const _continue = ValueKey('age-continue');

Future<void> _real(WidgetTester tester, [int ms = 200]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late FakeRewardedAds ads;
  late AppServices services;

  Future<void> launch(WidgetTester tester) async {
    ads = FakeRewardedAds(RewardedAdStatus.loading);
    await tester.runAsync(() async => services = await testServices(ads: RewardedAdsController(ads)));
    await tester.pumpWidget(BrainTrainApp(servicesFactory: () async => services, showIntro: false));
    await _real(tester);
  }

  Future<void> pick(WidgetTester tester, String decade, String year) async {
    await tester.tap(find.text(decade));
    await tester.pump();
    await tester.tap(find.text(year));
    await tester.pump();
  }

  testWidgets('first launch: asked once with nothing chosen, then the lobby; only the group is stored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await launch(tester);
    expect(find.text(_question), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byKey(_continue), findsNothing, reason: 'no age chosen in advance');
    expect(ads.starts, isEmpty, reason: 'no ads before the answer');
    await pick(tester, '1980s', '1985');
    expect(find.byKey(_continue), findsOneWidget);
    await tester.tap(find.byKey(_continue));
    await _real(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(_question), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsRepository.ageGroupKey), '13plus');
    expect(prefs.getKeys().where((k) => prefs.get(k).toString().contains('1985')), isEmpty, reason: 'the year is not kept');
    // The lobby starts ads after its first frame, for 13+.
    expect(ads.starts, [AdAudience.forAgeGroup(AgeGroup.thirteenPlus)]);
    expect(ads.starts.single.maxContentRating, AdContentRating.pg);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('later launches go straight to the lobby', (tester) async {
    SharedPreferences.setMockInitialValues({SettingsRepository.ageGroupKey: '13plus'});
    await launch(tester);
    expect(find.text(_question), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(ads.starts, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('under 13: the lobby requests child-directed ads, rated G', (tester) async {
    final year = DateTime.now().year - 5;
    SharedPreferences.setMockInitialValues({});
    await launch(tester);
    await pick(tester, '${year - year % 10}s', '$year');
    await tester.tap(find.byKey(_continue));
    await _real(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsRepository.ageGroupKey), 'under13');
    expect(ads.starts.single.childDirected, isTrue);
    expect(ads.starts.single.maxContentRating, AdContentRating.g);
    await tester.pumpWidget(const SizedBox());
  });

  group('the screen', () {
    late List<AgeGroup> answers;

    Future<void> pumpScreen(WidgetTester tester) async {
      answers = [];
      await tester.runAsync(() async => services = await testServices());
      await pumpLobby(
        tester,
        services: services,
        // A new screen each time (not the state of the last one).
        home: AgeScreen(key: UniqueKey(), onAnswered: answers.add, now: () => DateTime(2026, 10, 16)),
        phone: smallPhone,
      );
    }

    testWidgets('decades down to the 1930s and Earlier, then the years of one decade', (tester) async {
      await pumpScreen(tester);
      for (final decade in ['2020s', '2010s', '1990s', '1930s', 'Earlier']) {
        expect(find.text(decade), findsOneWidget, reason: decade);
      }
      expect(find.text('1920s'), findsNothing);
      await tester.tap(find.text('2020s'));
      await tester.pump();
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('2027'), findsNothing, reason: 'no future years');
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('2010s'), findsOneWidget);
      expect(find.byKey(_continue), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the year turning 13 counts as under 13; a year before counts as 13+', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('2010s'));
      await tester.pump();
      await tester.tap(find.text('2013'));
      await tester.pump();
      await tester.tap(find.byKey(_continue));
      await tester.pump();
      expect(answers, [AgeGroup.under13]);
      await tester.tap(find.byKey(_continue));
      await tester.pump();
      expect(answers, hasLength(1), reason: 'answered once');
    });

    testWidgets('13+ from 2012, and Earlier', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('2010s'));
      await tester.pump();
      await tester.tap(find.text('2012'));
      await tester.pump();
      await tester.tap(find.byKey(_continue));
      await tester.pump();
      expect(answers, [AgeGroup.thirteenPlus]);

      await pumpScreen(tester);
      await tester.tap(find.text('Earlier'));
      await tester.pump();
      await tester.tap(find.byKey(_continue));
      await tester.pump();
      expect(answers, [AgeGroup.thirteenPlus]);
    });

    testWidgets('fits a small phone at large text', (tester) async {
      answers = [];
      await tester.runAsync(() async => services = await testServices());
      await pumpLobby(
        tester,
        services: services,
        home: AgeScreen(onAnswered: answers.add, now: () => DateTime(2026, 10, 16)),
        phone: smallPhone,
        textScale: 1.3,
      );
      await tester.tap(find.text('1990s'));
      await tester.pump();
      await tester.tap(find.text('1999'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(_continue));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(Theme.of(tester.element(find.byType(AgeScreen))).brightness, Brightness.dark);
      expect(LobbyTheme.of(tester.element(find.byType(AgeScreen))), same(LobbyTheme.night));
    });
  });
}

// Settings: no theme choice (Night only, owner 2026-10-20); Sound Effects and
// Music are separate switches.
import 'package:brain_train/app/app.dart';
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({SettingsRepository.ageGroupKey: AgeGroup.thirteenPlus.storageValue});
    PackageInfo.setMockInitialValues(
      appName: 'Brain Train',
      packageName: 'com.sungamestudio.braintrain',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<AppServices> openSettings(WidgetTester tester) async {
    late AppServices services;
    await tester.runAsync(() async => services = await testServices());
    await tester.pumpWidget(BrainTrainApp(servicesFactory: () async => services, showIntro: false));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lobby-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsScreen), findsOneWidget);
    return services;
  }

  testWidgets('no theme choice: Settings is in the Night look', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await openSettings(tester);
    expect(LobbyTheme.of(tester.element(find.byType(SettingsScreen))), same(LobbyTheme.night));
    for (final gone in ['Game Theme', 'Day', 'Night', 'System']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Sound Effects and Music switch independently and persist', (tester) async {
    final services = await openSettings(tester);
    final settings = services.settings;
    expect(settings.sound, isTrue);
    expect(settings.music, isTrue);

    await tester.tap(find.text('Music'));
    await tester.pump();
    expect(settings.music, isFalse);
    expect(settings.sound, isTrue, reason: 'Music off leaves the effects on');

    await tester.tap(find.text('Sound Effects'));
    await tester.pump();
    expect(settings.sound, isFalse);
    expect(settings.music, isFalse);

    await tester.tap(find.text('Music'));
    await tester.pump();
    expect(settings.music, isTrue);
    expect(settings.sound, isFalse, reason: 'Music on leaves the effects off');

    final reopened = await SettingsRepository.open();
    expect(reopened.sound, isFalse);
    expect(reopened.music, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Music value from before 1.1.0 (muted Sound) shows as off', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsRepository.ageGroupKey: AgeGroup.thirteenPlus.storageValue,
      SettingsRepository.soundKey: false,
    });
    await openSettings(tester);
    SwitchListTile row(String key) => tester.widget<SwitchListTile>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(SwitchListTile)),
    );
    final music = row('settings-music');
    final sound = row('settings-sound');
    expect(sound.value, isFalse);
    expect(music.value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final phone in [smallPhone, largePhone]) {
    testWidgets('fits ${phone.name} at 1.3x text', (tester) async {
      late AppServices services;
      await tester.runAsync(() async => services = await testServices());
      await pumpLobby(tester, services: services, home: const SettingsScreen(), phone: phone, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text('Sound Effects'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Vibration'), 100);
      expect(find.text('Vibration'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

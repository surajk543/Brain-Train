// Day / Night / System (redesign 1.1.0): the stored setting, the app following
// it (and the platform brightness under System) without a restart, and the
// design tokens of both looks.
import 'dart:math' as math;

import 'package:brain_train/app/app.dart';
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/brand.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/app/typography.dart';
import 'package:brain_train/data/age_group.dart';
import 'package:brain_train/data/appearance.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/lobby_support.dart';

/// WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [top] (translucent) over [bottom] (opaque).
Color _over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsRepository.appearance', () {
    test('new installs follow the system', () async {
      final settings = await SettingsRepository.open();
      expect(settings.appearance, AppAppearance.system);
    });

    test('is stored, notifies, and survives a restart', () async {
      final settings = await SettingsRepository.open();
      var notified = 0;
      settings.addListener(() => notified++);
      await settings.setAppearance(AppAppearance.day);
      expect(settings.appearance, AppAppearance.day);
      expect(notified, 1);
      // Setting the same value again changes nothing.
      await settings.setAppearance(AppAppearance.day);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SettingsRepository.appearanceKey), 'day');
      expect((await SettingsRepository.open()).appearance, AppAppearance.day);
      await settings.setAppearance(AppAppearance.night);
      expect((await SettingsRepository.open()).appearance, AppAppearance.night);
      expect(notified, 2);
    });

    test('an unreadable stored value falls back to system', () async {
      SharedPreferences.setMockInitialValues({SettingsRepository.appearanceKey: 'sepia'});
      expect((await SettingsRepository.open()).appearance, AppAppearance.system);
    });

    test('maps to MaterialApp theme modes', () {
      expect(AppAppearance.system.themeMode, ThemeMode.system);
      expect(AppAppearance.day.themeMode, ThemeMode.light);
      expect(AppAppearance.night.themeMode, ThemeMode.dark);
    });
  });

  group('the app', () {
    late AppServices services;

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.runAsync(() async => services = await testServices(ageGroup: AgeGroup.thirteenPlus));
      await tester.pumpWidget(BrainTrainApp(servicesFactory: () async => services, showIntro: false));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    // The lobby animates forever (leaves, fireflies): pump past the theme
    // change's 200 ms animation instead of settling.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    BuildContext lobby(WidgetTester tester) => tester.element(find.byType(HomeScreen));

    void expectLook(WidgetTester tester, {required bool day, String? reason}) {
      final context = lobby(tester);
      expect(Theme.of(context).brightness, day ? Brightness.light : Brightness.dark, reason: reason);
      expect(
        BrainTrainPalette.of(context),
        same(day ? BrainTrainPalette.day : BrainTrainPalette.night),
        reason: reason,
      );
      expect(LobbyTheme.of(context), same(day ? LobbyTheme.day : LobbyTheme.night), reason: reason);
      expect(
        BrainTrainTypography.of(context),
        same(day ? BrainTrainTypography.day : BrainTrainTypography.night),
        reason: reason,
      );
    }

    tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue());

    testWidgets('under System, the first lobby frame already follows the platform brightness', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await pumpApp(tester);
        // No settle, no theme animation: the very first lobby frame.
        expectLook(tester, day: brightness == Brightness.light, reason: '$brightness');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('under System, it follows the platform brightness while running', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await pumpApp(tester);
      final state = tester.state(find.byType(HomeScreen));
      expectLook(tester, day: false);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await settle(tester);
      expectLook(tester, day: true);
      expect(tester.state(find.byType(HomeScreen)), same(state), reason: 'no restart');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Day and Night override the platform, at once and without a restart', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await pumpApp(tester);
      final state = tester.state(find.byType(HomeScreen));
      expectLook(tester, day: true);

      await tester.runAsync(() => services.settings.setAppearance(AppAppearance.night));
      await settle(tester);
      expectLook(tester, day: false, reason: 'Night on a light phone');

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.runAsync(() => services.settings.setAppearance(AppAppearance.day));
      await settle(tester);
      expectLook(tester, day: true, reason: 'Day on a dark phone');

      await tester.runAsync(() => services.settings.setAppearance(AppAppearance.system));
      await settle(tester);
      expectLook(tester, day: false, reason: 'System on a dark phone');
      expect(tester.state(find.byType(HomeScreen)), same(state), reason: 'no restart');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a stored Day is used from the first lobby frame on a dark phone', (tester) async {
      SharedPreferences.setMockInitialValues({SettingsRepository.appearanceKey: 'day'});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await pumpApp(tester);
      expectLook(tester, day: true);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('design tokens', () {
    test('both themes carry the palette, lobby and typography of their look', () {
      for (final (brightness, palette, lobby, type) in [
        (Brightness.light, BrainTrainPalette.day, LobbyTheme.day, BrainTrainTypography.day),
        (Brightness.dark, BrainTrainPalette.night, LobbyTheme.night, BrainTrainTypography.night),
      ]) {
        final theme = buildBrainTrainTheme(brightness);
        expect(theme.brightness, brightness);
        expect(theme.extension<BrainTrainPalette>(), same(palette));
        expect(theme.extension<LobbyTheme>(), same(lobby));
        expect(theme.extension<BrainTrainTypography>(), same(type));
        expect(theme.textTheme.bodyMedium!.fontFamily, BrainTrainFonts.ui);
        expect(theme.textTheme.headlineMedium!.fontFamily, BrainTrainFonts.display);
        expect(theme.scaffoldBackgroundColor, palette.feltDark);
      }
      expect(BrainTrainPalette.day.isNight, isFalse);
      expect(BrainTrainPalette.night.isNight, isTrue);
      expect(BrainTrainPalette.forBrightness(Brightness.light), same(BrainTrainPalette.day));
      expect(LobbyTheme.forBrightness(Brightness.dark), same(LobbyTheme.night));
      // Night is the look before 1.1.0.
      expect(LobbyTheme.night.sceneWash, isNull);
      expect(BrainTrainPalette.night.feltEdge, kFeltEdge);
    });

    test('the type scale: Playfair for titles, Manrope for UI, within the reference sizes', () {
      for (final (style, family, weight, min, max) in [
        (BrainTrainType.title(), BrainTrainFonts.display, FontWeight.w700, 36.0, 44.0),
        (BrainTrainType.levelName(), BrainTrainFonts.display, FontWeight.w600, 22.0, 28.0),
        (BrainTrainType.heading(), BrainTrainFonts.display, FontWeight.w700, 30.0, 36.0),
        (BrainTrainType.button(), BrainTrainFonts.ui, FontWeight.w700, 16.0, 18.0),
        (BrainTrainType.scoreValue(), BrainTrainFonts.ui, FontWeight.w800, 22.0, 28.0),
        (BrainTrainType.combo(), BrainTrainFonts.ui, FontWeight.w800, 26.0, 34.0),
        (BrainTrainType.hudLabel(), BrainTrainFonts.ui, FontWeight.w600, 10.0, 13.0),
        (BrainTrainType.body(), BrainTrainFonts.ui, FontWeight.w400, 13.0, 16.0),
      ]) {
        expect(style.fontFamily, family);
        expect(style.fontWeight, weight);
        expect(style.fontSize, inInclusiveRange(min, max));
      }
      expect(BrainTrainType.scoreValue().fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(BrainTrainType.combo().fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(kDisplayFont, BrainTrainFonts.display);
      expect(kDisplayFontFallback, contains('serif'));
    });

    test('the OFL licenses of the bundled fonts are in the license registry', () async {
      registerFontLicenses();
      final packages = <String>{};
      await for (final license in LicenseRegistry.licenses) {
        if (license.packages.any((p) => p.endsWith(' font'))) {
          packages.addAll(license.packages);
          expect(license.paragraphs.map((p) => p.text).join(' '), contains('SIL Open Font License'));
        }
      }
      expect(packages, containsAll(['Playfair Display font', 'Manrope font']));
    });

    test('text stays readable in both looks (WCAG contrast)', () {
      for (final palette in [BrainTrainPalette.day, BrainTrainPalette.night]) {
        final look = palette.isNight ? 'night' : 'day';
        // Panels over the brightest felt they sit on.
        final panel = _over(palette.panelFill.first, palette.feltCenter);
        expect(_contrast(palette.text, panel), greaterThanOrEqualTo(4.5), reason: '$look ivory on a panel');
        expect(_contrast(palette.hudLabel.withValues(alpha: 1), panel), greaterThanOrEqualTo(4.5), reason: look);
        expect(_contrast(palette.accent, panel), greaterThanOrEqualTo(4.5), reason: '$look gold on a panel');
        for (final gold in palette.primaryButtonFill) {
          expect(_contrast(palette.primaryButtonText, gold), greaterThanOrEqualTo(4.5), reason: '$look button label');
        }
        expect(_contrast(palette.textOnGold, palette.accent), greaterThanOrEqualTo(4.5), reason: look);
        // Ivory on the plain felt and background (text with a shadow).
        expect(_contrast(palette.text, palette.feltCenter), greaterThanOrEqualTo(4.5), reason: look);
        expect(_contrast(palette.text, palette.background.first), greaterThanOrEqualTo(4.5), reason: look);
      }
      for (final lobby in [LobbyTheme.day, LobbyTheme.night]) {
        final panel = _over(lobby.panelFill, lobby.baseFallback.last);
        expect(_contrast(lobby.panelText, panel), greaterThanOrEqualTo(4.5));
        expect(_contrast(lobby.panelAccent, panel), greaterThanOrEqualTo(4.5));
        expect(_contrast(lobby.primaryGlassText, lobby.primaryFill[1]), greaterThanOrEqualTo(4.5));
      }
    });
  });
}

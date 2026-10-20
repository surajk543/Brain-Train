// One look, Night (owner, 2026-10-20: Day and System were removed): the app
// ignores the phone's brightness and any stored 1.1.0 appearance, and the
// design tokens of that look.
import 'dart:io';
import 'dart:math' as math;

import 'package:brain_train/app/app.dart';
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/brand.dart';
import 'package:brain_train/app/theme.dart';
import 'package:brain_train/app/typography.dart';
import 'package:brain_train/data/age_group.dart';
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

  group('the app', () {
    late AppServices services;

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.runAsync(() async => services = await testServices(ageGroup: AgeGroup.thirteenPlus));
      await tester.pumpWidget(BrainTrainApp(servicesFactory: () async => services, showIntro: false));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    void expectNight(WidgetTester tester, {String? reason}) {
      final context = tester.element(find.byType(HomeScreen));
      expect(Theme.of(context).brightness, Brightness.dark, reason: reason);
      expect(BrainTrainPalette.of(context), same(BrainTrainPalette.night), reason: reason);
      expect(LobbyTheme.of(context), same(LobbyTheme.night), reason: reason);
      expect(BrainTrainTypography.of(context), same(BrainTrainTypography.night), reason: reason);
    }

    tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue());

    testWidgets('is Night on a light and on a dark phone, and stays Night when the phone switches', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await pumpApp(tester);
        expectNight(tester, reason: '$brightness phone');
        tester.platformDispatcher.platformBrightnessTestValue =
            brightness == Brightness.light ? Brightness.dark : Brightness.light;
        await tester.pump(const Duration(milliseconds: 400));
        expectNight(tester, reason: 'after switching from a $brightness phone');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a Day or System appearance stored by 1.1.0 is ignored', (tester) async {
      for (final stored in ['day', 'system']) {
        SharedPreferences.setMockInitialValues({'settings.appearance': stored});
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
        await pumpApp(tester);
        expectNight(tester, reason: 'stored $stored');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('design tokens', () {
    test('the theme carries the Night palette, lobby and typography', () {
      final theme = buildBrainTrainTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.extension<BrainTrainPalette>(), same(BrainTrainPalette.night));
      expect(theme.extension<LobbyTheme>(), same(LobbyTheme.night));
      expect(theme.extension<BrainTrainTypography>(), same(BrainTrainTypography.night));
      expect(theme.textTheme.bodyMedium!.fontFamily, BrainTrainFonts.ui);
      expect(theme.textTheme.headlineMedium!.fontFamily, BrainTrainFonts.display);
      expect(theme.scaffoldBackgroundColor, BrainTrainPalette.night.feltDark);
      expect(BrainTrainPalette.night.feltEdge, kFeltEdge);
    });

    test('the Night art is bundled and the Day art is not', () {
      const lobby = LobbyTheme.night;
      expect(lobby.baseAsset, 'assets/lobby/night_base.webp');
      for (final asset in [lobby.baseAsset, lobby.heroLedgeAsset, for (final d in lobby.decor) d.asset]) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      const foliage = FeltFoliage.night;
      for (final asset in [foliage.right, foliage.topLeft, foliage.bottomLeft, foliage.bottomRight]) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
        expect(pubspec, contains('- ${asset.substring(0, asset.lastIndexOf('/') + 1)}\n'), reason: asset);
      }
      expect(BrainTrainPalette.night.feltFoliage.right, 'assets/decor/foliage_right.webp');
      expect(pubspec, isNot(contains('/day/')));
      expect(Directory('assets/lobby/day').existsSync(), isFalse);
      expect(Directory('assets/decor/day').existsSync(), isFalse);
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

    test('text stays readable (WCAG contrast)', () {
      const palette = BrainTrainPalette.night;
      // Panels over the brightest felt they sit on.
      final panel = _over(palette.panelFill.first, palette.feltCenter);
      expect(_contrast(palette.text, panel), greaterThanOrEqualTo(4.5), reason: 'ivory on a panel');
      expect(_contrast(palette.hudLabel.withValues(alpha: 1), panel), greaterThanOrEqualTo(4.5));
      expect(_contrast(palette.accent, panel), greaterThanOrEqualTo(4.5), reason: 'gold on a panel');
      for (final gold in palette.primaryButtonFill) {
        expect(_contrast(palette.primaryButtonText, gold), greaterThanOrEqualTo(4.5), reason: 'button label');
      }
      expect(_contrast(palette.textOnGold, palette.accent), greaterThanOrEqualTo(4.5));
      // Ivory on the plain felt and background (text with a shadow).
      expect(_contrast(palette.text, palette.feltCenter), greaterThanOrEqualTo(4.5));
      expect(_contrast(palette.text, palette.background.first), greaterThanOrEqualTo(4.5));
      const lobby = LobbyTheme.night;
      final lobbyPanel = _over(lobby.panelFill, lobby.baseFallback.last);
      expect(_contrast(lobby.panelText, lobbyPanel), greaterThanOrEqualTo(4.5));
      expect(_contrast(lobby.panelAccent, lobbyPanel), greaterThanOrEqualTo(4.5));
      expect(_contrast(lobby.primaryGlassText, lobby.primaryFill[1]), greaterThanOrEqualTo(4.5));
    });
  });
}

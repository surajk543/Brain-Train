import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The two bundled font families (redesign 1.1.0). Both are the official
/// variable fonts from github.com/google/fonts (`ofl/playfairdisplay`,
/// `ofl/manrope`), unmodified (only renamed), under the SIL Open Font License
/// 1.1; the license text sits next to each file in `assets/fonts/` and is in
/// the app's license registry ([registerFontLicenses]).
///
/// Variable fonts need nothing special: Flutter sets the `wght` axis from
/// [TextStyle.fontWeight] (checked on Flutter 3.44), so `FontWeight.w800`
/// draws real ExtraBold. Do not add `fontVariations` to these styles: a
/// later `copyWith(fontWeight: ...)` would no longer change the weight.
abstract final class BrainTrainFonts {
  /// Playfair Display (wght 400-900, roman only): the title, level
  /// names and headings.
  static const String display = 'Playfair Display';

  /// Manrope (wght 200-800): buttons, HUD, numbers and body text.
  static const String ui = 'Manrope';

  /// Used only if a glyph is missing from the bundled font (or the font
  /// failed to load): the platform serif / sans.
  static const List<String> displayFallback = ['Georgia', 'Times New Roman', 'Noto Serif', 'serif'];
  static const List<String> uiFallback = ['Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'];

  /// OFL texts bundled with the fonts: (license registry package name, asset).
  static const List<(String, String)> licenses = [
    ('Playfair Display font', 'assets/fonts/playfair_display/OFL.txt'),
    ('Manrope font', 'assets/fonts/manrope/OFL.txt'),
  ];
}

/// Adds the fonts' OFL texts to Flutter's [LicenseRegistry] (read lazily,
/// only when something lists the licenses). Called once from `main`.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, asset) in BrainTrainFonts.licenses) {
      yield LicenseEntryWithLineBreaks([package], await rootBundle.loadString(asset));
    }
  });
}

/// The type scale of the reference design board: Playfair Display for the
/// title, level names and headings; Manrope for buttons, the HUD, numbers and
/// body text.
///
/// Sizes are logical pixels before text scaling. These are plain
/// [TextStyle]s: a [Text] scales them with the platform's text size, so
/// layouts must leave room to grow (wrap, scroll or FittedBox). Chrome with a
/// fixed height (HUD, tray, pills) may cap the scale with [chromeScaler];
/// never turn scaling off for readable text.
///
/// Each builder takes a size within its documented range and an optional
/// colour (null inherits from the surrounding [DefaultTextStyle]). For the
/// current theme's colours use [BrainTrainTypography.of].
abstract final class BrainTrainType {
  /// Display / app title: Playfair Display Bold, 36-44.
  static const double titleSize = 40;

  /// Level name: Playfair Display SemiBold, 22-28.
  static const double levelNameSize = 24;

  /// Screen and card headings: Playfair Display Bold, 30-36.
  static const double headingSize = 32;

  /// Button labels: Manrope Bold, 16-18.
  static const double buttonSize = 17;

  /// Score and other HUD values: Manrope ExtraBold, 22-28, tabular figures.
  static const double scoreSize = 24;

  /// Combo multiplier ("×3"): Manrope ExtraBold, 26-34, tabular figures.
  static const double comboSize = 30;

  /// HUD labels ("SCORE", "TIME"): Manrope SemiBold, 10-13, letter-spaced caps.
  static const double hudLabelSize = 11.5;

  /// Body text: Manrope Regular, 13-16.
  static const double bodySize = 15;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures(), FontFeature.liningFigures()];

  static TextStyle _display(double size, FontWeight weight, Color? color, {double height = 1.15, double spacing = 0}) =>
      TextStyle(
        fontFamily: BrainTrainFonts.display,
        fontFamilyFallback: BrainTrainFonts.displayFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
        fontFeatures: _tabular,
      );

  static TextStyle _ui(
    double size,
    FontWeight weight,
    Color? color, {
    double height = 1.25,
    double spacing = 0,
    bool tabular = false,
  }) => TextStyle(
    fontFamily: BrainTrainFonts.ui,
    fontFamilyFallback: BrainTrainFonts.uiFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: spacing,
    fontFeatures: tabular ? _tabular : null,
  );

  /// The game's title and big display lines.
  static TextStyle title({double size = titleSize, Color? color}) =>
      _display(size, FontWeight.w700, color, height: 1.1, spacing: size * 0.005);

  /// A level's name (lobby, Completed Levels, HUD, result cards).
  static TextStyle levelName({double size = levelNameSize, Color? color}) =>
      _display(size, FontWeight.w600, color, height: 1.15);

  /// Screen titles and card headings ("Settings", "Level complete!").
  static TextStyle heading({double size = headingSize, Color? color}) =>
      _display(size, FontWeight.w700, color, height: 1.12);

  /// Button labels.
  static TextStyle button({double size = buttonSize, Color? color}) =>
      _ui(size, FontWeight.w700, color, height: 1.2, spacing: 0.2);

  /// Score, time and other counters: figures keep one width, so a changing
  /// value never shifts the layout.
  static TextStyle scoreValue({double size = scoreSize, Color? color}) =>
      _ui(size, FontWeight.w800, color, height: 1.1, tabular: true);

  /// The combo multiplier.
  static TextStyle combo({double size = comboSize, Color? color}) =>
      _ui(size, FontWeight.w800, color, height: 1, spacing: 0.5, tabular: true);

  /// Small caps labels over HUD values. Pass upper-case text (a style cannot
  /// change case); the letter spacing grows with the size.
  static TextStyle hudLabel({double size = hudLabelSize, Color? color}) =>
      _ui(size, FontWeight.w600, color, height: 1.2, spacing: size * 0.14);

  /// Running text: descriptions, notices, list details.
  static TextStyle body({double size = bodySize, Color? color, FontWeight weight = FontWeight.w400}) =>
      _ui(size, weight, color, height: 1.4, spacing: 0.1);

  /// The platform text scale, capped at [max], for text in fixed-size chrome.
  static TextScaler chromeScaler(BuildContext context, {double max = 1.3}) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: max);
}

/// [BrainTrainType]'s styles in the theme's colours.
/// Read with `BrainTrainTypography.of(context)`, then `copyWith` for a
/// different size or colour:
///
/// ```dart
/// final type = BrainTrainTypography.of(context);
/// Text('SCORE', style: type.hudLabel);
/// Text(formatScore(score), style: type.scoreValue);
/// Text(entry.title, style: type.levelName.copyWith(fontSize: 26));
/// ```
@immutable
class BrainTrainTypography extends ThemeExtension<BrainTrainTypography> {
  const BrainTrainTypography({
    required this.title,
    required this.levelName,
    required this.heading,
    required this.button,
    required this.scoreValue,
    required this.combo,
    required this.hudLabel,
    required this.body,
    required this.bodyMuted,
  });

  /// The styles coloured for [palette]: ivory text, gold combo, muted HUD
  /// labels.
  factory BrainTrainTypography.forPalette(BrainTrainPalette palette) => BrainTrainTypography(
    title: BrainTrainType.title(color: palette.text),
    levelName: BrainTrainType.levelName(color: palette.text),
    heading: BrainTrainType.heading(color: palette.text),
    button: BrainTrainType.button(color: palette.secondaryButtonText),
    scoreValue: BrainTrainType.scoreValue(color: palette.hudValue),
    combo: BrainTrainType.combo(color: palette.accentLight),
    hudLabel: BrainTrainType.hudLabel(color: palette.hudLabel),
    body: BrainTrainType.body(color: palette.text),
    bodyMuted: BrainTrainType.body(color: palette.textMuted),
  );

  static final BrainTrainTypography night = BrainTrainTypography.forPalette(BrainTrainPalette.night);

  final TextStyle title;
  final TextStyle levelName;
  final TextStyle heading;
  final TextStyle button;
  final TextStyle scoreValue;
  final TextStyle combo;
  final TextStyle hudLabel;
  final TextStyle body;
  final TextStyle bodyMuted;

  static BrainTrainTypography of(BuildContext context) => Theme.of(context).extension<BrainTrainTypography>() ?? night;

  @override
  BrainTrainTypography copyWith() => this;

  @override
  BrainTrainTypography lerp(BrainTrainTypography? other, double t) => t < 0.5 || other == null ? this : other;
}

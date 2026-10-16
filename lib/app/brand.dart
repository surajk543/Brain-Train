import 'package:flutter/painting.dart';

import 'theme.dart';

/// Brain Train brand constants shared by the lobby and gameplay chrome.

/// Display serif. Uses the platform serif (Noto Serif on Android,
/// Georgia/Times on iOS) so no font file has to ship; to use a bundled OFL
/// font (e.g. Playfair Display), add it under pubspec `fonts:` and change
/// these two constants.
const String kDisplayFont = 'serif';
const List<String> kDisplayFontFallback = ['Georgia', 'Times New Roman', 'Noto Serif'];

abstract final class BrandGold {
  static const Color light = Color(0xFFF3DC98);
  static const Color base = Color(0xFFD8B25E);
  static const Color deep = Color(0xFF8E6C2A);
  static const Color warm = Color(0xFFF2C96B);
}

/// Serif display text with tabular, lining figures (counters never jump).
TextStyle displayText(
  double size, {
  Color color = BrainTrainColors.ivory,
  FontWeight weight = FontWeight.w600,
  double spacing = 0,
}) => TextStyle(
  fontFamily: kDisplayFont,
  fontFamilyFallback: kDisplayFontFallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing,
  height: 1.1,
  fontFeatures: const [FontFeature.tabularFigures(), FontFeature.liningFigures()],
);

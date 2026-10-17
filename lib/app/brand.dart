import 'package:flutter/painting.dart';

import 'theme.dart';
import 'typography.dart';

/// Brain Train brand constants shared by the lobby and gameplay chrome.

/// Display serif: Playfair Display, bundled (assets/fonts/, see
/// typography.dart), with the platform serifs (Georgia/Times on iOS, Noto
/// Serif on Android) as fallbacks for missing glyphs. The redesign's type
/// scale (Playfair for titles and headings, Manrope for buttons, HUD,
/// numbers and body) is [BrainTrainType] / [BrainTrainTypography].
const String kDisplayFont = BrainTrainFonts.display;
const List<String> kDisplayFontFallback = BrainTrainFonts.displayFallback;

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

import 'package:flutter/painting.dart';

import '../../game_engine/campaign/campaign_config.dart';

/// Label and badge colour of a level's difficulty tier.
///
/// Tiers are data (`difficulty` in the manifest): numeric tiers read `7/10`
/// on a green-to-red scale, and an unknown id still gets a readable label
/// (`veryHard` -> "Very Hard") and a stable colour.
class DifficultyStyle {
  const DifficultyStyle(this.label, this.color);

  factory DifficultyStyle.of(String id) {
    final number = numericDifficulty(id);
    return DifficultyStyle(
      difficultyLabel(id),
      number != null ? _scale[number - 1] : _colors[id] ?? _fallback(id),
    );
  }

  final String label;

  /// Badge tint on the dark-green glass: light enough to read as text.
  final Color color;

  static const Map<String, Color> _colors = {
    'easy': Color(0xFF8EDCA6), // fresh leaf
    'medium': Color(0xFF7FD0E0), // pond
    'hard': Color(0xFFF2C46A), // gold
    'veryHard': Color(0xFFF08A78), // ember
  };

  /// Difficulty 1..10: fresh leaf through gold to ember.
  static const List<Color> _scale = [
    Color(0xFF8EDCA6),
    Color(0xFFA6E09C),
    Color(0xFFBFE394),
    Color(0xFFD8E28C),
    Color(0xFFEDD883),
    Color(0xFFF2C46A),
    Color(0xFFF4AF6C),
    Color(0xFFF39C70),
    Color(0xFFF08A78),
    Color(0xFFEC7488),
  ];

  static Color _fallback(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0xFFFFFF;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.6, 0.72).toColor();
  }
}

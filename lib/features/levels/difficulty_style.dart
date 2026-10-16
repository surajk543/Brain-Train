import 'package:flutter/painting.dart';

import '../../game_engine/campaign/campaign_config.dart';

/// Label and badge colour of a level's difficulty tier.
///
/// Tiers are data (`difficulty` in the manifest), so an unknown id still
/// gets a readable label (`veryHard` -> "Very Hard") and a stable colour.
class DifficultyStyle {
  const DifficultyStyle(this.label, this.color);

  factory DifficultyStyle.of(String id) => DifficultyStyle(difficultyLabel(id), _colors[id] ?? _fallback(id));

  final String label;

  /// Badge tint on the dark-green glass: light enough to read as text.
  final Color color;

  static const Map<String, Color> _colors = {
    'easy': Color(0xFF8EDCA6), // fresh leaf
    'medium': Color(0xFF7FD0E0), // pond
    'hard': Color(0xFFF2C46A), // gold
    'veryHard': Color(0xFFF08A78), // ember
  };

  static Color _fallback(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0xFFFFFF;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.6, 0.72).toColor();
  }
}

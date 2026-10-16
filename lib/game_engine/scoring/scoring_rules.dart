/// How pairs score: base points, the combo window, the multiplier cap, the
/// speed tiers and the blocked-tap penalty. Pure Dart (tools may import it).
class ScoringRules {
  const ScoringRules({
    this.basePoints = 100,
    this.comboWindow = const Duration(seconds: 4),
    this.maxMultiplier = 5,
    this.speedTiers = const [
      (under: Duration(seconds: 1), bonus: 50),
      (under: Duration(seconds: 2), bonus: 25),
    ],
    this.windowBonus = 10,
    this.blockedTapPenalty = 1,
  });

  final int basePoints;

  /// A match at most this long after the previous one continues the combo
  /// (the boundary itself included).
  final Duration comboWindow;

  final int maxMultiplier;

  /// Bonus for a gap shorter than `under`, checked in order.
  final List<({Duration under, int bonus})> speedTiers;

  /// Bonus for a gap past every tier but still inside [comboWindow].
  final int windowBonus;

  /// Points a blocked-tile tap costs (the score never goes below 0).
  final int blockedTapPenalty;

  /// Speed bonus for a match [gap] after the previous one (0 past the window).
  int speedBonusFor(Duration gap) {
    if (gap.isNegative || gap > comboWindow) return 0;
    for (final tier in speedTiers) {
      if (gap < tier.under) return tier.bonus;
    }
    return windowBonus;
  }
}

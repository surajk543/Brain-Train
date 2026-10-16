import 'campaign_config.dart';
import 'seeded_random.dart';

/// The difficulty tier of each level, in level order.
///
/// Every tier gets exactly its `count` levels, shuffled with the campaign
/// seed. Level 1 is [CampaignConfig.firstTier] and no tier appears more
/// than [CampaignConfig.maxTierRun] times in a row. Each pick is weighted
/// by how many levels a tier still needs, so the tiers stay mixed along the
/// whole campaign; a dead end (only a tier that would break the run rule is
/// left) restarts with the next random stream.
List<String> scheduleTiers(CampaignConfig config) {
  final random = SeededRandom.of(['tiers', config.seed]);
  final total = config.levelCount;
  for (var attempt = 0; attempt < 10000; attempt++) {
    final remaining = {for (final t in config.tiers) t.id: t.count};
    final order = <String>[config.firstTier];
    remaining[config.firstTier] = remaining[config.firstTier]! - 1;
    if (remaining[config.firstTier]! < 0) throw StateError('firstTier ${config.firstTier} has count 0');
    var dead = false;
    while (order.length < total) {
      final options = [
        for (final t in config.tiers)
          if (remaining[t.id]! > 0 && !_breaksRun(order, t.id, config.maxTierRun)) t.id,
      ];
      if (options.isEmpty) {
        dead = true;
        break;
      }
      var roll = random.nextInt(options.fold(0, (sum, id) => sum + remaining[id]!));
      var chosen = options.last;
      for (final id in options) {
        roll -= remaining[id]!;
        if (roll < 0) {
          chosen = id;
          break;
        }
      }
      order.add(chosen);
      remaining[chosen] = remaining[chosen]! - 1;
    }
    if (!dead) return order;
  }
  throw StateError('no tier order satisfies maxTierRun ${config.maxTierRun}');
}

bool _breaksRun(List<String> order, String id, int maxRun) {
  if (order.length < maxRun) return false;
  for (var i = order.length - maxRun; i < order.length; i++) {
    if (order[i] != id) return false;
  }
  return true;
}

/// Longest run of one tier in [order].
int longestRun(List<String> order) {
  var best = 0, run = 0;
  for (var i = 0; i < order.length; i++) {
    run = i > 0 && order[i] == order[i - 1] ? run + 1 : 1;
    if (run > best) best = run;
  }
  return best;
}

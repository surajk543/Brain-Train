import 'campaign_config.dart';
import 'seeded_random.dart';

/// The difficulty tier of each level, in level order.
///
/// Batch by batch ([CampaignConfig.batches]): every tier gets exactly its
/// count in the batch, shuffled with the campaign seed (and the batch
/// number after the first). Level 1 is [CampaignConfig.firstTier] and no
/// tier appears more than [CampaignConfig.maxTierRun] times in a row, also
/// across a batch boundary. Each pick is weighted by how many levels a tier
/// still needs, so the tiers stay mixed along the whole batch; a dead end
/// (only a tier that would break the run rule is left) restarts the batch
/// with the next random stream. A batch depends only on the ones before it,
/// so appending one never changes an earlier level.
List<String> scheduleTiers(CampaignConfig config) {
  final order = <String>[];
  for (var batch = 0; batch < config.batches.length; batch++) {
    order.addAll(_scheduleBatch(config, batch, order));
  }
  return order;
}

List<String> _scheduleBatch(CampaignConfig config, int batch, List<String> before) {
  final random = SeededRandom.of(batch == 0 ? ['tiers', config.seed] : ['tiers', config.seed, batch]);
  final total = config.batches[batch].values.fold(0, (sum, n) => sum + n);
  for (var attempt = 0; attempt < 10000; attempt++) {
    final remaining = {for (final t in config.tiers) t.id: config.countIn(batch, t.id)};
    final order = [...before];
    if (batch == 0) {
      order.add(config.firstTier);
      remaining[config.firstTier] = remaining[config.firstTier]! - 1;
      if (remaining[config.firstTier]! < 0) throw StateError('firstTier ${config.firstTier} has count 0');
    }
    var dead = false;
    while (order.length < before.length + total) {
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
    if (!dead) return order.sublist(before.length);
  }
  throw StateError('batch ${batch + 1}: no tier order satisfies maxTierRun ${config.maxTierRun}');
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

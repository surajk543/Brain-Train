import 'dart:typed_data';

import 'campaign_config.dart';
import 'seeded_random.dart';

/// Restarts allowed per batch before [scheduleTiers] gives up.
///
/// A batch whose counts leave almost no valid order needs many: batch 2 of
/// the catalog (25 levels of difficulty 9, 50 of difficulty 10, maxTierRun 2)
/// only fits as near-forced "10 10 9" repeats and is placed at restart
/// 1,263,282 (about 2 s). Raising the limit never changes a batch that was
/// already placed, because every batch stops at its first success.
const int maxScheduleAttempts = 2000000;

/// The difficulty tier of each level, in level order.
///
/// Batch by batch ([CampaignConfig.batches]): every tier gets exactly its
/// count in the batch, shuffled with the campaign seed (and the batch
/// number after the first). Level 1 is [CampaignConfig.firstTier] and no
/// tier appears more than [CampaignConfig.maxTierRun] times in a row, also
/// across a batch boundary. Each pick is weighted by how many levels a tier
/// still needs, so the tiers stay mixed along the whole batch; a dead end
/// (only a tier that would break the run rule is left) restarts the batch
/// with the next random stream, at most [maxAttempts] times. A batch depends
/// only on the ones before it, so appending one never changes an earlier
/// level.
List<String> scheduleTiers(CampaignConfig config, {int maxAttempts = maxScheduleAttempts}) {
  final order = <String>[];
  for (var batch = 0; batch < config.batches.length; batch++) {
    order.addAll(_scheduleBatch(config, batch, order, maxAttempts));
  }
  return order;
}

// The draw is pinned: published levels depend on it. Per pick, the options
// are the tiers (in catalog order) that still need levels and would not
// break the run; one nextInt over their summed remaining counts picks one,
// weighted by those counts. This loop is the plain list version
// (`options = [for (t in tiers) if (remaining > 0 && !breaksRun) t]`)
// written with arrays and a running run length, so a batch that needs
// millions of restarts stays fast; it makes the same random calls.
List<String> _scheduleBatch(CampaignConfig config, int batch, List<String> before, int maxAttempts) {
  final random = SeededRandom.of(batch == 0 ? ['tiers', config.seed] : ['tiers', config.seed, batch]);
  final total = config.batches[batch].values.fold(0, (sum, n) => sum + n);
  final ids = [
    for (final t in config.tiers)
      if (config.countIn(batch, t.id) > 0) t.id,
  ];
  final counts = Int32List.fromList([for (final id in ids) config.countIn(batch, id)]);
  final maxRun = config.maxTierRun;

  // The run the batch starts after: the tier ending [before] (-1 if it is not
  // in this batch, so it can never be extended) and how many times in a row.
  var startRunTier = -1, startRunLength = 0;
  if (before.isNotEmpty) {
    startRunTier = ids.indexOf(before.last);
    for (var i = before.length - 1; i >= 0 && before[i] == before.last; i--) {
      startRunLength++;
    }
  }
  final first = batch == 0 ? ids.indexOf(config.firstTier) : -1;
  if (batch == 0 && first < 0) throw StateError('firstTier ${config.firstTier} has count 0');

  final remaining = Int32List(ids.length);
  final picks = Int32List(total);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    remaining.setAll(0, counts);
    var length = 0, runTier = startRunTier, runLength = startRunLength;
    if (first >= 0) {
      picks[length++] = first;
      remaining[first]--;
      runTier = first;
      runLength = 1;
    }
    var dead = false;
    while (length < total) {
      var weight = 0;
      for (var k = 0; k < ids.length; k++) {
        if (remaining[k] > 0 && !(k == runTier && runLength >= maxRun)) weight += remaining[k];
      }
      if (weight == 0) {
        dead = true;
        break;
      }
      var roll = random.nextInt(weight);
      var chosen = -1;
      for (var k = 0; k < ids.length; k++) {
        if (remaining[k] > 0 && !(k == runTier && runLength >= maxRun)) {
          chosen = k;
          roll -= remaining[k];
          if (roll < 0) break;
        }
      }
      picks[length++] = chosen;
      remaining[chosen]--;
      if (chosen == runTier) {
        runLength++;
      } else {
        runTier = chosen;
        runLength = 1;
      }
    }
    if (!dead) return [for (var i = 0; i < total; i++) ids[picks[i]]];
  }
  throw StateError('batch ${batch + 1}: no tier order satisfies maxTierRun ${config.maxTierRun}');
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

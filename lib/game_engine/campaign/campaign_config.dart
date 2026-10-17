import '../models/json_reader.dart';
import '../models/level_rules.dart';
import 'seeded_random.dart';

/// Highest difficulty of the numeric scale: tier ids `1`..`10`.
const int kMaxDifficulty = 10;

/// The numeric difficulty of a tier id (`1`..[kMaxDifficulty]), or null for
/// a named tier (`easy`, `veryHard`, ...).
int? numericDifficulty(String id) {
  final value = int.tryParse(id);
  return value != null && value >= 1 && value <= kMaxDifficulty && '$value' == id ? value : null;
}

/// Display label for a difficulty id: numeric tiers as `7/10`, named ones
/// split at their capitals (`veryHard` -> `Very Hard`), so a new tier in
/// the content needs no app change.
String difficultyLabel(String id) {
  final number = numericDifficulty(id);
  if (number != null) return '$number/$kMaxDifficulty';
  final words = id
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp('[_-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'));
  return [
    for (final word in words)
      if (word.isNotEmpty) word[0].toUpperCase() + word.substring(1).toLowerCase(),
  ].join(' ');
}

/// One difficulty tier of the campaign: how many levels it gets and what
/// its boards look like. All of it comes from `content-src/catalog.json`.
class TierSpec {
  const TierSpec({
    required this.id,
    required this.count,
    required this.minTiles,
    required this.maxTiles,
    required this.minLayers,
    required this.maxLayers,
    this.trayCapacity = 4,
    int? maxTrayCapacity,
    this.pairsPerStaticSymbol = 1,
    this.pairsPerAnimatedSymbol = 1,
    this.stalePairing = 0,
    this.minFreeRatio = 0,
    this.maxFreeRatio = 1,
    this.minWinRate = 0,
    this.maxWinRate = 1,
    this.families = const [],
  }) : maxTrayCapacity = maxTrayCapacity ?? trayCapacity;

  factory TierSpec.fromJson(JsonReader json) {
    List<int> range(String key) {
      final values = [for (final v in json.numberList(key)) v.toInt()];
      if (values.length != 2 || values[0] > values[1]) {
        throw JsonFormatException('${json.path}.$key', 'expected [min, max]');
      }
      return values;
    }

    List<double> ratio(String key, double lo, double hi) {
      if (!json.has(key)) return [lo, hi];
      final values = json.numberList(key);
      if (values.length != 2 || values[0] > values[1]) {
        throw JsonFormatException('${json.path}.$key', 'expected [min, max]');
      }
      return values;
    }

    // `trayCapacity`: one size, or [min, max] picked per level.
    List<int> tray() {
      if (!json.has('trayCapacity')) return [4, 4];
      try {
        final size = json.integer('trayCapacity');
        return [size, size];
      } on JsonFormatException {
        return range('trayCapacity');
      }
    }

    final tiles = range('tiles'), layers = range('layers'), trays = tray();
    final free = ratio('freeRatio', 0, 1), win = ratio('winRate', 0, 1);
    return TierSpec(
      id: json.string('id'),
      count: json.optInt('count') ?? 0,
      minTiles: tiles[0],
      maxTiles: tiles[1],
      minLayers: layers[0],
      maxLayers: layers[1],
      trayCapacity: trays[0],
      maxTrayCapacity: trays[1],
      pairsPerStaticSymbol: json.numberOr('pairsPerStaticSymbol', 1),
      pairsPerAnimatedSymbol: json.numberOr('pairsPerAnimatedSymbol', 1),
      stalePairing: json.numberOr('stalePairing', 0),
      minFreeRatio: free[0],
      maxFreeRatio: free[1],
      minWinRate: win[0],
      maxWinRate: win[1],
      families: json.has('families') ? json.stringList('families') : const [],
    );
  }

  /// Stored in levels and the manifest as `difficulty`, e.g. `7` or
  /// `veryHard`.
  final String id;

  /// Levels of this tier when the campaign has no `batches`.
  final int count;
  final int minTiles;
  final int maxTiles;

  /// Number of layers (1 = flat).
  final int minLayers;
  final int maxLayers;

  /// Tray slots for this tier's levels (`rules.trayCapacity`): each level
  /// takes a seeded pick from [trayCapacity]..[maxTrayCapacity].
  final int trayCapacity;
  final int maxTrayCapacity;

  /// Average pairs per distinct static / animated symbol: higher repeats
  /// symbols more (more ways to match, easier).
  final double pairsPerStaticSymbol;
  final double pairsPerAnimatedSymbol;

  /// Share of generated pairs that join a newly exposed tile with the tile
  /// that has been free the longest (a decoy that waits in the tray).
  final double stalePairing;

  /// Accepted share of tiles that are free at the start.
  final double minFreeRatio;
  final double maxFreeRatio;

  /// Accepted win rate of the simulated tray player.
  final double minWinRate;
  final double maxWinRate;

  /// Board shape families allowed for this tier (empty: all).
  final List<String> families;

  String get label => difficultyLabel(id);
}

/// Settings for the procedurally generated campaign (catalog `campaign`).
class CampaignConfig {
  CampaignConfig({
    required this.seed,
    required this.tiers,
    List<Map<String, int>>? batches,
    this.firstTier = 'easy',
    this.maxTierRun = 2,
    this.animatedShare = 0.3,
    this.maxDistinctAnimated = 12,
    this.maxPairsPerSymbol,
    this.simulationRuns = 200,
    this.minFaceWidth = 31,
    this.solverBudget = 500000,
    this.category = 'nature',
    List<String> titles = const [],
  }) : titles = List.unmodifiable(titles),
       batches = List.unmodifiable([
         for (final batch in batches ?? [{for (final t in tiers) t.id: t.count}])
           Map<String, int>.unmodifiable(batch),
       ]);

  factory CampaignConfig.fromJson(Object? decoded) {
    final json = JsonReader(decoded);
    final tiers = json.objectList('tiers').map(TierSpec.fromJson).toList();
    final config = CampaignConfig(
      seed: json.integer('seed'),
      tiers: tiers,
      batches: json.has('batches')
          ? [
              for (final batch in json.objectList('batches'))
                {for (final t in tiers) t.id: batch.optInt(t.id) ?? 0},
            ]
          : null,
      firstTier: json.optString('firstTier') ?? 'easy',
      maxTierRun: json.optInt('maxTierRun') ?? 2,
      animatedShare: json.numberOr('animatedShare', 0.3),
      maxDistinctAnimated: json.optInt('maxDistinctAnimated') ?? 12,
      maxPairsPerSymbol: json.optInt('maxPairsPerSymbol'),
      simulationRuns: json.optInt('simulationRuns') ?? 200,
      minFaceWidth: json.numberOr('minFaceWidth', 31),
      solverBudget: json.optInt('solverBudget') ?? 500000,
      category: json.optString('category') ?? 'nature',
      titles: json.has('titles') ? json.stringList('titles') : const [],
    );
    final problems = config.problems();
    if (problems.isNotEmpty) throw JsonFormatException(json.path, problems.join('; '));
    return config;
  }

  final int seed;

  /// Tiers in rising difficulty.
  final List<TierSpec> tiers;

  /// Levels per tier id, batch by batch. Each batch is shuffled on its own
  /// and follows the ones before it, so appending a batch never changes an
  /// earlier level. Without `batches` in the catalog: one batch of the
  /// tiers' `count`s.
  final List<Map<String, int>> batches;

  /// Tier of level 1.
  final String firstTier;

  /// No tier appears more than this many times in a row.
  final int maxTierRun;

  /// Animated pairs per level = floor(pairs * share), at least 1.
  final double animatedShare;

  /// Most distinct animated symbols on one level (each is rendered once per
  /// frame step into the board's `SymbolFrameAtlas`).
  final int maxDistinctAnimated;

  /// Most pairs of one symbol on a level (2 = at most 4 tiles); null: only
  /// the tiers' `pairsPer...Symbol` averages apply.
  final int? maxPairsPerSymbol;

  /// Simulated tray games per level for calibration.
  final int simulationRuns;

  /// Smallest tile face width (logical px) on a 360x640 phone.
  final double minFaceWidth;

  /// Solver nodes a generated board may need for its proof; boards that
  /// need more are replaced (the build re-proves with a larger budget).
  final int solverBudget;
  final String category;

  /// Titles of published levels, by level order (`titles[0]` is level 1),
  /// pinned so a change to how boards are built never renames a level. Later
  /// levels get generated titles that repeat none of these.
  final List<String> titles;

  int get levelCount => batches.fold(0, (sum, b) => sum + b.values.fold(0, (s, n) => s + n));

  /// Levels of [tierId] in batch [batch].
  int countIn(int batch, String tierId) => batches[batch][tierId] ?? 0;

  /// Tray slots of level [order] (1-based) of [tier]: a seeded pick from the
  /// tier's range, independent of the board's random stream.
  int trayCapacityFor(int order, TierSpec tier) => tier.trayCapacity == tier.maxTrayCapacity
      ? tier.trayCapacity
      : tier.trayCapacity + SeededRandom.of(['tray', seed, order]).nextInt(tier.maxTrayCapacity - tier.trayCapacity + 1);

  TierSpec tier(String id) => tiers.firstWhere((t) => t.id == id);

  List<String> problems() => [
    if (tiers.isEmpty) 'no tiers',
    if (tiers.map((t) => t.id).toSet().length != tiers.length) 'duplicate tier ids',
    if (!tiers.any((t) => t.id == firstTier)) 'firstTier $firstTier is not a tier',
    if (batches.isEmpty || levelCount < 1) 'no levels',
    if (titles.toSet().length != titles.length) 'duplicate pinned titles',
    for (var b = 0; b < batches.length; b++)
      for (final MapEntry(:key, :value) in batches[b].entries)
        if (value < 0) 'batch ${b + 1}: $key count must not be negative',
    if (batches.isNotEmpty && countIn(0, firstTier) < 1) 'firstTier $firstTier has no level in the first batch',
    if (maxTierRun < 1) 'maxTierRun must be at least 1',
    if (!(animatedShare >= 0 && animatedShare <= 0.3)) 'animatedShare must be within [0, 0.3]',
    if (maxDistinctAnimated < 1) 'maxDistinctAnimated must be at least 1',
    if (maxPairsPerSymbol != null && maxPairsPerSymbol! < 1) 'maxPairsPerSymbol must be at least 1',
    for (final t in tiers) ...[
      if (!RegExp(r'^[a-z][A-Za-z0-9]{0,31}$').hasMatch(t.id) && numericDifficulty(t.id) == null)
        'tier id ${t.id} must be camelCase letters or 1-$kMaxDifficulty',
      if (batches.every((batch) => (batch[t.id] ?? 0) < 1)) '${t.id}: count must be positive',
      if (t.minTiles < 2 || t.minTiles.isOdd || t.maxTiles.isOdd) '${t.id}: tile range must be even numbers',
      if (t.minLayers < 1) '${t.id}: layers start at 1',
      if (!kAllowedTrayCapacities.contains(t.trayCapacity) ||
          !kAllowedTrayCapacities.contains(t.maxTrayCapacity) ||
          t.trayCapacity > t.maxTrayCapacity)
        '${t.id}: trayCapacity must be within ${kAllowedTrayCapacities.join('/')}',
      if (t.pairsPerStaticSymbol < 1 || t.pairsPerAnimatedSymbol < 1) '${t.id}: pairs per symbol must be >= 1',
    ],
  ];
}

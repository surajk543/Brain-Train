import '../models/json_reader.dart';

/// Display label for a difficulty id: known tiers by name, anything else
/// split at its capitals (`veryHard` -> `Very Hard`), so a new tier in the
/// content needs no app change.
String difficultyLabel(String id) {
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
    this.pairsPerStaticSymbol = 1,
    this.pairsPerAnimatedSymbol = 1,
    this.stalePairing = 0,
    this.minFreeRatio = 0,
    this.maxFreeRatio = 1,
    this.minWinRate = 0,
    this.maxWinRate = 1,
    this.families = const [],
  });

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

    final tiles = range('tiles'), layers = range('layers');
    final free = ratio('freeRatio', 0, 1), win = ratio('winRate', 0, 1);
    return TierSpec(
      id: json.string('id'),
      count: json.integer('count'),
      minTiles: tiles[0],
      maxTiles: tiles[1],
      minLayers: layers[0],
      maxLayers: layers[1],
      trayCapacity: json.optInt('trayCapacity') ?? 4,
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

  /// Stored in levels and the manifest as `difficulty`, e.g. `veryHard`.
  final String id;
  final int count;
  final int minTiles;
  final int maxTiles;

  /// Number of layers (1 = flat).
  final int minLayers;
  final int maxLayers;

  /// Tray slots for this tier's levels (`rules.trayCapacity`).
  final int trayCapacity;

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
  const CampaignConfig({
    required this.seed,
    required this.tiers,
    this.firstTier = 'easy',
    this.maxTierRun = 2,
    this.animatedShare = 0.3,
    this.maxDistinctAnimated = 12,
    this.simulationRuns = 200,
    this.minFaceWidth = 31,
    this.solverBudget = 500000,
    this.category = 'nature',
  });

  factory CampaignConfig.fromJson(Object? decoded) {
    final json = JsonReader(decoded);
    final config = CampaignConfig(
      seed: json.integer('seed'),
      tiers: json.objectList('tiers').map(TierSpec.fromJson).toList(),
      firstTier: json.optString('firstTier') ?? 'easy',
      maxTierRun: json.optInt('maxTierRun') ?? 2,
      animatedShare: json.numberOr('animatedShare', 0.3),
      maxDistinctAnimated: json.optInt('maxDistinctAnimated') ?? 12,
      simulationRuns: json.optInt('simulationRuns') ?? 200,
      minFaceWidth: json.numberOr('minFaceWidth', 31),
      solverBudget: json.optInt('solverBudget') ?? 500000,
      category: json.optString('category') ?? 'nature',
    );
    final problems = config.problems();
    if (problems.isNotEmpty) throw JsonFormatException(json.path, problems.join('; '));
    return config;
  }

  final int seed;

  /// Tiers in rising difficulty.
  final List<TierSpec> tiers;

  /// Tier of level 1.
  final String firstTier;

  /// No tier appears more than this many times in a row.
  final int maxTierRun;

  /// Animated pairs per level = floor(pairs * share), at least 1.
  final double animatedShare;

  /// Most distinct animated symbols on one level (each is rendered once per
  /// frame step into the board's `SymbolFrameAtlas`).
  final int maxDistinctAnimated;

  /// Simulated tray games per level for calibration.
  final int simulationRuns;

  /// Smallest tile face width (logical px) on a 360x640 phone.
  final double minFaceWidth;

  /// Solver nodes a generated board may need for its proof; boards that
  /// need more are replaced (the build re-proves with a larger budget).
  final int solverBudget;
  final String category;

  int get levelCount => tiers.fold(0, (sum, t) => sum + t.count);

  TierSpec tier(String id) => tiers.firstWhere((t) => t.id == id);

  List<String> problems() => [
    if (tiers.isEmpty) 'no tiers',
    if (tiers.map((t) => t.id).toSet().length != tiers.length) 'duplicate tier ids',
    if (!tiers.any((t) => t.id == firstTier)) 'firstTier $firstTier is not a tier',
    if (maxTierRun < 1) 'maxTierRun must be at least 1',
    if (!(animatedShare >= 0 && animatedShare <= 0.3)) 'animatedShare must be within [0, 0.3]',
    if (maxDistinctAnimated < 1) 'maxDistinctAnimated must be at least 1',
    for (final t in tiers) ...[
      if (!RegExp(r'^[a-z][A-Za-z0-9]{0,31}$').hasMatch(t.id)) 'tier id ${t.id} must be camelCase letters',
      if (t.count < 1) '${t.id}: count must be positive',
      if (t.minTiles < 2 || t.minTiles.isOdd || t.maxTiles.isOdd) '${t.id}: tile range must be even numbers',
      if (t.minLayers < 1) '${t.id}: layers start at 1',
      if (t.trayCapacity < 2 || t.trayCapacity > 7) '${t.id}: trayCapacity must be 2-7',
      if (t.pairsPerStaticSymbol < 1 || t.pairsPerAnimatedSymbol < 1) '${t.id}: pairs per symbol must be >= 1',
    ],
  ];
}

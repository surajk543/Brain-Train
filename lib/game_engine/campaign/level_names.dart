import 'seeded_random.dart';

/// Nature words for level titles: a first word plus a noun that suits the
/// board's shape family ("Heron Bridge", "Mossy Pond").
const List<String> kTitleFirstWords = [
  'Mossy', 'Misty', 'Golden', 'Silver', 'Amber', 'Emerald', 'Jade', 'Cedar', 'Willow', 'Fern', //
  'Maple', 'Birch', 'Clover', 'Heather', 'Lotus', 'Pine', 'Juniper', 'Sage', 'Thistle', 'Aspen',
  'Hazel', 'Ivy', 'Laurel', 'Lily', 'Rowan', 'Briar', 'Orchid', 'Poppy', 'Saffron', 'Moonlit',
  'Starlit', 'Sunlit', 'Dewy', 'Hidden', 'Quiet', 'Whispering', 'Wild', 'Ancient', 'Autumn', 'Spring',
  'Summer', 'Winter', 'Dawn', 'Dusk', 'Twilight', 'Velvet', 'Copper', 'Coral', 'Lavender', 'River',
  'Forest', 'Mountain', 'Valley', 'Rain', 'Snowy', 'Firefly', 'Robin', 'Wren', 'Sparrow', 'Heron',
  'Fox', 'Otter', 'Owl', 'Deer', 'Bramble', 'Honey', 'Ember', 'Frost', 'Breezy', 'Bluebell',
  'Primrose', 'Marigold', 'Daisy', 'Acorn', 'Oak', 'Elder', 'Larch', 'Cypress', 'Linden', 'Magnolia',
];

const Map<String, List<String>> kTitleNouns = {
  'pyramid': ['Summit', 'Peak', 'Highlands', 'Mesa', 'Cairn', 'Hilltop', 'Ridge'],
  'terrace': ['Terrace', 'Steps', 'Paddies', 'Ledges', 'Tiers', 'Slopes', 'Uplands'],
  'diamond': ['Leaf', 'Seedpod', 'Dewdrop', 'Bud', 'Kernel', 'Sprout', 'Petal'],
  'cross': ['Crossroads', 'Junction', 'Fork', 'Trailhead', 'Waymark', 'Signpost'],
  'ring': ['Pond', 'Lagoon', 'Atoll', 'Crater', 'Basin', 'Tarn', 'Spring'],
  'fortress': ['Rampart', 'Crag', 'Outcrop', 'Bluff', 'Bastion', 'Tors'],
  'arch': ['Arch', 'Archway', 'Gorge', 'Gateway', 'Canyon', 'Grotto'],
  'bridge': ['Bridge', 'Ford', 'Causeway', 'Footbridge', 'Span', 'Crossing'],
  'hourglass': ['Narrows', 'Strait', 'Pass', 'Channel', 'Gap', 'Gully'],
  'heart': ['Heartwood', 'Rosebud', 'Lovebird', 'Heartleaf', 'Sweetbriar'],
  'flower': ['Blossom', 'Bloom', 'Petals', 'Garden', 'Posy', 'Bouquet'],
  'grove': ['Grove', 'Pines', 'Thicket', 'Copse', 'Timberland', 'Orchard'],
  'furrows': ['Furrows', 'Fields', 'Vineyard', 'Meadows', 'Pastures', 'Hedgerows'],
  'chevron': ['Flight', 'Wings', 'Migration', 'Flyway', 'Skein', 'Glide'],
  'isles': ['Isles', 'Shoals', 'Stepping Stones', 'Lily Pads', 'Islets', 'Reefs'],
  'oval': ['Clearing', 'Nest', 'Glade', 'Moon', 'Hollow', 'Dell'],
  'star': ['Starflower', 'Starfall', 'Aster', 'Star Moss', 'Comet', 'Lodestar'],
  'butterfly': ['Butterfly', 'Moth', 'Dragonfly', 'Monarch', 'Swallowtail', 'Mayfly'],
  'turtle': ['Turtle', 'Tortoise', 'Shell', 'Terrapin', 'Carapace'],
  'lattice': ['Lattice', 'Trellis', 'Arbor', 'Pergola', 'Weave', 'Bower'],
  'crown': ['Crown', 'Canopy', 'Treetops', 'Coronet', 'Spires'],
  'pillars': ['Pillars', 'Standing Stones', 'Columns', 'Totems', 'Monoliths', 'Menhirs'],
};

/// Nature palettes for a level's `backdrop.colors` (gameplay ambient light).
const List<List<String>> kBackdropPalettes = [
  ['#2E7D4F', '#7FBF6A', '#D9E8A6'], // forest
  ['#3F6B2A', '#9CC46B', '#E8E2A0'], // moss
  ['#1F7A8C', '#5FC4C9', '#CDEFE6'], // lagoon
  ['#5B3FA8', '#9B6BD6', '#E46FA8'], // dusk
  ['#A0522D', '#E39B4A', '#F4D58D'], // autumn
  ['#B04A7A', '#E58FB5', '#F7D6E0'], // blossom
  ['#2B4C7E', '#6F8FC9', '#D6E2F5'], // moonlight
  ['#3FA66B', '#B8E07A', '#F2E8B5'], // meadow
  ['#C2453A', '#F08A4B', '#F9D57A'], // sunset
  ['#6A4C93', '#A98FD6', '#E6DAF5'], // lavender
  ['#1E5631', '#4C9A2A', '#A4DE02'], // pine
  ['#E0605E', '#F2A07B', '#FFE3C2'], // coral
  ['#2F6F8F', '#8CC7E0', '#E7F6FB'], // glacier
  ['#7B4B8E', '#C38FC9', '#F0D9EF'], // heather
  ['#B8860B', '#E8B84A', '#FBEBB5'], // honey
  ['#2F7D5B', '#6FCF97', '#D2F5E3'], // fern
  ['#6B2D5C', '#B5579B', '#F1B7D8'], // plum
  ['#5C7D5A', '#A3C4A0', '#E4EEDC'], // sage
  ['#8C2F1C', '#D9603B', '#F6B26B'], // ember
  ['#234E52', '#3E8E7E', '#A8DCC8'], // twilight teal
];

/// Picks unique titles and palettes level by level. A first word is not
/// reused within six levels, a noun within three, a palette within two.
class LevelDecor {
  LevelDecor(this.seed);

  final int seed;
  final Set<String> _titles = {};
  final List<String> _firstWords = [], _nouns = [];
  final List<int> _palettes = [];

  String title(int order, String family) {
    final nouns = kTitleNouns[family] ?? const ['Glade'];
    final random = SeededRandom.of(['title', seed, order]);
    for (var attempt = 0; attempt < 4000; attempt++) {
      final first = random.pick(kTitleFirstWords);
      final noun = random.pick(nouns);
      final title = '$first $noun';
      final relaxed = attempt > 2000;
      if (_titles.contains(title)) continue;
      if (_related(first, noun)) continue;
      if (!relaxed && (_recent(_firstWords, 6).contains(first) || _recent(_nouns, 3).contains(noun))) continue;
      _titles.add(title);
      _firstWords.add(first);
      _nouns.add(noun);
      return title;
    }
    throw StateError('no unused title for level $order ($family)');
  }

  List<String> backdrop(int order) {
    final random = SeededRandom.of(['backdrop', seed, order]);
    final recent = _recent(_palettes, 2);
    final options = [
      for (var i = 0; i < kBackdropPalettes.length; i++)
        if (!recent.contains(i)) i,
    ];
    final chosen = random.pick(options);
    _palettes.add(chosen);
    return kBackdropPalettes[chosen];
  }

  static List<T> _recent<T>(List<T> items, int count) =>
      items.length <= count ? items : items.sublist(items.length - count);

  /// "Spring Spring", "Meadow Meadows", "Star Starfall": skip.
  static bool _related(String a, String b) {
    final x = a.toLowerCase(), y = b.toLowerCase();
    final stem = x.length < 4 ? x : x.substring(0, 4);
    return y.contains(stem) || x.contains(y.length < 4 ? y : y.substring(0, 4));
  }
}

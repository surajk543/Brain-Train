/// A compact, copyable set of tile indices.
///
/// Uses 32-bit words so behaviour is identical on the Dart VM and the web.
class TileMask {
  TileMask(this.size) : _words = List<int>.filled((size + 31) >> 5, 0);

  TileMask.all(this.size) : _words = List<int>.filled((size + 31) >> 5, 0xFFFFFFFF) {
    final extra = (_words.length << 5) - size;
    if (extra > 0 && _words.isNotEmpty) {
      _words[_words.length - 1] = 0xFFFFFFFF >>> extra;
    }
  }

  TileMask._copy(this.size, List<int> words) : _words = List<int>.of(words);

  final int size;
  final List<int> _words;

  bool contains(int index) => (_words[index >> 5] >> (index & 31)) & 1 == 1;

  void add(int index) => _words[index >> 5] |= 1 << (index & 31);

  void remove(int index) => _words[index >> 5] &= ~(1 << (index & 31)) & 0xFFFFFFFF;

  TileMask copy() => TileMask._copy(size, _words);

  bool get isEmpty => _words.every((word) => word == 0);

  int get count {
    var total = 0;
    for (var word in _words) {
      while (word != 0) {
        word &= word - 1;
        total++;
      }
    }
    return total;
  }

  Iterable<int> get indices sync* {
    for (var w = 0; w < _words.length; w++) {
      final word = _words[w];
      if (word == 0) continue;
      for (var bit = 0; bit < 32; bit++) {
        if ((word >> bit) & 1 == 1) yield (w << 5) + bit;
      }
    }
  }

  /// A stable string key for memoisation.
  String get key => _words.join(',');
}

import '../game_engine/models/json_reader.dart';

/// Ordered dotted-integer version, e.g. `2026.10.15.1`.
class ContentVersion implements Comparable<ContentVersion> {
  ContentVersion._(this.raw, this.parts);

  static final RegExp _pattern = RegExp(r'^\d{1,9}(\.\d{1,9}){0,5}$');

  static ContentVersion? tryParse(String raw) {
    if (!_pattern.hasMatch(raw)) return null;
    return ContentVersion._(raw, raw.split('.').map(int.parse).toList(growable: false));
  }

  final String raw;
  final List<int> parts;

  @override
  int compareTo(ContentVersion other) {
    for (var i = 0; i < parts.length || i < other.parts.length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  @override
  bool operator ==(Object other) => other is ContentVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(parts);

  @override
  String toString() => raw;
}

/// A pointer to an immutable content object, optionally with its SHA-256.
class ContentRef {
  const ContentRef({required this.url, this.sha256});

  factory ContentRef.fromJson(JsonReader json) =>
      ContentRef(url: json.string('url'), sha256: json.optString('sha256'));

  /// Content-root-relative path.
  final String url;
  final String? sha256;

  Map<String, Object?> toJson() => {'url': url, if (sha256 != null) 'sha256': sha256};
}

class LevelManifestEntry {
  const LevelManifestEntry({
    required this.levelId,
    required this.order,
    required this.title,
    required this.ref,
    this.difficulty,
    this.category,
    this.tileCount,
    this.trayCapacity,
  });

  factory LevelManifestEntry.fromJson(JsonReader json) => LevelManifestEntry(
    levelId: json.string('levelId'),
    order: json.integer('order'),
    title: json.optString('title') ?? json.string('levelId'),
    ref: ContentRef.fromJson(json),
    difficulty: json.optString('difficulty'),
    category: json.optString('category'),
    tileCount: json.optInt('tileCount'),
    trayCapacity: json.optInt('trayCapacity'),
  );

  final String levelId;
  final int order;
  final String title;
  final ContentRef ref;
  final String? difficulty;
  final String? category;
  final int? tileCount;

  /// The level's `rules.trayCapacity`, so lists and panels never need the
  /// level file. Null in manifests older than 2026.10.16.9 (then 4).
  final int? trayCapacity;

  /// This entry pointing at another file of the same level (an older
  /// version still on the device).
  LevelManifestEntry withRef(ContentRef other) => LevelManifestEntry(
    levelId: levelId,
    order: order,
    title: title,
    ref: other,
    difficulty: difficulty,
    category: category,
    tileCount: tileCount,
    trayCapacity: trayCapacity,
  );

  Map<String, Object?> toJson() => {
    'levelId': levelId,
    'order': order,
    'title': title,
    ...ref.toJson(),
    if (difficulty != null) 'difficulty': difficulty,
    if (category != null) 'category': category,
    if (tileCount != null) 'tileCount': tileCount,
    if (trayCapacity != null) 'trayCapacity': trayCapacity,
  };
}

/// The content manifest: the only mutable object, listing everything else.
class LevelManifest {
  LevelManifest({
    required this.schemaVersion,
    required this.contentVersion,
    required this.minClientContentSchema,
    required this.symbolRegistry,
    required List<LevelManifestEntry> levels,
    this.publishedAt,
  }) : levels = List.unmodifiable([...levels]..sort((a, b) => a.order.compareTo(b.order)));

  factory LevelManifest.fromJson(Object? decoded) {
    final json = JsonReader(decoded);
    final compatibility = json.optObject('compatibility');
    return LevelManifest(
      schemaVersion: json.integer('schemaVersion'),
      contentVersion: json.string('contentVersion'),
      minClientContentSchema: compatibility?.optInt('minClientContentSchema') ?? 1,
      symbolRegistry: ContentRef.fromJson(json.object('symbolRegistry')),
      levels: json.objectList('levels').map(LevelManifestEntry.fromJson).toList(),
      publishedAt: json.optString('publishedAt'),
    );
  }

  final int schemaVersion;
  final String contentVersion;

  /// Builds whose `kClientContentSchema` is lower must not use this content.
  final int minClientContentSchema;
  final ContentRef symbolRegistry;

  /// Sorted by [LevelManifestEntry.order].
  final List<LevelManifestEntry> levels;
  final String? publishedAt;

  LevelManifestEntry? entry(String levelId) {
    for (final level in levels) {
      if (level.levelId == levelId) return level;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'contentVersion': contentVersion,
    if (publishedAt != null) 'publishedAt': publishedAt,
    'compatibility': {'minClientContentSchema': minClientContentSchema},
    'symbolRegistry': symbolRegistry.toJson(),
    'levels': [for (final level in levels) level.toJson()],
  };
}

import 'dart:convert';
import 'dart:typed_data';

import 'content_validator.dart';
import 'content_exception.dart';

/// Byte storage behind [ContentCache]. Implementations must make [write]
/// atomic: a reader sees the old bytes or the new bytes, never a mix.
abstract class ContentStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, List<int> bytes);
  Future<void> delete(String key);

  /// Every stored key with its size in bytes.
  Future<Map<String, int>> sizes();
}

class MemoryContentStore implements ContentStore {
  final Map<String, Uint8List> _data = {};

  @override
  Future<Uint8List?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, List<int> bytes) async => _data[key] = Uint8List.fromList(bytes);

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<Map<String, int>> sizes() async => {for (final e in _data.entries) e.key: e.value.length};
}

/// The last manifest whose registry, levels and artwork were all fetched,
/// validated and cached.
class KnownGoodRecord {
  const KnownGoodRecord({required this.contentVersion, required this.manifestJson, required this.savedAt});

  final String contentVersion;

  /// The manifest as decoded JSON (re-validated on every load).
  final Object? manifestJson;
  final DateTime savedAt;
}

/// Persistent cache of immutable content objects plus the known-good pointer
/// and the index of ready levels.
///
/// Objects are addressed by their content path, which is content-addressed
/// or versioned (`levels/level-0001-<sha>.json`), so a cached object never
/// goes stale. Nothing is ever evicted: levels and art a player has had stay
/// playable offline.
class ContentCache {
  ContentCache(this.store);

  final ContentStore store;

  static const String _knownGoodKey = 'state/known-good.json';
  static String _objectKey(String path) => 'objects/$path';

  /// Cached bytes for [path], or null when missing. When [sha256] is given and
  /// the bytes do not match, the corrupt entry is deleted and null returned.
  Future<Uint8List?> readObject(String path, {String? sha256}) async {
    final bytes = await store.read(_objectKey(path));
    if (bytes == null) return null;
    try {
      ContentValidator.verifyChecksum(bytes, sha256, path);
      return bytes;
    } on ContentException {
      await store.delete(_objectKey(path));
      return null;
    }
  }

  Future<void> writeObject(String path, List<int> bytes) => store.write(_objectKey(path), bytes);

  Future<KnownGoodRecord?> readKnownGood() async {
    final bytes = await store.read(_knownGoodKey);
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return KnownGoodRecord(
        contentVersion: json['contentVersion']! as String,
        manifestJson: json['manifest'],
        savedAt: DateTime.parse(json['savedAt']! as String),
      );
    } on Object {
      // Corrupt pointer: forget it and fall back to bundled content.
      await store.delete(_knownGoodKey);
      return null;
    }
  }

  /// Call only after every object the manifest references is cached.
  Future<void> writeKnownGood(String contentVersion, Object? manifestJson) => store.write(
    _knownGoodKey,
    utf8.encode(jsonEncode({
      'contentVersion': contentVersion,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'manifest': manifestJson,
    })),
  );

  /// The cached file of each level the device can play: its level file and
  /// the registry that resolves its symbols, by level id. A level is
  /// recorded once its file and all its art are cached, and only replaced by
  /// a newer file of the same level once that one is cached too, so a level
  /// that was ever ready stays playable offline across content updates.
  Future<Map<String, CachedLevel>> readLevelIndex() async {
    final bytes = await store.read(_levelIndexKey);
    if (bytes == null) return {};
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return {
        for (final MapEntry(key: id, value: raw) in json.entries) id: CachedLevel.fromJson(raw! as Map<String, Object?>),
      };
    } on Object {
      // A corrupt index only costs the offline fallback; it is rebuilt.
      return {};
    }
  }

  Future<void> writeLevelIndex(Map<String, CachedLevel> index) => store.write(
    _levelIndexKey,
    utf8.encode(jsonEncode({for (final MapEntry(key: id, value: level) in index.entries) id: level.toJson()})),
  );

  static const String _levelIndexKey = 'state/levels.json';
}

/// Where a ready level's files are in the cache.
class CachedLevel {
  const CachedLevel({required this.level, required this.registry});

  factory CachedLevel.fromJson(Map<String, Object?> json) => CachedLevel(
    level: (url: json['url']! as String, sha256: json['sha256'] as String?),
    registry: (url: json['registry']! as String, sha256: json['registrySha256'] as String?),
  );

  final ({String url, String? sha256}) level;
  final ({String url, String? sha256}) registry;

  Map<String, Object?> toJson() => {
    'url': level.url,
    'sha256': ?level.sha256,
    'registry': registry.url,
    'registrySha256': ?registry.sha256,
  };
}

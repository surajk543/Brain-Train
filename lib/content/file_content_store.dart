import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'content_cache.dart';

final RegExp _keySegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$');

/// [ContentStore] on the local file system. Writes go to a temporary file
/// that is renamed into place, so a crash never leaves a half-written object.
class FileContentStore implements ContentStore {
  FileContentStore(this.root);

  final Directory root;
  final Random _random = Random();

  File _file(String key) {
    final segments = key.split('/');
    if (!segments.every(_keySegment.hasMatch)) {
      throw ArgumentError.value(key, 'key', 'unsafe cache key');
    }
    return File('${root.path}/${segments.join('/')}');
  }

  @override
  Future<Uint8List?> read(String key) async {
    final file = _file(key);
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, List<int> bytes) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp${_random.nextInt(1 << 32)}');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Map<String, int>> sizes() async {
    if (!await root.exists()) return {};
    final result = <String, int>{};
    final prefix = root.path.length + 1;
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File || entity.path.contains('.tmp')) continue;
      result[entity.path.substring(prefix)] = await entity.length();
    }
    return result;
  }
}

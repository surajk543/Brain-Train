import 'dart:convert';
import 'dart:typed_data';

import 'content_cache.dart';
import 'content_config.dart';
import 'content_exception.dart';
import 'content_validator.dart';
import 'remote_asset_resolver.dart';

/// Somewhere content objects can be read from by content-root-relative path.
abstract class ContentSource {
  /// Bytes of [path]. Throws [ContentException] when unavailable or invalid.
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256});
}

/// Reads only what is already cached; never touches the network.
class CachedContentSource implements ContentSource {
  const CachedContentSource(this.cache);

  final ContentCache cache;

  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) async {
    RemoteAssetResolver.checkPath(path, kind);
    final bytes = await cache.readObject(path, sha256: sha256);
    if (bytes == null) throw ContentException(ContentErrorKind.missingFromCache, 'not cached', path: path);
    return bytes;
  }
}

/// Content shipped inside the app, e.g. Flutter assets under
/// `content/brain-train/`. [loader] returns null for a missing asset.
class BundledContentSource implements ContentSource {
  BundledContentSource(this.loader, {this.prefix = 'content/brain-train/'});

  final Future<Uint8List?> Function(String assetKey) loader;
  final String prefix;

  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) async {
    RemoteAssetResolver.checkPath(path, kind);
    final bytes = await loader('$prefix$path');
    if (bytes == null) throw ContentException(ContentErrorKind.notFound, 'not bundled', path: path);
    ContentValidator.verifyChecksum(bytes, sha256, path);
    return bytes;
  }
}

/// Tries [primary], then [secondary]. Used for artwork: downloaded copy
/// first, bundled copy second, renderer fallback face last.
class FallbackContentSource implements ContentSource {
  const FallbackContentSource(this.primary, this.secondary);

  final ContentSource primary;
  final ContentSource secondary;

  @override
  Future<Uint8List> read(String path, ContentKind kind, {String? sha256}) async {
    try {
      return await primary.read(path, kind, sha256: sha256);
    } on ContentException {
      return secondary.read(path, kind, sha256: sha256);
    }
  }
}

/// Decodes UTF-8 JSON, mapping syntax errors to a format [ContentException].
Object? decodeJsonBytes(List<int> bytes, String path) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw ContentException(ContentErrorKind.format, 'invalid JSON: ${error.message}', path: path);
  }
}

/// Rejects bytes that are not PNG or WebP before they reach the decoder.
void checkImageSignature(Uint8List bytes, String path) {
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  bool at(int offset, List<int> expected) {
    if (bytes.length < offset + expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (bytes[offset + i] != expected[i]) return false;
    }
    return true;
  }

  final isPng = at(0, png);
  final isWebp = at(0, ascii.encode('RIFF')) && at(8, ascii.encode('WEBP'));
  if (!isPng && !isWebp) {
    throw ContentException(ContentErrorKind.format, 'not a PNG or WebP image', path: path);
  }
}

/// The basic facts of a Lottie animation that passed [checkLottieJson].
typedef LottieSummary = ({double frameRate, double seconds, double width, double height, int layers});

/// Rejects bytes that are not a plausible Lottie animation before they reach
/// the Lottie parser: at most [maxBytes], a JSON object with version `v`,
/// frame rate `fr`, in/out points `ip`/`op`, size `w`/`h` and a non-empty
/// `layers` array. Image assets must be embedded (`data:` URIs): animated
/// symbols never load files from elsewhere.
LottieSummary checkLottieJson(Uint8List bytes, String path, {int maxBytes = kMaxAnimationBytes}) {
  Never bad(String message) =>
      throw ContentException(ContentErrorKind.format, 'not a Lottie animation: $message', path: path);
  if (bytes.length > maxBytes) {
    throw ContentException(ContentErrorKind.tooLarge, '${bytes.length} bytes exceeds $maxBytes', path: path);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    bad('invalid JSON (${error.message})');
  }
  if (decoded is! Map<String, Object?>) bad('expected a JSON object');
  final json = decoded;
  double number(String key, {required double min, required double max}) {
    final value = json[key];
    if (value is! num || !value.isFinite || value < min || value > max) bad('"$key" must be a number in [$min, $max]');
    return value.toDouble();
  }

  if (json['v'] is! String) bad('"v" (version) must be a string');
  final frameRate = number('fr', min: 1, max: 240);
  final inPoint = number('ip', min: -100000, max: 100000);
  final outPoint = number('op', min: -100000, max: 100000);
  final width = number('w', min: 1, max: 8192);
  final height = number('h', min: 1, max: 8192);
  final seconds = (outPoint - inPoint) / frameRate;
  if (seconds <= 0 || seconds > 120) bad('"op" - "ip" must give a duration in (0, 120] seconds');
  final layers = json['layers'];
  if (layers is! List || layers.isEmpty || layers.any((layer) => layer is! Map)) {
    bad('"layers" must be a non-empty array of objects');
  }
  final assets = json['assets'];
  if (assets != null) {
    if (assets is! List) bad('"assets" must be an array');
    for (final asset in assets) {
      if (asset is! Map) bad('"assets" entries must be objects');
      if (asset['layers'] != null) continue; // a precomposition
      final file = asset['p'];
      if (file is String && !file.startsWith('data:')) {
        bad('image asset "${asset['id']}" is an external file; embed it');
      }
    }
  }
  return (frameRate: frameRate, seconds: seconds, width: width, height: height, layers: layers.length);
}

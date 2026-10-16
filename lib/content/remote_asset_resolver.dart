import '../game_engine/models/symbol_definition.dart';
import 'content_config.dart';
import 'content_exception.dart';

/// What a content path is expected to contain.
enum ContentKind {
  json({'.json'}),
  image({'.webp', '.png'}),

  /// Lottie animation JSON (animated symbols).
  animation({'.json'});

  const ContentKind(this.extensions);

  final Set<String> extensions;

  /// The kind of [symbol]'s artwork file, or null when it has none
  /// (emoji and text symbols are drawn from their value).
  static ContentKind? forSymbol(SymbolDefinition symbol) => switch (symbol.type) {
    SymbolType.image => ContentKind.image,
    SymbolType.lottie => ContentKind.animation,
    SymbolType.emoji || SymbolType.text => null,
  };
}

final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$');

/// Turns content-root-relative paths from manifests and registries into
/// fetchable URLs, refusing anything that could escape the content root or
/// reach another host.
class RemoteAssetResolver {
  const RemoteAssetResolver(this.config);

  final ContentConfig config;

  /// Throws [ContentException] of kind [ContentErrorKind.unsafePath] unless
  /// [path] is a plain relative path like `levels/level-0001-v1.json`.
  static void checkPath(String path, ContentKind kind) {
    String? problem;
    if (path.isEmpty || path.length > 240) {
      problem = 'empty or too long';
    } else if (path.contains('://') || path.startsWith('/') || path.contains('\\')) {
      problem = 'must be relative to the content root';
    } else if (path.contains('?') || path.contains('#') || path.contains('%')) {
      problem = 'query, fragment and escapes are not allowed';
    } else if (!path.split('/').every(_segmentPattern.hasMatch)) {
      problem = 'segments must be plain names (no "..", ".", or empty)';
    } else {
      final lower = path.toLowerCase();
      if (!kind.extensions.any(lower.endsWith)) {
        problem = 'expected ${kind.extensions.join(' or ')}';
      }
    }
    if (problem != null) {
      throw ContentException(ContentErrorKind.unsafePath, problem, path: path);
    }
  }

  static bool isSafe(String path, ContentKind kind) {
    try {
      checkPath(path, kind);
      return true;
    } on ContentException {
      return false;
    }
  }

  Uri resolve(String path, ContentKind kind) {
    checkPath(path, kind);
    return _checked(config.baseUrl.resolve('${config.contentRoot}$path'), path);
  }

  Uri get manifestUri =>
      _checked(config.baseUrl.resolve('${config.contentRoot}${config.manifestPath}'), config.manifestPath);

  Uri _checked(Uri uri, String path) {
    if (uri.scheme != 'https' || !config.allowedHosts.contains(uri.host)) {
      throw ContentException(ContentErrorKind.unsafePath, 'host ${uri.host} is not allowed', path: path);
    }
    return uri;
  }
}

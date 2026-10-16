enum ContentErrorKind {
  network,
  timeout,
  http,
  notFound,
  tooLarge,
  format,
  validation,
  checksum,
  unsafePath,
  incompatible,
  missingFromCache,
}

/// Any failure while fetching, caching or validating game content.
class ContentException implements Exception {
  ContentException(this.kind, this.message, {this.path, this.statusCode});

  final ContentErrorKind kind;
  final String message;
  final String? path;
  final int? statusCode;

  /// Worth retrying later (connectivity or server trouble), as opposed to
  /// content that is wrong and will stay wrong.
  bool get isTransient =>
      kind == ContentErrorKind.network ||
      kind == ContentErrorKind.timeout ||
      (kind == ContentErrorKind.http && (statusCode ?? 0) >= 500);

  @override
  String toString() => 'ContentException(${kind.name}${path == null ? '' : ' $path'}): $message';
}

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'content_config.dart';
import 'content_exception.dart';

/// HTTP GET with a timeout, a size cap and bounded retries for transient
/// failures. Never retries 4xx responses: they will not fix themselves.
class ContentFetcher {
  ContentFetcher({
    required this.client,
    required this.config,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final http.Client client;
  final ContentConfig config;
  final Future<void> Function(Duration) _delay;

  Future<Uint8List> get(Uri uri, {required int maxBytes, String? path}) async {
    ContentException? last;
    for (var attempt = 0; attempt <= config.maxRetries; attempt++) {
      if (attempt > 0) await _delay(config.retryBackoff * attempt);
      try {
        final response = await client.get(uri).timeout(config.requestTimeout);
        final status = response.statusCode;
        if (status == 200) {
          if (response.bodyBytes.length > maxBytes) {
            throw ContentException(ContentErrorKind.tooLarge, '${response.bodyBytes.length} bytes exceeds $maxBytes', path: path);
          }
          return response.bodyBytes;
        }
        last = ContentException(
          status == 404 ? ContentErrorKind.notFound : ContentErrorKind.http,
          'HTTP $status',
          path: path,
          statusCode: status,
        );
        if (status < 500 && status != 429) throw last;
      } on ContentException {
        rethrow;
      } on TimeoutException {
        last = ContentException(ContentErrorKind.timeout, 'no response within ${config.requestTimeout}', path: path);
      } on http.ClientException catch (error) {
        last = ContentException(ContentErrorKind.network, error.message, path: path);
      } on Exception catch (error) {
        // TLS and socket errors that the HTTP client does not wrap.
        last = ContentException(ContentErrorKind.network, error.toString(), path: path);
      }
    }
    throw last!;
  }
}

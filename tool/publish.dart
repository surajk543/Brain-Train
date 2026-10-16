// ignore_for_file: avoid_print

// Publishes content/brain-train/ to the R2 bucket under `brain-train/`.
//
//   dart run tool/publish.dart --dry-run   # show what would be uploaded
//   dart run tool/publish.dart             # validate, upload, verify
//
// Order matters: every immutable object (artwork, registry, levels) is
// compared with the bucket first (in parallel); an existing object with
// different bytes aborts before anything is written. New objects are then
// uploaded in parallel batches of 8 and verified by ETag; manifest.json goes
// last, so clients never see a manifest that points at missing files.
// Unchanged (content-addressed) objects are skipped.
//
// Credentials come from .env (R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
// R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME). They are only used here, never in
// the app.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brain_train/content/content_config.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'content.dart' as content;

const String prefix = 'brain-train/';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final force = args.contains('--force');
  if (!await content.validate()) {
    stderr.writeln('content is invalid; nothing published');
    exit(1);
  }
  final env = _readEnv();
  final r2 = R2Client(
    accountId: env['R2_ACCOUNT_ID']!,
    accessKeyId: env['R2_ACCESS_KEY_ID']!,
    secretAccessKey: env['R2_SECRET_ACCESS_KEY']!,
    bucket: env['R2_BUCKET_NAME']!,
  );

  final manifestFile = File('${content.contentRoot.path}/manifest.json');
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final registryPath = (manifest['symbolRegistry']! as Map<String, Object?>)['url']! as String;
  final registry = jsonDecode(File('${content.contentRoot.path}/$registryPath').readAsStringSync()) as Map<String, Object?>;
  final paths = <String>[
    for (final symbol in (registry['symbols']! as Map<String, Object?>).values)
      if ((symbol! as Map<String, Object?>)['assetPath'] case final String path) path,
    registryPath,
    for (final level in (manifest['levels']! as List<Object?>)) (level! as Map<String, Object?>)['url']! as String,
  ];

  print('\nPublishing contentVersion ${manifest['contentVersion']} to bucket ${r2.bucket} (${dryRun ? 'dry run' : 'live'})');

  // 1. Compare every immutable object with the bucket (in parallel) before
  //    anything is written: a key that exists with other bytes aborts the
  //    whole publish.
  final local = {for (final path in paths) path: File('${content.contentRoot.path}/$path').readAsBytesSync()};
  final remote = <String, String?>{};
  await _parallel(paths, (path) async => remote[path] = await r2.headEtag('$prefix$path'));
  final upload = <String>[];
  var same = 0;
  for (final path in paths) {
    final localMd5 = md5.convert(local[path]!).toString();
    if (remote[path] == localMd5) {
      same++;
    } else if (remote[path] != null && !force) {
      stderr.writeln('ABORT     $prefix$path exists with different bytes; published keys are immutable. Bump the revision.');
      exit(1);
    } else {
      upload.add(path);
    }
  }
  print('objects   ${paths.length} referenced: $same already published, ${upload.length} to upload');

  // 2. Upload the new objects in parallel batches, verifying each by ETag.
  if (dryRun) {
    for (final path in upload) {
      print('would put $prefix$path (${local[path]!.length} bytes)');
    }
  } else {
    var done = 0;
    await _parallel(upload, (path) async {
      final key = '$prefix$path';
      final bytes = local[path]!;
      await r2.put(key, bytes, contentType: _contentType(path));
      final stored = await r2.headEtag(key);
      final localMd5 = md5.convert(bytes).toString();
      if (stored != localMd5) throw StateError('verification failed for $key: stored ETag $stored, local MD5 $localMd5');
      done++;
      print('put       $key (${bytes.length} bytes) [$done/${upload.length}]');
    });
  }

  final manifestBytes = manifestFile.readAsBytesSync();
  if (dryRun) {
    print('would put ${prefix}manifest.json last');
    return;
  }
  await r2.put('${prefix}manifest.json', manifestBytes, contentType: 'application/json; charset=utf-8');
  print('put       ${prefix}manifest.json (last)');

  // End-to-end check through the public Worker URL the app uses.
  final publicUrl = ContentConfig.production.baseUrl.resolve('${prefix}manifest.json');
  final response = await http.get(publicUrl);
  if (response.statusCode == 200 && sha256.convert(response.bodyBytes) == sha256.convert(manifestBytes)) {
    print('\nverified  $publicUrl serves the new manifest');
  } else {
    print('\nWARNING   $publicUrl returned ${response.statusCode}; the Worker may not expose $prefix yet');
  }
}

/// Runs [task] for every item, at most [concurrency] at a time; the first
/// failure is rethrown once the running tasks finish.
Future<void> _parallel(List<String> items, Future<void> Function(String item) task, {int concurrency = 8}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      await _retry(() => task(item));
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
}

/// Retries transient network failures (R2 occasionally drops a connection).
Future<T> _retry<T>(Future<T> Function() body, {int attempts = 3}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await body();
    } on SocketException {
      if (attempt >= attempts) rethrow;
    } on http.ClientException {
      if (attempt >= attempts) rethrow;
    } on HttpException catch (error) {
      // 5xx only; 4xx will not fix itself.
      if (attempt >= attempts || !RegExp(r'-> 5\d\d').hasMatch(error.message)) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
  }
}

Map<String, String> _readEnv() {
  final file = File('.env');
  if (!file.existsSync()) throw StateError('.env not found');
  return {
    for (final line in file.readAsLinesSync())
      if (line.contains('=') && !line.trimLeft().startsWith('#'))
        line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1).trim().replaceAll(RegExp('^["\']|["\']\$'), ''),
  };
}

String _contentType(String path) => switch (path.split('.').last) {
  'json' => 'application/json; charset=utf-8',
  'webp' => 'image/webp',
  'png' => 'image/png',
  _ => 'application/octet-stream',
};

/// Minimal S3 SigV4 client for R2 (PUT and HEAD only).
class R2Client {
  R2Client({required this.accountId, required this.accessKeyId, required this.secretAccessKey, required this.bucket});

  final String accountId;
  final String accessKeyId;
  final String secretAccessKey;
  final String bucket;
  final http.Client _http = http.Client();

  String get _host => '$accountId.r2.cloudflarestorage.com';

  /// The object's ETag (MD5 for single-part uploads), or null if absent.
  Future<String?> headEtag(String key) async {
    final response = await _send('HEAD', key, Uint8List(0), const {});
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw HttpException('HEAD $key -> ${response.statusCode}');
    // R2 marks compressible objects' ETags weak (W/"..."); the hash is the same.
    return response.headers['etag']?.replaceFirst('W/', '').replaceAll('"', '');
  }

  Future<void> put(String key, Uint8List bytes, {required String contentType}) async {
    final response = await _send('PUT', key, bytes, {'content-type': contentType});
    if (response.statusCode != 200) {
      throw HttpException('PUT $key -> ${response.statusCode}: ${response.body}');
    }
  }

  Future<http.Response> _send(String method, String key, Uint8List body, Map<String, String> extra) async {
    final now = DateTime.now().toUtc();
    final amzDate = '${now.toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
    final date = amzDate.substring(0, 8);
    final path = '/$bucket/${key.split('/').map(Uri.encodeComponent).join('/')}';
    final payloadHash = sha256.convert(body).toString();
    final headers = <String, String>{
      'host': _host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      ...extra,
    };
    final names = headers.keys.toList()..sort();
    final canonical = [
      method,
      path,
      '',
      for (final name in names) '$name:${headers[name]!.trim()}',
      '',
      names.join(';'),
      payloadHash,
    ].join('\n');
    final scope = '$date/auto/s3/aws4_request';
    final toSign = ['AWS4-HMAC-SHA256', amzDate, scope, sha256.convert(utf8.encode(canonical)).toString()].join('\n');
    List<int> hmacOf(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    var signingKey = hmacOf(utf8.encode('AWS4$secretAccessKey'), date);
    signingKey = hmacOf(signingKey, 'auto');
    signingKey = hmacOf(signingKey, 's3');
    signingKey = hmacOf(signingKey, 'aws4_request');
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(toSign)).toString();
    final request = http.Request(method, Uri.parse('https://$_host$path'))
      ..headers.addAll({
        ...headers..remove('host'),
        'authorization': 'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, SignedHeaders=${names.join(';')}, Signature=$signature',
      })
      ..bodyBytes = body;
    return http.Response.fromStream(await _http.send(request));
  }
}

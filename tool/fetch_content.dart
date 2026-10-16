// ignore_for_file: avoid_print

// Mirrors the published content tree from production into
// content/brain-train/ (gitignored), so a fresh clone can rebuild, validate
// and publish without the original art.
//
//   dart run tool/fetch_content.dart              # current live version
//   dart run tool/fetch_content.dart --force      # overwrite a local tree
//
// Reads the public `brain-train/` prefix through the braintrain-assets
// Worker (no keys needed): the manifest, its registry, every level and every
// symbol file, each checked against its sha256. Files already present with
// the right hash are skipped. Uses only package:http, not the app's content
// code, so it keeps working while that code changes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _base = 'https://braintrain-cdn.sungamestudio.com/brain-train/';
const _out = 'content/brain-train';
const _parallel = 8;

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final client = http.Client();
  try {
    final manifestBytes = await _get(client, 'manifest.json');
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>;
    final version = manifest['contentVersion'];
    final local = File('$_out/manifest.json');
    if (local.existsSync() && !force) {
      final localVersion = (jsonDecode(local.readAsStringSync()) as Map<String, Object?>)['contentVersion'];
      if (localVersion != version) {
        stderr.writeln('$_out/ holds $localVersion, production is $version. Re-run with --force to replace it.');
        exitCode = 2;
        return;
      }
    }

    final registryRef = manifest['symbolRegistry']! as Map<String, Object?>;
    final registryBytes = await _fetchVerified(client, registryRef['url']! as String, registryRef['sha256']! as String);
    final registry = jsonDecode(utf8.decode(registryBytes)) as Map<String, Object?>;

    final files = <(String, String)>[
      for (final level in (manifest['levels']! as List).cast<Map<String, Object?>>())
        (level['url']! as String, level['sha256']! as String),
      for (final symbol in (registry['symbols']! as Map<String, Object?>).values.cast<Map<String, Object?>>())
        if (symbol['assetPath'] is String && symbol['sha256'] is String)
          (symbol['assetPath']! as String, symbol['sha256']! as String),
    ];

    var fetched = 0, skipped = 0;
    final queue = [...files];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final (path, sha) = queue.removeLast();
        final file = File('$_out/$path');
        if (file.existsSync() && sha256.convert(file.readAsBytesSync()).toString() == sha) {
          skipped++;
          continue;
        }
        await _fetchVerified(client, path, sha);
        fetched++;
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    // The manifest goes last, like publishing: a half-mirrored tree never
    // claims to be complete.
    local
      ..createSync(recursive: true)
      ..writeAsBytesSync(manifestBytes);
    print('mirrored $version into $_out/: ${files.length + 2} objects ($fetched fetched, $skipped already present)');
  } finally {
    client.close();
  }
}

Future<List<int>> _fetchVerified(http.Client client, String path, String sha) async {
  final bytes = await _get(client, path);
  final actual = sha256.convert(bytes).toString();
  if (actual != sha) throw StateError('$path: sha256 $actual, expected $sha');
  File('$_out/$path')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  return bytes;
}

Future<List<int>> _get(http.Client client, String path) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final response = await client.get(Uri.parse('$_base$path')).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) return response.bodyBytes;
      if (attempt >= 3) throw HttpException('GET $path: HTTP ${response.statusCode}');
    } on TimeoutException {
      if (attempt >= 3) rethrow;
    } on SocketException {
      if (attempt >= 3) rethrow;
    }
    await Future<void>.delayed(Duration(seconds: attempt));
  }
}

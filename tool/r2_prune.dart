// ignore_for_file: avoid_print

// Lists, and on request deletes, every object under `brain-train/` in the
// public content bucket (`contentBucket`) that the published manifest no longer references (old levels, old
// registries, retired symbol sets, unused art).
//
//   dart run tool/r2_prune.dart            # list what would be deleted
//   dart run tool/r2_prune.dart --delete   # delete it (permanent)
//
// The keep-set is built from content/brain-train/manifest.json: the manifest
// itself, its registry and every symbol in it, and every level file. Before
// listing, the live manifest (through the public URL the app uses)
// must be byte-identical to the local one, so nothing a client can still
// fetch from the live manifest is ever removed. Only `brain-train/` is
// touched; other prefixes in the bucket are never listed or deleted. The old
// private bucket's `brain-train/` copy (behind the workers.dev Worker, for
// builds before versionCode 5) is never touched.
//
// Credentials come from .env, as for tool/publish.dart.

import 'dart:convert';
import 'dart:io';

import 'package:brain_train/content/content_config.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'content.dart' as content;
import 'publish.dart' show R2Client, contentBucket, prefix, readEnv;

Future<void> main(List<String> args) async {
  final delete = args.contains('--delete');

  final manifestFile = File('${content.contentRoot.path}/manifest.json');
  final manifestBytes = manifestFile.readAsBytesSync();
  final publicUrl = ContentConfig.production.baseUrl.resolve('${prefix}manifest.json');
  final live = await http.get(publicUrl);
  if (live.statusCode != 200 || sha256.convert(live.bodyBytes) != sha256.convert(manifestBytes)) {
    stderr.writeln(
      'ABORT     $publicUrl (${live.statusCode}) is not the local manifest; publish it first '
      '(dart run tool/publish.dart), so pruning never removes a file the live manifest uses.',
    );
    exit(1);
  }

  final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>;
  final registryPath = (manifest['symbolRegistry']! as Map<String, Object?>)['url']! as String;
  final registry = jsonDecode(File('${content.contentRoot.path}/$registryPath').readAsStringSync()) as Map<String, Object?>;
  final keep = <String>{
    '${prefix}manifest.json',
    '$prefix$registryPath',
    for (final symbol in (registry['symbols']! as Map<String, Object?>).values)
      if ((symbol! as Map<String, Object?>)['assetPath'] case final String path) '$prefix$path',
    for (final level in (manifest['levels']! as List<Object?>)) '$prefix${(level! as Map<String, Object?>)['url']! as String}',
  };

  final env = readEnv();
  final r2 = R2Client(
    accountId: env['R2_ACCOUNT_ID']!,
    accessKeyId: env['R2_ACCESS_KEY_ID']!,
    secretAccessKey: env['R2_SECRET_ACCESS_KEY']!,
    bucket: contentBucket,
  );
  final objects = await r2.list(prefix);
  final missing = keep.difference({for (final (key, _) in objects) key});
  if (missing.isNotEmpty) {
    stderr.writeln('ABORT     ${missing.length} referenced objects are not in the bucket, e.g. ${missing.first}');
    exit(1);
  }
  final stale = [
    for (final (key, size) in objects)
      if (!keep.contains(key)) (key, size),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  // Summary by folder (levels/, registries/, symbols/v3/, ...).
  final byFolder = <String, (int, int)>{};
  for (final (key, size) in stale) {
    final parts = key.substring(prefix.length).split('/');
    final folder = parts.length > 2 && parts[0] == 'symbols' ? '${parts[0]}/${parts[1]}/' : '${parts.first}/';
    final (count, bytes) = byFolder[folder] ?? (0, 0);
    byFolder[folder] = (count + 1, bytes + size);
  }
  print('\nbucket ${r2.bucket}, $prefix: ${objects.length} objects, ${keep.length} referenced by '
      'contentVersion ${manifest['contentVersion']}, ${stale.length} unreferenced');
  for (final MapEntry(key: folder, value: (count, bytes)) in byFolder.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    print('  $prefix${folder.padRight(28)} ${count.toString().padLeft(5)} objects  ${(bytes / 1024).toStringAsFixed(0).padLeft(7)} KB');
  }
  if (stale.isEmpty) return;

  if (!delete) {
    for (final (key, size) in stale) {
      print('would delete $key ($size bytes)');
    }
    print('\nTo delete these ${stale.length} objects permanently, run:\n  dart run tool/r2_prune.dart --delete');
    return;
  }

  var done = 0;
  for (var i = 0; i < stale.length; i += 8) {
    await Future.wait([
      for (final (key, _) in stale.skip(i).take(8))
        r2.delete(key).then((_) {
          done++;
          print('deleted   $key [$done/${stale.length}]');
        }),
    ]);
  }
  print('\n$done objects deleted from $prefix');
}

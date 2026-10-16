// ignore_for_file: avoid_print

// Keeps the symbol masters (art/masters/, the full-size PNGs written by
// tool/assets/prepare_symbols.py) in the R2 bucket instead of git.
//
//   dart run tool/r2_art.dart push --dry-run   # show new or changed masters
//   dart run tool/r2_art.dart push             # upload them
//   dart run tool/r2_art.dart pull             # download missing or changed masters
//
// Keys mirror the paths: `art/masters/<set>/<name>.png`. They sit outside
// `brain-train/`, so the public Worker never serves them (licensed IconScout
// art); reading them needs the R2 keys in .env. Files are compared by MD5 (the
// ETag of a single-part upload). push never deletes from R2 and pull never
// deletes local files. The app never reads masters: it uses the WebP symbols
// that tool/publish.dart uploads under `brain-train/`.
//
// Credentials come from .env, as for tool/publish.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'publish.dart' show R2Client, readEnv;

const String folder = 'art/masters/';

Future<void> main(List<String> args) async {
  final command = args.isEmpty ? '' : args.first;
  if (command != 'push' && command != 'pull') {
    stderr.writeln('usage: dart run tool/r2_art.dart push [--dry-run] | pull');
    exit(64);
  }
  final env = readEnv();
  final r2 = R2Client(
    accountId: env['R2_ACCOUNT_ID']!,
    accessKeyId: env['R2_ACCESS_KEY_ID']!,
    secretAccessKey: env['R2_SECRET_ACCESS_KEY']!,
    bucket: env['R2_BUCKET_NAME']!,
  );
  if (command == 'push') {
    await push(r2, dryRun: args.contains('--dry-run'));
  } else {
    await pull(r2);
  }
}

Future<void> push(R2Client r2, {required bool dryRun}) async {
  final dir = Directory(folder);
  if (!dir.existsSync()) {
    stderr.writeln('$folder not found: run tool/assets/prepare_symbols.py, or pull first');
    exit(1);
  }
  final files = [
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.png')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));

  var changed = 0;
  await _batches(files, (file) async {
    final key = file.path.replaceAll(Platform.pathSeparator, '/');
    final bytes = file.readAsBytesSync();
    final md5Hex = md5.convert(bytes).toString();
    final etag = await r2.headEtag(key);
    if (etag == md5Hex) return;
    changed++;
    if (dryRun) {
      print('would upload $key (${etag == null ? 'new' : 'changed'})');
      return;
    }
    await r2.put(key, bytes, contentType: 'image/png');
    if (await r2.headEtag(key) != md5Hex) throw StateError('$key: uploaded bytes do not verify');
    print('uploaded  $key (${etag == null ? 'new' : 'changed'})');
  });
  print('\n${files.length} masters in $folder, $changed ${dryRun ? 'to upload' : 'uploaded'}, '
      '${files.length - changed} already in bucket ${r2.bucket}');
}

Future<void> pull(R2Client r2) async {
  final objects = await r2.list(folder);
  var changed = 0;
  await _batches(objects, (object) async {
    final (key, _) = object;
    final file = File(key);
    if (file.existsSync() && md5.convert(file.readAsBytesSync()).toString() == await r2.headEtag(key)) return;
    final Uint8List? bytes = await r2.get(key);
    if (bytes == null) throw StateError('$key vanished from the bucket');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    changed++;
    print('downloaded $key');
  });
  print('\n${objects.length} masters in bucket ${r2.bucket}, $changed downloaded, ${objects.length - changed} already here');
}

/// Runs [task] for every item, 8 at a time.
Future<void> _batches<T>(List<T> items, Future<void> Function(T item) task) async {
  for (var i = 0; i < items.length; i += 8) {
    await Future.wait([for (final item in items.skip(i).take(8)) task(item)]);
  }
}

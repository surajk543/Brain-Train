import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../platform/cloud_store.dart';
import 'progress_repository.dart';
import 'settings_repository.dart';

/// The cloud copy of the progress, one JSON value under
/// [CloudProgressSync.key]: `{"v": 1, "completed": {levelId: LevelRecord},
/// "settings": {key: bool}}`.
class CloudProgress {
  const CloudProgress({required this.completed, required this.settings});

  /// This build writes and reads format 1.
  static const int version = 1;

  /// Reads [json] leniently: a record or setting that does not parse is left
  /// out, the rest is kept.
  factory CloudProgress.fromJson(Map<String, Object?> json) {
    final completed = <String, LevelRecord>{};
    if (json['completed'] case final Map<String, Object?> records) {
      for (final MapEntry(key: levelId, value: record) in records.entries) {
        try {
          completed[levelId] = LevelRecord.fromJson(record! as Map<String, Object?>);
        } on Object {
          // A damaged record: skip it.
        }
      }
    }
    final settings = <String, bool>{
      if (json['settings'] case final Map<String, Object?> values)
        for (final MapEntry(key: key, value: value) in values.entries)
          if (value is bool) key: value,
    };
    return CloudProgress(completed: completed, settings: settings);
  }

  final Map<String, LevelRecord> completed;
  final Map<String, bool> settings;

  bool get isEmpty => completed.isEmpty && settings.isEmpty;

  /// Canonical (keys sorted), so two devices holding the same progress write
  /// the same bytes and never take turns rewriting it.
  String encode() => jsonEncode({
    'v': version,
    'completed': {for (final levelId in completed.keys.toList()..sort()) levelId: completed[levelId]!.toJson()},
    'settings': {for (final key in settings.keys.toList()..sort()) key: settings[key]},
  });
}

/// Keeps the player's progress in their own cloud account, so it survives a
/// reinstall (owner, 2026-10-23): the won levels with their best results
/// (the next level to play follows from them), the Sound / Music / Vibration
/// switches and the tutorial flag. Not the unfinished game (after a
/// reinstall that level starts over) and not the age group (it never leaves
/// the device).
///
/// Every sync reads the cloud copy, merges it into this device (a union of
/// the wins, the best result of each level; [ProgressRepository.mergeCompleted],
/// [SettingsRepository.restoreSynced]) and writes the merged copy back, so
/// two devices on one account never clash and nothing is overwritten. A copy
/// written by a newer build (a higher format) is read by nobody here and
/// never overwritten. Started by the lobby after its first frame, never on
/// the startup path; without a cloud store it does nothing.
class CloudProgressSync {
  CloudProgressSync({required this.progress, required this.settings, required this.cloud});

  final ProgressRepository progress;
  final SettingsRepository settings;
  final CloudStore cloud;

  /// The one cloud key.
  static const String key = 'progress.v1';

  bool _started = false;
  bool _disposed = false;
  StreamSubscription<void>? _changes;
  Future<void> _queue = Future.value();

  /// Syncs now, then after every change of the progress or the settings and
  /// whenever the cloud copy changes from outside (the first sync after an
  /// install, another device). Once per app run.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _changes = cloud.changes.listen((_) => sync());
    progress.addListener(sync);
    settings.addListener(sync);
    sync();
  }

  /// Queues one sync; syncs run one at a time, and a failure never stops the
  /// next. Completes when this one is done.
  Future<void> sync() => _queue = _queue.then((_) => _disposed ? null : _sync()).catchError((Object error) {
    debugPrint('Cloud save: sync failed ($error)');
  });

  Future<void> _sync() async {
    final raw = await cloud.read(key);
    Map<String, Object?>? json;
    if (raw != null) {
      try {
        json = jsonDecode(raw) as Map<String, Object?>;
      } on Object {
        json = null; // damaged: replaced by this device's copy below
      }
    }
    if (json != null && json['v'] is! int) json = null;
    if (json != null && (json['v']! as int) > CloudProgress.version) return; // a newer build's copy: leave it
    if (json != null) {
      final remote = CloudProgress.fromJson(json);
      await progress.mergeCompleted(remote.completed);
      await settings.restoreSynced(remote.settings);
    }
    final local = CloudProgress(completed: progress.completed(), settings: settings.syncedValues());
    // Nothing to keep yet, and never an empty copy over a stored one.
    if (local.isEmpty) return;
    final merged = local.encode();
    if (merged != raw) await cloud.write(key, merged);
  }

  void dispose() {
    _disposed = true;
    _changes?.cancel();
    if (_started) {
      progress.removeListener(sync);
      settings.removeListener(sync);
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:brain_train/data/cloud_progress_sync.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/platform/cloud_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iCloud key-value storage in memory; [changeFromOutside] plays another
/// device (or the first sync after an install).
class FakeCloudStore implements CloudStore {
  final values = <String, String>{};
  final _changes = StreamController<void>.broadcast();
  int writes = 0;

  void changeFromOutside(String key, String value) {
    values[key] = value;
    _changes.add(null);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    writes++;
    values[key] = value;
    return true;
  }

  @override
  Stream<void> get changes => _changes.stream;
}

LevelRecord _record({int timeMs = 60000, int moves = 20, int? score = 1000, int? combo = 2, DateTime? at}) =>
    LevelRecord(
      bestMoves: moves,
      bestTimeMs: timeMs,
      completedAt: at ?? DateTime(2026, 10, 20),
      bestScore: score,
      bestCombo: combo,
    );

String _cloudCopy(Map<String, LevelRecord> completed, {Map<String, bool> settings = const {}, int version = 1}) =>
    jsonEncode({
      'v': version,
      'completed': {for (final e in completed.entries) e.key: e.value.toJson()},
      'settings': settings,
    });

Map<String, Object?> _stored(FakeCloudStore cloud) =>
    jsonDecode(cloud.values[CloudProgressSync.key]!) as Map<String, Object?>;

void main() {
  late ProgressRepository progress;
  late SettingsRepository settings;
  late FakeCloudStore cloud;
  late CloudProgressSync sync;

  Future<void> open([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    progress = await ProgressRepository.open();
    settings = await SettingsRepository.open();
    cloud = FakeCloudStore();
    sync = CloudProgressSync(progress: progress, settings: settings, cloud: cloud);
  }

  /// Lets the queued syncs (and the ones their changes queue) finish.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await sync.sync();
    }
  }

  tearDown(() => sync.dispose());

  test('a reinstall gets the wins, the switches and the tutorial flag back', () async {
    await open();
    cloud.values[CloudProgressSync.key] = _cloudCopy(
      {'level-0001': _record(), 'level-0002': _record(timeMs: 45000, score: 1800, combo: 6)},
      settings: {SettingsRepository.soundKey: false, SettingsRepository.firstPlayTutorialKey: true},
    );
    var notified = 0;
    progress.addListener(() => notified++);
    sync.start();
    await settle();
    expect(progress.completed().keys, unorderedEquals(['level-0001', 'level-0002']));
    expect(progress.completed()['level-0002']!.bestCombo, 6);
    expect(notified, greaterThan(0), reason: 'the lobby redraws with the restored levels');
    expect(settings.sound, isFalse);
    expect(settings.firstPlayTutorialDone, isTrue);
    expect(settings.haptics, isTrue, reason: 'a switch the copy does not hold keeps its default');
  });

  test('levels won on both sides keep the best of each, and the union goes back to the cloud', () async {
    await open();
    await progress.recordWin('level-0001', moves: 18, timeMs: 70000, score: 2000, bestCombo: 3);
    await progress.recordWin('level-0003', moves: 30, timeMs: 90000, score: 900, bestCombo: 2);
    final cloudTime = DateTime(2026, 10, 1);
    cloud.values[CloudProgressSync.key] = _cloudCopy({
      'level-0001': _record(timeMs: 50000, moves: 25, score: 1500, combo: 5, at: cloudTime),
      'level-0002': _record(),
    });
    sync.start();
    await settle();
    final level1 = progress.completed()['level-0001']!;
    expect(level1.bestTimeMs, 50000, reason: 'the faster time');
    expect(level1.completedAt, cloudTime, reason: 'with the date of that faster win');
    expect(level1.bestMoves, 18);
    expect(level1.bestScore, 2000);
    expect(level1.bestCombo, 5);
    expect(progress.completed().keys, unorderedEquals(['level-0001', 'level-0002', 'level-0003']));
    final stored = _stored(cloud)['completed']! as Map<String, Object?>;
    expect(stored.keys, ['level-0001', 'level-0002', 'level-0003'], reason: 'sorted, the same bytes on every device');
    expect((stored['level-0001']! as Map)['bestTimeMs'], 50000);
  });

  test('a new win is written to the cloud', () async {
    await open();
    sync.start();
    await settle();
    expect(cloud.values, isEmpty, reason: 'nothing to keep yet');
    await progress.recordWin('level-0001', moves: 20, timeMs: 61000, score: 1200, bestCombo: 4);
    await settle();
    expect((_stored(cloud)['completed']! as Map).keys, ['level-0001']);
  });

  test('another device\'s wins arrive while playing, and the copies settle without rewriting', () async {
    await open();
    await progress.recordWin('level-0001', moves: 20, timeMs: 61000, score: 1200, bestCombo: 4);
    sync.start();
    await settle();
    cloud.changeFromOutside(CloudProgressSync.key, _cloudCopy({'level-0001': _record(timeMs: 61000), 'level-0002': _record()}));
    await settle();
    expect(progress.completed().keys, unorderedEquals(['level-0001', 'level-0002']));
    final writes = cloud.writes;
    await sync.sync();
    await sync.sync();
    expect(cloud.writes, writes, reason: 'an unchanged copy is never written again');
  });

  test('this device keeps its own switches; only unset ones come from the cloud', () async {
    await open({SettingsRepository.soundKey: true});
    cloud.values[CloudProgressSync.key] = _cloudCopy(
      {'level-0001': _record()},
      settings: {SettingsRepository.soundKey: false, SettingsRepository.musicKey: false},
    );
    sync.start();
    await settle();
    expect(settings.sound, isTrue);
    expect(settings.music, isFalse);
  });

  test('the age group never goes to the cloud', () async {
    await open({SettingsRepository.ageGroupKey: 'under13', SettingsRepository.soundKey: false});
    sync.start();
    await settle();
    expect((_stored(cloud)['settings']! as Map).keys, [SettingsRepository.soundKey]);
    expect(cloud.values[CloudProgressSync.key], isNot(contains('under13')));
  });

  test('a copy from a newer build is neither read nor overwritten', () async {
    await open();
    await progress.recordWin('level-0001', moves: 20, timeMs: 61000);
    final newer = _cloudCopy({'level-0009': _record()}, version: 2);
    cloud.values[CloudProgressSync.key] = newer;
    sync.start();
    await settle();
    expect(cloud.values[CloudProgressSync.key], newer);
    expect(progress.completed().keys, ['level-0001']);
  });

  test('a damaged copy is replaced by this device\'s, a damaged record skipped', () async {
    await open();
    await progress.recordWin('level-0001', moves: 20, timeMs: 61000);
    cloud.values[CloudProgressSync.key] = '{not json';
    sync.start();
    await settle();
    expect((_stored(cloud)['completed']! as Map).keys, ['level-0001']);

    cloud.changeFromOutside(
      CloudProgressSync.key,
      jsonEncode({
        'v': 1,
        'completed': {'level-0002': _record().toJson(), 'level-0003': {'bestMoves': 'x'}},
        'settings': {SettingsRepository.hapticsKey: 'no'},
      }),
    );
    await settle();
    expect(progress.completed().keys, unorderedEquals(['level-0001', 'level-0002']));
    expect(settings.haptics, isTrue);
  });

  test('without a cloud store nothing happens', () async {
    SharedPreferences.setMockInitialValues({});
    progress = await ProgressRepository.open();
    settings = await SettingsRepository.open();
    sync = CloudProgressSync(progress: progress, settings: settings, cloud: const UnavailableCloudStore());
    await progress.recordWin('level-0001', moves: 20, timeMs: 61000);
    sync.start();
    await settle();
    expect(progress.completed().keys, ['level-0001']);
  });
}

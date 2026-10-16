import 'dart:convert';

import 'package:brain_train/content/content_cache.dart';
import 'package:brain_train/content/content_coordinator.dart';
import 'package:brain_train/content/content_exception.dart';
import 'package:brain_train/content/content_snapshot.dart';
import 'package:brain_train/content/level_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fixture_content.dart';

void main() {
  final content = FixtureContent();

  Set<String> wonUpTo(int last) => {for (var n = 1; n <= last; n++) content.levelId(n)};

  /// Downloaded paths that are artwork.
  Set<String> art(Iterable<String> paths) => {
    for (final p in paths)
      if (p.startsWith('symbols/') || p.startsWith('animated-symbols/')) p,
  };

  /// Downloaded paths that are level files.
  Set<String> levelFiles(Iterable<String> paths) => {
    for (final p in paths)
      if (p.startsWith('levels/')) p,
  };

  group('first launch', () {
    test('offline: the starter pack lists every level and plays levels 1-5; level 6 needs the internet', () async {
      final f = fixtureCoordinator(server: content.server(online: () => false), bundle: content.starter());
      final snapshot = await f.coordinator.loadInitial();
      expect(snapshot.origin, ContentOrigin.bundled);
      expect(snapshot.playableEntries, hasLength(content.levels), reason: 'metadata of every level');
      expect(snapshot.levels.keys.toSet(), wonUpTo(5));
      expect(await f.coordinator.refresh(), ContentSyncStatus.offline);
      final window = await f.coordinator.maintainWindow();
      expect(window.window, [for (var n = 1; n <= 5; n++) content.levelId(n)]);
      expect(window.ready, 5);
      expect(window.offline, isFalse, reason: 'all from the bundle');
      for (var n = 1; n <= 5; n++) {
        expect(snapshot.isReady(content.levelId(n)), isTrue);
      }
      await expectLater(
        f.coordinator.ensureLevel(snapshot.manifest.entry(content.levelId(6))!),
        throwsA(isA<ContentException>().having((e) => e.isTransient, 'transient', isTrue)),
      );
      expect(f.downloads.networkRequests, 0);
    });

    test('online: only the manifest is downloaded; the window comes from the bundle', () async {
      final log = <String>[];
      final f = fixtureCoordinator(server: content.server(log: log), bundle: content.starter());
      await f.coordinator.loadInitial();
      expect(await f.coordinator.refresh(), ContentSyncStatus.upToDate);
      final window = await f.coordinator.maintainWindow();
      expect(window.ready, 5);
      expect(log, ['manifest.json']);
      expect(f.downloads.seededObjects, greaterThan(5), reason: 'registry, levels and art copied into the cache');
    });
  });

  group('rolling window', () {
    test('a win moves the window: only the new level and its art are downloaded, once each', () async {
      final log = <String>[];
      var won = <String>{};
      final f = fixtureCoordinator(server: content.server(log: log), bundle: content.starter(), completed: () => won);
      await f.coordinator.loadInitial();
      await f.coordinator.maintainWindow();
      expect(log, isEmpty);

      won = wonUpTo(2); // levels 1 and 2 won: the window is 3-7
      final window = await f.coordinator.maintainWindow();
      expect(window.window, [for (var n = 3; n <= 7; n++) content.levelId(n)]);
      expect(window.ready, 5);
      expect(levelFiles(log), {content.levelPaths[6], content.levelPaths[7]});
      expect(art(log), content.artOf([6, 7]).difference(content.artOf([1, 2, 3, 4, 5])));
      expect(log.toSet(), hasLength(log.length), reason: 'nothing twice; a symbol shared by both levels once');

      log.clear();
      await f.coordinator.maintainWindow();
      expect(log, isEmpty, reason: 'cached objects are not downloaded again');
    });

    test('only the window\'s symbols are fetched, never the whole registry', () async {
      final log = <String>[];
      // No starter pack to copy from: everything the window needs is downloaded.
      final bare = FixtureContent(version: '2026.1.1.0');
      final f = fixtureCoordinator(server: content.server(log: log), bundle: bare.starter(count: 0), seed: false);
      await f.coordinator.loadInitial();
      expect(await f.coordinator.refresh(), ContentSyncStatus.updated);
      final fetchedArt = art(log);
      expect(fetchedArt, content.artOf([1, 2, 3, 4, 5]));
      expect(fetchedArt.length, lessThan(content.allArt.length));
      expect(levelFiles(log), {for (var n = 1; n <= 5; n++) content.levelPaths[n]});
      expect(log, contains(content.registryPath), reason: 'the registry is metadata: always fetched');
    });

    test('a new session on the same cache downloads nothing it already has', () async {
      final store = MemoryContentStore();
      var won = wonUpTo(4);
      final first = fixtureCoordinator(server: content.server(), bundle: content.starter(), store: store, completed: () => won);
      await first.coordinator.loadInitial();
      await first.coordinator.maintainWindow();
      await first.coordinator.dispose();

      final log = <String>[];
      final second = fixtureCoordinator(server: content.server(log: log), bundle: content.starter(), store: store, completed: () => won);
      final snapshot = await second.coordinator.loadInitial();
      expect(snapshot.levels.keys, containsAll(wonUpTo(9)), reason: 'levels on disk load at start');
      final window = await second.coordinator.maintainWindow();
      expect(window.ready, 5);
      expect(log, isEmpty);
      won = wonUpTo(5);
      await second.coordinator.maintainWindow();
      expect(levelFiles(log), {content.levelPaths[10]});
    });

    test('the window never reaches past the last level, and is empty when all are won', () {
      final manifest = LevelManifest.fromJson(content.manifest);
      expect(ContentCoordinator.levelWindow(manifest, wonUpTo(10)).map((e) => e.order), [11, 12]);
      expect(ContentCoordinator.levelWindow(manifest, wonUpTo(12)), isEmpty);
      expect(ContentCoordinator.levelWindow(manifest, {content.levelId(2)}).map((e) => e.order), [1, 2, 3, 4, 5]);
      expect(
        ContentCoordinator.levelWindow(manifest, wonUpTo(1), excluded: {content.levelId(3)}).map((e) => e.order),
        [2, 4, 5, 6, 7],
      );
    });
  });

  group('offline play', () {
    test('won levels 1-7 online, then offline: each one and the window 8-12 replay with no network', () async {
      final store = MemoryContentStore();
      var online = true;
      var won = <String>{};
      final f = fixtureCoordinator(
        server: content.server(online: () => online),
        bundle: content.starter(),
        store: store,
        completed: () => won,
      );
      await f.coordinator.loadInitial();
      for (var n = 1; n <= 7; n++) {
        await f.coordinator.maintainWindow();
        final ready = await f.coordinator.ensureLevel(f.coordinator.current!.manifest.entry(content.levelId(n))!);
        expect(ready.level.levelId, content.levelId(n));
        won = wonUpTo(n);
      }
      await f.coordinator.maintainWindow();
      online = false;

      // A new launch, offline, same disk.
      final offline = fixtureCoordinator(server: content.server(online: () => false), bundle: content.starter(), store: store, completed: () => won);
      final snapshot = await offline.coordinator.loadInitial();
      for (var n = 1; n <= 12; n++) {
        final ready = await offline.coordinator.ensureLevel(snapshot.manifest.entry(content.levelId(n))!);
        expect(ready.level.levelId, content.levelId(n), reason: 'level $n offline');
        expect(ready.snapshot.isReady(content.levelId(n)), isTrue);
      }
      expect(offline.downloads.networkRequests, 0);
    });

    test('across a version switch: changed levels replay offline from their old files until the new ones are cached', () async {
      final store = MemoryContentStore();
      var won = wonUpTo(7);
      // Version 1: levels 1-7 played and won, window 8-12 cached.
      final v1 = fixtureCoordinator(server: content.server(), bundle: content.starter(), store: store, completed: () => won);
      await v1.coordinator.loadInitial();
      for (var n = 1; n <= 7; n++) {
        await v1.coordinator.ensureLevel(v1.coordinator.current!.manifest.entry(content.levelId(n))!);
      }
      await v1.coordinator.maintainWindow();
      await v1.coordinator.dispose();

      // Version 2 changes levels 2, 3 (won) and 9 (in the window) and adds a symbol.
      final v2 = FixtureContent(version: '2026.2.1.1', titles: {2: 'Glade Two', 3: 'Glade Three', 9: 'Glade Nine'}, extraSymbols: 1);
      final log = <String>[];
      final update = fixtureCoordinator(server: v2.server(log: log), bundle: content.starter(), store: store, completed: () => won);
      await update.coordinator.loadInitial();
      expect(await update.coordinator.refresh(), ContentSyncStatus.updated);
      expect(levelFiles(log), {v2.levelPaths[9]}, reason: 'only the window\'s changed level, not the won ones');

      // Offline from now on: every won level still opens.
      final offline = fixtureCoordinator(server: v2.server(online: () => false), bundle: content.starter(), store: store, completed: () => won);
      final snapshot = await offline.coordinator.loadInitial();
      expect(snapshot.contentVersion, '2026.2.1.1');
      for (var n = 1; n <= 12; n++) {
        final ready = await offline.coordinator.ensureLevel(snapshot.manifest.entry(content.levelId(n))!);
        expect(ready.level.levelId, content.levelId(n), reason: 'level $n');
        final changed = n == 2 || n == 3;
        expect(ready.entry.ref.url, changed ? content.levelPaths[n] : v2.levelPaths[n], reason: 'level $n file');
        expect(ready.level.title, changed ? 'Glade $n' : (n == 9 ? 'Glade Nine' : 'Glade $n'));
      }
      expect(offline.downloads.networkRequests, 0);

      // Back online: replaying level 2 fetches its new file, which then wins over the old one.
      final online = fixtureCoordinator(server: v2.server(), bundle: content.starter(), store: store, completed: () => won);
      final current = await online.coordinator.loadInitial();
      final replay = await online.coordinator.ensureLevel(current.manifest.entry(content.levelId(2))!);
      expect(replay.level.title, 'Glade Two');
      expect(replay.entry.ref.url, v2.levelPaths[2]);
    });

    test('a level that is not on the device, offline: a transient error (the app asks for the internet)', () async {
      final f = fixtureCoordinator(server: content.server(online: () => false), bundle: content.starter());
      final snapshot = await f.coordinator.loadInitial();
      final error = await f.coordinator
          .ensureLevel(snapshot.manifest.entry(content.levelId(9))!)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<ContentException>().having((e) => e.isTransient, 'transient', isTrue));
      expect(snapshot.levelErrors, isEmpty, reason: 'a missing connection is not a broken level');
    });
  });

  group('version updates', () {
    // An older app bundle without levels: the window must come from R2.
    final oldBundle = FixtureContent(version: '2026.1.1.0').starter(count: 0);

    test('a newer manifest becomes active only once its window is cached', () async {
      final store = MemoryContentStore();
      final missing = content.artOf([4]).first;
      final broken = fixtureCoordinator(
        server: content.server(overrides: {missing: http.Response('gone', 404)}),
        bundle: oldBundle,
        store: store,
        seed: false,
      );
      final before = await broken.coordinator.loadInitial();
      expect(await broken.coordinator.refresh(), ContentSyncStatus.rejected);
      expect(broken.coordinator.current, same(before));
      expect(await ContentCache(store).readKnownGood(), isNull);

      // The connection drops half-way: still the old version.
      var requests = 0;
      var online = true;
      final flaky = fixtureCoordinator(
        server: content.server(online: () => online && requests++ < 6),
        bundle: oldBundle,
        store: store,
        seed: false,
      );
      await flaky.coordinator.loadInitial();
      expect(await flaky.coordinator.refresh(), ContentSyncStatus.offline);
      expect(flaky.coordinator.current!.contentVersion, '2026.1.1.0');
      expect(await ContentCache(store).readKnownGood(), isNull);

      requests = -1000;
      expect(await flaky.coordinator.refresh(), ContentSyncStatus.updated);
      expect(flaky.coordinator.current!.contentVersion, '2026.1.1.1');
      for (var n = 1; n <= 5; n++) {
        expect(flaky.coordinator.current!.isReady(content.levelId(n)), isTrue);
      }
      expect((await ContentCache(store).readKnownGood())!.contentVersion, '2026.1.1.1');
      online = false;
    });

    test('an older remote version is refused (no downgrade)', () async {
      final log = <String>[];
      final older = FixtureContent(version: '2025.1.1.1', titles: {1: 'Old Glade'});
      final f = fixtureCoordinator(server: older.server(log: log), bundle: content.starter());
      final bundled = await f.coordinator.loadInitial();
      expect(await f.coordinator.refresh(), ContentSyncStatus.upToDate);
      expect(f.coordinator.current, same(bundled));
      expect(log, ['manifest.json']);
    });

    test('a broken level in the new window is left out; the update still applies', () async {
      final f = fixtureCoordinator(
        server: content.server(overrides: {content.levelPaths[3]!: http.Response(jsonEncode({'schemaVersion': 1}), 200)}),
        bundle: oldBundle,
        seed: false,
      );
      await f.coordinator.loadInitial();
      // The checksum no longer matches, so the level is rejected as content.
      expect(await f.coordinator.refresh(), ContentSyncStatus.updated);
      expect(f.coordinator.current!.levelErrors.keys, [content.levelId(3)]);
      expect(f.coordinator.current!.playableEntries.map((e) => e.order), isNot(contains(3)));
    });
  });
}

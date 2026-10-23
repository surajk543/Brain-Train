/// A small key-value store in the player's own cloud account, so progress
/// survives a reinstall (owner, 2026-10-23): iCloud key-value storage on iOS
/// (`icloud_store.dart`). Android has none here: Google's automatic backup
/// restores the app's preferences instead (`android/app/src/main/res/xml/`).
/// Pure Dart; nothing here is on the startup path.
library;

abstract class CloudStore {
  /// The value stored under [key], or null when there is none or the store
  /// cannot be read. Never throws.
  Future<String?> read(String key);

  /// Stores [value] under [key]; false when it could not be written. Never
  /// throws.
  Future<bool> write(String key, String value);

  /// Fires when the values changed from outside this app run: the first sync
  /// after an install, or another device on the same account.
  Stream<void> get changes;
}

/// Where there is no cloud store (Android, tests, desktop): holds nothing.
class UnavailableCloudStore implements CloudStore {
  const UnavailableCloudStore();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<bool> write(String key, String value) async => false;

  @override
  Stream<void> get changes => const Stream.empty();
}

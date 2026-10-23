import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cloud_store.dart';

/// [CloudStore] on iCloud key-value storage (`NSUbiquitousKeyValueStore`,
/// the `brain_train/cloud` channel in `AppDelegate.swift`): the player's own
/// iCloud account, no sign-in, up to 1 MB. Without iCloud (signed out,
/// turned off for the app) the values stay on the device. Every call is
/// caught and timed out.
class ICloudStore implements CloudStore {
  ICloudStore({this.channel = const MethodChannel('brain_train/cloud'), this.timeout = const Duration(seconds: 5)}) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _changes.add(null);
    });
  }

  final MethodChannel channel;
  final Duration timeout;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<String?> read(String key) async {
    try {
      return await channel.invokeMethod<String>('read', {'key': key}).timeout(timeout);
    } on Object catch (error) {
      debugPrint('Cloud save: read failed ($error)');
      return null;
    }
  }

  @override
  Future<bool> write(String key, String value) async {
    try {
      return await channel.invokeMethod<bool>('write', {'key': key, 'value': value}).timeout(timeout) ?? false;
    } on Object catch (error) {
      debugPrint('Cloud save: write failed ($error)');
      return false;
    }
  }

  @override
  Stream<void> get changes => _changes.stream;
}

/// iCloud on iOS, else [UnavailableCloudStore].
CloudStore createCloudStore() => Platform.isIOS ? ICloudStore() : const UnavailableCloudStore();

import 'package:shared_preferences/shared_preferences.dart';

/// The last good app update notice (its JSON), kept on the device so a
/// required update still applies when the notice cannot be fetched.
class AppUpdateCache {
  AppUpdateCache(this._prefs);

  static Future<AppUpdateCache> open() async => AppUpdateCache(await SharedPreferences.getInstance());

  static const String key = 'appUpdate.notice.v1';

  final SharedPreferences _prefs;

  /// The stored notice, or null (none yet, or unreadable).
  String? read() {
    try {
      return _prefs.getString(key);
    } on Object {
      return null;
    }
  }

  /// Stores [json], or forgets the notice when null.
  Future<void> write(String? json) async {
    try {
      if (json == null) {
        await _prefs.remove(key);
      } else {
        await _prefs.setString(key, json);
      }
    } on Object {
      // Not kept: the next check fetches it again.
    }
  }
}
